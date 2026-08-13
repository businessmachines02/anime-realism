-- Field battle — compact reference-style chrome (draw-only).
--
-- BattleState still owns phases, cursors, input, and turn resolution.
-- This module only paints:
--   menu         → FIGHT / PKMN / ITEM / RUN (or Safari set)
--   moveSelect   → diamond U/R/L/D move compass (opaque wipe covers TYPE/PP)
--   messages     → fallback dialogue box when speech toasts are not active
--
-- World-anchored HP bars are painted from UI.draw (battle overlay) so they
-- still show when the voxel pass skips entity draw().
--
-- Instant-cast / PAUSE latch live in hooks.lua, not here.


-- print("[anime_realism] ui.lua loaded @ " .. tostring(os.time()))

local UI = {}

UI.WIDTH = 160
UI.HEIGHT = 144

local function font()
    local ok, Font = pcall(require, "src.render.Font")
    return ok and Font or nil
end

local function clamp01(n)
    n = tonumber(n) or 0
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local function battlerHP(battler)
    local mon = battler and battler.mon
    local maxHP = mon and mon.stats and tonumber(mon.stats.hp) or 1
    local hp = tonumber(battler and battler.shownHP) or tonumber(mon and mon.hp) or 0
    return clamp01(hp / math.max(1, maxHP))
end

local function fitText(Font, value, maxWidth)
    local text = tostring(value or "POKéMON")
    if not (Font and type(Font.width) == "function") then
        return text
    end
    if Font.width(text) <= maxWidth then
        return text
    end
    while #text > 1 and Font.width(text .. "+") > maxWidth do
        text = text:sub(1, -2)
    end
    return text .. "+"
end

local function box(g, x, y, w, h)
    g.setColor(0.96, 0.92, 0.82, 0.96)
    g.rectangle("fill", x, y, w, h)
    g.setColor(0.10, 0.07, 0.06, 1)
    g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
    if w > 3 and h > 3 then
        g.rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3)
    end
end

local function hpBar(g, x, y, w, ratio)
    ratio = clamp01(ratio)
    g.setColor(0.12, 0.09, 0.08, 1)
    g.rectangle("fill", x, y, w, 4)
    g.setColor(0.96, 0.92, 0.78, 1)
    g.rectangle("fill", x + 1, y + 1, w - 2, 2)
    local fill = math.floor((w - 2) * ratio + 0.5)
    if fill > 0 then
        if ratio <= 0.2 then
            g.setColor(0.78, 0.18, 0.12, 1)
        elseif ratio <= 0.5 then
            g.setColor(0.88, 0.62, 0.12, 1)
        else
            g.setColor(0.20, 0.62, 0.24, 1)
        end
        g.rectangle("fill", x + 1, y + 1, fill, 2)
    end
end

function UI.active(battle)
    return battle ~= nil
        and (battle._arAnimeField or battle._arFieldCombat or battle._arFieldStandalone)
end

function UI.layoutState(battle)
    local phase = battle and battle.phase or ""
    return {
        phase = phase,
        showHUD = false,
        showCommand = phase == "menu",
        showMoves = phase == "moveSelect" or phase == "mimicSelect",
        showDialogue = phase == "messages" and not battle._arFieldBubbleDialogue,
        menuIndex = battle and battle.menuIndex or 1,
        moveIndex = phase == "mimicSelect"
            and (battle and battle.mimicIndex or 1)
            or (battle and battle.moveIndex or 1),
    }
end

local function fieldEntity(battle, side)
    local ow = battle and battle.game and battle.game.overworld
    for i = 1, #(ow and ow.entities or {}) do
        local ent = ow.entities[i]
        if ent and ent._arFieldBattler and ent._arFieldSide == side
            and not ent.hidden and not ent._removed then
            return ent
        end
    end
    return nil
end

local function drawWorldHP(g, battle)
    local ow = battle and battle.game and battle.game.overworld
    local cam = ow and ow.camera
    if not cam then return end
    for _, item in ipairs({
        { side = "player", battler = battle.player },
        { side = "enemy",  battler = battle.enemy },
    }) do
        local ent = fieldEntity(battle, item.side)
        if ent then
            local x = math.floor((ent.px or 0) - (cam.x or 0) + 8.5)
            local y = math.floor((ent.py or 0) - (cam.y or 0) - 5.5)
            x = math.max(12, math.min(148, x))
            y = math.max(3, math.min(136, y))
            hpBar(g, x - 11, y, 22, battlerHP(item.battler))
            -- Tiny downward pointer keeps the bar visually attached to its Pokémon.
            g.setColor(0.12, 0.09, 0.08, 1)
            g.polygon("fill", x - 1, y + 4, x + 1, y + 4, x, y + 6)
        end
    end
end

local function drawScaled(g, Font, text, x, y, scale)
    if not (Font and type(Font.draw) == "function") then return end
    g.push()
    g.translate(x, y)
    g.scale(scale, scale)
    Font.draw(text, 0, 0)
    g.pop()
end

local function drawCodeScaled(g, Font, code, x, y, scale)
    if not (Font and type(Font.drawCode) == "function") then return end
    g.push()
    g.translate(x, y)
    g.scale(scale, scale)
    Font.drawCode(code, 0, 0)
    g.pop()
end

local function commandLabels(battle)
    if battle and battle.safari then
        return { "BALL", "BAIT", "ROCK", "RUN" }
    end
    return { "FIGHT", "PKMN", "ITEM", "RUN" }
end

local function drawCommand(g, Font, battle)
    -- Draws FIGHT/PKMN/ITEM/RUN at the panel corners: TL, TR, BL, BR.
    local x, y, w, h = 54, 100, 128, 36
    box(g, x, y, w, h)
    local labels = commandLabels(battle)
    local index = math.max(1, math.min(4, battle.menuIndex or 1))
    local scale = 0.90

    -- Panel corners for each label
    -- Move top right and bottom right even more inward (increase sidePad so text is less far right)
    local sidePad = 32
    local panel = {
        { tx = x + 12,          ty = y + 9 },      -- Top left     (label 1)
        { tx = x + w - sidePad, ty = y + 9 },      -- Top right    (label 2)
        { tx = x + 12,          ty = y + h - 11 }, -- Bottom left  (label 3)
        { tx = x + w - sidePad, ty = y + h - 11 }, -- Bottom right (label 4)
    }

    for i = 1, 4 do
        local tx = panel[i].tx
        local ty = panel[i].ty
        if Font and type(Font.draw) == "function" then
            g.setColor(0.08, 0.06, 0.05, 1)
            g.push()
            g.translate(tx, ty)
            g.scale(scale, scale)
            -- Text anchor: align left for TL/BL, right for TR/BR
            if i == 2 or i == 4 then
                -- Move left for right alignment
                local label = labels[i] or ""
                local textWidth = Font.getWidth and Font.getWidth(label) or (#label * 8)
                g.translate(-textWidth, 0)
            end
            Font.draw(labels[i], 0, 0)
            g.pop()
        end
        if i == index then
            -- Slightly to left for TL/BL, rightward for TR/BR
            local selX = tx
            if i == 2 or i == 4 then
                local label = labels[i] or ""
                local textWidth = Font.getWidth and Font.getWidth(label) or (#label * 8)
                selX = tx - textWidth
                drawCodeScaled(g, Font, 0xED, selX - 14, ty, 0.9)
            else
                drawCodeScaled(g, Font, 0xED, selX - 14, ty, 0.9)
            end
        end
    end
end

local function moveRows(battle)
    if battle.phase == "mimicSelect" then
        return battle.mimicMoves or {}
    end
    return battle.player and battle.player.curMoves or {}
end

local function moveName(battle, move)
    if not move then return "-" end
    local def = battle.data and battle.data.moves and battle.data.moves[move.id]
    return def and def.name or tostring(move.id or "-")
end

local function drawMoves(g, Font, battle)
    -- Diamond compass: direction matches slot. Opaque panel covers TYPE/PP ghosts.
    --   U = 1, R = 2, L = 3, D = 4
    local rows = moveRows(battle)
    local index = battle.phase == "mimicSelect"
        and (battle.mimicIndex or 1) or (battle.moveIndex or 1)
    local slots = {
        { i = 1, label = "U", x = 44, y = 92 },
        { i = 2, label = "R", x = 84, y = 106 },
        { i = 3, label = "L", x = 4,  y = 106 },
        { i = 4, label = "D", x = 44, y = 120 },
    }
    g.setColor(0.96, 0.92, 0.82, 1)
    g.rectangle("fill", 0, 64, 160, 80)
    g.setColor(0.10, 0.07, 0.06, 1)
    g.rectangle("line", 0.5, 64.5, 159, 79)
    g.rectangle("line", 1.5, 65.5, 157, 77)
    if Font and type(Font.draw) == "function" then
        g.setColor(0.35, 0.30, 0.25, 1)
        Font.draw("R-SHIFT PAUSE", 4, 68)
    end
    for s = 1, #slots do
        local slot = slots[s]
        local move = rows[slot.i]
        if move then
            local selected = slot.i == index
            local cx, cy, cw, ch = slot.x, slot.y, 72, 12
            if selected then
                g.setColor(0.16, 0.30, 0.55, 1)
            else
                g.setColor(0.99, 0.96, 0.88, 1)
            end
            g.rectangle("fill", cx, cy, cw, ch)
            g.setColor(0.10, 0.08, 0.06, 1)
            g.rectangle("line", cx + 0.5, cy + 0.5, cw - 1, ch - 1)
            local name = fitText(Font, moveName(battle, move), 52)
            if Font and type(Font.draw) == "function" then
                if selected then
                    g.setColor(1, 1, 1, 1)
                else
                    g.setColor(0.08, 0.06, 0.05, 1)
                end
                Font.draw(slot.label, cx + 2, cy + 2)
                Font.draw(name, cx + 12, cy + 2)
            end
        end
    end
end


local function drawDialogue(g, Font, battle)
    return
end


function UI.draw(battle)
    -- Paint at most one bottom chrome layer per frame (command XOR moves XOR dialogue).
    if not (UI.active(battle) and love and love.graphics) then
        return
    end
    local g = love.graphics
    local Font = font()
    local state = UI.layoutState(battle)
    g.push("all")
    -- World HP bars on the overlay so voxel/3D cast still shows them (entity
    -- draw() may not run on the battle HUD pass).
    drawWorldHP(g, battle)
    if state.showCommand then
        drawCommand(g, Font, battle)
    elseif state.showMoves then
        drawMoves(g, Font, battle)
    elseif state.showDialogue then
        drawDialogue(g, Font, battle)
    end
    g.setColor(1, 1, 1, 1)
    g.pop()
end

-- this is not needed right now, the defualt dialogue box displays what we need.
local function _drawDialogue(g, Font, battle)
    -- Only draw dialogue if this is the *only* active dialogue, not the default/dialogue box managed elsewhere.
    -- This function should only handle drawing its own content, not duplicate global overlays.

    -- Check if the default dialogue box is visible (avoid drawing over it)
    if battle.defaultDialogueBoxVisible then
        return
    end

    local shown = battle.shown or {}

    -- Bail out if nothing to show and there's no pending/prompts; avoids drawing default/ghost dialogue.
    if #shown == 0 and not (battle.current or battle.msgHold or battle.msgWaiting or battle.msgPrompt) then
        return
    end

    -- Prevent double-drawing: only show this dialogue if not already handled by an active global toast or overlay.
    if battle.hasActiveDialoguePanel then
        -- Convention: the main battle object signals when the global panel toast is painting.
        return
    end

    local x, y, w, h = 4, 119, 152, 23
    box(g, x, y, w, h)
    g.setColor(0.08, 0.06, 0.05, 1)
    local first = math.max(1, #shown - 1)
    for lineIndex = first, #shown do
        local line = shown[lineIndex]
        local ty = y + 3 + (lineIndex - first) * 9
        if Font and type(Font.drawCode) == "function" then
            for i = 1, math.min(#line, 18) do
                Font.drawCode(line[i], x + 5 + (i - 1) * 8, ty)
            end
        end
    end
    if (battle.msgWaiting or battle.msgPrompt)
        and (battle.frame or 0) % 60 < 30 then
        if Font and type(Font.drawCode) == "function" then
            Font.drawCode(0xEE, x + w - 11, y + h - 9)
        end
    end
end


return UI
