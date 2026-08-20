-- Field battle — world-space projectiles for hybrid flat/voxel maps.
--
-- Simulated in world pixels; painted on the battle UI overlay with
-- world→UI mapping (same as HP bars) so FX survive 3D/world overrides.
-- Kept off ow.entities: Dramatic Shape's voxel pass wedges on nil sprites.
--
-- Movepool: named Gen1 moves + type defaults pick style / glitz. Persistent
-- PAR / FRZ / PSN / BRN / SLP / confusion auras are drawn around live field
-- sprites each frame. Cover plants the mon behind a real pad prop (or a
-- crouch shade if none is nearby) — never a looping crate glued to the sprite.
-- Fire specials paint teardrop flame tongues (not red blobs); Ember picks a
-- flight pattern each cast. Rock Throw lobs tumbling shards. Gust is a
-- traveling wind projectile even though Gen1 Flying is physical.

local Coords = require("coords")

local Projectiles = {}

local Catalog = require("fx_catalog")
local TYPE_COLORS = Catalog.TYPE_COLORS
local MOVE_FX = Catalog.MOVE_FX
local TYPE_STYLE = Catalog.TYPE_STYLE
local TYPE_CONTACT = Catalog.TYPE_CONTACT


local COVER_FLAVORS = {
  rock = { color = { 0.52, 0.45, 0.36 }, lite = { 0.72, 0.64, 0.52 } },
  grass = { color = { 0.28, 0.58, 0.20 }, lite = { 0.48, 0.78, 0.28 } },
  tree = { color = { 0.22, 0.50, 0.18 }, lite = { 0.34, 0.68, 0.28 } },
  water = { color = { 0.26, 0.54, 0.78 }, lite = { 0.72, 0.88, 1.00 } },
  crate = { color = { 0.62, 0.44, 0.22 }, lite = { 0.86, 0.70, 0.42 } },
  grave = { color = { 0.38, 0.36, 0.32 }, lite = { 0.58, 0.56, 0.50 } },
}

local COVER_PROP_RANGE2 = 48 * 48

local function flavorFromPropKind(kind, scene)
  kind = tostring(kind or ""):upper()
  if kind == "CRATE" then
    return "crate"
  end
  if kind == "TREE" then
    return "tree"
  end
  if kind == "POND" or kind == "WATER" then
    return "water"
  end
  if kind == "ROCK" then
    if scene == "grave" then
      return "grave"
    end
    return "rock"
  end
  return nil
end

local function propPixel(prop)
  if not prop then
    return nil, nil
  end
  local px = prop.px
  local py = prop.py
  if px == nil then
    px = ((prop.cellX or prop.cx or prop.wx or 0) * 16)
  end
  if py == nil then
    py = ((prop.cellY or prop.cy or prop.wy or 0) * 16)
  end
  return px, py
end

--- Nearest session cover / pad prop within a couple of tiles, or nil.
function Projectiles.nearestCoverProp(session, ent)
  if not (session and ent) then
    return nil
  end
  local ex = ent.px or ent.basePx
  local ey = ent.py or ent.basePy
  if ex == nil and session.grid and ent.padU ~= nil and type(Coords.padToPx) == "function" then
    ex, ey = Coords.padToPx(session.grid, ent.padU, ent.padV)
  end
  if ex == nil then
    return nil
  end
  local best, bestD = nil, COVER_PROP_RANGE2 + 1
  local function consider(prop)
    if not prop or prop.hidden then
      return
    end
    local px, py = propPixel(prop)
    if px == nil then
      return
    end
    local dx, dy = px - ex, py - ey
    local d = dx * dx + dy * dy
    if d < bestD then
      bestD, best = d, prop
    end
  end
  if type(session.covers) == "table" then
    for i = 1, #session.covers do
      consider(session.covers[i])
    end
  end
  if not best and session.grid and type(session.grid.props) == "table" then
    for i = 1, #session.grid.props do
      consider(session.grid.props[i])
    end
  end
  if bestD > COVER_PROP_RANGE2 then
    return nil
  end
  return best
end

--- Nearby prop kind wins; then tile (water / grass); else the fight kit.
function Projectiles.coverFlavor(session, ent, battle)
  battle = battle or (session and session._battle)
  local scene = tostring(session and session.coverScene or "")
  local prop = Projectiles.nearestCoverProp(session, ent)
  if prop then
    local fromProp = flavorFromPropKind(prop.kind, scene)
    if fromProp then
      return fromProp
    end
  end
  local grid = session and session.grid
  local u, v = ent and ent.padU, ent and ent.padV
  if grid and u ~= nil and v ~= nil then
    local water = grid.water
    if type(water) == "table" and water[Coords.key(u, v)] then
      return "water"
    end
  end
  local wx, wy = ent and ent.cellX, ent and ent.cellY
  if wx == nil and grid and u ~= nil and type(Coords.padToWorld) == "function" then
    wx, wy = Coords.padToWorld(grid, u, v)
  end
  local map = battle and battle.game and battle.game.overworld and battle.game.overworld.map
  if map and wx ~= nil then
    if type(map.isWaterCell) == "function" then
      local ok, wet = pcall(map.isWaterCell, map, wx, wy)
      if ok and wet then
        return "water"
      end
    end
    if type(map.isGrassCell) == "function" then
      local ok, grassy = pcall(map.isGrassCell, map, wx, wy)
      if ok and grassy then
        return "grass"
      end
    end
  end
  local kind = tostring(session and session.coverKind or ""):upper()
  if kind == "TREE" then
    return "tree"
  end
  if kind == "CRATE" then
    return "crate"
  end
  if kind == "ROCK" then
    if scene == "grave" then
      return "grave"
    end
    if scene == "water" then
      return "water"
    end
    return "rock"
  end
  if scene == "forest" then
    return "tree"
  end
  if scene == "route" then
    return "grass"
  end
  if scene == "water" then
    return "water"
  end
  if scene == "cave" or scene == "mountain" then
    return "rock"
  end
  if scene == "gym" or scene == "indoor" or scene == "city" then
    return "crate"
  end
  if scene == "grave" then
    return "grave"
  end
  return "rock"
end

--- Tile underfoot for the crouch tell (independent of overlay props).
function Projectiles.coverSurface(session, ent, battle)
  battle = battle or (session and session._battle)
  local grid = session and session.grid
  local u, v = ent and ent.padU, ent and ent.padV
  if grid and u ~= nil and v ~= nil then
    local water = grid.water
    if type(water) == "table" and water[Coords.key(u, v)] then
      return "water"
    end
  end
  local wx, wy = ent and ent.cellX, ent and ent.cellY
  if wx == nil and grid and u ~= nil and type(Coords.padToWorld) == "function" then
    wx, wy = Coords.padToWorld(grid, u, v)
  end
  local map = battle and battle.game and battle.game.overworld and battle.game.overworld.map
  if map and wx ~= nil then
    if type(map.isWaterCell) == "function" then
      local ok, wet = pcall(map.isWaterCell, map, wx, wy)
      if ok and wet then
        return "water"
      end
    end
    if type(map.isGrassCell) == "function" then
      local ok, grassy = pcall(map.isGrassCell, map, wx, wy)
      if ok and grassy then
        return "grass"
      end
    end
  end
  local scene = tostring(session and session.coverScene or "")
  if scene == "cave" or scene == "mountain" then
    return "cave"
  end
  local GridMod = session and session._deps and session._deps.Grid
  local hug = nil
  if GridMod and type(GridMod.wallHug) == "function" then
    hug = GridMod.wallHug(grid, ent)
  end
  if hug then
    local indoor = scene == "gym" or scene == "indoor" or scene == "city"
    local solid = hug.kind == "wall" or hug.kind == "prop"
    local hits = hug.hits
    if type(hits) == "table" then
      for i = 1, #hits do
        local k = hits[i].kind
        if k == "wall" or k == "prop" then
          solid = true
        end
      end
    end
    if indoor or solid then
      return "wall"
    end
  end
  return "open"
end

local function mapIdOf(battle)
  if battle and type(battle.currentMapId) == "function" then
    local ok, id = pcall(battle.currentMapId, battle)
    if ok then
      return tostring(id or "")
    end
  end
  return ""
end

local function mapTilesetOf(battle)
  local raw = mapIdOf(battle)
  if raw == "" then
    return ""
  end
  local maps = battle and battle.game and battle.game.data and battle.game.data.maps
  local def = maps and (maps[raw] or maps[raw:upper()])
  return tostring((type(def) == "table" and def.tileset) or ""):upper()
end

local function probeMapFlag(map, name, wx, wy)
  if not (map and wx ~= nil and type(map[name]) == "function") then
    return false
  end
  local ok, flag = pcall(map[name], map, wx, wy)
  return ok and flag == true
end

--- Debris flavor for a hit on this sprite (tile underfoot, then the fight kit).
function Projectiles.hitGround(session, ent, battle)
  battle = battle or (session and session._battle)
  local surface = Projectiles.coverSurface(session, ent, battle)
  if surface == "water" then
    return "water"
  end
  if surface == "grass" then
    return "grass"
  end
  local wx, wy = ent and ent.cellX, ent and ent.cellY
  local grid = session and session.grid
  if wx == nil and grid and ent and ent.padU ~= nil and type(Coords.padToWorld) == "function" then
    wx, wy = Coords.padToWorld(grid, ent.padU, ent.padV)
  end
  local map = battle and battle.game and battle.game.overworld and battle.game.overworld.map
  if probeMapFlag(map, "isIceCell", wx, wy) or probeMapFlag(map, "isSnowCell", wx, wy) then
    return "snow"
  end
  local mapId = mapIdOf(battle):upper()
  local tileset = mapTilesetOf(battle)
  if tileset:find("ICE", 1, true) or mapId:find("ICE", 1, true)
      or mapId:find("SEAFOAM", 1, true) then
    return "snow"
  end
  if surface == "cave" then
    return "cave"
  end
  local scene = tostring(session and session.coverScene or "")
  if scene == "water" then
    return "sand"
  end
  if scene == "gym" or scene == "indoor" or scene == "city" then
    return "spark"
  end
  if scene == "mountain" then
    return "cave"
  end
  return "dust"
end

local function battlerCoverHeld(session, battle, battler, isPlayer)
  if battler and (battler.cover == true or battler._arFieldCover == true) then
    return true
  end
  local RD = session and (session.ReactiveDefense or (battle and battle._arReactiveDefense))
  if RD and type(RD.sideState) == "function" then
    local ok, side = pcall(RD.sideState, battle, isPlayer == true)
    if ok and side and side.cover then
      return true
    end
  end
  return false
end

local function battlerInCover(session, battle, battler, isPlayer, ent)
  if ent and (ent.coverBlend or 0) > 0.15 then
    return true
  end
  return battlerCoverHeld(session, battle, battler, isPlayer)
end

--- Ease the mon toward the nearest prop and thicken that prop while held.
function Projectiles.syncCoverHold(session, battle, dt)
  if not session then
    return
  end
  dt = dt or (1 / 60)
  local covers = session.covers
  if type(covers) == "table" then
    for i = 1, #covers do
      local prop = covers[i]
      if prop then
        prop.coverGrow = 0
        prop._coverTowardX, prop._coverTowardY = nil, nil
      end
    end
  end
  local function apply(ent, covered)
    if not ent then
      return
    end
    local target = covered and 1 or 0
    local cur = ent.coverBlend or 0
    local rate = covered and 6 or 8
    cur = cur + (target - cur) * math.min(1, dt * rate)
    if math.abs(cur - target) < 0.02 then
      cur = target
    end
    ent.coverBlend = cur
    ent._coverHeld = covered == true
    ent._coverSurface = Projectiles.coverSurface(session, ent, battle)
    if covered then
      ent.wanderTx, ent.wanderTy = nil, nil
      ent._wanderCD = math.max(ent._wanderCD or 0, 2.2)
    end
    if cur > 0.05 then
      local prop = Projectiles.nearestCoverProp(session, ent)
      if prop then
        local px, py = propPixel(prop)
        ent.coverTx, ent.coverTy = px, py
        prop.coverGrow = math.max(prop.coverGrow or 0, cur)
        local dx = (ent.px or ent.basePx or px) - px
        local dy = (ent.py or ent.basePy or py) - py
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.1 then
          prop._coverTowardX, prop._coverTowardY = dx / len, dy / len
        else
          prop._coverTowardX, prop._coverTowardY = 0, 1
        end
        ent._coverWall = nil
      else
        local GridMod = session._deps and session._deps.Grid
        local hug = GridMod and type(GridMod.wallHug) == "function"
            and GridMod.wallHug(session.grid, ent) or nil
        ent._coverWall = hug
        if hug and session.grid and ent.padU ~= nil then
          local wu = ent.padU + (hug.u or 0)
          local wv = ent.padV + (hug.v or 0)
          local px, py = Coords.padToPx(session.grid, wu, wv)
          ent.coverTx, ent.coverTy = px, py
        else
          ent.coverTx, ent.coverTy = nil, nil
        end
      end
    else
      ent.coverTx, ent.coverTy = nil, nil
      ent._coverWall = nil
      if not covered then
        ent._coverSurface = nil
      end
    end
  end
  apply(session.playerMon, battlerCoverHeld(session, battle, battle and battle.player, true))
  apply(session.enemyMon, battlerCoverHeld(session, battle, battle and battle.enemy, false))
end

local STATUS_AURA = {
  PAR = { color = { 1.00, 0.88, 0.18 }, kind = "sparks" },
  FRZ = { color = { 0.55, 0.90, 1.00 }, kind = "ice" },
  PSN = { color = { 0.70, 0.32, 0.82 }, kind = "bubbles" },
  TOX = { color = { 0.55, 0.16, 0.70 }, kind = "bubbles" },
  BRN = { color = { 1.00, 0.42, 0.10 }, kind = "flame" },
  SLP = { color = { 0.72, 0.78, 0.96 }, kind = "zs" },
  CNF = { color = { 0.95, 0.78, 0.22 }, kind = "swirl" },
  LEECH = { color = { 0.28, 0.72, 0.24 }, kind = "seed" },
  COVER = { color = { 0.78, 0.66, 0.38 }, kind = "cover" },
}

-- Status moves that paint on the foe (not the user).
local FOE_STATUS_MOVES = {
  LEECH_SEED = true,
  TOXIC = true,
  SLEEP_POWDER = true,
  STUN_SPORE = true,
  POISONPOWDER = true,
  HYPNOSIS = true,
  CONFUSE_RAY = true,
  THUNDER_WAVE = true,
  GLARE = true,
  SPORE = true,
  LOVELY_KISS = true,
  SING = true,
  SUPERSONIC = true,
  SAND_ATTACK = true,
  SANDATTACK = true,
}

-- Strong hits: always shove the target back + typed impact FX (Gen1 roster + high BP).
local POWER_MOVES = {
  HYPER_BEAM = true,
  EXPLOSION = true,
  SELFDESTRUCT = true,
  HYDRO_PUMP = true,
  FIRE_BLAST = true,
  BLIZZARD = true,
  THUNDER = true,
  SOLARBEAM = true,
  SOLAR_BEAM = true,
  EARTHQUAKE = true,
  DOUBLE_EDGE = true,
  SKULL_BASH = true,
  DREAM_EATER = true,
  THUNDERBOLT = true,
  ICE_BEAM = true,
  FLAMETHROWER = true,
  SURF = true,
  PSYCHIC = true,
  PSYCHIC_M = true,
  TAKE_DOWN = true,
  BODY_SLAM = true,
  MEGA_PUNCH = true,
  MEGA_KICK = true,
  STRENGTH = true,
  SLAM = true,
  HYPER_FANG = true,
  SUBMISSION = true,
  RAZOR_WIND = true,
  SKY_ATTACK = true,
  ROCK_SLIDE = true,
  PETAL_DANCE = true,
  FISSURE = true,
  HORN_DRILL = true,
  GUILLOTINE = true,
}

local POWER_BP_THRESHOLD = 100

local function center(session, ent)
  if not ent then
    return nil, nil
  end
  -- Prefer live sprite pose so specials track bob / mid-lerp toward the foe.
  if type(ent.px) == "number" and type(ent.py) == "number" then
    return ent.px + 8, ent.py + 4
  end
  if type(ent.basePx) == "number" and type(ent.basePy) == "number" then
    return ent.basePx + 8, ent.basePy + 4
  end
  if session and session.grid and ent.padU ~= nil then
    local x, y = Coords.padCenterPx(session.grid, ent.padU, ent.padV)
    return x, y - 4
  end
  return nil, nil
end

local function removeEntity(session, projectile)
  local battle = session and session._battle
  local ow = battle and battle.game and battle.game.overworld
  local entities = ow and ow.entities
  if type(entities) == "table" then
    for i = #entities, 1, -1 do
      if entities[i] == projectile then
        table.remove(entities, i)
      end
    end
  end
end

local function now()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return 0
end

local function resolveFx(opts)
  opts = opts or {}
  local moveType = tostring(opts.moveType or ""):upper()
  local moveId = tostring(opts.moveId or ""):upper():gsub("%s+", "_")
  local named = MOVE_FX[moveId]
  local typed = TYPE_STYLE[moveType]
  local style = (named and named.style)
      or (typed and typed.style)
      or "orb"
  local glitz = (named and named.glitz)
      or (typed and typed.glitz)
      or nil
  local color = (named and named.color) or TYPE_COLORS[moveType]
  return {
    moveType = moveType,
    moveId = moveId,
    style = style,
    glitz = glitz,
    color = color,
    duration = named and named.duration,
    radius = (named and named.radius) or (typed and typed.radius),
    arc = (named and named.arc) or (typed and typed.arc),
  }
end

-- Named travel FX (Night Shade shadow, Earthquake bloom, …) fly even when
-- the Gen1 type split marks the move physical. Type defaults stay on the
-- contact / special path so Tackle doesn't become a floating orb.
local TRAVEL_STYLES = {
  orb = true,
  beam = true,
  stream = true,
  shadow = true,
  drain = true,
  multi = true,
  spiral = true,
  aura = true,
  area = true,
  wave = true,
  bolt = true,
  surf = true,
  razor = true,
  swift = true,
  sonic = true,
  ray = true,
  ember = true,
  rock = true,
  slide = true,
  blast = true,
  gust = true,
  sand = true,
  clones = true,
}

function Projectiles.isTravelFx(opts)
  local moveId = tostring((opts or {}).moveId or ""):upper():gsub("%s+", "_")
  local named = MOVE_FX[moveId]
  if not (named and named.style) then
    return false
  end
  return TRAVEL_STYLES[named.style] == true
end

-- Jaws / punches / slams close the gap even when the Gen1 type split marks
-- the move special (Bite is often Dark; Fire Punch is Fire).
function Projectiles.isContactFx(opts)
  local moveId = tostring((opts or {}).moveId or ""):upper():gsub("%s+", "_")
  local named = MOVE_FX[moveId]
  return named and named.style == "contact" or false
end

function Projectiles.isPowerfulMove(opts)
  opts = opts or {}
  local moveId = tostring(opts.moveId or ""):upper():gsub("%s+", "_")
  if POWER_MOVES[moveId] then
    return true
  end
  local power = tonumber(opts.movePower or opts.power)
  return power ~= nil and power >= POWER_BP_THRESHOLD
end

local function drawPowerBurst(g, x, y, t, age, c, opts)
  opts = opts or {}
  local impact = opts.impact == true
  local fade = 1 - t * 0.35
  local pulse = 0.55 + 0.45 * math.abs(math.sin((age or 0) * 14))
  local radius = (impact and 10 or 7) + t * (impact and 12 or 8)
  g.setColor(c[1], c[2], c[3], 0.22 * fade * pulse)
  g.circle("fill", x, y, radius)
  for i = 1, (impact and 10 or 6) do
    local a = (age or 0) * (impact and 7 or 9) + i * (math.pi * 2 / 6)
    local dist = t * (impact and 14 or 10) + (i % 3) * 2
    local px = x + math.cos(a) * dist
    local py = y + math.sin(a) * dist * 0.55
    g.setColor(c[1], c[2], c[3], (0.75 - t * 0.35) * fade)
    g.circle("fill", px, py, impact and 2.2 or 1.6)
    g.setColor(1, 1, 1, 0.55 * fade)
    g.circle("fill", px - 0.4, py - 0.5, 0.7)
  end
  if impact then
    -- Debris / shock lines on wall or cover.
    for i = 1, 5 do
      local a = i * 1.2 + (age or 0) * 5
      g.setColor(0.82, 0.78, 0.72, 0.65 * fade)
      g.setLineWidth(1.5)
      g.line(x, y, x + math.cos(a) * (6 + t * 8), y + math.sin(a) * (4 + t * 5))
    end
    g.setColor(0.55, 0.48, 0.42, 0.35 * fade)
    g.ellipse("fill", x, y + 2, 8 + t * 6, 3 + t * 2)
  end
  g.setColor(1, 1, 1, 0.45 * fade * pulse)
  g.circle("fill", x, y, impact and 4 or 3)
end

local function withAdd(g, fn)
  local restored = false
  if g and g.setBlendMode then
    restored = pcall(g.setBlendMode, "add")
  end
  fn()
  if restored then
    pcall(g.setBlendMode, "alpha")
  end
end

--- Rim light + bloom around a battler (overlay; voxel sprites skip ent:draw).
local function drawClashGlow(g, p, x, y, t, c)
  local fade = 1 - t * 0.45
  if t > 0.72 then
    fade = fade * (1 - (t - 0.72) / 0.28)
  end
  local pulse = 0.62 + 0.38 * math.abs(math.sin((p.age or 0) * 16))
  local cr, cg, cb = c[1] or 1, c[2] or 0.92, c[3] or 0.55
  withAdd(g, function()
    g.setColor(cr, cg, cb, 0.22 * fade * pulse)
    if g.ellipse then
      g.ellipse("fill", x, y + 2, 13 + pulse * 2, 7.5)
    else
      g.circle("fill", x, y + 2, 11)
    end
    g.setColor(1.00, 0.96, 0.72, 0.32 * fade * pulse)
    g.circle("fill", x, y - 2, 6.5 + pulse)
    g.setColor(1, 1, 1, 0.42 * fade * pulse)
    g.circle("fill", x, y - 3, 3.2)
    for i = 1, 6 do
      local a = (p.age or 0) * 9 + i * 1.05
      local rx = 8 + (i % 3)
      g.setColor(cr, cg, cb, 0.28 * fade)
      g.setLineWidth(1.4)
      g.line(x, y - 1,
        x + math.cos(a) * rx,
        y + math.sin(a) * rx * 0.55 - 2)
    end
  end)
end

--- Speed-line hair behind a lunge. dirX/dirY is the strike heading.
local function drawClashTrail(g, p, x, y, t, c)
  local fade = 1 - t * 0.4
  if t > 0.7 then
    fade = fade * (1 - (t - 0.7) / 0.3)
  end
  local dx, dy = p.dirX or 1, p.dirY or 0
  local bx, by = -dx, -dy
  local nx, ny = -dy, dx
  local pulse = 0.7 + 0.3 * math.abs(math.sin((p.age or 0) * 22))
  local cr, cg, cb = c[1] or 1, c[2] or 0.9, c[3] or 0.55
  withAdd(g, function()
    for i = 1, 8 do
      local off = (i - 4.5) * 1.7
      local len = (10 + i * 2.6) * (1.12 - t * 0.35)
      local sx = x + nx * off - 0.4
      local sy = y + ny * off * 0.5 - 1.5
      local ex = sx + bx * len
      local ey = sy + by * len * 0.7
      g.setColor(cr, cg, cb, 0.20 * fade * pulse)
      g.setLineWidth(2.6)
      g.line(sx, sy, ex, ey)
      g.setColor(1.00, 0.97, 0.86, 0.55 * fade * pulse)
      g.setLineWidth(1)
      g.line(sx, sy, ex, ey)
    end
    for i = 1, 4 do
      local u = i / 5
      local px = x + bx * (5 + u * 11)
      local py = y + by * (4 + u * 8) - 1
      g.setColor(1, 1, 1, (0.28 - u * 0.18) * fade)
      if g.ellipse then
        g.ellipse("fill", px, py, 4.2 - u, 1.35)
      else
        g.circle("fill", px, py, 2.2 - u * 0.5)
      end
    end
  end)
end

local function drawBall(g, x, y)
  g.setColor(0.08, 0.06, 0.07, 1)
  g.circle("fill", x, y, 4)
  g.setColor(0.92, 0.18, 0.18, 1)
  g.arc("fill", x, y, 3, math.pi, math.pi * 2)
  g.setColor(0.96, 0.96, 0.90, 1)
  g.arc("fill", x, y, 3, 0, math.pi)
  g.setColor(0.08, 0.06, 0.07, 1)
  g.rectangle("fill", x - 3, y - 1, 6, 2)
  g.setColor(1, 1, 1, 1)
  g.circle("fill", x, y, 1)
end

local function trailPoints(p, x, y, n, spacing)
  local pts = {}
  local dx, dy = p.dirX or 1, p.dirY or 0
  for i = 0, n - 1 do
    pts[#pts + 1] = {
      x = x - dx * spacing * i,
      y = y - dy * spacing * i,
      a = 1 - i / math.max(1, n),
    }
  end
  return pts
end

--- Jagged lightning polyline from (ox,oy) → (x,y). Returns point list.
local function lightningPoints(ox, oy, x, y, age, segs, amp)
  segs = segs or 7
  amp = amp or 5.5
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local nx, ny = 0, 1
  if len > 0.1 then
    nx, ny = -dy / len, dx / len
  end
  local pts = { { ox, oy } }
  for i = 1, segs - 1 do
    local u = i / segs
    local jitter = math.sin((age or 0) * 58 + i * 2.7) * amp
        + math.sin((age or 0) * 23 + i * 5.1) * (amp * 0.55)
        + math.cos((age or 0) * 81 + i * 1.4) * (amp * 0.3)
    local envelope = math.sin(u * math.pi)
    pts[#pts + 1] = {
      ox + dx * u + nx * jitter * envelope,
      oy + dy * u + ny * jitter * envelope,
    }
  end
  pts[#pts + 1] = { x, y }
  return pts, nx, ny
end

local function strokePoly(g, pts, width, r, gr, b, a)
  if not (pts and #pts >= 2) then
    return
  end
  g.setColor(r, gr, b, a)
  g.setLineWidth(width)
  for i = 1, #pts - 1 do
    g.line(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2])
  end
end

local function drawLightningBolt(g, ox, oy, x, y, age, c, opts)
  opts = opts or {}
  local fade = opts.fade or 1
  local flash = 0.55 + 0.45 * math.abs(math.sin((age or 0) * 34))
  local pts, nx, ny = lightningPoints(ox, oy, x, y, age, opts.segs or 8, opts.amp or 5.5)
  local cr, cg, cb = c[1] or 1, c[2] or 0.88, c[3] or 0.18
  local core = opts.coreColor or { 1, 1, 0.92 }
  local forkCore = opts.forkCore or { 1, 1, 0.9 }
  local mid = opts.midColor or { cr, cg * 0.95, cb * 0.55 }
  strokePoly(g, pts, opts.glow or 5.5, cr, cg, cb, 0.28 * fade * flash)
  strokePoly(g, pts, opts.mid or 2.8, mid[1], mid[2], mid[3], 0.8 * fade)
  strokePoly(g, pts, opts.core or 1.3, core[1], core[2], core[3], 0.95 * fade * flash)
  -- Forks / side branches.
  local forks = opts.forks
  if forks == nil then
    forks = true
  end
  if forks then
    for i = 2, #pts - 1, 2 do
      local side = (i % 4 < 2) and 1 or -1
      local fork = (opts.forkLen or 5) + (i % 3)
      local px, py = pts[i][1], pts[i][2]
      local fx = px + nx * fork * side + math.sin((age or 0) * 44 + i) * 1.4
      local fy = py + ny * fork * side + math.cos((age or 0) * 37 + i) * 1.2
      strokePoly(g, { { px, py }, { fx, fy } }, 2.2, cr, cg, cb, 0.45 * fade)
      strokePoly(g, { { px, py }, { fx, fy } }, 1.0,
        forkCore[1], forkCore[2], forkCore[3], 0.7 * fade * flash)
    end
  end
  return pts, nx, ny
end

--- Serpentine shadow body points from caster → tip (Night Shade).
local function shadowRibbon(ox, oy, x, y, age, segs)
  segs = segs or 12
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local nx, ny = 0, 1
  if len > 0.1 then
    nx, ny = -dy / len, dx / len
  end
  local pts = {}
  for i = 0, segs do
    local u = i / segs
    local amp = (3.2 + u * 3.5) * math.sin(u * math.pi)
    local wobble = math.sin(u * math.pi * 3.2 + (age or 0) * 11) * amp
        + math.sin(u * math.pi * 5.5 - (age or 0) * 7.5) * (amp * 0.45)
    pts[#pts + 1] = {
      ox + dx * u + nx * wobble,
      oy + dy * u + ny * wobble * 0.55 - math.sin(u * math.pi) * 1.5,
      u,
    }
  end
  return pts
end

local function drawShadeSmoke(g, x, y, t, age, c)
  -- Bursting smoke wisps at the impact point.
  local life = math.max(0, math.min(1, t))
  local fade = 1 - life
  for i = 1, 10 do
    local a = (age or 0) * 3.5 + i * 0.85
    local dist = 2 + life * (9 + (i % 3) * 4)
    local px = x + math.cos(a) * dist
    local py = y + math.sin(a) * dist * 0.7 - life * (4 + i % 4)
    local r = 2.8 + life * (5 + (i % 3)) + math.sin(a * 2) * 0.8
    local aFill = (0.7 - life * 0.45) * fade
    g.setColor(0.45, 0.22, 0.62, aFill * 0.5)
    g.circle("fill", px, py, r + 2.2)
    g.setColor(c[1], c[2], c[3], aFill)
    g.circle("fill", px, py, r)
    g.setColor(0.7, 0.5, 0.82, aFill * 0.4)
    g.circle("line", px, py, r * 0.85)
  end
  -- Soft dark bloom under the puff.
  g.setColor(0.05, 0.02, 0.08, 0.45 * fade)
  g.circle("fill", x, y + 1, 7 + life * 12)
end

--- Psychic / Confusion: enveloping aura around the target.
--- crush = Psychic squeeze rings; confuse = dizzy reverse-orbit motes.
local function drawPsyAura(g, x, y, ox, oy, t, age, c, opts)
  opts = opts or {}
  local crush = opts.crush == true
  local confuse = opts.confuse == true
  local fade = 1 - t * 0.18
  if t > 0.72 then
    fade = fade * (1 - (t - 0.72) / 0.28)
  end
  local pulse = 0.55 + 0.45 * math.abs(math.sin((age or 0) * 8.5))
  -- Thought sparkles from caster → target on the way in.
  if ox and oy and (math.abs(ox - x) + math.abs(oy - y) > 4) then
    local n = crush and 7 or 5
    for i = 1, n do
      local u = ((i / n) + t * 0.85) % 1
      local px = ox + (x - ox) * u
      local py = oy + (y - oy) * u + math.sin(u * math.pi) * -3
          + math.sin((age or 0) * 9 + i) * 1.4
      local a = (0.25 + 0.55 * u) * fade * (1 - t * 0.35)
      g.setColor(c[1], c[2], c[3], a * 0.55)
      g.circle("fill", px, py, crush and 2.4 or 1.8)
      g.setColor(1, 0.9, 1, a)
      g.circle("fill", px, py, crush and 1.1 or 0.8)
    end
  end
  -- Soft magenta bloom under the target.
  g.setColor(c[1], c[2], c[3], 0.22 * fade * pulse)
  g.ellipse("fill", x, y + 3, crush and (16 + pulse * 4) or (11 + pulse * 3),
    crush and 7 or 5)
  -- Concentric telekinetic rings.
  local rings = crush and 4 or 3
  for i = 1, rings do
    local u = i / rings
    local squeeze = crush and (1 - 0.26 * math.sin(t * math.pi * 2.2 + i * 0.7)) or 1
    local wobble = confuse and math.sin((age or 0) * 9 + i * 1.4) * 2.1 or 0
    local grow = 0.62 + t * 0.55
    local rx = (6.5 + u * (crush and 11 or 8)) * squeeze * grow
    local ry = (3.0 + u * (crush and 5.2 or 3.8)) * squeeze * grow
    g.setColor(c[1], c[2], c[3], (0.72 - u * 0.22) * fade)
    g.setLineWidth(crush and 2.3 or 1.5)
    g.ellipse("line", x + wobble, y - 1 - u * 1.4, rx, ry)
    if crush then
      g.setColor(1, 0.78, 1, 0.28 * fade * pulse)
      g.ellipse("line", x, y - 1 - u * 1.4, rx * 0.86, ry * 0.86)
    end
  end
  -- Orbiting motes (Confusion spins the other way and wobbles).
  local n = crush and 8 or 6
  local spin = (age or 0) * (confuse and -7.4 or 6.6)
  for i = 1, n do
    local a = spin + i * (math.pi * 2 / n)
    local orbit = crush
      and (9 + math.sin(t * math.pi) * 7)
      or (7 + math.sin((age or 0) * 4.2 + i) * 3.2)
    local px = x + math.cos(a) * orbit
    local py = y + math.sin(a) * orbit * 0.46 - 3
        - math.sin((age or 0) * 5.2 + i) * (confuse and 2.6 or 1.6)
    g.setColor(c[1], c[2], c[3], 0.82 * fade)
    g.circle("fill", px, py, crush and 1.9 or 1.45)
    g.setColor(1, 1, 1, 0.7 * fade)
    g.circle("fill", px - 0.35, py - 0.45, crush and 0.7 or 0.55)
  end
  -- Core flash / dizzy spark.
  g.setColor(1, 0.82, 1, (crush and 0.38 or 0.28) * fade * pulse)
  g.circle("fill", x, y - 2, crush and 5.2 or 3.4)
  if confuse then
    -- Tiny star motes for the dizzy hit.
    for i = 1, 3 do
      local a = (age or 0) * 5 + i * 2.1
      local r = 4 + i * 2
      g.setColor(1, 0.92, 1, 0.55 * fade)
      g.circle("fill", x + math.cos(a) * r, y - 6 + math.sin(a * 1.4) * 2, 0.9)
    end
  end
end

--- Leech Seed plant burst + traveling seed (attack) and pulsing sprouts (aura).
local function drawSeedSprouts(g, x, y, phase, c, opts)
  opts = opts or {}
  local planted = opts.planted == true
  local fade = opts.fade or 1
  local pulse = 0.55 + 0.45 * math.abs(math.sin((phase or 0) * 3.4))
  local baseY = y + (planted and 5 or 2)
  -- Soft green ground bloom.
  g.setColor(c[1], c[2], c[3], (planted and 0.22 or 0.14) * fade * pulse)
  g.ellipse("fill", x, baseY, planted and (9 + pulse * 3) or 6, planted and 3.5 or 2.2)
  -- Tiny grass blades.
  for i = 1, (planted and 4 or 2) do
    local bx = x + (i - (planted and 2.5 or 1.5)) * (planted and 3.2 or 2.8)
    local sway = math.sin((phase or 0) * 5.5 + i * 1.3) * (planted and 1.2 or 0.6)
    local h = (planted and (4 + pulse * 3) or 2.5)
        + math.sin((phase or 0) * 4 + i * 2) * (planted and 1.4 or 0.5)
    g.setColor(0.18, 0.48, 0.14, 0.85 * fade)
    g.rectangle("fill", bx + sway * 0.3, baseY - h, 1.4, h)
    g.setColor(c[1], c[2], c[3], 0.75 * fade)
    g.rectangle("fill", bx + sway * 0.3 + 0.2, baseY - h + 0.8, 0.9, h - 1.2)
    if planted and g.line then
      g.setColor(0.12, 0.32, 0.08, 0.55 * fade)
      g.setLineWidth(1)
      g.line(bx, baseY, bx + sway, baseY - h)
    end
  end
  if planted then
    -- Embedded seed nub.
    g.setColor(0.42, 0.28, 0.10, 0.9 * fade)
    g.ellipse("fill", x, baseY - 0.5, 2.2, 1.4)
    g.setColor(0.55, 0.38, 0.14, 0.7 * fade)
    g.ellipse("line", x, baseY - 0.5, 2.4, 1.6)
  end
end

local function drawSeedPlant(g, x, y, ox, oy, t, age, c)
  local travelT = math.min(1, t / 0.52)
  local plantT = math.max(0, (t - 0.48) / 0.52)
  local tipX = ox + (x - ox) * travelT
  local tipY = oy + (y - oy) * travelT - math.sin(travelT * math.pi) * 10
  -- Leaf trail behind the seed.
  if travelT < 0.98 then
    for i = 1, 4 do
      local u = travelT - i * 0.08
      if u > 0 then
        local px = ox + (x - ox) * u
        local py = oy + (y - oy) * u - math.sin(u * math.pi) * 8
            + math.sin((age or 0) * 12 + i) * 1.2
        local rot = (age or 0) * 3 + i
        g.setColor(c[1], c[2], c[3], 0.45 - i * 0.08)
        g.setLineWidth(1.2)
        g.line(px - 2, py, px + 2, py + math.sin(rot) * 0.8)
        g.line(px, py - 1.5, px + math.cos(rot) * 1.5, py + 1)
      end
    end
    -- Flying seed body.
    g.setColor(0.38, 0.24, 0.08, 0.95)
    g.ellipse("fill", tipX, tipY, 3.2, 2.2)
    g.setColor(c[1], c[2], c[3], 0.85)
    g.ellipse("fill", tipX - 0.4, tipY - 0.6, 2.4, 1.5)
    g.setColor(0.22, 0.52, 0.16, 0.8)
    g.line(tipX - 2.5, tipY - 0.5, tipX + 1, tipY - 2.2)
    g.line(tipX + 2.2, tipY - 0.3, tipX + 0.5, tipY - 2)
  end
  -- Planting burst as the seed lands.
  if plantT > 0 then
    local fade = 1 - plantT * 0.35
    drawSeedSprouts(g, x, y, (age or 0) + plantT * 2, c, {
      planted = true,
      fade = fade,
    })
    for i = 1, 5 do
      local a = (age or 0) * 4 + i * 1.25
      local dist = plantT * (5 + i * 1.8)
      g.setColor(c[1], c[2], c[3], (0.65 - plantT * 0.4) * fade)
      g.circle("fill",
        x + math.cos(a) * dist,
        y + 3 + math.sin(a) * dist * 0.5,
        1.2 + (1 - plantT) * 0.8)
    end
  end
end

--- Supersonic: expanding sound rings travel caster → foe, then ring the head.
local function drawSonicWaves(g, x, y, ox, oy, t, age, c)
  local fade = 1
  if t > 0.78 then
    fade = 1 - (t - 0.78) / 0.22
  end
  local travelT = math.min(1, t / 0.55)
  local landT = math.max(0, (t - 0.48) / 0.52)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local fx, fy = 1, 0
  if len > 0.1 then
    fx, fy = dx / len, dy / len
  end
  local ang = math.atan2(fy, fx)
  -- Traveling ")))" arcs along the path.
  for i = 1, 5 do
    local u = travelT - (i - 1) * 0.12
    if u > 0.02 and u < 1.05 then
      local along = math.min(1, u)
      local px = ox + dx * along
      local py = oy + dy * along
      local open = 3.2 + i * 1.4 + math.sin((age or 0) * 10 + i) * 0.6
      local a = (0.75 - i * 0.1) * fade * (1 - math.max(0, u - 0.85) / 0.2)
      g.setColor(c[1], c[2], c[3], a * 0.45)
      g.setLineWidth(2.4)
      if g.arc then
        g.arc("line", px, py, open, ang - 1.05, ang + 1.05)
      else
        g.circle("line", px, py, open)
      end
      g.setColor(1, 1, 1, a * 0.55)
      g.setLineWidth(1)
      if g.arc then
        g.arc("line", px, py, open * 0.72, ang - 0.85, ang + 0.85)
      end
    end
  end
  -- Rings around the target once the wave arrives.
  if landT > 0 then
    for i = 1, 3 do
      local r = 4 + landT * (7 + i * 3) + math.sin((age or 0) * 8 + i) * 0.8
      g.setColor(c[1], c[2], c[3], (0.7 - i * 0.15) * fade * (1 - landT * 0.35))
      g.setLineWidth(1.6)
      g.ellipse("line", x, y - 2, r, r * 0.55)
    end
    g.setColor(1, 1, 1, 0.45 * fade * (1 - landT))
    g.circle("fill", x, y - 3, 1.6)
  end
end

--- Confuse Ray: short purple smog wad that drifts caster → foe.
local function drawConfuseRay(g, x, y, ox, oy, t, age, c)
  local fade = 1
  if t > 0.72 then
    fade = 1 - (t - 0.72) / 0.28
  end
  local travelT = math.min(1, t / 0.38)
  local landT = math.max(0, (t - 0.32) / 0.68)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local nx, ny = 0, 1
  if len > 0.1 then
    nx, ny = -dy / len, dx / len
  end
  local cr, cg, cb = c[1] or 0.72, c[2] or 0.32, c[3] or 0.98
  -- Pale glow wake behind the wad.
  if travelT > 0.05 then
    local wake = 0.46
    local segs = 9
    local prevX, prevY
    for i = 0, segs do
      local u = travelT - (i / segs) * wake * travelT
      if u > 0.01 then
        local wobble = math.sin(u * math.pi * 2.2 + (age or 0) * 8) * 1.15
        local px = ox + dx * u + nx * wobble
        local py = oy + dy * u + ny * wobble * 0.4
            - math.sin(u * math.pi) * 1.2
        local along = 1 - i / segs
        local a = (0.16 + 0.42 * along) * fade * (1 - landT * 0.55)
        local r = 1.1 + along * 2.6
        g.setColor(0.82, 0.58, 1.00, a * 0.38)
        g.circle("fill", px, py, r + 2.4)
        g.setColor(0.96, 0.84, 1.00, a * 0.85)
        g.circle("fill", px, py, r * 0.5)
        if prevX then
          g.setColor(0.88, 0.68, 1.00, a * 0.55)
          g.setLineWidth(1.4 + along * 1.8)
          g.line(prevX, prevY, px, py)
        end
        prevX, prevY = px, py
      end
    end
  end
  -- Compact wad: only a short trail behind the leading puff.
  local trail = 0.28
  local n = 6
  for i = 1, n do
    local u = travelT - (i - 1) / math.max(1, n - 1) * trail * travelT
    if u > 0.02 then
      local billow = math.sin((age or 0) * 5.4 + i * 1.6) * (2.8 + i * 0.35)
      local px = ox + dx * u + nx * billow
      local py = oy + dy * u + ny * billow * 0.45
          - math.sin(u * math.pi) * 1.2 - (i - 1) * 0.35
      local r = (8.2 - i * 0.55) + math.sin((age or 0) * 7 + i) * 1.6
      local a = (0.28 - i * 0.028) * fade
      g.setColor(cr * 0.5, cg * 0.35, cb * 0.65, a * 0.5)
      g.circle("fill", px, py + 0.6, r + 4)
      g.setColor(cr, cg, cb, a)
      g.ellipse("fill", px, py, r, r * 0.7)
      g.setColor(math.min(1, cr + 0.1), math.min(1, cg + 0.06), 1, a * 0.32)
      g.circle("fill", px - 1.1, py - 1.4, r * 0.42)
    end
  end
  -- Loose wisps around the wad.
  for i = 1, 5 do
    local u = travelT - 0.06 - (i % 3) * 0.05
    if u > 0.02 then
      local a = (age or 0) * 4.4 + i * 1.35
      local px = ox + dx * u + math.cos(a) * (3.2 + i * 0.8)
      local py = oy + dy * u + math.sin(a) * 2.4 - 1
      g.setColor(cr, cg, cb, 0.16 * fade)
      g.circle("fill", px, py, 3.4 + (i % 2) * 1.2)
    end
  end
  if landT > 0 then
    local bloom = 6 + landT * 7
    g.setColor(cr, cg, cb, 0.22 * fade * (1 - landT * 0.45))
    g.ellipse("fill", x, y + 1, bloom, bloom * 0.62)
    drawPsyAura(g, x, y, x, y, math.min(1, 0.4 + landT * 0.6), age, c, {
      confuse = true,
    })
  end
end

--- Surf: curling tidal wall that swells at the caster, rushes the field, then crashes.
local function drawSurfTide(g, x, y, ox, oy, t, age, c, radius)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local fx, fy = 1, 0
  local nx, ny = 0, 1
  if len > 0.1 then
    fx, fy = dx / len, dy / len
    nx, ny = -fy, fx
  end
  local fade = 1
  if t > 0.84 then
    fade = 1 - (t - 0.84) / 0.16
  end
  local swell = math.min(1, t / 0.20)
  local rush = math.max(0, math.min(1, (t - 0.10) / 0.62))
  local crash = math.max(0, (t - 0.68) / 0.32)
  local cr, cg, cb = c[1] or 0.2, c[2] or 0.58, c[3] or 1
  local height = (5 + rush * 11) * (1 - crash * 0.55)
  local width = (radius or 16) * (0.45 + swell * 0.55 + rush * 0.35)

  -- Swell bloom at the caster's feet.
  g.setColor(cr, cg, cb, 0.22 * swell * fade)
  g.ellipse("fill", ox, oy + 3, 8 + swell * 7, 3 + swell * 2)
  for i = 1, 5 do
    local a = (age or 0) * 7 + i * 1.3
    local rise = swell * (4 + i) - math.sin(a) * 1.2
    g.setColor(cr, cg, cb, (0.55 - swell * 0.2) * fade)
    g.circle("fill",
      ox + math.cos(a) * (3 + swell * 4),
      oy + 2 - rise,
      1.2 + (i % 2) * 0.6)
    g.setColor(1, 1, 1, 0.45 * fade * swell)
    g.circle("fill",
      ox + math.cos(a) * (3 + swell * 4) - 0.4,
      oy + 2 - rise - 0.4,
      0.5)
  end

  -- Flood sheet from caster toward the crest.
  if rush > 0.02 then
    local midX = ox + dx * 0.5
    local midY = oy + dy * 0.5 + 3
    g.setColor(cr * 0.55, cg * 0.7, cb, 0.18 * fade)
    g.ellipse("fill", midX, midY, math.max(8, len * 0.55), 5 + rush * 3)
    for i = 1, 4 do
      local u = (i / 5) * rush
      local px = ox + dx * u
      local py = oy + dy * u + 3
      g.setColor(1, 1, 1, 0.18 * fade * (1 - u))
      g.setLineWidth(1)
      g.ellipse("line", px, py, 6 + u * 4, 2.2)
    end
  end

  -- Curling breaker at the traveling crest.
  if rush > 0.04 and crash < 0.95 then
    local lean = 2.5 + rush * 3
    local cx = x - fx * lean
    local cy = y + 2
    g.setColor(0.08, 0.22, 0.48, 0.55 * fade)
    g.ellipse("fill", cx, cy + 1, width * 0.95, height * 0.42)
    g.setColor(cr, cg, cb, 0.72 * fade)
    g.ellipse("fill", cx + fx * 1.2, cy - height * 0.15, width * 0.82, height * 0.38)
    g.setColor(0.55, 0.82, 1.00, 0.45 * fade)
    g.ellipse("fill", cx + fx * 2, cy - height * 0.28, width * 0.5, height * 0.22)
    g.setColor(0.92, 0.98, 1.00, 0.88 * fade)
    g.ellipse("fill", x + fx * 1.5, cy - height * 0.55, width * 0.62, 2.4 + rush * 1.4)
    g.setColor(1, 1, 1, 0.7 * fade)
    g.ellipse("line", x + fx * 1.5, cy - height * 0.55, width * 0.68, 2.8)
    for i = 1, 8 do
      local side = ((i % 2) * 2 - 1)
      local along = (i % 4) * 1.4
      local px = x + nx * (width * 0.35 * side) * math.sin((age or 0) * 9 + i)
          + fx * along
      local py = cy - height * 0.7 - (i % 3) * 1.6
          + math.sin((age or 0) * 14 + i) * 1.2
      g.setColor(1, 1, 1, (0.75 - i * 0.06) * fade)
      g.circle("fill", px, py, 1.1 + (i % 3) * 0.35)
    end
    -- Vertical columns so the wall reads in 2.5D.
    for i = -2, 2 do
      local wx = cx + nx * i * (width / 5)
      local wy = cy - 1
      local h = height * (0.7 + math.sin((age or 0) * 8 + i) * 0.12)
      g.setColor(cr, cg, cb, 0.35 * fade)
      g.rectangle("fill", wx - 1.6, wy - h, 3.2, h)
      g.setColor(1, 1, 1, 0.22 * fade)
      g.rectangle("fill", wx - 0.5, wy - h, 1.1, h * 0.45)
    end
  end

  -- Crash: geyser + foam burst at the foe.
  if crash > 0 then
    local burst = math.sin(crash * math.pi)
    g.setColor(cr, cg, cb, 0.32 * fade * burst)
    g.ellipse("fill", x, y + 3, 10 + crash * 14, 4 + crash * 5)
    g.setColor(0.9, 0.97, 1, 0.55 * fade)
    g.setLineWidth(2)
    g.ellipse("line", x, y + 3, 8 + crash * 12, 3 + crash * 4)
    for i = 1, 12 do
      local a = i * 0.52 + (age or 0) * 3
      local dist = crash * (8 + (i % 4) * 4)
      local px = x + math.cos(a) * dist
      local py = y + math.sin(a) * dist * 0.45 - crash * (6 + i % 5) * 1.6
      local r = 1.4 + (i % 3) * 0.7
      g.setColor(cr, cg, cb, (0.7 - crash * 0.35) * fade)
      g.circle("fill", px, py, r)
      g.setColor(1, 1, 1, 0.55 * fade * (1 - crash * 0.4))
      g.circle("fill", px - 0.4, py - 0.5, r * 0.4)
    end
    g.setColor(0.75, 0.9, 1, 0.4 * burst * fade)
    g.ellipse("fill", x, y - crash * 8, 4 + burst * 3, 7 + crash * 6)
  end
end

--- Spinning leaf-blade (elongated diamond + midrib).
local function drawLeafBlade(g, px, py, rot, scale, c, alpha)
  scale = scale or 1
  alpha = alpha or 1
  local ca, sa = math.cos(rot), math.sin(rot)
  local function pt(lx, ly)
    return px + lx * ca * scale - ly * sa * scale,
      py + lx * sa * scale + ly * ca * scale
  end
  local x1, y1 = pt(5.2, 0)
  local x2, y2 = pt(0.8, 2.3)
  local x3, y3 = pt(-4.4, 0)
  local x4, y4 = pt(0.8, -2.3)
  g.setColor(c[1], c[2], c[3], alpha)
  g.polygon("fill", x1, y1, x2, y2, x3, y3, x4, y4)
  g.setColor(0.16, 0.42, 0.12, alpha * 0.85)
  g.setLineWidth(1)
  g.line(x1, y1, x3, y3)
  g.setColor(0.72, 1.00, 0.55, alpha * 0.55)
  local hx, hy = pt(2.2, -0.7)
  g.circle("fill", hx, hy, 0.7 * scale)
end

--- Razor Leaf: wide cyclone of blades that spirals into the foe.
local function drawRazorVolley(g, x, y, ox, oy, t, age, c)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local nx, ny = 0, 1
  if len > 0.1 then
    nx, ny = -dy / len, dx / len
  end
  local fade = 1
  if t > 0.84 then
    fade = 1 - (t - 0.84) / 0.16
  end
  local spinUp = math.min(1, t / 0.20)
  local launch = math.max(0, (t - 0.12) / 0.88)

  -- Gather cyclone at the caster.
  if spinUp > 0.02 and t < 0.52 then
    local ringFade = (1 - math.max(0, (t - 0.28) / 0.24)) * fade
    g.setColor(c[1], c[2], c[3], 0.18 * ringFade)
    g.ellipse("fill", ox, oy + 2, 8 + spinUp * 5, 3.4)
    for i = 1, 8 do
      local a = (age or 0) * 16 + i * (math.pi * 2 / 8)
      local r = 6 + spinUp * 4
      local px = ox + math.cos(a) * r
      local py = oy + math.sin(a) * r * 0.42 - 1
      drawLeafBlade(g, px, py, a + math.pi * 0.5, 0.55 + spinUp * 0.2, c,
        0.7 * ringFade)
    end
  end

  -- Extra orbiting leaves filling the travel corridor.
  if launch > 0.04 and t < 0.78 then
    for i = 1, 6 do
      local u = math.min(1, launch * 0.92 - (i - 1) * 0.07)
      if u > 0.04 then
        local spin = (age or 0) * 12 + i * 1.1
        local amp = 6.5 * (1 - u * 0.35)
        local px = ox + dx * u + nx * math.cos(spin) * amp
        local py = oy + dy * u + ny * math.sin(spin) * amp * 0.48
            - math.sin(u * math.pi) * 2
        drawLeafBlade(g, px, py, spin + math.pi * 0.5, 0.58, c, 0.55 * fade)
      end
    end
  end

  -- Staggered flying blades on a tightening helix into the foe.
  local n = 13
  for i = 1, n do
    local delay = (i - 1) * 0.042
    local u = (launch - delay) / math.max(0.32, 1 - delay)
    if u > 0 and u < 1.18 then
      local along = math.min(1, u)
      local spread = (1 - along * 0.72) * (8.5 + (i % 5) * 1.5)
      local spin = along * math.pi * 4.4 + i * 0.85 + (age or 0) * 11
      local px = ox + dx * along + nx * math.cos(spin) * spread
      local py = oy + dy * along + ny * math.sin(spin) * spread * 0.5
          - math.sin(along * math.pi) * 2.4
      local rot = (age or 0) * (18 + i * 1.2) + spin
      local aLeaf = fade * (u < 1 and 0.95 or (1.18 - u) / 0.18)
      drawLeafBlade(g, px, py, rot, 0.82 + (i % 4) * 0.1, c, aLeaf)
      if along > 0.08 and along < 0.95 then
        g.setColor(c[1], c[2], c[3], 0.3 * aLeaf)
        g.setLineWidth(1.3)
        g.line(px - dx * 0.07, py - dy * 0.07, px, py)
      end
      if along > 0.78 and along < 1.05 then
        local slash = (along - 0.78) / 0.27
        local reach = 3 + slash * 7
        local sa = rot + math.pi * 0.25
        g.setColor(0.85, 1.00, 0.55, (0.8 - slash * 0.5) * fade)
        g.setLineWidth(1.6)
        g.line(
          px - math.cos(sa) * reach, py - math.sin(sa) * reach,
          px + math.cos(sa) * reach, py + math.sin(sa) * reach)
        g.setColor(1, 1, 1, 0.55 * fade * (1 - slash))
        g.circle("fill", px, py, 1.2)
      end
    end
  end

  -- Cyclone tightening onto the foe.
  if t > 0.34 then
    local tight = math.min(1, (t - 0.34) / 0.48)
    local ring = 13 * (1 - tight * 0.72)
    local inward = (age or 0) * 14
    for i = 1, 8 do
      local a = inward + i * (math.pi * 2 / 8)
      local px = x + math.cos(a) * ring
      local py = y + math.sin(a) * ring * 0.48 - 1
      drawLeafBlade(g, px, py, a + math.pi * 0.5 + tight * 2,
        0.62 + (i % 3) * 0.08, c, (0.82 - tight * 0.35) * fade)
    end
    g.setColor(c[1], c[2], c[3], 0.16 * fade * (1 - tight * 0.4))
    g.ellipse("fill", x, y + 2, 6 + ring * 0.35, 2.6)
  end

  -- Impact leaf burst past the target.
  if t > 0.72 then
    local burst = (t - 0.72) / 0.28
    for i = 1, 7 do
      local a = i * 0.9 + (age or 0) * 2
      local dist = burst * (7 + i)
      drawLeafBlade(g,
        x + math.cos(a) * dist,
        y + math.sin(a) * dist * 0.55 - burst * 2,
        a + burst * 4, 0.5, c, (0.7 - burst * 0.45) * fade)
    end
  end
end

--- Four-point sparkle star (classic Swift).
local function drawStar(g, px, py, rot, scale, c, alpha)
  scale = scale or 1
  alpha = alpha or 1
  local ca, sa = math.cos(rot), math.sin(rot)
  local function pt(lx, ly)
    return px + (lx * ca - ly * sa) * scale,
      py + (lx * sa + ly * ca) * scale
  end
  local x1, y1 = pt(0, -3.2)
  local x2, y2 = pt(0.85, 0)
  local x3, y3 = pt(0, 3.2)
  local x4, y4 = pt(-0.85, 0)
  local x5, y5 = pt(-3.2, 0)
  local x6, y6 = pt(0, 0.85)
  local x7, y7 = pt(3.2, 0)
  local x8, y8 = pt(0, -0.85)
  g.setColor(c[1], c[2], c[3], alpha)
  g.polygon("fill", x1, y1, x2, y2, x3, y3, x4, y4)
  g.polygon("fill", x5, y5, x6, y6, x7, y7, x8, y8)
  g.setColor(1, 1, 1, alpha * 0.9)
  g.circle("fill", px, py, 0.65 * scale)
end

--- Swift: a swarm of little stars that peel off the caster and fly into the foe.
local function drawSwiftStars(g, x, y, ox, oy, t, age, c)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local nx, ny = 0, 1
  if len > 0.1 then
    nx, ny = -dy / len, dx / len
  end
  local fade = 1
  if t > 0.84 then
    fade = 1 - (t - 0.84) / 0.16
  end
  local n = 9
  for i = 1, n do
    local delay = (i - 1) * 0.055
    local u = (t - delay) / math.max(0.42, 0.78 - delay * 0.4)
    if u > 0 and u < 1.12 then
      local along = math.min(1, u)
      local side = ((i % 2) * 2 - 1)
      local spread = (1.8 + (i % 4) * 1.4) * math.sin(along * math.pi)
      local weave = math.sin(along * math.pi * 2.2 + i * 0.9) * 1.6
      local px = ox + dx * along + nx * (spread * side + weave)
      local py = oy + dy * along + ny * (spread * side * 0.45)
          - math.sin(along * math.pi) * (2.2 + (i % 3))
      local twinkle = 0.72 + 0.28 * math.abs(math.sin((age or 0) * 18 + i * 2.1))
      local aStar = fade * (u < 1 and 0.95 or (1.12 - u) / 0.12) * twinkle
      local scale = (0.55 + (i % 3) * 0.14) * (0.85 + twinkle * 0.25)
      local rot = (age or 0) * (7 + i * 0.6) + i * 0.8
      -- Sparkle crumbs behind each star.
      if along > 0.06 and along < 0.95 then
        for k = 1, 3 do
          local back = k * 0.045
          local bx = ox + dx * math.max(0, along - back)
              + nx * (spread * side + weave) * 0.7
          local by = oy + dy * math.max(0, along - back)
              + ny * (spread * side * 0.45) * 0.7
          g.setColor(c[1], c[2], c[3], (0.4 - k * 0.1) * aStar)
          g.circle("fill", bx, by, 0.7 - k * 0.12)
        end
      end
      drawStar(g, px, py, rot, scale, c, aStar)
    end
  end
  -- Little pings as the swarm arrives.
  if t > 0.62 then
    local burst = (t - 0.62) / 0.38
    for i = 1, 6 do
      local a = i * 1.047 + (age or 0) * 5
      local dist = burst * (5 + i * 1.2)
      drawStar(g,
        x + math.cos(a) * dist,
        y + math.sin(a) * dist * 0.5 - burst * 1.5,
        a, 0.42, c, (0.7 - burst * 0.5) * fade)
    end
  end
end

--- Teardrop flame sprite. rot=0 points up (screen -Y).
local function drawFlameTongue(g, px, py, rot, scale, alpha)
  if type(px) ~= "number" or type(py) ~= "number" then
    return
  end
  scale = math.max(0.18, scale or 1)
  alpha = alpha or 1
  rot = rot or 0
  local fx, fy = math.sin(rot), -math.cos(rot)
  local nx, ny = -fy, fx
  local h, w = 7.4 * scale, 2.55 * scale
  local function pt(along, side)
    return px + fx * along * h + nx * side * w,
      py + fy * along * h + ny * side * w
  end
  local function fillPoly(x1, y1, x2, y2, x3, y3, x4, y4, r, gr, b, a)
    if g.polygon then
      g.setColor(r, gr, b, a)
      g.polygon("fill", x1, y1, x2, y2, x3, y3, x4, y4)
    else
      g.setColor(r, gr, b, a)
      g.circle("fill", (x1 + x3) * 0.5, (y1 + y3) * 0.5, w * 0.7)
    end
  end
  local tx, ty = pt(1.00, 0)
  local rx, ry = pt(0.28, 1.08)
  local bx, by = pt(-0.16, 0)
  local lx, ly = pt(0.28, -1.08)
  fillPoly(tx + fx * 1.2, ty + fy * 1.2, rx + nx * 0.55, ry + ny * 0.55,
    bx - fx * 0.6, by - fy * 0.6, lx - nx * 0.55, ly - ny * 0.55,
    0.92, 0.14, 0.02, 0.32 * alpha)
  fillPoly(tx, ty, rx, ry, bx, by, lx, ly, 1.00, 0.30, 0.04, 0.90 * alpha)
  local itx, ity = pt(0.74, 0)
  local irx, iry = pt(0.22, 0.62)
  local ibx, iby = pt(0.00, 0)
  local ilx, ily = pt(0.22, -0.62)
  fillPoly(itx, ity, irx, iry, ibx, iby, ilx, ily,
    1.00, 0.62, 0.10, 0.95 * alpha)
  local ytx, yty = pt(0.46, 0)
  local yrx, yry = pt(0.16, 0.32)
  local ybx, yby = pt(0.05, 0)
  local ylx, yly = pt(0.16, -0.32)
  fillPoly(ytx, yty, yrx, yry, ybx, yby, ylx, yly,
    1.00, 0.93, 0.40, 0.95 * alpha)
  g.setColor(1, 1, 1, 0.82 * alpha)
  g.circle("fill", px + fx * 0.10 * h, py + fy * 0.10 * h, math.max(0.45, 0.72 * scale))
end

--- Crescent wind slash. ang is travel heading (atan2).
local function drawWindSlash(g, px, py, ang, scale, c, alpha)
  scale = scale or 1
  alpha = alpha or 1
  local cr, cg, cb = c[1] or 0.7, c[2] or 0.84, c[3] or 1
  local r = 5.2 * scale
  if g.arc then
    g.setColor(cr, cg, cb, 0.28 * alpha)
    g.setLineWidth(3.4 * scale)
    g.arc("line", px, py, r + 1.2, ang - 1.05, ang + 1.05)
    g.setColor(cr, cg, cb, 0.88 * alpha)
    g.setLineWidth(1.8 * scale)
    g.arc("line", px, py, r, ang - 0.95, ang + 0.95)
    g.setColor(1, 1, 1, 0.55 * alpha)
    g.setLineWidth(1)
    g.arc("line", px, py, r * 0.68, ang - 0.72, ang + 0.72)
  else
    local ca, sa = math.cos(ang), math.sin(ang)
    local nx, ny = -sa, ca
    g.setColor(cr, cg, cb, 0.85 * alpha)
    g.setLineWidth(2)
    g.line(px + nx * r, py + ny * r * 0.45 - sa * 1.2,
      px - nx * r, py - ny * r * 0.45 + sa * 1.2)
  end
end

local ROCK_SHAPES = {
  { { -3.4, 1.6 }, { -1.2, 3.2 }, { 2.8, 2.2 }, { 3.6, -0.8 }, { 0.8, -3.1 }, { -2.6, -2.0 } },
  { { -2.9, 2.6 }, { 0.6, 3.5 }, { 3.4, 1.0 }, { 2.2, -2.8 }, { -1.6, -3.2 }, { -3.5, -0.2 } },
  { { -2.4, 3.0 }, { 2.0, 2.8 }, { 3.5, 0.2 }, { 1.4, -3.0 }, { -2.8, -2.2 }, { -3.3, 0.8 } },
  { { -3.1, 0.8 }, { -0.4, 3.4 }, { 3.2, 2.4 }, { 3.0, -1.6 }, { 0.2, -3.3 }, { -3.2, -1.8 } },
}

local function drawRockChunk(g, px, py, rot, scale, c, alpha, shape)
  if type(px) ~= "number" or type(py) ~= "number" then
    return
  end
  scale = math.max(0.22, scale or 1)
  alpha = alpha or 1
  local verts = ROCK_SHAPES[(((shape or 1) - 1) % #ROCK_SHAPES) + 1]
  local ca, sa = math.cos(rot or 0), math.sin(rot or 0)
  local pts = {}
  local unpackFn = table.unpack or unpack
  for i = 1, #verts do
    local lx, ly = verts[i][1], verts[i][2]
    pts[#pts + 1] = px + (lx * ca - ly * sa) * scale
    pts[#pts + 1] = py + (lx * sa + ly * ca) * scale
  end
  local cr, cg, cb = c[1] or 0.66, c[2] or 0.56, c[3] or 0.34
  -- Grounded shadow so the lob reads against grass / cave floors.
  if g.ellipse then
    g.setColor(0.18, 0.12, 0.08, 0.28 * alpha)
    g.ellipse("fill", px + 0.4, py + 2.4 * scale, 3.4 * scale, 1.15 * scale)
  end
  g.setColor(cr * 0.62, cg * 0.58, cb * 0.48, alpha)
  g.polygon("fill", unpackFn(pts))
  -- Lit facet (first three verts pulled toward a highlight).
  local hx = px + (-1.1 * ca - (-1.6) * sa) * scale
  local hy = py + (-1.1 * sa + (-1.6) * ca) * scale
  local ix = px + (1.4 * ca - (-0.4) * sa) * scale
  local iy = py + (1.4 * sa + (-0.4) * ca) * scale
  local jx = px + (0.2 * ca - 0.6 * sa) * scale
  local jy = py + (0.2 * sa + 0.6 * ca) * scale
  g.setColor(math.min(1, cr * 1.25), math.min(1, cg * 1.22),
    math.min(1, cb * 1.15), 0.55 * alpha)
  g.polygon("fill", hx, hy, ix, iy, jx, jy)
  g.setColor(1, 1, 1, 0.28 * alpha)
  g.circle("fill", px - 0.6 * scale, py - 0.9 * scale, 0.7 * scale)
end

--- Rock Throw: kick a tumbling stone, then shatter it on the foe.
local function drawRockThrow(g, x, y, ox, oy, t, age, c)
  if type(x) ~= "number" or type(y) ~= "number"
      or type(ox) ~= "number" or type(oy) ~= "number" then
    return
  end
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local nx, ny = 0, 1
  if len > 0.1 then
    nx, ny = -dy / len, dx / len
  end
  local cr, cg, cb = c[1] or 0.66, c[2] or 0.56, c[3] or 0.34
  local fade = 1
  if t > 0.86 then
    fade = 1 - (t - 0.86) / 0.14
  end
  local kick = math.min(1, t / 0.14)
  local travel = math.max(0, math.min(1, (t - 0.04) / 0.70))
  local smash = math.max(0, (t - 0.68) / 0.32)

  -- Scuff at the thrower's feet.
  g.setColor(cr, cg, cb, 0.32 * kick * (1 - smash) * fade)
  g.ellipse("fill", ox, oy + 5, 4 + kick * 5, 1.8 + kick * 1.1)
  for i = 1, 4 do
    local a = (age or 0) * 7 + i * 1.4
    g.setColor(cr * 0.8, cg * 0.75, cb * 0.65, (0.55 - i * 0.08) * kick * fade)
    g.circle("fill",
      ox + math.cos(a) * (1.8 + kick * 2.4),
      oy + 4 - kick * (2 + i * 0.6),
      0.9 + (i % 2) * 0.35)
  end

  -- Dust ribbon behind the lob.
  if travel > 0.06 and smash < 0.55 then
    for i = 1, 5 do
      local u = math.max(0, travel - i * 0.07)
      if u > 0.04 then
        local px = ox + dx * u + nx * math.sin(u * 9 + i) * 1.2
        local py = oy + dy * u - math.sin(u * math.pi) * 2.2
        g.setColor(cr, cg, cb, (0.42 - i * 0.06) * fade * (1 - smash))
        g.circle("fill", px, py, 1.35 - i * 0.14)
      end
    end
  end

  -- Main stone + two chips, until the hit.
  if smash < 0.82 then
    local spin = (age or 0) * 14
    local bodyA = fade * (1 - smash * 0.85)
    drawRockChunk(g, x, y, spin, 1.18 * (1 - smash * 0.35), c, bodyA, 1)
    for i = 1, 2 do
      local delay = 0.08 + (i - 1) * 0.07
      local u = (t - delay) / 0.62
      if u > 0.04 and u < 0.98 then
        local along = math.min(1, u)
        local side = (i == 1) and 1 or -1
        local px = ox + dx * along + nx * side * (2.2 + along * 2.6)
        local py = oy + dy * along - math.sin(along * math.pi) * (3 + i)
            + ny * side * 0.8
        drawRockChunk(g, px, py, -spin * (0.8 + i * 0.3),
          0.52 + i * 0.08, c, bodyA * 0.9, i + 1)
      end
    end
  end

  -- Impact shatter.
  if smash > 0.02 then
    local burst = math.min(1, smash)
    g.setColor(cr, cg, cb, 0.28 * fade * (1 - burst * 0.4))
    g.ellipse("fill", x, y + 2, 5 + burst * 9, 2.4 + burst * 2.2)
    for i = 1, 8 do
      local a = i * 0.85 + (age or 0) * 3
      local dist = burst * (5 + (i % 4) * 2.2)
      local px = x + math.cos(a) * dist
      local py = y + math.sin(a) * dist * 0.55 - burst * 3.2
      local shardSpin = a + burst * 8 + i
      drawRockChunk(g, px, py, shardSpin,
        0.38 + (i % 3) * 0.08, c, (0.9 - burst * 0.55) * fade, i)
    end
    for i = 1, 6 do
      local a = i * 1.1 + burst * 4
      g.setColor(0.86, 0.76, 0.58, (0.55 - burst * 0.35) * fade)
      g.circle("fill",
        x + math.cos(a) * burst * (3 + i),
        y + math.sin(a) * burst * 2.2 - burst * 2,
        1.1 - burst * 0.4)
    end
  end
end

-- Staggered stones that rain onto the target (classic Rock Slide).
local ROCK_SLIDE_FALLS = {
  { delay = 0.00, ox = -7, drop = 30, scale = 1.18, shape = 1, spin = 11 },
  { delay = 0.08, ox =  6, drop = 34, scale = 0.92, shape = 2, spin = -13 },
  { delay = 0.16, ox = -1, drop = 26, scale = 1.32, shape = 3, spin = 9 },
  { delay = 0.24, ox =  9, drop = 32, scale = 0.78, shape = 4, spin = -16 },
  { delay = 0.32, ox = -9, drop = 28, scale = 1.04, shape = 1, spin = 14 },
  { delay = 0.40, ox =  2, drop = 36, scale = 1.12, shape = 2, spin = -10 },
}

--- Rock Slide: stones peel off above the foe and pile onto them.
local function drawRockSlide(g, x, y, _ox, _oy, t, age, c, radius)
  if type(x) ~= "number" or type(y) ~= "number" then
    return
  end
  local cr, cg, cb = c[1] or 0.66, c[2] or 0.56, c[3] or 0.34
  local fade = 1
  if t > 0.82 then
    fade = 1 - (t - 0.82) / 0.18
  end
  local spread = (radius or 16) * 0.55
  local rumble = 0.55 + 0.45 * math.abs(math.sin((age or 0) * 18))

  -- Ground haze / rumble under the cascade.
  if g.ellipse then
    g.setColor(cr * 0.55, cg * 0.48, cb * 0.38, 0.22 * fade * rumble)
    g.ellipse("fill", x, y + 5, 7 + t * 9, 2.4 + t * 1.6)
  end
  g.setColor(0.78, 0.68, 0.48, 0.28 * fade)
  for i = 1, 7 do
    local a = (age or 0) * 6 + i * 0.95
    g.circle("fill",
      x + math.cos(a) * (3 + t * 6),
      y + 4 + math.sin(a * 1.4) * 1.2 - t * 1.5,
      0.7 + (i % 3) * 0.25)
  end

  for i = 1, #ROCK_SLIDE_FALLS do
    local spec = ROCK_SLIDE_FALLS[i]
    local localT = (t - spec.delay) / 0.38
    if localT > 0 then
      local fall = math.min(1, localT)
      local grav = fall * fall
      local landed = fall >= 1
      local px = x + spec.ox * (spread / 8) + grav * 1.2
      local py = y - spec.drop * (1 - grav)
      if landed then
        py = y + (i % 3) * 0.6
        px = x + spec.ox * 0.72
      end
      local bodyA = fade
      if landed then
        bodyA = fade * math.max(0, 1 - (localT - 1) * 1.6)
      end
      if bodyA > 0.04 then
        if not landed and g.ellipse then
          local shadow = 0.35 + grav * 0.65
          g.setColor(0.16, 0.11, 0.07, 0.22 * fade * shadow)
          g.ellipse("fill", px, y + 5, 2.2 * spec.scale * shadow,
            0.85 * spec.scale * shadow)
        end
        local rot = (age or 0) * spec.spin + spec.delay * 4
        if landed then
          rot = spec.spin * 0.35 + i
        end
        drawRockChunk(g, px, py, rot, spec.scale * (landed and 0.92 or 1),
          c, bodyA, spec.shape)
      end
      if landed then
        local burst = math.min(1, localT - 1)
        local dustA = (0.7 - burst * 0.9) * fade
        if dustA > 0.04 then
          if g.ellipse then
            g.setColor(cr, cg, cb, 0.28 * dustA)
            g.ellipse("fill", px, y + 4, 3.5 + burst * 6, 1.5 + burst * 1.4)
          end
          for s = 1, 4 do
            local a = s * 1.7 + i + burst * 5
            drawRockChunk(g,
              px + math.cos(a) * burst * (3 + s),
              y + math.sin(a) * burst * 1.8 - burst * 2.4,
              a + burst * 6, 0.32 + (s % 2) * 0.08, c,
              dustA * 0.9, s)
          end
        end
      end
    end
  end
end

local EMBER_VARIANTS = { "volley", "hop", "spray", "corkscrew", "pop" }

local function emberFade(t)
  if t > 0.82 then
    return 1 - (t - 0.82) / 0.18
  end
  return 1
end

local function emberAxes(x, y, ox, oy)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local nx, ny = 0, 1
  if len > 0.1 then
    nx, ny = -dy / len, dx / len
  end
  return dx, dy, nx, ny, math.atan2(dy, dx) + math.pi * 0.5
end

local function drawEmberImpact(g, x, y, t, age, fade)
  if t <= 0.62 then
    return
  end
  local burst = (t - 0.62) / 0.38
  for i = 1, 5 do
    local a = i * 1.256 + (age or 0) * 4
    local dist = burst * (4 + i)
    drawFlameTongue(g,
      x + math.cos(a) * dist,
      y + math.sin(a) * dist * 0.5 - burst * 2,
      a + math.pi * 0.5, 0.42, (0.7 - burst * 0.5) * fade)
  end
end

--- Ember / volley: staggered bouncing flame tongues caster → foe.
local function drawEmberVolley(g, x, y, ox, oy, t, age, fade, dx, dy, nx, ny, heading)
  local n = 6
  for i = 1, n do
    local delay = (i - 1) * 0.07
    local u = (t - delay) / math.max(0.38, 0.78 - delay * 0.35)
    if u > 0 and u < 1.14 then
      local along = math.min(1, u)
      local side = ((i % 2) * 2 - 1)
      local bounce = math.sin(along * math.pi) * (5.5 + (i % 3) * 1.4)
      local weave = math.sin(along * math.pi * 2.1 + i) * 2.2
      local px = ox + dx * along + nx * (weave * side * 0.55)
      local py = oy + dy * along + ny * (weave * side * 0.3) - bounce
      local flick = 0.82 + 0.18 * math.abs(math.sin((age or 0) * 16 + i * 2.2))
      local a = fade * (u < 1 and 0.95 or (1.14 - u) / 0.14) * flick
      local rot = heading + math.sin((age or 0) * 10 + i) * 0.35
          + side * 0.18
      drawFlameTongue(g, px, py, rot, (0.62 + (i % 3) * 0.12) * flick, a)
      if along > 0.08 and along < 0.92 then
        for k = 1, 2 do
          local back = k * 0.05
          local sx = ox + dx * math.max(0, along - back)
          local sy = oy + dy * math.max(0, along - back) - bounce * 0.7
          g.setColor(1, 0.72, 0.18, (0.45 - k * 0.14) * a)
          g.circle("fill", sx, sy, 1.1 - k * 0.25)
        end
      end
    end
  end
end

--- Ember / hop: two or three bigger fireballs that skip toward the foe.
local function drawEmberHop(g, x, y, ox, oy, t, age, fade, dx, dy, nx, ny, heading)
  for i = 1, 3 do
    local delay = (i - 1) * 0.11
    local u = (t - delay) / 0.72
    if u > 0 and u < 1.12 then
      local along = math.min(1, u)
      local hops = 1 + (i % 2)
      local bounce = math.abs(math.sin(along * math.pi * hops)) * (7.5 + i * 1.6)
      local side = ((i % 2) * 2 - 1) * (1.4 + along * 1.2)
      local px = ox + dx * along + nx * side
      local py = oy + dy * along + ny * side * 0.25 - bounce
      local flick = 0.8 + 0.2 * math.abs(math.sin((age or 0) * 18 + i))
      local a = fade * (u < 1 and 1 or (1.12 - u) / 0.12) * flick
      drawFlameTongue(g, px, py, heading + math.sin((age or 0) * 8 + i) * 0.4,
        (0.95 + (i % 3) * 0.12) * flick, a)
      -- Spark kick at each bounce peak.
      local peak = math.sin(along * math.pi * hops)
      if peak > 0.82 then
        for k = 1, 3 do
          local aa = (age or 0) * 12 + i * 2 + k
          drawFlameTongue(g,
            px + math.cos(aa) * 2.2,
            py + 1.2,
            aa, 0.32, a * 0.7)
        end
      end
      g.setColor(1, 0.78, 0.22, 0.4 * a)
      g.circle("fill", px, py + 1.4, 1.4)
    end
  end
end

--- Ember / spray: a widening fan of small tongues.
local function drawEmberSpray(g, x, y, ox, oy, t, age, fade, dx, dy, nx, ny, heading)
  for i = 1, 9 do
    local delay = (i - 1) * 0.035
    local u = (t - delay) / 0.62
    if u > 0 and u < 1.1 then
      local along = math.min(1, u)
      local lane = (i - 5) / 4
      local spread = along * 7.2 * lane
      local loft = -along * 2.4 - math.sin(along * math.pi) * 2.1
      local px = ox + dx * along + nx * spread
      local py = oy + dy * along + ny * spread * 0.3 + loft
      local flick = 0.78 + 0.22 * math.abs(math.sin((age or 0) * 20 + i))
      local a = fade * (u < 1 and 0.9 or (1.1 - u) / 0.1) * flick
      drawFlameTongue(g, px, py,
        heading + lane * 0.55 + math.sin((age or 0) * 11 + i) * 0.25,
        (0.48 + (i % 3) * 0.1) * flick, a)
    end
  end
end

--- Ember / corkscrew: tongues spiral around the flight line.
local function drawEmberCorkscrew(g, x, y, ox, oy, t, age, fade, dx, dy, nx, ny, heading)
  for i = 1, 5 do
    local delay = (i - 1) * 0.06
    local u = (t - delay) / 0.70
    if u > 0 and u < 1.12 then
      local along = math.min(1, u)
      local ang = along * math.pi * 4.2 + i * 1.256 + (age or 0) * 6
      local rad = 2.2 + along * 3.4
      local px = ox + dx * along + nx * math.cos(ang) * rad
      local py = oy + dy * along + ny * math.sin(ang) * rad * 0.55
          - math.sin(along * math.pi) * 2.4
      local flick = 0.8 + 0.2 * math.abs(math.sin((age or 0) * 15 + i))
      local a = fade * (u < 1 and 0.95 or (1.12 - u) / 0.12) * flick
      drawFlameTongue(g, px, py, ang + math.pi * 0.5, 0.7 * flick, a)
      if along > 0.08 then
        g.setColor(1, 0.7, 0.16, 0.35 * a)
        g.circle("fill",
          ox + dx * math.max(0, along - 0.06),
          oy + dy * math.max(0, along - 0.06),
          1.0)
      end
    end
  end
end

--- Ember / pop: a few tongues that burst into sparks mid-flight.
local function drawEmberPop(g, x, y, ox, oy, t, age, fade, dx, dy, nx, ny, heading)
  for i = 1, 4 do
    local delay = (i - 1) * 0.09
    local u = (t - delay) / 0.68
    if u > 0 and u < 1.16 then
      local along = math.min(1, u)
      local side = ((i % 2) * 2 - 1)
      local px = ox + dx * along + nx * side * (1.6 + along)
      local py = oy + dy * along - math.sin(along * math.pi) * (4.5 + i)
      local flick = 0.82 + 0.18 * math.abs(math.sin((age or 0) * 14 + i))
      local a = fade * (u < 1 and 0.95 or (1.16 - u) / 0.16) * flick
      if along < 0.52 then
        drawFlameTongue(g, px, py, heading + side * 0.2, 0.88 * flick, a)
      else
        local pop = (along - 0.52) / 0.48
        for k = 1, 4 do
          local aa = i * 1.7 + k * 1.4 + (age or 0) * 5
          local dist = pop * (3.5 + k)
          drawFlameTongue(g,
            px + math.cos(aa) * dist,
            py + math.sin(aa) * dist * 0.55 - pop * 2.4,
            aa + math.pi * 0.5, 0.4 + (1 - pop) * 0.2,
            a * (0.85 - pop * 0.4))
        end
      end
    end
  end
end

local function drawEmberCast(g, x, y, ox, oy, t, age, c, variant)
  if type(x) ~= "number" or type(y) ~= "number"
      or type(ox) ~= "number" or type(oy) ~= "number" then
    return
  end
  local dx, dy, nx, ny, heading = emberAxes(x, y, ox, oy)
  local fade = emberFade(t)
  variant = variant or "volley"
  if variant == "hop" then
    drawEmberHop(g, x, y, ox, oy, t, age, fade, dx, dy, nx, ny, heading)
  elseif variant == "spray" then
    drawEmberSpray(g, x, y, ox, oy, t, age, fade, dx, dy, nx, ny, heading)
  elseif variant == "corkscrew" then
    drawEmberCorkscrew(g, x, y, ox, oy, t, age, fade, dx, dy, nx, ny, heading)
  elseif variant == "pop" then
    drawEmberPop(g, x, y, ox, oy, t, age, fade, dx, dy, nx, ny, heading)
  else
    drawEmberVolley(g, x, y, ox, oy, t, age, fade, dx, dy, nx, ny, heading)
  end
  drawEmberImpact(g, x, y, t, age, fade)
end

--- Flamethrower: dense jet of flame tongues along the stream.
local function drawFlameJet(g, x, y, ox, oy, t, age, c)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local nx, ny = 0, 1
  if len > 0.1 then
    nx, ny = -dy / len, dx / len
  end
  local heading = math.atan2(dy, dx) + math.pi * 0.5
  local fade = 1 - t * 0.18
  local n = 16
  for i = 0, n do
    local u = i / n
    local along = u * math.min(1, t * 1.18 + 0.06)
    local wobble = math.sin((age or 0) * 17 + i * 1.5) * (1.6 + u * 2.4)
        + math.cos((age or 0) * 11 + i * 2.1) * 1.1
    local px = ox + dx * along + nx * wobble
    local py = oy + dy * along + ny * wobble * 0.45 - u * 1.4
        - math.abs(math.sin((age or 0) * 14 + i)) * 0.6
    local flick = 0.78 + 0.22 * math.abs(math.sin((age or 0) * 22 + i * 1.7))
    local scale = (0.55 + (1 - u) * 0.85) * flick
    local a = (0.35 + 0.6 * (1 - u * 0.45)) * fade * flick
    local rot = heading + math.sin((age or 0) * 13 + i) * 0.28
    drawFlameTongue(g, px, py, rot, scale, a)
  end
  -- Hot core along the jet spine.
  if len > 1 then
    g.setColor(1.00, 0.82, 0.22, 0.22 * fade)
    g.setLineWidth(4)
    g.line(ox, oy, x, y)
    g.setColor(1.00, 0.95, 0.62, 0.45 * fade)
    g.setLineWidth(1.6)
    g.line(ox, oy, x, y)
  end
  -- Leading bloom.
  g.setColor(1.00, 0.45, 0.08, 0.28 * fade)
  g.circle("fill", x, y, 6.5)
  drawFlameTongue(g, x, y, heading, 1.15, 0.95 * fade)
  for i = 1, 5 do
    local a = (age or 0) * 15 + i * 1.8
    drawFlameTongue(g,
      x + math.cos(a) * (2.5 + i % 3),
      y + math.sin(a) * 1.8 - 1.5,
      heading + math.sin(a) * 0.5, 0.42, 0.7 * fade)
  end
end

--- Fire Blast: traveling fireball, then a 大-shaped star of tongues.
local function drawFireBlast(g, x, y, ox, oy, t, age, c, radius)
  local dx, dy = x - ox, y - oy
  local heading = math.atan2(dy, dx) + math.pi * 0.5
  local fade = 1
  if t > 0.86 then
    fade = 1 - (t - 0.86) / 0.14
  end
  local travelT = math.min(1, t / 0.46)
  local bloomT = math.max(0, (t - 0.40) / 0.60)
  if travelT < 0.98 then
    local tipX = ox + dx * travelT
    local tipY = oy + dy * travelT
    for i = 1, 6 do
      local u = travelT - (i - 1) * 0.055
      if u > 0.02 then
        local px = ox + dx * u
        local py = oy + dy * u
        drawFlameTongue(g, px, py, heading, 1.18 - i * 0.12,
          (0.9 - i * 0.1) * fade)
      end
    end
    g.setColor(1.00, 0.42, 0.06, 0.38 * fade)
    g.circle("fill", tipX, tipY, 9)
    g.setColor(1.00, 0.88, 0.28, 0.55 * fade)
    g.circle("fill", tipX, tipY, 4.2)
    drawFlameTongue(g, tipX, tipY, heading, 1.55, fade)
    drawFlameTongue(g, tipX, tipY, heading + 0.55, 0.95, 0.7 * fade)
    drawFlameTongue(g, tipX, tipY, heading - 0.55, 0.95, 0.7 * fade)
  end
  if bloomT > 0 then
    local R = (radius or 26) * (0.40 + bloomT * 0.82)
    g.setColor(1.00, 0.28, 0.04, 0.26 * fade * (1 - bloomT * 0.4))
    g.circle("fill", x, y, R)
    -- Horizontal bar of 大.
    g.setColor(1.00, 0.42, 0.08, 0.42 * fade * (1 - bloomT * 0.35))
    g.ellipse("fill", x, y, R * 0.92, 3.4 + bloomT * 1.2)
    drawFlameTongue(g, x - R * 0.55, y, -math.pi * 0.5, 1.15 + bloomT * 0.25,
      (0.95 - bloomT * 0.3) * fade)
    drawFlameTongue(g, x + R * 0.55, y, math.pi * 0.5, 1.15 + bloomT * 0.25,
      (0.95 - bloomT * 0.3) * fade)
    -- Five-point 大 star of tongues.
    local tips = {}
    for i = 1, 5 do
      local a = i * (math.pi * 2 / 5) - math.pi * 0.5 + bloomT * 0.25
      local dist = R * 0.52
      local tx = x + math.cos(a) * dist
      local ty = y + math.sin(a) * dist * 0.72
      tips[i] = { tx, ty }
      drawFlameTongue(g, tx, ty, a + math.pi * 0.5, 1.35 + bloomT * 0.42,
        (0.98 - bloomT * 0.32) * fade)
    end
    -- Pentagram spokes between every second tip.
    if g.line and #tips == 5 then
      g.setColor(1.00, 0.72, 0.18, 0.45 * fade * (1 - bloomT * 0.5))
      g.setLineWidth(1.6)
      for i = 1, 5 do
        local a = tips[i]
        local b = tips[((i + 1) % 5) + 1]
        g.line(a[1], a[2], b[1], b[2])
      end
    end
    drawFlameTongue(g, x, y - 1, 0, 1.22, 0.95 * fade)
    for i = 1, 9 do
      local a = i * 0.7 + (age or 0) * 5
      local dist = bloomT * (7 + (i % 3) * 3.5)
      g.setColor(1, 0.78, 0.22, (0.7 - bloomT * 0.4) * fade)
      g.circle("fill",
        x + math.cos(a) * dist,
        y + math.sin(a) * dist * 0.55 - bloomT * 2,
        1.4)
    end
  end
end

--- Hyper Beam: charge orb at the caster, then a fat gold beam with traveling rings.
local function drawHyperBeam(g, x, y, ox, oy, t, age, c)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local fx, fy = 1, 0
  local nx, ny = 0, 1
  if len > 0.1 then
    fx, fy = dx / len, dy / len
    nx, ny = -fy, fx
  end
  local fade = 1
  if t > 0.86 then
    fade = 1 - (t - 0.86) / 0.14
  end
  local chargeT = math.min(1, t / 0.26)
  local fireT = math.max(0, (t - 0.18) / 0.82)
  -- Charge bloom at the caster.
  if t < 0.48 then
    local pulse = 0.7 + 0.3 * math.abs(math.sin((age or 0) * 16))
    local r = 2.4 + chargeT * 9 * pulse
    g.setColor(1.00, 0.42, 0.08, 0.28 * fade * (1 - t * 0.4))
    g.circle("fill", ox, oy, r + 4)
    g.setColor(1.00, 0.72, 0.18, 0.55 * fade)
    g.circle("fill", ox, oy, r)
    g.setColor(1, 1, 0.92, 0.92 * fade)
    g.circle("fill", ox, oy, r * 0.42)
    for i = 1, 6 do
      local a = (age or 0) * 10 + i * (math.pi * 2 / 6)
      local dist = r + 2
      g.setColor(1.00, 0.78, 0.28, 0.7 * fade * (1 - t * 0.5))
      g.circle("fill", ox + math.cos(a) * dist, oy + math.sin(a) * dist * 0.55, 1.4)
    end
  end
  if fireT > 0.02 then
    local reach = math.min(1, fireT / 0.16)
    local tx = ox + dx * reach
    local ty = oy + dy * reach
    g.setColor(1.00, 0.34, 0.06, 0.28 * fade)
    g.setLineWidth(16)
    g.line(ox, oy, tx, ty)
    g.setColor(c[1], c[2], c[3], 0.45 * fade)
    g.setLineWidth(11)
    g.line(ox, oy, tx, ty)
    g.setColor(1.00, 0.72, 0.18, 0.85 * fade)
    g.setLineWidth(6)
    g.line(ox, oy, tx, ty)
    g.setColor(1, 1, 0.94, 0.95 * fade)
    g.setLineWidth(2.4)
    g.line(ox, oy, tx, ty)
    -- Traveling rings along the beam.
    local n = 5
    for i = 1, n do
      local u = ((fireT * 1.4 + i / n) % 1) * reach
      if u > 0.04 and u < 0.98 then
        local px = ox + dx * u
        local py = oy + dy * u
        local a = 0.55 * fade * (1 - math.abs(u - 0.5) * 0.6)
        g.setColor(1.00, 0.82, 0.32, a)
        g.setLineWidth(1.6)
        g.ellipse("line", px, py, 7 + math.sin((age or 0) * 8 + i) * 1.4, 3.2)
        g.setColor(1, 1, 0.9, a * 0.7)
        g.ellipse("line", px, py, 4.2, 1.8)
      end
    end
    -- Side motes.
    for i = 1, 7 do
      local u = (i / 8) * reach
      local wobble = math.sin((age or 0) * 14 + i * 1.7) * 3.4
      g.setColor(1.00, 0.62, 0.14, 0.45 * fade)
      g.circle("fill",
        ox + dx * u + nx * wobble,
        oy + dy * u + ny * wobble * 0.45,
        1.3)
    end
    -- Impact bloom.
    if reach > 0.82 then
      local slam = (reach - 0.82) / 0.18
      g.setColor(1.00, 0.48, 0.08, 0.32 * fade * (1 - slam * 0.4))
      g.circle("fill", tx, ty, 8 + slam * 10)
      g.setColor(1, 1, 0.9, 0.7 * fade)
      g.circle("fill", tx, ty, 3.4)
      for i = 1, 6 do
        local a = i * (math.pi * 2 / 6) + (age or 0) * 4
        local dist = 5 + slam * 8
        g.setColor(1.00, 0.78, 0.22, (0.8 - slam * 0.4) * fade)
        g.setLineWidth(1.8)
        g.line(tx, ty, tx + math.cos(a) * dist, ty + math.sin(a) * dist * 0.55)
      end
    end
  end
end

--- Psybeam: pastel corkscrew helix caster → foe.
local function drawPsybeam(g, x, y, ox, oy, t, age, c)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local nx, ny = 0, 1
  if len > 0.1 then
    nx, ny = -dy / len, dx / len
  end
  local fade = 1
  if t > 0.84 then
    fade = 1 - (t - 0.84) / 0.16
  end
  local travel = math.min(1, t / 0.22)
  local hues = {
    { 0.96, 0.38, 0.88 },
    { 1.00, 0.62, 0.92 },
    { 0.55, 0.82, 1.00 },
    { 0.92, 0.52, 1.00 },
  }
  -- Soft core beam.
  g.setColor(c[1], c[2], c[3], 0.22 * fade)
  g.setLineWidth(5)
  g.line(ox, oy, ox + dx * travel, oy + dy * travel)
  g.setColor(1, 0.88, 1, 0.55 * fade)
  g.setLineWidth(1.6)
  g.line(ox, oy, ox + dx * travel, oy + dy * travel)
  local segs = 18
  for strand = 1, 2 do
    local phase = strand * math.pi
    local prevX, prevY
    for i = 0, segs do
      local u = (i / segs) * travel
      local spin = u * math.pi * 6.2 + (age or 0) * 9 + phase
      local amp = 3.4 + math.sin(u * math.pi) * 1.6
      local px = ox + dx * u + nx * math.cos(spin) * amp
      local py = oy + dy * u + ny * math.cos(spin) * amp * 0.48
          + math.sin(spin) * 0.8
      local col = hues[(i % #hues) + 1]
      local a = (0.45 + 0.5 * u) * fade
      if prevX then
        g.setColor(col[1], col[2], col[3], a * 0.55)
        g.setLineWidth(1.8)
        g.line(prevX, prevY, px, py)
      end
      g.setColor(col[1], col[2], col[3], a)
      g.circle("fill", px, py, 1.55 + (i % 2) * 0.35)
      g.setColor(1, 1, 1, a * 0.7)
      g.circle("fill", px - 0.35, py - 0.4, 0.55)
      prevX, prevY = px, py
    end
  end
  -- Sparkle motes along the corkscrew.
  for i = 1, 8 do
    local u = ((i / 8) + (age or 0) * 0.35) % 1 * travel
    if u > 0.04 then
      local spin = u * math.pi * 6.2 + (age or 0) * 9
      local px = ox + dx * u + nx * math.sin(spin) * 4.2
      local py = oy + dy * u + ny * math.sin(spin) * 4.2 * 0.45
      g.setColor(1, 0.86, 1, 0.55 * fade)
      g.circle("fill", px, py, 0.9)
    end
  end
  if travel > 0.72 then
    local slam = (travel - 0.72) / 0.28
    g.setColor(c[1], c[2], c[3], 0.28 * fade)
    g.circle("fill", x, y, 5 + slam * 6)
    for i = 1, 5 do
      local a = i * 1.256 + (age or 0) * 6
      g.setColor(1, 0.78, 1, (0.7 - slam * 0.4) * fade)
      g.circle("fill",
        x + math.cos(a) * (4 + slam * 5),
        y + math.sin(a) * (4 + slam * 5) * 0.5,
        1.3)
    end
  end
end

--- Double Team: afterimages fan out in every direction around the user.
local function drawMonSilhouette(g, px, py, scale, c, alpha)
  scale = scale or 1
  alpha = alpha or 1
  g.setColor(c[1], c[2], c[3], alpha * 0.55)
  g.ellipse("fill", px, py + 2.2 * scale, 5.6 * scale, 3.4 * scale)
  g.circle("fill", px, py - 3.1 * scale, 3.5 * scale)
  g.setColor(1, 1, 1, alpha * 0.28)
  g.circle("fill", px - 0.9 * scale, py - 3.7 * scale, 1.15 * scale)
end

local function drawDoubleTeam(g, x, y, t, age, c)
  local fade = 1
  if t > 0.78 then
    fade = 1 - (t - 0.78) / 0.22
  end
  local pop = math.min(1, t / 0.16)
  -- Origin flicker.
  g.setColor(c[1], c[2], c[3], 0.22 * fade * (0.6 + 0.4 * math.sin((age or 0) * 18)))
  g.ellipse("fill", x, y + 2, 7 + pop * 3, 3.2)
  drawMonSilhouette(g, x, y, 1.0, c, 0.35 * fade * (1 - t * 0.4))
  local n = 12
  for i = 1, n do
    local delay = (i - 1) * 0.028
    local u = math.max(0, (t - delay) / 0.72)
    if u > 0.02 and u < 1.12 then
      local a = i * (math.pi * 2 / n) + t * 0.55
      local dist = (5 + math.min(1, u) * 20) * (1 + (i % 3) * 0.16)
      local px = x + math.cos(a) * dist
      local py = y + math.sin(a) * dist * 0.52 - math.sin(u * math.pi) * 2.4
      local aClone = fade * (u < 0.85 and 0.85 or (1.12 - u) / 0.27)
      drawMonSilhouette(g, px, py, 0.82 + (i % 3) * 0.08, c, aClone)
    end
  end
  -- Extra clones that dash farther out.
  for i = 1, 6 do
    local delay = 0.08 + (i - 1) * 0.05
    local u = math.max(0, (t - delay) / 0.62)
    if u > 0.02 and u < 1.05 then
      local a = i * 1.047 + 0.4
      local dist = 10 + math.min(1, u) * 26
      local px = x + math.cos(a) * dist
      local py = y + math.sin(a) * dist * 0.48 - u * 3
      drawMonSilhouette(g, px, py, 0.7, c, 0.55 * fade * (1 - u * 0.55))
    end
  end
end

--- Fire Spin: vortex of flame tongues around the foe.
local function drawFireSpin(g, x, y, t, age, c)
  local fade = 1 - t * 0.35
  local pulse = math.sin(t * math.pi)
  for i = 1, 8 do
    local a = (age or 0) * 9 + i * 0.785
    local r = (4 + i * 1.15) * (0.4 + 0.7 * pulse)
    local px = x + math.cos(a) * r
    local py = y + math.sin(a) * r * 0.55
    local rot = a + math.pi * 0.5 + 0.4
    drawFlameTongue(g, px, py, rot, 0.62 + (i % 3) * 0.12, 0.85 * fade)
  end
  g.setColor(1.00, 0.45, 0.08, 0.22 * fade)
  g.ellipse("fill", x, y + 2, 7 + pulse * 5, 2.6)
  drawFlameTongue(g, x, y - 1, 0, 0.85, 0.7 * fade)
end

--- Gust: traveling wind crescents + swirl impact.
local function drawGustWind(g, x, y, ox, oy, t, age, c)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local fx, fy = 1, 0
  local nx, ny = 0, 1
  if len > 0.1 then
    fx, fy = dx / len, dy / len
    nx, ny = -fy, fx
  end
  local ang = math.atan2(fy, fx)
  local fade = 1
  if t > 0.82 then
    fade = 1 - (t - 0.82) / 0.18
  end
  local travelT = math.min(1, t / 0.58)
  local landT = math.max(0, (t - 0.48) / 0.52)
  -- Helical ribbons filling the path.
  for i = 1, 7 do
    local u = travelT - (i - 1) * 0.08
    if u > 0.04 and u < 1.05 then
      local along = math.min(1, u)
      local spin = (age or 0) * 10 + i * 1.1
      local px = ox + dx * along + nx * math.sin(spin) * (3.2 + along * 2)
      local py = oy + dy * along + ny * math.sin(spin) * (3.2 + along * 2) * 0.45
          - math.sin(along * math.pi) * 2.2
      local a = (0.8 - i * 0.08) * fade * (1 - math.max(0, u - 0.88) / 0.17)
      drawWindSlash(g, px, py, ang + math.sin(spin) * 0.35,
        0.72 + (i % 3) * 0.12, c, a)
    end
  end
  -- Leading gust cone.
  if travelT > 0.06 and travelT < 0.98 then
    local tipX = ox + dx * travelT
    local tipY = oy + dy * travelT
    drawWindSlash(g, tipX, tipY, ang, 1.25, c, 0.95 * fade)
    drawWindSlash(g, tipX - fx * 4, tipY - fy * 4, ang, 0.95, c, 0.55 * fade)
    g.setColor(c[1], c[2], c[3], 0.18 * fade)
    g.ellipse("fill", tipX, tipY, 8, 3.4)
  end
  -- Leaf specks caught in the draft.
  for i = 1, 5 do
    local u = travelT - 0.05 - (i % 3) * 0.07
    if u > 0.04 and u < 0.95 then
      local spin = (age or 0) * 8 + i * 2
      local px = ox + dx * u + nx * math.cos(spin) * 5
      local py = oy + dy * u + math.sin(spin) * 2.4
      g.setColor(0.55, 0.72, 0.38, 0.55 * fade)
      if g.polygon then
        g.polygon("fill",
          px, py - 1.4,
          px + 1.6, py,
          px, py + 1.2,
          px - 1.2, py)
      else
        g.circle("fill", px, py, 1.1)
      end
    end
  end
  if landT > 0 then
    for i = 1, 4 do
      local r = 4 + landT * (8 + i * 3)
      g.setColor(c[1], c[2], c[3], (0.55 - i * 0.1) * fade * (1 - landT * 0.4))
      g.setLineWidth(1.6)
      g.ellipse("line", x, y + 1, r, r * 0.48)
    end
    for i = 1, 5 do
      local a = i * 1.256 + (age or 0) * 6
      drawWindSlash(g,
        x + math.cos(a) * (5 + landT * 6),
        y + math.sin(a) * (3 + landT * 3),
        a, 0.7, c, (0.7 - landT * 0.4) * fade)
    end
  end
end

--- Sand Attack: scuff at the caster's feet, then a grit cone into the face.
local function drawSandSpray(g, x, y, ox, oy, t, age, c)
  if type(x) ~= "number" or type(y) ~= "number"
      or type(ox) ~= "number" or type(oy) ~= "number" then
    return
  end
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local fx, fy = 1, 0
  local nx, ny = 0, 1
  if len > 0.1 then
    fx, fy = dx / len, dy / len
    nx, ny = -fy, fx
  end
  local cr, cg, cb = c[1] or 0.82, c[2] or 0.62, c[3] or 0.32
  local fade = 1
  if t > 0.82 then
    fade = 1 - (t - 0.82) / 0.18
  end
  local kick = math.min(1, t / 0.16)
  local travel = math.max(0, math.min(1, (t - 0.06) / 0.52))
  local face = math.max(0, (t - 0.48) / 0.52)

  -- Scuff / dust ring at the kicker's feet.
  g.setColor(cr, cg, cb, 0.28 * kick * fade)
  g.ellipse("fill", ox, oy + 5, 5 + kick * 7, 2.2 + kick * 1.6)
  g.setColor(0.42, 0.28, 0.12, 0.45 * kick * fade)
  g.setLineWidth(1)
  g.ellipse("line", ox, oy + 5, 4 + kick * 6, 1.8 + kick * 1.2)
  for i = 1, 6 do
    local a = (age or 0) * 8 + i * 1.1
    local rise = kick * (3 + i * 0.8) - math.sin(a) * 0.8
    g.setColor(cr * 0.85, cg * 0.8, cb * 0.7, (0.65 - i * 0.06) * kick * fade)
    g.circle("fill",
      ox + math.cos(a) * (2.5 + kick * 3),
      oy + 4 - rise,
      1.1 + (i % 3) * 0.4)
  end

  -- Widening grit cone along the path.
  local n = 16
  for i = 1, n do
    local u = travel - (i - 1) * 0.035
    if u > 0.02 and u < 1.08 then
      local along = math.min(1, u)
      local spread = 1.2 + along * 7.5
      local side = ((i % 2) * 2 - 1)
      local wobble = math.sin((age or 0) * 14 + i * 1.7) * spread * 0.55
      local loft = -along * 5 - math.sin(along * math.pi) * 2.4
          + math.sin((age or 0) * 11 + i) * 1.2
      local px = ox + dx * along + nx * (side * spread * 0.42 + wobble)
      local py = oy + dy * along + ny * wobble * 0.35 + loft
      local grain = 0.7 + (i % 4) * 0.45
      local a = (0.85 - along * 0.25) * fade * (u < 1 and 1 or (1.08 - u) / 0.08)
      g.setColor(cr, cg, cb, a)
      g.circle("fill", px, py, grain)
      if i % 3 == 0 then
        g.setColor(0.95, 0.86, 0.62, a * 0.7)
        g.circle("fill", px - 0.35, py - 0.4, grain * 0.4)
      elseif i % 3 == 1 then
        g.setColor(0.48, 0.32, 0.14, a * 0.8)
        g.circle("fill", px + 0.3, py + 0.2, grain * 0.55)
      end
    end
  end

  -- A few heavier pebbles in the stream.
  for i = 1, 5 do
    local u = travel - 0.04 - i * 0.07
    if u > 0.05 and u < 0.98 then
      local side = ((i % 2) * 2 - 1)
      local px = ox + dx * u + nx * side * (2 + u * 4)
      local py = oy + dy * u - 2 - math.sin(u * math.pi) * 3
      g.setColor(0.52, 0.36, 0.16, 0.9 * fade)
      g.circle("fill", px, py, 1.6 + (i % 2) * 0.4)
      g.setColor(0.72, 0.54, 0.28, 0.7 * fade)
      g.circle("fill", px - 0.4, py - 0.5, 0.7)
    end
  end

  -- Face puff: sand in the eyes.
  if face > 0.02 then
    local burst = math.min(1, face)
    g.setColor(cr, cg, cb, 0.32 * fade * (1 - burst * 0.35))
    g.ellipse("fill", x, y - 3, 7 + burst * 8, 4.2 + burst * 3)
    g.setColor(0.92, 0.82, 0.55, 0.22 * fade)
    g.ellipse("fill", x - 1, y - 5, 4 + burst * 3, 2.2)
    for i = 1, 8 do
      local a = i * 0.85 + (age or 0) * 6
      local dist = 2 + burst * (5 + i % 3)
      g.setColor(cr, cg, cb, (0.8 - burst * 0.4) * fade)
      g.circle("fill",
        x + math.cos(a) * dist,
        y - 3 + math.sin(a) * dist * 0.55 - burst * 2,
        1.15 + (i % 3) * 0.3)
    end
  end
end

local function drawMove(g, p, x, y)
  local c = p.color or { 0.92, 0.92, 1.00 }
  local glitz = p.glitz or "orb"
  local age = p.age or 0
  local trail = trailPoints(p, x, y, (glitz == "flame" or glitz == "bubble") and 8 or 3,
    (glitz == "flame" or glitz == "bubble") and 3.2 or 4)

  if glitz == "flame" then
    local heading = math.atan2(p.dirY or 0, p.dirX or 1) + math.pi * 0.5
    for i = #trail, 1, -1 do
      local tp = trail[i]
      local wobble = math.sin(age * 18 + i * 1.6) * 0.28
      drawFlameTongue(g, tp.x, tp.y - (i - 1) * 0.35,
        heading + wobble, 0.95 - (i - 1) * 0.08, 0.85 * tp.a)
    end
    drawFlameTongue(g, x, y, heading, 1.15, 0.95)
    for i = 1, 4 do
      local a = age * 14 + i * 2.1
      drawFlameTongue(g,
        x + math.cos(a) * (2.5 + i % 3) - (p.dirX or 0) * (i + 0.5),
        y + math.sin(a) * 1.6 - 1.5 - i * 0.3,
        heading + math.sin(a) * 0.4, 0.4, 0.7)
    end
    return
  end

  if glitz == "bubble" then
    for i = 1, #trail do
      local tp = trail[i]
      local bob = math.sin(age * 16 + i * 1.9) * 2.2
      local side = math.cos(age * 11 + i * 2.4) * 1.6
      local nx = -(p.dirY or 0)
      local ny = (p.dirX or 1)
      local r = 4.2 - (i - 1) * 0.28 + (i % 3) * 0.35
      local bx = tp.x + nx * side
      local by = tp.y + ny * side + bob * 0.35
      g.setColor(c[1], c[2], c[3], 0.22 * tp.a)
      g.circle("fill", bx, by, r)
      g.setColor(c[1], c[2], c[3], 0.55 * tp.a)
      g.circle("line", bx, by, r)
      g.setColor(1, 1, 1, 0.65 * tp.a)
      g.circle("fill", bx - r * 0.35, by - r * 0.35, math.max(0.6, r * 0.28))
    end
    -- Extra satellite bubbles around the tip.
    for i = 1, 4 do
      local a = age * 9 + i * 1.8
      local r = 1.6 + (i % 2) * 0.8
      local bx = x + math.cos(a) * (4 + i)
      local by = y + math.sin(a * 1.3) * (3 + i * 0.4)
      g.setColor(c[1], c[2], c[3], 0.5)
      g.circle("line", bx, by, r)
      g.setColor(1, 1, 1, 0.7)
      g.circle("fill", bx - 0.5, by - 0.5, 0.7)
    end
    g.setColor(c[1], c[2], c[3], 0.85)
    g.circle("fill", x, y, 3.8)
    g.setColor(1, 1, 1, 0.92)
    g.circle("fill", x - 1.2, y - 1.2, 1.3)
    return
  end

  if glitz == "leaf" then
    g.setColor(c[1], c[2], c[3], 0.35)
    g.setLineWidth(2)
    g.line(x - (p.dirX or 0) * 8, y - (p.dirY or 0) * 8, x, y)
    g.setColor(c[1], c[2], c[3], 0.9)
    g.polygon("fill",
      x + 4, y,
      x - 2, y - 3,
      x - 1, y,
      x - 2, y + 3)
    return
  end

  if glitz == "blob" then
    for i = 1, #trail do
      local tp = trail[i]
      g.setColor(c[1], c[2], c[3], 0.4 * tp.a)
      g.circle("fill", tp.x + math.sin(i * 2) , tp.y, 3.2 - i * 0.4)
    end
    g.setColor(c[1] * 0.7, c[2] * 0.5, c[3], 0.95)
    g.circle("fill", x, y, 4)
    return
  end

  if glitz == "star" or glitz == "tri" then
    local n = glitz == "tri" and 3 or 4
    for i = 1, n do
      local a = (p.age or 0) * 10 + i * (math.pi * 2 / n)
      local rx = x + math.cos(a) * 5
      local ry = y + math.sin(a) * 5
      g.setColor(c[1], c[2], c[3], 0.85)
      g.circle("fill", rx, ry, 2.2)
      g.setColor(1, 1, 1, 0.9)
      g.circle("fill", rx, ry, 1)
    end
    return
  end

  if glitz == "rock" then
    drawRockChunk(g, x, y, (p.age or 0) * 11, 1.08, c, 0.95, 1)
    return
  end

  -- Default orb + short trail.
  local trailX = x - (p.dirX or 0) * 6
  local trailY = y - (p.dirY or 0) * 6
  g.setColor(c[1], c[2], c[3], 0.28)
  g.setLineWidth(3)
  g.line(trailX, trailY, x, y)
  g.setColor(c[1], c[2], c[3], 0.72)
  g.circle("fill", x, y, 4)
  g.setColor(1, 1, 1, 0.95)
  g.circle("fill", x, y, 2)
end

local function drawIceCrystal(g, px, py, rot, scale, c, alpha)
  scale = scale or 1
  alpha = alpha or 1
  local ca, sa = math.cos(rot), math.sin(rot)
  local function pt(lx, ly)
    return px + (lx * ca - ly * sa) * scale,
      py + (lx * sa + ly * ca) * scale
  end
  local ax, ay = pt(0, -2.6)
  local bx, by = pt(1.05, 0)
  local cx, cy = pt(0, 2.6)
  local dx, dy = pt(-1.05, 0)
  g.setColor(c[1], c[2], c[3], 0.9 * alpha)
  g.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
  local hx, hy = pt(0, -1.15)
  local ix, iy = pt(0.38, 0)
  local jx, jy = pt(0, 0.55)
  local kx, ky = pt(-0.22, -0.12)
  g.setColor(1, 1, 1, 0.75 * alpha)
  g.polygon("fill", hx, hy, ix, iy, jx, jy, kx, ky)
end

local function drawPunchBurst(g, x, y, t, fade, c)
  local r = 3 + t * 7
  g.setColor(c[1], c[2], c[3], 0.7 * fade)
  g.setLineWidth(2)
  g.circle("line", x, y, r)
  g.setColor(1, 1, 1, 0.9 * fade)
  g.circle("fill", x - 1, y - 1, 2.4)
  g.setColor(c[1], c[2], c[3], fade)
  g.setLineWidth(2)
  g.line(x - 6, y + 4, x + 2, y - 5)
end

local function drawContact(g, p, x, y, t)
  local c = p.color or { 0.92, 0.92, 1.00 }
  local glitz = p.glitz or "slash"
  local fade = 1 - t

  if glitz == "bite" then
    local open = 4 + t * 6
    g.setColor(c[1], c[2], c[3], fade)
    g.setLineWidth(2)
    g.arc("line", x, y - 1, open, math.pi * 0.15, math.pi * 0.85)
    g.arc("line", x, y + 1, open, math.pi * 1.15, math.pi * 1.85)
    return
  end

  if glitz == "impact" then
    local r = 4 + t * 10
    g.setColor(c[1], c[2], c[3], 0.55 * fade)
    g.circle("line", x, y, r)
    g.setColor(1, 1, 1, 0.85 * fade)
    g.circle("fill", x, y, 2)
    for i = 1, 4 do
      local a = i * math.pi * 0.5 + t
      g.setColor(c[1], c[2], c[3], fade)
      g.line(x + math.cos(a) * 3, y + math.sin(a) * 3,
        x + math.cos(a) * (r + 2), y + math.sin(a) * (r + 2))
    end
    return
  end

  if glitz == "dash" then
    local dx = p.dirX or 1
    local dy = p.dirY or 0
    g.setColor(1, 1, 1, 0.55 * fade)
    g.circle("fill", x, y, 2.4 + t * 2)
    g.setColor(c[1], c[2], c[3], fade)
    g.setLineWidth(2.6)
    g.line(x - dx * 12, y - dy * 12, x + dx * 7, y + dy * 7)
    g.setLineWidth(1.3)
    g.line(x - dx * 9 + dy * 3, y - dy * 9 - dx * 2, x + dx * 5, y + dy * 5)
    g.line(x - dx * 8 - dy * 3, y - dy * 8 + dx * 2, x + dx * 4, y + dy * 4)
    return
  end

  if glitz == "wing" then
    local reach = 5 + t * 9
    local ang = -0.45
    drawWindSlash(g, x, y, ang, 1.15 + t * 0.35, c, fade)
    drawWindSlash(g, x + 2, y - 1, ang + 0.55, 0.85, c, fade * 0.7)
    g.setColor(1, 1, 1, 0.75 * fade)
    g.setLineWidth(2)
    g.line(x - reach * 0.3, y + 3, x + reach * 0.55, y - 5)
    g.setColor(c[1], c[2], c[3], fade)
    g.circle("fill", x + reach * 0.2, y - 2, 1.6)
    return
  end

  if glitz == "pierce" then
    g.setColor(c[1], c[2], c[3], fade)
    g.setLineWidth(2)
    g.line(x - 8, y + 3, x + 8, y - 3)
    g.setColor(1, 1, 1, 0.85 * fade)
    g.circle("fill", x + 6, y - 2, 1.5)
    return
  end

  if glitz == "punch" then
    drawPunchBurst(g, x, y, t, fade, c)
    return
  end

  if glitz == "icepunch" then
    drawPunchBurst(g, x, y, t, fade, c)
    for i = 1, 6 do
      local a = i * 1.047 + t * 2.4
      local dist = 4 + t * 8
      drawIceCrystal(g,
        x + math.cos(a) * dist,
        y + math.sin(a) * dist * 0.6 - t * 2,
        a + t * 3, 0.85 + (i % 2) * 0.2, c, fade)
    end
    g.setColor(0.78, 0.96, 1.00, 0.35 * fade)
    g.circle("fill", x, y, 5 + t * 4)
    return
  end

  if glitz == "firepunch" then
    drawPunchBurst(g, x, y, t, fade, c)
    for i = 1, 6 do
      local a = i * 1.047 + t * 3
      local dist = 3 + t * 7
      drawFlameTongue(g,
        x + math.cos(a) * dist,
        y + math.sin(a) * dist * 0.6 - t * 2,
        a + math.pi * 0.5, 0.78 + (i % 2) * 0.12, fade)
    end
    drawFlameTongue(g, x, y - 2, 0, 1.15, fade)
    return
  end

  if glitz == "thunderpunch" then
    drawPunchBurst(g, x, y, t, fade, c)
    local age = p.age or t
    for i = 1, 3 do
      local a = i * (math.pi * 2 / 3) + t * 4
      local dist = 6 + t * 8
      drawLightningBolt(g, x, y,
        x + math.cos(a) * dist,
        y + math.sin(a) * dist * 0.55,
        age + i * 0.2, c, {
          fade = fade,
          segs = 4,
          amp = 3.2,
          glow = 3.4,
          mid = 1.8,
          core = 1.05,
          forkLen = 3.2,
          coreColor = { 1, 1, 0.92 },
        })
    end
    g.setColor(1, 1, 0.7, 0.45 * fade)
    g.circle("fill", x, y, 3.5)
    return
  end

  if glitz == "toss" then
    local lift = 0
    if t < 0.18 then
      lift = 0
      g.setColor(c[1], c[2], c[3], fade)
      g.setLineWidth(2)
      g.circle("line", x, y, 4 + t * 8)
      for i = 1, 4 do
        local a = i * 1.57 + t * 6
        g.setColor(1, 1, 1, 0.7 * fade)
        g.circle("fill", x + math.cos(a) * 5, y + math.sin(a) * 3, 1.2)
      end
    elseif t < 0.52 then
      local u = (t - 0.18) / 0.34
      lift = u * u * (3 - 2 * u) * 32
    elseif t < 0.60 then
      lift = 32 + math.sin((t - 0.52) * 40) * 1.2
    else
      local u = math.min(1, (t - 0.60) / 0.18)
      lift = (1 - u * u) * 32
    end
    local hold = 1
    if t > 0.88 then
      hold = 1 - (t - 0.88) / 0.12
    end
    if t < 0.78 then
      drawMonSilhouette(g, x, y - lift, 1.05, c, hold)
      g.setColor(c[1], c[2], c[3], 0.22 * hold)
      g.ellipse("fill", x, y + 4, 6 + (1 - lift / 32) * 3, 2.2)
    end
    if t > 0.70 then
      local slam = math.min(1, (t - 0.70) / 0.30)
      g.setColor(c[1], c[2], c[3], 0.4 * (1 - slam * 0.5) * hold)
      g.ellipse("fill", x, y + 3, 8 + slam * 10, 3.4 + slam * 2)
      g.setColor(1, 1, 1, 0.7 * (1 - slam) * hold)
      g.circle("fill", x, y, 2.6)
      for i = 1, 6 do
        local a = i * (math.pi * 2 / 6)
        local dist = 4 + slam * 10
        g.setColor(c[1], c[2], c[3], (0.85 - slam * 0.5) * hold)
        g.setLineWidth(1.8)
        g.line(x, y,
          x + math.cos(a) * dist,
          y + math.sin(a) * dist * 0.45)
      end
      for i = 1, 5 do
        local a = i * 1.256 + slam * 2
        g.setColor(0.72, 0.58, 0.32, (0.6 - slam * 0.4) * hold)
        g.circle("fill",
          x + math.cos(a) * (5 + slam * 6),
          y + 3 + math.sin(a) * 2,
          1.4)
      end
    end
    return
  end

  if glitz == "kick" then
    g.setColor(c[1], c[2], c[3], fade)
    g.setLineWidth(2.4)
    g.line(x - 7, y + 6, x + 7, y - 5)
    g.setLineWidth(1.4)
    g.line(x - 3, y + 7, x + 8, y - 1)
    g.setColor(1, 1, 1, 0.8 * fade)
    g.circle("fill", x + 6, y - 4, 1.6)
    return
  end

  if glitz == "slap" then
    local reach = 4 + t * 7
    g.setColor(c[1], c[2], c[3], fade)
    g.setLineWidth(2.2)
    g.line(x - reach, y - 1, x + reach, y + 2)
    g.setColor(1, 1, 1, 0.75 * fade)
    g.circle("fill", x + reach * 0.4, y, 1.8)
    return
  end

  if glitz == "sting" then
    g.setColor(c[1], c[2], c[3], fade)
    g.setLineWidth(1.6)
    g.line(x - 7, y + 4, x + 6, y - 5)
    g.polygon("fill", x + 5, y - 6, x + 9, y - 3, x + 4, y - 2)
    g.setColor(1, 1, 1, 0.8 * fade)
    g.circle("fill", x + 6, y - 4, 1.1)
    return
  end

  if glitz == "wrap" then
    local r = 3 + t * 7
    g.setColor(c[1], c[2], c[3], 0.8 * fade)
    g.setLineWidth(1.8)
    g.arc("line", x, y, r, t * 2, t * 2 + 4.2)
    g.arc("line", x, y, r * 0.65, t * 2 + 1.2, t * 2 + 4.8)
    return
  end

  if glitz == "pinch" then
    local open = 3 + (1 - t) * 5
    g.setColor(c[1], c[2], c[3], fade)
    g.setLineWidth(2)
    g.line(x - open, y - 5, x, y + 3)
    g.line(x + open, y - 5, x, y + 3)
    g.setColor(1, 1, 1, 0.75 * fade)
    g.circle("fill", x, y + 2, 1.4)
    return
  end

  if glitz == "coin" then
    for i = 1, 4 do
      local a = i * 1.7 + t * 3
      local dist = 3 + t * 8
      local px = x + math.cos(a) * dist
      local py = y + math.sin(a) * dist * 0.7 - t * 3
      g.setColor(1.00, 0.84, 0.22, fade)
      g.rectangle("fill", px - 1.4, py - 1.4, 2.8, 2.8)
      g.setColor(1, 1, 0.75, 0.8 * fade)
      g.rectangle("fill", px - 0.6, py - 0.6, 1.2, 1.2)
    end
    return
  end

  if glitz == "flame" then
    for i = 1, 5 do
      local a = i * 1.256 + t * 3
      local dist = 2 + t * 7
      drawFlameTongue(g,
        x + math.cos(a) * dist,
        y + math.sin(a) * dist * 0.6 - t * 2,
        a + math.pi * 0.5, 0.7, fade)
    end
    drawFlameTongue(g, x, y - 1, 0, 1.05, fade)
    return
  end

  if glitz == "bubble" or glitz == "blob"
      or glitz == "frost" or glitz == "bolt" or glitz == "ghost"
      or glitz == "leaf" or glitz == "psy" then
    local reach = 3 + t * 8
    g.setColor(c[1], c[2], c[3], fade)
    g.circle("fill", x, y, 2 + (1 - t) * 3)
    g.setLineWidth(2)
    g.line(x - reach, y, x + reach, y)
    g.line(x, y - reach, x, y + reach)
    return
  end

  -- Default slash X.
  local reach = 3 + t * 9
  g.setColor(c[1], c[2], c[3], fade)
  g.setLineWidth(2)
  g.line(x - reach, y + reach, x + reach, y - reach)
  g.line(x - reach * 0.6, y - reach, x + reach * 0.6, y + reach)
end

-- Compact spark burst on weak hits (contact flash is already gone by then).
local function drawLightHit(g, p, x, y, t)
  local c = p.color or { 0.92, 0.92, 1.00 }
  local fade = 1 - t
  g.setColor(1, 1, 1, 0.75 * fade)
  g.circle("fill", x, y, 1.6 * (1 - t * 0.4))
  for i = 1, 5 do
    local a = i * 1.2566 + t * 2.4
    local dist = 2.2 + t * 8
    local px = x + math.cos(a) * dist
    local py = y + math.sin(a) * dist * 0.72 - t * 2
    g.setColor(c[1], c[2], c[3], 0.85 * fade)
    g.circle("fill", px, py, 1.3)
    g.setColor(1, 1, 1, 0.55 * fade)
    g.circle("fill", px - 0.3, py - 0.3, 0.55)
  end
  drawContact(g, p, x, y, math.min(1, t * 1.15))
end

local function polyUnpack(pts)
  local unpackFn = table.unpack or unpack
  return unpackFn(pts)
end

--- Comic-book crit starburst. Same jagged silhouette; fill/accents follow type.
local CRIT_PALETTES = {
  NORMAL = {
    rim = { 0.82, 0.08, 0.06 },
    mid = { 1.00, 0.46, 0.08 },
    core = { 1.00, 0.92, 0.22 },
    shard = { 1.00, 0.38, 0.08 },
    accent = "comic",
  },
  FIRE = {
    rim = { 0.86, 0.10, 0.04 },
    mid = { 1.00, 0.42, 0.08 },
    core = { 1.00, 0.90, 0.28 },
    shard = { 1.00, 0.34, 0.08 },
    accent = "flame",
  },
  ICE = {
    rim = { 0.22, 0.52, 0.92 },
    mid = { 0.55, 0.88, 1.00 },
    core = { 0.96, 0.99, 1.00 },
    shard = { 0.78, 0.94, 1.00 },
    accent = "ice",
  },
  ELECTRIC = {
    rim = { 0.90, 0.58, 0.04 },
    mid = { 1.00, 0.88, 0.18 },
    core = { 1.00, 1.00, 0.92 },
    shard = { 1.00, 0.92, 0.35 },
    accent = "bolt",
  },
  PSYCHIC = {
    rim = { 0.70, 0.10, 0.58 },
    mid = { 0.96, 0.40, 0.86 },
    core = { 1.00, 0.86, 1.00 },
    shard = { 0.94, 0.55, 0.92 },
    accent = "psy",
  },
  DARK = {
    rim = { 0.10, 0.04, 0.08 },
    mid = { 0.28, 0.10, 0.24 },
    core = { 0.58, 0.36, 0.70 },
    shard = { 0.22, 0.08, 0.20 },
    accent = "ink",
  },
  GHOST = {
    rim = { 0.28, 0.12, 0.46 },
    mid = { 0.52, 0.32, 0.72 },
    core = { 0.86, 0.78, 1.00 },
    shard = { 0.42, 0.22, 0.62 },
    accent = "ink",
  },
  WATER = {
    rim = { 0.08, 0.32, 0.78 },
    mid = { 0.22, 0.62, 1.00 },
    core = { 0.82, 0.94, 1.00 },
    shard = { 0.40, 0.72, 1.00 },
    accent = "comic",
  },
  GRASS = {
    rim = { 0.12, 0.48, 0.14 },
    mid = { 0.38, 0.82, 0.28 },
    core = { 0.82, 1.00, 0.45 },
    shard = { 0.42, 0.78, 0.22 },
    accent = "comic",
  },
  POISON = {
    rim = { 0.42, 0.08, 0.58 },
    mid = { 0.72, 0.28, 0.82 },
    core = { 0.94, 0.72, 1.00 },
    shard = { 0.62, 0.22, 0.78 },
    accent = "ink",
  },
  FIGHTING = {
    rim = { 0.62, 0.10, 0.10 },
    mid = { 0.88, 0.28, 0.16 },
    core = { 1.00, 0.78, 0.42 },
    shard = { 0.82, 0.22, 0.12 },
    accent = "comic",
  },
  GROUND = {
    rim = { 0.48, 0.28, 0.10 },
    mid = { 0.78, 0.56, 0.28 },
    core = { 0.96, 0.86, 0.52 },
    shard = { 0.68, 0.48, 0.24 },
    accent = "comic",
  },
  ROCK = {
    rim = { 0.42, 0.34, 0.22 },
    mid = { 0.70, 0.60, 0.38 },
    core = { 0.92, 0.86, 0.62 },
    shard = { 0.62, 0.52, 0.32 },
    accent = "comic",
  },
  FLYING = {
    rim = { 0.32, 0.48, 0.82 },
    mid = { 0.62, 0.74, 0.96 },
    core = { 0.94, 0.96, 1.00 },
    shard = { 0.70, 0.82, 1.00 },
    accent = "comic",
  },
  BUG = {
    rim = { 0.38, 0.48, 0.08 },
    mid = { 0.66, 0.78, 0.18 },
    core = { 0.92, 1.00, 0.45 },
    shard = { 0.58, 0.72, 0.16 },
    accent = "comic",
  },
  DRAGON = {
    rim = { 0.22, 0.12, 0.62 },
    mid = { 0.48, 0.36, 0.90 },
    core = { 0.86, 0.78, 1.00 },
    shard = { 0.40, 0.28, 0.82 },
    accent = "psy",
  },
  STEEL = {
    rim = { 0.38, 0.42, 0.48 },
    mid = { 0.72, 0.76, 0.82 },
    core = { 0.96, 0.97, 1.00 },
    shard = { 0.62, 0.66, 0.72 },
    accent = "comic",
  },
  FAIRY = {
    rim = { 0.78, 0.28, 0.52 },
    mid = { 0.96, 0.58, 0.78 },
    core = { 1.00, 0.90, 0.96 },
    shard = { 0.94, 0.62, 0.80 },
    accent = "psy",
  },
}

local function drawCritBurst(g, p, x, y, t)
  local fade = 1
  if t > 0.62 then
    fade = 1 - (t - 0.62) / 0.38
  end
  local pop = 0.55
  if t < 0.16 then
    local u = t / 0.16
    pop = 0.35 + u * u * (3 - 2 * u) * 0.92
  else
    pop = 1.27 - math.min(0.22, (t - 0.16) * 0.55)
  end
  local pal = CRIT_PALETTES[tostring(p.glitz or "NORMAL"):upper()]
      or CRIT_PALETTES.NORMAL
  local rot = (p.seed or 0.4) + t * 0.35
  local n = 10
  local function star(scale, rLong, rShort)
    local pts = {}
    for i = 0, n - 1 do
      local a = rot + i * (math.pi * 2 / n) - math.pi * 0.5
      local jagged = 0.86 + 0.14 * math.sin(i * 2.4 + rot * 2)
      local r = ((i % 2 == 0) and rLong or rShort) * scale * jagged
      pts[#pts + 1] = x + math.cos(a) * r
      pts[#pts + 1] = y + math.sin(a) * r * 0.92
    end
    return pts
  end
  local rim, mid, core, shard = pal.rim, pal.mid, pal.core, pal.shard
  if not g.polygon then
    g.setColor(mid[1], mid[2], mid[3], 0.7 * fade)
    g.circle("fill", x, y, 10 * pop)
    g.setColor(core[1], core[2], core[3], 0.9 * fade)
    g.circle("fill", x, y, 4.5 * pop)
    return
  end
  local shadow = star(pop, 17.5, 8.2)
  for i = 1, #shadow, 2 do
    shadow[i] = shadow[i] - 1.6
    shadow[i + 1] = shadow[i + 1] + 1.8
  end
  g.setColor(0.12, 0.10, 0.10, 0.28 * fade)
  g.polygon("fill", polyUnpack(shadow))
  g.setColor(rim[1], rim[2], rim[3], 0.96 * fade)
  g.polygon("fill", polyUnpack(star(pop, 16.8, 7.6)))
  g.setColor(mid[1], mid[2], mid[3], 0.96 * fade)
  g.polygon("fill", polyUnpack(star(pop * 0.78, 16.8, 7.6)))
  g.setColor(core[1], core[2], core[3], 0.98 * fade)
  g.polygon("fill", polyUnpack(star(pop * 0.46, 16.8, 7.6)))
  g.setColor(1, 1, 0.92, 0.82 * fade)
  g.circle("fill", x - 0.6, y - 0.8, 2.6 * pop)

  local accent = pal.accent or "comic"
  local age = p.age or t
  if accent == "ice" then
    for i = 1, 6 do
      local a = rot + i * 1.05
      local dist = (7 + i) * pop + t * 5
      drawIceCrystal(g,
        x + math.cos(a) * dist,
        y + math.sin(a) * dist * 0.72,
        a + t * 4, 0.7 + (i % 2) * 0.18, shard, (0.85 - t * 0.35) * fade)
    end
  elseif accent == "bolt" then
    for i = 1, 4 do
      local a = rot + i * (math.pi * 0.5)
      local dist = 12 * pop + t * 4
      drawLightningBolt(g, x, y,
        x + math.cos(a) * dist,
        y + math.sin(a) * dist * 0.7,
        age + i * 0.15, mid, {
          fade = fade,
          segs = 4,
          amp = 2.8,
          glow = 3.2,
          mid = 1.6,
          core = 1.0,
          forkLen = 3.4,
          coreColor = core,
        })
    end
  elseif accent == "psy" then
    for i = 1, 3 do
      local u = i / 3
      g.setColor(mid[1], mid[2], mid[3], (0.55 - u * 0.15) * fade)
      g.setLineWidth(1.6)
      g.ellipse("line", x, y - 1, (6 + u * 8) * pop, (3.2 + u * 4) * pop)
    end
    for i = 1, 5 do
      local a = rot * 2 + i * 1.256
      g.setColor(core[1], core[2], core[3], 0.7 * fade)
      g.circle("fill",
        x + math.cos(a) * (5 + t * 6) * pop,
        y + math.sin(a) * (5 + t * 6) * pop * 0.55,
        1.2)
    end
  elseif accent == "ink" then
    g.setColor(rim[1], rim[2], rim[3], 0.42 * fade)
    g.ellipse("fill", x + 1, y + 2, 9 * pop, 6 * pop)
    for i = 1, 5 do
      local a = rot + i * 1.2
      local dist = 4 + t * (6 + i)
      g.setColor(mid[1], mid[2], mid[3], (0.65 - t * 0.3) * fade)
      g.circle("fill",
        x + math.cos(a) * dist * 0.7,
        y + math.sin(a) * dist * 0.45 + t * 3,
        1.8 + (i % 2) * 0.6)
    end
  elseif accent == "flame" then
    for i = 1, 5 do
      local a = rot + i * 1.256
      drawFlameTongue(g,
        x + math.cos(a) * 6 * pop,
        y + math.sin(a) * 4.5 * pop,
        a + math.pi * 0.5, 0.7, fade)
    end
  else
    for i = 1, 6 do
      local a = rot + i * 1.05
      local dist = (8 + i) * pop + t * 6
      local px = x + math.cos(a) * dist
      local py = y + math.sin(a) * dist * 0.72
      g.setColor(shard[1], shard[2], shard[3], (0.7 - t * 0.4) * fade)
      local s = 1.6 + (i % 2) * 0.5
      g.polygon("fill",
        px, py - s,
        px + s * 0.55, py,
        px, py + s * 0.45,
        px - s * 0.55, py)
    end
  end
end

--- Speed-line smear caster → foe (Quick Attack / Extreme Speed).
local function drawDashSmear(g, x, y, ox, oy, t, age, c, glitz)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local fx, fy = 1, 0
  local nx, ny = 0, 1
  if len > 0.1 then
    fx, fy = dx / len, dy / len
    nx, ny = -fy, fx
  end
  local fade = 1
  if t > 0.68 then
    fade = 1 - (t - 0.68) / 0.32
  end
  local extreme = glitz == "extreme"
  g.setColor(1, 1, 1, 0.28 * fade)
  g.setLineWidth(extreme and 5.5 or 4.2)
  g.line(ox, oy, x, y)
  g.setColor(c[1], c[2], c[3], 0.8 * fade)
  g.setLineWidth(extreme and 2.2 or 1.6)
  g.line(ox, oy, x, y)
  local n = extreme and 7 or 5
  for i = 1, n do
    local along = 0.12 + (i - 1) * (0.72 / n)
    local px = ox + dx * along
    local py = oy + dy * along
    local side = ((i % 2) * 2 - 1) * (2.0 + i * 0.4)
    local lx = px + nx * side - fx * 7
    local ly = py + ny * side * 0.45 - fy * 7
    local reach = 7 + i * 1.2
    g.setColor(1, 1, 1, (0.58 - i * 0.05) * fade)
    g.setLineWidth(1.3)
    g.line(lx, ly, lx + fx * reach, ly + fy * reach)
  end
  for i = 1, 3 do
    local u = (i / 4) * math.min(1, t * 1.35 + 0.08)
    local px = ox + dx * u - fx * (i * 2)
    local py = oy + dy * u
    drawMonSilhouette(g, px, py, 0.78 - i * 0.1, c, 0.32 * fade * (1 - u * 0.35))
  end
  g.setColor(1, 1, 1, 0.55 * fade)
  g.circle("fill", x - fx * 2, y - fy * 2, extreme and 2.4 or 1.8)
end

--- Kick-up debris from the tile under the struck mon (grass / snow / water / …).
local function drawGroundKick(g, p, x, y, t, c, glitz)
  local fade = 1
  if t > 0.72 then
    fade = 1 - (t - 0.72) / 0.28
  end
  local age = p.age or 0
  local dx = p.dirX or 1
  local dy = p.dirY or 0
  local nx, ny = -dy, dx
  glitz = glitz or "dust"
  g.setColor(c[1], c[2], c[3], 0.22 * fade)
  g.ellipse("fill", x, y + 1, 6 + t * 5, 2.2 + t * 1.2)

  if glitz == "grass" then
    for i = 1, 8 do
      local u = math.min(1, t * 1.35 + (i - 1) * 0.04)
      local side = ((i % 2) * 2 - 1)
      local px = x + dx * u * (5 + i) + nx * side * (2 + (i % 3))
      local py = y - math.sin(u * math.pi) * (5 + i * 0.4) + dy * u * 2
      drawLeafBlade(g, px, py, age * 10 + i, 0.52 + (i % 3) * 0.08, c,
        (0.9 - u * 0.35) * fade)
    end
    return
  end

  if glitz == "water" then
    for i = 1, 8 do
      local u = math.min(1, t * 1.4 + (i % 4) * 0.05)
      local side = ((i % 2) * 2 - 1)
      local px = x + dx * u * (4 + i) + nx * side * (1.6 + i * 0.35)
      local py = y - math.sin(u * math.pi) * (6 + i * 0.5)
      local r = 1.5 + (i % 3) * 0.45
      g.setColor(c[1], c[2], c[3], (0.7 - u * 0.3) * fade)
      g.circle("fill", px, py, r)
      g.setColor(1, 1, 1, 0.55 * fade * (1 - u))
      g.circle("fill", px - r * 0.3, py - r * 0.35, r * 0.35)
    end
    g.setColor(0.55, 0.82, 1.00, 0.35 * fade)
    g.ellipse("fill", x, y + 1, 7 + t * 6, 2.4)
    return
  end

  if glitz == "snow" then
    for i = 1, 8 do
      local u = math.min(1, t * 1.3 + (i - 1) * 0.04)
      local side = ((i % 2) * 2 - 1)
      local px = x + dx * u * (4 + i) + nx * side * (2 + i * 0.3)
      local py = y - math.sin(u * math.pi) * (5 + i * 0.35) - u * 2
      drawIceCrystal(g, px, py, age * 8 + i, 0.7 + (i % 2) * 0.18, c,
        (0.9 - u * 0.3) * fade)
    end
    g.setColor(0.92, 0.96, 1.00, 0.3 * fade)
    g.ellipse("fill", x, y + 1, 6 + t * 4, 2)
    return
  end

  if glitz == "cave" then
    for i = 1, 7 do
      local u = math.min(1, t * 1.25 + (i % 3) * 0.06)
      local side = ((i % 2) * 2 - 1)
      local px = x + dx * u * (4 + i) + nx * side * (1.4 + i * 0.4)
      local py = y - math.sin(u * math.pi) * (3 + i * 0.3)
      local r = 1.3 + (i % 3) * 0.5
      g.setColor(c[1], c[2], c[3], (0.75 - u * 0.3) * fade)
      g.circle("fill", px, py, r)
      g.setColor(0.55, 0.42, 0.28, 0.4 * fade)
      g.circle("fill", px - 0.3, py - 0.3, r * 0.4)
    end
    return
  end

  if glitz == "sand" then
    for i = 1, 9 do
      local a = i * 0.7 + t * 2
      local dist = 3 + t * (7 + i % 3)
      local px = x + math.cos(a) * dist * 0.7 + dx * t * 4
      local py = y + math.sin(a) * dist * 0.35 - t * 3
      g.setColor(c[1], c[2], c[3], (0.7 - t * 0.35) * fade)
      g.circle("fill", px, py, 1.2 + (i % 2) * 0.4)
    end
    return
  end

  if glitz == "spark" then
    for i = 1, 6 do
      local a = i * 1.047 + t * 4
      local dist = 3 + t * 8
      g.setColor(1.00, 0.88, 0.35, (0.8 - t * 0.4) * fade)
      g.setLineWidth(1.4)
      g.line(x, y,
        x + math.cos(a) * dist,
        y + math.sin(a) * dist * 0.5 - t * 2)
      g.setColor(1, 1, 0.85, 0.7 * fade)
      g.circle("fill", x + math.cos(a) * dist * 0.6, y - 1, 0.9)
    end
    return
  end

  -- Dust / dirt fallback.
  for i = 1, 6 do
    local a = i * 1.05 + t * 1.6
    local dist = 3 + t * 8
    local px = x + math.cos(a) * dist * 0.65 + dx * t * 3
    local py = y - t * (5 + i % 3) + math.sin(a) * 1.4
    g.setColor(c[1], c[2], c[3], (0.6 - t * 0.3) * fade)
    g.circle("fill", px, py, 1.8 - t * 0.8)
    g.setColor(1, 1, 1, 0.2 * fade)
    g.circle("fill", px - 0.3, py - 0.4, 0.6)
  end
end


local STYLE_PAINTERS = {}

function Projectiles.registerStyle(name, fn)
  if type(name) == "string" and type(fn) == "function" then
    STYLE_PAINTERS[name] = fn
  end
end

Projectiles.registerStyle("beam", function(g, p, x, y, ox, oy, t, c, glitz)
    if glitz == "hyper" then
      drawHyperBeam(g, x, y, ox, oy, t, p.age, c)
      return
    end
    if glitz == "psy" then
      drawPsybeam(g, x, y, ox, oy, t, p.age, c)
      return
    end
    local thick = (glitz == "thick") and 7 or 5
    if glitz == "bolt" or glitz == "icebolt" then
      local ice = glitz == "icebolt"
      drawLightningBolt(g, ox, oy, x, y, p.age, c, {
        fade = 1 - t * 0.25,
        segs = 9,
        amp = ice and 4.4 or 6.2,
        glow = ice and 5.0 or 5.5,
        mid = ice and 2.6 or 2.8,
        core = ice and 1.5 or 1.35,
        forkLen = ice and 4.8 or 5.5,
        coreColor = ice and { 0.86, 0.97, 1.00 } or { 1, 1, 0.92 },
        forkCore = ice and { 0.78, 0.94, 1.00 } or { 1, 1, 0.9 },
        midColor = ice and { 0.55, 0.88, 1.00 } or nil,
      })
      -- Secondary delayed fork for a multi-bolt feel.
      local midAge = (p.age or 0) + 0.37
      local mx = ox + (x - ox) * 0.62
      local my = oy + (y - oy) * 0.62
      drawLightningBolt(g, ox, oy, mx + math.sin(midAge * 12) * 4,
        my + math.cos(midAge * 10) * 3, midAge, c, {
          fade = 0.55 * (1 - t),
          segs = 5,
          amp = ice and 3.2 or 4,
          glow = ice and 3.2 or 3.5,
          mid = 1.8,
          core = ice and 1.15 or 1,
          forks = false,
          coreColor = ice and { 0.86, 0.97, 1.00 } or { 1, 1, 0.92 },
          midColor = ice and { 0.55, 0.88, 1.00 } or nil,
        })
      if ice then
        -- Crisp ice shards along the bolt.
        for i = 1, 5 do
          local u = i / 6
          local px = ox + (x - ox) * u
          local py = oy + (y - oy) * u
          local rot = u * 1.4 + (p.age or 0) * 6
          local scale = 0.7 + (i % 2) * 0.25
          local ca, sa = math.cos(rot), math.sin(rot)
          local function pt(lx, ly)
            return px + (lx * ca - ly * sa) * scale,
              py + (lx * sa + ly * ca) * scale
          end
          local fadeIce = (1 - t * 0.2)
          -- Unpack both returns from each pt() — Lua only expands the last
          -- call in an arg list, so inlining pt() into polygon() yields an
          -- odd vertex count and Love errors every overlay frame.
          local ax, ay = pt(0, -2.4)
          local bx, by = pt(0.9, 0)
          local cx, cy = pt(0, 2.4)
          local dx, dy = pt(-0.9, 0)
          g.setColor(c[1], c[2], c[3], 0.85 * fadeIce)
          g.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
          local hx, hy = pt(0, -1.1)
          local ix, iy = pt(0.35, 0)
          local jx, jy = pt(0, 0.5)
          local kx, ky = pt(-0.2, -0.15)
          g.setColor(1, 1, 1, 0.7 * fadeIce)
          g.polygon("fill", hx, hy, ix, iy, jx, jy, kx, ky)
        end
      end
    else
      g.setColor(c[1], c[2], c[3], 0.34)
      g.setLineWidth(thick)
      g.line(ox, oy, x, y)
      g.setColor(1, 1, 1, 0.9)
      g.setLineWidth(2)
      g.line(ox, oy, x, y)
      if glitz == "frost" or glitz == "ghost" then
        for i = 1, 3 do
          local u = i / 4
          local px = ox + (x - ox) * u
          local py = oy + (y - oy) * u
          g.setColor(c[1], c[2], c[3], 0.7 * (1 - t))
          g.circle("fill", px, py, 2)
        end
      end
    end
end)
Projectiles.registerStyle("shadow", function(g, p, x, y, ox, oy, t, c, glitz)
    -- Night Shade: slithering shadow ribbon → smoke burst on arrival.
    -- x,y is the traveling tip (interpolated); ox,oy stays at the caster.
    local age = p.age or 0
    local tipX, tipY = x, y
    local ribbon = shadowRibbon(ox, oy, tipX, tipY, age, 16)
    for i = 1, #ribbon do
      local pt = ribbon[i]
      local u = pt[3] or ((i - 1) / math.max(1, #ribbon - 1))
      local r = 2.2 + u * 4.4 + math.sin(age * 14 + i) * 0.7
      local a = (0.35 + 0.6 * u) * (0.85 + 0.15 * math.sin(age * 9 + i))
      -- Soft violet outer haze (readable on dark maps).
      g.setColor(0.42, 0.18, 0.62, a * 0.45)
      g.circle("fill", pt[1], pt[2], r + 3.2)
      -- Dark core.
      g.setColor(c[1], c[2], c[3], a)
      g.circle("fill", pt[1], pt[2], r)
      if i > 1 then
        local prev = ribbon[i - 1]
        g.setColor(0.28, 0.1, 0.4, a * 0.7)
        g.setLineWidth(math.max(2.2, r * 1.05))
        g.line(prev[1], prev[2], pt[1], pt[2])
      end
    end
    -- Head of the shadow (denser oval + violet eye).
    g.setColor(0.05, 0.02, 0.08, 0.85)
    g.ellipse("fill", tipX, tipY, 7.5, 4.4)
    g.setColor(c[1], c[2], c[3], 0.95)
    g.ellipse("fill", tipX, tipY, 5.0, 2.9)
    g.setColor(0.78, 0.35, 0.95, 0.55 + 0.35 * math.abs(math.sin(age * 12)))
    g.circle("fill", tipX - 1.2, tipY - 0.6, 1.6)
    g.setColor(1, 0.85, 1, 0.55)
    g.circle("fill", tipX - 1.2, tipY - 0.6, 0.7)
    -- Impact smoke as the tip arrives.
    if t >= 0.68 then
      local smokeT = (t - 0.68) / 0.32
      drawShadeSmoke(g, tipX, tipY, smokeT, age, c)
    end
end)
Projectiles.registerStyle("shade_smoke", function(g, p, x, y, ox, oy, t, c, glitz)
    drawShadeSmoke(g, x, y, t, p.age, c)
end)
Projectiles.registerStyle("bolt", function(g, p, x, y, ox, oy, t, c, glitz)
    -- Vertical thunder strike onto the target (Thunder).
    local top = y - 30 + t * 6
    drawLightningBolt(g, x + math.sin((p.age or 0) * 8) * 2, top, x, y, p.age, c, {
      fade = 1 - t * 0.35,
      segs = 7,
      amp = 5,
      glow = 5,
      mid = 2.6,
      core = 1.2,
      forkLen = 6,
    })
    -- Ground impact bloom.
    g.setColor(c[1], c[2], c[3], 0.4 * (1 - t))
    g.circle("fill", x, y, 5 + t * 10)
    g.setColor(1, 1, 1, 0.55 * (1 - t))
    g.circle("line", x, y, 4 + t * 7)
end)
Projectiles.registerStyle("area", function(g, p, x, y, ox, oy, t, c, glitz)
    local radius = 3 + math.sin(t * math.pi) * (p.radius or 18)
    g.setColor(c[1], c[2], c[3], 0.30 * (1 - t))
    g.circle("fill", x, y, radius)
    g.setColor(c[1], c[2], c[3], 0.9 * (1 - t))
    g.setLineWidth(2)
    g.circle("line", x, y, radius)
    if glitz == "quake" then
      g.setColor(0.42, 0.30, 0.14, 0.38 * (1 - t))
      g.ellipse("fill", x, y + 3, radius, radius * 0.42)
      for i = 1, 6 do
        local a = t * math.pi * 2 + i * 1.05
        g.setColor(c[1], c[2], c[3], 0.85 * (1 - t))
        g.setLineWidth(2)
        g.line(x + math.cos(a) * radius * 0.25, y + math.sin(a) * 1.5,
          x + math.cos(a) * radius, y + math.sin(a) * 3.5)
      end
    elseif glitz == "burst" or glitz == "flash" then
      for i = 1, 6 do
        local a = i * math.pi / 3 + t
        g.setColor(1, 1, 1, 0.7 * (1 - t))
        g.line(x, y, x + math.cos(a) * radius, y + math.sin(a) * radius)
      end
    elseif glitz == "flame" then
      for i = 1, 5 do
        local a = i * 1.256 + t * 4 - math.pi * 0.5
        drawFlameTongue(g,
          x + math.cos(a) * radius * 0.45,
          y + math.sin(a) * radius * 0.45 - 1,
          a + math.pi * 0.5, 0.95, 0.85 * (1 - t))
      end
      drawFlameTongue(g, x, y - 1, 0, 1.1, 0.9 * (1 - t))
    end
end)
Projectiles.registerStyle("wave", function(g, p, x, y, ox, oy, t, c, glitz)
    local radius = 6 + t * (p.radius or 20)
    for i = 1, 3 do
      local r = radius - (i - 1) * 5
      if r > 0 then
        g.setColor(c[1], c[2], c[3], (0.55 - i * 0.12) * (1 - t))
        g.setLineWidth(2)
        g.circle("line", x, y + 2, r)
      end
    end
end)
Projectiles.registerStyle("surf", function(g, p, x, y, ox, oy, t, c, glitz)
    drawSurfTide(g, x, y, ox, oy, t, p.age, c, p.radius)
end)
Projectiles.registerStyle("razor", function(g, p, x, y, ox, oy, t, c, glitz)
    drawRazorVolley(g, x, y, ox, oy, t, p.age, c)
end)
Projectiles.registerStyle("swift", function(g, p, x, y, ox, oy, t, c, glitz)
    drawSwiftStars(g, x, y, ox, oy, t, p.age, c)
end)
Projectiles.registerStyle("ember", function(g, p, x, y, ox, oy, t, c, glitz)
    drawEmberCast(g, x, y, ox, oy, t, p.age, c, p.variant)
end)
Projectiles.registerStyle("rock", function(g, p, x, y, ox, oy, t, c, glitz)
    drawRockThrow(g, x, y, ox, oy, t, p.age, c)
end)
Projectiles.registerStyle("slide", function(g, p, x, y, ox, oy, t, c, glitz)
    drawRockSlide(g, x, y, ox, oy, t, p.age, c, p.radius)
end)
Projectiles.registerStyle("blast", function(g, p, x, y, ox, oy, t, c, glitz)
    drawFireBlast(g, x, y, ox, oy, t, p.age, c, p.radius)
end)
Projectiles.registerStyle("gust", function(g, p, x, y, ox, oy, t, c, glitz)
    drawGustWind(g, x, y, ox, oy, t, p.age, c)
end)
Projectiles.registerStyle("sand", function(g, p, x, y, ox, oy, t, c, glitz)
    drawSandSpray(g, x, y, ox, oy, t, p.age, c)
end)
Projectiles.registerStyle("clones", function(g, p, x, y, ox, oy, t, c, glitz)
    drawDoubleTeam(g, x, y, t, p.age, c)
end)
Projectiles.registerStyle("spiral", function(g, p, x, y, ox, oy, t, c, glitz)
    if glitz == "psy" then
      drawPsyAura(g, x, y, ox, oy, t, p.age, c, { crush = true })
    elseif glitz == "flame" then
      drawFireSpin(g, x, y, t, p.age, c)
    else
      for i = 1, 8 do
        local a = t * math.pi * 5 + i * 0.7
        local r = 3 + i * 1.6 * (0.35 + 0.65 * math.sin(t * math.pi))
        g.setColor(c[1], c[2], c[3], 0.85 * (1 - t * 0.5))
        g.circle("fill", x + math.cos(a) * r, y + math.sin(a) * r, 2)
      end
      g.setColor(1, 1, 1, 0.55 * (1 - t))
      g.circle("line", x, y, 5 + t * 8)
    end
end)
Projectiles.registerStyle("aura", function(g, p, x, y, ox, oy, t, c, glitz)
    drawPsyAura(g, x, y, ox, oy, t, p.age, c, {
      crush = (glitz ~= "confuse"),
      confuse = (glitz == "confuse"),
    })
end)
Projectiles.registerStyle("seed", function(g, p, x, y, ox, oy, t, c, glitz)
    drawSeedPlant(g, x, y, ox, oy, t, p.age, c)
end)
Projectiles.registerStyle("sonic", function(g, p, x, y, ox, oy, t, c, glitz)
    drawSonicWaves(g, x, y, ox, oy, t, p.age, c)
end)
Projectiles.registerStyle("ray", function(g, p, x, y, ox, oy, t, c, glitz)
    drawConfuseRay(g, x, y, ox, oy, t, p.age, c)
end)
Projectiles.registerStyle("stream", function(g, p, x, y, ox, oy, t, c, glitz)
    -- Dense particle stream from caster origin → traveling tip.
    local age = p.age or 0
    local dx, dy = x - ox, y - oy
    local len = math.sqrt(dx * dx + dy * dy)
    local nx, ny = 0, 1
    if len > 0.1 then
      nx, ny = -dy / len, dx / len
    end
    local n = (glitz == "flame" or glitz == "bubble") and 14
        or (glitz == "blob" and 10 or 8)
    if glitz == "flame" then
      drawFlameJet(g, x, y, ox, oy, t, age, c)
    elseif glitz == "bubble" then
      for i = 0, n do
        local u = i / n
        local along = u * math.min(1, t * 1.1 + 0.1)
        local bob = math.sin(age * 14 + i * 2.1) * (2.5 + u * 2)
        local side = math.cos(age * 9 + i * 1.7) * (1.8 + u * 1.5)
        local px = ox + dx * along + nx * side
        local py = oy + dy * along + ny * side * 0.4 + bob * 0.45
        local r = 1.6 + (1 - u) * 2.8 + (i % 4) * 0.45
        local a = (0.3 + 0.5 * (1 - u)) * (1 - t * 0.15)
        g.setColor(c[1], c[2], c[3], a * 0.35)
        g.circle("fill", px, py, r)
        g.setColor(c[1], c[2], c[3], a)
        g.circle("line", px, py, r)
        g.setColor(1, 1, 1, a * 0.85)
        g.circle("fill", px - r * 0.3, py - r * 0.3, math.max(0.5, r * 0.25))
      end
      -- Foam splash at the tip.
      for i = 1, 5 do
        local a = age * 10 + i * 1.5
        local r = 1.4 + (i % 2)
        g.setColor(c[1], c[2], c[3], 0.55)
        g.circle("line", x + math.cos(a) * (3 + i), y + math.sin(a) * 2.5, r)
      end
    else
      -- Generic dense stream (leaf / blob / dragon / acid).
      for i = 0, n do
        local u = i / n
        local along = u * math.min(1, t * 1.1 + 0.1)
        local wobble = math.sin(age * 16 + i * 1.8) * 2.2
        local px = ox + dx * along + nx * wobble
        local py = oy + dy * along + ny * wobble
        local r = 2 + (1 - u) * 2.5
        g.setColor(c[1], c[2], c[3], (0.35 + 0.45 * (1 - u)) * (1 - t * 0.2))
        g.circle("fill", px, py, r)
      end
      g.setColor(1, 1, 1, 0.55)
      g.circle("fill", x, y, 2.2)
    end
    if glitz ~= "flame" then
      drawMove(g, p, x, y)
    end
end)
Projectiles.registerStyle("multi", function(g, p, x, y, ox, oy, t, c, glitz)
    local n = (glitz == "tri") and 3 or 5
    for i = 1, n do
      local a = (i / n) * math.pi * 2 + (p.age or 0) * 8
      local r = 4 + math.sin(t * math.pi) * 8
      local px = x + math.cos(a) * r
      local py = y + math.sin(a) * r * 0.7
      g.setColor(c[1], c[2], c[3], 0.85 * (1 - t * 0.35))
      g.circle("fill", px, py, 2.4)
      g.setColor(1, 1, 1, 0.8)
      g.circle("fill", px, py, 1)
    end
end)
Projectiles.registerStyle("drain", function(g, p, x, y, ox, oy, t, c, glitz)
    -- Particles drift from foe (x,y) toward attacker origin (ox,oy).
    for i = 1, 5 do
      local u = (t + i * 0.12) % 1
      local px = x + (ox - x) * u
      local py = y + (oy - y) * u - math.sin(u * math.pi) * 4
      g.setColor(c[1], c[2], c[3], 0.8 * (1 - u))
      g.circle("fill", px, py, 2.2)
    end
    g.setColor(c[1], c[2], c[3], 0.35 * (1 - t))
    g.circle("line", x, y, 6 + t * 4)
end)
Projectiles.registerStyle("contact", function(g, p, x, y, ox, oy, t, c, glitz)
    drawContact(g, p, x, y, t)
end)
Projectiles.registerStyle("light_hit", function(g, p, x, y, ox, oy, t, c, glitz)
    drawLightHit(g, p, x, y, t)
end)
Projectiles.registerStyle("crit", function(g, p, x, y, ox, oy, t, c, glitz)
    drawCritBurst(g, p, x, y, t)
end)
Projectiles.registerStyle("dash_smear", function(g, p, x, y, ox, oy, t, c, glitz)
    drawDashSmear(g, x, y, ox, oy, t, p.age, c, glitz)
end)
Projectiles.registerStyle("ground_kick", function(g, p, x, y, ox, oy, t, c, glitz)
    drawGroundKick(g, p, x, y, t, c, glitz)
end)
Projectiles.registerStyle("bonk", function(g, p, x, y, ox, oy, t, c, glitz)
    -- Self-hit: impact ring plus popping stars.
    local r = 3 + math.sin(t * math.pi) * 8
    g.setColor(c[1], c[2], c[3], 0.55 * (1 - t))
    g.setLineWidth(2)
    g.circle("line", x, y, r)
    g.setColor(1, 1, 1, 0.85 * (1 - t))
    g.circle("fill", x, y, 1.8)
    for i = 1, 4 do
      local a = i * math.pi * 0.5 + t * 2.2
      local dist = 4 + t * 8
      local px = x + math.cos(a) * dist
      local py = y + math.sin(a) * dist - t * 4
      g.setColor(c[1], c[2], c[3], 0.9 * (1 - t))
      g.setLineWidth(1)
      g.line(px - 2.2, py, px + 2.2, py)
      g.line(px, py - 2.2, px, py + 2.2)
    end
end)
Projectiles.registerStyle("status", function(g, p, x, y, ox, oy, t, c, glitz)
    for i = 1, 5 do
      local a = t * math.pi * 4 + i * math.pi * 0.4
      local r = 5 + t * 8
      g.setColor(c[1], c[2], c[3], 1 - t * 0.45)
      g.circle("fill", x + math.cos(a) * r, y + math.sin(a) * r, 2)
    end
end)
Projectiles.registerStyle("heal", function(g, p, x, y, ox, oy, t, c, glitz)
    for i = 1, 3 do
      local hx = (i - 2) * 5
      g.setColor(c[1], c[2], c[3], 1 - t)
      g.rectangle("fill", x + hx - 1, y + 7 - t * 18, 3, 7)
      g.rectangle("fill", x + hx - 3, y + 9 - t * 18, 7, 3)
    end
end)
Projectiles.registerStyle("puff", function(g, p, x, y, ox, oy, t, c, glitz)
    -- Faint dust: rising wisps + a settling ring.
    local fade = 1 - t
    g.setColor(c[1], c[2], c[3], 0.28 * fade)
    g.circle("fill", x, y + 2, 5 + t * 7)
    g.setColor(c[1], c[2], c[3], 0.7 * fade)
    g.setLineWidth(1)
    g.circle("line", x, y + 2, 4 + t * 9)
    for i = 1, 5 do
      local a = i * 1.256 + t * 1.4
      local dist = 3 + t * 9
      local px = x + math.cos(a) * dist
      local py = y + 3 - t * 12 + math.sin(a * 2) * 1.5
      g.setColor(c[1], c[2], c[3], 0.55 * fade)
      g.circle("fill", px, py, 2.2 - t * 1.2)
      g.setColor(1, 1, 1, 0.25 * fade)
      g.circle("fill", px - 0.4, py - 0.6, 0.7)
    end
end)
Projectiles.registerStyle("dig_burst", function(g, p, x, y, ox, oy, t, c, glitz)
    -- Dirt clods + dust ring as a mon burrows or erupts.
    local fade = 1 - t
    local age = p.age or 0
    g.setColor(c[1], c[2], c[3], 0.35 * fade)
    g.ellipse("fill", x, y + 3, 6 + t * 10, 3 + t * 4)
    for i = 1, 8 do
      local a = i * 0.85 + age * 2.2
      local dist = 2 + t * (8 + (i % 3) * 3)
      local px = x + math.cos(a) * dist
      local py = y + 2 + math.sin(a) * dist * 0.45 - t * (2 + i % 4)
      local r = 1.6 + (i % 3) * 0.7
      g.setColor(c[1], c[2], c[3], 0.7 * fade)
      g.circle("fill", px, py, r)
      g.setColor(0.55, 0.4, 0.22, 0.4 * fade)
      g.circle("fill", px - 0.4, py - 0.5, r * 0.45)
    end
    g.setColor(0.35, 0.22, 0.1, 0.5 * fade)
    g.ellipse("line", x, y + 3, 5 + t * 8, 2.5 + t * 3)
end)
Projectiles.registerStyle("fly_gust", function(g, p, x, y, ox, oy, t, c, glitz)
    -- Wind ribbons climbing (or diving) with the flyer.
    local fade = 1 - t
    local age = p.age or 0
    local rising = (oy or y) >= (y - 1)
    local ang = rising and (-math.pi * 0.5) or (math.pi * 0.5)
    for i = 1, 6 do
      local u = i / 6
      local along = rising and (-u * (12 + t * 14)) or (u * (10 + t * 12))
      local sway = math.sin(age * 10 + i * 1.7) * (3 + u * 2)
      local px = x + sway
      local py = y + along
      drawWindSlash(g, px, py, ang + math.sin(age * 8 + i) * 0.25,
        0.7 + u * 0.2, c, (0.7 - u * 0.25) * fade)
    end
    g.setColor(c[1], c[2], c[3], 0.25 * fade)
    g.ellipse("fill", x, y + 2, 7 + t * 4, 2.5)
    drawWindSlash(g, x, y, ang, 1.15, c, 0.85 * fade)
end)
Projectiles.registerStyle("power_hit", function(g, p, x, y, ox, oy, t, c, glitz)
    drawPowerBurst(g, x, y, t, p.age, c, { impact = false })
end)
Projectiles.registerStyle("clash_glow", function(g, p, x, y, ox, oy, t, c, glitz)
    drawClashGlow(g, p, x, y, t, c)
end)
Projectiles.registerStyle("clash_trail", function(g, p, x, y, ox, oy, t, c, glitz)
    drawClashTrail(g, p, x, y, t, c)
end)
Projectiles.registerStyle("power_impact", function(g, p, x, y, ox, oy, t, c, glitz)
    drawPowerBurst(g, x, y, t, p.age, c, { impact = true })
end)
Projectiles.registerStyle("recall", function(g, p, x, y, ox, oy, t, c, glitz)
    -- Anime red recall laser: irregular thunder forks trainer → mon.
    local fade = 1 - t * 0.25
    local flash = 0.55 + 0.45 * math.abs(math.sin((p.age or 0) * 30))
    local dx, dy = x - ox, y - oy
    local len = math.sqrt(dx * dx + dy * dy)
    local nx, ny = 0, 1
    if len > 0.1 then
      nx, ny = -dy / len, dx / len
    end
    local segs = 8
    local pts = { { ox, oy } }
    for i = 1, segs - 1 do
      local u = i / segs
      local jitter = math.sin((p.age or 0) * 52 + i * 2.9) * 5.5
          + math.sin((p.age or 0) * 21 + i * 5.3) * 3.2
          + math.cos((p.age or 0) * 73 + i * 1.7) * 1.8
      -- Stronger mid-bolt thrash; ends stay closer to the true line.
      local amp = math.sin(u * math.pi)
      pts[#pts + 1] = {
        ox + dx * u + nx * jitter * amp,
        oy + dy * u + ny * jitter * amp,
      }
    end
    pts[#pts + 1] = { x, y }
    local function stroke(width, r, gr, b, a)
      g.setColor(r, gr, b, a)
      g.setLineWidth(width)
      for i = 1, #pts - 1 do
        g.line(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2])
      end
    end
    stroke(6, 1.00, 0.12, 0.10, 0.28 * fade * flash)
    stroke(3.2, 1.00, 0.28, 0.18, 0.75 * fade)
    stroke(1.4, 1.00, 0.85, 0.75, 0.95 * fade * flash)
    -- Side forks (thunder branches).
    for i = 2, #pts - 1, 2 do
      local px, py = pts[i][1], pts[i][2]
      local fork = 4 + (i % 3)
      local side = (i % 4 < 2) and 1 or -1
      local fx = px + nx * fork * side + math.sin((p.age or 0) * 40 + i) * 1.5
      local fy = py + ny * fork * side + math.cos((p.age or 0) * 37 + i) * 1.5
      g.setColor(1.00, 0.35, 0.22, 0.55 * fade * flash)
      g.setLineWidth(1.5)
      g.line(px, py, fx, fy)
      g.setColor(1, 0.92, 0.85, 0.7 * fade * flash)
      g.setLineWidth(1)
      g.line(px, py, fx, fy)
    end
    -- Impact bloom on the mon.
    g.setColor(1.00, 0.45, 0.30, 0.45 * fade * flash)
    g.circle("fill", x, y, 3 + flash * 2)
    g.setColor(1, 1, 1, 0.8 * fade * flash)
    g.circle("fill", x, y, 1.6)
end)

local function drawEffect(g, p, x, y, ox, oy)
  local c = p.color or { 0.92, 0.92, 1.00 }
  local t = math.min(1, (p.age or 0) / math.max(0.01, p.duration or 1))
  local glitz = p.glitz
  ox = ox or x
  oy = oy or y

  local painter = STYLE_PAINTERS[p.style]
  if painter then
    painter(g, p, x, y, ox, oy, t, c, glitz)
  end
end

local function voxelPeek(g, cx, cy, w, h, rgb, alpha)
  alpha = alpha or 1
  local isoH = h * 0.5
  local isoW = w * 0.5
  if g.polygon then
    g.setColor(rgb[1], rgb[2], rgb[3], alpha)
    g.polygon("fill",
      cx, cy - isoH,
      cx + isoW, cy,
      cx, cy + isoH,
      cx - isoW, cy)
    g.setColor(rgb[1] * 0.52, rgb[2] * 0.52, rgb[3] * 0.52, alpha * 0.9)
    g.polygon("fill",
      cx, cy + isoH,
      cx + isoW, cy,
      cx + isoW, cy + isoH * 0.8,
      cx, cy + isoH * 1.55)
  else
    g.setColor(rgb[1], rgb[2], rgb[3], alpha)
    g.rectangle("fill", cx - isoW, cy - isoH, w, h)
  end
end

local function drawPebble(g, cx, cy, w, h, rgb, alpha)
  voxelPeek(g, cx, cy, w, h, rgb, alpha)
  g.setColor(1, 1, 1, 0.18 * (alpha or 1))
  if g.ellipse then
    g.ellipse("fill", cx + w * 0.08, cy - h * 0.28, w * 0.18, h * 0.12)
  else
    g.circle("fill", cx + 0.6, cy - 1.2, 0.8)
  end
end

--- Crouch tell underfoot: grass patch, cave pebbles, water dive, wall shade.
local function drawCoverAura(g, x, y, phase, surface, foeX, foeY, wall)
  surface = surface or "open"
  local pulse = 0.62 + 0.28 * math.abs(math.sin(phase * 2.1))
  local ox, oy = 0, 5.8
  if foeX and foeY then
    local dx, dy = foeX - x, foeY - y
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 1 then
      ox = dx / len * 2.2
      oy = oy + dy / len * 1.1
    end
  end
  local cx, cy = x + ox, y + oy
  if surface == "grass" then
    g.setColor(0.12, 0.28, 0.10, 0.40 * pulse)
    if g.ellipse then
      g.ellipse("fill", cx, cy, 8.6, 2.6)
    else
      g.circle("fill", cx, cy, 3.0)
    end
    for i = -2, 2 do
      local px = cx + i * 2.5
      local sway = math.sin(phase * 4.6 + i * 1.2) * 0.85
      local h = 4.4 + (i % 2) * 1.4
      g.setColor(0.28, 0.62, 0.20, 0.82)
      if g.polygon then
        g.polygon("fill",
          px + sway, cy - h,
          px + 1.2, cy + 1.1,
          px - 1.2, cy + 1.1)
      else
        g.line(px, cy + 1, px + sway, cy - h)
      end
    end
    return
  end
  if surface == "cave" then
    -- Little voxel rocks around the lower body — not a Dig hole.
    local bob = math.sin(phase * 2.2) * 0.25
    local rocks = {
      { -7.2, 2.4, 7.5, 5.4, { 0.46, 0.38, 0.30 } },
      { 6.8, 2.0, 6.6, 4.8, { 0.54, 0.46, 0.36 } },
      { -3.4, 5.6, 6.2, 4.6, { 0.40, 0.34, 0.28 } },
      { 3.6, 5.8, 8.2, 5.8, { 0.50, 0.42, 0.32 } },
      { 0.4, 1.6, 5.0, 3.8, { 0.58, 0.50, 0.40 } },
    }
    for i = 1, #rocks do
      local r = rocks[i]
      local py = cy - 4.2 + r[2] + bob * ((i % 2 == 0) and 1 or -1)
      drawPebble(g, cx + r[1], py, r[3], r[4], r[5], 0.92 * pulse)
    end
    return
  end
  if surface == "water" then
    local ring = 0.7 + 0.3 * math.abs(math.sin(phase * 3.2))
    g.setColor(0.18, 0.46, 0.72, 0.42 * pulse)
    if g.ellipse then
      g.ellipse("fill", cx, cy, 9.2 * ring, 3.0)
      g.setColor(0.78, 0.92, 1.00, 0.40 * pulse)
      g.ellipse("line", cx, cy, 8.0 * ring, 2.5)
      g.ellipse("line", cx, cy, 5.2, 1.7)
    else
      g.circle("fill", cx, cy, 3.6)
    end
    for i = 1, 4 do
      local drift = (phase * 0.7 + i * 0.22) % 1
      local px = cx + math.sin(phase * 2.1 + i * 1.7) * 5.0
      local py = cy - 1 - drift * 7
      local a = 0.55 * (1 - drift)
      g.setColor(0.55, 0.82, 1.00, a)
      g.circle("fill", px, py, 1.05 + (i % 2) * 0.35)
      g.setColor(1, 1, 1, a * 0.5)
      g.circle("fill", px - 0.3, py - 0.3, 0.4)
    end
    return
  end
  if surface == "wall" then
    local wx = (wall and wall.u or 0) * 3.2
    local wy = (wall and wall.v or 0) * 2.4
    g.setColor(0.05, 0.04, 0.05, 0.50 * pulse)
    if g.ellipse then
      g.ellipse("fill", cx + wx, cy + wy, 7.4, 2.6)
    else
      g.circle("fill", cx + wx, cy + wy, 3.0)
    end
    voxelPeek(g, cx + wx * 0.6, cy + wy - 1.2, 9, 5, { 0.08, 0.07, 0.08 }, 0.32 * pulse)
    return
  end
  g.setColor(0.06, 0.05, 0.04, 0.42 * pulse)
  if g.ellipse then
    g.ellipse("fill", cx, cy, 8.4, 2.8)
  else
    g.circle("fill", cx, cy, 3.2)
  end
  voxelPeek(g, cx, cy - 1.6, 11, 6, { 0.10, 0.09, 0.08 }, 0.28 * pulse)
end

local function drawStatusAura(g, x, y, status, phase)
  local aura = STATUS_AURA[status]
  if not aura then
    return
  end
  local c = aura.color
  if aura.kind == "sparks" then
    for i = 1, 5 do
      local a = phase * 9 + i * 1.35
      local r = 7 + math.sin(phase * 14 + i) * 2
      local px = x + math.cos(a) * r
      local py = y + math.sin(a) * r * 0.75 - 2
      local flash = 0.45 + 0.55 * math.abs(math.sin(phase * 18 + i * 2))
      g.setColor(c[1], c[2], c[3], flash)
      g.setLineWidth(1)
      g.line(px - 2, py, px + 2, py)
      g.line(px, py - 2, px, py + 2)
    end
  elseif aura.kind == "ice" then
    g.setColor(c[1], c[2], c[3], 0.22)
    g.circle("fill", x, y - 1, 9)
    g.setColor(c[1], c[2], c[3], 0.55)
    g.setLineWidth(1)
    g.circle("line", x, y - 1, 8 + math.sin(phase * 2) * 0.6)
    for i = 1, 4 do
      local a = i * math.pi * 0.5 + phase * 0.4
      local px = x + math.cos(a) * 6
      local py = y + math.sin(a) * 5 - 1
      g.setColor(0.85, 0.96, 1.0, 0.7)
      g.polygon("fill", px, py - 3, px + 2, py, px, py + 3, px - 2, py)
    end
  elseif aura.kind == "bubbles" then
    for i = 1, 4 do
      local drift = (phase * 0.55 + i * 0.37) % 1
      local px = x + math.sin(phase * 2 + i * 2.2) * 6
      local py = y + 4 - drift * 14
      local rad = 1.4 + (i % 2) * 0.8
      g.setColor(c[1], c[2], c[3], 0.35 + 0.4 * (1 - drift))
      g.circle("line", px, py, rad)
      g.setColor(1, 1, 1, 0.35 * (1 - drift))
      g.circle("fill", px - 0.5, py - 0.5, 0.6)
    end
  elseif aura.kind == "flame" then
    -- Rising ember tongues around a burned mon (poison-bubbles analog).
    for i = 1, 4 do
      local drift = (phase * 0.72 + i * 0.28) % 1
      local sway = math.sin(phase * 8 + i * 2.1) * 1.5
      local px = x + math.sin(phase * 1.7 + i * 1.9) * 5.6 + sway
      local py = y + 5 - drift * 16
      local a = 0.30 + 0.55 * (1 - drift)
      drawFlameTongue(g, px, py, math.sin(phase * 6 + i) * 0.25,
        0.55 + (i % 2) * 0.18, a)
    end
  elseif aura.kind == "zs" then
    -- Rising Z's over a sleeping mon.
    for i = 1, 2 do
      local drift = (phase * 0.35 + i * 0.5) % 1
      local scale = 0.7 + i * 0.35
      local px = x + 5 + i * 2 + math.sin(phase + i) * 1.2
      local py = y - 4 - drift * 10
      local a = 0.25 + 0.55 * (1 - drift)
      g.setColor(c[1], c[2], c[3], a)
      local w, h = 4 * scale, 5 * scale
      g.rectangle("fill", px, py, w, 1.2)
      g.rectangle("fill", px, py + h, w, 1.2)
      if g.polygon then
        g.polygon("fill",
          px + w, py + 1.2,
          px + w - 1, py + 1.2,
          px + 1, py + h,
          px, py + h)
      end
    end
  elseif aura.kind == "swirl" then
    -- Circling "birds" / stars around a confused mon.
    for i = 1, 3 do
      local a = phase * 4.2 + i * (math.pi * 2 / 3)
      local r = 7.5
      local px = x + math.cos(a) * r
      local py = y - 6 + math.sin(a) * 3.2
      local flash = 0.45 + 0.45 * math.abs(math.sin(phase * 6 + i))
      g.setColor(c[1], c[2], c[3], flash)
      if g.arc then
        g.arc("line", px, py, 2.2, a - 0.9, a + 0.9)
      else
        g.circle("line", px, py, 2.2)
      end
      g.setColor(1, 0.95, 0.55, flash * 0.7)
      g.circle("fill", px, py, 0.8)
    end
  elseif aura.kind == "seed" then
    drawSeedSprouts(g, x, y, phase, c, { planted = true, fade = 1 })
  elseif aura.kind == "cover" then
    drawCoverAura(g, x, y, phase, "rock")
  end
end

local function spawn(session, spec)
  if not (session and session.live and session._battle) then
    return nil
  end
  session.projectiles = session.projectiles or {}
  session._projectileSeq = (session._projectileSeq or 0) + 1
  local p = {
    id = "ar_fbv_projectile_" .. tostring(session._projectileSeq),
    _fbv = true,
    _arFieldProjectile = true,
    passable = true,
    frozen = true,
    wanders = false,
    kind = spec.kind or "move",
    sx = spec.sx,
    sy = spec.sy,
    ex = spec.ex,
    ey = spec.ey,
    px = spec.sx,
    py = spec.sy,
    -- OverworldController queries grass/voxel placement for every entity.
    cellX = math.floor((spec.sx or 0) / 16),
    cellY = math.floor((spec.sy or 0) / 16),
    age = -(spec.delay or 0),
    duration = spec.duration or 0.36,
    hold = spec.hold or 0,
    arc = spec.arc or 8,
    color = spec.color,
    style = spec.style,
    glitz = spec.glitz,
    radius = spec.radius,
    variant = spec.variant,
    seed = spec.seed,
    onDone = spec.onDone,
    pinTip = spec.pinTip,
    pinFrozen = spec.pinFrozen == true,
    followSide = spec.followSide,
    followEnt = spec.followEnt,
    followPin = spec.followPin == true,
  }
  local dx, dy = p.ex - p.sx, p.ey - p.sy
  local len = math.sqrt(dx * dx + dy * dy)
  if len > 0 then
    p.dirX, p.dirY = dx / len, dy / len
  else
    p.dirX, p.dirY = 1, 0
  end
  function p:update()
  end
  function p:pose()
    return nil, self.px, self.py, "down", 0, false
  end
  -- camX/camY: world camera. mapFn(wx, wy) → UI pixels when painting overlay.
    function p:draw(camX, camY, mapFn)
    if self._removed or not (love and love.graphics) then
      return
    end
    if (self.age or 0) < 0 then
      return
    end
    local g = love.graphics
    camX, camY = camX or 0, camY or 0
    self.camX, self.camY = camX, camY
    local x = (self.px or 0) - camX
    local y = (self.py or 0) - camY
    local ox = (self.sx or 0) - camX
    local oy = (self.sy or 0) - camY
    if type(mapFn) == "function" then
      x, y = mapFn(x, y)
      ox, oy = mapFn(ox, oy)
    end
    local function finite(n)
      return type(n) == "number" and n == n and n > -1e8 and n < 1e8
    end
    if not (finite(x) and finite(y) and finite(ox) and finite(oy)) then
      return
    end
    if self.kind == "ball" then
      drawBall(g, x, y)
    elseif self.kind == "effect" then
      drawEffect(g, self, x, y, ox, oy)
    else
      drawMove(g, self, x, y)
    end
    g.setColor(1, 1, 1, 1)
    if g.setLineWidth then
      g.setLineWidth(1)
    end
  end
  session.projectiles[#session.projectiles + 1] = p
  return p
end

function Projectiles.draw(session, camX, camY, mapFn)
  local list = session and session.projectiles
  if type(list) ~= "table" then
    return
  end
  for i = 1, #list do
    local p = list[i]
    if p and not p._removed and type(p.draw) == "function" then
      p:draw(camX, camY, mapFn)
    end
  end
end

function Projectiles.drawStatusAuras(session, battle, camX, camY, mapFn)
  if not (session and session.live and love and love.graphics) then
    return
  end
  local g = love.graphics
  local phase = now()
  camX, camY = camX or 0, camY or 0
  local function mapPt(wx, wy)
    local x = wx - camX
    local y = wy - camY
    if type(mapFn) == "function" then
      x, y = mapFn(x, y)
    end
    return x, y
  end
  for _, item in ipairs({
    { ent = session.playerMon, battler = battle and battle.player, isPlayer = true },
    { ent = session.enemyMon, battler = battle and battle.enemy, isPlayer = false },
  }) do
    local ent = item.ent
    local mon = item.battler and item.battler.mon
    local status = mon and mon.status
    if type(status) == "string" then
      status = status:upper()
    end
    local confused = item.battler and tonumber(item.battler.confusedTurns)
    if confused and confused <= 0 then
      confused = nil
    end
    local leech = item.battler and item.battler.leechSeeded
    local covered = battlerInCover(session, battle, item.battler, item.isPlayer, ent)
    if ent and not ent.hidden and not ent._removed and not ent._fainting
        and ((status and STATUS_AURA[status]) or confused or leech or covered) then
      local wx, wy = center(session, ent)
      if wx then
        local x, y = mapPt(wx, wy)
        if status and STATUS_AURA[status] then
          drawStatusAura(g, x, y, status, phase)
        end
        if confused then
          drawStatusAura(g, x, y, "CNF", phase)
        end
        if leech then
          drawStatusAura(g, x, y, "LEECH", phase)
        end
        if covered then
          local surface = Projectiles.coverSurface(session, ent, battle)
          local prop = Projectiles.nearestCoverProp(session, ent)
          -- Tile tells (grass / cave / water) always sit under the crouch.
          -- Open/wall with a real prop: the world prop is the hide, no sticker.
          local paint = not (prop and (surface == "open" or surface == "wall"))
          if paint then
            local foe = item.isPlayer and session.enemyMon or session.playerMon
            local foeX, foeY = center(session, foe)
            if foeX then
              foeX, foeY = mapPt(foeX, foeY)
            end
            drawCoverAura(g, x, y, phase, surface, foeX, foeY, ent._coverWall)
          end
        end
      end
    end
  end
  g.setColor(1, 1, 1, 1)
  if g.setLineWidth then
    g.setLineWidth(1)
  end
end

local function rrRange(a, b)
  local random = (love and love.math and love.math.random) or math.random
  if b ~= nil then
    return random(a, b)
  end
  if a ~= nil then
    return random(a)
  end
  return random()
end

--- Random pad cells across the fight envelope (skip the user's tile).
local function pickPadTiles(session, count, skip)
  local g = session and session.grid
  local su = g and g.sizeU or 0
  local sv = g and g.sizeV or 0
  local cells = {}
  if su > 0 and sv > 0 then
    for u = 0, su - 1 do
      for v = 0, sv - 1 do
        local k = tostring(u) .. "," .. tostring(v)
        if not (skip and skip[k]) then
          cells[#cells + 1] = { u = u, v = v }
        end
      end
    end
  end
  local n = math.min(count, #cells)
  local picked = {}
  for _ = 1, n do
    local idx = rrRange(1, #cells)
    picked[#picked + 1] = table.remove(cells, idx)
  end
  return picked
end

--- Earthquake: Dig-like dirt bursts on random battlefield tiles.
local function spawnEarthquakeDigs(session, from)
  local dirt = { 0.72, 0.55, 0.32 }
  local skip = {}
  if from and from.padU ~= nil then
    skip[tostring(from.padU) .. "," .. tostring(from.padV)] = true
  end
  local tiles = pickPadTiles(session, 8, skip)
  if #tiles == 0 then
    local tx, ty = center(session, from)
    if not tx then
      return
    end
    for i = 1, 6 do
      local ox = (rrRange(0, 4) - 2) * 16
      local oy = (rrRange(0, 2) - 1) * 16
      spawn(session, {
        kind = "effect",
        style = "dig_burst",
        sx = tx + ox, sy = ty + oy + 2,
        ex = tx + ox, ey = ty + oy + 2,
        duration = 0.40 + (i % 3) * 0.08,
        delay = (i - 1) * 0.05,
        arc = 0,
        color = dirt,
      })
    end
    return
  end
  for i = 1, #tiles do
    local cell = tiles[i]
    local px, py = Coords.padCenterPx(session.grid, cell.u, cell.v)
    spawn(session, {
      kind = "effect",
      style = "dig_burst",
      sx = px, sy = py + 2,
      ex = px, ey = py + 2,
      duration = 0.40 + (i % 3) * 0.08,
      delay = (i - 1) * 0.04 + rrRange() * 0.08,
      arc = 0,
      color = dirt,
    })
  end
end

--- Paint on the 160×144 battle overlay (world→UI mapped).
function Projectiles.drawUi(session, battle)
  if not (session and session.live) then
    return
  end
  local ow = battle and battle.game and battle.game.overworld
  local cam = ow and ow.camera
  if not cam then
    return
  end
  local camX, camY = cam.x or 0, cam.y or 0
  local ren = battle.game and battle.game.renderer
  local mapFn = nil
  if type(Coords.worldViewToUi) == "function" then
    mapFn = function(wx, wy)
      return Coords.worldViewToUi(wx, wy, ren)
    end
  end
  Projectiles.drawStatusAuras(session, battle, camX, camY, mapFn)
  Projectiles.draw(session, camX, camY, mapFn)
end

function Projectiles.move(session, side, opts)
  opts = opts or {}
  local from = (side == "player") and session.playerMon or session.enemyMon
  local target = (side == "player") and session.enemyMon or session.playerMon
  local sx, sy = center(session, from)
  local ex, ey = center(session, target)
  if not (sx and ex) then
    return nil
  end
  local fx = resolveFx(opts)
  local jump = opts.jump == true

  -- Heal-named moves land on the user.
  if fx.style == "heal" then
    return Projectiles.heal(session, side)
  end

  if fx.style == "clones" then
    return spawn(session, {
      kind = "effect",
      style = "clones",
      glitz = fx.glitz or "afterimage",
      sx = sx, sy = sy, ex = sx, ey = sy,
      duration = fx.duration or 0.82,
      arc = 0,
      color = fx.color or TYPE_COLORS.NORMAL,
      pinTip = true,
      followPin = true,
      followSide = side,
      onDone = opts.onDone,
    })
  end

  -- Status-styled damaging/status moves (e.g. Toxic) orbit the foe.
  if fx.style == "status" then
    return spawn(session, {
      kind = "effect",
      style = "status",
      glitz = fx.glitz,
      sx = ex, sy = ey, ex = ex, ey = ey,
      duration = fx.duration or 0.48,
      arc = 0,
      color = fx.color,
      onDone = opts.onDone,
    })
  end

  if fx.style == "contact" then
    return spawn(session, {
      kind = "effect",
      style = "contact",
      glitz = fx.glitz or "slash",
      sx = ex, sy = ey, ex = ex, ey = ey,
      duration = fx.duration or 0.26,
      arc = 0,
      color = fx.color,
      onDone = opts.onDone,
    })
  end

  if fx.style == "aura" then
    -- Envelop the foe; keep caster origin for thought-sparkle stream.
    return spawn(session, {
      kind = "effect",
      style = "aura",
      glitz = fx.glitz,
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or 0.55,
      arc = 0,
      color = fx.color,
      pinTip = true,
      followSide = (side == "player") and "enemy" or "player",
      onDone = opts.onDone,
    })
  end

  if fx.style == "area" or fx.style == "wave" or fx.style == "bolt"
      or fx.style == "spiral" or fx.style == "multi" then
    local p = spawn(session, {
      kind = "effect",
      style = fx.style,
      glitz = fx.glitz,
      sx = ex, sy = ey, ex = ex, ey = ey,
      duration = fx.duration or 0.45,
      arc = 0,
      radius = fx.radius or 20,
      color = fx.color,
      onDone = opts.onDone,
    })
    if fx.moveId == "EARTHQUAKE" then
      spawnEarthquakeDigs(session, from)
    end
    return p
  end

  if fx.style == "drain" then
    return spawn(session, {
      kind = "effect",
      style = "drain",
      glitz = fx.glitz,
      sx = ex, sy = ey, ex = sx, ey = sy,
      duration = fx.duration or 0.48,
      arc = 0,
      color = fx.color,
      onDone = opts.onDone,
    })
  end

  if fx.style == "beam" then
    return spawn(session, {
      kind = "effect",
      style = "beam",
      glitz = fx.glitz,
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or 0.28,
      arc = 0,
      color = fx.color,
      onDone = opts.onDone,
    })
  end

  if fx.style == "shadow" then
    local color = fx.color or { 0.18, 0.08, 0.26 }
    local userDone = opts.onDone
    return spawn(session, {
      kind = "effect",
      style = "shadow",
      glitz = fx.glitz or "shade",
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or 0.52,
      arc = 3,
      color = color,
      onDone = function()
        -- Linger a smoke burst at the impact point after the ribbon lands.
        local smoke = spawn(session, {
          kind = "effect",
          style = "shade_smoke",
          glitz = "shade",
          sx = ex, sy = ey, ex = ex, ey = ey,
          duration = 0.38,
          arc = 0,
          color = color,
          onDone = userDone,
        })
        if not smoke and type(userDone) == "function" then
          pcall(userDone)
        end
      end,
    })
  end

  if fx.style == "surf" then
    return spawn(session, {
      kind = "effect",
      style = "surf",
      glitz = fx.glitz or "tide",
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or 0.68,
      arc = 3,
      radius = fx.radius or 18,
      color = fx.color,
      onDone = opts.onDone,
    })
  end

  if fx.style == "razor" then
    return spawn(session, {
      kind = "effect",
      style = "razor",
      glitz = fx.glitz or "blade",
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or 0.58,
      arc = 5,
      color = fx.color,
      onDone = opts.onDone,
    })
  end

  if fx.style == "swift" then
    return spawn(session, {
      kind = "effect",
      style = "swift",
      glitz = fx.glitz or "star",
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or 0.52,
      arc = 6,
      color = fx.color,
      onDone = opts.onDone,
    })
  end

  if fx.style == "ember" then
    local roll = (love and love.math and love.math.random) or math.random
    local variant = EMBER_VARIANTS[roll(#EMBER_VARIANTS)]
    return spawn(session, {
      kind = "effect",
      style = "ember",
      glitz = fx.glitz or "flame",
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or 0.54,
      arc = fx.arc or 13,
      color = fx.color,
      variant = variant,
      onDone = opts.onDone,
    })
  end

  if fx.style == "rock" then
    return spawn(session, {
      kind = "effect",
      style = "rock",
      glitz = fx.glitz or "rock",
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or 0.58,
      arc = fx.arc or 22,
      color = fx.color or TYPE_COLORS.ROCK,
      onDone = opts.onDone,
    })
  end

  if fx.style == "slide" then
    return spawn(session, {
      kind = "effect",
      style = "slide",
      glitz = fx.glitz or "rock",
      sx = ex, sy = ey, ex = ex, ey = ey,
      duration = fx.duration or 0.72,
      arc = 0,
      radius = fx.radius or 16,
      color = fx.color or TYPE_COLORS.ROCK,
      pinTip = true,
      followSide = (side == "player") and "enemy" or "player",
      onDone = opts.onDone,
    })
  end

  if fx.style == "blast" then
    return spawn(session, {
      kind = "effect",
      style = "blast",
      glitz = fx.glitz or "flame",
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or 0.56,
      arc = 5,
      radius = fx.radius or 24,
      color = fx.color,
      onDone = opts.onDone,
    })
  end

  if fx.style == "gust" then
    return spawn(session, {
      kind = "effect",
      style = "gust",
      glitz = fx.glitz or "wind",
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or 0.56,
      arc = 6,
      color = fx.color,
      onDone = opts.onDone,
    })
  end

  if fx.style == "sand" then
    return spawn(session, {
      kind = "effect",
      style = "sand",
      glitz = fx.glitz or "grit",
      sx = sx, sy = sy, ex = ex, ey = (ey or 0) - 4,
      duration = fx.duration or 0.58,
      arc = 5,
      color = fx.color,
      pinTip = true,
      followSide = (side == "player") and "enemy" or "player",
      onDone = opts.onDone,
    })
  end

  if fx.style == "stream" then
    return spawn(session, {
      kind = "effect",
      style = "stream",
      glitz = fx.glitz,
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or (jump and 0.44 or 0.38),
      arc = jump and 10 or 2,
      color = fx.color,
      onDone = opts.onDone,
    })
  end

  -- Default traveling orb (with type glitz).
  return spawn(session, {
    kind = "move",
    glitz = fx.glitz or "orb",
    sx = sx, sy = sy,
    ex = ex, ey = ey,
    duration = fx.duration or (jump and 0.42 or 0.34),
    arc = fx.arc or (jump and 20 or 5),
    color = fx.color,
    onDone = opts.onDone,
  })
end

function Projectiles.contact(session, side, opts)
  opts = opts or {}
  local target = (side == "player") and session.enemyMon or session.playerMon
  local x, y = center(session, target)
  if not x then return nil end
  local fx = resolveFx(opts)
  local glitz = fx.glitz
  if not glitz or fx.style ~= "contact" then
    glitz = TYPE_CONTACT[fx.moveType] or "slash"
  end
  local toss = glitz == "toss"
  local dash = glitz == "dash"
  local from = (side == "player") and session.playerMon or session.enemyMon
  local ox, oy = center(session, from)
  local dirX, dirY = 1, 0
  if ox then
    local dx, dy = x - ox, y - oy
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0.1 then
      dirX, dirY = dx / len, dy / len
    end
  end
  local hit = spawn(session, {
    kind = "effect",
    style = "contact",
    glitz = glitz,
    sx = x, sy = y, ex = x, ey = y,
    duration = fx.duration or (dash and 0.32 or 0.26),
    delay = dash and 0.10 or nil,
    arc = 0,
    color = fx.color or TYPE_COLORS[fx.moveType],
    pinTip = toss or nil,
    followSide = toss and ((side == "player") and "enemy" or "player") or nil,
  })
  if hit then
    hit.dirX, hit.dirY = dirX, dirY
  end
  if dash then
    Projectiles.dashSmear(session, side, opts)
  end
  return hit
end

function Projectiles.lightHit(session, side, opts)
  opts = opts or {}
  local target = (side == "player") and session.playerMon or session.enemyMon
  local x, y = center(session, target)
  if not x then
    return nil
  end
  local fx = resolveFx(opts)
  local glitz = fx.glitz
  if not glitz or (fx.style ~= "contact" and fx.style ~= "orb") then
    glitz = TYPE_CONTACT[fx.moveType] or "slash"
  end
  return spawn(session, {
    kind = "effect",
    style = "light_hit",
    glitz = glitz,
    sx = x, sy = y, ex = x, ey = y,
    duration = 0.32,
    arc = 0,
    color = fx.color or TYPE_COLORS[fx.moveType] or TYPE_COLORS.NORMAL,
  })
end

local GROUND_KICK_COLORS = {
  grass = { 0.38, 0.78, 0.28 },
  water = { 0.32, 0.68, 1.00 },
  snow = { 0.86, 0.94, 1.00 },
  cave = { 0.58, 0.46, 0.32 },
  sand = { 0.82, 0.66, 0.36 },
  spark = { 1.00, 0.88, 0.32 },
  dust = { 0.72, 0.64, 0.48 },
}

--- Comic-book starburst on a critical hit.
function Projectiles.critBurst(session, side, opts)
  opts = opts or {}
  local target = (side == "player") and session.playerMon or session.enemyMon
  local x, y = center(session, target)
  if not x then
    return nil
  end
  local roll = (love and love.math and love.math.random) or math.random
  local moveType = tostring(opts.moveType or "NORMAL"):upper()
  if moveType == "" then
    moveType = "NORMAL"
  end
  return spawn(session, {
    kind = "effect",
    style = "crit",
    glitz = moveType,
    sx = x, sy = y, ex = x, ey = y,
    duration = 0.42,
    arc = 0,
    seed = roll() * math.pi * 2,
    color = TYPE_COLORS[moveType] or TYPE_COLORS.NORMAL,
    pinTip = true,
    followSide = side,
  })
end

--- Speed-line smear on the attacker for Quick Attack / Extreme Speed.
function Projectiles.dashSmear(session, side, opts)
  opts = opts or {}
  local from = (side == "player") and session.playerMon or session.enemyMon
  local target = (side == "player") and session.enemyMon or session.playerMon
  local sx, sy = center(session, from)
  local ex, ey = center(session, target)
  if not (sx and ex) then
    return nil
  end
  local moveId = tostring(opts.moveId or ""):upper():gsub("%s+", "_")
  local extreme = moveId == "EXTREMESPEED" or moveId == "EXTREME_SPEED"
  return spawn(session, {
    kind = "effect",
    style = "dash_smear",
    glitz = extreme and "extreme" or "dash",
    sx = sx, sy = sy, ex = ex, ey = ey,
    duration = extreme and 0.42 or 0.34,
    arc = 0,
    color = { 0.92, 0.94, 1.00 },
  })
end

function Projectiles.groundKick(session, side, opts)
  opts = opts or {}
  local target = (side == "player") and session.playerMon or session.enemyMon
  local x, y = center(session, target)
  if not x then
    return nil
  end
  local glitz = Projectiles.hitGround(session, target, session and session._battle)
  local from = (side == "player") and session.enemyMon or session.playerMon
  local fx, fy = 1, 0
  if from then
    local ox, oy = center(session, from)
    if ox then
      local dx, dy = x - ox, y - oy
      local len = math.sqrt(dx * dx + dy * dy)
      if len > 0.1 then
        fx, fy = dx / len, dy / len
      end
    end
  end
  local p = spawn(session, {
    kind = "effect",
    style = "ground_kick",
    glitz = glitz,
    sx = x, sy = y + 5, ex = x + fx * 6, ey = y + 3,
    duration = 0.40,
    arc = 4,
    color = GROUND_KICK_COLORS[glitz] or GROUND_KICK_COLORS.dust,
  })
  if p then
    p.dirX, p.dirY = fx, fy
  end
  return p
end

function Projectiles.status(session, side, opts)
  opts = opts or {}
  local fx = resolveFx(opts)
  local moveId = fx.moveId
  local foeTarget = FOE_STATUS_MOVES[moveId] == true
  local targetEnt = foeTarget
      and ((side == "player") and session.enemyMon or session.playerMon)
      or ((side == "player") and session.playerMon or session.enemyMon)
  local fromEnt = (side == "player") and session.playerMon or session.enemyMon
  local ex, ey = center(session, targetEnt)
  if not ex then return nil end

  if fx.style == "clones" then
    return spawn(session, {
      kind = "effect",
      style = "clones",
      glitz = fx.glitz or "afterimage",
      sx = ex, sy = ey, ex = ex, ey = ey,
      duration = fx.duration or 0.82,
      arc = 0,
      color = fx.color or TYPE_COLORS.NORMAL,
      pinTip = true,
      followPin = true,
      followSide = side,
      onDone = opts.onDone,
    })
  end

  if fx.style == "seed" or fx.style == "sonic" or fx.style == "ray"
      or fx.style == "sand" then
    local sx, sy = center(session, fromEnt)
    if not sx then
      sx, sy = ex, ey
    end
    local color = fx.color
    if not color then
      color = (fx.style == "seed") and TYPE_COLORS.GRASS
          or (fx.style == "sand") and TYPE_COLORS.GROUND
          or TYPE_COLORS[fx.moveType]
    end
    local faceY = ey
    if fx.style == "sand" then
      faceY = ey - 4
    end
    return spawn(session, {
      kind = "effect",
      style = fx.style,
      glitz = fx.glitz or (fx.style == "seed" and "leaf"
          or (fx.style == "sand" and "grit" or nil)),
      sx = sx, sy = sy, ex = ex, ey = faceY,
      duration = fx.duration or (fx.style == "seed" and 0.58
          or (fx.style == "sand" and 0.58 or 0.62)),
      arc = (fx.style == "seed" and 8) or (fx.style == "sand" and 5) or 0,
      color = color,
      pinTip = foeTarget and true or nil,
      followSide = foeTarget and ((side == "player") and "enemy" or "player") or nil,
      onDone = opts.onDone,
    })
  end

  return spawn(session, {
    kind = "effect",
    style = "status",
    glitz = fx.glitz,
    sx = ex, sy = ey, ex = ex, ey = ey,
    duration = 0.48,
    arc = 0,
    color = fx.color or TYPE_COLORS[fx.moveType],
    onDone = opts.onDone,
  })
end

function Projectiles.heal(session, side)
  local target = (side == "player") and session.playerMon or session.enemyMon
  local x, y = center(session, target)
  if not x then return nil end
  return spawn(session, {
    kind = "effect",
    style = "heal",
    sx = x, sy = y, ex = x, ey = y,
    duration = 0.52,
    arc = 0,
    color = { 0.34, 0.92, 0.48 },
  })
end

function Projectiles.selfHit(session, side)
  local target = (side == "player") and session.playerMon or session.enemyMon
  local x, y = center(session, target)
  if not x then return nil end
  return spawn(session, {
    kind = "effect",
    style = "bonk",
    sx = x, sy = y - 2, ex = x, ey = y - 2,
    duration = 0.34,
    arc = 0,
    color = { 1.00, 0.62, 0.28 },
  })
end

function Projectiles.vanish(session, side, flavor)
  local target = (side == "player") and session.playerMon or session.enemyMon
  local x, y = center(session, target)
  if not x then return nil end
  flavor = tostring(flavor or "dig")
  if flavor == "fly" then
    return spawn(session, {
      kind = "effect",
      style = "fly_gust",
      sx = x, sy = y - 2, ex = x, ey = y - 22,
      duration = 0.52,
      arc = 0,
      color = { 0.78, 0.88, 1.00 },
    })
  end
  return spawn(session, {
    kind = "effect",
    style = "dig_burst",
    sx = x, sy = y + 4, ex = x, ey = y + 4,
    duration = 0.50,
    arc = 0,
    color = { 0.72, 0.55, 0.32 },
  })
end

function Projectiles.emerge(session, side, flavor)
  local target = (side == "player") and session.playerMon or session.enemyMon
  local x, y = center(session, target)
  if not x then return nil end
  flavor = tostring(flavor or "dig")
  if flavor == "fly" then
    return spawn(session, {
      kind = "effect",
      style = "fly_gust",
      sx = x, sy = y - 18, ex = x, ey = y - 2,
      duration = 0.36,
      arc = 0,
      color = { 0.82, 0.90, 1.00 },
    })
  end
  return spawn(session, {
    kind = "effect",
    style = "dig_burst",
    sx = x, sy = y + 3, ex = x, ey = y + 3,
    duration = 0.40,
    arc = 0,
    color = { 0.78, 0.58, 0.34 },
  })
end

function Projectiles.clashBurst(session, side, opts)
  opts = opts or {}
  local atk = (side == "player") and session.playerMon or session.enemyMon
  local def = (side == "player") and session.enemyMon or session.playerMon
  local ax, ay = center(session, atk)
  local bx, by = center(session, def)
  if not ax then
    return nil
  end
  local dx, dy = (bx or ax) - ax, (by or ay) - ay
  local len = math.sqrt(dx * dx + dy * dy)
  if len > 0.1 then
    dx, dy = dx / len, dy / len
  else
    dx, dy = 1, 0
  end
  local moveType = tostring(opts.moveType or "NORMAL"):upper()
  local color = TYPE_COLORS[moveType] or TYPE_COLORS.NORMAL
  local foeSide = (side == "player") and "enemy" or "player"
  spawn(session, {
    kind = "effect",
    style = "clash_glow",
    sx = ax, sy = ay, ex = ax, ey = ay,
    duration = 0.72,
    arc = 0,
    color = color,
    followPin = true,
    followEnt = atk,
    followSide = side,
  })
  if bx then
    spawn(session, {
      kind = "effect",
      style = "clash_glow",
      sx = bx, sy = by, ex = bx, ey = by,
      duration = 0.62,
      arc = 0,
      color = color,
      followPin = true,
      followEnt = def,
      followSide = foeSide,
    })
  end
  local trail = spawn(session, {
    kind = "effect",
    style = "clash_trail",
    sx = ax, sy = ay, ex = ax, ey = ay,
    duration = 0.58,
    arc = 0,
    color = color,
    followPin = true,
    followEnt = atk,
    followSide = side,
  })
  if trail then
    trail.dirX, trail.dirY = dx, dy
  end
  if bx then
    local kick = spawn(session, {
      kind = "effect",
      style = "clash_trail",
      sx = bx, sy = by, ex = bx, ey = by,
      duration = 0.42,
      arc = 0,
      color = color,
      followPin = true,
      followEnt = def,
      followSide = foeSide,
    })
    if kick then
      kick.dirX, kick.dirY = -dx, -dy
    end
  end
  return Projectiles.powerHit(session, foeSide, opts)
end

function Projectiles.powerHit(session, side, opts)
  opts = opts or {}
  local target = (side == "player") and session.playerMon or session.enemyMon
  local x, y = center(session, target)
  if not x then
    return nil
  end
  local moveType = tostring(opts.moveType or "NORMAL"):upper()
  return spawn(session, {
    kind = "effect",
    style = "power_hit",
    sx = x, sy = y, ex = x, ey = y,
    duration = 0.40,
    arc = 0,
    color = TYPE_COLORS[moveType] or TYPE_COLORS.NORMAL,
  })
end

function Projectiles.wallImpact(session, obstacle, opts)
  if not (session and obstacle and session.grid) then
    return nil
  end
  opts = opts or {}
  local x, y = Coords.padCenterPx(session.grid, obstacle.u, obstacle.v)
  y = y - 4
  local moveType = tostring(opts.moveType or "NORMAL"):upper()
  return spawn(session, {
    kind = "effect",
    style = "power_impact",
    glitz = obstacle.kind or "wall",
    sx = x, sy = y, ex = x, ey = y,
    duration = 0.46,
    arc = 0,
    color = TYPE_COLORS[moveType] or TYPE_COLORS.NORMAL,
  })
end

function Projectiles.faint(session, side)
  local target = (side == "player") and session.playerMon or session.enemyMon
  local x, y = center(session, target)
  if not x then return nil end
  return spawn(session, {
    kind = "effect",
    style = "puff",
    sx = x, sy = y + 2, ex = x, ey = y + 2,
    duration = 0.52,
    arc = 0,
    color = { 0.82, 0.78, 0.70 },
  })
end

--- Dust whoosh past the foe when an attack misses.
function Projectiles.miss(session, side)
  local from = (side == "player") and session.playerMon or session.enemyMon
  local target = (side == "player") and session.enemyMon or session.playerMon
  local sx, sy = center(session, from)
  local ex, ey = center(session, target)
  if not (session and sx) then
    return nil
  end
  if not ex then
    ex, ey = sx + 12, sy
  end
  local dx, dy = ex - sx, ey - sy
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.1 then
    dx, dy, len = 1, 0, 1
  end
  dx, dy = dx / len, dy / len
  local px, py = ex + dx * 14, ey + dy * 10
  return spawn(session, {
    kind = "effect",
    style = "puff",
    sx = sx, sy = sy,
    ex = px, ey = py,
    duration = 0.36,
    arc = 6,
    color = { 0.90, 0.90, 0.94 },
  })
end

--- Live trainer sprite for this side (player OW sprite / parked foe NPC).
local function trainerEnt(session, side)
  if not session then
    return nil
  end
  if side == "player" then
    local battle = session._battle
    local overworld = battle and battle.game and battle.game.overworld
    return overworld and overworld.player
  end
  return session.foe
end

--- Map pose of a battler (basePx), not the recall-shrink draw offset on px.
local function mapPose(session, ent)
  if not ent then
    return nil, nil
  end
  if type(ent.basePx) == "number" and type(ent.basePy) == "number" then
    return ent.basePx + 8, ent.basePy + 4
  end
  return center(session, ent)
end

--- Laser origin: chest of the recalling trainer's live sprite. Home pad is
--- only a fallback for tests / missing OW sprites — trainers can walk aside.
local function trainerOrigin(session, side)
  local trainer = trainerEnt(session, side)
  if trainer and type(trainer.px) == "number" and type(trainer.py) == "number" then
    -- Same lift as padCenterPx - 7: mid-tile X, torso rather than feet.
    return trainer.px + 8, trainer.py + 1
  end
  local home = session and session.grid and session.grid.home
  local slot = home and ((side == "player") and home.playerTrainer or home.enemyTrainer)
  if slot then
    local sx, sy = Coords.padCenterPx(session.grid, slot.u, slot.v)
    return sx, sy - 7
  end
  if side == "player" then
    return center(session, session.playerMon)
  end
  local foe = session and session.foe
  if foe and foe.cellX ~= nil then
    return foe.cellX * 16 + 8, foe.cellY * 16
  end
  return nil, nil
end

--- Red thunder-laser from the trainer into the mon (switch recall / faint recall).
-- Returns nil when there is no trainer origin (e.g. wild foe).
-- Never fires at a mon that is arriving (send-out / call-in).
function Projectiles.recallBeam(session, side, opts)
  opts = opts or {}
  local target = opts.target
      or ((side == "player") and session.playerMon or session.enemyMon)
  if not target or target._removed then
    return nil
  end
  -- Never aim the shrink laser at a battler from the other side.
  if target._arFieldSide and side and target._arFieldSide ~= side then
    return nil
  end
  local ex, ey = mapPose(session, target)
  if not (session and ex) then
    return nil
  end
  -- Wild foes have no trainer to fire the laser; keep the ground faint.
  if side == "enemy" then
    local battle = session._battle
    local kind = battle and tostring(battle.kind or ""):lower() or ""
    if not session.foe and kind ~= "trainer" then
      return nil
    end
  end
  local sx, sy = trainerOrigin(session, side)
  if not sx then
    return nil
  end
  return spawn(session, {
    kind = "effect",
    style = "recall",
    sx = sx, sy = sy,
    ex = ex, ey = ey,
    duration = opts.duration or 0.48,
    arc = 0,
    color = { 1.00, 0.28, 0.18 },
    -- Full bolt trainer → faint pose. Do not chase the shrink offset or a
    -- replacement send-out on this side.
    pinTip = true,
    pinFrozen = true,
    followEnt = target,
    followSide = side,
  })
end

function Projectiles.ball(session, opts)
  opts = opts or {}
  local target = session and session.enemyMon
  local ex, ey = center(session, target)
  if not (session and ex) then
    return nil
  end
  local trainer = session.grid and session.grid.home
    and session.grid.home.playerTrainer
  local sx, sy
  if trainer then
    sx, sy = Coords.padCenterPx(session.grid, trainer.u, trainer.v)
    sy = sy - 7
  else
    sx, sy = center(session, session.playerMon)
  end
  return spawn(session, {
    kind = "ball",
    sx = sx, sy = sy,
    ex = ex, ey = ey,
    duration = 0.52,
    hold = math.max(0, tonumber(opts.shakes) or 0) * 0.16,
    arc = 18,
    onDone = opts.onDone,
  })
end

function Projectiles.tick(session, dt)
  local list = session and session.projectiles
  if type(list) ~= "table" then
    return
  end
  for i = #list, 1, -1 do
    local p = list[i]
    p.age = (p.age or 0) + (dt or 0)
    local t = math.min(1, math.max(0, p.age) / math.max(0.01, p.duration))
    if p.followPin then
      local ent = p.followEnt
      if not ent or ent._removed or ent.hidden then
        ent = nil
      end
      if not ent and p.followSide then
        ent = (p.followSide == "player") and session.playerMon or session.enemyMon
      end
      if ent then
        local cx, cy = center(session, ent)
        if cx then
          p.sx, p.sy, p.ex, p.ey, p.px, p.py = cx, cy, cx, cy, cx, cy
        end
      end
    elseif p.pinTip then
      -- Frozen tips (recall) stay on the snapshot pose. Live tips follow the
      -- original target, never a replacement send-out on that side.
      if not p.pinFrozen then
        local ent = p.followEnt
        if not ent or ent._removed or ent.hidden then
          ent = nil
        end
        if not ent and p.followSide then
          ent = (p.followSide == "player") and session.playerMon or session.enemyMon
          if ent and ent.anim == "sendout" then
            ent = nil
          end
        end
        if ent then
          local cx, cy = center(session, ent)
          if cx then
            p.ex, p.ey = cx, cy
          end
        end
      end
      p.px = p.ex
      p.py = p.ey
    else
      p.px = p.sx + (p.ex - p.sx) * t
      p.py = p.sy + (p.ey - p.sy) * t - math.sin(t * math.pi) * (p.arc or 0)
    end
    if t >= 1 and p.kind == "ball" and p.hold > 0 then
      local holdAge = p.age - p.duration
      p.px = p.ex + math.sin(holdAge * 34) * math.max(0, 2 - holdAge * 3)
      p.py = p.ey
    end
    p.cellX = math.floor((p.px or 0) / 16)
    p.cellY = math.floor((p.py or 0) / 16)
    if p.age >= p.duration + (p.hold or 0) then
      p._removed = true
      removeEntity(session, p)
      table.remove(list, i)
      if type(p.onDone) == "function" then
        pcall(p.onDone)
      end
    end
  end
end

function Projectiles.clear(session)
  local list = session and session.projectiles
  if type(list) ~= "table" then
    return
  end
  for i = #list, 1, -1 do
    list[i]._removed = true
    removeEntity(session, list[i])
    list[i] = nil
  end
end

return Projectiles
