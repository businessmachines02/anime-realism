-- Field battle — the front desk for "play this beat on the pad."
--
-- When a move is announced, someone gets hit, dodges, faints, and so on,
-- something has to turn that into motion and animation on the field.
-- This file is that front desk. Call Cues.apply(session, side, kind, …)
-- and it looks up the right handler, skips duplicates, and logs a trail.
--
-- The actual "what does an attack look like?" code is not here. This file
-- holds shared helpers (which mon, is this melee, how fast do they walk)
-- and the dispatcher. The rest of the work lives in sibling files:
--
--   cues_kinds.lua  what each beat does (attack, hit, dodge, faint, …)
--   cues_close.lua  walking up to punch, and waiting to apply HP until then
--   cues_pump.lua   when to play a beat that is sitting on the battle queue
--   cues_tags.lua   reading battle text ("hurt itself", "dug a hole") and
--                   marking the matching queue row as a field beat
--   cues_tick.lua   every frame: finish the punch, walk home, Dig/Fly poses
--
-- To add a new beat, register it in cues_kinds.lua. Do not grow apply().

local Cues = {}
Cues._Log = nil

local H = {}
Cues._H = H

function H.note(session, battle, tag, ...)
    local Log = (session and session._deps and session._deps.Log) or Cues._Log
    if not (Log and type(Log.note) == "function") then
        return
    end
    pcall(Log.note, battle or (session and session._battle), tag, ...)
end

function H.noteErr(session, battle, tag, err)
    local Log = (session and session._deps and session._deps.Log) or Cues._Log
    if not (Log and type(Log.err) == "function") then
        return
    end
    pcall(Log.err, battle or (session and session._battle), tag, err)
end

function H.now(session)
    if session and session._now ~= nil then
        return session._now
    end
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return 0
end

function H.rr(...)
    local random = (love and love.math and love.math.random) or math.random
    return random(...)
end

function H.sideEnt(session, side)
    if not session then
        return nil
    end
    if side == "player" then
        return session.playerMon
    end
    return session.enemyMon
end

function H.foeOf(session, side)
    if side == "player" then
        return session.enemyMon
    end
    return session.playerMon
end

function H.normCategory(cat)
    cat = tostring(cat or ""):lower()
    if cat == "special" or cat == "sp" then
        return "special"
    end
    if cat == "physical" or cat == "phys" then
        return "physical"
    end
    return nil
end

function H.isExitPlaying(ent)
    if not ent then
        return false
    end
    return ent._fainting == true
        or ent._faintDone == true
        or ent._recallDone == true
        or ent.anim == "recall"
        or ent.anim == "faint"
end

function H.playAnim(ent, name)
    if ent and type(ent.play) == "function" then
        ent:play(name)
    end
end

-- Punch the camera into the clash and slow the present clock. Optical
-- Zoom.offset is integer and recrops the voxel pass — we pan + time-scale
-- instead of fighting survey zoom. Glow / hair trails paint on the overlay
-- so voxel battlers still read the beat.
function H.clashFocus(session, side, opts)
    local ent = H.sideEnt(session, side)
    if not (session and ent) then
        return false
    end
    local foe = H.foeOf(session, side)
    local ax = (ent.basePx or ent.px or 0) + 8
    local ay = (ent.basePy or ent.py or 0) + 8
    local bx = foe and ((foe.basePx or foe.px or 0) + 8) or ax
    local by = foe and ((foe.basePy or foe.py or 0) + 8) or ay
    session.cameraNudgeX = (ax + bx) * 0.5
    session.cameraNudgeY = (ay + by) * 0.5
    session.cameraNudgeT = 0.62
    session._clashPunch = true
    session._clashSlowT = 0.78
    session._clashSlowDur = 0.78
    session._clashHitFx = true
    local Projectiles = session._deps and session._deps.Projectiles
    if Projectiles and type(Projectiles.clashBurst) == "function" then
        Projectiles.clashBurst(session, side, opts or {})
    elseif Projectiles and type(Projectiles.powerHit) == "function" then
        local foeSide = (side == "player") and "enemy" or "player"
        Projectiles.powerHit(session, foeSide, opts or {})
    end
    return true
end

function H.cueMoveId(opts)
    local mid = opts and opts.moveId and tostring(opts.moveId):upper() or nil
    if mid == "" then
        return nil
    end
    return mid
end

function H.cueForce(opts)
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

function H.flattenText(text)
    return tostring(text or ""):lower():gsub("\n", " "):gsub("%s+", " ")
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

function Cues.vanishKind(moveId)
    if not moveId then
        return nil
    end
    return Cues.VANISH_MOVES[tostring(moveId):upper()]
end

function H.battlerChargingVanish(battler)
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

function H.isChargeTurn(ent, moveId)
    local kind = Cues.vanishKind(moveId)
    if not kind then
        return false, nil
    end
    local battler = ent and ent._battleBattler
    if battler and (battler.invulnerable or battler.charging) then
        return true, H.battlerChargingVanish(battler) or kind
    end
    return false, kind
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
    return H.normCategory(opts.category) ~= "special"
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

--- Dash px/s: at least a brisk walk (idle gait is ~28–80). Attack adds a boost.
--- Player charges a bit harder so your swing does not stall after the walk.
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
    local gait = 48 + 72 * speedU
    local boost = 1 + 0.4 * atkU
    local px = gait * boost
    if side == "player" then
        px = px * 1.4
    end
    if px < 52 then
        px = 52
    elseif px > 130 then
        px = 130
    end
    return px
end

function H.restoreStepSpeed(ent)
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

function H.markPresented(session, side, mid)
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

function H.wasPresented(session, side, mid)
    if not (session and side and mid) then
        return false
    end
    local set = session._presentedMove and session._presentedMove[side]
    if type(set) == "string" then
        return set == mid
    end
    return type(set) == "table" and set[mid] == true
end

function H.markStruck(ent, mid)
    if not (ent and mid) then
        return
    end
    ent._struckMoves = ent._struckMoves or {}
    ent._struckMoves[mid] = true
    ent._closeStruckMoveId = mid
end

function H.wasStruck(ent, mid)
    if not (ent and mid) then
        return false
    end
    if ent._closeStruckMoveId == mid then
        return true
    end
    return ent._struckMoves and ent._struckMoves[mid] == true
end

function H.hasStruckThisTurn(ent)
    if not ent then
        return false
    end
    if ent._closeStruckMoveId then
        return true
    end
    local struck = ent._struckMoves
    return type(struck) == "table" and next(struck) ~= nil
end

function Cues.awaitingReact(battle)
    return battle and battle._arAwaitingReact == true
end

function H.fieldMenuOpen(battle)
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

--- Walk feet, not draw offsets / occupancy destination.
function H.walkPx(ent)
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
    local x, y = H.walkPx(ent)
    if type(x) ~= "number" then
        return false
    end
    local dx = ent.targetPx - x
    local dy = (ent.targetPy or 0) - (y or 0)
    return (dx * dx + dy * dy) > 8 * 8
end

--- True when the sprite is close enough to swing (last tile of the charge).
--- Never use targetPx: closeGap writes that to the adjacent cell immediately.
function Cues.inMeleeReach(ent, foe)
    if not (ent and foe) then
        return false
    end
    local ax, ay = H.walkPx(ent)
    local fx, fy = H.walkPx(foe)
    if type(ax) == "number" and type(fx) == "number" then
        local dx = fx - ax
        local dy = (fy or 0) - (ay or 0)
        -- 16px tile; 28 covers a diagonal step and a lunge before feet stop.
        return (dx * dx + dy * dy) <= 28 * 28
    end
    return false
end

function H.padSnap(ent)
    if not ent then
        return "nil"
    end
    local px = (type(ent.basePx) == "number") and "Y" or "N"
    return tostring(ent.padU) .. "," .. tostring(ent.padV) .. " px=" .. px
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

function H.describeEnt(session, ent, label)
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
        H.hasStruckThisTurn(ent) and "Y" or "N",
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
    return H.describeEnt(session, session.playerMon, "you"),
        H.describeEnt(session, session.enemyMon, "foe"),
        "dist=" .. dist
end

function Cues.notePos(session, battle, tag)
    tag = tag or "pos"
    local ok, you, foe, dist = pcall(Cues.describeField, session)
    if not ok then
        return
    end
    H.note(session, battle, tag, you)
    H.note(session, battle, tag, foe, dist)
end

--- Contact FX + attack/jump anim at the current cell (follow-up / Again!).
function H.playMeleeContact(session, side, ent, opts, jump)
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
    H.playAnim(ent, (jump or ent._attackJump) and "jump" or "attack")
    local mid = H.cueMoveId(opts)
    if mid then
        H.markStruck(ent, mid)
    end
    ent._returnAt = H.now(session) + 0.42
    ent._withdrawAfterStrike = true
end

local HANDLERS = {}

function Cues.register(kind, handler)
    if type(kind) ~= "string" or kind == "" or type(handler) ~= "function" then
        return Cues
    end
    HANDLERS[kind] = handler
    return Cues
end

--- Apply a cue kind to a side. opts.category = "physical"|"special"
function Cues.apply(session, side, kind, Grid, nudgeCamera, battle, opts)
    if not (session and session.live and session.grid) then
        return false
    end
    local ent = H.sideEnt(session, side)
    if not ent or ent._removed then
        return false
    end
    kind = tostring(kind or "attack")
    opts = opts or {}
    local flags = { "via=" .. tostring(opts.via or "-") }
    local force = H.cueForce(opts)
    if force then
        flags[#flags + 1] = force
    end
    if ent._pendingCloseStrike then
        flags[#flags + 1] = "pend"
    end
    if H.hasStruckThisTurn(ent) then
        flags[#flags + 1] = "struck"
    end
    local mid0 = H.cueMoveId(opts)
    if mid0 and H.wasPresented(session, side, mid0) then
        flags[#flags + 1] = "seen"
    end
    H.note(session, battle, "cue", side, kind, opts.moveId, opts.category,
        table.concat(flags, " "), H.describeEnt(session, ent, side))
    local category = H.normCategory(opts.category)
    session._lastCueSide = side
    session._lastCueKind = kind
    session._lastCueAt = H.now(session)
    if category then
        session._lastAttackCategory = category
    end
    if kind == "attack" or kind == "status" then
        local mid = H.cueMoveId(opts)
        session._lastCueMoveId = mid
        session._lastCueMoveType = opts.moveType
        if mid and not opts.followUp then
            H.markPresented(session, side, mid)
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
            H.noteErr(session, battle, "cue." .. kind, result)
            return false
        end
        H.note(session, battle, "cue ok", side, kind, opts.moveId)
        return result and true or false
    end
    if type(ent.play) == "function" and not ent._pendingCloseStrike then
        ent:play("attack")
    end
    H.note(session, battle, "cue ok", side, kind, opts.moveId)
    return true
end

function Cues.skipReason(session, side, kind, opts)
    kind = tostring(kind or "")
    opts = opts or {}
    if session and (kind == "faint" or kind == "recall") then
        local ent = H.sideEnt(session, side)
        if H.isExitPlaying(ent) then
            return "exit"
        end
    end
    if not (session and session.live) then
        return nil
    end
    if H.cueForce(opts) then
        return nil
    end
    if kind == "attack" or kind == "status" then
        local mid = H.cueMoveId(opts)
        if mid and H.wasPresented(session, side, mid) then
            return "presented"
        end
        local ent = H.sideEnt(session, side)
        local pending = ent and ent._pendingCloseStrike
        local pendingId = pending and pending.moveId
            and tostring(pending.moveId):upper() or nil
        if pending and (not mid or pendingId == mid) then
            return "pending"
        end
        if mid and H.wasStruck(ent, mid) then
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
        local mid = H.cueMoveId(opts)
        if mid and session._lastCueMoveId == mid then
            return "same-move"
        end
    end
    if (H.now(session) - session._lastCueAt) > 1.25 then
        return nil
    end
    if kind == last and (
            kind == "attack" or kind == "vanish" or kind == "emerge"
            or kind == "hit" or kind == "selfhit" or kind == "status"
            or kind == "counter" or kind == "faint" or Cues.isReactKind(kind)) then
        return "beat"
    end
    return nil
end

function Cues.shouldSkipEvent(session, side, kind, opts)
    local reason = Cues.skipReason(session, side, kind, opts)
    if reason then
        H.note(session, session and session._battle, "cue skip", side, kind,
            H.cueMoveId(opts) or "-", reason, "via=" .. tostring((opts and opts.via) or "-"))
    end
    return reason ~= nil
end

function Cues.isReactKind(kind)
    kind = tostring(kind or "")
    return kind == "dodge" or kind == "cover" or kind == "hide" or kind == "brace"
end

--- Load cue siblings. `loadFile` is field/init.lua's env.load (or the
--- test harness load) and receives paths relative to field/.
function Cues.attach(loadFile)
    if type(loadFile) ~= "function" then
        error("Cues.attach requires a load function", 2)
    end
    local files = {
        "fx/cues_close.lua",
        "fx/cues_kinds.lua",
        "fx/cues_pump.lua",
        "fx/cues_tags.lua",
        "fx/cues_tick.lua",
    }
    for i = 1, #files do
        local chunk = loadFile(files[i])
        if type(chunk) ~= "function" then
            error("Cues.attach: " .. files[i] .. " must return function(Cues)", 2)
        end
        chunk(Cues)
    end
    return Cues
end

return Cues
