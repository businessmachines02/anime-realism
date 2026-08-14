-- Field battle — arFieldCue → grid steps + cast anims.
--
-- Physical attacks step in toward the foe (or jump over cover); specials
-- cast in place with attacker→foe projectiles. Hits may knock the target
-- back one cell. Self-hits (confusion / recoil / crash) stumble in place.
-- Two-turn vanish moves (Dig / Fly) burrow or soar out of sight on the
-- charge turn and emerge on the release strike.
-- Cue dedupe prevents double-steps when multiple battle
-- events fire for the same move beat.

local Cues = {}

-- Gen1 semi-invulnerable charge moves → field vanish flavor.
Cues.VANISH_MOVES = {
  DIG = "dig",
  FLY = "fly",
}

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
  local category = normCategory(opts.category)
  session._lastCueSide = side
  session._lastCueKind = kind
  session._lastCueAt = now(session)
  if category then
    session._lastAttackCategory = category
  end
  local foe = foeOf(session, side)
  local g = session.grid

  ent.returning = nil
  ent.wanderTx, ent.wanderTy = nil, nil
  ent._wanderCD = 2.4

  if kind == "dodge" then
    Grid.dodge(g, ent, foe)
    if type(ent.play) == "function" then
      ent:play("dodge")
    end
    return true
  end

  if kind == "cover" or kind == "hide" then
    local hasCover = (session.grid and session.grid.props and #session.grid.props > 0)
        or (session.coverSlots and #session.coverSlots > 0)
    if hasCover then
      Grid.seekCover(g, ent, foe)
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
  end

  if kind == "brace" then
    if type(ent.play) == "function" then
      ent:play("brace")
    end
    return true
  end

  if kind == "status" then
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
  end

  if kind == "vanish" then
    local flavor = opts.vanish or Cues.vanishKind(opts.moveId) or "dig"
    ent._vanishKind = flavor
    ent._fieldVanished = nil
    ent._emerging = nil
    ent._pendingReleaseAttack = nil
    ent._returnAt = nil
    ent.hidden = false
    local Projectiles = session._deps and session._deps.Projectiles
    if Projectiles and type(Projectiles.vanish) == "function" then
      Projectiles.vanish(session, side, flavor)
    end
    if type(ent.play) == "function" then
      ent:play(flavor == "fly" and "vanish_fly" or "vanish_dig")
    end
    return true
  end

  if kind == "emerge" then
    local flavor = opts.vanish or ent._vanishKind
      or Cues.vanishKind(opts.moveId) or "dig"
    ent._vanishKind = flavor
    ent._emerging = true
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
  end

  if kind == "attack" then
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
    if Audio and type(Audio.playMove) == "function" then
      pcall(Audio.playMove, battle or session._battle, opts.moveId,
        side == "player")
    end
    if category == "special" then
      ent._returnAt = nil
      ent._attackStepped = nil
      if Projectiles and type(Projectiles.move) == "function" then
        local jump = type(Grid.pathObstructed) == "function"
            and Grid.pathObstructed(g, ent, foe)
        Projectiles.move(session, side, {
          category = "special",
          jump = jump,
          moveType = opts.moveType,
          moveId = opts.moveId,
        })
      end
      if type(ent.play) == "function" then
        ent:play("cast")
      end
    else
      -- Physical: mon charges (step / jump over cover); impact FX at the foe only.
      -- Jump only when cover blocks the path — already-adjacent mons just attack in place.
      local obstructed = type(Grid.pathObstructed) == "function"
          and Grid.pathObstructed(g, ent, foe)
      local jump = obstructed == true
      ent._attackJump = jump and true or nil
      ent._attackStepped = Grid.attackStep(g, ent, foe) == true
      if Projectiles and type(Projectiles.contact) == "function" then
        Projectiles.contact(session, side, {
          moveType = opts.moveType,
          moveId = opts.moveId,
        })
      end
      if ent._attackStepped then
        ent._returnAt = now(session) + (jump and 0.56 or 0.48)
      else
        ent._returnAt = nil
      end
      if type(ent.play) == "function" then
        ent:play(jump and "jump" or "attack")
      end
    end
    return true
  end

  if kind == "hit" then
    if type(nudgeCamera) == "function" and battle then
      nudgeCamera(battle, side, 0.35)
    end
    local Audio = session._deps and session._deps.Audio
    if Audio and type(Audio.playHit) == "function" then
      pcall(Audio.playHit, battle or session._battle, opts.typeMult)
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
  end

  if kind == "selfhit" then
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
  end

  if kind == "faint" then
    if type(nudgeCamera) == "function" and battle then
      nudgeCamera(battle, side, 0.28)
    end
    local Projectiles = session._deps and session._deps.Projectiles
    if Projectiles and type(Projectiles.faint) == "function" then
      Projectiles.faint(session, side)
    end
    -- Trainer-owned mons get the red recall laser; wild foes keep the sink.
    local beamed = false
    if Projectiles and type(Projectiles.recallBeam) == "function" then
      beamed = Projectiles.recallBeam(session, side) ~= nil
    end
    if type(ent.play) == "function" and not ent._fainting then
      if beamed then
        ent._fainting = true
        ent:play("recall")
      else
        ent:play("faint")
      end
    end
    return true
  end

  if kind == "recall" then
    local Projectiles = session._deps and session._deps.Projectiles
    if Projectiles and type(Projectiles.recallBeam) == "function" then
      Projectiles.recallBeam(session, side)
    end
    if type(ent.play) == "function" then
      ent:play("recall")
    end
    return true
  end

  if type(ent.play) == "function" then
    ent:play("attack")
  end
  return true
end

function Cues.shouldSkipEvent(session, side, kind)
  if not (session and session.live and session._lastCueAt) then
    return false
  end
  if (now(session) - session._lastCueAt) > 1.25 then
    return false
  end
  if session._lastCueSide ~= side then
    return false
  end
  kind = tostring(kind or "")
  local last = session._lastCueKind
  if kind == "attack" and last == "attack" then
    return true
  end
  if kind == "vanish" and last == "vanish" then
    return true
  end
  if kind == "emerge" and last == "emerge" then
    return true
  end
  if kind == "hit" and last == "hit" then
    return true
  end
  if kind == "selfhit" and last == "selfhit" then
    return true
  end
  if kind == "status" and last == "status" then
    return true
  end
  if kind == "faint" and last == "faint" then
    return true
  end
  return false
end

--- Drain one-shot cue from battle.current when it becomes active.
function Cues.pumpCurrent(session, battle, Grid, nudgeCamera)
  local cur = battle and battle.current
  local cue = cur and cur.arFieldCue
  if not (cur and cue and not cur._arFieldCueDone) then
    return false
  end
  cur._arFieldCueDone = true
  return Cues.apply(session, cue.side, cue.kind, Grid, nudgeCamera, battle, {
    category = cue.category,
    moveType = cue.moveType,
    moveId = cue.moveId,
    vanish = cue.vanish,
  })
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
  local t = now(session)
  for _, side in ipairs({ "player", "enemy" }) do
    local ent = (side == "player") and session.playerMon or session.enemyMon
    if ent and ent._returnAt and t >= ent._returnAt then
      ent._returnAt = nil
      Grid.returnHome(session.grid, ent)
    end
    if ent and ent._releaseAt and t >= ent._releaseAt then
      ent._releaseAt = nil
      local pending = ent._pendingReleaseAttack
      ent._pendingReleaseAttack = nil
      ent._fieldVanished = nil
      ent._emerging = nil
      ent.hidden = false
      if pending then
        Cues.apply(session, side, "attack", Grid, nil, session._battle, {
          category = pending.category,
          moveType = pending.moveType,
          moveId = pending.moveId,
          releaseStrike = true,
        })
      end
    end
  end
end

--- Keep Dig/Fly users disappeared while semi-invulnerable; emerge if the
--- invuln flag cleared without a release cue (miss / cancel / faint).
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
            and anim ~= "vanish_dig" and anim ~= "vanish_fly" then
          Cues.apply(session, side, "vanish", Grid, nil, session._battle, {
            vanish = flavor,
          })
        elseif ent._fieldVanished then
          ent.hidden = true
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
