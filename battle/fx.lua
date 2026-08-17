-- Battle animation policy — classic picFx vs FIELD sprite cues.
--
-- FIELD presentation lives in field/ (Cues.apply / Projectiles).
-- This module decides which layer to fire and tags engine queue rows so
-- FIELD can play them. Classic dodge/brace queue helpers stay in main.lua
-- and are injected via Fx.bind(host).

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

function Fx.foeCoverCue(foeBuffs, foeLine)
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
    return { side = "enemy", kind = "dodge" }
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
            hostCall("fieldReact", battle, "player",
                (kind == "entrench_hold" and "brace") or kind)
        end
        return
    end
    action = tostring(action or "")
    result = result or {}
    local state = hostCall("momentumState", battle) or {}

    if action == "dodge" then
        if result.forceMiss then
            hostCall("enqueueDodgeHideAnim", battle, {
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
        hostCall("enqueueDodgeHideAnim", battle, {
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
        hostCall("enqueueBraceAnim", battle, { beforeAnim = true })
        return
    end

    if action == "entrench" or action == "entrench_hold" then
        if action == "entrench" then
            hostCall("enqueueBraceAnim", battle, { beforeAnim = true, entrenched = true })
        end
    end
end

return Fx
