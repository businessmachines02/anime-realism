-- Battle chrome — REACT / COUNTER pick HUD (GRID / TABS / DIAMOND).
--
-- Pipeline (when to open, what the pick does) stays in rules/react.lua.
-- This module paints the modal and owns D-pad / A confirm.

local Pick = {}
local host = {}

function Pick.bind(h)
    if type(h) == "table" then
        host = h
    end
    return Pick
end

-- Same cream/brown as the MOVE HUD, a notch darker.
local function reactChrome()
    return {
        paper = { 0.88, 0.83, 0.72 },
        cell = { 0.93, 0.88, 0.78 },
        selected = { 0.76, 0.70, 0.58 },
        ink = { 0.10, 0.07, 0.06 },
        muted = { 0.35, 0.30, 0.25 },
        fill255 = { 224, 212, 184 },
    }
end

local function reactHudStyle()
    local fn = host.reactHudStyle
    if type(fn) == "function" then
        local raw = tostring(fn() or "GRID"):upper()
        if raw == "TABS" or raw == "DIAMOND" then
            return raw
        end
    end
    return "GRID"
end

local function shortReactLabel(choice)
    local name = tostring(choice and choice.label or "")
    if name == "TAKE COVER" then
        return "COVER"
    end
    if name == "STAY COVER" then
        return "STAY"
    end
    if name == "PHYSICAL" then
        return "PHYS"
    end
    if name == "SPECIAL" then
        return "SPEC"
    end
    if name == "ENTRENCH" then
        return "ENTR"
    end
    return name
end

local function easeOutCubic(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local u = 1 - t
    return 1 - u * u * u
end

local function tabLabel(choice)
    local name = tostring(choice and choice.label or "")
    if name == "TAKE COVER" then
        return "COVER"
    end
    if name == "STAY COVER" then
        return "STAY"
    end
    return name
end

local function drawDirArrow(g, dir, cx, cy, rgb)
    g.setColor(rgb[1], rgb[2], rgb[3], 1)
    local s = 2
    if dir == "up" then
        g.polygon("fill", cx, cy - s - 1, cx - s, cy + s, cx + s, cy + s)
    elseif dir == "down" then
        g.polygon("fill", cx, cy + s + 1, cx - s, cy - s, cx + s, cy - s)
    elseif dir == "left" then
        g.polygon("fill", cx - s - 1, cy, cx + s, cy - s, cx + s, cy + s)
    elseif dir == "right" then
        g.polygon("fill", cx + s + 1, cy, cx - s, cy - s, cx - s, cy + s)
    end
end

local function glyphWidth(Font, text)
    if Font and type(Font.width) == "function" then
        local w = Font.width(text)
        if tonumber(w) then
            return tonumber(w)
        end
    end
    return #text * 8
end

local function isCommitChoice(choice)
    return choice and (choice.id == "commit" or choice.dir == "a")
end

-- Floating labels. No boxes, no dock panel — D-pad reacts only.
local function drawReactTabs(g, Font, modal, chrome)
    local choices = modal.choices
    local n = #choices
    if n < 1 then
        return
    end

    local byDir = {}
    local anyDir = false
    for i = 1, n do
        local choice = choices[i]
        if choice and choice.dir and not isCommitChoice(choice) then
            byDir[choice.dir] = choice
            anyDir = true
        end
    end

    local rows = {}
    if anyDir then
        local top = {}
        if byDir.left then
            top[#top + 1] = { dir = "left", choice = byDir.left }
        end
        if byDir.up then
            top[#top + 1] = { dir = "up", choice = byDir.up }
        end
        if byDir.right then
            top[#top + 1] = { dir = "right", choice = byDir.right }
        end
        local bot = {}
        if byDir.down then
            bot[#bot + 1] = { dir = "down", choice = byDir.down }
        end
        if #top == 0 and #bot == 0 then
            for i = 1, n do
                local choice = choices[i]
                if not isCommitChoice(choice) then
                    top[#top + 1] = { dir = choice.dir, choice = choice }
                end
            end
        end
        if #top > 0 then
            rows[#rows + 1] = top
        end
        if #bot > 0 then
            rows[#rows + 1] = bot
        end
    else
        rows[1] = {}
        for i = 1, n do
            local choice = choices[i]
            if not isCommitChoice(choice) then
                rows[1][#rows[1] + 1] = { dir = nil, choice = choice }
            end
        end
        if #rows[1] == 0 then
            return
        end
    end

    local inset = 4
    local gap = 8
    local rowH = 11
    local rowGap = 4
    local dockH = inset + #rows * rowH + math.max(0, #rows - 1) * rowGap + inset
    local t = easeOutCubic((modal._tabAge or 0) / 0.18)
    local y = 144 - dockH * t
    local preferred = choices[modal.index]

    for r = 1, #rows do
        local row = rows[r]
        local cols = #row
        if cols > 0 then
            local inner = 160 - inset * 2 - gap * (cols - 1)
            local cellW = math.floor(inner / cols)
            local leftover = inner - cellW * cols
            local x = inset + math.floor(leftover / 2)
            local rowY = y + inset + (r - 1) * (rowH + rowGap)
            for c = 1, cols do
                local slot = row[c]
                local choice = slot.choice
                local selected = preferred == choice
                local ink = chrome.muted
                if selected then
                    ink = chrome.ink
                end
                if choice and choice.disabled then
                    ink = chrome.muted
                end
                local label = tabLabel(choice)
                local tw = glyphWidth(Font, label)
                local arrowW = slot.dir and 7 or 0
                local total = arrowW + tw
                local scale = 1
                if total > cellW then
                    scale = cellW / total
                    total = cellW
                end
                local start = x + math.floor((cellW - total) / 2)
                if slot.dir then
                    drawDirArrow(g, slot.dir, start + 2, rowY + 5, ink)
                    start = start + arrowW
                end
                g.setColor(ink[1], ink[2], ink[3], 1)
                if Font and type(Font.draw) == "function" then
                    g.push()
                    g.translate(start, rowY + 2)
                    g.scale(scale, scale)
                    Font.draw(label, 0, 0)
                    g.pop()
                end
                if selected then
                    g.rectangle("fill", start, rowY + 10, math.max(1, tw * scale), 1)
                end
                x = x + cellW + gap
            end
        end
    end
    g.setColor(1, 1, 1, 1)
end

-- U/R/L/D compass plus A, same language as the MOVE HUD diamond.
local function drawReactDiamond(g, Font, modal, chrome)
    local preferred = modal.choices[modal.index]
    g.setColor(chrome.paper[1], chrome.paper[2], chrome.paper[3], 0.96)
    g.rectangle("fill", 0, 78, 160, 66)
    g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
    g.rectangle("line", 0.5, 78.5, 159, 65)
    g.rectangle("line", 1.5, 79.5, 157, 63)
    local title = modal.title or "REACT!"
    if Font and type(Font.draw) == "function" then
        g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
        Font.draw(title, 6, 80)
        if modal.subtitle then
            local sub = tostring(modal.subtitle)
            if #sub > 10 then
                sub = sub:sub(1, 9) .. "."
            end
            g.setColor(chrome.muted[1], chrome.muted[2], chrome.muted[3], 1)
            Font.draw(sub, 70, 80)
        end
    end
    local slots = {
        { dir = "up",    letter = "U", x = 56,  y = 92,  w = 48, h = 12 },
        { dir = "left",  letter = "L", x = 8,   y = 108, w = 52, h = 12 },
        { dir = "right", letter = "R", x = 100, y = 108, w = 52, h = 12 },
        { dir = "down",  letter = "D", x = 56,  y = 124, w = 48, h = 12 },
        { dir = "a",     letter = "A", x = 56,  y = 136, w = 48, h = 11 },
    }
    local byDir = {}
    for i = 1, #modal.choices do
        local choice = modal.choices[i]
        if choice and choice.dir then
            byDir[choice.dir] = choice
        end
    end
    for s = 1, #slots do
        local slot = slots[s]
        local choice = byDir[slot.dir]
        if choice then
            local selected = preferred == choice
            if selected then
                g.setColor(chrome.selected[1], chrome.selected[2], chrome.selected[3], 1)
            else
                g.setColor(chrome.cell[1], chrome.cell[2], chrome.cell[3], 1)
            end
            g.rectangle("fill", slot.x, slot.y, slot.w, slot.h)
            g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
            g.rectangle("line", slot.x + 0.5, slot.y + 0.5, slot.w - 1, slot.h - 1)
            local label = shortReactLabel(choice)
            if choice.disabled then
                label = "(" .. label .. ")"
                g.setColor(chrome.muted[1], chrome.muted[2], chrome.muted[3], 1)
            else
                g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
            end
            if Font and type(Font.draw) == "function" then
                Font.draw(slot.letter, slot.x + 2, slot.y + 2)
                local scale = (#label > 6) and 0.72 or 0.85
                g.push()
                g.translate(slot.x + 12, slot.y + 2)
                g.scale(scale, scale)
                Font.draw(label, 0, 0)
                g.pop()
            end
        end
    end
    g.setColor(1, 1, 1, 1)
end

local function drawReactGrid(g, Font, modal, chrome, choiceForDir)
    local preferred = modal.choices[modal.index]
    local x, y, w, h = 4, 100, 152, 40
    g.setColor(chrome.paper[1], chrome.paper[2], chrome.paper[3], 0.96)
    g.rectangle("fill", x, y, w, h)
    g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
    g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
    if w > 3 and h > 3 then
        g.rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3)
    end
    local title = modal.title or "REACT!"
    g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
    Font.draw(title, x + 6, y + 3)
    local aChoice = choiceForDir("a")
    if modal.subtitle and not aChoice then
        local sub = tostring(modal.subtitle)
        if #sub > 8 then
            sub = sub:sub(1, 7) .. "."
        end
        g.setColor(chrome.muted[1], chrome.muted[2], chrome.muted[3], 1)
        Font.draw(sub, x + 58, y + 3)
    end
    if aChoice then
        local aLabel = shortReactLabel(aChoice)
        local selectedA = preferred == aChoice
        if selectedA then
            g.setColor(chrome.selected[1], chrome.selected[2],
                chrome.selected[3], 1)
            g.rectangle("fill", x + w - 58, y + 2, 52, 10)
        end
        if aChoice.disabled then
            g.setColor(chrome.muted[1], chrome.muted[2], chrome.muted[3], 1)
        else
            g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
        end
        Font.draw("A", x + w - 56, y + 3)
        g.push()
        g.translate(x + w - 46, y + 3)
        g.scale(0.75, 0.75)
        Font.draw(aLabel, 0, 0)
        g.pop()
    end
    local slots = {
        { dir = "up",    letter = "U", col = 0, row = 0 },
        { dir = "right", letter = "R", col = 1, row = 0 },
        { dir = "left",  letter = "L", col = 0, row = 1 },
        { dir = "down",  letter = "D", col = 1, row = 1 },
    }
    local colW = 74
    for s = 1, #slots do
        local slot = slots[s]
        local choice = choiceForDir(slot.dir)
        if choice then
            local tx = x + 6 + slot.col * colW
            local ty = y + 14 + slot.row * 12
            local selected = preferred == choice
            if selected then
                g.setColor(chrome.selected[1], chrome.selected[2],
                    chrome.selected[3], 1)
                g.rectangle("fill", tx - 2, ty - 1, colW - 4, 11)
                if type(Font.drawCode) == "function" then
                    g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
                    Font.drawCode(0xED, tx, ty)
                end
            end
            local label = shortReactLabel(choice)
            if choice.disabled then
                label = "(" .. label .. ")"
                g.setColor(chrome.muted[1], chrome.muted[2], chrome.muted[3], 1)
            else
                g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
            end
            Font.draw(slot.letter, tx + 12, ty)
            local scale = (#label > 6) and 0.72 or 0.85
            g.push()
            g.translate(tx + 22, ty)
            g.scale(scale, scale)
            Font.draw(label, 0, 0)
            g.pop()
        end
    end
    g.setColor(1, 1, 1, 1)
end

local function drawReactList(Font, modal, chrome)
    local n = #modal.choices
    local widest = #Font.split(modal.title)
    if modal.subtitle then
        widest = math.max(widest, #Font.split(modal.subtitle))
    end
    for i = 1, n do
        local label = tostring(modal.choices[i].label or "")
        widest = math.max(widest, #Font.split(label) + 2)
    end
    local tw = math.min(16, math.max(10, widest + 2))
    local head = modal.subtitle and 2 or 1
    local th = head + n + 2
    local tx = 1
    local ty = math.max(1, 13 - th)
    if ty + th > 13 then
        th = 13 - ty
    end

    Font.drawBox(tx, ty, tw, th, chrome.fill255)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(modal.title, (tx + 1) * 8, (ty + 1) * 8)
    local row = ty + 2
    if modal.subtitle then
        Font.draw(modal.subtitle, (tx + 1) * 8, row * 8)
        row = row + 1
    end
    for i = 1, n do
        local choice = modal.choices[i]
        local y = row * 8
        if i == modal.index then
            Font.drawCode(0xED, tx * 8 + 2, y)
        end
        Font.draw(tostring(choice.label or ""), (tx + 2) * 8, y)
        row = row + 1
        if row >= ty + th - 1 then
            break
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Pick.newModal(game, opts)
    local Font = require("src.render.Font")
    local Sound = require("src.core.Sound")
    local choices = opts.choices or {}
    local start = tonumber(opts.index) or 1
    if start < 1 then
        start = 1
    end
    if #choices > 0 and start > #choices then
        start = #choices
    end
    -- D-pad picks instantly when there are few options (REACT / BRACE / STAY).
    -- Long lists (COUNTER move pick) keep cursor + A.
    local usePad = opts.pad
    if usePad == nil then
        usePad = #choices > 0 and #choices <= 5
    end
    local style = reactHudStyle()
    local hideCommit = style == "TABS"

    local function ensurePadDirs()
        if not usePad then
            return
        end
        for i = 1, #choices do
            if choices[i].dir then
                return
            end
        end
        local byId = {}
        for i = 1, #choices do
            local id = choices[i].id
            if id then
                byId[id] = choices[i]
            end
        end
        if byId.dodge or byId.commit or byId.entrench then
            if byId.dodge then
                byId.dodge.dir = "up"
            end
            if byId.cover then
                byId.cover.dir = "left"
            end
            if byId.brace then
                byId.brace.dir = "right"
            end
            if byId.entrench then
                byId.entrench.dir = "down"
            end
            if byId.commit and not hideCommit then
                byId.commit.dir = "a"
            end
            if byId.entrench_hold then
                byId.entrench_hold.dir = "down"
            end
            if byId.entrench_break then
                byId.entrench_break.dir = "up"
            end
            return
        end
        local n = #choices
        if n == 1 then
            choices[1].dir = "a"
        elseif n == 2 then
            choices[1].dir = "up"
            choices[2].dir = "down"
        elseif n == 3 then
            choices[1].dir = "up"
            choices[2].dir = "left"
            choices[3].dir = "right"
        elseif n == 4 then
            choices[1].dir = "up"
            choices[2].dir = "left"
            choices[3].dir = "right"
            choices[4].dir = "down"
        else
            choices[1].dir = "up"
            choices[2].dir = "left"
            choices[3].dir = "right"
            choices[4].dir = "down"
            if not hideCommit then
                choices[5].dir = "a"
            end
        end
    end
    ensurePadDirs()

    local self = {
        game = game,
        title = tostring(opts.title or "DODGE!"),
        subtitle = opts.subtitle and tostring(opts.subtitle) or nil,
        choices = choices,
        index = start,
        usePad = usePad,
        style = style,
        cancelable = opts.cancelable == true,
        onPick = opts.onPick,
        onCancel = opts.onCancel,
        -- Instant D-pad picks must not fire on the same press that opened
        -- this modal (or a leftover held direction from the prior menu).
        _padArmed = not usePad,
        _tabAge = 0,
        _resolved = false,
    }

    local function choiceForDir(dir)
        for i = 1, #self.choices do
            if self.choices[i].dir == dir then
                return self.choices[i]
            end
        end
        return nil
    end

    local function anyPadDown(input)
        local down = input.isDown or input.down
        if type(down) ~= "function" then
            return false
        end
        return down(input, "up") or down(input, "down")
            or down(input, "left") or down(input, "right")
            or down(input, "a")
    end

    local function confirm(choice)
        if self._resolved or not choice then
            return
        end
        self._resolved = true
        Sound.play(self.game.data, "Press_AB")
        self.game.stack:pop()
        if self.onPick then
            self.onPick(choice)
        end
    end

    function self:update(dt)
        if self.usePad and self.style == "TABS" then
            self._tabAge = (self._tabAge or 0) + (tonumber(dt) or 0)
        end
        local input = self.game.input
        local n = #self.choices
        if n < 1 or self._resolved then
            return
        end
        if self.cancelable
            and (input:wasPressed("b") or input:wasPressed("start")) then
            self._resolved = true
            Sound.play(self.game.data, "Press_AB")
            self.game.stack:pop()
            if self.onCancel then
                self.onCancel()
            end
            return
        end
        if self.usePad then
            -- Wait until every direction/A is released once so a held
            -- press from opening / the previous modal cannot auto-pick.
            if not self._padArmed then
                if not anyPadDown(input) then
                    self._padArmed = true
                end
                return
            end
            local dir = nil
            if input:wasPressed("up") then
                dir = "up"
            elseif input:wasPressed("down") then
                dir = "down"
            elseif input:wasPressed("left") then
                dir = "left"
            elseif input:wasPressed("right") then
                dir = "right"
            elseif input:wasPressed("a") then
                dir = "a"
            end
            if dir then
                confirm(choiceForDir(dir))
            end
            return
        end
        if input:wasPressed("up") then
            self.index = self.index > 1 and self.index - 1 or n
        elseif input:wasPressed("down") then
            self.index = self.index < n and self.index + 1 or 1
        elseif input:wasPressed("a") then
            confirm(self.choices[self.index])
        end
    end

    function self:draw()
        local n = #self.choices
        if n < 1 then
            return
        end
        local g = love.graphics

        if self.usePad then
            if self.style == "TABS" then
                drawReactTabs(g, Font, self, reactChrome())
                return
            end
            if self.style == "DIAMOND" then
                drawReactDiamond(g, Font, self, reactChrome())
                return
            end
            -- Compact full-width 2×2 (GRID). U/R on top, L/D below;
            -- A (COMMIT) sits on the header row.
            drawReactGrid(g, Font, self, reactChrome(), choiceForDir)
            return
        end

        drawReactList(Font, self, reactChrome())
    end

    return self
end

return Pick
