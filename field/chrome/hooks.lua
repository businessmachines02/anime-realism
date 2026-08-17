-- Field battle — BattleState presentation hooks + events + standalone intercept.
--
-- Responsibilities:
--   • Suppress classic move paint; FIELD FX come from projectiles.lua
--   • Drive present-clock ticks so idle bob keeps moving under menus
--   • FIELD input UX on top of vanilla BattleState phases:
--       - Start on FIGHT / PKMN / ITEM / RUN until the player picks FIGHT
--       - After FIGHT, keep opening the move diamond each turn until PAUSE
--       - B = PAUSE back to the command menu (clears move latch)
--       - While ENTRENCHED, stay on command so FIGHT opens HOLD/BREAK
--       - U/R/L/D instantly cast that slot (inject A) while on the diamond
--   • Redraw compact UI last so Move Inspector / typed-move panels cannot cover it
--   • Forward battle.* cues into Lifecycle / Cues / Projectiles
--
-- Install is idempotent via _arFbv* guards; bump the update guard when the
-- BattleState:update wrap must replace an older FIELD wrap after hot reload.

local Hooks = {}

-- Classic BattleState paints the field as a 160×144 white fill, then flashes
-- the same rect at ~0.85 alpha for hit / attack programs. Over a white field
-- that reads as a flash; over the live map it is a white overlay. Compact
-- FIELD boxes are smaller than the frame, so they stay visible.
--
-- Returns "clear" (opaque: also wipe bg/wave canvases), "drop", or false.
function Hooks.shouldDropFieldFill(mode, x, y, w, h, r, gr, b, a)
    if mode ~= "fill" or x ~= 0 or y ~= 0 or w ~= 160 or h ~= 144 then
        return false
    end
    if type(r) ~= "number" or type(gr) ~= "number" or type(b) ~= "number" then
        return false
    end
    if r <= 0.99 or gr <= 0.99 or b <= 0.99 then
        return false
    end
    if a == nil or a > 0.99 then
        return "clear"
    end
    return "drop"
end

-- Fainted / empty HP / send-out: PKMN must be reachable. The sticky move
-- diamond (B PAUSE) must not sit on top of the party switch.
function Hooks.playerMustSwitch(battle)
    if not battle then
        return false
    end
    if battle.sendingOut then
        return true
    end
    local p = battle.player
    if not p then
        return false
    end
    local hp = (p.mon and p.mon.hp) or p.hp
    if type(hp) == "number" and hp <= 0 then
        return true
    end
    local shown = p.shownHP
    if type(shown) == "number" and shown <= 0 then
        return true
    end
    return false
end

-- Foe fainted / empty bar: do not reopen the move diamond over "fainted!".
function Hooks.foeIsDown(battle)
    if not battle then
        return false
    end
    local e = battle.enemy
    if not e then
        return false
    end
    local hp = (e.mon and e.mon.hp) or e.hp
    if type(hp) == "number" and hp <= 0 then
        return true
    end
    local shown = e.shownHP
    if type(shown) == "number" and shown <= 0 then
        return true
    end
    return false
end

-- B on the move diamond (or the sticky command frame before it reopens)
-- pauses back to FIGHT/PKMN/ITEM/RUN. Mobile virtual pads have B; they
-- do not have Right Shift. Dialogue B (toast pause) stays on messages.
function Hooks.fieldPausePressed(input, battle)
    if not input or type(input.wasPressed) ~= "function" then
        return false
    end
    local phase = battle and battle.phase
    if phase ~= "moveSelect"
        and not (phase == "menu" and battle._arFieldPreferMoves) then
        return false
    end
    return input:wasPressed("b") == true
end

-- Apply PAUSE: leave the diamond, clear the sticky move latch, hold command.
-- Returns true when a pause actually happened this call.
function Hooks.applyFieldPause(battle)
    if not battle then
        return false
    end
    if battle.phase == "moveSelect" then
        battle.phase = "menu"
        battle.menuIndex = battle.menuIndex or 1
        battle.moveSwapIndex = nil
        battle._arFieldPreferMoves = nil
        battle._arFieldCommandHold = true
        return true
    end
    if battle.phase == "menu" and battle._arFieldPreferMoves then
        battle._arFieldPreferMoves = nil
        battle._arFieldCommandHold = true
        return true
    end
    return false
end

function Hooks.install(FBV, mod)
    if not mod then
        return false
    end
    mod._arFieldBattleViewerInstalled = true

    local Compat = FBV and FBV.Compat
    local function isFieldBattle(self)
        if Compat and type(Compat.isFieldBattle) == "function" then
            return Compat.isFieldBattle(self, FBV, mod)
        end
        if not self then
            return false
        end
        if self._arAnimeField or self._arFieldCombat or self._arFieldStandalone then
            return true
        end
        return FBV and mod and type(FBV.shouldUse) == "function"
            and FBV.shouldUse(mod, self)
    end

    if FBV and FBV.Intercept and type(FBV.Intercept.install) == "function" then
        pcall(FBV.Intercept.install, FBV, mod)
    end

    if Compat and type(Compat.suppressDramaticShape) == "function" then
        pcall(Compat.suppressDramaticShape, FBV, mod)
    end
    if FBV and FBV.Audio and type(FBV.Audio.installEngineMute) == "function" then
        pcall(FBV.Audio.installEngineMute)
    end
    FBV.suppressForeignStages = function()
        if Compat and type(Compat.suppressDramaticShape) == "function" then
            Compat.suppressDramaticShape(FBV, mod)
        end
    end

    local function focusEntrenched(battle)
        -- Entrench used to eat PreferMoves attacks via executeAction → holdPosition.
        -- We still avoid auto-opening the diamond so FIGHT can show ENTRENCH!.
        local RD = FBV and FBV.ReactiveDefense
        if not (RD and type(RD.sideState) == "function" and battle) then
            return false
        end
        local ok, side = pcall(RD.sideState, battle, true)
        return ok and side and side.entrenched == true and (side.entrenchTurns or 0) > 0
    end

    local ctx = {
        isFieldBattle = isFieldBattle,
        focusEntrenched = focusEntrenched,
    }
    if type(Hooks.installDraw) == "function" then
        Hooks.installDraw(FBV, mod, ctx)
    end
    if type(Hooks.installInput) == "function" then
        Hooks.installInput(FBV, mod, ctx)
    end
    if type(Hooks.installEvents) == "function" then
        Hooks.installEvents(FBV, mod, ctx)
    end

    return true
end

return Hooks
