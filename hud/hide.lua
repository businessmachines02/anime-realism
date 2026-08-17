-- HUD hide — levels, HP numbers/bars, XP strip, party/summary.
-- Dialogue chrome (speech bubbles, say wraps, overlay) stays in main.lua /
-- battle/rules/dialogue.lua + battle/chrome/bubbles.lua.
-- FIELD compact chrome lives in field/chrome/ui.lua.

local Hide = {
    hidingHud = false,
    patched = setmetatable({}, { __mode = "k" }),
    suppressingBattleHpText = false,
}

local host = {}

function Hide.bind(h)
    if type(h) == "table" then
        host = h
    end
    return Hide
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
    return true
end

local function hideAll()
    return hostCall("hideAllHud") and true or false
end

function Hide.install(mod)
    if not mod or mod._arImmersionHide then
        return true
    end
    local Font = require("src.render.Font")
    local HudTiles = require("src.render.HudTiles")
    local BattleState = require("src.battle.BattleState")
    local WideBattle
    do
        local ok, value = pcall(require, "src.battle.WideBattle")
        if ok then
            WideBattle = value
        end
    end
    local PartyMenu = require("src.ui.PartyMenu")
    local SummaryMenu = require("src.ui.SummaryMenu")
    mod._arImmersionHide = true

Hide.isDigits = function(text)
    return type(text) == "string" and text:match("^%d+$") ~= nil
end

Hide.isHpFraction = function(text)
    return type(text) == "string" and text:match("^%s*%d+%s*/%s*%d+%s*$") ~= nil
end

-- Gen 3 UI / modern overlays print "Lv.12" instead of the native <LV> tile.
Hide.isLevelTag = function(text)
    local s = tostring(text or "")
    return s:match("^[Ll][Vv]%.") ~= nil
end

Hide.isHpLabel = function(text)
    local s = tostring(text or ""):upper()
    return s == "HP" or s == "EXP"
end

Hide.wrapHudPaint = function(fn, ...)
    local prev = Hide.hidingHud
    Hide.hidingHud = true
    local ok, a, b, c = pcall(fn, ...)
    Hide.hidingHud = prev
    if not ok then
        error(a, 0)
    end
    return a, b, c
end

-- Live Font.draw lookup: native digits + "Lv." tags from UI overhaul mods.
Hide.origFontDraw = Font.draw
function Font.draw(text, x, y, ...)
    if Hide.isLevelTag(text) or Hide.isHpFraction(text) then
        return
    end
    if Hide.hidingHud and not hideAll() then
        if Hide.isDigits(text) and (y == 8 or y == 64) then
            return
        end
    end
    return Hide.origFontDraw(text, x, y, ...)
end

-- True while a patched Gen3 (etc.) battle status HUD is painting.

-- Catch TrueType love.graphics.print/printf "Lv." tags from UI overhauls.
-- HP numbers are filtered only while a battle status HUD paint is active,
-- so party/summary HP text stays visible when only HIDE BATTLE HP is on.
Hide.installLoveTextFilters = function()
    if not (love and love.graphics) or Hide.patched.__love_text then
        return
    end
    Hide.patched.__love_text = true
    local g = love.graphics
    local origPrint, origPrintf = g.print, g.printf
    function g.print(text, ...)
        if Hide.isLevelTag(text) or Hide.isHpFraction(text) or Hide.isHpLabel(text) then
            return
        end
        return origPrint(text, ...)
    end

    function g.printf(text, ...)
        if Hide.isLevelTag(text) or Hide.isHpFraction(text) or Hide.isHpLabel(text) then
            return
        end
        return origPrintf(text, ...)
    end
end

-- Table-path draws (WideBattle, party, etc.).
Hide.origHPBar = HudTiles.drawHPBar
function HudTiles.drawHPBar(data, tx, ty, mon, barType, ...)
    -- Never draw HP bars (battle, party, summary).
    return
end

Hide.origTile = HudTiles.tile
function HudTiles.tile(code, x, y, ...)
    if code == 0x6E then
        return
    end
    return Hide.origTile(code, x, y, ...)
end

Hide.origStatusTile = HudTiles.statusTile
if Hide.origStatusTile then
    function HudTiles.statusTile(code, x, y, ...)
        if code == 0x6E then
            return
        end
        return Hide.origStatusTile(code, x, y, ...)
    end
end

Hide.wrapHudDraw = function(inner)
    return function(...)
        if hideAll() then
            return
        end
        return Hide.wrapHudPaint(inner, ...)
    end
end

-- Classic BattleState caches drawHPBar/hudTile as locals. Dramatic Shape
-- also keeps an innerHUDs upvalue that bypasses later BattleState.drawHUDs
-- wraps. Patch those upvalues after every mod has installed.
Hide.patchDrawLocals = function(fn, seen)
    if type(fn) ~= "function" then
        return
    end
    if not (debug and type(debug.getupvalue) == "function"
        and type(debug.setupvalue) == "function") then
        return
    end
    seen = seen or {}
    if seen[fn] then
        return
    end
    seen[fn] = true

    local i = 1
    while true do
        local name, val = debug.getupvalue(fn, i)
        if not name then
            break
        end

        if name == "drawHPBar" and type(val) == "function" and not Hide.patched[val] then
            local wrapped = function()
                return
            end
            Hide.patched[val] = true
            Hide.patched[wrapped] = true
            debug.setupvalue(fn, i, wrapped)
        elseif name == "hudTile" and type(val) == "function" and not Hide.patched[val] then
            local wrapped = function(code, x, y, tint)
                if code == 0x6E then
                    return
                end
                return val(code, x, y, tint)
            end
            Hide.patched[val] = true
            Hide.patched[wrapped] = true
            debug.setupvalue(fn, i, wrapped)
        elseif (name == "innerHUDs" or name == "drawHUDs") and type(val) == "function" then
            if not Hide.patched[val] then
                local wrapped = Hide.wrapHudDraw(val)
                Hide.patched[val] = true
                Hide.patched[wrapped] = true
                debug.setupvalue(fn, i, wrapped)
                Hide.patchDrawLocals(val, seen)
            else
                Hide.patchDrawLocals(val, seen)
            end
        elseif type(val) == "function"
            and (name == "origHUDs" or name == "origDrawHUDs" or name == "orig") then
            -- Walk past FBV's drawHUDs wrap to the engine/DS upvalues.
            Hide.patchDrawLocals(val, seen)
        end
        i = i + 1
    end
end

Hide.installBattleDrawWrap = function()
    local current = BattleState.drawHUDs
    if Hide.patched[current] then
        Hide.patchDrawLocals(current)
        return
    end
    local wrapped = Hide.wrapHudDraw(current)
    Hide.patched[current] = true
    Hide.patched[wrapped] = true
    BattleState.drawHUDs = wrapped
    Hide.patchDrawLocals(current)
    Hide.patchDrawLocals(wrapped)
end

Hide.installWideWrap = function()
    -- Only patch WideBattle's local drawHUDs — do not wrap the whole wide
    -- draw (that would also filter the dialogue box).
    if WideBattle and type(WideBattle.draw) == "function" then
        Hide.patchDrawLocals(WideBattle.draw)
    end
end

-- Dramatic Shape snaps HUD bands + frosted panels outside drawHUDs.
Hide.installDramaticShapeHide = function()
    hostCall("onFieldInstall", mod)
end

-- Gen 3 Inspired UI (and similar) keep their own printText / HUD drawers as
-- upvalues on render.hud / battle.overlay wraps. Patch those after load so
-- "Lv." tags and status panels honor this mod's options.
Hide.patchCompatUiFn = function(fn, seen)
    if type(fn) ~= "function" or seen[fn] then
        return
    end
    if not (debug and type(debug.getupvalue) == "function"
        and type(debug.setupvalue) == "function") then
        return
    end
    seen[fn] = true
    local i = 1
    while true do
        local name, val = debug.getupvalue(fn, i)
        if not name then
            break
        end
        if type(val) == "function" and not Hide.patched[val] then
            if name == "renderHudHook" then
                -- Gen 3's battle UI is reached through a table of renderer methods,
                -- so its individual drawers are not all visible as callback upvalues.
                -- Bypass the top-level foreground pass for FIELD instead.
                local inner = val
                local wrapped = function(ownerMod, next, game, ...)
                    if hostCall("fieldBattleInGame",game) then
                        return next(game, ...)
                    end
                    return inner(ownerMod, next, game, ...)
                end
                Hide.patched[val] = true
                Hide.patched[wrapped] = true
                debug.setupvalue(fn, i, wrapped)
            elseif name == "printText" or name == "partyText" or name == "finalText" then
                local inner = val
                local wrapped = function(text, ...)
                    local s = tostring(text or "")
                    if Hide.isLevelTag(s) or Hide.isHpLabel(s) or Hide.isHpFraction(s) then
                        return
                    end
                    if Hide.suppressingBattleHpText and Hide.isHpFraction(s) then
                        return
                    end
                    return inner(text, ...)
                end
                Hide.patched[val] = true
                Hide.patched[wrapped] = true
                debug.setupvalue(fn, i, wrapped)
            elseif name == "drawDialogue"
                or name == "drawCommandMenu" or name == "drawMoveSelect" then
                -- Gen 3 Inspired UI paints its own cream dialogue panel; skip it
                -- while SPEECH BUBBLE owns the message beat.
                local inner = val
                local wrapped = function(battle, ...)
                    if hostCall("fieldCompactActive",battle) or hostCall("bubblesOwnDialogue",battle) then
                        return
                    end
                    return inner(battle, ...)
                end
                Hide.patched[val] = true
                Hide.patched[wrapped] = true
                debug.setupvalue(fn, i, wrapped)
            elseif name == "drawEnemyHUD" or name == "drawPlayerHUD" then
                local inner = val
                local wrapped = function(...)
                    local battle = select(1, ...)
                    if hostCall("fieldCompactActive",battle) or hideAll() then
                        return
                    end
                    local prev = Hide.suppressingBattleHpText
                    Hide.suppressingBattleHpText = true
                    local ok, a, b, c = pcall(inner, ...)
                    Hide.suppressingBattleHpText = prev
                    if not ok then
                        error(a, 0)
                    end
                    return a, b, c
                end
                Hide.patched[val] = true
                Hide.patched[wrapped] = true
                debug.setupvalue(fn, i, wrapped)
            elseif name == "drawStyledHP" or name == "drawPartyExpBar" then
                local wrapped = function()
                    return
                end
                Hide.patched[val] = true
                Hide.patched[wrapped] = true
                debug.setupvalue(fn, i, wrapped)
            elseif name == "partyHPBarFinal" then
                local inner = val
                local partyTextFn = nil
                for j = 1, 48 do
                    local n, v = debug.getupvalue(fn, j)
                    if n == "partyText" and type(v) == "function" then
                        partyTextFn = v
                        break
                    end
                end
                local wrapped = function(...)
                    local mon
                    for i = 1, select("#", ...) do
                        local v = select(i, ...)
                        if type(v) == "table" and v.stats and v.hp ~= nil then
                            mon = v
                            break
                        end
                    end
                    local hint = hostCall("partyRowHint",mon)
                    if hint and partyTextFn then
                        local x, y = ...
                        partyTextFn(hint, x, y - 2, 3, { 0.46, 0.14, 0.12, 1 })
                        return
                    end
                    -- Still never draw the real HP bar.
                    return
                end
                Hide.patched[val] = true
                Hide.patched[wrapped] = true
                debug.setupvalue(fn, i, wrapped)
            elseif name == "drawEXPRow" then
                local inner = val
                local wrapped = function(...)
                    if opt("hide_xp_bar") or hideAll() then
                        return
                    end
                    return inner(...)
                end
                Hide.patched[val] = true
                Hide.patched[wrapped] = true
                debug.setupvalue(fn, i, wrapped)
            else
                Hide.patchCompatUiFn(val, seen)
            end
        end
        i = i + 1
    end
end

Hide.installCompatUiOverrides = function()
    Hide.installLoveTextFilters()
    local Runtime = require("src.mods.Runtime")
    local chains = Runtime.hooks and Runtime.hooks.chains
    if type(chains) ~= "table" then
        return
    end
    local seen = {}
    for _, hookName in ipairs({ "render.hud", "battle.overlay" }) do
        local chain = chains[hookName]
        if type(chain) == "table" then
            for _, entry in ipairs(chain) do
                if entry and type(entry.callback) == "function" then
                    -- Prefer known UI overhaul owners; still walk unknown wraps that
                    -- close over printText/drawEnemyHUD.
                    if entry.owner == "gen3_battle_ui"
                        or entry.owner == nil
                        or type(entry.owner) == "string" then
                        Hide.patchCompatUiFn(entry.callback, seen)
                    end
                    -- Gen 3 UI has multiple late foreground passes. Skipping its whole
                    -- hook during FIELD is more reliable than patching individual
                    -- captured drawers, and leaves BattleState/input ownership intact.
                    local skipFieldUi = entry.owner == "gen3_battle_ui"
                        or entry.owner == "move_inspector"
                        or entry.owner == "typed_move_colors"
                    if skipFieldUi and not entry._arFieldUiSkip then
                        local inner = entry.callback
                        if hookName == "render.hud" then
                            entry.callback = function(next, game, ...)
                                if hostCall("fieldBattleInGame",game) then
                                    return next(game, ...)
                                end
                                return inner(next, game, ...)
                            end
                        else
                            entry.callback = function(next, battle, ...)
                                if hostCall("fieldCompactActive",battle) then
                                    return next(battle, ...)
                                end
                                return inner(next, battle, ...)
                            end
                        end
                        entry._arFieldUiSkip = true
                    end
                end
            end
        end
    end
end

mod.events:on("mods.loaded", function()
    Hide.installBattleDrawWrap()
    Hide.installWideWrap()
    Hide.installDramaticShapeHide()
    Hide.installCompatUiOverrides()
    hostCall("onFieldInstall", mod)
end)
mod.events:on("game.ready", function()
    Hide.installLoveTextFilters()
    Hide.installCompatUiOverrides()
    hostCall("onFieldInstall", mod)
end)
-- Hot reload / late installers.
Hide.installBattleDrawWrap()
Hide.installWideWrap()
Hide.installDramaticShapeHide()
Hide.installCompatUiOverrides()

-- Suppress the QoL thin XP rectangle (classic, wide, and Dramatic Shape).
mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle or type(battle.draw) ~= "function" or battle.__lhh_draw then
        return
    end
    local baseDraw = battle.draw
    battle.draw = function(self, ...)
        if not (opt("hide_xp_bar") or hideAll()) then
            return baseDraw(self, ...)
        end
        local g = love.graphics
        local origRect = g.rectangle
        g.rectangle = function(mode, x, y, w, h, ...)
            if mode == "fill" and type(h) == "number" and type(w) == "number"
                and h > 0 and h <= 16 and w >= 2 then
                local shot = rawget(self, "dramaticShapeShot")
                if type(shot) == "table" and type(shot.ly) == "number"
                    and type(shot.scale) == "number" and shot.scale > 0 then
                    local expY = shot.ly + 89 * shot.scale
                    if math.abs((y or 0) - expY) <= shot.scale then
                        return
                    end
                end
                -- Classic / wide QoL XP strip sits on rows 88-91.
                if (y or 0) >= 88 and (y or 0) <= 94 and h <= 4 then
                    return
                end
            end
            return origRect(mode, x, y, w, h, ...)
        end
        local ok, a, b, c = pcall(baseDraw, self, ...)
        g.rectangle = origRect
        if not ok then
            error(a, 0)
        end
        return a, b, c
    end
    battle.__lhh_draw = true
end)

-- Party menu: never show level/HP; print a heal hint on the old HP row.
Hide.origPartyDraw = PartyMenu.draw
function PartyMenu.draw(self)
    local prevDraw, prevTile = Font.draw, HudTiles.tile
    local prevHPBar = HudTiles.drawHPBar

    Font.draw = function(text, x, y, ...)
        if Hide.isLevelTag(text) or Hide.isHpFraction(text) then
            return
        end
        if Hide.isDigits(text) and (x == 104 or x == 112) and (y % 16 == 0) then
            return
        end
        return prevDraw(text, x, y, ...)
    end
    HudTiles.tile = function(code, x, y, ...)
        if code == 0x6E then
            return
        end
        return prevTile(code, x, y, ...)
    end
    HudTiles.drawHPBar = function()
        return
    end

    local ok, err = pcall(Hide.origPartyDraw, self)
    Font.draw = prevDraw
    HudTiles.tile = prevTile
    HudTiles.drawHPBar = prevHPBar
    if not ok then
        error(err, 0)
    end

    if self.tmhm then
        return
    end
    local party = self.party or (self.game.save and self.game.save.party) or {}
    love.graphics.setColor(0, 0, 0, 1)
    for i, mon in ipairs(party) do
        local hint = hostCall("partyRowHint",mon)
        if hint then
            local y = PartyMenu.entryY(i)
            prevDraw(hint, 40, y + 8)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Summary (STATS): hide level + HP bar/numbers.
Hide.origSummaryDraw = SummaryMenu.draw
function SummaryMenu.draw(self)
    local prevDraw = Font.draw
    local prevStatus = HudTiles.statusTile
    local prevTile = HudTiles.tile
    local prevHPBar = HudTiles.drawHPBar

    Font.draw = function(text, x, y, ...)
        if Hide.isLevelTag(text) or Hide.isHpFraction(text) then
            return
        end
        if Hide.isDigits(text) then
            if (y == 16 and (x == 112 or x == 120))
                or (y == 48 and (x == 128 or x == 136)) then
                return
            end
        end
        return prevDraw(text, x, y, ...)
    end
    local function hideLv(code, x, y)
        return code == 0x6E
            and ((x == 112 and y == 16) or (x == 128 and y == 48))
    end
    if prevStatus then
        HudTiles.statusTile = function(code, x, y, tint)
            if hideLv(code, x, y) then
                return
            end
            return prevStatus(code, x, y, tint)
        end
    end
    HudTiles.tile = function(code, x, y, tint)
        if hideLv(code, x, y) then
            return
        end
        return prevTile(code, x, y, tint)
    end
    HudTiles.drawHPBar = function()
        return
    end

    local ok, err = pcall(Hide.origSummaryDraw, self)
    Font.draw = prevDraw
    HudTiles.statusTile = prevStatus
    HudTiles.tile = prevTile
    HudTiles.drawHPBar = prevHPBar
    if not ok then
        error(err, 0)
    end
end

    return true
end

return Hide
