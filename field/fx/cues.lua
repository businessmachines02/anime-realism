-- Field battle — arFieldCue → grid steps + cast anims.
--
-- Physical attacks step in toward the foe (or jump over cover); specials
-- cast in place with attacker→foe projectiles. Hits may knock the target
-- back one cell. Self-hits (confusion / recoil / crash) stumble in place.
-- Two-turn vanish moves (Dig / Fly) burrow or soar out of sight on the
-- charge turn and emerge on the release strike.
-- With CLOSE THE GAP, physicals walk to the foe before the punch; engine
-- damage waits for that same arrival beat (gait from Speed, Attack boost, cap).
-- Cue dedupe prevents double-steps when multiple battle
-- events fire for the same move beat.
-- Multi-hit physicals (Pin Missile, Double Kick, Fury Attack, …) keep
-- the first FIELD swing, then replay contact/cast FX on each extra
-- engine anim row so landed hits stay readable.

-- Cue kinds register via Cues.register(kind, handler). Cues.apply keeps the
-- existing signature and dispatches the table. Add a kind here instead of
-- growing the old if-chain.

local Cues = {}
Cues._Log = nil

local function note(session, battle, tag, ...)
  local Log = (session and session._deps and session._deps.Log) or Cues._Log
  if not (Log and type(Log.note) == "function") then
    return
  end
  pcall(Log.note, battle or (session and session._battle), tag, ...)
end

local function noteErr(session, battle, tag, err)
  local Log = (session and session._deps and session._deps.Log) or Cues._Log
  if not (Log and type(Log.err) == "function") then
    return
  end
  pcall(Log.err, battle or (session and session._battle), tag, err)
end

-- Gen1 semi-invulnerable charge moves → field vanish flavor.
Cues.VANISH_MOVES = {
  DIG = "dig",
  FLY = "fly",
}

-- Named Gen1 (and later) multi-strike moves. Engine `move.multiHit`
-- wins when the record is present; this table covers anim-row ids.
Cues.MULTI_HIT_MOVES = {
  DOUBLE_KICK = true,
  TWINEEDLE = true,
  PIN_MISSILE = true,
  COMET_PUNCH = true,
  FURY_ATTACK = true,
  FURY_SWIPES = true,
  SPIKE_CANNON = true,
  BARRAGE = true,
  DOUBLE_SLAP = true,
  DOUBLESLAP = true,
  BONEMERANG = true,
  ICICLE_SPEAR = true,
  BULLET_SEED = true,
  ARM_THRUST = true,
  BONE_RUSH = true,
  ROCK_BLAST = true,
}

function Cues.isMultiHitMove(moveOrId)
  if type(moveOrId) == "table" then
    local mh = moveOrId.multiHit
    if type(mh) == "number" then
      return mh > 1
    end
    if type(mh) == "table" and #mh > 0 then
      return true
    end
    return Cues.isMultiHitMove(moveOrId.id)
  end
  local id = tostring(moveOrId or ""):upper():gsub("%s+", "_")
  return Cues.MULTI_HIT_MOVES[id] == true
end

-- Engine specials use a *_ANIM id; move strikes use the move id.
function Cues.isEngineMoveAnim(anim)
  if not anim then
    return false
  end
  local id = tostring(anim):upper()
  if id == "" or id:find("_ANIM$", 1) then
    return false
  end
  return true
end

local function now(session)
  if session and session._now ~= nil then
    return session._now
  end
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return 0
end

local function rr(...)
  local random = (love and love.math and love.math.random) or math.random
  return random(...)
end

local function isExitPlaying(ent)
  if not ent then
    return false
  end
  return ent._fainting == true
      or ent._faintDone == true
      or ent._recallDone == true
      or ent.anim == "recall"
      or ent.anim == "faint"
end

local function foeOf(session, side)
  if side == "player" then
    return session.enemyMon
  end
  return session.playerMon
end

local function normCategory(cat)
  cat = tostring(cat or ""):lower()
  if cat == "special" or cat == "sp" then
    return "special"
  end
  if cat == "physical" or cat == "phys" then
    return "physical"
  end
  return nil
end

function Cues.vanishKind(moveId)
  if not moveId then
    return nil
  end
  return Cues.VANISH_MOVES[tostring(moveId):upper()]
end

-- Walk-in / close-the-gap: contact FX and physicals. Travel FX and
-- non-contact specials cast in place. Bite / Fire Punch stay melee even
-- when Damage.isSpecial(type) is true.
function Cues.isMeleeAttack(opts, Projectiles)
  opts = opts or {}
  if Projectiles and type(Projectiles.isTravelFx) == "function"
      and Projectiles.isTravelFx(opts) then
    return false
  end
  if Projectiles and type(Projectiles.isContactFx) == "function"
      and Projectiles.isContactFx(opts) then
    return true
  end
  return normCategory(opts.category) ~= "special"
end

local function battlerChargingVanish(battler)
  if not battler then
    return nil
  end
  if battler.invulnerable then
    local charging = battler.charging
    local id = type(charging) == "table" and charging.id or charging
    return Cues.vanishKind(id) or "dig"
  end
  return nil
end

local function isChargeTurn(ent, moveId)
  local kind = Cues.vanishKind(moveId)
  if not kind then
    return false, nil
  end
  local battler = ent and ent._battleBattler
  if battler and (battler.invulnerable or battler.charging) then
    return true, battlerChargingVanish(battler) or kind
  end
  return false, kind
end

function Cues.closeTheGapEnabled(session, opts)
  if opts and opts.closeTheGap ~= nil then
    return opts.closeTheGap == true
  end
  local mod = session and session._mod
  if mod and mod.options and type(mod.options.get) == "function" then
    return mod.options:get("close_the_gap") ~= false
  end
  if session and session.closeTheGap ~= nil then
    return session.closeTheGap == true
  end
  return true
end

--- Dash px/s: slower base Speed walks slower; Attack adds a boost; hard cap.
function Cues.closeGapSpeed(ent, battle, side)
  local spe, atk = 70, 70
  local stats = ent and ent._closeGapStats
  if type(stats) ~= "table" then
    local battler = nil
    if battle then
      battler = (side == "player") and battle.player or battle.enemy
    end
    if not battler and ent then
      battler = ent._battleBattler
    end
    local mon = battler and battler.mon
    local def = mon and (mon.pokemon or mon.def)
    if type(def) == "table" and type(def.baseStats) == "table" then
      stats = def.baseStats
    elseif battler and type(battler.stats) == "table" then
      stats = battler.stats
    elseif mon and type(mon.stats) == "table" then
      stats = mon.stats
    end
  end
  if type(stats) == "table" then
    spe = tonumber(stats.speed or stats.spe) or spe
    atk = tonumber(stats.attack or stats.atk) or atk
  end
  -- Battle stats are often ~2× base; compress so gait still reads as species.
  if spe > 140 or atk > 160 then
    spe = spe * 0.45
    atk = atk * 0.45
  end
  local speedU = math.max(0, math.min(1, spe / 120))
  local atkU = math.max(0, math.min(1, (atk - 40) / 100))
  local gait = 26 + 54 * speedU   -- Raise base gait & speed scaling for faster minimums
  local boost = 1 + 0.4 * atkU
  local px = gait * boost
  if px < 28 then                  -- Raise the minimum a bit from 22 to 28
    px = 28
  elseif px > 86 then
    px = 86
  end
  return px
end

local function restoreStepSpeed(ent)
  if not ent then
    return
  end
  if ent._savedStepSpeed ~= nil then
    ent.stepSpeed = ent._savedStepSpeed
    ent._savedStepSpeed = nil
  else
    ent.stepSpeed = nil
  end
end

local function markPresented(session, side, mid)
  if not (session and side and mid) then
    return
  end
  session._presentedMove = session._presentedMove or {}
  local set = session._presentedMove[side]
  if type(set) ~= "table" then
    local prev = (type(set) == "string") and set or nil
    set = {}
    if prev then
      set[prev] = true
    end
    session._presentedMove[side] = set
  end
  set[mid] = true
end

local function wasPresented(session, side, mid)
  if not (session and side and mid) then
    return false
  end
  local set = session._presentedMove and session._presentedMove[side]
  if type(set) == "string" then
    return set == mid
  end
  return type(set) == "table" and set[mid] == true
end

local function markStruck(ent, mid)
  if not (ent and mid) then
    return
  end
  ent._struckMoves = ent._struckMoves or {}
  ent._struckMoves[mid] = true
  ent._closeStruckMoveId = mid
end

local function cueMoveId(opts)
  local mid = opts and opts.moveId and tostring(opts.moveId):upper() or nil
  if mid == "" then
    return nil
  end
  return mid
end

local function cueForce(opts)
  opts = opts or {}
  if opts.releaseStrike then
    return "release"
  end
  if opts.again then
    return "again"
  end
  if opts.isCalled then
    return "called"
  end
  if opts.followUp then
    return "follow"
  end
  if opts.multiHit then
    return "multi"
  end
  return nil
end

local function padSnap(ent)
  if not ent then
    return "nil"
  end
  local px = (type(ent.basePx) == "number") and "Y" or "N"
  return tostring(ent.padU) .. "," .. tostring(ent.padV) .. " px=" .. px
end

local function wasStruck(ent, mid)
  if not (ent and mid) then
    return false
  end
  if ent._closeStruckMoveId == mid then
    return true
  end
  return ent._struckMoves and ent._struckMoves[mid] == true
end

function Cues.awaitingReact(battle)
  return battle and battle._arAwaitingReact == true
end

local function fieldMenuOpen(battle)
  if Cues.awaitingReact(battle) then
    return true
  end
  local stack = battle and battle.game and battle.game.stack
  if not (stack and type(stack.top) == "function") then
    return false
  end
  local top = stack:top()
  return top ~= nil and top ~= battle
end

local function hasStruckThisTurn(ent)
  if not ent then
    return false
  end
  if ent._closeStruckMoveId then
    return true
  end
  local struck = ent._struckMoves
  return type(struck) == "table" and next(struck) ~= nil
end

local function playMeleeContact(session, side, ent, opts, jump)
  opts = opts or {}
  local deps = session and session._deps
  local Projectiles = deps and deps.Projectiles
  local Audio = deps and deps.Audio
  local battle = session and session._battle
  if Projectiles and type(Projectiles.contact) == "function" then
    Projectiles.contact(session, side, {
      moveType = opts.moveType,
      moveId = opts.moveId,
    })
  end
  if Audio and type(Audio.playMove) == "function" then
    pcall(Audio.playMove, battle, opts.moveId, side == "player")
  end
  if type(ent.play) == "function" then
    ent:play((jump or ent._attackJump) and "jump" or "attack")
  end
  local mid = opts.moveId and tostring(opts.moveId):upper() or nil
  if mid and mid ~= "" then
    markStruck(ent, mid)
  end
  ent._returnAt = now(session) + 0.42
  ent._withdrawAfterStrike = true
end

--- Walk feet, not draw offsets / occupancy destination.
local function walkPx(ent)
  if not ent then
    return nil, nil
  end
  local x = ent.basePx
  local y = ent.basePy
  if type(x) ~= "number" then
    x = ent.px
    y = ent.py
  end
  return x, y
end

--- True while occupancy has jumped ahead and the sprite is still lerping.
function Cues.stillWalkingToPad(ent)
  if not ent or type(ent.targetPx) ~= "number" then
    return false
  end
  local x, y = walkPx(ent)
  if type(x) ~= "number" then
    return false
  end
  local dx = ent.targetPx - x
  local dy = (ent.targetPy or 0) - (y or 0)
  return (dx * dx + dy * dy) > 8 * 8
end

--- True when the sprite is within one tile of the foe (pixel reach).
--- Never use targetPx: closeGap writes that to the adjacent cell immediately.
function Cues.inMeleeReach(ent, foe)
  if not (ent and foe) then
    return false
  end
  if Cues.stillWalkingToPad(ent) then
    return false
  end
  local ax, ay = walkPx(ent)
  local fx, fy = walkPx(foe)
  if type(ax) == "number" and type(fx) == "number" then
    local dx = fx - ax
    local dy = (fy or 0) - (ay or 0)
    -- One pad tile is 16px; a little slack so the punch lunge connects.
    return (dx * dx + dy * dy) <= 18 * 18
  end
  return false
end

local function num(v)
  if type(v) ~= "number" then
    return "-"
  end
  return string.format("%.0f", v)
end

local function occKey(session, ent)
  local occ = session and session.grid and session.grid.occ
  if not (occ and ent and ent.id) then
    return "-"
  end
  for k, id in pairs(occ) do
    if id == ent.id then
      return tostring(k)
    end
  end
  return "none"
end

local function describeEnt(session, ent, label)
  if not ent then
    return label .. "=nil"
  end
  local pend = ent._pendingCloseStrike
  local pendId = "-"
  if type(pend) == "table" then
    pendId = tostring(pend.moveId or "Y")
  end
  return string.format(
    "%s u=%s,v=%s px=%s,%s tgt=%s,%s walk=%s anim=%s pend=%s struck=%s occ=%s",
    label,
    tostring(ent.padU), tostring(ent.padV),
    num(ent.basePx or ent.px), num(ent.basePy or ent.py),
    num(ent.targetPx), num(ent.targetPy),
    Cues.stillWalkingToPad(ent) and "Y" or "N",
    tostring(ent.anim or "-"),
    pendId,
    hasStruckThisTurn(ent) and "Y" or "N",
    occKey(session, ent))
end

--- Pad / pixel / walk / pending snapshot for crash trails.
function Cues.describeField(session)
  if not session then
    return "you=nil", "foe=nil", "dist=-"
  end
  local dist = "-"
  local Grid = session._deps and session._deps.Grid
  if Grid and type(Grid.padDistance) == "function"
      and session.playerMon and session.enemyMon then
    dist = tostring(Grid.padDistance(session.grid, session.playerMon, session.enemyMon) or "-")
  end
  return describeEnt(session, session.playerMon, "you"),
    describeEnt(session, session.enemyMon, "foe"),
    "dist=" .. dist
end

function Cues.notePos(session, battle, tag)
  tag = tag or "pos"
  local ok, you, foe, dist = pcall(Cues.describeField, session)
  if not ok then
    return
  end
  note(session, battle, tag, you)
  note(session, battle, tag, foe, dist)
end

--- damage_dealt often fires while CLOSE THE GAP is still walking (applyDamage
--- reports the hit so the engine can continue). Hold the FIELD shove until
--- the punch, or Body Slam etc. never push.
function Cues.holdCloseHit(session, side, opts)
  if not (session and side) then
    return false
  end
  session._pendingCloseHit = { side = side, opts = type(opts) == "table" and opts or {} }
  return true
end

function Cues.flushCloseHit(session, Grid)
  local hit = session and session._pendingCloseHit
  if not hit then
    return false
  end
  session._pendingCloseHit = nil
  Grid = Grid or (session._deps and session._deps.Grid)
  if not (hit.side and Grid) then
    return false
  end
  return Cues.apply(session, hit.side, "hit", Grid, nil, session._battle, hit.opts or {})
      and true or false
end

local function fireCloseStrike(session, side, ent, Grid)
  if not ent then
    return
  end
  local pending = ent._pendingCloseStrike
  local mid = pending and pending.moveId and tostring(pending.moveId):upper() or nil
  if mid == "" then
    mid = nil
  end
  local foe = foeOf(session, side)
  local dist = "-"
  local G = Grid or (session and session._deps and session._deps.Grid)
  if foe and G and type(G.padDistance) == "function" then
    dist = tostring(G.padDistance(session.grid, ent, foe) or "-")
  end
  note(session, session and session._battle, "closeStrike", side, mid,
    "dist=" .. dist, describeEnt(session, ent, side))
  if mid then
    markStruck(ent, mid)
  end
  ent._pendingCloseStrike = nil
  ent._closeStrikeDeadline = nil
  ent._closeStrikeWait = nil
  ent._closeStrikeArmedAt = nil
  local deps = session and session._deps
  local Projectiles = deps and deps.Projectiles
  local Audio = deps and deps.Audio
  local battle = session and session._battle
  if pending and Audio and type(Audio.playMove) == "function" then
    pcall(Audio.playMove, battle, pending.moveId, side == "player")
  end
  if pending and Projectiles and type(Projectiles.contact) == "function" then
    Projectiles.contact(session, side, pending)
  end
  local jump = (pending and pending.jump) or ent._attackJump
  if type(ent.play) == "function" then
    ent:play(jump and "jump" or "attack")
  end
  local punch = jump and 0.56 or 0.48
  ent._returnAt = now(session) + punch
  -- Shove now that occupancy is adjacent. damage_dealt during the walk
  -- was stashed; a replay after this is skipped by shouldSkipEvent.
  Cues.flushCloseHit(session, Grid)
  Cues.flushHeldHit(session, battle)
end

--- True while CLOSE THE GAP still owns the physical beat.
function Cues.closeGapHoldActive(session)
  if not (session and session.live) then
    return false
  end
  local battle = session._battle
  if Cues.awaitingReact(battle) then
    return true
  end
  if not Cues.closeTheGapEnabled(session) then
    return false
  end
  local p, e = session.playerMon, session.enemyMon
  return (p and p._pendingCloseStrike) or (e and e._pendingCloseStrike) or false
end

--- Park updateQueue during the walk so Harden cannot start — except while
--- REACT is waiting. That menu is a queue `ui` row; parking it deadlocks
--- (punch waits for the menu, menu waits for the queue).
function Cues.shouldParkEngineQueue(session)
  if not (session and session.live) then
    return false
  end
  local battle = session._battle
  if battle and battle._arCloseGapResuming then
    return false
  end
  if Cues.awaitingReact(battle) then
    return false
  end
  local p, e = session.playerMon, session.enemyMon
  return (p and p._pendingCloseStrike) or (e and e._pendingCloseStrike) or false
end

--- Drop a close-the-gap walk without punching (REACT dodge miss / cancelled hit).
function Cues.cancelCloseStrike(session, side, Grid)
  local ent = (side == "player") and (session and session.playerMon)
      or (session and session.enemyMon)
  if not ent or not ent._pendingCloseStrike then
    return false
  end
  ent._pendingCloseStrike = nil
  ent._closeStrikeDeadline = nil
  ent._closeStrikeWait = nil
  ent._closeStrikeArmedAt = nil
  restoreStepSpeed(ent)
  ent._withdrawAfterStrike = true
  ent._returnAt = now(session)
  return true
end

--- A close-gap walk that leaked into the next turn (foe Harden while
--- Scratch was still walking). Punch if already adjacent, else cancel
--- and flush the held HP so the next swing starts clean.
function Cues.settleOrphanCloseGap(session, battle, Grid)
  if not (session and session.live) then
    return false
  end
  Grid = Grid or (session._deps and session._deps.Grid)
  local settled = false
  for _, side in ipairs({ "player", "enemy" }) do
    local ent = (side == "player") and session.playerMon or session.enemyMon
    if ent and ent._pendingCloseStrike then
      local mid = ent._pendingCloseStrike.moveId
      local foe = foeOf(session, side)
      local punch = Cues.inMeleeReach(ent, foe)
      note(session, battle, "settleGap", side, mid or "-",
        punch and "punch" or "cancel", padSnap(ent))
      if punch then
        fireCloseStrike(session, side, ent, Grid)
      else
        Cues.cancelCloseStrike(session, side, Grid)
      end
      settled = true
    end
  end
  if settled then
    Cues.flushHeldHit(session, battle)
  end
  return settled
end

--- Drop leftover close-gap punch clocks at turn start. Keep melee home /
--- `_meleeAnchor` so idle roam does not bounce back to the opening cell.
function Cues.resetTurnSide(session, side, keep, _)
  local ent = (side == "player") and (session and session.playerMon)
      or (session and session.enemyMon)
  if not ent or keep then
    return false
  end
  ent._pendingCloseStrike = nil
  ent._closeStrikeDeadline = nil
  ent._closeStrikeWait = nil
  ent._closeStrikeArmedAt = nil
  ent._closeStruckMoveId = nil
  ent._struckMoves = nil
  restoreStepSpeed(ent)
  ent._returnAt = nil
  ent._withdrawAfterStrike = nil
  return true
end

--- True while a physical closer is still walking; engine damage must wait.
function Cues.shouldHoldEngineHit(session, ctx)
  if not Cues.closeGapHoldActive(session) then
    return false
  end
  local user = ctx and ctx.user
  if not user then
    return true
  end
  local side = user.isPlayer and "player" or "enemy"
  local ent = (side == "player") and session.playerMon or session.enemyMon
  return ent and ent._pendingCloseStrike and true or false
end

--- Normalize one held `{ ctx, record }` or a list of them.
local function heldRunList(held)
  if type(held) ~= "table" then
    return nil
  end
  if held.ctx then
    return { held }
  end
  if #held > 0 then
    return held
  end
  return nil
end

--- Resume engine HP / hit that waited for the close-the-gap punch.
function Cues.flushHeldHit(session, battle)
  if not battle then
    return false
  end
  local p, e = session and session.playerMon, session and session.enemyMon
  if (p and p._pendingCloseStrike) or (e and e._pendingCloseStrike) then
    return false
  end
  local runs = heldRunList(battle._arCloseGapDamage)
  local stashed = battle._arCloseGapApply
  if not runs and (type(stashed) ~= "table" or #stashed == 0) then
    return false
  end
  battle._arCloseGapDamage = nil
  battle._arCloseGapApply = nil
  -- Punch already applied this when Grid was available. If not, shove
  -- before HP replay so a second damage_dealt cannot double-push.
  Cues.flushCloseHit(session, session._deps and session._deps.Grid)
  battle._arCloseGapResuming = true
  local replayedRun = runs and true or false
  note(session, battle, "flushHeldHit", replayedRun and "runDamaging" or "applyDamage")
  if replayedRun then
    -- Resume the engine (or close-gap's orig), never the live React wrap.
    -- Calling EffectRegistry.runDamaging here re-entered AUTO counter / Again!
    -- after FURY_ATTACK and armed a second closeStrike.
    local okE, registry = pcall(require, "src.battle.EffectRegistry")
    local react = okE and registry and registry._arReactRunDamaging
    local function usable(fn)
      return type(fn) == "function" and fn ~= react
    end
    local run = okE and registry and (
      (usable(registry._arEngineRunDamaging) and registry._arEngineRunDamaging)
      or (usable(registry._arVanillaRunDamaging) and registry._arVanillaRunDamaging)
    )
    if type(run) == "function" then
      for i = 1, #runs do
        local held = runs[i]
        if type(held) == "table" and held.ctx then
          local okR, errR = pcall(run, battle, held.ctx, held.record)
          if not okR then
            noteErr(session, battle, "flushHeldHit.runDamaging", errR)
          end
        end
      end
    end
  elseif type(stashed) == "table" and type(battle.applyDamage) == "function" then
    for i = 1, #stashed do
      local args = stashed[i]
      if type(args) == "table" then
        local okA, errA = pcall(battle.applyDamage, battle, unpack(args))
        if not okA then
          noteErr(session, battle, "flushHeldHit.applyDamage", errA)
        end
      end
    end
    -- applyDamage alone does not run the engine faint script.
    local function down(b)
      if not b then
        return false
      end
      local hp = (b.mon and b.mon.hp) or b.hp
      return type(hp) == "number" and hp <= 0
    end
    if type(battle.onFaint) == "function" then
      if down(battle.player) then
        pcall(battle.onFaint, battle, battle.player)
      end
      if down(battle.enemy) then
        pcall(battle.onFaint, battle, battle.enemy)
      end
    end
  end
  battle._arCloseGapResuming = nil
  -- Sticky FIELD diamond must not cover faint / send-out.
  local function down(b)
    if not b then
      return false
    end
    local hp = (b.mon and b.mon.hp) or b.hp
    local shown = b.shownHP
    return (type(hp) == "number" and hp <= 0)
        or (type(shown) == "number" and shown <= 0)
  end
  if down(battle.player) or down(battle.enemy) then
    battle._arFieldPreferMoves = nil
    battle._arFieldCommandHold = true
    if battle.phase == "moveSelect" or battle.phase == "mimicSelect" then
      battle.phase = down(battle.player) and "menu" or "messages"
    end
  end
  return true
end

local HANDLERS = {}

function Cues.register(kind, handler)
  if type(kind) ~= "string" or kind == "" or type(handler) ~= "function" then
    return Cues
  end
  HANDLERS[kind] = handler
  return Cues
end

Cues.register("dodge", function(session, side, kind, Grid, nudgeCamera, battle, opts)
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return false
  end
  opts = opts or {}
  local foe = foeOf(session, side)
  local g = session.grid
  local category = normCategory(opts.category)

    Grid.dodge(g, ent, foe)
    if type(ent.play) == "function" then
      ent:play("dodge")
    end
    return true
end)

Cues.register("cover", function(session, side, kind, Grid, nudgeCamera, battle, opts)
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return false
  end
  opts = opts or {}
  local foe = foeOf(session, side)
  local g = session.grid
  local category = normCategory(opts.category)

    local tucked = false
    if type(Grid.seekCover) == "function" then
      tucked = Grid.seekCover(g, ent, foe) == true
    end
    if not tucked and type(Grid.seekWallCover) == "function" then
      tucked = Grid.seekWallCover(g, ent, foe) == true
    end
    if tucked then
      if type(ent.play) == "function" then
        ent:play("cover")
      end
    else
      Grid.dodge(g, ent, foe)
      if type(ent.play) == "function" then
        ent:play("dodge")
      end
    end
    return true
end)

Cues.register("hide", HANDLERS["cover"])

Cues.register("brace", function(session, side, kind, Grid, nudgeCamera, battle, opts)
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return false
  end
  opts = opts or {}
  local foe = foeOf(session, side)
  local g = session.grid
  local category = normCategory(opts.category)

    if type(ent.play) == "function" then
      ent:play("brace")
    end
    return true
end)

Cues.register("status", function(session, side, kind, Grid, nudgeCamera, battle, opts)
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return false
  end
  opts = opts or {}
  local foe = foeOf(session, side)
  local g = session.grid
  local category = normCategory(opts.category)

    local Projectiles = session._deps and session._deps.Projectiles
    local Audio = session._deps and session._deps.Audio
    if Audio and type(Audio.playMove) == "function" then
      pcall(Audio.playMove, battle or session._battle, opts.moveId,
        side == "player")
    end
    if Projectiles and type(Projectiles.status) == "function" then
      Projectiles.status(session, side, opts)
    end
    if type(ent.play) == "function" then
      ent:play("cast")
    end
    return true
end)

Cues.register("vanish", function(session, side, kind, Grid, nudgeCamera, battle, opts)
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return false
  end
  opts = opts or {}
  local foe = foeOf(session, side)
  local g = session.grid
  local category = normCategory(opts.category)

    local flavor = opts.vanish or Cues.vanishKind(opts.moveId) or "dig"
    ent._vanishKind = flavor
    ent._fieldVanished = nil
    ent._emerging = nil
    ent._pendingReleaseAttack = nil
    ent._returnAt = nil
    ent._arFieldDetached = nil
    ent.hidden = false
    local Projectiles = session._deps and session._deps.Projectiles
    if Projectiles and type(Projectiles.vanish) == "function" then
      Projectiles.vanish(session, side, flavor)
    end
    if type(ent.play) == "function" then
      ent:play(flavor == "fly" and "vanish_fly" or "vanish_dig")
    end
    return true
end)

Cues.register("emerge", function(session, side, kind, Grid, nudgeCamera, battle, opts)
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return false
  end
  opts = opts or {}
  local foe = foeOf(session, side)
  local g = session.grid
  local category = normCategory(opts.category)

    local flavor = opts.vanish or ent._vanishKind
      or Cues.vanishKind(opts.moveId) or "dig"
    ent._vanishKind = flavor
    ent._emerging = true
    ent._arFieldDetached = nil
    ent.hidden = false
    ent.drawScale = ent.drawScale or 1
    local Projectiles = session._deps and session._deps.Projectiles
    if Projectiles and type(Projectiles.emerge) == "function" then
      Projectiles.emerge(session, side, flavor)
    end
    if type(ent.play) == "function" then
      ent:play(flavor == "fly" and "emerge_fly" or "emerge_dig")
    end
    return true
end)

Cues.register("attack", function(session, side, kind, Grid, nudgeCamera, battle, opts)
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return false
  end
  opts = opts or {}
  local foe = foeOf(session, side)
  local g = session.grid
  local category = normCategory(opts.category)

    -- Dig / Fly charge turn: disappear instead of striking.
    if not opts.releaseStrike then
      local charging, flavor = isChargeTurn(ent, opts.moveId)
      if charging then
        return Cues.apply(session, side, "vanish", Grid, nudgeCamera, battle, {
          vanish = flavor,
          moveId = opts.moveId,
          moveType = opts.moveType,
        })
      end
      -- Release strike while still hidden: emerge, then strike shortly after.
      if (ent._fieldVanished or ent.hidden) and Cues.vanishKind(opts.moveId) then
        ent._pendingReleaseAttack = {
          category = category,
          moveType = opts.moveType,
          moveId = opts.moveId,
        }
        ent._releaseAt = now(session) + 0.28
        return Cues.apply(session, side, "emerge", Grid, nudgeCamera, battle, {
          vanish = ent._vanishKind or Cues.vanishKind(opts.moveId),
          moveId = opts.moveId,
        })
      end
    end
    if type(nudgeCamera) == "function" and battle then
      local foeSide = (side == "player") and "enemy" or "player"
      nudgeCamera(battle, foeSide, 0.45)
    end
    -- Physical: close distance on the pad, then return home.
    -- Special: hold cell; still play an in-place cast anim.
    local Projectiles = session._deps and session._deps.Projectiles
    local Audio = session._deps and session._deps.Audio
    -- Travel FX (beams, Night Shade, …) fly even when the Gen1 type split
    -- marks the move physical. Contact FX (Bite, Fire Punch) walk in even
    -- when that split marks them special.
    if not Cues.isMeleeAttack(opts, Projectiles) then
      note(session, battle or session._battle, "cue path", side,
        opts.moveId or "-", "cast", padSnap(ent))
      if Audio and type(Audio.playMove) == "function" then
        pcall(Audio.playMove, battle or session._battle, opts.moveId,
          side == "player")
      end
      ent._returnAt = nil
      ent._attackStepped = nil
      if Projectiles and type(Projectiles.move) == "function" then
        local jump = type(Grid.pathObstructed) == "function"
            and Grid.pathObstructed(g, ent, foe)
        Projectiles.move(session, side, {
          category = category or "special",
          jump = jump,
          moveType = opts.moveType,
          moveId = opts.moveId,
        })
      end
      if type(ent.play) == "function" then
        ent:play("cast")
      end
    else
      -- Extra swings (multi-hit, Again!, REACT counter after a punch, nameless
      -- toasts) stay in melee. One close-the-gap walk per side per turn.
      local thisId = opts.moveId and tostring(opts.moveId):upper() or nil
      if thisId == "" then
        thisId = nil
      end
      local inPlace = opts.followUp or opts.again
          or hasStruckThisTurn(ent) or (ent._pendingCloseStrike and true)
      if inPlace then
        local why = opts.followUp and "follow"
            or opts.again and "again"
            or hasStruckThisTurn(ent) and "struck"
            or "pending"
        note(session, battle or session._battle, "cue path", side, thisId or "-",
          "inPlace", why, padSnap(ent))
        playMeleeContact(session, side, ent, opts, ent._attackJump)
        return true
      end
      local delayStrike = Cues.closeTheGapEnabled(session, opts)
          and not opts.releaseStrike
      -- Physical: mon charges (optional close-the-gap, else one step / jump).
      -- Jump only when cover blocks the path — already-adjacent mons attack in place.
      local obstructed = type(Grid.pathObstructed) == "function"
          and Grid.pathObstructed(g, ent, foe)
      local jump = obstructed == true
      ent._attackJump = jump and true or nil
      local closed = false
      if Cues.closeTheGapEnabled(session, opts)
          and type(Grid.closeGap) == "function" then
        local okC, did = pcall(Grid.closeGap, g, ent, foe)
        if not okC then
          noteErr(session, battle, "cue.closeGap", did)
        else
          closed = did == true
        end
      end
      local stepped = closed
      if not stepped and type(Grid.attackStep) == "function" then
        local okS, didS = pcall(Grid.attackStep, g, ent, foe)
        if not okS then
          noteErr(session, battle, "cue.attackStep", didS)
        else
          stepped = didS == true
        end
      end
      ent._attackStepped = stepped
      -- CLOSE THE GAP owns the physical beat: the announce cue only starts
      -- the walk. Punch + engine damage wait until the sprite is in reach.
      if delayStrike then
        local speed = Cues.closeGapSpeed(ent, battle or session._battle, side)
        ent._savedStepSpeed = ent.stepSpeed
        ent.stepSpeed = speed
        ent._pendingCloseStrike = {
          moveType = opts.moveType,
          moveId = thisId,
          movePower = opts.movePower,
          jump = jump,
        }
        -- Same present tick still runs tickReturns after pumpCurrent / react.
        ent._closeStrikeWait = true
        ent._closeStrikeArmedAt = now(session)
        ent._returnAt = nil
        -- After the punch, withdraw 1–2 tiles from the foe instead of home.
        ent._withdrawAfterStrike = true
        local dist = "-"
        if foe and type(Grid.padDistance) == "function" then
          dist = tostring(Grid.padDistance(g, ent, foe) or "-")
        end
        note(session, battle or session._battle, "cue path", side, thisId or "-",
          "walk", closed and "gap" or (stepped and "step" or "stay"),
          "dist=" .. dist, padSnap(ent), padSnap(foe))
      else
        if Projectiles and type(Projectiles.contact) == "function" then
          Projectiles.contact(session, side, {
            moveType = opts.moveType,
            moveId = opts.moveId,
          })
        end
        if Audio and type(Audio.playMove) == "function" then
          pcall(Audio.playMove, battle or session._battle, opts.moveId,
            side == "player")
        end
        if stepped then
          ent._returnAt = now(session) + (jump and 0.56 or 0.48)
        else
          ent._returnAt = nil
        end
        if type(ent.play) == "function" then
          ent:play(jump and "jump" or "attack")
        end
      end
    end
    return true
end)

Cues.register("hit", function(session, side, kind, Grid, nudgeCamera, battle, opts)
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return false
  end
  opts = opts or {}
  local foe = foeOf(session, side)
  local g = session.grid
  local category = normCategory(opts.category)

    if type(nudgeCamera) == "function" and battle then
      nudgeCamera(battle, side, 0.35)
    end
    local Audio = session._deps and session._deps.Audio
    if Audio and type(Audio.playHit) == "function" then
      pcall(Audio.playHit, battle or session._battle, opts.typeMult, {
        category = category or session._lastAttackCategory,
      })
    end
    local Projectiles = session._deps and session._deps.Projectiles
    local powerful = Projectiles and type(Projectiles.isPowerfulMove) == "function"
        and Projectiles.isPowerfulMove(opts)
    if powerful then
      local obstacle = Grid.obstacleBehind(g, ent, foe, 2)
      if Projectiles.powerHit then
        Projectiles.powerHit(session, side, opts)
      end
      Grid.knockbackTiles(g, ent, foe, 2)
      if obstacle and Projectiles.wallImpact then
        Projectiles.wallImpact(session, obstacle, opts)
      end
      ent._heavyHit = true
      if type(ent.play) == "function" then
        ent:play("hit")
      end
      return true
    end
    if Projectiles and type(Projectiles.lightHit) == "function" then
      Projectiles.lightHit(session, side, opts)
    end
    local cat = category or session._lastAttackCategory or "physical"
    -- Both can shove; physical more often / more reliably.
    local pushChance = (cat == "special") and 0.45 or 0.78
    if opts.push == false then
      pushChance = 0
    elseif opts.push == true then
      pushChance = 1
    end
    if rr() <= pushChance then
      Grid.knockback(g, ent, foe)
    end
    if type(ent.play) == "function" then
      ent:play("hit")
    end
    return true
end)

Cues.register("selfhit", function(session, side, kind, Grid, nudgeCamera, battle, opts)
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return false
  end
  opts = opts or {}
  local foe = foeOf(session, side)
  local g = session.grid
  local category = normCategory(opts.category)

    -- Confusion / recoil / crash: the user damages itself. Stumble in place
    -- with a bonk burst — never knock away from the foe.
    if type(nudgeCamera) == "function" and battle then
      nudgeCamera(battle, side, 0.22)
    end
    local Audio = session._deps and session._deps.Audio
    if Audio and type(Audio.playHit) == "function" then
      pcall(Audio.playHit, battle or session._battle, opts.typeMult)
    end
    local Projectiles = session._deps and session._deps.Projectiles
    if Projectiles and type(Projectiles.selfHit) == "function" then
      Projectiles.selfHit(session, side)
    end
    if type(ent.play) == "function" then
      ent:play("selfhit")
    end
    return true
end)

Cues.register("faint", function(session, side, kind, Grid, nudgeCamera, battle, opts)
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return false
  end
  opts = opts or {}
  local foe = foeOf(session, side)
  local g = session.grid
  local category = normCategory(opts.category)

    -- Owned by the HP bar hitting 0, not the "fainted!" dialogue.
    if isExitPlaying(ent) then
      return true
    end
    if type(nudgeCamera) == "function" and battle then
      nudgeCamera(battle, side, 0.28)
    end
    local Projectiles = session._deps and session._deps.Projectiles
    if Projectiles and type(Projectiles.faint) == "function" then
      Projectiles.faint(session, side)
    end
    -- Trainer-owned mons get the red recall laser; wild foes keep the sink.
    local beamed = false
    if ent.anim ~= "sendout"
        and Projectiles and type(Projectiles.recallBeam) == "function" then
      beamed = Projectiles.recallBeam(session, side, { target = ent }) ~= nil
    end
    ent._fainting = true
    if type(ent.play) == "function" then
      if beamed then
        ent:play("recall")
      else
        ent:play("faint")
      end
    end
    return true
end)

Cues.register("recall", function(session, side, kind, Grid, nudgeCamera, battle, opts)
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return false
  end
  opts = opts or {}
  local foe = foeOf(session, side)
  local g = session.grid
  local category = normCategory(opts.category)

    if isExitPlaying(ent) then
      return true
    end
    -- Don't shrink the live foe while the player is calling in.
    if side == "enemy" then
      local player = session.playerMon
      if (session.awaitPlayerMon or session._playerSendLockT
          or (player and player.anim == "sendout")) then
        return true
      end
    end
    local Projectiles = session._deps and session._deps.Projectiles
    if Projectiles and type(Projectiles.recallBeam) == "function" then
      Projectiles.recallBeam(session, side, { target = ent })
    end
    if type(ent.play) == "function" then
      ent:play("recall")
    end
    return true
end)

--- Apply a cue kind to a side. opts.category = "physical"|"special"
function Cues.apply(session, side, kind, Grid, nudgeCamera, battle, opts)
  if not (session and session.live and session.grid) then
    return false
  end
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent or ent._removed then
    return false
  end
  kind = tostring(kind or "attack")
  opts = opts or {}
  local flags = { "via=" .. tostring(opts.via or "-") }
  local force = cueForce(opts)
  if force then
    flags[#flags + 1] = force
  end
  if ent._pendingCloseStrike then
    flags[#flags + 1] = "pend"
  end
  if hasStruckThisTurn(ent) then
    flags[#flags + 1] = "struck"
  end
  local mid0 = cueMoveId(opts)
  if mid0 and wasPresented(session, side, mid0) then
    flags[#flags + 1] = "seen"
  end
  note(session, battle, "cue", side, kind, opts.moveId, opts.category,
    table.concat(flags, " "), describeEnt(session, ent, side))
  local category = normCategory(opts.category)
  session._lastCueSide = side
  session._lastCueKind = kind
  session._lastCueAt = now(session)
  if category then
    session._lastAttackCategory = category
  end
  if kind == "attack" or kind == "status" then
    local mid = opts.moveId and tostring(opts.moveId):upper() or nil
    if mid == "" then
      mid = nil
    end
    session._lastCueMoveId = mid
    session._lastCueMoveType = opts.moveType
    if mid and not opts.followUp then
      markPresented(session, side, mid)
    end
    if kind == "attack" and not opts.followUp and Cues.isMultiHitMove(mid) then
      -- First FIELD swing already presented; the engine's hit-1 anim
      -- row must not replay it. Hits 2+ reuse that skip flag.
      session._arSkipEngineStrike = true
      session._multiHitMoveId = mid
      session._multiHitSide = side
    end
  end

  ent.returning = nil
  ent.wanderTx, ent.wanderTy = nil, nil
  ent._wanderCD = 2.4

  local fn = HANDLERS[kind]
  if fn then
    local tracer = (type(debug) == "table" and debug.traceback) or tostring
    local ok, result = xpcall(function()
      return fn(session, side, kind, Grid, nudgeCamera, battle, opts)
    end, tracer)
    if not ok then
      noteErr(session, battle, "cue." .. kind, result)
      return false
    end
    note(session, battle, "cue ok", side, kind, opts.moveId)
    return result and true or false
  end
  if type(ent.play) == "function" and not ent._pendingCloseStrike then
    ent:play("attack")
  end
  note(session, battle, "cue ok", side, kind, opts.moveId)
  return true
end

function Cues.skipReason(session, side, kind, opts)
  kind = tostring(kind or "")
  opts = opts or {}
  if session and (kind == "faint" or kind == "recall") then
    local ent = (side == "player") and session.playerMon or session.enemyMon
    if isExitPlaying(ent) then
      return "exit"
    end
  end
  if not (session and session.live) then
    return nil
  end
  if cueForce(opts) then
    return nil
  end
  if kind == "attack" or kind == "status" then
    local mid = cueMoveId(opts)
    if mid and wasPresented(session, side, mid) then
      return "presented"
    end
    local ent = (side == "player") and session.playerMon or session.enemyMon
    local pending = ent and ent._pendingCloseStrike
    local pendingId = pending and pending.moveId
        and tostring(pending.moveId):upper() or nil
    if pending and (not mid or pendingId == mid) then
      return "pending"
    end
    if mid and wasStruck(ent, mid) then
      return "struck"
    end
  end
  if not session._lastCueAt then
    return nil
  end
  if session._lastCueSide ~= side then
    return nil
  end
  local last = session._lastCueKind
  if (kind == "attack" or kind == "status")
      and (last == "attack" or last == "status") then
    local mid = cueMoveId(opts)
    if mid and session._lastCueMoveId == mid then
      return "same-move"
    end
  end
  if (now(session) - session._lastCueAt) > 1.25 then
    return nil
  end
  if kind == last and (
      kind == "attack" or kind == "vanish" or kind == "emerge"
      or kind == "hit" or kind == "selfhit" or kind == "status"
      or kind == "faint") then
    return "beat"
  end
  return nil
end

function Cues.shouldSkipEvent(session, side, kind, opts)
  local reason = Cues.skipReason(session, side, kind, opts)
  if reason then
    note(session, session and session._battle, "cue skip", side, kind,
      cueMoveId(opts) or "-", reason, "via=" .. tostring((opts and opts.via) or "-"))
  end
  return reason ~= nil
end

function Cues.isReactKind(kind)
  kind = tostring(kind or "")
  return kind == "dodge" or kind == "cover" or kind == "hide" or kind == "brace"
end

-- Foe "Move!" / dodge is queued after "Surf!", so pumpCurrent would wait for
-- the attack toast to finish. Issue #10: play the react on the same beat as
-- the attack FX, and push the trainer line as an overlay callout.
function Cues.pumpOverlapReacts(session, battle, Grid, nudgeCamera)
  if not (session and session.live and battle) then
    return false
  end
  local cur = battle.current
  local attack = cur and cur.arFieldCue
  if not attack then
    return false
  end
  local attackKind = tostring(attack.kind or "")
  if attackKind ~= "attack" and attackKind ~= "status" then
    return false
  end

  local applied = false
  local function fire(react, row)
    if not react or react._arOverlapDone then
      return
    end
    if not Cues.isReactKind(react.kind) then
      return
    end
    react._arOverlapDone = true
    if row then
      row._arFieldCueDone = true
      row._arOverlapShown = true
    end
    Cues.apply(session, react.side, react.kind, Grid, nudgeCamera, battle, {
      category = react.category,
      moveType = react.moveType,
      moveId = react.moveId,
      via = "overlap",
    })
    local Callouts = session._deps and session._deps.Callouts
    if Callouts and type(Callouts.push) == "function" and react.text
        and react.side == "enemy" and react.bubble ~= "narrator"
        and (type(Callouts.isTrainerSpeech) ~= "function"
          or Callouts.isTrainerSpeech(react.text)) then
      pcall(Callouts.push, session, "foe", react.text, {
        kind = "react",
        urgent = true,
      })
    end
    applied = true
  end

  local attached = cur.arOverlapReact
  if type(attached) == "table" then
    for i = 1, #attached do
      fire(attached[i], nil)
    end
  end

  local opposite = (attack.side == "player") and "enemy" or "player"
  local q = battle.queue
  if type(q) == "table" then
    for i = 1, math.min(6, #q) do
      local row = q[i]
      local cue = row and row.arFieldCue
      if cue and not row._arFieldCueDone and cue.side == opposite
          and Cues.isReactKind(cue.kind) then
        fire({
          side = cue.side,
          kind = cue.kind,
          text = row.text,
          bubble = row.bubble,
        }, row)
      elseif cue and (cue.kind == "attack" or cue.kind == "status") then
        break
      end
    end
  end
  return applied
end

--- Drain one-shot cue from battle.current when it becomes active.
-- Faint / recall are HP-bar events (`shownHP` → 0), not dialogue. The
-- "fainted!" line often becomes current after the sprite is gone — applying
-- it then would replay the laser on the replacement mon.
-- Dodge / brace / cover attached to this attack (or sitting in the next
-- queue rows) fire on the same beat so they overlap the travel FX.
local function pushPinnedCallout(session, text, kind)
  local Callouts = session and session._deps and session._deps.Callouts
  if not (Callouts and type(Callouts.push) == "function" and text) then
    return
  end
  -- Pinned orders are already known NPC speech; do not re-filter.
  pcall(Callouts.push, session, "foe", text, {
    kind = kind or "order",
    urgent = true,
  })
end

function Cues.pumpCurrent(session, battle, Grid, nudgeCamera)
  local cur = battle and battle.current
  local cue = cur and cur.arFieldCue
  local applied = false
  local called = false
  -- Open the foe order first so the gray box is up a beat before the FX.
  if cur and cur.arNpcCallout and not cur._arNpcCalloutDone then
    cur._arNpcCalloutDone = true
    called = true
    pushPinnedCallout(session, cur.arNpcCallout, cur.arNpcCalloutKind or "order")
  end
  if cur and cue and not cur._arFieldCueDone then
    cur._arFieldCueDone = true
    local kind = tostring(cue.kind or "")
    local pumpOpts = {
      category = cue.category,
      moveType = cue.moveType,
      moveId = cue.moveId,
      vanish = cue.vanish,
      again = cue.again,
      isCalled = cue.isCalled,
      releaseStrike = cue.releaseStrike,
      followUp = cue.followUp,
      via = "pump",
    }
    if kind ~= "faint" and kind ~= "recall"
        and not Cues.shouldSkipEvent(session, cue.side, kind, pumpOpts) then
      applied = Cues.apply(session, cue.side, cue.kind, Grid, nudgeCamera, battle, pumpOpts)
          and true or false
    end
  end
  -- Overlap dodge/brace onto the live swing (including a close-gap walk, and
  -- late-attached reacts after the announce). After the punch, leftover
  -- queue reacts must not replay onto the foe's counter.
  local overlapped = false
  local attackEnt
  if cue and (cue.side == "player" or cue.side == "enemy") then
    attackEnt = (cue.side == "player") and session.playerMon or session.enemyMon
  end
  local punched = hasStruckThisTurn(attackEnt)
      and not (attackEnt and attackEnt._pendingCloseStrike)
  if not punched then
    overlapped = Cues.pumpOverlapReacts(session, battle, Grid, nudgeCamera)
  end
  return applied or overlapped or called
end

local function followUpAnimRow(row, moveId, wantPlayer)
  if not row or not row.anim then
    return false
  end
  if tostring(row.anim):upper() ~= moveId then
    return false
  end
  if not Cues.isEngineMoveAnim(row.anim) then
    return false
  end
  return (row.attackerIsPlayer == true) == wantPlayer
end

--- True while extra multi-hit engine anims (or the live clip) still belong
--- to this side — hold withdraw so the combo stays in melee.
function Cues.pendingMultiHitFollowUp(session, battle, side)
  if not (session and battle and side) then
    return false
  end
  local moveId = session._multiHitMoveId
  if not moveId or session._multiHitSide ~= side then
    return false
  end
  if not Cues.isMultiHitMove(moveId) then
    return false
  end
  local wantPlayer = side == "player"
  if battle.animPlaying and Cues.isEngineMoveAnim(battle.animName)
      and tostring(battle.animName):upper() == moveId
      and (battle.animAttackerIsPlayer == true) == wantPlayer then
    return true
  end
  local q = battle.queue
  if type(q) ~= "table" then
    return false
  end
  for i = 1, #q do
    local row = q[i]
    if followUpAnimRow(row, moveId, wantPlayer) and not row._arFieldFollowUpDone then
      return true
    end
  end
  return false
end

--- Replay FIELD contact/cast on each extra engine anim row (issue #16).
-- Hit 1 is the announce / close-the-gap punch; later `{ anim = move.id }`
-- rows are the remaining strikes. Engine queue already waits on each
-- anim + HP drain, so we only have to paint the world FX on those beats.
function Cues.pumpFollowUpAnims(session, battle, Grid, nudgeCamera)
  if not (session and session.live and battle) then
    return false
  end
  local moveId, isPlayer, item
  local q1 = battle.queue and battle.queue[1]
  if q1 and not q1._arFieldFollowUpDone and Cues.isEngineMoveAnim(q1.anim) then
    moveId = tostring(q1.anim):upper()
    isPlayer = q1.attackerIsPlayer == true
    item = q1
  elseif battle.animPlaying and Cues.isEngineMoveAnim(battle.animName) then
    moveId = tostring(battle.animName):upper()
    isPlayer = battle.animAttackerIsPlayer == true
    local key = moveId .. ":" .. (isPlayer and "P" or "E")
    if session._arFollowUpAnimKey == key then
      return false
    end
  else
    if not battle.animPlaying then
      session._arFollowUpAnimKey = nil
    end
    return false
  end

  if not Cues.isMultiHitMove(moveId) then
    return false
  end
  if session._lastCueMoveId ~= moveId then
    return false
  end
  local side = isPlayer and "player" or "enemy"
  if session._lastCueSide ~= side then
    return false
  end

  if item then
    item._arFieldFollowUpDone = true
  end
  session._arFollowUpAnimKey = moveId .. ":" .. (isPlayer and "P" or "E")

  -- Engine hit-1 anim is the swing FIELD already presented.
  if session._arSkipEngineStrike then
    session._arSkipEngineStrike = nil
    return false
  end

  local opts = {
    category = session._lastAttackCategory,
    moveId = moveId,
    moveType = session._lastCueMoveType,
    followUp = true,
    via = "followUp",
  }
  Cues.apply(session, side, "attack", Grid, nudgeCamera, battle, opts)
  local foeSide = (side == "player") and "enemy" or "player"
  Cues.apply(session, foeSide, "hit", Grid, nudgeCamera, battle, {
    category = opts.category,
    moveId = moveId,
    moveType = opts.moveType,
    followUp = true,
    push = false,
  })
  return true
end

local function flattenText(text)
  return tostring(text or ""):lower():gsub("\n", " "):gsub("%s+", " ")
end

function Cues.isSelfDamageText(text)
  local lower = flattenText(text)
  if lower:find("hurt itself", 1, true) then
    return true
  end
  if lower:find("hit with recoil", 1, true) then
    return true
  end
  if lower:find("kept going and", 1, true) and lower:find("crashed", 1, true) then
    return true
  end
  return false
end

local function inferSelfDamageSide(battle, text)
  local raw = tostring(text or "")
  local lower = flattenText(raw)
  if lower:find("hurt itself", 1, true) then
    local q = battle and battle.queue
    local idx = tonumber(battle and battle.nextInsert) or (q and #q) or 0
    for i = idx - 1, math.max(1, idx - 4), -1 do
      local prev = q and q[i]
      local t = flattenText(prev and prev.text)
      if t:find("is confused!", 1, true) then
        if t:find("enemy ", 1, true) then
          return "enemy"
        end
        return "player"
      end
    end
    return nil
  end
  if raw:find("Enemy ", 1, true) then
    return "enemy"
  end
  return "player"
end

--- Tag the latest (or nearby) queue row as a self-damage field cue.
-- `sideHint` wins when the line has no name ("It hurt itself...").
function Cues.tagSelfDamage(battle, text, sideHint)
  if type(battle) ~= "table" then
    return false
  end
  local q = battle.queue
  if type(q) ~= "table" then
    return false
  end
  local function rowMatches(row)
    return row and type(row.text) == "string" and Cues.isSelfDamageText(row.text)
  end
  local item = q[battle.nextInsert]
  if not rowMatches(item) then
    item = nil
    local start = tonumber(battle.nextInsert) or #q
    for i = start, math.max(1, start - 4), -1 do
      if rowMatches(q[i]) then
        item = q[i]
        break
      end
    end
  end
  if not item then
    return false
  end
  local side = sideHint or inferSelfDamageSide(battle, item.text)
  if side ~= "player" and side ~= "enemy" then
    return false
  end
  item.arFieldCue = { side = side, kind = "selfhit" }
  return true
end

--- Tag the latest queue row when a mon faints.
-- Kept for tests / callers; FIELD does not play exit FX from this tag.
-- Recall / faint sprites fire when the HP bar (`shownHP`) reaches 0.
function Cues.tagFaint(battle, text)
  if type(battle) ~= "table" or type(text) ~= "string" then
    return false
  end
  local lower = flattenText(text)
  if not lower:find("fainted!", 1, true) then
    return false
  end
  local item = battle.queue and battle.queue[battle.nextInsert]
  if type(item) ~= "table" then
    return false
  end
  local side = tostring(text):find("Enemy ", 1, true) and "enemy" or "player"
  item.arFieldCue = { side = side, kind = "faint" }
  return true
end

--- Tag Dig/Fly charge lines ("dug a hole" / "flew up high") as vanish cues.
function Cues.tagChargeVanish(battle, text)
  if type(battle) ~= "table" or type(text) ~= "string" then
    return false
  end
  local lower = flattenText(text)
  local flavor = nil
  if lower:find("dug a hole", 1, true) then
    flavor = "dig"
  elseif lower:find("flew up high", 1, true) then
    flavor = "fly"
  else
    return false
  end
  local item = battle.queue and battle.queue[battle.nextInsert]
  if type(item) ~= "table" then
    return false
  end
  local side = tostring(text):find("Enemy ", 1, true) and "enemy" or "player"
  item.arFieldCue = {
    side = side,
    kind = "vanish",
    vanish = flavor,
    moveId = flavor == "fly" and "FLY" or "DIG",
  }
  return true
end

--- Finish delayed attack returns to home cell + Dig/Fly release strikes.
function Cues.tickReturns(session, Grid)
  if not (session and session.grid) then
    return
  end
  local battle = session._battle
  local whiff = battle and battle._arWhiffCloseStrike
  if whiff then
    battle._arWhiffCloseStrike = nil
    Cues.cancelCloseStrike(session, whiff, Grid)
  end
  local t = now(session)
  for _, side in ipairs({ "player", "enemy" }) do
    local ent = (side == "player") and session.playerMon or session.enemyMon
    if ent and ent._pendingCloseStrike then
      local foe = foeOf(session, side)
      if foe and Grid.padDistance and Grid.padDistance(session.grid, ent, foe) > 1 then
        if type(Grid.closeGap) == "function" then
          local okG, errG = pcall(Grid.closeGap, session.grid, ent, foe)
          if not okG then
            noteErr(session, battle, "tickReturns.closeGap", errG)
          end
        end
      end
      if ent._closeStrikeWait then
        -- Cue just armed this tick (HUD confirm / announce). Walk first.
        ent._closeStrikeWait = nil
      elseif fieldMenuOpen(session._battle) then
        -- REACT! / other menus: keep the walk parked.
      elseif not Cues.stillWalkingToPad(ent) and Cues.inMeleeReach(ent, foe) then
        local okF, errF = pcall(fireCloseStrike, session, side, ent, Grid)
        if not okF then
          noteErr(session, battle, "tickReturns.punch", errF)
        end
      elseif ent._closeStrikeArmedAt
          and (t - ent._closeStrikeArmedAt) > 2.8
          and not fieldMenuOpen(session._battle) then
        local okF, errF = pcall(fireCloseStrike, session, side, ent, Grid)
        if not okF then
          noteErr(session, battle, "tickReturns.timeout", errF)
        end
      end
    end
    if ent and ent._pendingCloseStrike then
      -- Still closing; do not walk home yet.
    elseif ent and ent._returnAt and t >= ent._returnAt then
      if Cues.pendingMultiHitFollowUp(session, session._battle, side) then
        ent._returnAt = t + 0.12
      else
        ent._returnAt = nil
        local foe = foeOf(session, side)
        if ent._withdrawAfterStrike then
          ent._withdrawAfterStrike = nil
          if foe and type(Grid.withdrawFromFoe) == "function" then
            Grid.withdrawFromFoe(session.grid, ent, foe)
          end
        else
          Grid.returnHome(session.grid, ent)
        end
        restoreStepSpeed(ent)
      end
    end
    if ent and ent._releaseAt and t >= ent._releaseAt then
      ent._releaseAt = nil
      local pending = ent._pendingReleaseAttack
      ent._pendingReleaseAttack = nil
      ent._fieldVanished = nil
      ent._emerging = nil
      ent._arFieldDetached = nil
      ent.hidden = false
      if pending then
        Cues.apply(session, side, "attack", Grid, nil, session._battle, {
          category = pending.category,
          moveType = pending.moveType,
          moveId = pending.moveId,
          releaseStrike = true,
          via = "release",
        })
      end
    end
  end
end

--- Keep Dig/Fly users in buried/aloft holds while semi-invulnerable; emerge
--- if the invuln flag cleared without a release cue (miss / cancel / faint).
function Cues.syncSemiInvuln(session, Grid)
  if not (session and session.live) then
    return
  end
  for _, side in ipairs({ "player", "enemy" }) do
    local ent = (side == "player") and session.playerMon or session.enemyMon
    if not ent or ent._removed or ent._fainting then
      -- fall through
    else
      local battler = ent._battleBattler
      local flavor = battlerChargingVanish(battler)
      if flavor then
        ent._vanishKind = flavor
        local anim = ent.anim or ""
        if not ent._fieldVanished
            and anim ~= "vanish_dig" and anim ~= "vanish_fly"
            and anim ~= "buried" and anim ~= "aloft" then
          Cues.apply(session, side, "vanish", Grid, nil, session._battle, {
            vanish = flavor,
          })
        elseif ent._fieldVanished then
          -- Stay on the cast with a hold pose (dirt hole / sky circle).
          ent.hidden = false
          ent._arFieldDetached = nil
          local hold = (flavor == "fly") and "aloft" or "buried"
          if anim ~= hold and anim ~= "vanish_dig" and anim ~= "vanish_fly"
              and anim ~= "emerge_dig" and anim ~= "emerge_fly" then
            if type(ent.play) == "function" then
              ent:play(hold)
            else
              ent.anim = hold
            end
          end
        end
      elseif ent._fieldVanished and not ent._emerging
          and not ent._pendingReleaseAttack and not ent._releaseAt then
        -- Invulnerability ended without a queued release strike (miss/cancel).
        Cues.apply(session, side, "emerge", Grid, nil, session._battle, {
          vanish = ent._vanishKind or "dig",
        })
      end
    end
  end
end

return Cues
