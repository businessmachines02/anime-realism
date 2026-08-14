-- Field battle — OW follower sprites as battlers + motion.
--
-- Sprite set is user-pickable (FIELD SPRITES): AUTO matches Wilds of Kanto
-- if that mod is loaded, else GSC follower sheets. GSC / HGSS / POKEDEX
-- pull from PokePCFollowers, FOLLOWERS_EX, or Wilds packs. FIELD always
-- uses animated 2D overworld art — never voxel mon meshes.

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
    local f = io.open(path, "rb")
    if f and love.filesystem and love.filesystem.newFileData then
      local bytes = f:read("*a")
      f:close()
      if type(bytes) == "string" and #bytes > 0 then
        local okFd, fd = pcall(love.filesystem.newFileData, bytes, "fbv.png")
        if okFd and fd then
          local okImg, img = pcall(love.graphics.newImage, fd)
          if okImg and img then
            return img
          end
        end
      end
    elseif f then
      f:close()
    end
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

local function fileExists(path)
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

local function appSupport(rel)
  local home = os.getenv and os.getenv("HOME")
  if type(home) ~= "string" or home == "" then
    return nil
  end
  return home .. "/Library/Application Support/pokemon-love2d/mods/" .. rel
end

local function sheetFromPath(path, frames, walker)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if fileExists(path) then
    return { image = path, frames = frames or 6, walker = walker ~= false, trueColor = true }
  end
  -- Assets.image can still resolve some pack-relative paths.
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
      local path = root .. "/assets/sprites/follower_"
        .. string.format("%03d", dex) .. ".png"
      if fileExists(path) then
        return path
      end
    end
  end
  local dex = speciesDex(game, key)
  if dex then
    local path = appSupport("PokePCFollowers_VoxelMerge/assets/sprites/follower_"
      .. string.format("%03d", dex) .. ".png")
    if path and fileExists(path) then
      return path
    end
  end
  return nil
end

local function wildsRoot(mod)
  local handle = findHandle(mod, "overworld_wild_spawns")
  local root = handleRoot(handle)
  if root then
    return root
  end
  local path = appSupport("overworld_wild_spawns")
  if path and fileExists(path .. "/manifest.json") then
    return path
  end
  return nil
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
    if fileExists(candidates[i]) then
      return candidates[i]
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

function Sprites.isWaterType(battler, game, species)
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
  for i = 1, #(types or {}) do
    if tostring(types[i] or ""):upper() == "WATER" then
      return true
    end
  end
  return false
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
    if fileExists(candidates[i]) then
      return candidates[i]
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

local function faceFromDelta(dx, dy)
  if math.abs(dx or 0) >= math.abs(dy or 0) then
    return (dx or 0) >= 0 and "right" or "left"
  end
  return (dy or 0) >= 0 and "down" or "up"
end

local Coords
do
  local ok, c = pcall(require, "coords")
  if ok then
    Coords = c
  end
end

local function healthRatio(battler)
  local mon = battler and battler.mon
  local maxHP = mon and mon.stats and tonumber(mon.stats.hp) or 1
  local hp = tonumber(battler and battler.shownHP) or tonumber(mon and mon.hp) or 0
  return math.max(0, math.min(1, hp / math.max(1, maxHP)))
end

local function drawHealthBar(ent, camX, camY)
  if not (ent._battleBattler and love and love.graphics) then return end
  local g = love.graphics
  local ratio = healthRatio(ent._battleBattler)
  local x = math.floor((ent.px or 0) - (camX or 0) + 8.5)
  local y = math.floor((ent.py or 0) - (camY or 0)
    - (ent._fieldBarLift or 8) + 0.5)
  local w = 18
  g.setColor(0.08, 0.07, 0.06, 1)
  g.rectangle("fill", x - w / 2, y, w, 4)
  g.setColor(0.94, 0.91, 0.77, 1)
  g.rectangle("fill", x - w / 2 + 1, y + 1, w - 2, 2)
  local fill = math.floor((w - 2) * ratio + 0.5)
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
    return self.sprite, self.px, self.py, self.facing, self._walkFrame or 0, false
  end

  function ent:walkPhase()
    return self._walkFrame or 0
  end

  function ent:update()
  end

  function ent:draw(camX, camY)
    if self.hidden or self._removed then
      return
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
    local scale = self.drawScale or 1
    if scale ~= 1 and love and love.graphics then
      local g = love.graphics
      local cx = (self.px or 0) - (camX or 0) + 8
      local cy = (self.py or 0) - (camY or 0) + 8
      g.push()
      g.translate(cx, cy)
      g.scale(scale, scale)
      g.translate(-cx, -cy)
      drawBody()
      g.pop()
    else
      drawBody()
    end
    local g = love and love.graphics
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
      self.drawScale = 1
    elseif kind == "emerge_dig" or kind == "emerge_fly" then
      self.hidden = false
      self._emerging = true
      self.drawScale = 0.15
    else
      self.drawScale = 1
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
    if self.hidden or self._removed then
      return
    end
    dt = dt or (1 / 60)
    -- Lerp base toward pad pixel target (occupancy stays on padU/padV).
    local tpx = self.targetPx
    local tpy = self.targetPy
    if tpx ~= nil and tpy ~= nil then
      local dx = tpx - self.basePx
      local dy = tpy - self.basePy
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist < 0.8 then
        self.basePx, self.basePy = tpx, tpy
        -- Leave _walkFrame alone so idle / cast can keep animating in place.
      else
        local step = math.min(dist, (self.stepSpeed or 56) * dt)
        self.basePx = self.basePx + dx / dist * step
        self.basePy = self.basePy + dy / dist * step
        self.facing = faceFromDelta(dx, dy)
        self._walkT = (self._walkT or 0) + dt
        self._walkFrame = (math.floor(self._walkT * 8) % 2)
      end
    end
    -- Land ↔ swim sheet when a Water-type steps onto surveyed water.
    Sprites.syncSurface(self)
    -- Always advance bob — independent of battle queue / waitFrames / UI.
    -- Major status lightly flavors the idle pose (freeze stills, para jitters).
    local battler = self._battleBattler
    local status = battler and battler.mon and battler.mon.status
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
    elseif status == "PSN" or status == "TOX" then
      bobAmp = bobAmp * 0.85
    elseif confused then
      bobSpeed = bobSpeed * 1.15
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
      ox = ox + dx * blend
      oy = oy + dy * blend - blend * 2
    end

    local anim = self.anim or "idle"
    if anim == "idle" and not self._fainting then
      -- Overworld-style idle: one stable frame with a gentle vertical bob.
      self._idleT = (self._idleT or 0) + dt
      self._walkFrame = 0
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
      self._walkFrame = (t < 0.9) and 1 or 0
      if self.animT >= 0.34 then
        self.anim = "idle"
        self.animT = 0
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
    elseif anim == "dodge" then
      -- Lateral sidestep away from the foe (not a full cover tuck).
      self.animT = (self.animT or 0) + dt
      local t = math.min(1, self.animT / 0.38)
      local pulse = math.sin(t * math.pi)
      local tx = self.basePx - (towardX or self.basePx)
      local ty = self.basePy - (towardY or self.basePy)
      local len = math.sqrt(tx * tx + ty * ty)
      local px, py = -ty, tx
      if len > 0.1 then
        px, py = -ty / len, tx / len
        self.facing = faceFromDelta(tx, ty)
      else
        px, py = 1, 0
      end
      ox = ox + px * pulse * 14
      oy = oy + py * pulse * 14 - pulse * 4
      self._walkFrame = (t < 0.85) and 1 or 0
      if self.animT >= 0.38 then
        self.anim = "idle"
        self.animT = 0
      end
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
      local flash = (math.floor(self.animT * 22) % 2 == 0) and 1 or -1
      local knock = math.min(1, self.animT / 0.18)
      local tx = self.basePx - (towardX or self.basePx)
      local ty = self.basePy - (towardY or self.basePy)
      local len = math.sqrt(tx * tx + ty * ty)
      if len > 0.1 then
        tx, ty = tx / len, ty / len
      else
        tx, ty = 0, 1
      end
      ox = ox + flash * 4 + tx * knock * 8
      oy = oy + 2 + ty * knock * 5
      if self.animT >= 0.42 then
        self.anim = "idle"
        self.animT = 0
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
      -- Sink into the ground; dust handled by Projectiles.vanish.
      self.animT = (self.animT or 0) + dt
      local dur = 0.42
      local t = math.min(1, self.animT / dur)
      oy = oy + t * t * 18
      self.drawScale = math.max(0.08, 1 - t * 0.92)
      ox = ox + math.sin(t * math.pi * 5) * (1 - t) * 2
      if self.animT >= dur then
        self._fieldVanished = true
        self.hidden = true
        self.drawScale = 0.08
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "vanish_fly" then
      -- Soar up and shrink out of sight.
      self.animT = (self.animT or 0) + dt
      local dur = 0.44
      local t = math.min(1, self.animT / dur)
      oy = oy - t * 28 - math.sin(t * math.pi) * 6
      self.drawScale = math.max(0.06, 1 - t * 0.95)
      if self.animT >= dur then
        self._fieldVanished = true
        self.hidden = true
        self.drawScale = 0.06
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "emerge_dig" then
      -- Pop up from underground.
      self.hidden = false
      self._emerging = true
      self.animT = (self.animT or 0) + dt
      local dur = 0.30
      local t = math.min(1, self.animT / dur)
      if t < 0.05 then
        self.drawScale = 0.12
        oy = oy + 10
      else
        local u = (t - 0.05) / 0.95
        self.drawScale = 0.12 + 0.88 * u
        oy = oy + (1 - u) * (1 - u) * 12 - math.sin(u * math.pi) * 4
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
      -- Drop back onto the field from above.
      self.hidden = false
      self._emerging = true
      self.animT = (self.animT or 0) + dt
      local dur = 0.32
      local t = math.min(1, self.animT / dur)
      self.drawScale = 0.2 + 0.8 * t
      oy = oy - (1 - t) * (1 - t) * 26
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
      end
    end

    self.px = self.basePx + ox
    self.py = self.basePy + oy
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
  return { sprite = nil, drawer = drawer, lift = (fh >= 32) and 24 or 8 }
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

local function picDrawer(img, scale)
  scale = scale or 1
  local angles = {
    down = 0,
    right = -math.pi / 2,
    left = math.pi / 2,
    up = math.pi,
  }
  return function(ent, camX, camY)
    if not img or ent.hidden or ent._removed then
      return
    end
    local iw, ih = img:getDimensions()
    local w, h = iw * scale, ih * scale
    local x = ent.px - camX + 8
    local y = ent.py - camY + 8
    local ang = angles[ent.facing or "down"] or 0
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, ang, scale, scale, iw / 2, ih / 2)
  end
end

function Sprites.makeMon(mod, game, species, cellX, cellY, facing, side, battler, grid)
  local mode = Sprites.castMode(mod)

  if mode == "STADIUM" then
    local img = battler and battler.sprite or nil
    if type(img) == "userdata" or type(img) == "table" then
      local iw = (img.getWidth and img:getWidth()) or 56
      local scale = (iw > 40) and 0.55 or 1
      return finalizeEntity(buildEntity(side, cellX, cellY, facing, species,
        picDrawer(img, scale), "stadium", grid), battler, 12, mod, game, species)
    end
  end

  local sheet = Sprites.resolveSheet(mod, game, species, battler, "land")
  local visual = sheetToVisual(sheet, side)
  if visual then
    local ent = buildEntity(side, cellX, cellY, facing, species, visual.drawer, "ow", grid)
    ent.sprite = visual.sprite
    ent._surfaceVisuals = { land = visual }
    return finalizeEntity(ent, battler, visual.lift, mod, game, species)
  end
  if sheet and sheet.image then
    print("[anime_realism] field_battle: Assets.image failed for " .. tostring(sheet.image))
  else
    print("[anime_realism] field_battle: no follower path for " .. tostring(species))
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

  print("[anime_realism] field_battle: OW sprite missing for " .. tostring(species)
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
