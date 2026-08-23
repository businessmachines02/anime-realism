-- Field battle — compact reference-style chrome (draw-only).
--
-- Three voices; each paints at most once per frame:
--   1. Game dialogue — engine narrator (appeared / used / about to use / faint)
--      One light glass plate. Never the classic white slab, never a bubble.
--   2. Banter        — trainer / NPC interludes (Callouts strip)
--   3. REACT / miss  — chips over the battler sprite after a successful
--      REACT! pick (DODGE / BRACE / COVER / HOLD) or an accuracy MISS.
--      Emotion pills (worry / angry) stay on the HUD stack. Orders and
--      failed reacts stay toasts.
--
-- BattleState still owns phases, cursors, input, and turn resolution.
-- This module also paints command / move HUDs and world-anchored HP bars.
--
-- Battler chrome (HP / Focus / chips / face) is authored on the UI overlay
-- corners, then docked to the window via setBattleUIAnchor (same path as
-- Gen1BetterMenus / WideBattle EXTENDED). Move chrome stays in the letterbox.
-- Floor / cover / projectiles still paint from Lifecycle.drawWorldOverlay.
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

local Type
do
    local ok, mod = pcall(require, "field_type")
    if ok and type(mod) == "table" then
        Type = mod
    end
end
UI.Type = Type

local function font()
    local ok, Font = pcall(require, "src.render.Font")
    return ok and Font or nil
end

-- Authored HUD copy: ALL-CAPS words → lowercase for the pixel face.
function UI.hudText(text)
    if Type and type(Type.display) == "function" then
        return Type.display(text)
    end
    return tostring(text or "")
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
function UI.hitPaintHeld(battle)
    if not battle then
        return false
    end
    if battle._arRangedHitHold then
        return true
    end
    if type(battle._arHeldHpPaint) == "table" then
        return true
    end
    local apply = battle._arCloseGapApply
    if type(apply) == "table" and #apply > 0 then
        return true
    end
    local dmg = battle._arCloseGapDamage
    if type(dmg) == "table" and (dmg.ctx or #dmg > 0) then
        return true
    end
    return false
end

function UI.heldHpSnap(battle, battler)
    local snap = battle and battle._arHeldHpPaint
    if type(snap) ~= "table" or not battler then
        return nil
    end
    if battler == battle.player then
        return tonumber(snap.player)
    end
    if battler == battle.enemy then
        return tonumber(snap.enemy)
    end
    return nil
end

function UI.battlerHP(battler, battle)
    local mon = battler and battler.mon
    local maxHP = tonumber(mon and mon.stats and mon.stats.hp)
    if not maxHP or maxHP < 1 then
        maxHP = 1
    end
    local live = tonumber(mon and mon.hp)
    local shown = tonumber(battler and battler.shownHP)
    local snap = UI.heldHpSnap(battle, battler)
    local hp = live
    -- Charge / travel shot: keep the pre-hit bar even if the engine
    -- already resolved mon.hp. Snapshot wins; stashed shownHP is next.
    if snap ~= nil then
        hp = snap
    elseif UI.hitPaintHeld(battle) and shown ~= nil then
        hp = shown
    elseif hp == nil then
        hp = shown or 0
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

local function measureText(Font, text)
    if Type and type(Type.width) == "function" then
        return Type.width(text, Font)
    end
    text = UI.hudText(text)
    if Font and type(Font.width) == "function" then
        return tonumber(Font.width(text)) or (#text * 8)
    end
    return #tostring(text or "") * 8
end

local function fitText(Font, value, maxWidth)
    local text = UI.hudText(value or "POKéMON")
    if measureText(Font, text) <= maxWidth then
        return text
    end
    while #text > 1 and measureText(Font, text .. "+") > maxWidth do
        text = text:sub(1, -2)
    end
    return text .. "+"
end

-- Command / move HUD: cream plate, opaque enough that the floor
-- cannot eat the pixel type. Dialogue stays a lighter glass.
UI.HUD_PANEL_A = 0.92
UI.DIALOGUE_FILL = { 0.98, 0.96, 0.90 }
UI.DIALOGUE_A = 0.78
UI.DIALOGUE_X = 4
UI.DIALOGUE_Y = 119
UI.DIALOGUE_W = 152
UI.DIALOGUE_H = 23
local DARK_INK = { 0.08, 0.06, 0.05, 1 }

local function resetTint(g)
    if g and type(g.setColor) == "function" then
        g.setColor(1, 1, 1, 1)
    end
end

function UI.hudPanelAlpha()
    return UI.HUD_PANEL_A
end

function UI.dialogueRect()
    return UI.DIALOGUE_X, UI.DIALOGUE_Y, UI.DIALOGUE_W, UI.DIALOGUE_H
end

-- One light fill + one thin edge. No second frame, no dark/light swap.
function UI.paintDialoguePlate(g, x, y, w, h, alpha)
    if not (g and type(g.setColor) == "function") then
        return
    end
    alpha = tonumber(alpha)
    if alpha == nil then
        alpha = UI.DIALOGUE_A
    end
    if alpha <= 0 then
        return
    end
    local fill = UI.DIALOGUE_FILL
    g.setColor(fill[1], fill[2], fill[3], alpha)
    g.rectangle("fill", x, y, w, h)
    g.setColor(0.18, 0.14, 0.12, math.min(1, alpha + 0.15))
    g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
end

-- Move / command chrome: same cream plate as dialogue, no halo.
local function hudBox(g, x, y, w, h)
    UI.paintDialoguePlate(g, x, y, w, h, UI.HUD_PANEL_A)
end

local function hpBar(g, x, y, w, ratio, fill)
    ratio = clamp01(ratio)
    fill = math.floor(tonumber(fill) or 0)
    local h = UI.HP_BAR_H or 5
    local inner = math.max(2, h - 2)
    g.setColor(0.12, 0.09, 0.08, 1)
    g.rectangle("fill", x, y, w, h)
    g.setColor(0.96, 0.92, 0.78, 1)
    g.rectangle("fill", x + 1, y + 1, w - 2, inner)
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
        g.rectangle("fill", x + 1, y + 1, fill, inner)
    end
end

-- Soft purple Focus meter (same shell as HP, thinner fill).
local function focusBar(g, x, y, w, ratio)
    ratio = clamp01(ratio)
    local h = UI.FOCUS_BAR_H or 4
    local inner = math.max(2, h - 2)
    g.setColor(0.16, 0.10, 0.20, 1)
    g.rectangle("fill", x, y, w, h)
    g.setColor(0.90, 0.84, 0.94, 1)
    g.rectangle("fill", x + 1, y + 1, w - 2, inner)
    local fill = math.floor((w - 2) * ratio + 0.5)
    if fill > 0 then
        g.setColor(0.62, 0.40, 0.82, 0.92)
        g.rectangle("fill", x + 1, y + 1, fill, inner)
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

-- World HP row: cream initial badge + HP bar (+ optional Focus above it).
-- Keep the chip on the canvas when a mon is near the top (or side).
UI.HP_LETTER_W = 11       -- cream badge width (holds the species initial)
UI.HP_BAR_W = 20          -- green HP track width, right of the badge
UI.HP_CHIP_W = UI.HP_LETTER_W + 1 + UI.HP_BAR_W
UI.HP_CHIP_H = 10         -- cream badge height
UI.HP_LETTER_SCALE = 1    -- 1 = native HUD type size inside the badge
UI.HP_BADGE_LIFT = 2      -- nudge the badge (not the bars) up, in pixels
UI.HP_BAR_H = 5           -- green HP track height
UI.FACE_SIZE = 28         -- PMD portrait square under the HP row
UI.FACE_GAP = 28
UI.FACE_LIFT = 10
UI.FACE_MARGIN = 2
UI.HUD_PAD = 4
UI.HP_FACE_GAP = 0        -- px between HP row bottom and portrait top
UI.CHIP_AIR = 4           -- px between the emotion pill and the HP row
UI.REACT_CHIP_LIFT = 6    -- px the REACT pill sits above the mon sprite

function UI.faceGap(ent)
    local gap = UI.FACE_GAP
    local cell = tonumber(ent and ent._kitCell)
    if cell and cell > 16 then
        gap = math.max(gap, math.floor(cell / 2) + 10)
    end
    return gap
end

-- Player chrome hugs top-left; foe hugs top-right of the UI overlay.
-- `gap` is stack height above the face.
--
-- Widescreen docking: author the stack in native UI pixels. The foe uses
-- the engine's setBattleUIAnchor "topright". The engine has no topleft, so
-- the player stack is stored and blitted after endFrame (mod wrap only).
function UI.hudAnchor(side)
    if side == "enemy" then
        return "topright"
    end
    return "window-left"
end

function UI.hudStackBox(fx, fy, size, stackH)
    size = tonumber(size) or UI.FACE_SIZE
    fx = tonumber(fx) or 0
    fy = tonumber(fy) or 0
    stackH = tonumber(stackH) or 0
    if stackH < 0 then
        stackH = 0
    end
    local barW = UI.HP_CHIP_W or 27
    local mid = fx + math.floor(size / 2)
    local half = math.floor(barW / 2)
    local left = math.min(fx, mid - half)
    local right = math.max(fx + size, mid + barW - half)
    local top = fy - stackH
    if top < 0 then
        top = 0
    end
    local bottom = fy + size
    return left, top, math.max(1, right - left), math.max(1, bottom - top)
end

function UI.anchorFieldHud(battle, side, x, y, w, h)
    local ren = battle and battle.game and battle.game.renderer
    if not ren then
        return false
    end
    if side == "player" then
        ren._arFieldHudLeft = {
            x = tonumber(x) or 0,
            y = tonumber(y) or 0,
            w = tonumber(w) or 1,
            h = tonumber(h) or 1,
            canvas = ren.battleHUDCanvas,
        }
        return true
    end
    if type(ren.setBattleUIAnchor) ~= "function" then
        return false
    end
    local ok = pcall(ren.setBattleUIAnchor, ren, x, y, w, h, UI.hudAnchor(side))
    return ok == true
end

-- Copy the stored player stack to the real window left. Called after the
-- engine finishes compositing so this is not clipped to the letterbox.
function UI.drawWindowPlayerHud(ren, metrics)
    local box = ren and ren._arFieldHudLeft
    local canvas = box and (box.canvas or (ren and ren.battleHUDCanvas))
    if not (box and canvas and love and love.graphics) then
        return false
    end
    metrics = metrics or {}
    local g = love.graphics
    local ww = tonumber(metrics.width)
    local wh = tonumber(metrics.height)
    if not ww and type(g.getWidth) == "function" then
        ww = g.getWidth()
    end
    if not wh and type(g.getHeight) == "function" then
        wh = g.getHeight()
    end
    if not (ww and wh and ww > 0 and wh > 0) then
        return false
    end
    local dpiX = tonumber(metrics.dpiX) or 1
    local dpiY = tonumber(metrics.dpiY) or 1
    if dpiX < 1 then
        dpiX = 1
    end
    if dpiY < 1 then
        dpiY = 1
    end
    local uiw, uih = UI.WIDTH, UI.HEIGHT
    if ren and type(ren.uiSize) == "function" then
        local a, b = ren:uiSize()
        if type(a) == "number" and a > 0 then
            uiw, uih = a, b or uih
        end
    end
    local up = 1
    if type(ren.uiScale) == "function" then
        up = tonumber(ren:uiScale()) or 1
    end
    if ren.uiFill then
        up = math.min((wh * dpiY) / uih, (ww * dpiX) / uiw)
    end
    if up < 1 then
        up = 1
    end
    local ux, uy = up / dpiX, up / dpiY
    local dx = (box.x or 0) * ux
    local dy = (box.y or 0) * uy
    local dw = (box.w or 1) * ux
    local dh = (box.h or 1) * uy
    dx = math.max(0, math.min(math.max(0, ww - dw), dx))
    dy = math.max(0, math.min(math.max(0, wh - dh), dy))
    g.push("all")
    if type(g.origin) == "function" then
        g.origin()
    end
    if type(g.setScissor) == "function" then
        g.setScissor()
    end
    g.setColor(1, 1, 1, 1)
    if type(ren.blitCanvas) == "function" then
        local ok = pcall(ren.blitCanvas, ren, canvas, ux, uy, nil, ux, uy,
            dx - (box.x or 0) * ux, dy - (box.y or 0) * uy,
            dx, dy, dw, dh, dpiX, dpiY)
        g.pop()
        return ok == true
    end
    if type(g.newQuad) == "function" and canvas.getWidth then
        local quad = g.newQuad(box.x, box.y, box.w, box.h,
            canvas:getWidth(), canvas:getHeight())
        g.draw(canvas, quad, dx, dy, 0, ux, uy)
    else
        g.draw(canvas, dx - (box.x or 0) * ux, dy - (box.y or 0) * uy, 0, ux, uy)
    end
    g.pop()
    return true
end

function UI.faceAnchor(side, _bodyX, _bodyY, size, gap, canvasW)
    size = tonumber(size) or UI.FACE_SIZE
    canvasW = tonumber(canvasW) or UI.WIDTH
    local pad = UI.HUD_PAD or UI.FACE_MARGIN or 4
    local fx
    if side == "player" then
        fx = pad
    else
        fx = canvasW - pad - size
    end
    if fx < 1 then
        fx = 1
    end
    local stackAbove = tonumber(gap) or 0
    if stackAbove < 0 then
        stackAbove = 0
    end
    return fx, pad + stackAbove
end

-- HP chip sits on the portrait: centered on the face, just above it.
function UI.hpAboveFace(fx, fy, size)
    size = tonumber(size) or UI.FACE_SIZE
    fx = tonumber(fx) or 0
    fy = tonumber(fy) or 0
    return fx + math.floor(size / 2), fy - (UI.HP_CHIP_H or 7) - (UI.HP_FACE_GAP or 0)
end

-- Emotion / worry pill on the HUD stack, above HP (and Focus if shown).
function UI.moodChipAboveHp(hx, hy, extraTop)
    extraTop = math.max(0, tonumber(extraTop) or 0)
    local gap = UI.CHIP_AIR or 4
    return hx, hy - extraTop - gap - (UI.CHIP_H or 13)
end

-- REACT / MISS pill, centered on the battler sprite (grid, not the HUD).
function UI.reactChipAboveMon(spriteX, spriteY)
    spriteX = tonumber(spriteX) or 0
    spriteY = tonumber(spriteY) or 0
    return spriteX, spriteY - (UI.CHIP_H or 13) - (UI.REACT_CHIP_LIFT or 6)
end

-- HP / focus sit a couple px above the ink, not the hop-padded cell top.
-- 2D kit plant is +12; rest occupancy is ~24–32px at the bottom of the cell.
function UI.barLift(ent)
    local stored = tonumber(ent and ent._fieldBarLift) or 10
    local cell = tonumber(ent and ent._kitCell)
    local kit = ent and (ent._kitSheet or (ent.sprite and ent.sprite.kit))
    if not kit then
        return stored
    end
    local body = stored
    if not body or body > 32 then
        body = 24
    end
    if cell and cell >= 16 and cell <= 32 then
        body = cell
    end
    return math.max(10, body - 10)
end
UI.HP_CHIP_TOP = 2
UI.FOCUS_BAR_H = 4
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

local function foeIsDown(battle)
    if type(UI.foeIsDown) == "function" then
        return UI.foeIsDown(battle)
    end
    if not battle then
        return false
    end
    local e = battle.enemy
    if not e then
        return false
    end
    local hp = (e.mon and e.mon.hp) or e.hp
    return type(hp) == "number" and hp <= 0
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
    -- Send-out keeps foe HP at 0 for a beat; hiding FIGHT there freezes
    -- "X sent out Y!" with no menu and no advancing narrator.
    local sending = battle and (battle.enemySendingOut or battle.sendingOut)
    if not sending then
        local text = tostring(battle and battle.current and battle.current.text or "")
            :lower():gsub("%s+", " ")
        sending = text:find("sent out", 1, true) or text:find("go!", 1, true)
    end
    local hold = foeIsDown(battle) and not sending
    local showCommand = phase == "menu" and not hold
    local showMoves = (phase == "moveSelect" or phase == "mimicSelect") and not hold
    return {
        phase = phase,
        showHUD = false,
        showCommand = showCommand,
        showMoves = showMoves,
        showDialogue = (not showCommand and not showMoves) and UI.gameDialogue(battle),
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

-- First A–Z of nickname / species ("Vaporeon" → "V").
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

UI.CHIP_HOLD = 90   -- frames a REACT / mood pill stays up
UI.CHIP_H = 13      -- yellow (etc.) status / mood pill height
UI.CHIP_SCALE = 1   -- pill type size vs HUD type (1 = same)

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
    { "CRASHED THROUGH", "CHARGE" },
    { "THEY CRASHED", "CHARGE" },
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

function UI.drawFace(g, img, x, y, size, alpha)
    if not (g and img and type(g.draw) == "function") then
        return
    end
    size = tonumber(size) or UI.FACE_SIZE
    alpha = tonumber(alpha)
    if alpha == nil then
        alpha = 1
    end
    if alpha <= 0.02 then
        return
    end
    local iw = 40
    if type(img.getWidth) == "function" then
        iw = tonumber(img:getWidth()) or iw
    end
    local scale = size / math.max(1, iw)
    if img.setFilter then
        pcall(img.setFilter, img, "nearest", "nearest")
    end
    g.setColor(1, 1, 1, alpha)
    g.draw(img, math.floor(x + 0.5), math.floor(y + 0.5), 0, scale, scale)
    resetTint(g)
end

function UI.moodChipSpec(mood)
    if type(UI.moodChip) == "function" then
        return UI.moodChip(mood)
    end
    return nil
end

local function moodChipOf(battle, isPlayer)
    if type(UI.moodOf) ~= "function" then
        return nil
    end
    local mood = UI.moodOf(battle, isPlayer)
    if not mood or mood == "normal" then
        return nil
    end
    return UI.moodChipSpec(mood), mood
end

local function drawStatusChip(g, Font, chip, x, y, canvasW)
    local text = tostring(chip.text or "")
    local scale = UI.CHIP_SCALE or 1
    local tw = math.max(1, math.floor(measureText(Font, text) * scale + 0.5))
    local w, h = tw + 6, UI.CHIP_H
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
    local fill = chip.fill or { 1, 1, 0.94 }
    local ink = chip.ink or DARK_INK
    local faceH = (Type and Type.SIZE) or 8
    local textY = math.max(1, math.floor((h - faceH) / 2))
    g.push("all")
    g.setColor(fill[1], fill[2], fill[3], 1)
    g.rectangle("fill", cx, y, w, h)
    g.setColor(0.10, 0.08, 0.06, 1)
    g.rectangle("line", cx + 0.5, y + 0.5, w - 1, h - 1)
    g.push()
    g.translate(cx + 3, y + textY)
    if scale ~= 1 then
        g.scale(scale, scale)
    end
    if Type and type(Type.draw) == "function" then
        Type.draw(g, text, 0, 0, ink, Font, { track = 0 })
    elseif Font and type(Font.draw) == "function" then
        g.setColor(ink[1], ink[2], ink[3], ink[4] or 1)
        Font.draw(text, 0, 0)
    end
    g.pop()
    resetTint(g)
    g.pop()
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
    if ren then
        ren._arFieldHudLeft = nil
    end
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
            local lift = UI.barLift(ent)
            local wx = (ent.px or 0) - camX + 8
            local wy = (ent.py or 0) - camY - lift
            local spriteX, spriteY = wx, wy
            if mode == "ui" and Coords and type(Coords.worldViewToUi) == "function" then
                spriteX, spriteY = Coords.worldViewToUi(wx, wy, ren)
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

            -- Emotion pill stays on the HUD. REACT / MISS follows the mon.
            local reactChip = statusChip(battle, item.side)
            local moodSpec = select(1, moodChipOf(battle, item.side == "player"))
            local moodTop = moodSpec and ((UI.CHIP_H or 13) + (UI.CHIP_AIR or 4)) or 0
            local faceOn = type(UI.faceEnabled) == "function" and UI.faceEnabled(battle)
            local faceImg, faceA
            if faceOn and type(UI.faceFlash) == "function" then
                faceImg, faceA = UI.faceFlash(battle, item.side == "player")
            end
            -- Portrait square; stackH reserves room above it for mood + HP.
            local fs = UI.FACE_SIZE or 28
            -- +4 / badge lift: HP row sits a few px above hpAboveFace, cream higher still.
            local stackH = extraTop + moodTop + UI.HP_CHIP_H + (UI.HP_FACE_GAP or 0)
                + 4 + (UI.HP_BADGE_LIFT or 2)
            local fx, fy = UI.faceAnchor(item.side, nil, nil, fs, stackH, canvasW)
            if fy + fs > canvasH - 1 then
                fy = canvasH - 1 - fs
            end
            -- HP row origin: centered on the portrait, flush above it.
            local x, y = UI.hpAboveFace(fx, fy, fs)
            x = math.floor(x + 0.5)
            y = math.floor(y + 0.5)
            -- Bubbles still point at the mon; HUD chrome is screen-pinned.
            if mode == "ui" then
                ent._fieldWorldX, ent._fieldWorldY = wx, wy
                ent._fieldScreenX, ent._fieldScreenY = spriteX, spriteY
            end

            -- "V" / first letter of the nickname or species.
            local initial = barInitial(battler)
            local barW = UI.HP_BAR_W
            local letterW = UI.HP_LETTER_W
            local totalW = letterW + 1 + barW
            local left = x - math.floor(totalW / 2)
            -- baseY = HP/Focus bar row. badgeY = cream square, 2px above that.
            local baseY = y - 4
            local badgeY = baseY - (UI.HP_BADGE_LIFT or 2)
            local badgeH = math.max(UI.HP_CHIP_H, (Type and Type.SIZE or 8) + 2)
            -- Cream plate behind the initial.
            UI.paintDialoguePlate(g, left, badgeY, letterW, badgeH, 1)
            local faceH = (Type and Type.SIZE) or 8
            local letterY = badgeY + math.max(1, math.floor((badgeH - faceH) / 2))
            local letterX = left + 2
            g.push()
            g.translate(letterX, letterY)
            local letterScale = UI.HP_LETTER_SCALE or 1
            if letterScale ~= 1 then
                g.scale(letterScale, letterScale)
            end
            if Type and type(Type.draw) == "function" then
                Type.draw(g, initial, 0, 0, DARK_INK, Font, { track = 0 })
            elseif Font and type(Font.draw) == "function" then
                g.setColor(DARK_INK[1], DARK_INK[2], DARK_INK[3], 1)
                Font.draw(initial, 0, 0)
            else
                g.setColor(DARK_INK[1], DARK_INK[2], DARK_INK[3], 1)
                g.print(initial, 0, 0)
            end
            g.pop()
            resetTint(g)
            -- Purple Focus (REACT meter) sits on the same X as HP, one row up.
            local barH = UI.HP_BAR_H or 5
            local barY = baseY + math.max(0, math.floor((badgeH - barH) / 2))
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
                    focusBar(g, left + letterW + 1, barY - extraTop, barW, shown[key])
                end
            end
            -- Green HP track to the right of the cream badge.
            local ratio, hp, maxHP = UI.battlerHP(battler, battle)
            local fills = battle._arHpBarFill
            if type(fills) ~= "table" then
                fills = {}
                battle._arHpBarFill = fills
            end
            local target = UI.hpFillWidth(barW - 2, hp, maxHP)
            fills[item.side] = UI.easeHpFill(fills[item.side], target)
            hpBar(g, left + letterW + 1, barY, barW, ratio, fills[item.side])
            -- Worry / ANGRY / TIRED stays on this HUD stack.
            if moodSpec then
                local mx, my = UI.moodChipAboveHp(x, y, extraTop)
                drawStatusChip(g, Font, moodSpec, mx, my, canvasW)
            end
            -- DODGE / BRACE / COVER / HOLD / MISS sits over the battler.
            if reactChip then
                local rx, ry = UI.reactChipAboveMon(spriteX, spriteY)
                drawStatusChip(g, Font, reactChip, rx, ry, canvasW)
            end
            -- PMD portrait under the HP row.
            if faceImg and (faceA or 1) > 0.02 and fx then
                UI.drawFace(g, faceImg, fx, fy, fs, faceA)
            end
            if mode == "ui" then
                resetTint(g)
                local bx, by, bw, bh = UI.hudStackBox(fx, fy, fs, stackH)
                UI.anchorFieldHud(battle, item.side, bx, by, bw, bh)
            end
        end
    end
    resetTint(g)
end

local function drawScaled(g, Font, text, x, y, scale)
    if not (Font and type(Font.draw) == "function") then return end
    g.push()
    g.translate(x, y)
    g.scale(scale, scale)
    Font.draw(text, 0, 0)
    g.pop()
end

local function labelWidth(Font, text)
    return measureText(Font, text)
end

-- this draws out the labels on our HUD (either main menu or move selection menu)
local function drawHudLabel(g, Font, text, x, y, scale, alignRight, ink)
    text = UI.hudText(text)
    if text == "" then
        return
    end
    ink = ink or DARK_INK
    local ox = 0
    if alignRight then
        ox = -labelWidth(Font, text)
    end
    g.push("all")
    g.translate(x + ox, y)
    if Type and type(Type.draw) == "function" then
        Type.draw(g, text, 0, 0, ink, Font)
    elseif Font and type(Font.draw) == "function" then
        scale = scale or 1
        if scale ~= 1 then
            g.scale(scale, scale)
        end
        g.setColor(ink[1], ink[2], ink[3], ink[4] or 1)
        Font.draw(text, 0, 0)
    end
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
    hudBox(g, x, y, w, h)

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
        drawHudLabel(g, Font, labels[i], tx, ty, scale, i == 2 or i == 4)
        if i == index then
            -- Slightly to left for TL/BL, rightward for TR/BR
            local selX = tx
            if i == 2 or i == 4 then
                selX = tx - labelWidth(Font, labels[i] or "")
            end
            drawCodeScaled(g, Font, 0xED, selX - 14, ty, 0.9)
        end
    end
    g.setColor(1, 1, 1, 1) -- Reset color afterwards
end

local function moveRows(battle)
    if battle.phase == "mimicSelect" then
        return battle.mimicMoves or {}
    end
    return battle.player and battle.player.curMoves or {}
end

local function moveDefOf(battle, move)
    if not (battle and move) then
        return nil
    end
    if type(battle.moveDef) == "function" then
        local ok, def = pcall(battle.moveDef, battle, move)
        if ok and type(def) == "table" then
            return def
        end
    end
    local dex = battle.data and battle.data.moves
    local id = move.id
    if id and type(dex) == "table" and type(dex[id]) == "table" then
        return dex[id]
    end
    return nil
end

local function moveName(battle, move)
    if not move then return "-" end
    local def = moveDefOf(battle, move)
    return (def and def.name) or tostring(move.id or "-")
end

-- Remaining PP, plus max when the instance or dex has one.
function UI.movePP(battle, move)
    if not move or move.struggle then
        return nil, nil
    end
    local cur = tonumber(move.pp)
    if cur == nil then
        return nil, nil
    end
    if cur < 0 then
        cur = 0
    end
    cur = math.floor(cur)
    local def = moveDefOf(battle, move)
    local max = tonumber(move.maxPP or move.ppMax or move.maxPp)
        or tonumber(def and (def.maxPP or def.ppMax or def.pp))
    if max ~= nil then
        max = math.floor(max)
        if max < 0 then
            max = 0
        end
    end
    return cur, max
end

function UI.movePPLabel(battle, move, withMax)
    local cur, max = UI.movePP(battle, move)
    if cur == nil then
        return nil
    end
    if withMax and max ~= nil then
        return tostring(cur) .. "/" .. tostring(max)
    end
    return tostring(cur)
end

local function drawHeaderPP(g, Font, battle, move, right, y)
    local header = UI.movePPLabel(battle, move, true)
    if not header then
        return
    end
    local cur = UI.movePP(battle, move)
    local ink = cur == 0
        and { 0.78, 0.18, 0.12, 1 }
        or { 0.35, 0.30, 0.25, 1 }
    drawHudLabel(g, Font, "PP " .. header, right, y, 1, true, ink)
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
    hudBox(g, x, y, w, h)
    drawHudLabel(g, Font, "B PAUSE", x + 6, y + 3, 1, false, { 0.35, 0.30, 0.25, 1 })
    drawHeaderPP(g, Font, battle, rows[index], x + w - 6, y + 3)
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
            drawHudLabel(g, Font, slot.label, tx + 12, ty, 1)
            drawHudLabel(g, Font, name, tx + 22, ty, 1)
        end
    end
    g.setColor(1, 1, 1, 1) -- Reset color afterwards, just in case
end

local function drawMovesDiamond(g, Font, battle)
    -- Diamond compass: direction matches slot. Translucent plate over the field.
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
    hudBox(g, 0, 64, 160, 80)
    drawHudLabel(g, Font, "B PAUSE", 4, 68, 1, false, { 0.35, 0.30, 0.25, 1 })
    drawHeaderPP(g, Font, battle, rows[index], 154, 68)
    for s = 1, #slots do
        local slot = slots[s]
        local move = rows[slot.i]
        if move then
            local selected = slot.i == index
            local cx, cy, cw, ch = slot.x, slot.y, 72, 12
            if selected then
                g.setColor(0.16, 0.30, 0.55, 1)
            else
                g.setColor(0.99, 0.96, 0.88, 0.42)
            end
            g.rectangle("fill", cx, cy, cw, ch)
            g.setColor(0.10, 0.08, 0.06, 1)
            g.rectangle("line", cx + 0.5, cy + 0.5, cw - 1, ch - 1)
            local name = fitText(Font, moveName(battle, move), 52)
            if selected then
                drawHudLabel(g, Font, slot.label, cx + 2, cy + 2, 1, false, { 1, 1, 1, 1 })
                drawHudLabel(g, Font, name, cx + 12, cy + 2, 1, false, { 1, 1, 1, 1 })
            else
                drawHudLabel(g, Font, slot.label, cx + 2, cy + 2, 1)
                drawHudLabel(g, Font, name, cx + 12, cy + 2, 1)
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
        return false
    end
    local x, y, w, h = UI.dialogueRect()
    g.push("all")
    UI.paintDialoguePlate(g, x, y, w, h)
    g.setColor(DARK_INK[1], DARK_INK[2], DARK_INK[3], 1)
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
    resetTint(g)
    g.pop()
    battle._arNarratorTop = y
    return true
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
    -- HP / faces go on the extended HUD canvas so setBattleUIAnchor can
    -- dock them to the window. Move / command chrome stays on the UI canvas.
    local ren = battle and battle.game and battle.game.renderer
    local hudPrev
    local hudPass = ren and type(ren.beginBattleHUDPass) == "function"
        and type(ren.endBattleHUDPass) == "function"
    if hudPass then
        local ok, prev = pcall(ren.beginBattleHUDPass, ren)
        if ok then
            hudPrev = prev
        else
            hudPass = false
        end
    end
    UI.drawWorldHP(battle, nil, nil, "ui")
    resetTint(g)
    if hudPass then
        pcall(ren.endBattleHUDPass, ren, hudPrev)
    end
    resetTint(g)
    local paintedDialogue = false
    if state.showCommand then
        drawCommand(g, Font, battle)
    elseif state.showMoves then
        drawMoves(g, Font, battle, style)
    elseif state.showDialogue then
        paintedDialogue = drawDialogue(g, Font, battle) == true
    end
    if not paintedDialogue then
        battle._arNarratorTop = nil
    end
    resetTint(g)
    g.pop()
    -- HUD canvas blit uses the current multiply. Do not leave dark ink.
    resetTint(g)
end

return UI
