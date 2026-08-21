-- Field battle — OW follower sprites as battlers + motion.
--
-- Pad battlers prefer this mod's 4-column combat kits
-- (`assets/followers/follower_XXX.png`, 32px cells, no right-flip). Extra
-- rows play dodge / brace / physical / special / hit, then idle, then faint,
-- then charge / jump / counter / miss / sleep / freeze / confuse / float,
-- then tumble, then optional flap. FIELD
-- SPRITES (AUTO / GSC / HGSS / POKEDEX) only picks the Wilds / PokePC
-- fallback. Overworld followers behind the player stay on those packs.
-- Never load PMD `AnimData.xml` or `*-Anim.png` here — those strips wedge
-- the voxel pass. Dodge squash/fade (issue #66) still rides on top.

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

local function loadablePath(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if loadImage(path) then
    return path
  end
  -- Tests / resolve without Love still need a real file on disk.
  if pathExists(path) then
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

local function thisModRoot(mod)
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
  return handleRoot(findHandle(mod, "anime_realism"))
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

-- Combat kit: 4 columns × N 4-row blocks, 32px cells, 128px wide.
-- Blocks 0–7 stay put so an older 8-block sheet still maps. 8+ append.
Sprites.KIT_CELL = 32
Sprites.KIT_COLS = 4
Sprites.KIT_FACE = { down = 0, left = 1, right = 2, up = 3 }
Sprites.KIT_IDLE_BLOCK = 6
Sprites.KIT_FAINT_BLOCK = 7
Sprites.KIT_BLOCK = {
  walk = 0,
  idle = 6,
  dodge = 1, brace = 2,
  attack = 3, physical = 3,
  jump = 9, counter = 10, miss = 11,
  cast = 4, special = 4, shoot = 4,
  charge = 8,
  hit = 5, selfhit = 5,
  faint = 7,
  sleep = 12, freeze = 13, confuse = 14,
  float = 15,
  tumble = 16, tumbleback = 16,
  flap = 17,
}

-- Missing extra rows reuse an earlier combat strip instead of walk.
Sprites.KIT_FALLBACK = {
  jump = 3, counter = 3, miss = 3,
  charge = 4,
  sleep = 6, freeze = 6, confuse = 6,
  float = 1,
  tumble = 5, tumbleback = 5,
}

-- Kit faint: four collapse frames, then hold the crumpled pose.
Sprites.KIT_FAINT_PLAY = 0.60
Sprites.KIT_FAINT_HOLD = 0.28

local KIT_ANIM_DUR = {
  attack = 0.34, jump = 0.46, counter = 0.52, miss = 0.42,
  cast = 0.42, brace = 0.40, selfhit = 0.46, tumble = 0.58,
  faint = Sprites.KIT_FAINT_PLAY + Sprites.KIT_FAINT_HOLD,
}

function Sprites.kitCandidatePaths(mod, game, species)
  local root = thisModRoot(mod)
  if not root then
    return {}
  end
  local key = tostring(species or ""):upper()
  local dex = speciesDex(game, key)
  local nnn = dex and string.format("%03d", dex) or nil
  local out = {}
  local function add(path)
    out[#out + 1] = path
  end
  if nnn then
    add(root .. "/assets/followers/follower_" .. nnn .. ".png")
    add(root .. "/assets/followers/follower_" .. nnn .. "_normal.png")
  end
  if key ~= "" then
    add(root .. "/assets/followers/" .. key .. ".png")
    add(root .. "/assets/followers/" .. key .. "_normal.png")
  end
  return out
end

function Sprites.kitSheetFromPath(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return {
    image = path,
    frames = Sprites.KIT_COLS,
    walker = true,
    trueColor = true,
    frameWidth = Sprites.KIT_CELL,
    frameHeight = Sprites.KIT_CELL,
    kit = true,
  }
end

local function kitPackPath(mod, game, species)
  local candidates = Sprites.kitCandidatePaths(mod, game, species)
  for i = 1, #candidates do
    local path = loadablePath(candidates[i])
    if path then
      return path
    end
  end
  return nil
end

function Sprites.kitBlockForAnim(anim, blocks, ent)
  blocks = tonumber(blocks) or 1
  if blocks < 1 then
    blocks = 1
  end
  if anim == "dodge" and ent and ent._dodgeStyle == "lift" then
    local floatB = Sprites.KIT_BLOCK.float
    if floatB < blocks then
      return floatB
    end
  end
  local want = Sprites.KIT_BLOCK[anim or "idle"] or 0
  if want < blocks then
    return want
  end
  local fallback = Sprites.KIT_FALLBACK[anim]
  if fallback and fallback < blocks then
    return fallback
  end
  return 0
end

--- True when this battler has a kit combat strip for `anim` (not walk fallback).
function Sprites.usesKitPose(ent, anim)
  if not (ent and ent._kitSheet) then
    return false
  end
  local want = Sprites.KIT_BLOCK[anim or "idle"] or 0
  if want <= 0 then
    return false
  end
  return Sprites.kitBlockForAnim(anim, ent._kitBlocks or 1, ent) > 0
end

function Sprites.kitIdleOverride(ent, moving)
  if moving or not ent then
    return nil
  end
  local battler = ent._battleBattler
  local mon = battler and battler.mon
  local status = mon and mon.status
  if type(status) == "string" then
    status = status:upper()
  end
  if status == "SLP" then
    return "sleep"
  end
  if status == "FRZ" then
    return "freeze"
  end
  local confused = battler and tonumber(battler.confusedTurns)
  if confused and confused > 0 then
    return "confuse"
  end
  return nil
end

-- Flying types with a FlapAround/Hover row: sometimes travel on that strip
-- instead of Walk. Rolled once per movement burst.
Sprites.FLAP_CHANCE = 0.45

function Sprites.kitMoveOverride(ent, moving)
  if not (ent and moving) then
    if ent then
      ent._flapWalk = nil
    end
    return nil
  end
  local battler = ent._battleBattler
  local status = battler and battler.mon and battler.mon.status
  if type(status) == "string" and status:upper() == "SLP" then
    return nil
  end
  if not Sprites.hasType(ent, "FLYING") then
    return nil
  end
  if not Sprites.usesKitPose(ent, "flap") then
    return nil
  end
  if ent._flapWalk == nil then
    local rand = (love and love.math and love.math.random) or math.random
    ent._flapWalk = rand() < (Sprites.FLAP_CHANCE or 0.45)
  end
  if ent._flapWalk then
    return "flap"
  end
  return nil
end

function Sprites.kitColForAnim(ent, anim, moving)
  anim = anim or "idle"
  if anim == "idle" and moving then
    anim = Sprites.kitMoveOverride(ent, true) or "walk"
  end
  local blocks = (ent and (ent._kitBlocks or 1)) or 1
  local block = Sprites.kitBlockForAnim(anim, blocks, ent)
  if anim == "walk" or anim == "flap" or (anim == "idle" and block == 0) then
    if moving then
      local rate = (anim == "flap") and 10 or 8
      return math.floor((ent and ent._walkT or 0) * rate) % 4
    end
    -- Walk cols 0 and 2 are idle; cycle them so standing is not frozen.
    return (math.floor((ent and ent._idleT or 0) / 0.5) % 2) * 2
  end
  if anim == "idle" or anim == "sleep" then
    -- PMD Idle / Sleep are breathing loops, not one-shots.
    local step = (anim == "sleep") and 0.42 or 0.28
    return math.floor((ent and ent._idleT or 0) / step) % 4
  end
  if anim == "freeze" then
    return 0
  end
  if anim == "confuse" then
    return math.floor((ent and ent._idleT or 0) / 0.18) % 4
  end
  if anim == "charge" then
    return math.floor((ent and ent.animT or 0) / 0.12) % 4
  end
  if anim == "faint" then
    local play = Sprites.KIT_FAINT_PLAY
    local t = (ent and ent.animT) or 0
    if t >= play then
      return 3
    end
    return math.min(3, math.floor((t / play) * 4))
  end
  local dur = KIT_ANIM_DUR[anim]
  if anim == "dodge" then
    -- Match tickDodge clip length; style durs live later in this file.
    local style = ent and ent._dodgeStyle
    dur = (style == "blur" and 0.28)
        or (style == "static" and 0.34)
        or (style == "sidehop" and 0.38)
        or (style == "duck" and 0.40)
        or (style == "splash" and 0.40)
        or (style == "lean" and 0.42)
        or (style == "hop" and 0.42)
        or (style == "burrow" and 0.42)
        or (style == "phase" and 0.44)
        or (style == "lift" and 0.46)
        or 0.38
  elseif anim == "hit" then
    dur = (ent and ent._heavyHit) and 0.52 or 0.42
  end
  dur = dur or 0.40
  local t = (ent and ent.animT) or 0
  if dur <= 0 then
    return 0
  end
  local u = t / dur
  if u < 0 then
    u = 0
  elseif u > 0.999 then
    u = 0.999
  end
  return math.min(3, math.floor(u * 4))
end

function Sprites.kitCellOrigin(ent, facing)
  local cell = Sprites.KIT_CELL
  local face = Sprites.KIT_FACE[facing or (ent and ent.facing) or "down"] or 0
  local row = (tonumber(ent and ent._kitBlock) or 0) * 4 + face
  local col = tonumber(ent and ent._kitCol) or 0
  return col * cell, row * cell
end

--- Facing handed to Dramatic Shape. GSC sheets draw right as a flip of
--- left; kits already have a right row, so that extra mirror makes both
--- battlers look the same way.
function Sprites.billboardFacing(facing, kit)
  if facing ~= "up" and facing ~= "down" and facing ~= "left" and facing ~= "right" then
    facing = "down"
  end
  if kit and facing == "right" then
    return "left"
  end
  return facing
end

local function syncKitPose(ent, moving)
  if not ent then
    return
  end
  local anim = ent.anim or "idle"
  if (anim == "attack" or anim == "jump") and ent._pendingCloseStrike then
    anim = "idle"
  end
  if anim == "idle" and moving then
    anim = Sprites.kitMoveOverride(ent, true) or "walk"
  elseif not moving then
    ent._flapWalk = nil
  end
  if anim == "idle" then
    anim = Sprites.kitIdleOverride(ent, moving) or anim
  end
  local blocks = ent._kitBlocks or (ent.sprite and ent.sprite.kitBlocks) or 1
  -- Recall after a kit faint: keep the crumpled cell while they shrink into
  -- the laser. Do not replay Walk under the bolt.
  if anim == "recall" and ent._fainting and Sprites.usesKitPose(ent, "faint") then
    ent._kitBlock = Sprites.kitBlockForAnim("faint", blocks, ent)
    ent._kitCol = 3
    local sprite = ent.sprite
    if sprite and sprite.kit then
      sprite.kitBlock = ent._kitBlock
      sprite.kitCol = ent._kitCol
      local def = sprite.def
      if type(def) == "table" then
        local u, v = Sprites.kitCellOrigin(ent, ent.facing)
        def.kitU, def.kitV = u, v
        def.kit = true
      end
    end
    return
  end
  ent._kitBlock = Sprites.kitBlockForAnim(anim, blocks, ent)
  ent._kitCol = Sprites.kitColForAnim(ent, anim, moving)
  local sprite = ent.sprite
  if sprite and sprite.kit then
    sprite.kitBlock = ent._kitBlock
    sprite.kitCol = ent._kitCol
    local def = sprite.def
    if type(def) == "table" then
      local u, v = Sprites.kitCellOrigin(ent, ent.facing)
      def.kitU, def.kitV = u, v
      def.kit = true
    end
  end
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

-- Seismic Toss: both mons grab, shoot high, hang, then crash. Keep this
-- in lockstep with Cues.TOSS_DUR / the toss contact FX.
Sprites.TOSS_DUR = 1.08
Sprites.TOSS_PEAK = 58

local function tossHeight(t)
  if t < 0.08 then
    return 3 * (t / 0.08)
  end
  if t < 0.38 then
    local u = (t - 0.08) / 0.30
    local k = 1 - (1 - u) * (1 - u)
    return 3 + k * Sprites.TOSS_PEAK
  end
  if t < 0.52 then
    return Sprites.TOSS_PEAK + 3 + math.sin((t - 0.38) * 26) * 1.5
  end
  if t < 0.74 then
    local u = (t - 0.52) / 0.22
    return (Sprites.TOSS_PEAK + 3) * (1 - u * u)
  end
  local u = (t - 0.74) / 0.26
  return math.abs(math.sin(u * math.pi)) * 8 * (1 - u)
end

--- ox/oy for toss (attacker) / tossed (carried). Ground stay on basePx/Py.
local function tickToss(self, dt, towardX, towardY, carried)
  self.animT = (self.animT or 0) + dt
  local dur = Sprites.TOSS_DUR
  local t = math.min(1, self.animT / dur)
  local height = tossHeight(t)
  local hx = ((self.basePx + (towardX or self.basePx)) * 0.5) - self.basePx
  local hy = ((self.basePy + (towardY or self.basePy)) * 0.5) - self.basePy
  local lock
  if t < 0.08 then
    lock = t / 0.08
  elseif t < 0.78 then
    lock = 1
  else
    lock = math.max(0, 1 - (t - 0.78) / 0.22)
  end
  local ox = hx * lock
  local oy = hy * lock * 0.12 - height
  if carried then
    oy = oy + 2 * lock
  else
    oy = oy - 6 * lock
  end
  local peak = Sprites.TOSS_PEAK + 3
  local air = math.min(1, height / math.max(1, peak))
  self.drawScale = 1 - air * 0.22
  if t > 0.74 and t < 0.90 then
    local squash = 1 - (t - 0.74) / 0.16
    self.drawScale = 1.04 + squash * 0.10
  end
  if t > 0.10 and t < 0.74 then
    self._walkFrame = (math.floor(t * 14) % 2)
  else
    self._walkFrame = 0
  end
  if t > 0.52 and t < 0.76 then
    self.facing = "down"
  elseif math.abs(hx) > 0.4 or math.abs(hy) > 0.4 then
    self.facing = faceFromDelta(hx, hy)
  end
  self._tossAir = true
  self._tossHeight = height
  if self.animT >= dur then
    self.anim = "idle"
    self.animT = 0
    self.drawScale = 1
    self._tossAir = nil
    self._tossHeight = nil
    self._walkFrame = 0
  end
  return ox, oy
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

  if Sprites.usesKitPose(self, "dodge") then
    -- Sheet is PMD Hop (or Float for Flying). Style only flavors motion / FX
    -- so a hop actually hops instead of sliding the same drawing.
    ox = lx * pulse * 8
    oy = ly * pulse * 3
    if style == "phase" then
      self.drawAlpha = 0.38 + 0.40 * (0.5 + 0.5 * math.sin(t * math.pi * 7))
    elseif style == "lift" then
      oy = oy - pulse * 8
    elseif style == "hop" then
      ox = lx * pulse * 5
      oy = -pulse * 14
    elseif style == "duck" then
      oy = pulse * 6
    elseif style == "burrow" then
      oy = pulse * 6
      if not self._dodgeFxSpawned then
        spawnDodgeBits(self, 6, { 0.42, 0.32, 0.16 }, "crumb")
        self._dodgeFxSpawned = true
      end
    elseif style == "blur" then
      ox = lx * pulse * 14
      self.drawAlpha = 0.82
    elseif style == "splash" then
      ox = lx * pulse * 12
      if not self._dodgeFxSpawned then
        spawnDodgeBits(self, 7, { 0.45, 0.78, 1.0 }, "ripple")
        spawnDodgeBits(self, 5, { 0.85, 0.95, 1.0 }, "spark")
        self._dodgeFxSpawned = true
      end
    elseif style == "static" then
      ox = lx * pulse * 10 + math.sin((self.animT or 0) * 70) * 1.4
      if not self._dodgeFxSpawned then
        spawnDodgeBits(self, 8, { 1.0, 0.92, 0.25 }, "spark")
        self._dodgeFxSpawned = true
      end
    end
    tickDodgeBits(self, dt)
    if self.animT >= dur then
      self.anim = "idle"
      self.animT = 0
      clearDodgePose(self)
    end
    return ox, oy
  end

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

  if surface == "water" or surface == "surfing" then
    local swimPath = swimPackPath(mod, game, species, shiny)
    if swimPath then
      return sheetFromPath(swimPath, 6, true)
    end
    -- No swim art: fall through to land kit / Wilds sheet.
  end

  local kitPath = kitPackPath(mod, game, species)
  if kitPath then
    local kit = Sprites.kitSheetFromPath(kitPath)
    kit.surface = surface or "land"
    return kit
  end

  local sheet = wildsExportSheet(mod, game, species, wildsStyle, shiny, surface)
  if sheet then
    return sheet
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
    -- Wilds may wrap SpriteBillboards after we do; re-assert kit UVs each pose.
    pcall(Sprites.installKitBillboards, self._spriteMod)
    if sprite and sprite.kit then
      sprite.kitBlock = self._kitBlock or 0
      sprite.kitCol = self._kitCol or 0
      local def = sprite.def
      if type(def) == "table" then
        local u, v = Sprites.kitCellOrigin(self, self.facing)
        def.kitU, def.kitV = u, v
        def.kit = true
        def.frameWidth = Sprites.KIT_CELL
        def.frameHeight = Sprites.KIT_CELL
      end
    end
    local phase = (self._walkFrame == 1) and 1 or 0
    if self._kitCol then
      phase = (self._kitCol % 2 == 1) and 1 or 0
    end
    local poseFacing = Sprites.billboardFacing(self.facing, sprite and sprite.kit)
    return sprite, self.px, self.py, poseFacing, phase, false
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
    elseif g and (self.anim == "toss" or self.anim == "tossed") then
      local bx = (self.basePx or self.px or 0) - (camX or 0)
      local by = (self.basePy or self.py or 0) - (camY or 0)
      local air = math.min(1, (self._tossHeight or 0) / Sprites.TOSS_PEAK)
      local pulse = 0.55 + 0.45 * (1 - air)
      g.setColor(0.05, 0.07, 0.10, 0.42 * pulse)
      g.ellipse("fill", bx, by + 4, 9 * pulse, 3.4 * pulse)
      g.setColor(0.22, 0.16, 0.10, 0.22 * pulse)
      g.ellipse("line", bx, by + 4, 10 * pulse, 3.8 * pulse)
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
    elseif kind == "toss" or kind == "tossed" then
      self.hidden = false
      self._tossAir = true
      self._tossHeight = 0
      self.drawScale = 1
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
    local battler = self._battleBattler
    local status = battler and battler.mon and battler.mon.status
    if type(status) == "string" then
      status = status:upper()
    end
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
    local moving = false
    if tpx ~= nil and tpy ~= nil and status ~= "FRZ" then
      local dx = tpx - self.basePx
      local dy = tpy - self.basePy
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist < 0.8 then
        self.basePx, self.basePy = tpx, tpy
        -- Leave _walkFrame alone so idle / cast can keep animating in place.
      else
        local gait = self.stepSpeed or 56
        if status == "SLP" then
          gait = math.max(16, gait * 0.42)
        end
        local step = math.min(dist, gait * dt)
        self.basePx = self.basePx + dx / dist * step
        self.basePy = self.basePy + dy / dist * step
        self.facing = faceFromDelta(dx, dy)
        self._walkT = (self._walkT or 0) + dt * (gait / 56)
        self._walkFrame = (math.floor(self._walkT * 8) % 2)
        moving = true
      end
    end
    -- Land ↔ swim sheet when feet are on surveyed water (any species).
    Sprites.syncSurface(self)
    -- Always advance bob — independent of battle queue / waitFrames / UI.
    -- Major status lightly flavors the idle pose (freeze stills, para jitters).
    local confused = battler and tonumber(battler.confusedTurns)
    if confused and confused <= 0 then
      confused = nil
    end
    local bobAmp = self.bobAmp or 3.2
    local bobSpeed = self.bobSpeed or 5.0
    if Sprites.kitBlockForAnim("idle", self._kitBlocks or 1) > 0 then
      -- Dedicated Idle strip already breathes; keep a tiny lift only.
      bobAmp = bobAmp * 0.18
    end
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
      -- Sleepwalkers keep the step frames so the shuffle reads.
      self._idleT = (self._idleT or 0) + dt
      if not self._pendingCloseStrike and not (status == "SLP" and moving) then
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
      local kit = Sprites.usesKitPose(self, "attack")
      local lunge = self._attackStepped and (kit and 3 or 5) or (kit and 8 or 14)
      ox = ox + tx * pulse * lunge
      oy = oy + ty * pulse * lunge
      if not kit then
        oy = oy - pulse * 7
        self.drawScale = 1 + pulse * 0.08
        self._walkFrame = (t < 0.9) and 1 or 0
      end
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
      local kit = Sprites.usesKitPose(self, "jump")
      local reach = self._attackStepped and (kit and 8 or 10) or (kit and 16 or 20)
      local hop = kit and 12 or 22
      ox = ox + tx * pulse * reach
      oy = oy + ty * pulse * (reach * 0.35) - math.sin(t * math.pi) * hop
      if not kit then
        self.drawScale = 1 + pulse * 0.08
        self._walkFrame = (t < 0.92) and 1 or 0
      end
      if self.animT >= dur then
        self.anim = "idle"
        self.animT = 0
        self.drawScale = 1
        self._attackStepped = nil
        self._attackJump = nil
      end
    elseif anim == "toss" or anim == "tossed" then
      local dx, dy = tickToss(self, dt, towardX, towardY, anim == "tossed")
      ox = ox + dx
      oy = oy + dy
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
      local kit = Sprites.usesKitPose(self, "cast")
      if kit then
        ox = ox + tx * pulse * 2
      else
        ox = ox + tx * pulse * 5 + math.sin(t * math.pi * 3) * 1.5
        oy = oy - pulse * 10
        self._walkFrame = (math.floor(self.animT * 10) % 2)
      end
      if self.animT >= 0.42 then
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "charge" then
      -- Wind-up hold: FIRE NOW overlapping pose, or the gather before Shoot.
      -- Do not drop back to idle; Shoot (`cast`) replaces this when the shot leaves.
      self.animT = (self.animT or 0) + dt
      local tx = (towardX or self.basePx) - self.basePx
      local ty = (towardY or self.basePy) - self.basePy
      local len = math.sqrt(tx * tx + ty * ty)
      if len > 0.1 then
        self.facing = faceFromDelta(tx, ty)
      end
      local kit = Sprites.usesKitPose(self, "charge")
      local pulse = 0.5 + 0.5 * math.sin((self.animT or 0) * 6)
      if kit then
        if len > 0.1 then
          ox = ox + (tx / len) * pulse * 1.5
          oy = oy + (ty / len) * pulse * 1.5
        end
      else
        oy = oy - pulse * 5
        self._walkFrame = (math.floor(self.animT * 8) % 2)
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
      local kit = Sprites.usesKitPose(self, "counter")
      local reach = kit and 14 or 22
      ox = ox + tx * lunge * reach
      oy = oy + ty * lunge * reach
      if not kit then
        oy = oy - math.sin(math.min(1, t / 0.36) * math.pi) * 7
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
      local kit = Sprites.usesKitPose(self, "brace")
      oy = oy + pulse * (kit and 2 or 5)
      if not kit then
        ox = ox + math.sin(t * math.pi * 2) * 1.2
      end
      if self.animT >= 0.40 then
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "hit" then
      self.animT = (self.animT or 0) + dt
      local heavy = self._heavyHit == true
      local kit = Sprites.usesKitPose(self, "hit")
      local knock = math.min(1, self.animT / (heavy and 0.22 or 0.18))
      local tx = self.basePx - (towardX or self.basePx)
      local ty = self.basePy - (towardY or self.basePy)
      local len = math.sqrt(tx * tx + ty * ty)
      if len > 0.1 then
        tx, ty = tx / len, ty / len
      else
        tx, ty = 0, 1
      end
      local knockReach = heavy and (kit and 10 or 14) or (kit and 6 or 8)
      local knockLift = heavy and (kit and 4 or 7) or (kit and 3 or 5)
      ox = ox + tx * knock * knockReach
      oy = oy + ty * knock * knockLift
      if not kit then
        local flash = (math.floor(self.animT * 22) % 2 == 0) and 1 or -1
        ox = ox + flash * (heavy and 6 or 4)
        oy = oy + 2
      end
      if self.animT >= (heavy and 0.52 or 0.42) then
        self.anim = "idle"
        self.animT = 0
        self._heavyHit = nil
      end
    elseif anim == "tumble" then
      -- Heavy knock: farther slip and a longer recover than a flinch.
      self.animT = (self.animT or 0) + dt
      local dur = 0.58
      local t = math.min(1, self.animT / dur)
      local kit = Sprites.usesKitPose(self, "tumble")
      local knock = math.min(1, self.animT / 0.28)
      local tx = self.basePx - (towardX or self.basePx)
      local ty = self.basePy - (towardY or self.basePy)
      local len = math.sqrt(tx * tx + ty * ty)
      if len > 0.1 then
        tx, ty = tx / len, ty / len
      else
        tx, ty = 0, 1
      end
      local reach = kit and 16 or 20
      local lift = kit and 7 or 11
      ox = ox + tx * knock * reach
      oy = oy + ty * knock * lift - math.sin(t * math.pi) * (kit and 5 or 8)
      if not kit then
        local flash = (math.floor(self.animT * 18) % 2 == 0) and 1 or -1
        ox = ox + flash * 5
        self.drawAngle = math.sin(t * math.pi) * 0.18
      end
      if self.animT >= dur then
        self.anim = "idle"
        self.animT = 0
        self.drawAngle = 0
        self._heavyHit = nil
      end
    elseif anim == "selfhit" then
      -- Stumble / bonk: dip and wobble in place (not knockback from the foe).
      self.animT = (self.animT or 0) + dt
      local t = math.min(1, self.animT / 0.46)
      local kit = Sprites.usesKitPose(self, "selfhit")
      local dip = math.sin(math.min(1, t / 0.55) * math.pi) * (kit and 2 or 5)
      ox = ox + math.sin(t * math.pi * 6) * (kit and 1.4 or 3.4)
      oy = oy + dip + (kit and 0 or 1)
      if self.animT >= 0.46 then
        self.anim = "idle"
        self.animT = 0
      end
    elseif anim == "miss" then
      -- Lunge at the foe, slip past, recover — the attack never lands.
      self.animT = (self.animT or 0) + dt
      local dur = 0.42
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
      local nx, ny = -ty, tx
      local kit = Sprites.usesKitPose(self, "miss")
      local reach = kit and 6 or 9
      ox = ox + tx * pulse * reach + nx * math.sin(t * math.pi) * (kit and 4 or 7)
      oy = oy + ty * pulse * reach
      if not kit then
        oy = oy - pulse * 4
        self._walkFrame = (t < 0.88) and 1 or 0
      end
      if self.animT >= dur then
        self.anim = "idle"
        self.animT = 0
        self.drawScale = 1
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
      -- Stagger, then sink. Kit Faint plays the collapse and holds the last
      -- crumpled frame. Trainer-owned mons then shrink into the recall laser
      -- still on that pose. Missing block keeps the old shrink-into-ground.
      local dur = KIT_ANIM_DUR.faint
      local kit = Sprites.usesKitPose(self, "faint")
      self.animT = (self.animT or 0) + dt
      local t = math.min(1, self.animT / dur)
      if kit then
        self.drawScale = 1
      else
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
      end
      if self.animT >= dur then
        if self._recallAfterFaint then
          self._recallAfterFaint = nil
          self:play("recall")
        else
          self._faintDone = true
          self.hidden = true
          self.drawScale = 0.05
          self._pendingDetach = true
        end
      end
    end

    local coverTuck = self.coverBlend or 0
    if coverTuck > 0.12 and not self._fainting and not self._fieldVanished then
      local animNow = self.anim or "idle"
      if animNow ~= "recall" and animNow ~= "sendout" and animNow ~= "capture"
          and animNow ~= "vanish_dig" and animNow ~= "vanish_fly"
          and animNow ~= "buried" and animNow ~= "aloft"
          and animNow ~= "toss" and animNow ~= "tossed" then
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
    syncKitPose(self, moving)
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
    -- Combat mons may splash through surveyed water; the swim sheet
    -- follows their feet, not their typing.
    ent.canSwim = true
    ent._kitBlocks = ent._kitBlocks or 1
    ent._kitBlock = ent._kitBlock or 0
    ent._kitCol = ent._kitCol or 0
  end
  return ent
end

local function applyVisual(ent, visual)
  if not (ent and visual) then
    return
  end
  ent.sprite = visual.sprite
  ent.drawer = visual.drawer
  if visual.lift then
    ent._fieldBarLift = visual.lift
  end
  ent._kitBlocks = visual.kitBlocks or 1
  ent._kitSheet = visual.kit == true
  if visual.sprite and visual.sprite.kit then
    visual.sprite.kitBlock = ent._kitBlock or 0
    visual.sprite.kitCol = ent._kitCol or 0
  end
end

local function kitToVisual(sheet, img, side)
  if not (img and love and love.graphics and love.graphics.newQuad) then
    return nil
  end
  local cell = Sprites.KIT_CELL
  local iw, ih = img:getDimensions()
  if iw < cell or ih < cell then
    return nil
  end
  local rows = math.max(1, math.floor(ih / cell))
  local cols = math.max(1, math.floor(iw / cell))
  local blocks = math.max(1, math.floor(rows / 4))
  local quads = {}
  for row = 0, blocks * 4 - 1 do
    quads[row] = {}
    for col = 0, math.min(3, cols - 1) do
      quads[row][col] = love.graphics.newQuad(
        col * cell, row * cell, cell, cell, iw, ih)
    end
  end
  local def = {
    id = "ar_fbv_kit_" .. tostring(side) .. "_" .. tostring(sheet.surface or "land"),
    image = sheet.image,
    frames = blocks * 4,
    walker = true,
    trueColor = true,
    frameWidth = cell,
    frameHeight = cell,
    anchorX = cell / 2,
    anchorY = cell,
    kit = true,
    kitU = 0,
    kitV = 0,
  }
  local sprite = {
    def = def,
    kit = true,
    kitBlock = 0,
    kitCol = 0,
    kitBlocks = blocks,
    image = img,
    resolveImage = function()
      return img
    end,
  }

  local function cellAt(facing, block, col)
    block = math.max(0, math.min(blocks - 1, tonumber(block) or 0))
    col = math.max(0, math.min(3, tonumber(col) or 0))
    local face = Sprites.KIT_FACE[facing or "down"] or 0
    local row = block * 4 + face
    return row, col, quads[row] and quads[row][col]
  end

  function sprite:getPoseGeometry(facing, walkPhase)
    local col = self.kitCol
    if col == nil then
      col = (walkPhase == 1) and 1 or 0
    end
    local row, c, quad = cellAt(facing, self.kitBlock or 0, col)
    return {
      frame = row * 4 + c,
      x = c * cell,
      y = row * cell,
      width = cell,
      height = cell,
      anchorX = cell / 2,
      anchorY = cell,
      quad = quad,
      facing = facing,
      walkPhase = walkPhase,
      mirror = false,
    }
  end

  function sprite:getFrameGeometry(frame)
    frame = math.floor(tonumber(frame) or 0)
    local row = math.floor(frame / 4)
    local col = frame % 4
    local quad = quads[row] and quads[row][col]
    return {
      frame = frame,
      x = col * cell,
      y = row * cell,
      width = cell,
      height = cell,
      anchorX = cell / 2,
      anchorY = cell,
      quad = quad,
    }
  end

  function sprite:draw(px, py, camX, camY, facing, walkPhase)
    local geo = self:getPoseGeometry(facing, walkPhase)
    if not geo.quad then
      return
    end
    -- Same world anchor as SpriteRenderer (8, 12) so 32px feet sit on the tile.
    local x = math.floor((px or 0) - (camX or 0)) + 8 - geo.anchorX
    local y = math.floor((py or 0) - (camY or 0)) + 12 - geo.anchorY
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, geo.quad, x, y)
  end

  local drawer = function(ent, camX, camY)
    if ent.hidden or ent._removed then
      return
    end
    sprite.kitBlock = ent._kitBlock or 0
    sprite.kitCol = ent._kitCol or 0
    sprite:draw(ent.px, ent.py, camX, camY, ent.facing, ent._walkFrame or 0)
  end
  return {
    sprite = sprite,
    drawer = drawer,
    lift = 24,
    kit = true,
    kitBlocks = blocks,
  }
end

local function isKitSheet(sheet, img)
  if sheet and sheet.kit then
    return true
  end
  if not (img and img.getDimensions) then
    return false
  end
  local iw, ih = img:getDimensions()
  return iw == 128 and ih >= 128 and (ih % 128) == 0
end

local function sheetToVisual(sheet, side)
  if not (sheet and sheet.image) then
    return nil
  end
  local img = loadImage(sheet.image)
  if not img then
    return nil
  end
  if isKitSheet(sheet, img) then
    local kit = kitToVisual(sheet, img, side)
    if kit then
      return kit
    end
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
  applyVisual(ent, visual)
  ent._fieldSurface = surface
  return true
end

--- True when this entity's occupancy or live feet sit on surveyed water.
function Sprites.feetOnWater(ent)
  if not ent then
    return false
  end
  local g = ent._grid
  if not (g and type(g.water) == "table" and Coords) then
    return false
  end
  local function wet(u, v)
    return u ~= nil and v ~= nil and g.water[Coords.key(u, v)] == true
  end
  if wet(ent.padU, ent.padV) then
    return true
  end
  local px = ent.basePx or ent.px
  local py = ent.basePy or ent.py
  if type(px) == "number" and type(py) == "number" then
    local cell = Coords.CELL or 16
    local wx = math.floor(px / cell)
    local wy = math.floor(py / cell)
    local u, v = Coords.worldToPad(g, wx, wy)
    if wet(u, v) then
      return true
    end
  end
  return false
end

function Sprites.syncSurface(ent)
  if not ent or ent._removed or ent.hidden then
    return
  end
  local want = Sprites.feetOnWater(ent) and "water" or "land"
  if want ~= ent._fieldSurface then
    Sprites.applySurface(ent, want)
  end
end

local KIT_VOXEL_IDS = { "DRAMATIC_SHAPE", "DRAMALESS_SHAPE", "potato_voxel" }

local function kitBillboardMesh(def, Voxel3D, cache)
  local img = def.kitImage
  if not (img and img.getDimensions) then
    img = loadImage(def.image)
  end
  if not img then
    return nil
  end
  local iw, ih = img:getDimensions()
  local cell = Sprites.KIT_CELL
  local x = tonumber(def.kitU) or 0
  local y = tonumber(def.kitV) or 0
  if x + cell > iw or y + cell > ih then
    return nil
  end
  local key = table.concat({ tostring(def.image), x, y }, "#")
  if cache[key] then
    return cache[key]
  end
  local u0 = (x + 0.02) / iw
  local u1 = (x + cell - 0.02) / iw
  local v0 = (y + 0.05) / ih
  local v1 = (y + cell - 0.05) / ih
  local ax = cell / 2
  local ay = cell
  local x0 = 8 - ax
  local x1 = x0 + cell
  local y0 = ay - cell
  local y1 = ay
  local verts = {
    { x0, y0, 0, u0, v1, 1 }, { x1, y0, 0, u1, v1, 1 },
    { x1, y1, 0, u1, v0, 1 }, { x0, y1, 0, u0, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  local mesh = Voxel3D.newMesh(verts, indices)
  if mesh then
    cache[key] = mesh
  end
  return mesh
end

local function wrapKitBillboards(SB, Voxel3D)
  if not (type(SB) == "table" and type(SB.mesh) == "function"
      and Voxel3D and type(Voxel3D.newMesh) == "function"
      and type(Voxel3D.pushQuad) == "function") then
    return false
  end
  -- Wilds wraps mesh() for 32px cards as a 1-column strip. Stay outermost
  -- so kitU/kitV actually reach the sampler; re-wrap if someone stole us.
  if SB.mesh == SB._arKitWrapper then
    return true
  end
  local orig = SB.mesh
  local origShadow = SB.shadowQuad
  local cache = {}
  local function wrapper(def, frame)
    if type(def) == "table" and def.kit then
      local mesh = kitBillboardMesh(def, Voxel3D, cache)
      if mesh then
        return mesh
      end
    end
    return orig(def, frame)
  end
  SB.mesh = wrapper
  SB._arKitWrapper = wrapper
  SB._arKitMesh = true
  if origShadow == orig or origShadow == nil then
    SB.shadowQuad = wrapper
  elseif type(origShadow) == "function" then
    SB.shadowQuad = function(def, frame)
      if type(def) == "table" and def.kit then
        local mesh = kitBillboardMesh(def, Voxel3D, cache)
        if mesh then
          return mesh
        end
      end
      return origShadow(def, frame)
    end
  end
  return true
end

--- Voxel billboards slice a 1-column GSC strip. Wrap mesh() so kit defs
--- sample the live 32px cell (kitU/kitV) on the 4×24 sheet.
function Sprites.installKitBillboards(mod)
  local wrapped = false
  for i = 1, #KIT_VOXEL_IDS do
    local handle = findHandle(mod, KIT_VOXEL_IDS[i])
    local lib = handle and handle.exports and handle.exports.lib
    if lib and type(lib.require) == "function" then
      local okSB, SB = pcall(lib.require, "SpriteBillboards")
      local okV3, Voxel3D = pcall(lib.require, "Voxel3D")
      if okSB and okV3 and wrapKitBillboards(SB, Voxel3D) then
        wrapped = true
      end
    end
  end
  Sprites._kitBillboards = wrapped or Sprites._kitBillboards
  return wrapped
end

function Sprites.makeMon(mod, game, species, cellX, cellY, facing, side, battler, grid)
  pcall(Sprites.installKitBillboards, mod)
  local sheet = Sprites.resolveSheet(mod, game, species, battler, "land")
  local visual = sheetToVisual(sheet, side)
  if visual then
    local ent = buildEntity(side, cellX, cellY, facing, species, visual.drawer, "ow", grid)
    applyVisual(ent, visual)
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
