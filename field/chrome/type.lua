-- Field chrome typeface. Authored HUD / chip / callout copy uses this
-- pixel face; engine narrator tiles stay on Font.drawCode.

local Type = {}

Type.FILE = "assets/pokepixel-gba.ttf"
Type.SIZE = 8
Type.TRACK = 1
Type.INK = { 0.10, 0.08, 0.06, 1 }
Type.KEEP = {
    A = true, B = true, U = true, R = true, L = true, D = true,
    PP = true, HP = true, PKMN = true,
}

local cached
local failed

function Type.bindRoot(root)
    if type(root) == "string" and root ~= "" then
        Type.root = root:gsub("[/\\]+$", "")
    else
        Type.root = nil
    end
    cached = nil
    failed = nil
    Type.loadedPath = nil
end

function Type.bindReader(read)
    Type.read = type(read) == "function" and read or nil
    cached = nil
    failed = nil
end

local function addPath(out, path)
    if type(path) ~= "string" or path == "" then
        return
    end
    for i = 1, #out do
        if out[i] == path then
            return
        end
    end
    out[#out + 1] = path
end

function Type.paths()
    local out = {}
    addPath(out, Type.FILE)
    if Type.root then
        addPath(out, Type.root .. "/" .. Type.FILE)
    end
    return out
end

-- ALL-CAPS engine words become Title case so the pixel lowercase reads.
-- Compass letters and HUD tags (PP, PKMN) stay as written.
function Type.display(text)
    text = tostring(text or "")
    if text == "" then
        return text
    end
    return (text:gsub("(%S+)", function(word)
        if Type.KEEP[word] then
            return word
        end
        if word:find("%l") or not word:find("%a") then
            return word
        end
        if #word == 1 then
            return word
        end
        return word:sub(1, 1) .. word:sub(2):lower()
    end))
end

local function readBytes(path)
    if Type.read then
        local ok, body = pcall(Type.read, path or Type.FILE)
        if ok and type(body) == "string" and #body > 100 then
            return body
        end
    end
    local try = {
        path,
        Type.root and (Type.root .. "/" .. Type.FILE) or nil,
        Type.FILE,
    }
    for i = 1, #try do
        local p = try[i]
        if type(p) == "string" then
            local f = io.open(p, "rb")
            if f then
                local body = f:read("*a")
                f:close()
                if type(body) == "string" and #body > 100 then
                    return body
                end
            end
            local fs = love and love.filesystem
            if fs and type(fs.read) == "function" then
                local ok, body = pcall(fs.read, p)
                if ok and type(body) == "string" and #body > 100 then
                    return body
                end
            end
        end
    end
    return nil
end

local function makeFont(g, source)
    local ok, face = pcall(g.newFont, source, Type.SIZE, "mono", 1)
    if not ok or not face then
        ok, face = pcall(g.newFont, source, Type.SIZE)
    end
    if ok and face then
        if type(face.setFilter) == "function" then
            pcall(face.setFilter, face, "nearest", "nearest")
        end
        return face
    end
    return nil
end

function Type.font()
    if cached then
        return cached
    end
    if failed then
        return nil
    end
    local g = love and love.graphics
    if not (g and type(g.newFont) == "function") then
        return nil
    end
    local okP, paths = pcall(Type.paths)
    if okP and type(paths) == "table" then
        for i = 1, #paths do
            local face = makeFont(g, paths[i])
            if face then
                cached = face
                Type.loadedPath = paths[i]
                return cached
            end
        end
    end
    local bytes = readBytes(Type.FILE)
    local fs = love and love.filesystem
    if bytes and fs and type(fs.newFileData) == "function" then
        local okD, data = pcall(fs.newFileData, bytes, "pokepixel-gba.ttf")
        if okD and data then
            local face = makeFont(g, data)
            if face then
                cached = face
                Type.loadedPath = "bytes"
                return cached
            end
        end
    end
    failed = true
    return nil
end

local function trackedWidth(face, text)
    local track = Type.TRACK or 0
    local w = 0
    local n = 0
    for i = 1, #text do
        local ch = text:sub(i, i)
        w = w + (tonumber(face:getWidth(ch)) or 5)
        n = n + 1
    end
    if n > 1 then
        w = w + track * (n - 1)
    end
    return w
end

function Type.width(text, Font)
    text = Type.display(text)
    local face = Type.font()
    if face and type(face.getWidth) == "function" then
        if (Type.TRACK or 0) > 0 then
            return trackedWidth(face, text)
        end
        return tonumber(face:getWidth(text)) or (#text * 5)
    end
    if Font and type(Font.width) == "function" then
        return tonumber(Font.width(text)) or (#text * 8)
    end
    if Font and type(Font.getWidth) == "function" then
        return tonumber(Font.getWidth(text)) or (#text * 8)
    end
    return #text * 6
end

function Type.draw(g, text, x, y, ink, Font, opts)
    if not g then
        return false
    end
    text = Type.display(text)
    ink = ink or Type.INK
    opts = type(opts) == "table" and opts or nil
    local face = Type.font()
    if face and type(g.print) == "function" then
        local prev
        if type(g.getFont) == "function" then
            prev = g.getFont()
        end
        if type(g.setFont) == "function" then
            g.setFont(face)
        end
        g.setColor(ink[1], ink[2], ink[3], ink[4] or 1)
        local track = Type.TRACK or 0
        if opts and opts.track ~= nil then
            track = tonumber(opts.track) or 0
        end
        if track > 0 and type(face.getWidth) == "function" then
            local cx = x
            for i = 1, #text do
                local ch = text:sub(i, i)
                g.print(ch, cx, y)
                cx = cx + (tonumber(face:getWidth(ch)) or 5) + track
            end
        else
            g.print(text, x, y)
        end
        if prev and type(g.setFont) == "function" then
            g.setFont(prev)
        end
        return true
    end
    if Font and type(Font.draw) == "function" then
        if type(g.setColor) == "function" then
            g.setColor(ink[1], ink[2], ink[3], ink[4] or 1)
        end
        Font.draw(text, x, y)
        return true
    end
    if type(g.print) == "function" then
        if type(g.setColor) == "function" then
            g.setColor(ink[1], ink[2], ink[3], ink[4] or 1)
        end
        g.print(text, x, y)
        return true
    end
    return false
end

return Type
