-- Field battle — compact reference-style chrome (draw-only).
--
-- Three voices; each paints at most once per frame:
--   1. Game dialogue — engine narrator (appeared / used / about to use / faint)
--      Compact bottom box only. Never the classic white slab, never a bubble.
--   2. Banter        — trainer / NPC interludes (Callouts strip)
--   3. REACT / miss  — status chips on the battler after a successful
--      REACT! pick (DODGE / BRACE / COVER / HOLD) or an accuracy MISS.
--      Orders and failed reacts stay toasts.
--
-- BattleState still owns phases, cursors, input, and turn resolution.
-- This module also paints command / move HUDs and world-anchored HP bars.
--
-- World-anchored HP bars paint on the battle UI overlay with world→UI mapping
-- (survey zoom makes worldViewSize ≠ 160×144). Floor / cover / projectiles
-- still paint from Lifecycle.drawWorldOverlay on the world canvas when that
-- pass is visible.
--
-- Instant-cast / PAUSE latch live in hooks.lua, not here.


-- print("[anime_realism] ui.lua loaded @ " .. tostring(os.time()))

local UI = {}

UI.WIDTH = 160
UI.HEIGHT = 144

local Coords
do
    local ok, mod = pcall(require, "coords")
    if ok then
        Coords = mod
    end
end

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

-- Classic HUD is 48 px (GetHPBarLength). Compact FIELD chips map HP/max
-- straight onto the inner track instead of scaling 48ths twice.

-- Remaining HP for the chip. Prefer live `mon.hp` over the engine drain
-- numerator (`shownHP`): a parked queue / send-out can leave shownHP at 0
-- while the mon is still up, which painted an empty bar on a living Pokémon.
function UI.battlerHP(battler)
    local mon = battler and battler.mon
    local maxHP = tonumber(mon and mon.stats and mon.stats.hp)
    if not maxHP or maxHP < 1 then
        maxHP = 1
    end
    local hp = tonumber(mon and mon.hp)
    if hp == nil then
        hp = tonumber(battler and battler.shownHP) or 0
    end
    if hp < 0 then
        hp = 0
    end
    return clamp01(hp / maxHP), hp, maxHP
end

-- Inner fill width in pixels. Floor the ratio so a hit that crosses a
-- compact pixel actually shortens the bar; living HP never paints empty.
function UI.hpFillWidth(innerW, hp, maxHP)
    innerW = math.max(0, math.floor(tonumber(innerW) or 0))
    hp = tonumber(hp) or 0
    maxHP = tonumber(maxHP) or 0
    if innerW < 1 or hp <= 0 or maxHP <= 0 then
        return 0
    end
    local fill = math.floor(hp * innerW / maxHP)
    if fill < 1 then
        fill = 1
    end
    if fill > innerW then
        fill = innerW
    end
    return fill
end

-- Tick the painted fill one pixel toward the true ratio so damage reads
-- as a drain, not a snap. Send-out / big heals jump.
function UI.easeHpFill(cur, target)
    target = math.floor(tonumber(target) or 0)
    if target < 0 then
        target = 0
    end
    cur = tonumber(cur)
    if cur == nil or math.abs(target - cur) > 8 then
        return target
    end
    if cur < target then
        return cur + 1
    end
    if cur > target then
        return cur - 1
    end
    return target
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

local function hpBar(g, x, y, w, ratio, fill)
    ratio = clamp01(ratio)
    fill = math.floor(tonumber(fill) or 0)
    g.setColor(0.12, 0.09, 0.08, 1)
    g.rectangle("fill", x, y, w, 4)
    g.setColor(0.96, 0.92, 0.78, 1)
    g.rectangle("fill", x + 1, y + 1, w - 2, 2)
    if fill < 1 and ratio > 0 then
        fill = 1
    end
    if fill > w - 2 then
        fill = math.max(0, w - 2)
    end
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

-- Soft purple Focus meter (same shell as HP, thinner fill).
local function focusBar(g, x, y, w, ratio)
    ratio = clamp01(ratio)
    g.setColor(0.16, 0.10, 0.20, 1)
    g.rectangle("fill", x, y, w, 3)
    g.setColor(0.90, 0.84, 0.94, 1)
    g.rectangle("fill", x + 1, y + 1, w - 2, 1)
    local fill = math.floor((w - 2) * ratio + 0.5)
    if fill > 0 then
        g.setColor(0.62, 0.40, 0.82, 0.92)
        g.rectangle("fill", x + 1, y + 1, fill, 1)
    end
end

local function easeToward(cur, target, step)
    if cur == nil then
        return target
    end
    local d = target - cur
    if math.abs(d) <= step then
        return target
    end
    if d > 0 then
        return cur + step
    end
    return cur - step
end

-- Letter + bar + pointer: keep the chip on the canvas when a mon is
-- near the top (or side) of the view.
UI.HP_LETTER_W = 6
UI.HP_BAR_W = 20
UI.HP_CHIP_W = UI.HP_LETTER_W + 1 + UI.HP_BAR_W
UI.HP_CHIP_H = 7
UI.HP_CHIP_TOP = 2
UI.FOCUS_BAR_H = 3
UI.FOCUS_BAR_GAP = 0 -- in pixels. this is either 1 or 0 ~ cannot have a half pixel unfortunately :)

function UI.clampHpChip(x, y, canvasW, canvasH, extraTop)
    canvasW = tonumber(canvasW) or UI.WIDTH
    canvasH = tonumber(canvasH) or UI.HEIGHT
    local w = UI.HP_CHIP_W
    local h = UI.HP_CHIP_H
    local top = UI.HP_CHIP_TOP + (tonumber(extraTop) or 0)
    y = tonumber(y) or 0
    x = tonumber(x) or 0
    if y < top then
        y = top
    end
    if y + h > canvasH - 1 then
        y = canvasH - 1 - h
    end
    local half = math.floor(w / 2)
    if x - half < 1 then
        x = 1 + half
    elseif x - half + w > canvasW - 1 then
        x = canvasW - 1 - w + half
    end
    return x, y
end

local function overlaySize(ren)
    local w, h = UI.WIDTH, UI.HEIGHT
    if ren and type(ren.uiSize) == "function" then
        local a, b = ren:uiSize()
        if type(a) == "number" and a > 0 then
            w, h = a, b or h
        end
    end
    return w, h
end

function UI.active(battle)
    return battle ~= nil
        and (battle._arAnimeField or battle._arFieldCombat or battle._arFieldStandalone)
end

local function stackedPrompt(battle)
    local stack = battle and battle.game and battle.game.stack
    local top = stack and type(stack.top) == "function" and stack:top() or nil
    return top ~= nil and top ~= battle and top.isOpaque ~= true
end

-- Lane 1: engine narrator. Banter (Name:) and chip-owned REACT toasts stay out.
function UI.gameDialogue(battle)
    if not battle or battle.phase ~= "messages" then
        return false
    end
    if battle._arFieldChipDialogue or stackedPrompt(battle) then
        return false
    end
    local text = (battle.current and battle.current.text) or ""
    if tostring(text):match("^[%w%.%s']+:") then
        return false
    end
    return true
end

function UI.layoutState(battle)
    local phase = battle and battle.phase or ""
    return {
        phase = phase,
        showHUD = false,
        showCommand = phase == "menu",
        showMoves = phase == "moveSelect" or phase == "mimicSelect",
        showDialogue = UI.gameDialogue(battle),
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

local function barInitial(battler)
    local mon = battler and battler.mon
    local name = mon and (mon.nickname or mon.name or mon.species) or "?"
    name = tostring(name):gsub("^Enemy%s+", "")
    local ch = name:match("[%a]") or name:sub(1, 1) or "?"
    if ch == "" then
        ch = "?"
    end
    return ch:upper()
end

UI.CHIP_HOLD = 90
UI.CHIP_H = 12

-- Successful REACT! outcomes, plus accuracy MISS on the attacker.
-- Orders and failed reacts stay toasts / notices — they must not paint a chip.
local CHIP_PHRASE = {
    { "TOOK IT WELL", "BRACE" },
    { "BRACED RIGHT", "BRACE" },
    { "ENTRENCH", "HOLD" },
    { "THE SHELL", "HOLD" },
    { "TOOK COVER", "COVER" },
    { "HOLDING COVER", "COVER" },
    { "SAFE IN COVER", "COVER" },
    { "BEHIND COVER", "COVER" },
    { "LEAPT CLEAR", "DODGE" },
    { "SLIPPED PAST", "DODGE" },
    { "NARROWLY AVOIDED", "DODGE" },
    { "EVADED SKILLFULLY", "DODGE" },
    { "DODGED ASIDE", "DODGE" },
}

local function chipFlat(text)
    local s = tostring(text or ""):gsub("\v", " "):gsub("\n", " "):gsub("%s+", " ")
    return (s:match("^%s*(.-)%s*$") or ""):upper()
end

-- Map a REACT success line to its chip label. Callers must already know this
-- was a player REACT! pick — toast inference is not a chip.
function UI.chipAbbrev(text)
    local upper = chipFlat(text)
    for i = 1, #CHIP_PHRASE do
        if upper:find(CHIP_PHRASE[i][1], 1, true) then
            return CHIP_PHRASE[i][2]
        end
    end
    return nil
end

function UI.chipSide(battle, text)
    local cue = battle and battle.current and battle.current.arFieldCue
    if cue and (cue.side == "player" or cue.side == "enemy") then
        return cue.side
    end
    local s = chipFlat(text)
    if s:find("ENEMY ", 1, true) == 1 then
        return "enemy"
    end
    return "player"
end

function UI.armStatusChip(battle, side, text)
    if not (battle and text and tostring(text) ~= "") then
        return false
    end
    side = side == "enemy" and "enemy" or "player"
    local chips = battle._arStatusChips
    if type(chips) ~= "table" then
        chips = {}
        battle._arStatusChips = chips
    end
    local frame = tonumber(battle.frame) or 0
    chips[side] = { text = tostring(text), untilFrame = frame + UI.CHIP_HOLD }
    return true
end

-- Chips are armed from a successful REACT! pick (armStatusChip), not from
-- live toasts. Keep this hook so overlay still has a place to expire state.
function UI.syncStatusChips(battle)
    if not battle then
        return
    end
    battle._arFieldChipDialogue = nil
end

local function statusChip(battle, side)
    local chips = battle and battle._arStatusChips
    local chip = chips and chips[side]
    if not (chip and chip.text) then
        return nil
    end
    local frame = tonumber(battle.frame) or 0
    if frame > (tonumber(chip.untilFrame) or 0) then
        chips[side] = nil
        return nil
    end
    return chip
end

local function drawStatusChip(g, Font, chip, x, y, canvasW)
    local text = chip.text
    local tw = (#text) * 8
    if Font and type(Font.width) == "function" then
        tw = tonumber(Font.width(text)) or tw
    end
    local w, h = math.floor(tw + 6), UI.CHIP_H
    local cx = math.floor(x - w / 2)
    if cx + w > canvasW - 1 then
        cx = canvasW - 1 - w
    end
    if cx < 1 then
        cx = 1
    end
    if y < 1 then
        y = 1
    end
    g.setColor(1, 1, 0.94, 1)
    g.rectangle("fill", cx, y, w, h)
    g.setColor(0, 0, 0, 1)
    g.rectangle("line", cx + 0.5, y + 0.5, w - 1, h - 1)
    if Font and type(Font.draw) == "function" then
        Font.draw(text, cx + 3, y + 2)
    end
end

-- Draw HP chips above each field battler.
-- mode:
--   "ui" (default) — battle overlay; maps world-camera pixels → UI canvas
--   "world"        — world canvas; raw cam-relative pixels (no remap)
function UI.drawWorldHP(battle, camX, camY, mode)
    if not (love and love.graphics) then
        return
    end
    local g = love.graphics
    local Font = font()
    camX = camX or 0
    camY = camY or 0
    mode = mode or "ui"
    local ren = battle and battle.game and battle.game.renderer
    local ow = battle and battle.game and battle.game.overworld
    if (camX == 0 and camY == 0) and ow and ow.camera then
        camX = ow.camera.x or 0
        camY = ow.camera.y or 0
    end
    for _, item in ipairs({
        { side = "player", battler = battle and battle.player },
        { side = "enemy",  battler = battle and battle.enemy },
    }) do
        local ent = fieldEntity(battle, item.side)
        local battler = item.battler
        if ent and battler and not ent.hidden and not ent._removed then
            local lift = ent._fieldBarLift or 10
            local wx = (ent.px or 0) - camX + 8
            local wy = (ent.py or 0) - camY - lift
            local x, y = wx, wy
            if mode == "ui" and Coords and type(Coords.worldViewToUi) == "function" then
                x, y = Coords.worldViewToUi(wx, wy, ren)
            end
            local canvasW, canvasH = overlaySize(ren)
            if mode ~= "ui" and ren and type(ren.worldViewSize) == "function" then
                local a, b = ren:worldViewSize()
                if type(a) == "number" and a > 0 then
                    canvasW, canvasH = a, b or canvasH
                end
            end
            local showFocus = type(UI.focusBarVisible) == "function"
                and UI.focusBarVisible(battle) == true
            local extraTop = 0
            if showFocus then
                local gap = UI.FOCUS_BAR_GAP
                if type(UI.focusBarGap) == "function" then
                    gap = tonumber(UI.focusBarGap(battle)) or gap
                end
                extraTop = UI.FOCUS_BAR_H + math.max(0, math.floor(gap + 0.5))
            end
            local chip = statusChip(battle, item.side)
            local chipTop = chip and (UI.CHIP_H + 1) or 0
            x, y = UI.clampHpChip(x, y, canvasW, canvasH, extraTop + chipTop)
            x = math.floor(x + 0.5)
            y = math.floor(y + 0.5)
            -- Stash UI anchors for speech bubbles / other overlay chrome.
            if mode == "ui" then
                ent._fieldWorldX, ent._fieldWorldY = wx, wy
                ent._fieldScreenX, ent._fieldScreenY = x, y
            end
            local initial = barInitial(battler)
            local barW = UI.HP_BAR_W
            local letterW = UI.HP_LETTER_W
            local totalW = letterW + 1 + barW
            local left = x - math.floor(totalW / 2)
            if Font and type(Font.draw) == "function" then
                g.setColor(0.08, 0.06, 0.05, 1)
                g.push()
                g.translate(left, y - 1)
                g.scale(0.75, 0.75)
                Font.draw(initial, 0, 0)
                g.pop()
            else
                g.setColor(0.08, 0.06, 0.05, 1)
                g.print(initial, left, y - 2)
            end
            if showFocus and type(UI.focusRatio) == "function" then
                local target = tonumber(UI.focusRatio(battle, item.side == "player"))
                if target then
                    local shown = battle._arFocusBarShown
                    if type(shown) ~= "table" then
                        shown = {}
                        battle._arFocusBarShown = shown
                    end
                    local key = item.side
                    shown[key] = easeToward(shown[key], clamp01(target), 0.03)
                    focusBar(g, left + letterW + 1, y - extraTop, barW, shown[key])
                end
            end
            local ratio, hp, maxHP = UI.battlerHP(battler)
            local fills = battle._arHpBarFill
            if type(fills) ~= "table" then
                fills = {}
                battle._arHpBarFill = fills
            end
            local target = UI.hpFillWidth(barW - 2, hp, maxHP)
            fills[item.side] = UI.easeHpFill(fills[item.side], target)
            hpBar(g, left + letterW + 1, y, barW, ratio, fills[item.side])
            g.setColor(0.12, 0.09, 0.08, 1)
            g.polygon("fill", x - 1, y + 4, x + 1, y + 4, x, y + 6)
            if chip then
                drawStatusChip(g, Font, chip, x, y - extraTop - chipTop, canvasW)
            end
        end
    end
    g.setColor(1, 1, 1, 1)
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
    local x, y, w, h = 48, 100, 140, 36  -- x a little more left, w wider
    box(g, x, y, w, h)
    local labels = commandLabels(battle)
    local index = math.max(1, math.min(4, battle.menuIndex or 1))
    local scale = 0.90

    -- Panel corners for each label
    -- Move top right and bottom right even more inward (increase sidePad so text is less far right)
    local sidePad = 40  -- pad the right side more, so text isn't hugging the panel edge
    local panel = {
        { tx = x + 16,          ty = y + 9 },      -- Top left     (label 1) (moved right since panel is wider)
        { tx = x + w - sidePad, ty = y + 9 },      -- Top right    (label 2)
        { tx = x + 16,          ty = y + h - 11 }, -- Bottom left  (label 3)
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

function UI.moveHudStyle(style)
    if type(style) == "string" and string.upper(style) == "DIAMOND" then
        return "DIAMOND"
    end
    return "CLASSIC"
end

local function drawMovesClassic(g, Font, battle)
    -- Compact full-width 2×2. Slot letters match the diamond compass
    -- (U=1, R=2, L=3, D=4). D-pad moves the cursor; A confirms.
    local rows = moveRows(battle)
    local index = battle.phase == "mimicSelect"
        and (battle.mimicIndex or 1) or (battle.moveIndex or 1)
    local x, y, w, h = 4, 100, 152, 40
    box(g, x, y, w, h)
    if Font and type(Font.draw) == "function" then
        g.setColor(0.35, 0.30, 0.25, 1)
        Font.draw("B PAUSE", x + 6, y + 3)
    end
    local slots = {
        { i = 1, label = "U", col = 0, row = 0 },
        { i = 2, label = "R", col = 1, row = 0 },
        { i = 3, label = "L", col = 0, row = 1 },
        { i = 4, label = "D", col = 1, row = 1 },
    }
    local colW = 74
    for s = 1, #slots do
        local slot = slots[s]
        local move = rows[slot.i]
        if move then
            local tx = x + 6 + slot.col * colW
            local ty = y + 14 + slot.row * 12
            local selected = slot.i == index
            if selected then
                drawCodeScaled(g, Font, 0xED, tx, ty, 0.9)
            end
            local name = fitText(Font, moveName(battle, move), 52)
            if Font and type(Font.draw) == "function" then
                g.setColor(0.08, 0.06, 0.05, 1)
                Font.draw(slot.label, tx + 12, ty)
                Font.draw(name, tx + 22, ty)
            end
        end
    end
end

local function drawMovesDiamond(g, Font, battle)
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
        Font.draw("B PAUSE", 4, 68)
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

local function drawMoves(g, Font, battle, style)
    if UI.moveHudStyle(style) == "DIAMOND" then
        drawMovesDiamond(g, Font, battle)
    else
        drawMovesClassic(g, Font, battle)
    end
end


local function drawDialogue(g, Font, battle)
    local shown = battle.shown or {}
    if #shown == 0 and not (battle.current or battle.msgHold
        or battle.msgWaiting or battle.msgPrompt) then
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


function UI.draw(battle, style)
    -- Paint at most one bottom chrome layer per frame (command XOR moves XOR dialogue).
    if not (UI.active(battle) and love and love.graphics) then
        return
    end
    local g = love.graphics
    local Font = font()
    local state = UI.layoutState(battle)
    g.push("all")
    -- HP on the UI overlay with world→UI mapping so bars survive 3D/world
    -- overrides and stay glued to mons under survey zoom.
    UI.drawWorldHP(battle, nil, nil, "ui")
    if state.showCommand then
        drawCommand(g, Font, battle)
    elseif state.showMoves then
        drawMoves(g, Font, battle, style)
    elseif state.showDialogue then
        drawDialogue(g, Font, battle)
    end
    g.setColor(1, 1, 1, 1)
    g.pop()
end

return UI
