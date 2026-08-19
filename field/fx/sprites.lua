-- Field battle — OW follower sprites as battlers + motion.
--
-- Sprite set is user-pickable (FIELD SPRITES): AUTO matches Wilds of Kanto
-- if that mod is loaded, else GSC follower sheets. GSC / HGSS / POKEDEX
-- pull from PokePCFollowers, FOLLOWERS_EX, or Wilds packs. FIELD always
-- uses animated 2D overworld art — never voxel mon meshes.
-- Dodge poses (issue #66) live here: type/speed pick a style, then tick
-- offsets + squash/fade/afterimages on the live sprite.

local Sprites = {}

local function loadImage(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  -- Same loader the follower pack uses successfully with absolute paths.
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and type(Assets.image) == "function" then
    local ok, img = pcall(Assets.image, path)
    if ok and img then
      return img
    end
  end
  if love and love.graphics and love.graphics.newImage then
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
      return img
    end
  end
  return nil
end

local function findHandle(mod, id)
  if not (mod and type(mod.find) == "function") then
    return nil
  end
  local ok, handle = pcall(mod.find, mod, id)
  if ok and handle then
    return handle
  end
  ok, handle = pcall(mod.find, id)
  if ok and handle then
    return handle
  end
  return nil
end

local function loadablePath(path)
  if loadImage(path) then
    return path
  end
  return nil
end

local function handleRoot(handle)
  local root = handle and (handle.path or handle.root)
  if type(root) == "string" and root ~= "" then
    return root
  end
  return nil
end

local function speciesDex(game, species)
  if type(species) == "number" then
    return species
  end
  local key = tostring(species or ""):upper()
  if key == "" then
    return nil
  end
  local data = game and game.data and game.data.pokemon
  local def = data and data[key]
  local dex = def and tonumber(def.dex)
  if dex and dex > 0 then
    return dex
  end
  return nil
end

local function isShinyBattler(battler)
  local mon = battler and battler.mon
  if not mon then
    return false
  end
  if mon.shiny == true or mon.isShiny == true then
    return true
  end
  return false
end

local STYLE_ALIAS = {
  AUTO = "AUTO",
  GSC = "followers",
  FOLLOWERS = "followers",
  FOLLOWER = "followers",
  FOLLOWERS_EX = "followers",
  HGSS = "pokemmo",
  POKEMMO = "pokemmo",
  POKEDEX = "pokedex",
  DEX = "pokedex",
}

function Sprites.normalizeSpriteStyle(value)
  local raw = tostring(value or "AUTO"):upper()
  raw = raw:gsub("%s+", "_"):gsub("[^A-Z0-9_]", "")
  return STYLE_ALIAS[raw] or STYLE_ALIAS[tostring(value or ""):lower()] or "followers"
end

function Sprites.fieldSpriteStyle(mod)
  local raw = "AUTO"
  if mod and mod.options and type(mod.options.get) == "function" then
    raw = tostring(mod.options:get("field_sprites") or "AUTO")
  end
  local chosen = tostring(raw):upper()
  if chosen ~= "AUTO" and chosen ~= "" then
    return Sprites.normalizeSpriteStyle(chosen)
  end
  local wilds = findHandle(mod, "overworld_wild_spawns")
  if wilds then
    local ex = wilds.exports
    if ex and type(ex.spriteStyle) == "function" then
      local ok, style = pcall(ex.spriteStyle)
      if ok and type(style) == "string" and style ~= "" then
        return Sprites.normalizeSpriteStyle(style)
      end
    end
    if wilds.options and type(wilds.options.get) == "function" then
      local ok, style = pcall(wilds.options.get, wilds.options, "sprite_style")
      if ok and type(style) == "string" and style ~= "" then
        return Sprites.normalizeSpriteStyle(style)
      end
    end
  end
  return "followers"
end

local function sheetFromPath(path, frames, walker)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return { image = path, frames = frames or 6, walker = walker ~= false, trueColor = true }
end

local function pokePcPath(mod, game, species)
  local key = tostring(species or ""):upper()
  local ids = { "PokePCFollowers_VoxelMerge", "FOLLOWERS_EX" }
  for i = 1, #ids do
    local handle = findHandle(mod, ids[i])
    local ex = handle and handle.exports
    if ex and type(ex.assetPath) == "function" then
      local ok, path = pcall(ex.assetPath, key)
      if ok and type(path) == "string" and path ~= "" then
        return path
      end
    end
    local root = handleRoot(handle)
    local dex = speciesDex(game, key)
    if root and dex then
      local path = loadablePath(root .. "/assets/sprites/follower_"
        .. string.format("%03d", dex) .. ".png")
      if path then
        return path
      end
    end
  end
  return nil
end

local function wildsRoot(mod)
  local handle = findHandle(mod, "overworld_wild_spawns")
  return handleRoot(handle)
end

local function wildsPackPath(mod, game, species, style, shiny)
  local dex = speciesDex(game, species)
  if not dex then
    return nil
  end
  local root = wildsRoot(mod)
  if not root then
    return nil
  end
  local nnn = string.format("%03d", dex)
  local variant = shiny and "shiny" or "normal"
  local candidates
  if style == "pokemmo" then
    candidates = {
      root .. "/assets/generated/true_size/hgss/" .. nnn .. "-" .. variant .. ".png",
      root .. "/assets/generated/followsprites_runtime/" .. nnn .. "-" .. variant .. ".png",
      root .. "/assets/generated/true_size/hgss/" .. nnn .. "-normal.png",
      root .. "/assets/generated/followsprites_runtime/" .. nnn .. "-normal.png",
    }
  elseif style == "pokedex" then
    candidates = {
      root .. "/assets/generated/true_size/pokedex/" .. nnn .. "-" .. variant .. ".png",
      root .. "/assets/generated/true_size/pokedex/" .. nnn .. "-normal.png",
    }
  else
    candidates = {
      root .. "/assets/enhanced_overworld/poke_followers/follower_"
        .. nnn .. "_" .. variant .. ".png",
      root .. "/assets/enhanced_overworld/poke_followers/follower_"
        .. nnn .. "_normal.png",
      root .. "/assets/generated/true_size/followers/" .. nnn .. "-" .. variant .. ".png",
      root .. "/assets/generated/true_size/followers/" .. nnn .. "-normal.png",
    }
  end
  for i = 1, #candidates do
    local path = loadablePath(candidates[i])
    if path then
      return path
    end
  end
  return nil
end

local function wildsExportSheet(mod, game, species, style, shiny, surface)
  local wilds = findHandle(mod, "overworld_wild_spawns")
  local ex = wilds and wilds.exports
  if not (ex and type(ex.resolveFollowerSprite) == "function") then
    return nil
  end
  local opts = {
    species = species,
    shiny = shiny == true,
    style = style,
    game = game,
    surface = surface or "land",
    -- Wilds/follower API token (stable; not the package folder name).
    role = "field_battle",
  }
  -- AUTO with Wilds present: omit style so Wilds uses its own Sprite Style.
  if style == nil then
    opts.style = nil
  end
  local ok, def = pcall(ex.resolveFollowerSprite, opts)
  if ok and type(def) == "table" and type(def.image) == "string" and def.image ~= "" then
    return {
      image = def.image,
      frames = tonumber(def.frames) or 6,
      walker = def.walker ~= false,
      trueColor = def.trueColor ~= false,
      frameWidth = def.frameWidth,
      frameHeight = def.frameHeight,
      providerId = def.providerId,
      surface = surface or "land",
    }
  end
  return nil
end

local function typesFromBattler(battler, game, species)
  local types = battler and battler.curTypes
  if (not types or #types == 0) and battler and battler.def then
    types = battler.def.types
  end
  if (not types or #types == 0) and battler and battler.mon then
    local mon = battler.mon
    if mon.type1 or mon.type2 then
      types = { mon.type1, mon.type2 }
    else
      types = mon.types
    end
  end
  if (not types or #types == 0) and game and species then
    local data = game.data
    local poke = data and (data.pokemon or data.species)
    local def = poke and poke[species]
    types = def and def.types
  end
  local out = {}
  for i = 1, #(types or {}) do
    local name = tostring(types[i] or ""):upper()
    if name ~= "" then
      out[#out + 1] = name
    end
  end
  return out
end

function Sprites.monTypes(source, game, species)
  if source and source._battleBattler then
    return typesFromBattler(
      source._battleBattler,
      game or source._spriteGame,
      species or source._spriteSpecies)
  end
  return typesFromBattler(source, game, species)
end

function Sprites.hasType(source, want, game, species)
  want = tostring(want or ""):upper()
  local types = Sprites.monTypes(source, game, species)
  for i = 1, #types do
    if types[i] == want then
      return true
    end
  end
  return false
end

function Sprites.isWaterType(battler, game, species)
  return Sprites.hasType(battler, "WATER", game, species)
end

-- Sprite-shift + type-flavored dodges (issue #66). Generics cycle so two
-- Normal-types in a row do not always hop the same way.
local DODGE_GENERIC = { "sidehop", "duck", "lean", "hop" }
local DODGE_ROUND = {
  VOLTORB = true, ELECTRODE = true, JIGGLYPUFF = true, WIGGLYTUFF = true,
  CHANSEY = true, DITTO = true, KOFFING = true, WEEZING = true,
  SHELLDER = true, CLOYSTER = true, EXEGGCUTE = true,
  MAGNEMITE = true, MAGNETON = true,
}
local DODGE_DUR = {
  sidehop = 0.38, duck = 0.40, lean = 0.42, hop = 0.42, blur = 0.28,
  lift = 0.46, phase = 0.44, splash = 0.40, burrow = 0.42, static = 0.34,
}

local function dodgeRand()
  return (love and love.math and love.math.random) or math.random
end

local function dodgeSpecies(ent)
  if not ent then
    return ""
  end
  local id = ent._spriteSpecies or ent.species
  if not id and ent._battleBattler then
    local battler = ent._battleBattler
    local mon = battler.mon
    id = battler.species
        or (mon and (mon.pokemon or mon.id or mon.species or mon.name))
  end
  return tostring(id or ""):upper():gsub("%s+", "_")
end

local function dodgeSpeed(ent)
  local stats = ent and ent._closeGapStats
  if type(stats) ~= "table" then
    local battler = ent and ent._battleBattler
    stats = battler and (battler.stats or (battler.mon and battler.mon.stats))
  end
  if type(stats) == "table" then
    return tonumber(stats.speed or stats.spe) or 0
  end
  return 0
end

function Sprites.pickDodgeStyle(ent)
  if Sprites.hasType(ent, "GHOST") then
    return "phase"
  end
  if Sprites.hasType(ent, "ELECTRIC") then
    return "static"
  end
  if Sprites.hasType(ent, "FLYING") then
    return "lift"
  end
  if Sprites.hasType(ent, "WATER") then
    return "splash"
  end
  if Sprites.hasType(ent, "BUG") or Sprites.hasType(ent, "GRASS") then
    return "burrow"
  end
  if dodgeSpeed(ent) >= 100 then
    return "blur"
  end
  if DODGE_ROUND[dodgeSpecies(ent)] then
    return "hop"
  end
  local n = (ent and ent._dodgeGenericN or 0) + 1
  if ent then
    ent._dodgeGenericN = n
  end
  return DODGE_GENERIC[((n - 1) % #DODGE_GENERIC) + 1]
end

local function clearDodgePose(self)
  self.drawScale = 1
  self.drawScaleX = nil
  self.drawScaleY = nil
  self.drawAngle = 0
  self.drawAlpha = 1
  self._dodgeTrail = nil
  self._dodgeBits = nil
  self._dodgeFxSpawned = nil
  self._dodgeStyle = nil
end

local function spawnDodgeBits(self, count, color, kind)
  local rand = dodgeRand()
  self._dodgeBits = self._dodgeBits or {}
  local bx = self.basePx or self.px or 0
  local by = (self.basePy or self.py or 0) + 10
  for _ = 1, count do
    self._dodgeBits[#self._dodgeBits + 1] = {
      kind = kind or "spark",
      t = 0,
      life = 0.26 + rand() * 0.14,
      x = bx + (rand() - 0.5) * 12,
      y = by + (rand() - 0.5) * 4,
      vx = (rand() - 0.5) * 52,
      vy = -14 - rand() * 30,
      color = color,
    }
  end
end

local function finiteCoord(n, fallback)
  if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
    return fallback
  end
  return n
end

local function voxelFacing(facing)
  if facing == "up" or facing == "down" or facing == "left" or facing == "right" then
    return facing
  end
  return "down"
end

local function faceFromDelta(dx, dy)
  if math.abs(dx or 0) >= math.abs(dy or 0) then
    return (dx or 0) >= 0 and "right" or "left"
  end
  return (dy or 0) >= 0 and "down" or "up"
end

local function tickDodgeBits(self, dt)
  local bits = self._dodgeBits
  if not bits then
    return
  end
  local live = {}
  for i = 1, #bits do
    local bit = bits[i]
    bit.t = bit.t + dt
    bit.x = bit.x + bit.vx * dt
    bit.y = bit.y + bit.vy * dt
    bit.vy = bit.vy + 90 * dt
    if bit.t < bit.life then
      live[#live + 1] = bit
    end
  end
  self._dodgeBits = live
end

--- Extra ox/oy + drawScale/alpha/angle for the live dodge style.
local function tickDodge(self, dt, towardX, towardY)
  self.animT = (self.animT or 0) + dt
  local style = self._dodgeStyle or "sidehop"
  local dur = DODGE_DUR[style] or 0.38
  local t = math.min(1, self.animT / dur)
  local pulse = math.sin(t * math.pi)
  local tx = self.basePx - (towardX or self.basePx)
  local ty = self.basePy - (towardY or self.basePy)
  local len = math.sqrt(tx * tx + ty * ty)
  local lx, ly = 1, 0
  local ax, ay = 0, -1
  if len > 0.1 then
    lx, ly = -ty / len, tx / len
    ax, ay = tx / len, ty / len
    self.facing = faceFromDelta(tx, ty)
  end

  local ox, oy = 0, 0
  self.drawScale = 1
  self.drawScaleX = nil
  self.drawScaleY = nil
  self.drawAngle = 0
  self.drawAlpha = 1

  if style == "duck" then
    ox = lx * pulse * 5
    oy = pulse * 7
    self.drawScaleX = 1 + pulse * 0.22
    self.drawScaleY = 1 - pulse * 0.42
  elseif style == "lean" then
    ox = ax * pulse * 9 + lx * pulse * 4
    oy = ay * pulse * 4
    self.drawAngle = (tx >= 0 and 1 or -1) * pulse * 0.38
  elseif style == "hop" then
    ox = lx * pulse * 6
    oy = -pulse * 16
    local squash = (t < 0.18 or t > 0.82) and 0.18 or -0.10
    self.drawScaleX = 1 + pulse * squash
    self.drawScaleY = 1 - pulse * squash
  elseif style == "blur" then
    ox = lx * pulse * 18
    oy = ly * pulse * 18 - pulse * 3
    self.drawAlpha = 0.82
    self._walkFrame = (math.floor(self.animT * 18) % 2)
  elseif style == "lift" then
    ox = lx * pulse * 7 + math.sin(t * math.pi * 2) * 2
    oy = -pulse * 18 - math.sin(t * math.pi * 4) * 2.5
    self.drawScaleY = 1 + math.sin(t * math.pi * 4) * 0.12
    self._walkFrame = (t < 0.9) and 1 or 0
  elseif style == "phase" then
    ox = lx * pulse * 10
    oy = -pulse * 3
    self.drawAlpha = 0.18 + 0.62 * (0.5 + 0.5 * math.sin(t * math.pi * 9))
    self.drawScale = 1 + pulse * 0.06
  elseif style == "splash" then
    ox = lx * pulse * 14
    oy = ly * pulse * 10 - pulse * 3
    if not self._dodgeFxSpawned then
      spawnDodgeBits(self, 7, { 0.45, 0.78, 1.0 }, "ripple")
      spawnDodgeBits(self, 5, { 0.85, 0.95, 1.0 }, "spark")
      self._dodgeFxSpawned = true
    end
  elseif style == "burrow" then
    ox = lx * pulse * 4
    oy = pulse * 11
    self.drawScaleX = 1 + pulse * 0.28
    self.drawScaleY = 1 - pulse * 0.52
    if not self._dodgeFxSpawned then
      spawnDodgeBits(self, 6, { 0.42, 0.32, 0.16 }, "crumb")
      self._dodgeFxSpawned = true
    end
  elseif style == "static" then
    local snap = 0
    if t > 0.14 and t < 0.86 then
      snap = 1
    end
    ox = lx * snap * 16 + math.sin(self.animT * 70) * 1.8
    oy = ly * snap * 10 - snap * 2
    if t > 0.12 and t < 0.28 then
      self.drawAlpha = 0.08
    elseif t > 0.28 and t < 0.42 then
      self.drawAlpha = 0.35 + math.sin(self.animT * 90) * 0.25
    end
    if not self._dodgeFxSpawned then
      spawnDodgeBits(self, 8, { 1.0, 0.92, 0.25 }, "spark")
      self._dodgeFxSpawned = true
    end
    self._walkFrame = (math.floor(self.animT * 22) % 2)
  else
    -- sidehop: classic lateral hop.
    ox = lx * pulse * 14
    oy = ly * pulse * 14 - pulse * 4
    self._walkFrame = (t < 0.85) and 1 or 0
  end

  if style == "blur" or style == "static" or style == "phase" then
    local trail = self._dodgeTrail or {}
    if self.px and self.py then
      trail[#trail + 1] = { px = self.px, py = self.py }
      while #trail > 4 do
        table.remove(trail, 1)
      end
    end
    self._dodgeTrail = trail
  end

  tickDodgeBits(self, dt)

  if self.animT >= dur then
    self.anim = "idle"
    self.animT = 0
    clearDodgePose(self)
  end
  return ox, oy
end

local function swimPackPath(mod, game, species, shiny)
  local dex = speciesDex(game, species)
  if not dex then
    return nil
  end
  local root = wildsRoot(mod)
  if not root then
    return nil
  end
  local nnn = string.format("%03d", dex)
  local variant = shiny and "shiny" or "normal"
  local candidates = {
    root .. "/assets/generated/true_size/swimming/" .. nnn .. "-" .. variant .. ".png",
    root .. "/assets/generated/true_size/swimming/" .. nnn .. "-normal.png",
    root .. "/assets/generated/true_size/levitate/" .. nnn .. "-" .. variant .. ".png",
    root .. "/assets/generated/true_size/levitate/" .. nnn .. "-normal.png",
  }
  for i = 1, #candidates do
    local path = loadablePath(candidates[i])
    if path then
      return path
    end
  end
  return nil
end

function Sprites.resolveSheet(mod, game, species, battler, surface)
  if not species then
    return nil
  end
  surface = surface or "land"
  local explicit = "AUTO"
  if mod and mod.options and type(mod.options.get) == "function" then
    explicit = tostring(mod.options:get("field_sprites") or "AUTO"):upper()
  end
  local style = Sprites.fieldSpriteStyle(mod)
  local shiny = isShinyBattler(battler)
  local wildsStyle = (explicit == "AUTO") and nil or style

  local sheet = wildsExportSheet(mod, game, species, wildsStyle, shiny, surface)
  if sheet then
    return sheet
  end

  if surface == "water" or surface == "surfing" then
    local swimPath = swimPackPath(mod, game, species, shiny)
    if swimPath then
      return sheetFromPath(swimPath, 6, true)
    end
    -- No swim art: fall through to land sheet (mon may still stand in water).
  end

  if style == "pokemmo" or style == "pokedex" then
    local path = wildsPackPath(mod, game, species, style, shiny)
    if path then
      return sheetFromPath(path, style == "pokedex" and 1 or 6, style ~= "pokedex")
    end
  end

  local gsc = pokePcPath(mod, game, species)
  if gsc then
    return sheetFromPath(gsc, 6, true)
  end
  local wildsGsc = wildsPackPath(mod, game, species, "followers", shiny)
  if wildsGsc then
    return sheetFromPath(wildsGsc, 6, true)
  end
  if style ~= "pokemmo" then
    local hgss = wildsPackPath(mod, game, species, "pokemmo", shiny)
    if hgss then
      return sheetFromPath(hgss, 6, true)
    end
  end
  return nil
end

function Sprites.resolveFollowerPath(mod, game, species)
  local sheet = Sprites.resolveSheet(mod, game, species, nil)
  return sheet and sheet.image or nil
end

function Sprites.castMode(mod)
  return "OVERWORLD"
end

local STAND = { down = 0, up = 1, left = 2, right = 2 }
local WALK = { down = 3, up = 4, left = 5, right = 5 }

local Coords
do
  local ok, c = pcall(require, "coords")
  if ok then
    Coords = c
  end
end

local function healthRatio(battler)
  local mon = battler and battler.mon
  local maxHP = tonumber(mon and mon.stats and mon.stats.hp) or 1
  if maxHP < 1 then
    maxHP = 1
  end
  local hp = tonumber(mon and mon.hp)
  if hp == nil then
    hp = tonumber(battler and battler.shownHP) or 0
  end
  if hp < 0 then
    hp = 0
  end
  return math.max(0, math.min(1, hp / maxHP)), hp, maxHP
end

local function drawHealthBar(ent, camX, camY)
  if not (ent._battleBattler and love and love.graphics) then return end
  local g = love.graphics
  local ratio, hp = healthRatio(ent._battleBattler)
  local x = math.floor((ent.px or 0) - (camX or 0) + 8.5)
  local y = math.floor((ent.py or 0) - (camY or 0)
    - (ent._fieldBarLift or 8) + 0.5)
  local w = 18
  g.setColor(0.08, 0.07, 0.06, 1)
  g.rectangle("fill", x - w / 2, y, w, 4)
  g.setColor(0.94, 0.91, 0.77, 1)
  g.rectangle("fill", x - w / 2 + 1, y + 1, w - 2, 2)
  local fill = math.floor((w - 2) * ratio + 0.5)
  if hp and hp > 0 and fill < 1 then
    fill = 1
  end
  if fill > 0 then
    if ratio <= 0.2 then
      g.setColor(0.82, 0.16, 0.12, 1)
    elseif ratio <= 0.5 then
      g.setColor(0.92, 0.62, 0.10, 1)
    else
      g.setColor(0.20, 0.68, 0.27, 1)
    end
    g.rectangle("fill", x - w / 2 + 1, y + 1, fill, 2)
  end
  g.setColor(0.08, 0.07, 0.06, 1)
  g.polygon("fill", x - 1, y + 4, x + 1, y + 4, x, y + 6)
  g.setColor(1, 1, 1, 1)
end

local function buildEntity(side, cellX, cellY, facing, species, drawer, kind, grid)
  local padU, padV
  local basePx, basePy
  if grid and Coords then
    padU, padV = Coords.worldToPad(grid, cellX, cellY)
    basePx, basePy = Coords.padToPx(grid, padU, padV)
    cellX, cellY = Coords.padToWorld(grid, padU, padV)
  else
    basePx, basePy = cellX * 16, cellY * 16
  end
  local ent = {
    id = "ar_fbv_" .. tostring(side),
    cellX = cellX,
    cellY = cellY,
    padU = padU,
    padV = padV,
    homePadU = padU,
    homePadV = padV,
    _grid = grid,
    px = basePx,
    py = basePy,
    facing = facing or "down",
    species = species,
    _arFieldBattler = true,
    _arFieldSide = side,
    _fbv = true,
    _fbvKind = kind or "ow",
    basePx = basePx,
    basePy = basePy,
    targetPx = basePx,
    targetPy = basePy,
    homePx = basePx,
    homePy = basePy,
    homeCellX = cellX,
    homeCellY = cellY,
    trainerPx = basePx,
    trainerPy = basePy,
    bobT = (side == "enemy") and 2.1 or 0.4,
    -- Continuous sine bob (through rest pose) — keep lively while standing still.
    bobAmp = (side == "enemy") and 2.0 or 1.8,
    bobSpeed = (side == "enemy") and 4.3 or 4.0,
    swayAmp = 0,
    anim = "idle",
    animT = 0,
    passable = true,
    frozen = true,
    wanders = false,
    drawer = drawer,
    _walkFrame = 0,
    _walkT = 0,
    _idleT = (side == "enemy") and 1.3 or 0.2,
    wanderCD = (side == "enemy") and 3.2 or 2.6,
    _wanderCD = (side == "enemy") and 3.2 or 2.6,
    drawScale = 1,
  }

  function ent:pose()
    -- Dramatic Shape VoxelScene.posesOf:
    --   sprite, vx, vy, facing, phase, flip = e:pose()
    --   billboard at (vx, e.py) with lift = e.py - vy
    --   then drawEntity → sprite.def / sprite:resolveImage() / Voxel3D.draw
    -- Nil sprite, nil def, missing resolveImage, non-cardinal facing, or
    -- non-finite px/py abort Love with no error screen. Every attack/dodge
    -- just changes this pose, so crashes look move-specific.
    local sprite = self.sprite
    if not (sprite and sprite.def) then
      self._poseSafe = self._poseSafe or {
        def = {
          id = "ar_fbv_pose_" .. tostring(self.id or "mon"),
          frames = 1,
          image = "ar_fbv_missing",
        },
        draw = function() end,
        resolveImage = function() return nil end,
      }
      sprite = self._poseSafe
      if not self.sprite then
        self.sprite = sprite
      elseif not self.sprite.def then
        self.sprite.def = sprite.def
      end
    elseif type(sprite.resolveImage) ~= "function" then
      sprite.resolveImage = function()
        return sprite.image
      end
    end
    self.px = finiteCoord(self.px, finiteCoord(self.basePx, 0))
    self.py = finiteCoord(self.py, finiteCoord(self.basePy, 0))
    self.basePx = finiteCoord(self.basePx, self.px)
    self.basePy = finiteCoord(self.basePy, self.py)
    self.cellX = finiteCoord(self.cellX, math.floor(self.px / 16))
    self.cellY = finiteCoord(self.cellY, math.floor(self.py / 16))
    self.cellX = math.floor(self.cellX + 0.5)
    self.cellY = math.floor(self.cellY + 0.5)
    self.facing = voxelFacing(self.facing)
    local phase = (self._walkFrame == 1) and 1 or 0
    return sprite, self.px, self.py, self.facing, phase, false
  end

  function ent:walkPhase()
    return self._walkFrame or 0
  end

  function ent:update()
  end

  local function drawVanishTell(self, g, camX, camY)
    local bx = (self.basePx or self.px or 0) - (camX or 0)
    local by = (self.basePy or self.py or 0) - (camY or 0)
    local fly = self._vanishKind == "fly" or self.anim == "aloft"
        or self.anim == "vanish_fly" or self.anim == "emerge_fly"
    if fly then
      -- Ground shadow while the mon is up high.
      local pulse = 0.85 + 0.15 * math.sin((self.bobT or 0) * 2.4)
      g.setColor(0.05, 0.08, 0.12, 0.38 * pulse)
      g.ellipse("fill", bx, by + 3, 8 * pulse, 3.2)
      g.setColor(0.7, 0.82, 1.0, 0.2)
      g.ellipse("line", bx, by + 3, 9 * pulse, 3.6)
    else
      -- Dirt hole while burrowed.
      g.setColor(0.18, 0.1, 0.05, 0.9)
      g.ellipse("fill", bx, by + 5, 9, 4.5)
      g.setColor(0.42, 0.28, 0.14, 0.85)
      g.ellipse("fill", bx, by + 4, 7, 3.2)
      g.setColor(0.62, 0.46, 0.26, 0.55)
      g.ellipse("line", bx, by + 4, 8, 3.6)
      -- Loose crumbs.
      local t = self.bobT or 0
      for i = 1, 4 do
        local a = t * 1.7 + i * 1.6
        g.setColor(0.55, 0.38, 0.2, 0.55)
        g.circle("fill",
          bx + math.cos(a) * (5 + i % 2),
          by + 5 + math.sin(a * 1.3) * 1.5,
          1.1)
      end
    end
  end

  function ent:draw(camX, camY)
    if self._removed then
      return
    end
    if self.hidden and not self._fieldVanished then
      return
    end
    local g = love and love.graphics
    if g and (self._fieldVanished or self.anim == "vanish_dig"
        or self.anim == "vanish_fly" or self.anim == "buried"
        or self.anim == "aloft" or self.anim == "emerge_dig"
        or self.anim == "emerge_fly") then
      drawVanishTell(self, g, camX, camY)
    end
    local function drawBody()
      if self.drawer then
        self.drawer(self, camX, camY)
        return
      end
      if self.sprite and self.sprite.draw then
        self.sprite:draw(self.px, self.py, camX, camY, self.facing,
          self._walkFrame or 0, false)
      end
    end
    local function drawBodyAt(px, py, scaleX, scaleY, angle, alpha)
      local savedPx, savedPy = self.px, self.py
      self.px, self.py = px, py
      local sx = scaleX or 1
      local sy = scaleY or sx
      local ang = angle or 0
      local a = alpha or 1
      g = love and love.graphics
      local need = g and (sx ~= 1 or sy ~= 1 or ang ~= 0 or a < 0.999)
      if need then
        local cx = (px or 0) - (camX or 0) + 8
        local cy = (py or 0) - (camY or 0) + 8
        -- Uneven scale squashes from the feet (duck / burrow).
        if math.abs(sx - sy) > 0.01 then
          cy = cy + 8
        end
        g.push()
        g.translate(cx, cy)
        if ang ~= 0 then
          g.rotate(ang)
        end
        g.scale(sx, sy)
        g.translate(-cx, -cy)
        if a < 0.999 then
          g.setColor(1, 1, 1, a)
        end
        drawBody()
        if a < 0.999 then
          g.setColor(1, 1, 1, 1)
        end
        g.pop()
      else
        drawBody()
      end
      self.px, self.py = savedPx, savedPy
    end
    local scaleX = self.drawScaleX or self.drawScale or 1
    local scaleY = self.drawScaleY or self.drawScale or 1
    local trail = self._dodgeTrail
    if g and trail then
      for i = 1, #trail do
        local ghost = trail[i]
        local fade = 0.18 + 0.12 * (i / #trail)
        drawBodyAt(ghost.px, ghost.py, scaleX, scaleY, self.drawAngle or 0, fade)
      end
    end
    drawBodyAt(self.px, self.py, scaleX, scaleY, self.drawAngle or 0,
      self.drawAlpha or 1)
    if g and self._dodgeBits then
      for i = 1, #self._dodgeBits do
        local bit = self._dodgeBits[i]
        local u = 1 - bit.t / bit.life
        if u > 0 then
          local c = bit.color or { 1, 1, 1 }
          local x = bit.x - (camX or 0)
          local y = bit.y - (camY or 0)
          g.setColor(c[1], c[2], c[3], 0.8 * u)
          if bit.kind == "ripple" then
            local r = 2.5 + (1 - u) * 9
            g.setLineWidth(1)
            g.ellipse("line", x, y, r, r * 0.42)
          else
            g.circle("fill", x, y, bit.kind == "crumb" and 1.15 or 1.45)
          end
        end
      end
      g.setColor(1, 1, 1, 1)
    end
    g = love and love.graphics
    if g and type(g.transformPoint) == "function" then
      local ok, sx, sy = pcall(g.transformPoint,
        (self.px or 0) - (camX or 0) + 8,
        (self.py or 0) - (camY or 0) - (self._fieldBarLift or 8))
      if ok and type(sx) == "number" and type(sy) == "number" then
        self._fieldScreenX, self._fieldScreenY = sx, sy
      end
    end
    -- HP bars paint from UI.drawWorldHP (battle overlay) so voxel cast still
    -- shows them when entity draw() is skipped.
  end

  function ent:setPad(u, v, face, snap)
    self.padU, self.padV = u, v
    if self._grid and Coords then
      self.cellX, self.cellY = Coords.padToWorld(self._grid, u, v)
      self.targetPx, self.targetPy = Coords.padToPx(self._grid, u, v)
    end
    if snap ~= false then
      self.basePx, self.basePy = self.targetPx, self.targetPy
      self.px, self.py = self.basePx, self.basePy
    end
    if face then
      self.facing = face
    end
  end

  function ent:setCell(cx, cy, face, snap)
    self.cellX, self.cellY = cx, cy
    if self._grid and Coords then
      local u, v = Coords.worldToPad(self._grid, cx, cy)
      self:setPad(u, v, face, snap)
      return
    end
    self.targetPx, self.targetPy = cx * 16, cy * 16
    if snap ~= false then
      self.basePx, self.basePy = self.targetPx, self.targetPy
      self.px, self.py = self.basePx, self.basePy
    end
    if face then
      self.facing = face
    end
  end

  function ent:setHome(px, py)
    self.homePx, self.homePy = px, py
    -- Occupancy / home pad are not derived from pixels.
    if self.homePadU == nil and type(px) == "number" and type(py) == "number" then
      self.homeCellX = math.floor(px / 16 + 0.5)
      self.homeCellY = math.floor(py / 16 + 0.5)
    end
  end

  function ent:setTrainerSide(px, py)
    self.trainerPx, self.trainerPy = px, py
  end

  function ent:play(kind)
    -- HUD confirm arms a close-the-gap walk; do not lunge until melee reach.
    if (kind == "attack" or kind == "jump") and self._pendingCloseStrike then
      return
    end
    self.anim = kind or "idle"
    self.animT = 0
    self._recallDone = nil
    self._captureDone = nil
    if kind == "sendout" then
      self._sendoutStarted = true
      self.hidden = false
      self.drawScale = 0.15
    elseif kind == "recall" or kind == "capture" then
      self.drawScale = 1
      self.wanderTx, self.wanderTy = nil, nil
      self.returning = nil
    elseif kind == "faint" then
      self.drawScale = 1
      self._fainting = true
      self.wanderTx, self.wanderTy = nil, nil
      self.returning = nil
    elseif kind == "vanish_dig" or kind == "vanish_fly" then
      self.hidden = false
      self._fieldVanished = nil
      self._emerging = nil
      self._arFieldDetached = nil
      self.drawScale = 1
      self._vanishKind = (kind == "vanish_fly") and "fly" or "dig"
    elseif kind == "emerge_dig" or kind == "emerge_fly" then
      self.hidden = false
      self._emerging = true
      self._arFieldDetached = nil
      self.drawScale = (kind == "emerge_fly") and 0.22 or 0.18
      self._vanishKind = (kind == "emerge_fly") and "fly" or "dig"
    elseif kind == "buried" or kind == "aloft" then
      self.hidden = false
      self._fieldVanished = true
      self._emerging = nil
      self.drawScale = (kind == "aloft") and 0.26 or 0.2
      self._vanishKind = (kind == "aloft") and "fly" or "dig"
    elseif kind == "dodge" then
      self.drawScale = 1
      self._dodgeStyle = Sprites.pickDodgeStyle(self)
      self._dodgeTrail = {}
      self._dodgeBits = {}
      self._dodgeFxSpawned = nil
      self.drawAngle = 0
      self.drawAlpha = 1
      self.drawScaleX, self.drawScaleY = nil, nil
    elseif kind == "counter" then
      self.drawScale = 1
      self._dodgeTrail = {}
      self._dodgeBits = nil
      self.drawAngle = 0
      self.drawAlpha = 1
      self.drawScaleX, self.drawScaleY = nil, nil
    else
      self.drawScale = 1
      self.drawScaleX, self.drawScaleY = nil, nil
      self.drawAngle = 0
      self.drawAlpha = 1
      self._dodgeTrail = nil
      self._dodgeBits = nil
    end
  end

  --- Soft-move base position toward a world pixel target; faces travel dir.
  function ent:steerBase(tx, ty, speed, dt)
    if tx == nil or ty == nil then
      self._walkFrame = 0
      return true
    end
    local dx = tx - self.basePx
    local dy = ty - self.basePy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1.5 then
      self.basePx, self.basePy = tx, ty
      self._walkFrame = 0
      return true
    end
    local step = math.min(dist, (speed or 40) * (dt or 0.016))
    self.basePx = self.basePx + dx / dist * step
    self.basePy = self.basePy + dy / dist * step
    -- Pad occupancy is never derived from pixels.
    self.facing = faceFromDelta(dx, dy)
    self._walkT = (self._walkT or 0) + (dt or 0.016)
    self._walkFrame = (math.floor(self._walkT * 8) % 2)
    return false
  end

  function ent:tick(dt, towardX, towardY)
    if self._removed then
      return
    end
    -- Dig/Fly holds keep ticking so buried/aloft bob continues; other
    -- hidden states (recall / faint / capture) stay frozen.
    if self.hidden and not self._fieldVanished then
      return
    end
    dt = dt or (1 / 60)
    -- Lerp base toward pad pixel target (occupancy stays on padU/padV).
    local tpx = self.targetPx
    local tpy = self.targetPy
    if type(self.basePx) ~= "number" then
      self.basePx = (type(tpx) == "number" and tpx)
          or (type(self.px) == "number" and self.px)
          or 0
      self.basePy = (type(tpy) == "number" and tpy)
          or (type(self.py) == "number" and self.py)
          or 0
    end
    if tpx ~= nil and tpy ~= nil then
      local dx = tpx - self.basePx
      local dy = tpy - self.basePy
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist < 0.8 then
        self.basePx, self.basePy = tpx, tpy
        -- Leave _walkFrame alone so idle / cast can keep animating in place.
      else
        local gait = self.stepSpeed or 56
        local step = math.min(dist, gait * dt)
        self.basePx = self.basePx + dx / dist * step
        self.basePy = self.basePy + dy / dist * step
        self.facing = faceFromDelta(dx, dy)
        self._walkT = (self._walkT or 0) + dt * (gait / 56)
        self._walkFrame = (math.floor(self._walkT * 8) % 2)
      end
    end
    -- Land ↔ swim sheet when a Water-type steps onto surveyed water.
    Sprites.syncSurface(self)
    -- Always advance bob — independent of battle queue / waitFrames / UI.
    -- Major status lightly flavors the idle pose (freeze stills, para jitters).
    local battler = self._battleBattler
    local status = battler and battler.mon and battler.mon.status
    if type(status) == "string" then
      status = status:upper()
    end
    local confused = battler and tonumber(battler.confusedTurns)
    if confused and confused <= 0 then
      confused = nil
    end
    local bobAmp = self.bobAmp or 3.2
    local bobSpeed = self.bobSpeed or 5.0
    if status == "FRZ" then
      bobAmp = bobAmp * 0.12
      bobSpeed = bobSpeed * 0.25
    elseif status == "SLP" then
      bobAmp = bobAmp * 0.35
      bobSpeed = bobSpeed * 0.45
    elseif status == "PAR" then
      bobSpeed = bobSpeed * 1.35
    elseif status == "BRN" then
      bobSpeed = bobSpeed * 1.22
    elseif status == "PSN" or status == "TOX" then
      bobAmp = bobAmp * 0.85
    elseif confused then
      bobSpeed = bobSpeed * 1.15
    end
    local coverHold = self.coverBlend or 0
    if coverHold > 0.12 then
      local k = math.min(1, coverHold)
      bobAmp = bobAmp * (1 - 0.72 * k)
      bobSpeed = bobSpeed * (1 - 0.35 * k)
    end
    self.bobT = (self.bobT or 0) + dt * bobSpeed
    local bob = math.sin(self.bobT) * bobAmp
    local ox, oy = 0, bob
    if self._fainting then
      bob = bob * (1 - math.min(1, (self.animT or 0) / 0.18))
      ox, oy = 0, bob
    elseif status == "PAR" then
      local jitter = math.sin((self.bobT or 0) * 17) * 1.1
      ox = ox + jitter
    elseif status == "BRN" then
      ox = ox + math.sin((self.bobT or 0) * 13) * 0.45
      oy = oy + math.abs(math.sin((self.bobT or 0) * 11)) * 0.7
    elseif status == "FRZ" then
      oy = oy + 1
    elseif status == "SLP" then
      oy = oy + 2
    elseif confused then
      ox = ox + math.sin((self.bobT or 0) * 3.4) * 1.6
      oy = oy + math.sin((self.bobT or 0) * 5.1) * 0.8
    end

    -- Blend toward a cover prop when Reactive Defense has us hidden.
    local blend = self.coverBlend or 0
    if blend > 0 and self.coverTx and self.coverTy then
      local dx = (self.coverTx or self.basePx) - self.basePx
      local dy = (self.coverTy or self.basePy) - self.basePy
      ox = ox + dx * blend * 0.55
      oy = oy + dy * blend * 0.55 + blend * 1.5
    end

    local anim = self.anim or "idle"
    if (anim == "attack" or anim == "jump") and self._pendingCloseStrike then
      anim = "idle"
      self.anim = "idle"
      self.animT = 0
    end
    if anim == "idle" and not self._fainting then
      -- Overworld-style idle: one stable frame with a gentle vertical bob.
      -- Closing a gap keeps the walk cycle from the pad lerp above.
      self._idleT = (self._idleT or 0) + dt
      if not self._pendingCloseStrike then
        self._walkFrame = 0
      end
    end

    if anim == "sendout" then
      self.animT = (self.animT or 0) + dt
      local t = math.min(1, self.animT / 0.32)
      local overshoot = math.sin(t * math.pi) * 0.12
      self.drawScale = 0.15 + 0.85 * t + overshoot
      oy = oy - math.sin(t * math.pi) * 5
      if self.animT >= 0.32 then
        self.drawScale = 1
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "recall" then
      -- Shrink into the trainer's red recall laser.
      self.animT = (self.animT or 0) + dt
      local dur = 0.48
      local t = math.min(1, self.animT / dur)
      local flash = math.sin(t * math.pi * 6) * (1 - t) * 1.5
      self.drawScale = math.max(0.04, 1 - t * t)
      ox = ox + flash
      oy = oy - t * 12 - math.sin(t * math.pi) * 3
      if self.animT >= dur then
        self._recallDone = true
        self.hidden = true
        self.drawScale = 0.04
        -- Leave ow.entities immediately — a hidden nil-pose crashed voxel.
        self._pendingDetach = true
        -- Faint→recall path still triggers the faint despawn.
        if self._fainting then
          self._faintDone = true
        end
      end
    elseif anim == "capture" then
      self.animT = (self.animT or 0) + dt
      local t = math.min(1, self.animT / 0.42)
      self.drawScale = math.max(0.04, 1 - t)
      oy = oy - math.sin(t * math.pi) * 12
      if self.animT >= 0.42 then
        self._captureDone = true
        self.hidden = true
        self._pendingDetach = true
      end
    elseif anim == "attack" then
      self.animT = (self.animT or 0) + dt
      local t = math.min(1, self.animT / 0.34)
      local pulse = math.sin(t * math.pi)
      local tx = (towardX or self.basePx) - self.basePx
      local ty = (towardY or self.basePy) - self.basePy
      local len = math.sqrt(tx * tx + ty * ty)
      if len > 0.1 then
        tx, ty = tx / len, ty / len
        self.facing = faceFromDelta(tx, ty)
      else
        tx, ty = 0, -1
      end
      -- A physical cue already advances one pad cell. Keep the pose punchy
      -- without adding a second full-cell lunge on top of that movement.
      local lunge = self._attackStepped and 5 or 14
      ox = ox + tx * pulse * lunge
      oy = oy + ty * pulse * lunge - pulse * 7
      self.drawScale = 1 + pulse * 0.08
      self._walkFrame = (t < 0.9) and 1 or 0
      if self.animT >= 0.34 then
        self.anim = "idle"
        self.animT = 0
        self.drawScale = 1
        self._attackStepped = nil
        self._attackJump = nil
      end
    elseif anim == "jump" then
      -- Leap the fight axis when cover / a blocker sits between mons.
      self.animT = (self.animT or 0) + dt
      local dur = 0.46
      local t = math.min(1, self.animT / dur)
      local pulse = math.sin(t * math.pi)
      local tx = (towardX or self.basePx) - self.basePx
      local ty = (towardY or self.basePy) - self.basePy
      local len = math.sqrt(tx * tx + ty * ty)
      if len > 0.1 then
        tx, ty = tx / len, ty / len
        self.facing = faceFromDelta(tx, ty)
      else
        tx, ty = 0, -1
      end
      local reach = self._attackStepped and 10 or 20
      ox = ox + tx * pulse * reach
      oy = oy + ty * pulse * (reach * 0.35) - math.sin(t * math.pi) * 22
      self.drawScale = 1 + pulse * 0.08
      self._walkFrame = (t < 0.92) and 1 or 0
      if self.animT >= dur then
        self.anim = "idle"
        self.animT = 0
        self.drawScale = 1
        self._attackStepped = nil
        self._attackJump = nil
      end
    elseif anim == "cast" then
      -- Special: stay on cell, still read as an action (rise + glow pulse).
      self.animT = (self.animT or 0) + dt
      local t = math.min(1, self.animT / 0.42)
      local pulse = math.sin(t * math.pi)
      local tx = (towardX or self.basePx) - self.basePx
      local ty = (towardY or self.basePy) - self.basePy
      local len = math.sqrt(tx * tx + ty * ty)
      if len > 0.1 then
        tx, ty = tx / len, ty / len
        self.facing = faceFromDelta(tx, ty)
      else
        tx, ty = 0, -1
      end
      ox = ox + tx * pulse * 5 + math.sin(t * math.pi * 3) * 1.5
      oy = oy - pulse * 10
      self._walkFrame = (math.floor(self.animT * 10) % 2)
      if self.animT >= 0.42 then
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "counter" then
      -- Rebound into the foe: overlap, hang in the clash, then ease off.
      self.animT = (self.animT or 0) + dt
      local dur = 0.52
      local t = math.min(1, self.animT / dur)
      local tx = (towardX or self.basePx) - self.basePx
      local ty = (towardY or self.basePy) - self.basePy
      local len = math.sqrt(tx * tx + ty * ty)
      if len > 0.1 then
        tx, ty = tx / len, ty / len
        self.facing = faceFromDelta(tx, ty)
      else
        tx, ty = 0, -1
      end
      local lunge
      if t < 0.18 then
        lunge = t / 0.18
      elseif t < 0.58 then
        lunge = 1
      else
        lunge = 1 - (t - 0.58) / 0.42 * 0.38
      end
      ox = ox + tx * lunge * 22
      oy = oy + ty * lunge * 22 - math.sin(math.min(1, t / 0.36) * math.pi) * 7
      self.drawScale = 1 + lunge * 0.16
      self._walkFrame = 1
      if self.px and self.py then
        local trail = self._dodgeTrail or {}
        trail[#trail + 1] = { px = self.px, py = self.py }
        while #trail > 7 do
          table.remove(trail, 1)
        end
        self._dodgeTrail = trail
      end
      if self.animT >= dur then
        self.anim = "idle"
        self.animT = 0
        self.drawScale = 1
        self._dodgeTrail = nil
      end
    elseif anim == "dodge" then
      -- Style is picked in play("dodge"): type, speed, round body, or cycle.
      local dx, dy = tickDodge(self, dt, towardX, towardY)
      ox = ox + dx
      oy = oy + dy
    elseif anim == "brace" then
      -- Brief crouch / settle into a guard.
      self.animT = (self.animT or 0) + dt
      local t = math.min(1, self.animT / 0.40)
      local pulse = math.sin(t * math.pi)
      oy = oy + pulse * 5
      ox = ox + math.sin(t * math.pi * 2) * 1.2
      if self.animT >= 0.40 then
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "hit" then
      self.animT = (self.animT or 0) + dt
      local heavy = self._heavyHit == true
      local flash = (math.floor(self.animT * 22) % 2 == 0) and 1 or -1
      local knock = math.min(1, self.animT / (heavy and 0.22 or 0.18))
      local tx = self.basePx - (towardX or self.basePx)
      local ty = self.basePy - (towardY or self.basePy)
      local len = math.sqrt(tx * tx + ty * ty)
      if len > 0.1 then
        tx, ty = tx / len, ty / len
      else
        tx, ty = 0, 1
      end
      local knockReach = heavy and 14 or 8
      local knockLift = heavy and 7 or 5
      ox = ox + flash * (heavy and 6 or 4) + tx * knock * knockReach
      oy = oy + 2 + ty * knock * knockLift
      if self.animT >= (heavy and 0.52 or 0.42) then
        self.anim = "idle"
        self.animT = 0
        self._heavyHit = nil
      end
    elseif anim == "selfhit" then
      -- Stumble / bonk: dip and wobble in place (not knockback from the foe).
      self.animT = (self.animT or 0) + dt
      local t = math.min(1, self.animT / 0.46)
      local dip = math.sin(math.min(1, t / 0.55) * math.pi) * 5
      ox = ox + math.sin(t * math.pi * 6) * 3.4
      oy = oy + dip + 1
      if self.animT >= 0.46 then
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "cover" then
      self.animT = (self.animT or 0) + dt
      oy = oy - math.min(6, self.animT * 14)
      if self.animT >= 0.45 then
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "vanish_dig" then
      -- Dig down with a shake, then hold as a dirt-hole tell (still posed).
      self.animT = (self.animT or 0) + dt
      local dur = 0.55
      local t = math.min(1, self.animT / dur)
      oy = oy + t * t * 20
      self.drawScale = math.max(0.16, 1 - t * 0.84)
      ox = ox + math.sin(t * math.pi * 7) * (1 - t) * 3.2
      self._walkFrame = (math.floor(t * 10) % 2)
      if self.animT >= dur then
        self._fieldVanished = true
        self.hidden = false
        self.drawScale = 0.2
        self.anim = "buried"
        self.animT = 0
      end
    elseif anim == "vanish_fly" then
      -- Climb and shrink into the sky, then hold aloft (still posed).
      self.animT = (self.animT or 0) + dt
      local dur = 0.58
      local t = math.min(1, self.animT / dur)
      oy = oy - t * 32 - math.sin(t * math.pi) * 8
      ox = ox + math.sin(t * math.pi * 2) * 3 * (1 - t)
      self.drawScale = math.max(0.18, 1 - t * 0.82)
      self._walkFrame = (t < 0.85) and 1 or 0
      if self.animT >= dur then
        self._fieldVanished = true
        self.hidden = false
        self.drawScale = 0.26
        self.anim = "aloft"
        self.animT = 0
      end
    elseif anim == "buried" then
      -- Semi-invulnerable Dig hold: rumble in the hole.
      self._fieldVanished = true
      self.hidden = false
      self.drawScale = 0.18 + math.sin((self.bobT or 0) * 2.6) * 0.03
      oy = oy + 15 + math.sin((self.bobT or 0) * 3.4) * 1.4
      ox = ox + math.sin((self.bobT or 0) * 5.1) * 1.1
      self._walkFrame = 0
    elseif anim == "aloft" then
      -- Semi-invulnerable Fly hold: circle high above the pad.
      self._fieldVanished = true
      self.hidden = false
      self.drawScale = 0.24 + math.sin((self.bobT or 0) * 1.8) * 0.04
      oy = oy - 34 + math.sin((self.bobT or 0) * 2.1) * 3.5
      ox = ox + math.sin((self.bobT or 0) * 1.25) * 5
      self._walkFrame = (math.floor((self.bobT or 0) * 4) % 2)
    elseif anim == "emerge_dig" then
      -- Burst up from the hole.
      self.hidden = false
      self._emerging = true
      self.animT = (self.animT or 0) + dt
      local dur = 0.38
      local t = math.min(1, self.animT / dur)
      if t < 0.12 then
        self.drawScale = 0.16 + t * 2
        oy = oy + 12 - t * 40
        ox = ox + math.sin(t * 40) * 2
      else
        local u = (t - 0.12) / 0.88
        self.drawScale = 0.4 + 0.6 * u
        oy = oy + (1 - u) * (1 - u) * 10 - math.sin(u * math.pi) * 6
        ox = ox + math.sin(u * math.pi * 3) * (1 - u) * 2
      end
      if self.animT >= dur then
        self.drawScale = 1
        self._fieldVanished = nil
        self._emerging = nil
        self._vanishKind = nil
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "emerge_fly" then
      -- Dive back onto the field from above.
      self.hidden = false
      self._emerging = true
      self.animT = (self.animT or 0) + dt
      local dur = 0.40
      local t = math.min(1, self.animT / dur)
      self.drawScale = 0.22 + 0.78 * t
      oy = oy - (1 - t) * (1 - t) * 36 + math.sin(t * math.pi) * 2
      ox = ox + math.sin(t * math.pi * 2) * (1 - t) * 4
      self._walkFrame = (t < 0.9) and 1 or 0
      if self.animT >= dur then
        self.drawScale = 1
        self._fieldVanished = nil
        self._emerging = nil
        self._vanishKind = nil
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "faint" then
      -- Stagger, then sink and shrink into the ground (opposite of recall).
      local dur = 0.80
      self.animT = (self.animT or 0) + dt
      local t = math.min(1, self.animT / dur)
      local wobble = 0
      if t < 0.25 then
        local u = t / 0.25
        wobble = math.sin(u * math.pi * 5) * (1 - u) * 4
      end
      local fall = 0
      if t > 0.16 then
        local u = (t - 0.16) / 0.84
        fall = u * u
      end
      ox = ox + wobble
      oy = oy + fall * 20
      self.drawScale = math.max(0.06, 1 - fall)
      if self.animT >= dur then
        self._faintDone = true
        self.hidden = true
        self.drawScale = 0.05
        self._pendingDetach = true
      end
    end

    local coverTuck = self.coverBlend or 0
    if coverTuck > 0.12 and not self._fainting and not self._fieldVanished then
      local animNow = self.anim or "idle"
      if animNow ~= "recall" and animNow ~= "sendout" and animNow ~= "capture"
          and animNow ~= "vanish_dig" and animNow ~= "vanish_fly"
          and animNow ~= "buried" and animNow ~= "aloft" then
        local k = math.min(1, coverTuck)
        local surface = self._coverSurface or "open"
        if surface == "water" then
          self.drawScale = (self.drawScale or 1) * (1 - 0.46 * k)
          oy = oy + 7.5 * k
        elseif surface == "grass" then
          self.drawScale = (self.drawScale or 1) * (1 - 0.20 * k)
          oy = oy + 3.2 * k
        elseif surface == "cave" then
          self.drawScale = (self.drawScale or 1) * (1 - 0.14 * k)
          oy = oy + 1.6 * k
        else
          self.drawScale = (self.drawScale or 1) * (1 - 0.16 * k)
          oy = oy + 1.8 * k
        end
      end
    end

    self.px = finiteCoord(self.basePx + ox, finiteCoord(self.basePx, 0))
    self.py = finiteCoord(self.basePy + oy, finiteCoord(self.basePy, 0))
    self.facing = voxelFacing(self.facing)
    if self._walkFrame ~= 1 then
      self._walkFrame = 0
    end
  end

  return ent
end

local function finalizeEntity(ent, battler, barLift, mod, game, species)
  if ent then
    ent._battleBattler = battler
    ent._fieldBarLift = barLift or 8
    ent._spriteMod = mod
    ent._spriteGame = game
    ent._spriteSpecies = species
    ent._fieldSurface = "land"
    ent.canSwim = Sprites.isWaterType(battler, game, species) and true or false
  end
  return ent
end

local function sheetToVisual(sheet, side)
  if not (sheet and sheet.image) then
    return nil
  end
  local img = loadImage(sheet.image)
  if not img then
    return nil
  end
  local okSR, SpriteRenderer = pcall(require, "src.render.SpriteRenderer")
  if okSR and type(SpriteRenderer.new) == "function" then
    local def = {
      id = "ar_fbv_" .. tostring(side) .. "_" .. tostring(sheet.surface or "land"),
      image = sheet.image,
      frames = tonumber(sheet.frames) or 6,
      walker = not (sheet.walker == false),
      trueColor = not (sheet.trueColor == false),
      frameWidth = sheet.frameWidth,
      frameHeight = sheet.frameHeight,
    }
    local okSp, sprite = pcall(SpriteRenderer.new, def, def.id)
    if okSp and sprite then
      local fh = tonumber(sheet.frameHeight)
      local lift = (fh and fh >= 24 and 24)
        or ((img:getWidth() >= 32 and img:getHeight() >= 192) and 24 or 8)
      return { sprite = sprite, drawer = nil, lift = lift }
    end
  end
  local iw, ih = img:getDimensions()
  local fw, fh = 16, 16
  if tonumber(sheet.frameWidth) and tonumber(sheet.frameHeight) then
    fw, fh = tonumber(sheet.frameWidth), tonumber(sheet.frameHeight)
  elseif iw >= 32 and ih >= 192 then
    fw, fh = 32, 32
  end
  local quads = {}
  local n = math.max(1, math.floor(ih / fh))
  for f = 0, n - 1 do
    quads[f] = love.graphics.newQuad(0, f * fh, fw, fh, iw, ih)
  end
  local drawer = function(ent, camX, camY)
    if ent.hidden or ent._removed then
      return
    end
    local face = ent.facing or "down"
    local walk = (ent._walkFrame or 0) == 1
    local frame = walk and (WALK[face] or STAND[face] or 0) or (STAND[face] or 0)
    if frame >= n then
      frame = STAND[face] or 0
    end
    if frame >= n then
      frame = 0
    end
    local x = ent.px - camX - (fw - 16) / 2
    local y = ent.py - camY - 4 - (fh - 16)
    local flip = face == "right"
    love.graphics.setColor(1, 1, 1, 1)
    if flip then
      love.graphics.draw(img, quads[frame], x + fw, y, 0, -1, 1)
    else
      love.graphics.draw(img, quads[frame], x, y)
    end
  end
  -- Voxel samples sprite.def; a drawer-only visual used to return nil and
  -- abort the 3D pass (hiding the other battler) as soon as this mon spawned.
  local sprite = {
    def = {
      id = "ar_fbv_" .. tostring(side) .. "_" .. tostring(sheet.surface or "land"),
      image = sheet.image,
      frames = n,
      walker = true,
    },
    draw = function(_, px, py, camX, camY, facing, walkFrame)
      drawer({
        px = px, py = py, facing = facing, _walkFrame = walkFrame,
        hidden = false,
      }, camX, camY)
    end,
    resolveImage = function()
      return img
    end,
  }
  return { sprite = sprite, drawer = drawer, lift = (fh >= 32) and 24 or 8 }
end

function Sprites.applySurface(ent, surface)
  if not ent then
    return false
  end
  surface = surface or "land"
  if ent._fieldSurface == surface and (ent.sprite or ent.drawer) then
    return false
  end
  local cache = ent._surfaceVisuals
  if type(cache) ~= "table" then
    cache = {}
    ent._surfaceVisuals = cache
  end
  local visual = cache[surface]
  if not visual then
    local sheet = Sprites.resolveSheet(
      ent._spriteMod, ent._spriteGame, ent._spriteSpecies,
      ent._battleBattler, surface)
    visual = sheetToVisual(sheet, ent.side or "player")
    if not visual and surface ~= "land" then
      -- Keep land art if swim sheet missing.
      visual = cache.land
    end
    if visual then
      cache[surface] = visual
    end
  end
  if not visual then
    return false
  end
  ent.sprite = visual.sprite
  ent.drawer = visual.drawer
  if visual.lift then
    ent._fieldBarLift = visual.lift
  end
  ent._fieldSurface = surface
  return true
end

function Sprites.syncSurface(ent)
  if not ent or ent._removed or ent.hidden then
    return
  end
  local g = ent._grid
  local onWater = false
  if g and type(g.water) == "table" and ent.padU ~= nil and Coords then
    onWater = g.water[Coords.key(ent.padU, ent.padV)] == true
  end
  local want = (onWater and ent.canSwim) and "water" or "land"
  if want ~= ent._fieldSurface then
    Sprites.applySurface(ent, want)
  end
end

function Sprites.makeMon(mod, game, species, cellX, cellY, facing, side, battler, grid)
  local sheet = Sprites.resolveSheet(mod, game, species, battler, "land")
  local visual = sheetToVisual(sheet, side)
  if visual then
    local ent = buildEntity(side, cellX, cellY, facing, species, visual.drawer, "ow", grid)
    ent.sprite = visual.sprite
    ent._surfaceVisuals = { land = visual }
    return finalizeEntity(ent, battler, visual.lift, mod, game, species)
  end
  if sheet and sheet.image then
    print("[anime_realism] field: Assets.image failed for " .. tostring(sheet.image))
  else
    print("[anime_realism] field: no follower path for " .. tostring(species))
  end

  -- Last resort: try live party follower's sprite on the map.
  local ow = game and game.overworld
  if ow then
    local okPF, PF = pcall(require, "src.world.PikachuFollower")
    if okPF and PF and type(PF.current) == "function" then
      local npc = PF.current(ow)
      if npc and npc.sprite and npc._pokepcFollowerSpecies
          and tostring(npc._pokepcFollowerSpecies):upper() == tostring(species):upper() then
        local ent = buildEntity(side, cellX, cellY, facing, species, nil, "ow", grid)
        ent.sprite = npc.sprite
        return finalizeEntity(ent, battler, 24, mod, game, species)
      end
    end
  end

  print("[anime_realism] field: OW sprite missing for " .. tostring(species)
    .. " — enable PokePCFollowers_VoxelMerge")
  -- Tiny colored square only if every loader failed.
  local r, g, b = 0.2, 0.55, 0.9
  if side == "player" then
    r, g, b = 0.9, 0.35, 0.25
  end
  local drawer = function(ent, camX, camY)
    local x = ent.px - camX
    local y = ent.py - camY - 4
    love.graphics.setColor(r, g, b, 1)
    love.graphics.rectangle("fill", x + 1, y + 1, 14, 14)
    love.graphics.setColor(1, 1, 1, 1)
  end
  return finalizeEntity(
    buildEntity(side, cellX, cellY, facing, species, drawer, "placeholder", grid),
    battler, 8, mod, game, species)
end

return Sprites
