-- Battle animation policy — classic picFx vs FIELD sprite cues.
--
-- FIELD presentation lives in field/ (Cues.apply / Projectiles).
-- This module decides which layer to fire and tags engine queue rows so
-- FIELD can play them. Classic dodge/brace queue builders live here; Fx.play calls them.
-- insertBeforeAnim is still injected via Fx.bind(host).

local Fx = {}
local host = {}

function Fx.bind(h)
    if type(h) == "table" then
        host = h
    end
    return Fx
end

local function hostCall(name, ...)
    local fn = host[name]
    if type(fn) == "function" then
        return fn(...)
    end
end

local function opt(key)
    local fn = host.opt
    if type(fn) == "function" then
        return fn(key)
    end
    return false
end

local function isField(battle)
    return hostCall("isFieldBattle", battle) and true or false
end

-- Stamp an engine queue row so FIELD Cues.apply can play it.
function Fx.tag(item, side, kind, category, moveType, moveId)
    if type(item) ~= "table" or not side or not kind then
        return false
    end
    item.arFieldCue = { side = side, kind = kind }
    if category == "physical" or category == "special" then
        item.arFieldCue.category = category
    end
    item.arFieldCue.moveType = moveType
    item.arFieldCue.moveId = moveId
    if side == "enemy" and kind == "attack" then
        item.arThreatToast = true
    end
    return true
end

function Fx.tagLatest(battle, side, kind, category, moveType, moveId)
    if not (battle and battle.queue and battle.nextInsert) then
        return false
    end
    return Fx.tag(battle.queue[battle.nextInsert], side, kind, category, moveType, moveId)
end

function Fx.foeCoverCue(foeBuffs, foeLine, extra)
    extra = extra or {}
    if extra.kind == "cast" or extra.kind == "fire" then
        return {
            side = "enemy",
            kind = "cast",
            category = extra.category or "special",
            moveType = extra.moveType,
            moveId = extra.moveId,
        }
    end
    if hostCall("isDodgeFailNarrator", foeLine) then
        return { side = "enemy", kind = "hit" }
    end
    if type(foeBuffs) == "table" then
        for i = 1, #foeBuffs do
            local b = foeBuffs[i]
            if b and b.stat == "defense" then
                return { side = "enemy", kind = "brace" }
            end
            if b and b.stat == "evasion" then
                return { side = "enemy", kind = "dodge" }
            end
        end
    end
    -- Failed dodge still returns the trainer order as foeLine. Do not
    -- pose a dodge (or arm a DODGE chip) just because they were told to.
    return { side = "enemy", kind = "hit" }
end

-- Play dodge / cover / brace / entrench FX for Focus reacts.
function Fx.play(battle, action, result)
    if not battle or not opt("momentum_counter") then
        return
    end
    if isField(battle) then
        local kind = tostring(action or "")
        if kind == "dodge" or kind == "cover" or kind == "brace"
            or kind == "entrench" or kind == "entrench_hold" then
            local opts
            if kind == "dodge" and result and result.counter
                and not result.counter.deferToCall then
                opts = {
                    counterMoveId = result.counter.moveId,
                    counterMoveType = result.counter.moveType,
                    counterCategory = result.counter.category,
                }
            end
            hostCall("fieldReact", battle, "player",
                (kind == "entrench_hold" and "brace") or kind, opts)
        end
        return
    end
    action = tostring(action or "")
    result = result or {}
    local state = hostCall("momentumState", battle) or {}

    if action == "dodge" then
        if result.forceMiss then
            Fx.enqueueDodgeHideAnim(battle, {
                label = "DODGE",
                beforeAnim = true,
                stayHidden = false,
            })
        else
            hostCall("insertBeforeAnim", battle, { wait = 10, arFx = true })
            hostCall("insertBeforeAnim", battle, {
                arFx = true,
                fn = function()
                    if battle.picFxFor and battle.player then
                        local pf = battle:picFxFor(battle.player)
                        if pf then
                            pf.kind, pf.t = "blink", 0
                        end
                    end
                    if battle.fx then
                        battle.fx.shake = math.max(battle.fx.shake or 0, 10)
                    end
                end,
            })
        end
        return
    end

    if action == "cover" then
        local RD = host.RD
        if state.focusCoverSpot and RD and type(RD.sideState) == "function" then
            local rdSide = RD.sideState(battle, true)
            if rdSide and rdSide.cover then
                return
            end
        end
        local spot = hostCall("pickFocusCoverLabel", battle)
        state.focusCoverSpot = spot
        hostCall("rememberCoverSpot", battle, spot)
        local tucked = hostCall("pickCoverHideSpot", battle) and true or false
        Fx.enqueueDodgeHideAnim(battle, {
            label = spot,
            beforeAnim = true,
            stayHidden = not tucked,
        })
        hostCall("insertBeforeAnim", battle, {
            arFx = true,
            fn = function()
                if tucked then
                    hostCall("applyCoverTuckVisual", battle)
                end
                hostCall("fieldReact", battle, "player", "cover")
            end,
        })
        return
    end

    if action == "brace" then
        Fx.enqueueBraceAnim(battle, { beforeAnim = true })
        return
    end

    if action == "entrench" or action == "entrench_hold" then
        if action == "entrench" then
            Fx.enqueueBraceAnim(battle, { beforeAnim = true, entrenched = true })
        end
    end
end


local function pickLine(lines)
    if type(lines) ~= "table" then
        return nil
    end
    local n = #lines
    if n == 0 then
        return nil
    end
    local r = (love and love.math and love.math.random) or math.random
    return lines[r(n)]
end

local function canonMoveId(raw)
    local id = tostring(raw or ""):upper():gsub("%s+", "_")
    if id == "" or id == "NIL" or id == "NILL" then
        return nil
    end
    return id
end

local function battlerMoveList(battler)
    if type(battler) ~= "table" then
        return nil
    end
    if type(battler.curMoves) == "table" then
        return battler.curMoves
    end
    if battler.mon and type(battler.mon.moves) == "table" then
        return battler.mon.moves
    end
    return nil
end

local function lookupMoveDef(battle, mv)
    if type(mv) ~= "table" then
        return nil, nil
    end
    local raw = canonMoveId(mv.id or mv.name)
    if type(battle) == "table" and type(battle.moveDef) == "function" then
        local ok, def = pcall(battle.moveDef, battle, mv)
        if (not ok or type(def) ~= "table") and raw then
            ok, def = pcall(battle.moveDef, battle, { id = raw })
        end
        if ok and type(def) == "table" then
            return def, canonMoveId(def.id or raw)
        end
    end
    local dex = battle and battle.data and battle.data.moves
    if type(dex) == "table" then
        if raw and type(dex[raw]) == "table" then
            return dex[raw], canonMoveId(dex[raw].id or raw)
        end
        local want = tostring(mv.name or mv.id or ""):upper()
        if want ~= "" then
            for mid, def in pairs(dex) do
                if type(def) == "table" and tostring(def.name or ""):upper() == want then
                    return def, canonMoveId(def.id or mid)
                end
            end
        end
    end
    local found = hostCall("findMoveByName", battle, mv.id or mv.name)
    if type(found) == "table" then
        return found, canonMoveId(found.id or found.name or raw)
    end
    return nil, raw
end

local GEN1_SPECIAL = {
    FIRE = true, WATER = true, ELECTRIC = true, GRASS = true,
    ICE = true, PSYCHIC = true, DRAGON = true,
}

-- Gen 1 type-split is physical; these still fly. Match field/fx/fx_catalog.lua.
local PROJECTILE_SPECIAL = {
    SWIFT = true,
    GUST = true,
    NIGHT_SHADE = true,
    TRI_ATTACK = true,
    BONEMERANG = true,
    ROCK_THROW = true,
}

local function defIsSpecial(def, mv)
    local id = canonMoveId((def and def.id) or (mv and (mv.id or mv.name)))
    if id and PROJECTILE_SPECIAL[id] then
        return true
    end
    local cat = tostring((def and def.category) or (mv and mv.category) or ""):lower()
    if cat == "special" then
        return true
    end
    if cat == "physical" or cat == "status" then
        return false
    end
    local typ = tostring((def and def.type) or (mv and mv.type) or ""):upper()
    return GEN1_SPECIAL[typ] == true
end

local function isRangedSpecial(battle, def, mv, id)
    local opts = {
        moveId = id,
        moveType = (def and def.type) or (mv and mv.type),
        category = (def and def.category) or (mv and mv.category),
    }
    local flagged = hostCall("isRangedCounter", battle, opts)
    if flagged ~= nil then
        return flagged == true
    end
    if not defIsSpecial(def, mv) then
        return false
    end
    -- Contact punches stay melee even when the type looks special.
    if id and id:find("PUNCH", 1, true) then
        return false
    end
    return true
end

-- Damaging ranged specials this battler can still fire (PP left).
function Fx.listFireNowMoves(battle, battler)
    if type(battler) ~= "table" then
        battler = battle and battle.player
    end
    local out = {}
    local moves = battlerMoveList(battler)
    if type(moves) ~= "table" then
        return out
    end
    for i = 1, #moves do
        local mv = moves[i]
        if mv and not mv.struggle and (mv.pp == nil or mv.pp > 0) then
            local def, id = lookupMoveDef(battle, mv)
            if not id then
                id = canonMoveId(mv.id or mv.name)
            end
            local power = tonumber(def and def.power) or tonumber(mv.power) or 0
            local category = tostring((def and def.category) or mv.category or ""):lower()
            if id and power > 0 and category ~= "status"
                and isRangedSpecial(battle, def, mv, id) then
                out[#out + 1] = {
                    label = tostring((def and def.name) or mv.name or id),
                    hint = (mv.pp ~= nil) and ("PP " .. tostring(mv.pp)) or "Special now",
                    moveInst = mv,
                    moveDef = def,
                    moveId = id,
                    name = (def and def.name) or mv.name or id,
                    moveType = (def and def.type) or mv.type,
                    category = "special",
                }
            end
        end
    end
    return out
end

-- Counter clip for the battler that is actually striking (you or the foe).
-- Flavor lists only rank moves they already know — never a dex punch
-- like MEGA_PUNCH / HEADBUTT that nobody on the field has.
function Fx.pickCounterStrikeMove(battle, kind, battler, incoming)
    kind = tostring(kind or "")
    if type(battler) ~= "table" then
        battler = battle and battle.player
    end
    local function incomingOpts()
        if type(incoming) ~= "table" then
            return nil
        end
        return {
            moveId = incoming.id or incoming.moveId,
            moveType = incoming.type or incoming.moveType,
            category = incoming.category,
        }
    end
    local function incomingMelee()
        local opts = incomingOpts()
        if not opts then
            return false
        end
        local id = canonMoveId(opts.moveId)
        if id and PROJECTILE_SPECIAL[id] then
            return false
        end
        local melee = hostCall("isMeleeAttack", battle, opts)
        if melee ~= nil then
            return melee == true
        end
        local cat = tostring(opts.category or ""):lower()
        if cat == "physical" then
            return true
        end
        if cat == "special" or cat == "status" then
            return false
        end
        local typ = tostring(opts.moveType or ""):upper()
        if typ == "" then
            return false
        end
        return not GEN1_SPECIAL[typ]
    end
    local function incomingRanged()
        local opts = incomingOpts()
        if not opts then
            return false
        end
        local id = canonMoveId(opts.moveId)
        if id and PROJECTILE_SPECIAL[id] then
            return true
        end
        local ranged = hostCall("isRangedCounter", battle, opts)
        if ranged ~= nil then
            return ranged == true
        end
        local cat = tostring(opts.category or ""):lower()
        if cat == "special" then
            return true
        end
        return false
    end
    local byKind = {
        dodge = { "QUICK_ATTACK", "TACKLE", "POUND", "SCRATCH", "DOUBLE_KICK" },
        brace = { "MEGA_PUNCH", "TACKLE", "STRENGTH", "HEADBUTT", "BODY_SLAM", "POUND", "SCRATCH" },
        entrench = { "TACKLE", "HEADBUTT", "POUND", "MEGA_PUNCH", "SCRATCH" },
    }
    local specialFlavor = {
        "THUNDERBOLT", "THUNDERSHOCK", "EMBER", "FLAMETHROWER",
        "WATER_GUN", "BUBBLEBEAM", "SURF", "PSYBEAM", "PSYCHIC",
        "ICE_BEAM", "AURORABEAM", "MEGA_DRAIN", "SOLARBEAM",
        "SWIFT",
    }
    local flavor = byKind[kind] or byKind.brace
    local physical, specials, any = {}, {}, {}
    local known = {}
    local moves = battlerMoveList(battler)
    if type(moves) == "table" then
        for i = 1, #moves do
            local mv = moves[i]
            if mv and not mv.struggle then
                local def, id = lookupMoveDef(battle, mv)
                if not id then
                    id = canonMoveId(mv.id or mv.name)
                end
                local power = tonumber(def and def.power) or tonumber(mv.power) or 0
                local category = tostring((def and def.category) or mv.category or ""):lower()
                if id and power > 0 and category ~= "status" then
                    known[id] = true
                    any[#any + 1] = id
                    if defIsSpecial(def, mv) then
                        specials[#specials + 1] = id
                    else
                        physical[#physical + 1] = id
                    end
                end
            end
        end
    end
    local function firstKnown(list)
        if type(list) ~= "table" then
            return nil
        end
        for i = 1, #list do
            local id = list[i]
            if known[id] then
                return id
            end
        end
        return nil
    end
    -- Charge in your face: physical rebound so the counter pose reads.
    -- Far special / projectile: only a shot back — no melee jab across the pad.
    if kind == "dodge" and incomingMelee() then
        return firstKnown(flavor) or physical[1]
            or firstKnown(specialFlavor) or specials[1] or any[1]
    end
    if incomingRanged() then
        return firstKnown(specialFlavor) or specials[1]
    end
    if kind == "dodge" then
        return firstKnown(flavor) or physical[1] or any[1]
    end
    return firstKnown(flavor) or physical[1] or any[1]
end

-- Pick a Gen1 move id that exists in this battle's data.
function Fx.pickHideMoveAnim(battle, candidates)
    local moves = battle and battle.data and battle.data.moves
    if type(moves) ~= "table" or type(candidates) ~= "table" then
        return nil
    end
    local ok = {}
    for i = 1, #candidates do
        local id = candidates[i]
        if type(id) == "string" and moves[id] then
            ok[#ok + 1] = id
        end
    end
    if #ok == 0 then
        return nil
    end
    return pickLine(ok) or ok[1]
end

-- Dig/Fly/leaf/surf-style hides: picFx motion + thematic move anim.
function Fx.dodgeAnimSpec(choice, battle)
    local label = ""
    if type(choice) == "table" then
        label = tostring(choice.label or ""):upper()
    elseif type(choice) == "string" then
        label = choice:upper()
    end
    -- STAY re-hide / auto path: reuse the remembered cover spot.
    if label == "" and battle then
        local st = hostCall("momentumState", battle)
        if st and st.temp and st.temp.coverSpot then
            label = tostring(st.temp.coverSpot):upper()
        end
    end
    local spec = {
        pic = "slideDownHide",
        wait = 20,
        moves = { "DIG", "SLIDE_DOWN_ANIM", "DOUBLE_TEAM" },
        emerge = { "DIG", "QUICK_ATTACK" },
    }
    local byLabel = {
        ["FLY UP"] = {
            pic = "slideUp",
            wait = 18,
            moves = { "FLY", "GUST", "WING_ATTACK", "SKY_ATTACK", "DRILL_PECK" },
            emerge = { "FLY", "GUST", "WING_ATTACK" },
        },
        ["ZIP"] = {
            pic = "slideOff",
            wait = 20,
            moves = { "THUNDERBOLT", "THUNDER_WAVE", "QUICK_ATTACK", "FLASH" },
            emerge = { "THUNDERBOLT", "QUICK_ATTACK" },
        },
        ["BURST"] = {
            pic = "bounce",
            wait = 28,
            moves = { "FLAMETHROWER", "FIRE_BLAST", "FIRE_SPIN", "EMBER", "SMOKESCREEN" },
            emerge = { "EMBER", "FLAMETHROWER" },
        },
        ["FADE"] = {
            pic = "blink",
            wait = 26,
            moves = { "TELEPORT", "NIGHT_SHADE", "CONFUSE_RAY", "LICK" },
            emerge = { "TELEPORT", "NIGHT_SHADE" },
        },
        ["SENSE"] = {
            pic = "blink",
            wait = 22,
            moves = { "PSYCHIC", "CONFUSION", "TELEPORT", "DISABLE" },
            emerge = { "PSYCHIC", "TELEPORT" },
        },
        ["DIVE"] = {
            pic = "slideDown",
            wait = 22,
            moves = { "SURF", "WATERFALL", "BUBBLEBEAM", "CLAMP", "WITHDRAW" },
            emerge = { "SURF", "WATERFALL", "BUBBLEBEAM" },
        },
        ["SPLASH"] = {
            pic = "slideDown",
            wait = 20,
            moves = { "SURF", "WATER_GUN", "BUBBLE", "BUBBLEBEAM" },
            emerge = { "SURF", "WATER_GUN" },
        },
        ["SHORE"] = {
            pic = "slideHalf",
            wait = 18,
            moves = { "SURF", "WATER_GUN", "SAND_ATTACK" },
            emerge = { "WATER_GUN", "QUICK_ATTACK" },
        },
        ["GRASS"] = {
            pic = "slideDownHide",
            wait = 20,
            moves = { "RAZOR_LEAF", "VINE_WHIP", "PETAL_DANCE", "LEECH_SEED", "SLEEP_POWDER" },
            emerge = { "RAZOR_LEAF", "VINE_WHIP", "PETAL_DANCE" },
        },
        ["BRUSH"] = {
            pic = "slideDownHide",
            wait = 20,
            moves = { "RAZOR_LEAF", "VINE_WHIP", "PETAL_DANCE", "STUN_SPORE" },
            emerge = { "RAZOR_LEAF", "VINE_WHIP" },
        },
        ["TREE"] = {
            pic = "slideHalf",
            wait = 18,
            moves = { "RAZOR_LEAF", "VINE_WHIP", "LEECH_SEED", "FLY" },
            emerge = { "RAZOR_LEAF", "FLY" },
        },
        ["ROCK"] = {
            pic = "slideHalf",
            wait = 18,
            moves = { "DIG", "ROCK_SLIDE", "ROCK_THROW", "STRENGTH" },
            emerge = { "DIG", "ROCK_THROW" },
        },
        ["STONE"] = {
            pic = "slideHalf",
            wait = 18,
            moves = { "DIG", "ROCK_THROW", "HARDEN" },
            emerge = { "DIG", "ROCK_THROW" },
        },
        ["LEDGE"] = {
            pic = "slideUp",
            wait = 16,
            moves = { "DIG", "QUICK_ATTACK", "STRENGTH" },
            emerge = { "DIG", "QUICK_ATTACK" },
        },
        ["CLIFF"] = {
            pic = "slideUp",
            wait = 18,
            moves = { "FLY", "DIG", "STRENGTH", "ROCK_SLIDE" },
            emerge = { "FLY", "DIG" },
        },
        ["CART"] = {
            pic = "slideOff",
            wait = 20,
            moves = { "QUICK_ATTACK", "DOUBLE_TEAM", "SMOKESCREEN" },
            emerge = { "QUICK_ATTACK", "DOUBLE_TEAM" },
        },
        ["ALLEY"] = {
            pic = "slideOff",
            wait = 20,
            moves = { "SMOKESCREEN", "DOUBLE_TEAM", "QUICK_ATTACK", "TOXIC" },
            emerge = { "SMOKESCREEN", "QUICK_ATTACK" },
        },
        ["PATH"] = {
            pic = "slideOff",
            wait = 18,
            moves = { "QUICK_ATTACK", "DOUBLE_TEAM", "AGILITY", "SAND_ATTACK" },
            emerge = { "QUICK_ATTACK", "AGILITY" },
        },
        ["SHADOW"] = {
            pic = "blink",
            wait = 24,
            moves = { "NIGHT_SHADE", "CONFUSE_RAY", "LICK", "TELEPORT" },
            emerge = { "NIGHT_SHADE", "TELEPORT" },
        },
        ["PILLAR"] = {
            pic = "slideHalf",
            wait = 18,
            moves = { "BARRIER", "LIGHT_SCREEN", "REFLECT", "HARDEN" },
            emerge = { "BARRIER", "QUICK_ATTACK" },
        },
        ["COURT"] = {
            pic = "slideOff",
            wait = 16,
            moves = { "QUICK_ATTACK", "DOUBLE_TEAM", "AGILITY" },
            emerge = { "QUICK_ATTACK" },
        },
        ["WALL"] = {
            pic = "slideHalf",
            wait = 18,
            moves = { "BARRIER", "REFLECT", "HARDEN" },
            emerge = { "BARRIER", "QUICK_ATTACK" },
        },
        ["COVER"] = {
            pic = "slideDownHide",
            wait = 20,
            moves = { "DOUBLE_TEAM", "MINIMIZE", "DIG", "HARDEN" },
            emerge = { "DOUBLE_TEAM", "DIG" },
        },
        ["DODGE"] = {
            pic = "slideOff",
            wait = 14,
            moves = { "QUICK_ATTACK", "DOUBLE_TEAM" },
            emerge = { "QUICK_ATTACK" },
        },
    }
    if byLabel[label] then
        spec = byLabel[label]
    elseif label == "" and battle then
        local types = (hostCall("playerTypeSet", battle) or {})
        if types.FLYING then
            spec = byLabel["FLY UP"]
        elseif types.WATER then
            spec = byLabel["DIVE"]
        elseif types.GRASS then
            spec = byLabel["GRASS"]
        elseif types.GHOST or types.PSYCHIC then
            spec = byLabel["FADE"]
        elseif types.FIRE then
            spec = byLabel["BURST"]
        elseif types.ELECTRIC then
            spec = byLabel["ZIP"]
        end
    end
    return spec, label
end

local function insertQueueAfter(battle, item)
    battle.nextInsert = (battle.nextInsert or 0) + 1
    table.insert(battle.queue, battle.nextInsert, item)
end

function Fx.enqueueDodgeHideAnim(battle, choice)
    if type(battle) ~= "table" or type(battle.queue) ~= "table" then
        return
    end
    local beforeAnim = type(choice) == "table" and choice.beforeAnim == true
    local stayHidden = not (type(choice) == "table" and choice.stayHidden == false)
    local state = hostCall("momentumState", battle)
    if stayHidden then
        state.temp.picHidden = true
    end
    -- FIELD combat: OW sprite tuck behind real props. Skip Dig/Fly/etc.
    -- thematic anims that stamp cover shapes onto the map stage.
    if isField(battle) then
        return
    end
    if battle.animationsOn and not battle:animationsOn() then
        local player = battle.player
        if stayHidden and player and battle.picFxFor then
            local pf = battle:picFxFor(player)
            if pf then
                pf.kind, pf.hidden = nil, true
            end
        end
        return
    end
    local spec, label = Fx.dodgeAnimSpec(choice, battle)
    local moveId = spec.move or Fx.pickHideMoveAnim(battle, spec.moves)
    local items = {}
    -- 1) Kick a picFx so the mon visibly ducks / flies / fades.
    items[#items + 1] = {
        arFx = true,
        fn = function()
            if not battle.picFxFor or not battle.player then
                return
            end
            local pf = battle:picFxFor(battle.player)
            if not pf then
                return
            end
            pf.kind, pf.t = spec.pic, 0
            pf.hidden, pf.ox, pf.oy = nil, 0, 0
            if battle.fx then
                battle.fx.shake = math.max(battle.fx.shake or 0, 8)
            end
        end,
    }
    -- 2) Let the picFx play out.
    items[#items + 1] = { wait = spec.wait or 18, arFx = true }
    -- 3) Thematic move anim (FLY / RAZOR_LEAF / DIG / SURF / …).
    if moveId and battle.data and battle.data.moves and battle.data.moves[moveId] then
        items[#items + 1] = {
            anim = moveId,
            attackerIsPlayer = true,
            arFx = true,
        }
        hostCall("log", battle, "HIDE anim",
            tostring(label or "?") .. "→" .. tostring(moveId))
    end
    -- 4) Stay hidden in cover afterward (or clear for a brief sidestep).
    items[#items + 1] = {
        arFx = true,
        fn = function()
            if not battle.picFxFor or not battle.player then
                return
            end
            local pf = battle:picFxFor(battle.player)
            if not pf then
                return
            end
            pf.kind, pf.t = nil, nil
            pf.ox, pf.oy = 0, 0
            if stayHidden then
                pf.hidden = true
            else
                pf.hidden = nil
                if state.temp then
                    state.temp.picHidden = false
                end
            end
        end,
    }

    if beforeAnim then
        for i = #items, 1, -1 do
            hostCall("insertBeforeAnim", battle, items[i])
        end
    else
        for i = 1, #items do
            insertQueueAfter(battle, items[i])
        end
    end
end

function Fx.enqueueBraceAnim(battle, opts)
    if type(battle) ~= "table" or type(battle.queue) ~= "table" then
        return
    end
    opts = opts or {}
    -- FIELD: brace is the OW sprite crouch — skip classic BARRIER/etc. FX.
    if isField(battle) then
        return
    end
    local foeSide = opts.foe == true
    local side = foeSide and battle.enemy or battle.player
    if not side then
        return
    end
    if battle.animationsOn and not battle:animationsOn() then
        return
    end

    local entrenched = opts.entrenched == true
    -- Classic status anims that read as "toughen up" / shell / barrier.
    -- Picked at random so brace/entrench don't always look identical.
    local movePool = entrenched and {
        "BARRIER", "ACID_ARMOR", "HARDEN", "WITHDRAW", "DEFENSE_CURL", "REFLECT",
    } or {
        "HARDEN", "WITHDRAW", "DEFENSE_CURL", "MEDITATE", "BIDE",
        "BARRIER", "ACID_ARMOR",
    }
    local picPool = {
        { pic = "blink",     wait = 10 },
        { pic = "bounce",    wait = 14 },
        { pic = "slideHalf", wait = 12 },
        { pic = "blink",     wait = 8, follow = "bounce", followWait = 12 },
    }
    local moveId = pickLine(movePool)
    local pic = pickLine(picPool) or picPool[1]
    local wait = pic.wait or 12
    if entrenched then
        wait = wait + 6
    end
    local shake = entrenched and 14 or 10

    local items = {}
    items[#items + 1] = {
        arFx = true,
        fn = function()
            if not battle.picFxFor then
                return
            end
            local battler = foeSide and battle.enemy or battle.player
            if not battler then
                return
            end
            local pf = battle:picFxFor(battler)
            if pf then
                pf.kind, pf.t = pic.pic, 0
                pf.hidden = nil
            end
            if battle.fx then
                battle.fx.shake = math.max(battle.fx.shake or 0, shake)
            end
        end,
    }
    items[#items + 1] = { wait = wait, arFx = true }
    if pic.follow then
        items[#items + 1] = {
            arFx = true,
            fn = function()
                if not battle.picFxFor then
                    return
                end
                local battler = foeSide and battle.enemy or battle.player
                if not battler then
                    return
                end
                local pf = battle:picFxFor(battler)
                if pf then
                    pf.kind, pf.t = pic.follow, 0
                end
            end,
        }
        items[#items + 1] = { wait = pic.followWait or 12, arFx = true }
    end
    if moveId and battle.data and battle.data.moves and battle.data.moves[moveId] then
        items[#items + 1] = {
            anim = moveId,
            attackerIsPlayer = not foeSide,
            arFx = true,
        }
    end
    -- Clear leftover picFx so the real attack reads cleanly.
    items[#items + 1] = {
        arFx = true,
        fn = function()
            if not battle.picFxFor then
                return
            end
            local battler = foeSide and battle.enemy or battle.player
            if not battler then
                return
            end
            local pf = battle:picFxFor(battler)
            if pf and (pf.kind == pic.pic or pf.kind == pic.follow) then
                pf.kind, pf.t = nil, nil
            end
        end,
    }

    if opts.beforeAnim then
        -- insertBeforeAnim prepends at the anim index; reverse so order stays.
        for i = #items, 1, -1 do
            hostCall("insertBeforeAnim", battle, items[i])
        end
    else
        for i = 1, #items do
            insertQueueAfter(battle, items[i])
        end
    end
end


return Fx
