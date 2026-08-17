-- Battle chrome — live-stream notice stack (top-right).
--
-- Native 8px glyphs, black on cream. Readability over chrome: no scaled
-- type, no stacked fade, no slide-in that clips letters.

local Notices = {}

local byBattle = setmetatable({}, { __mode = "k" })

Notices.MAX = 2
Notices.HOLD = 2.4
Notices.FADE = 0.35
Notices.POP = 0.08
Notices.GAP = 2
Notices.LINE_H = 8
Notices.PAD_X = 4
Notices.PAD_Y = 3
Notices.MAX_W = 112
Notices.MAX_LINES = 2
Notices.RIGHT = 157
Notices.TOP = 2
Notices.FILL_ALPHA = 0.72
Notices.INK_ALPHA = 0.95

local FILL = { 1, 1, 0.94 }
local INK = { 0, 0, 0 }

local function now()
    if love and love.timer and type(love.timer.getTime) == "function" then
        return love.timer.getTime()
    end
    return os.clock()
end

local function font()
    local ok, Font = pcall(require, "src.render.Font")
    return ok and Font or nil
end

local function trim(s)
    return (tostring(s or ""):gsub("%s+", " "):match("^%s*(.-)%s*$")) or ""
end

-- Keep author line breaks; they already fit the 8px box.
function Notices.norm(text)
    local raw = tostring(text or ""):gsub("\v", "\n")
    local lines = {}
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        local flat = trim(line)
        if flat ~= "" then
            lines[#lines + 1] = flat
        end
    end
    return table.concat(lines, "\n")
end

local function bag(battle)
    local st = byBattle[battle]
    if not st then
        st = { items = {} }
        byBattle[battle] = st
    end
    return st
end

local function textWidth(Font, text)
    if Font and type(Font.width) == "function" then
        local ok, w = pcall(Font.width, text)
        if ok and tonumber(w) then
            return tonumber(w)
        end
    end
    if Font and type(Font.encode) == "function" and type(Font.advanceOf) == "function" then
        local ok, codes = pcall(Font.encode, text)
        if ok and type(codes) == "table" then
            local w = 0
            for i = 1, #codes do
                w = w + (Font.advanceOf(codes[i]) or 8)
            end
            return w
        end
    end
    return #tostring(text or "") * 8
end

local function wrapLine(Font, text, maxInner)
    if textWidth(Font, text) <= maxInner then
        return { text }
    end
    local words = {}
    for word in tostring(text or ""):gmatch("%S+") do
        words[#words + 1] = word
    end
    if #words == 0 then
        return { "" }
    end
    local lines = {}
    local cur = words[1]
    for i = 2, #words do
        local trial = cur .. " " .. words[i]
        if textWidth(Font, trial) <= maxInner then
            cur = trial
        else
            lines[#lines + 1] = cur
            cur = words[i]
        end
    end
    lines[#lines + 1] = cur
    return lines
end

local function wrap(Font, text, maxInner)
    local out = {}
    local raw = tostring(text or "")
    if raw == "" then
        return { "" }
    end
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        local chunks = wrapLine(Font, line, maxInner)
        for i = 1, #chunks do
            out[#out + 1] = chunks[i]
            if #out >= Notices.MAX_LINES then
                return out
            end
        end
    end
    if #out == 0 then
        out[1] = ""
    end
    return out
end

local function alphaOf(item, t)
    local age = t - (item.at or t)
    local hold = item.hold or Notices.HOLD
    if age < Notices.POP then
        return math.max(0.65, age / Notices.POP)
    end
    if age > hold then
        return math.max(0, 1 - (age - hold) / Notices.FADE)
    end
    return 1
end

local function prune(st, t)
    local items = st.items
    local keep = {}
    for i = 1, #items do
        local item = items[i]
        local hold = item.hold or Notices.HOLD
        if (t - (item.at or t)) < (hold + Notices.FADE) then
            keep[#keep + 1] = item
        end
    end
    st.items = keep
    return keep
end

function Notices.push(battle, text, opts)
    if type(battle) ~= "table" then
        return false
    end
    text = Notices.norm(text)
    if text == "" then
        return false
    end
    opts = opts or {}
    local st = bag(battle)
    local items = st.items
    local t = now()
    if items[1] and items[1].text == text and (t - (items[1].at or t)) < 0.35 then
        return true
    end
    table.insert(items, 1, {
        text = text,
        kind = tostring(opts.kind or "info"),
        at = t,
        hold = tonumber(opts.hold) or Notices.HOLD,
    })
    while #items > Notices.MAX do
        items[#items] = nil
    end
    return true
end

function Notices.items(battle)
    local st = battle and byBattle[battle]
    return (st and st.items) or {}
end

function Notices.clear(battle)
    if battle then
        byBattle[battle] = nil
    end
end

local function drawLine(Font, text, x, y)
    if type(Font.encode) == "function" and type(Font.drawCode) == "function" then
        local codes = Font.encode(text)
        local tx = x
        for j = 1, #codes do
            Font.drawCode(codes[j], tx, y)
            tx = tx + (Font.advanceOf and Font.advanceOf(codes[j]) or 8)
        end
        return
    end
    if type(Font.draw) == "function" then
        Font.draw(text, x, y)
    end
end

function Notices.draw(battle)
    if type(battle) ~= "table" or not (love and love.graphics) then
        return
    end
    local st = byBattle[battle]
    if not st then
        return
    end
    local t = now()
    local items = prune(st, t)
    if #items == 0 then
        return
    end
    local Font = font()
    if not Font then
        return
    end
    local g = love.graphics
    local maxInner = Notices.MAX_W - Notices.PAD_X * 2
    local y = Notices.TOP
    for i = 1, #items do
        local item = items[i]
        local a = alphaOf(item, t)
        if a > 0.12 then
            local lines = wrap(Font, item.text, maxInner)
            local innerW = 0
            for li = 1, #lines do
                innerW = math.max(innerW, textWidth(Font, lines[li]))
            end
            local bw = math.min(Notices.MAX_W, innerW + Notices.PAD_X * 2)
            bw = math.max(bw, 40)
            local bh = Notices.PAD_Y * 2 + #lines * Notices.LINE_H
            local x = Notices.RIGHT - bw
            g.push("all")
            g.setColor(FILL[1], FILL[2], FILL[3], Notices.FILL_ALPHA * a)
            g.rectangle("fill", x, y, bw, bh)
            g.setColor(INK[1], INK[2], INK[3], Notices.INK_ALPHA * a)
            local ty = y + Notices.PAD_Y
            for li = 1, #lines do
                drawLine(Font, lines[li], x + Notices.PAD_X, ty)
                ty = ty + Notices.LINE_H
            end
            g.pop()
            y = y + bh + Notices.GAP
        end
    end
end

return Notices
