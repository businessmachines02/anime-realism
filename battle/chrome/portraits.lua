-- Battle chrome — PMD 40×40 emotion portraits (issue #74 v1).
--
-- Lazy-loads Gen 1 root files: assets/portrait/{dex:04d}/{Emotion}.png
-- Form / shiny folders and Emotion^.png flips wait. No boot preload.

local Portraits = {}

Portraits.SIZE = 40
Portraits.CHIP = 16
Portraits.FLASH = 28
Portraits.CLASSIC = 32

local host = {}
local cache = {}

function Portraits.bind(h)
    if type(h) == "table" then
        host = h
    end
    return Portraits
end

local function emotions()
    return host.Emotions
end

local function facesOn()
    local fn = host.facesOn
    if type(fn) == "function" then
        return fn() ~= false
    end
    local opt = host.opt
    if type(opt) == "function" then
        return opt("battle_faces") ~= false
    end
    return true
end

function Portraits.emotionFile(mood)
    local E = emotions()
    if E and type(E.fileName) == "function" then
        return E.fileName(mood)
    end
    local map = {
        normal = "Normal",
        pain = "Pain",
        determined = "Determined",
        worried = "Worried",
        angry = "Angry",
        stunned = "Stunned",
        surprised = "Surprised",
        sigh = "Sigh",
        happy = "Happy",
    }
    return map[tostring(mood or "")] or "Normal"
end

local function handleRoot(handle)
    local root = handle and (handle.path or handle.root)
    if type(root) == "string" and root ~= "" then
        return root
    end
    return nil
end

function Portraits.modRoot(mod)
    if type(mod) ~= "table" then
        mod = host.mod
    end
    if type(mod) ~= "table" then
        return nil
    end
    local root = handleRoot(mod)
    if root then
        return root
    end
    if type(mod.path) == "string" and mod.path ~= "" then
        return mod.path
    end
    if type(mod.root) == "string" and mod.root ~= "" then
        return mod.root
    end
    return nil
end

function Portraits.dexOf(battle, battler)
    local mon = battler and battler.mon
    local n = tonumber(mon and (mon.dex or mon.natDex or mon.number))
        or tonumber(battler and (battler.dex or battler.dexNumber))
    if n and n > 0 then
        return math.floor(n)
    end
    local species = mon and (mon.species or mon.name)
    if type(species) == "number" and species > 0 then
        return math.floor(species)
    end
    local key = tostring(species or ""):upper()
    if key == "" then
        return nil
    end
    local data = battle and battle.game and battle.game.data and battle.game.data.pokemon
    data = data or (battle and battle.data and battle.data.pokemon)
    local def = data and data[key]
    local dex = def and tonumber(def.dex)
    if dex and dex > 0 then
        return math.floor(dex)
    end
    return nil
end

function Portraits.relPath(dex, emotion)
    dex = tonumber(dex)
    if not dex or dex < 1 then
        return nil
    end
    local file = Portraits.emotionFile(emotion)
    return string.format("assets/portrait/%04d/%s.png", math.floor(dex), file)
end

local function pathExists(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function loadImage(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    local cached = cache[path]
    if cached ~= nil then
        return cached or nil
    end
    local img
    local okA, Assets = pcall(require, "src.render.Assets")
    if okA and Assets and type(Assets.image) == "function" then
        local ok, got = pcall(Assets.image, path)
        if ok and got then
            img = got
        end
    end
    if not img and love and love.graphics and love.graphics.newImage then
        local ok, got = pcall(love.graphics.newImage, path)
        if ok and got then
            img = got
        end
    end
    cache[path] = img or false
    if img and img.setFilter then
        pcall(img.setFilter, img, "nearest", "nearest")
    end
    return img
end

function Portraits.resolve(mod, dex, emotion)
    local root = Portraits.modRoot(mod)
    local rel = Portraits.relPath(dex, emotion)
    if not rel then
        return nil
    end
    local candidates = {}
    if root then
        candidates[#candidates + 1] = root .. "/" .. rel
    end
    candidates[#candidates + 1] = rel
    if emotion and emotion ~= "normal" then
        local fallback = Portraits.relPath(dex, "normal")
        if fallback then
            if root then
                candidates[#candidates + 1] = root .. "/" .. fallback
            end
            candidates[#candidates + 1] = fallback
        end
    end
    for i = 1, #candidates do
        local path = candidates[i]
        local img = loadImage(path)
        if img then
            return img, path
        end
        if pathExists(path) then
            return nil, path
        end
    end
    return nil, rel
end

function Portraits.image(battle, isPlayer, mood)
    if not facesOn() then
        return nil
    end
    local battler = isPlayer and (battle and battle.player) or (battle and battle.enemy)
    local dex = Portraits.dexOf(battle, battler)
    if not dex then
        return nil
    end
    if not mood then
        local E = emotions()
        mood = "normal"
        if E and type(E.mood) == "function" then
            mood = E.mood(battle, isPlayer) or "normal"
        end
    end
    return Portraits.resolve(host.mod, dex, mood)
end

function Portraits.flash(battle, isPlayer)
    if not facesOn() then
        return nil, 0
    end
    local E = emotions()
    local alpha = 0
    local mood
    if E and type(E.portraitAlpha) == "function" then
        alpha = tonumber(E.portraitAlpha(battle, isPlayer)) or 0
    end
    if alpha <= 0.02 then
        return nil, 0
    end
    if E and type(E.portraitMood) == "function" then
        mood = E.portraitMood(battle, isPlayer)
    end
    local img = Portraits.image(battle, isPlayer, mood)
    return img, alpha, mood
end

function Portraits.drawChip(g, img, x, y, size, alpha)
    if not (g and img and type(g.draw) == "function") then
        return
    end
    size = tonumber(size) or Portraits.FLASH
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
end

-- Classic overlay: face stays while the mood is up. Player bottom-left,
-- foe top-right.
function Portraits.draw(battle)
    if not facesOn() or type(battle) ~= "table" then
        return
    end
    if not (love and love.graphics) then
        return
    end
    local g = love.graphics
    local size = Portraits.CLASSIC
    local player, pA = Portraits.flash(battle, true)
    local foe, eA = Portraits.flash(battle, false)
    g.push("all")
    if player then
        Portraits.drawChip(g, player, 4, 108, size, pA)
    end
    if foe then
        Portraits.drawChip(g, foe, 160 - 4 - size, 4, size, eA)
    end
    g.pop()
end

return Portraits
