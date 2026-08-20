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

Cues.TOSS_DUR = 1.08

function Cues.isTossMove(opts)
    return H.cueMoveId(opts) == "SEISMIC_TOSS"
end

function Cues.tossAirPending(session)
    if not session then
        return false
    end
    local function air(ent)
        return ent and (ent.anim == "toss" or ent.anim == "tossed")
    end
    return air(session.playerMon) or air(session.enemyMon)
end

--- Knockback / hit pose wait until Seismic Toss slams back down.
function Cues.tickTossLand(session, Grid)
    local pending = session and session._pendingTossHit
    if not pending then
        return false
    end
    if Cues.tossAirPending(session) then
        return false
    end
    session._pendingTossHit = nil
    local opts = pending.opts or {}
    opts.via = "toss-land"
    Grid = Grid or (session._deps and session._deps.Grid)
    return Cues.apply(session, pending.side, "hit", Grid, nil, session._battle, opts)
        == true
end

function H.playTossPair(session, side)
    local atk = H.sideEnt(session, side)
    local def = H.foeOf(session, side)
    H.playAnim(atk, "toss")
    H.playAnim(def, "tossed")
    H.punchIn(session, side, {
        focus = "mid",
        hold = Cues.TOSS_DUR,
        lift = 30,
    })
end

function H.playMeleeStrike(session, side, ent, opts, jump)
    opts = opts or {}
    if Cues.isTossMove(opts) then
        H.playTossPair(session, side)
        return Cues.TOSS_DUR
    end
    local leaping = jump or (ent and ent._attackJump)
    H.playAnim(ent, leaping and "jump" or "attack")
    return leaping and 0.56 or 0.48
end

-- Punch the camera in. Optical Zoom.offset recrops voxel, so we pan +
-- time-scale. Clash is the full counter beat (glow, hair, heavy hit).
function H.punchIn(session, side, spec)
    spec = spec or {}
    local ent = H.sideEnt(session, side)
    if not (session and ent) then
        return false
    end
    if spec.mode ~= "clash" and spec.mode ~= "react" and session._clashPunch then
        return false
    end
    local foe = H.foeOf(session, side)
    local ax = (ent.basePx or ent.px or 0) + 8
    local ay = (ent.basePy or ent.py or 0) + 8
    local bx = foe and ((foe.basePx or foe.px or 0) + 8) or ax
    local by = foe and ((foe.basePy or foe.py or 0) + 8) or ay
    local lift = spec.lift or 6
    local focus = spec.focus or "mid"
    local nx, ny
    if focus == "user" then
        nx, ny = ax, ay - lift
    elseif focus == "foe" and foe then
        nx, ny = bx, by - lift
    else
        nx, ny = (ax + bx) * 0.5, (ay + by) * 0.5 - lift
    end
    session.cameraNudgeX = nx
    session.cameraNudgeY = ny
    session.cameraNudgeT = spec.hold or 0.55
    if spec.mode == "clash" then
        session._clashPunch = true
        session._clashHitFx = true
    end
    local slow = tonumber(spec.slow) or 0
    if slow > 0 then
        session._clashSlowT = slow
        session._clashSlowDur = slow
    end
    local Projectiles = session._deps and session._deps.Projectiles
    if spec.burst and Projectiles and type(Projectiles.clashBurst) == "function" then
        Projectiles.clashBurst(session, side, spec.opts or spec)
    elseif spec.mode == "clash" and Projectiles and type(Projectiles.powerHit) == "function" then
        local foeSide = (side == "player") and "enemy" or "player"
        Projectiles.powerHit(session, foeSide, spec.opts or spec)
    end
    return true
end

function H.clashFocus(session, side, opts)
    return H.punchIn(session, side, {
        mode = "clash",
        focus = "mid",
        hold = 0.88,
        slow = 0.78,
        lift = 6,
        burst = true,
        opts = opts or {},
    })
end

--- Player KO: same clash beat as a counter (glow, hair trails, slow-mo).
function H.finishingFocus(session, atkSide, opts)
    if not session then
        return false
    end
    if session._clashPunch then
        return true
    end
    H.clashFocus(session, atkSide, opts)
    local atk = H.sideEnt(session, atkSide)
    H.playAnim(atk, "counter")
    return true
end

--- Player hit that just dropped the foe to 0 HP.
function Cues.isFinishingBlow(user, target)
    if not (user and user.isPlayer and target and not target.isPlayer) then
        return false
    end
    local hp = target.mon and target.mon.hp
    return type(hp) == "number" and hp <= 0
end

--- Contact juice without a fake zoom: freeze a few frames and bump the camera.
--- Classic battle.fx.shake recrops the voxel pass and can abort Love.
function H.impactKick(session, spec)
    spec = spec or {}
    if not session then
        return false
    end
    local heavy = spec.powerful == true or spec.clash == true
    if spec.noStop ~= true and spec.clash ~= true and (session._clashSlowT or 0) <= 0 then
        session._hitStopT = heavy and 0.08 or 0.045
    end
    session._camShakeDur = heavy and 0.16 or 0.10
    session._camShakeT = session._camShakeDur
    session._camShakeAmp = heavy and 2.8 or 1.6
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
    if Projectiles and type(Projectiles.isProjectileSpecial) == "function"
        and Projectiles.isProjectileSpecial(opts) then
        return false
    end
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

local function closeGapStatTable(ent, battle, side)
    local stats = ent and ent._closeGapStats
    if type(stats) == "table" then
        return stats
    end
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
        return def.baseStats
    end
    if battler and type(battler.stats) == "table" then
        return battler.stats
    end
    if mon and type(mon.stats) == "table" then
        return mon.stats
    end
    return nil
end

--- Same band as the red HP chip / WK row (and the default low-HP warn).
Cues.LOW_HP_RATIO = 0.20
--- Hurt mons want the FIRE ring even if they are melee brawlers.
Cues.LOW_HP_KEEP = 0.85

function Cues.hpRatio(ent, battle, side)
    if ent and ent._hpRatio ~= nil then
        return tonumber(ent._hpRatio)
    end
    local battler = ent and ent._battleBattler
    if not battler and battle then
        if side == "player" then
            battler = battle.player
        elseif side == "enemy" then
            battler = battle.enemy
        end
    end
    local mon = battler and battler.mon
    local hp = tonumber(mon and mon.hp)
    if hp == nil then
        hp = tonumber(battler and battler.shownHP)
    end
    local maxHp = mon and mon.stats and tonumber(mon.stats.hp)
    if not hp or not maxHp or maxHp <= 0 then
        return nil
    end
    if hp < 0 then
        hp = 0
    end
    return math.max(0, math.min(1, hp / maxHp))
end

--- 0 = melee brawler, 1 = glass cannon that wants space.
--- Red HP (≤20%) also wants space, even on a tank.
function Cues.keepAwayBias(ent, battle, side)
    local bias = 0
    local stats = closeGapStatTable(ent, battle, side)
    if type(stats) == "table" then
        local spa = tonumber(stats.special or stats.spa or stats.spAtk
            or stats.spatk or stats.spAttack) or 70
        local defn = tonumber(stats.defense or stats.def) or 70
        if spa > 140 or defn > 160 then
            spa = spa * 0.45
            defn = defn * 0.45
        end
        local d = spa - defn
        if d >= 80 then
            bias = 1
        elseif d > 10 then
            bias = (d - 10) / 70
        end
    else
        bias = tonumber(ent and ent._keepAway) or 0
    end
    local ratio = Cues.hpRatio(ent, battle, side)
    local low = Cues.LOW_HP_RATIO or 0.20
    if ratio and ratio > 0 and ratio <= low then
        local floor = Cues.LOW_HP_KEEP or 0.85
        if bias < floor then
            bias = floor
        end
    end
    return bias
end

--- Damaging ranged special this battler can still fire (PP left).
function Cues.battlerHasFireSpecial(battle, battler, Projectiles)
    if type(battler) ~= "table" then
        battler = battle and battle.player
    end
    local moves = battler and battler.curMoves
    if type(moves) ~= "table" then
        moves = battler and battler.mon and battler.mon.moves
    end
    if type(moves) ~= "table" then
        return false
    end
    for i = 1, #moves do
        local mv = moves[i]
        if mv and not mv.struggle and (mv.pp == nil or mv.pp > 0) then
            local id = tostring(mv.id or mv.name or ""):upper():gsub("%s+", "_")
            local power = tonumber(mv.power)
            local cat = tostring(mv.category or ""):lower()
            local def = nil
            if type(battle) == "table" and type(battle.moveDef) == "function" then
                local ok, got = pcall(battle.moveDef, battle, mv)
                if ok and type(got) == "table" then
                    def = got
                end
            end
            if not def and battle and battle.data and battle.data.moves then
                def = battle.data.moves[id]
            end
            if def then
                power = tonumber(def.power) or power
                cat = tostring(def.category or cat):lower()
                id = tostring(def.id or id):upper():gsub("%s+", "_")
            end
            if id ~= "" and (power or 0) > 0 and cat ~= "status" then
                local opts = {
                    moveId = id,
                    moveType = (def and def.type) or mv.type,
                    category = cat,
                }
                local contact = Projectiles and type(Projectiles.isContactFx) == "function"
                    and Projectiles.isContactFx(opts)
                local travel = Projectiles and type(Projectiles.isTravelFx) == "function"
                    and Projectiles.isTravelFx(opts)
                if not contact and (travel or cat == "special") then
                    return true
                end
            end
        end
    end
    return false
end

local function rng01()
    local r = (love and love.math and love.math.random) or math.random
    return r()
end

--- Slow wind-up into the usual dash. Stronger / more random when the
--- player could FIRE NOW, and when the charger wants to keep space.
function Cues.armCloseGapGait(ent, battle, side, foe, opts)
    opts = opts or {}
    if not ent then
        return 0
    end
    local cruise = Cues.closeGapSpeed(ent, battle, side)
    local bias = Cues.keepAwayBias(ent, battle, side)
    ent._keepAway = bias
    local playerSpecial = false
    if side == "enemy" then
        local Projectiles = opts.Projectiles
        playerSpecial = Cues.battlerHasFireSpecial(battle, battle and battle.player,
            Projectiles) == true
    end
    local roll = tonumber(opts.rand)
    if roll == nil then
        roll = rng01()
    end
    local startFrac
    if playerSpecial then
        -- Still a wind-up, but not a crawl — the player needs a beat, not a stall.
        startFrac = 0.28 + roll * 0.24
    else
        startFrac = 0.58 + roll * 0.30
    end
    startFrac = startFrac * (1 - 0.40 * math.max(0, bias))
    local start = cruise * startFrac
    if start < 14 then
        start = 14
    end
    if start > cruise then
        start = cruise
    end
    ent._closeGapCruise = cruise
    ent._closeGapStart = start
    ent.stepSpeed = start
    local ax, ay = H.walkPx(ent)
    local fx, fy = H.walkPx(foe)
    local span = 48
    if type(ax) == "number" and type(fx) == "number" then
        local dx, dy = fx - ax, (fy or 0) - (ay or 0)
        span = math.sqrt(dx * dx + dy * dy)
    end
    ent._closeGapSpan = math.max(span, 8)
    if playerSpecial then
        local now = opts.now
        if type(now) ~= "number" then
            now = 0
        end
        ent._closeGapMinAt = now + 0.28 + roll * 0.34
    else
        ent._closeGapMinAt = nil
    end
    return start
end

function Cues.tickCloseGapGait(ent, foe)
    if not (ent and ent._pendingCloseStrike and ent._closeGapCruise) then
        return ent and ent.stepSpeed
    end
    local cruise = ent._closeGapCruise
    local start = ent._closeGapStart or cruise
    local span = ent._closeGapSpan or 48
    local dist = span
    local ax, ay = H.walkPx(ent)
    local fx, fy = H.walkPx(foe)
    if type(ax) == "number" and type(fx) == "number" then
        local dx, dy = fx - ax, (fy or 0) - (ay or 0)
        dist = math.sqrt(dx * dx + dy * dy)
    end
    local u = 1 - math.max(0, math.min(1, dist / span))
    -- Mix linear with quadratic so the first steps aren't glued down.
    local eased = u * (0.42 + 0.58 * u)
    local px = start + (cruise - start) * eased
    ent.stepSpeed = px
    return px
end

function Cues.closeGapPunchTimeout(ent)
    local cruise = ent and ent._closeGapCruise
    local start = ent and ent._closeGapStart
    local t = 2.8
    if cruise and start and start > 0 and start < cruise then
        t = 2.8 * (cruise / start)
        if t > 5.6 then
            t = 5.6
        end
    end
    return t
end

function H.restoreStepSpeed(ent)
    if not ent then
        return
    end
    ent._closeGapCruise = nil
    ent._closeGapStart = nil
    ent._closeGapSpan = nil
    ent._closeGapMinAt = nil
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

--- Opening homes leave one empty cell (Chebyshev 2). That is the FIRE shot.
Cues.FIRE_PAD_RANGE = 2
--- Ranged specials from this far pick up an extra miss. Compact pads
--- top out around 4, so this only bites on a wide arena.
Cues.FAR_SHOT_RANGE = 5
Cues.FAR_SHOT_MISS = {
    [5] = 0.10,
    [6] = 0.15,
}
Cues.FAR_SHOT_MISS_CAP = 0.20

local function padChebyshev(a, b)
    if not (a and b) then
        return 0
    end
    return math.max(
        math.abs((b.padU or 0) - (a.padU or 0)),
        math.abs((b.padV or 0) - (a.padV or 0)))
end

function Cues.livePadDistance(session, a, b)
    a = a or (session and session.playerMon)
    b = b or (session and session.enemyMon)
    local dist = padChebyshev(a, b)
    local Grid = session and session._deps and session._deps.Grid
    if Grid and type(Grid.padDistance) == "function" and session.grid then
        dist = Grid.padDistance(session.grid, a, b) or dist
    end
    return dist
end

function Cues.farShotMissChance(dist)
    dist = tonumber(dist) or 0
    if dist < (Cues.FAR_SHOT_RANGE or 5) then
        return 0
    end
    local by = Cues.FAR_SHOT_MISS
    if type(by) == "table" and type(by[dist]) == "number" then
        return by[dist]
    end
    return Cues.FAR_SHOT_MISS_CAP or 0.20
end

function Cues.rollFarShotMiss(dist, rng)
    local chance = Cues.farShotMissChance(dist)
    if chance <= 0 then
        return false
    end
    if type(rng) ~= "function" then
        rng = (love and love.math and love.math.random) or math.random
    end
    return rng() < chance
end

--- Extra miss on a ranged special fired from 5+ tiles. Melee, never-miss,
--- and compact-pad shots are unchanged. `hit` is the engine's roll.
function Cues.applyFarShotAccuracy(session, ctx, hit, rng)
    if not hit then
        return false
    end
    local move = ctx and ctx.move
    if not move then
        return hit
    end
    if move.neverMiss or move.accuracy == 0 then
        return hit
    end
    local Projectiles = session and session._deps and session._deps.Projectiles
    if not Cues.isRangedCounter({
        category = move.category,
        moveId = move.id,
        moveType = move.type,
    }, Projectiles) then
        return hit
    end
    if Cues.rollFarShotMiss(Cues.livePadDistance(session), rng) then
        return false
    end
    return true
end

--- True when the mons are still a two-tile shot.
--- closeGap jumps occupancy to adjacent immediately; feet can still be
--- two tiles out, and that is still FIRE until they reach melee.
function Cues.fireRangeOpen(session)
    if not (session and session.live) then
        return false
    end
    local player = session.playerMon
    local foe = session.enemyMon
    if not (player and foe) then
        return false
    end
    local dist = Cues.livePadDistance(session, player, foe)
    if dist == Cues.FIRE_PAD_RANGE then
        return true
    end
    local closing = (foe._pendingCloseStrike or player._pendingCloseStrike)
        and not Cues.inMeleeReach(player, foe)
    if dist == 1 and closing then
        return true
    end
    return false
end

--- True while a close-gap charge is still a two-tile FIRE window.
--- `side` is the charger: "enemy" (default, your FIRE) or "player" (theirs).
function Cues.chargeWindowOpen(session, side)
    if not Cues.fireRangeOpen(session) then
        return false
    end
    side = side or "enemy"
    local charger = (side == "player") and session.playerMon or session.enemyMon
    return charger and charger._pendingCloseStrike and true or false
end

function Cues.playerChargeWindowOpen(session)
    return Cues.chargeWindowOpen(session, "player")
end

function Cues.awaitingReact(battle)
    return battle and battle._arAwaitingReact == true
end

--- True while the slower side's move diamond is waiting after the incoming.
function Cues.awaitingCallout(battle)
    return battle and battle._arAwaitCallout == true
end

--- True while Again! parked a special attacker on a second CALL.
function Cues.awaitingAgain(battle)
    return battle and battle._arAwaitAgain == true
end

--- Melee Again! is an extra swing. A special / travel shot is a new call.
function Cues.againOffersCall(opts, Projectiles)
    opts = opts or {}
    if opts.forceMeleeAgain == true then
        return false
    end
    return not Cues.isMeleeAttack(opts, Projectiles)
end

--- Brace/entrench counter: clash after the incoming hit, not on the pick.
function Cues.tickBraceCounter(session, Grid)
    local battle = session and session._battle
    local pending = battle and battle._arPendingBraceCounter
    if not pending then
        return false
    end
    local t = H.now(session)
    if not pending.armedAt then
        pending.armedAt = t
    end
    if pending.fireAt then
        if t < pending.fireAt then
            return false
        end
    elseif (t - pending.armedAt) < 1.35 then
        return false
    end
    battle._arPendingBraceCounter = nil
    battle._arBraceCounterPlayed = true
    return Cues.apply(session, "player", "counter", Grid, nil, battle, {
        category = pending.category,
        moveId = pending.moveId,
        moveType = pending.moveType,
        via = "brace-counter",
    }) == true
end

--- Incoming special/travel used as a dodge-counter (not a punch/bite).
function Cues.isRangedCounter(opts, Projectiles)
    opts = opts or {}
    if Projectiles and type(Projectiles.isContactFx) == "function"
        and Projectiles.isContactFx(opts) then
        return false
    end
    if Projectiles and type(Projectiles.isProjectileSpecial) == "function"
        and Projectiles.isProjectileSpecial(opts) then
        return true
    end
    if Projectiles and type(Projectiles.isTravelFx) == "function"
        and Projectiles.isTravelFx(opts) then
        return true
    end
    return H.normCategory(opts.category) == "special"
end

--- Fire the dodge-counter special while the charger is still walking in.
function Cues.fireDodgeCounterShot(session, side, opts)
    opts = opts or {}
    local moveId = opts.counterMoveId
    if not moveId or tostring(moveId) == "" then
        return false
    end
    local shot = {
        moveId = moveId,
        moveType = opts.counterMoveType,
        category = opts.counterCategory or "special",
    }
    local Projectiles = session and session._deps and session._deps.Projectiles
    if not Cues.isRangedCounter(shot, Projectiles) then
        return false
    end
    if Projectiles and type(Projectiles.move) == "function" then
        Projectiles.move(session, side, shot)
    end
    session._dodgeCounterShot = {
        side = side,
        moveId = tostring(moveId):upper():gsub("%s+", "_"),
    }
    return true
end

--- Two specials collide between the mons.
function Cues.playBeamClash(session, Grid, result, ctx)
    if not session then
        return false
    end
    result = result or {}
    ctx = ctx or {}
    local incoming = ctx.move or {}
    local reply = ctx.replyMove or {}
    local replySide = ctx.replySide or "player"
    local playerShot, enemyShot
    if replySide == "enemy" then
        playerShot, enemyShot = incoming, reply
    else
        playerShot, enemyShot = reply, incoming
    end
    local Projectiles = session._deps and session._deps.Projectiles
    if Projectiles and type(Projectiles.beamClash) == "function" then
        Projectiles.beamClash(session, {
            moveId = playerShot.id or playerShot.moveId,
            moveType = playerShot.type or playerShot.moveType,
        }, {
            moveId = enemyShot.id or enemyShot.moveId,
            moveType = enemyShot.type or enemyShot.moveType,
        })
    end
    local player = H.sideEnt(session, "player")
    local enemy = H.sideEnt(session, "enemy")
    if player then
        H.playAnim(player, "cast")
    end
    if enemy then
        H.playAnim(enemy, "cast")
    end
    H.punchIn(session, "player", {
        mode = "clash",
        focus = "mid",
        hold = 0.88,
        slow = 0.78,
        lift = 6,
        burst = false,
    })
    return true
end

--- Hold slow-mo + camera on the charger while REACT is open.
function Cues.beginReactHold(session, battle)
    if not session then
        return false
    end
    if session._reactHold then
        return true
    end
    session._reactHold = true
    session._reactReleaseT = nil
    session._reactReleaseDur = nil
    local incoming = "enemy"
    if session.playerMon and session.playerMon._pendingCloseStrike then
        incoming = "player"
    elseif session.enemyMon and session.enemyMon._pendingCloseStrike then
        incoming = "enemy"
    end
    H.punchIn(session, incoming, {
        mode = "react",
        focus = "user",
        hold = 8,
        lift = 8,
    })
    return true
end

--- Hold slow-mo on the special attacker while Again! waits for a CALL.
function Cues.beginAgainHold(session, battle)
    if not session then
        return false
    end
    if session._reactHold then
        return true
    end
    session._reactHold = true
    session._reactReleaseT = nil
    session._reactReleaseDur = nil
    local side = (battle and battle._arAwaitAgainSide) or "player"
    if side ~= "enemy" then
        side = "player"
    end
    H.punchIn(session, side, {
        mode = "react",
        focus = "user",
        hold = 8,
        lift = 8,
    })
    return true
end

--- Snap out of the REACT hold: speed up, then juice matches the pick.
function Cues.releaseReactHold(session, outcome)
    if not session then
        return false
    end
    local held = session._reactHold == true
    session._reactHold = nil
    outcome = tostring(outcome or "commit")
    if outcome == "clash" then
        session._reactReleaseT = nil
        session._reactReleaseDur = nil
        return held
    end
    local shot = outcome == "dodge_shot" or outcome == "call"
    session._reactReleaseT = shot and 0.24 or 0.16
    session._reactReleaseDur = session._reactReleaseT
    H.impactKick(session, {
        powerful = shot or outcome == "dodge_fail" or outcome == "commit",
        noStop = true,
    })
    return true
end

function Cues.releaseAgainHold(session, outcome)
    return Cues.releaseReactHold(session, outcome or "call")
end

function Cues.syncReactHold(session, battle)
    if not session then
        return false
    end
    if Cues.awaitingReact(battle) then
        return Cues.beginReactHold(session, battle)
    end
    if Cues.awaitingAgain(battle) then
        return Cues.beginAgainHold(session, battle)
    end
    if session._reactHold then
        return Cues.releaseReactHold(session, "commit")
    end
    return false
end

--- Keep the close-gap walk alive until the dodge-counter shot reads.
function Cues.deferCancelCloseStrike(session, side, delay)
    local battle = session and session._battle
    if not battle then
        return false
    end
    battle._arWhiffCloseStrike = side
    battle._arWhiffCloseAfter = H.now(session) + (tonumber(delay) or 0.42)
    return true
end

function H.fieldMenuOpen(battle)
    if Cues.awaitingReact(battle) or Cues.awaitingAgain(battle)
        or Cues.awaitingCallout(battle) then
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

--- Dodge/brace wait for the charger to arrive. Occupancy can already be
--- adjacent while feet are still two tiles out.
function Cues.shouldHoldReactPose(session, side, kind, opts)
    kind = tostring(kind or "")
    if kind ~= "dodge" and kind ~= "brace" then
        return false
    end
    opts = opts or {}
    if opts.via == "held-react" or H.cueForce(opts) then
        return false
    end
    local defender = H.sideEnt(session, side)
    local charger = H.foeOf(session, side)
    if not (defender and charger and charger._pendingCloseStrike) then
        return false
    end
    return not Cues.inMeleeReach(charger, defender)
end

function Cues.heldReactPending(session)
    return session and session._heldReact ~= nil
end

--- Play a stashed dodge/brace once the charger is in melee.
function Cues.tickHeldReact(session, Grid)
    local held = session and session._heldReact
    if not held then
        return false
    end
    local defender = H.sideEnt(session, held.side)
    local charger = H.foeOf(session, held.side)
    if not Cues.inMeleeReach(charger, defender) then
        return false
    end
    session._heldReact = nil
    local opts = held.opts or {}
    opts.via = "held-react"
    return Cues.apply(session, held.side, held.kind, Grid or held.Grid,
        held.nudgeCamera, held.battle or session._battle, opts) == true
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
    H.playMeleeStrike(session, side, ent, opts, jump or ent._attackJump)
    local mid = H.cueMoveId(opts)
    if mid then
        H.markStruck(ent, mid)
    end
    local hang = Cues.isTossMove(opts) and Cues.TOSS_DUR or 0.42
    ent._returnAt = H.now(session) + hang
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
    if Cues.shouldHoldReactPose(session, side, kind, opts) then
        session._heldReact = {
            side = side,
            kind = kind,
            opts = opts,
            Grid = Grid,
            nudgeCamera = nudgeCamera,
            battle = battle,
        }
        H.note(session, battle, "cue hold", side, kind, "until charger is near")
        return true
    end
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
    -- "beat" means that this cue event matches the previous event's kind,
    -- occurred on the same side, and happened within a short time window (1.25s).
    -- This typically prevents redundant cues (e.g., attack, vanish, hit, miss, etc)
    -- within the same animation "beat" or moment.
    if kind == last and (
            kind == "attack" or kind == "vanish" or kind == "emerge"
            or kind == "hit" or kind == "selfhit" or kind == "status"
            or kind == "miss" or kind == "counter" or kind == "faint" or Cues.isReactKind(kind)) then
        if opts.finishing then
            return nil
        end
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
    return kind == "dodge" or kind == "cover" or kind == "hide"
        or kind == "brace" or kind == "cast"
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
