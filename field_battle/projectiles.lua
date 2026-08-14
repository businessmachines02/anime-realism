-- Field battle — world-space projectiles for hybrid flat/voxel maps.
--
-- Simulated in world pixels; painted on the battle UI overlay with
-- world→UI mapping (same as HP bars) so FX survive 3D/world overrides.
-- Kept off ow.entities: Dramatic Shape's voxel pass wedges on nil sprites.
--
-- Movepool: named Gen1 moves + type defaults pick style / glitz. Persistent
-- PAR / FRZ / PSN / BRN / SLP / confusion auras are drawn around live field
-- sprites each frame.

local Coords = require("coords")

local Projectiles = {}

local TYPE_COLORS = {
  NORMAL = { 0.86, 0.86, 0.78 },
  FIRE = { 1.00, 0.34, 0.12 },
  WATER = { 0.20, 0.58, 1.00 },
  ELECTRIC = { 1.00, 0.88, 0.18 },
  GRASS = { 0.30, 0.82, 0.28 },
  ICE = { 0.52, 0.90, 1.00 },
  FIGHTING = { 0.78, 0.28, 0.22 },
  POISON = { 0.66, 0.30, 0.78 },
  GROUND = { 0.72, 0.52, 0.28 },
  FLYING = { 0.62, 0.72, 0.96 },
  PSYCHIC = { 0.92, 0.34, 0.82 },
  BUG = { 0.66, 0.78, 0.20 },
  ROCK = { 0.66, 0.56, 0.34 },
  GHOST = { 0.52, 0.36, 0.72 },
  DRAGON = { 0.45, 0.36, 0.88 },
  DARK = { 0.40, 0.32, 0.28 },
  STEEL = { 0.72, 0.74, 0.80 },
  FAIRY = { 0.94, 0.58, 0.78 },
}

-- Named move overrides (style on effect/move; glitz tunes the paint).
local MOVE_FX = {
  HYPER_BEAM = { style = "beam", glitz = "thick", duration = 0.46 },
  SOLARBEAM = { style = "beam", glitz = "thick", duration = 0.44, color = { 0.72, 1.00, 0.42 } },
  ICE_BEAM = {
    style = "beam",
    glitz = "icebolt",
    duration = 0.36,
    color = { 0.48, 0.86, 1.00 },
  },
  AURORA_BEAM = { style = "beam", glitz = "frost" },
  PSYBEAM = { style = "beam", glitz = "psy" },
  THUNDERBOLT = { style = "beam", glitz = "bolt", duration = 0.36 },
  THUNDERSHOCK = { style = "beam", glitz = "bolt", duration = 0.30 },
  THUNDER = { style = "bolt", duration = 0.42 },
  FLAMETHROWER = { style = "stream", glitz = "flame", duration = 0.48 },
  FIRE_BLAST = { style = "area", glitz = "flame", radius = 24, duration = 0.50 },
  EMBER = { style = "orb", glitz = "flame", arc = 10 },
  FIRE_SPIN = { style = "spiral", glitz = "flame", duration = 0.48 },
  HYDRO_PUMP = { style = "stream", glitz = "bubble", duration = 0.46 },
  WATER_GUN = { style = "orb", glitz = "bubble" },
  BUBBLEBEAM = { style = "stream", glitz = "bubble", duration = 0.46 },
  BUBBLE_BEAM = { style = "stream", glitz = "bubble", duration = 0.46 },
  BUBBLE = { style = "orb", glitz = "bubble", arc = 12 },
  SURF = {
    style = "surf",
    glitz = "tide",
    duration = 0.68,
    radius = 18,
    color = { 0.18, 0.62, 0.98 },
  },
  BLIZZARD = { style = "area", glitz = "frost", radius = 22 },
  PSYCHIC = {
    style = "aura",
    glitz = "psy",
    duration = 0.62,
    color = { 0.92, 0.34, 0.82 },
  },
  PSYCHIC_M = {
    style = "aura",
    glitz = "psy",
    duration = 0.62,
    color = { 0.92, 0.34, 0.82 },
  },
  CONFUSION = {
    style = "aura",
    glitz = "confuse",
    duration = 0.50,
    color = { 0.86, 0.48, 0.96 },
  },
  DREAM_EATER = { style = "drain", glitz = "psy", duration = 0.52 },
  MEGA_DRAIN = { style = "drain", glitz = "leaf", duration = 0.48 },
  GIGA_DRAIN = { style = "drain", glitz = "leaf", duration = 0.52 },
  ABSORB = { style = "drain", glitz = "leaf", duration = 0.42 },
  RAZOR_LEAF = {
    style = "razor",
    glitz = "blade",
    duration = 0.58,
    color = { 0.42, 0.88, 0.22 },
  },
  PETAL_DANCE = { style = "multi", glitz = "leaf", duration = 0.44 },
  VINE_WHIP = { style = "stream", glitz = "leaf" },
  LEECH_SEED = {
    style = "seed",
    glitz = "leaf",
    duration = 0.58,
    color = { 0.28, 0.72, 0.24 },
  },
  SLUDGE = { style = "orb", glitz = "blob", arc = 9 },
  SLUDGE_BOMB = { style = "orb", glitz = "blob", arc = 12 },
  ACID = { style = "stream", glitz = "blob" },
  SMOG = { style = "area", glitz = "blob", radius = 16 },
  TOXIC = { style = "status", glitz = "blob", duration = 0.55 },
  EARTHQUAKE = { style = "area", glitz = "quake", radius = 22, duration = 0.62 },
  FISSURE = { style = "area", glitz = "quake", radius = 18 },
  ROCK_SLIDE = { style = "area", glitz = "rock", radius = 20 },
  ROCK_THROW = { style = "orb", glitz = "rock", arc = 16 },
  EXPLOSION = { style = "area", glitz = "burst", radius = 28, duration = 0.55 },
  SELFDESTRUCT = { style = "area", glitz = "burst", radius = 26, duration = 0.52 },
  SWIFT = {
    style = "swift",
    glitz = "star",
    duration = 0.52,
    color = { 1.00, 0.92, 0.42 },
  },
  TRI_ATTACK = { style = "multi", glitz = "tri", duration = 0.40 },
  NIGHT_SHADE = {
    style = "shadow",
    glitz = "shade",
    duration = 0.52,
    color = { 0.18, 0.08, 0.26 },
  },
  LICK = { style = "contact", glitz = "ghost" },
  DRAGON_RAGE = { style = "stream", glitz = "dragon" },
  HORN_DRILL = { style = "beam", glitz = "pierce" },
  FLASH = { style = "area", glitz = "flash", radius = 18, duration = 0.32 },
  RECOVER = { style = "heal" },
  SOFTBOILED = { style = "heal" },
  REST = { style = "heal" },
  -- Physical contact signatures (still land at the foe).
  SLASH = { style = "contact", glitz = "slash" },
  CUT = { style = "contact", glitz = "slash" },
  FURY_SWIPES = { style = "contact", glitz = "slash" },
  FURY_ATTACK = { style = "contact", glitz = "pierce" },
  HORN_ATTACK = { style = "contact", glitz = "pierce" },
  PECK = { style = "contact", glitz = "pierce" },
  DRILL_PECK = { style = "contact", glitz = "pierce" },
  BITE = { style = "contact", glitz = "bite" },
  CRUNCH = { style = "contact", glitz = "bite" },
  BODY_SLAM = { style = "contact", glitz = "impact" },
  TAKE_DOWN = { style = "contact", glitz = "impact" },
  DOUBLE_EDGE = { style = "contact", glitz = "impact" },
  TACKLE = { style = "contact", glitz = "impact" },
  STRENGTH = { style = "contact", glitz = "impact" },
  MEGA_PUNCH = { style = "contact", glitz = "impact" },
  MEGA_KICK = { style = "contact", glitz = "impact" },
  QUICK_ATTACK = { style = "contact", glitz = "dash" },
  EXTREMESPEED = { style = "contact", glitz = "dash" },
}

local TYPE_STYLE = {
  FIRE = { style = "stream", glitz = "flame" },
  WATER = { style = "orb", glitz = "bubble" },
  ELECTRIC = { style = "beam", glitz = "bolt" },
  ICE = { style = "beam", glitz = "frost" },
  PSYCHIC = { style = "spiral", glitz = "psy" },
  GHOST = { style = "beam", glitz = "ghost" },
  GRASS = { style = "orb", glitz = "leaf" },
  POISON = { style = "orb", glitz = "blob" },
  DRAGON = { style = "stream", glitz = "dragon" },
  GROUND = { style = "area", glitz = "quake", radius = 18 },
  ROCK = { style = "orb", glitz = "rock", arc = 14 },
  BUG = { style = "orb", glitz = "leaf" },
  FLYING = { style = "multi", glitz = "star" },
  FIGHTING = { style = "contact", glitz = "impact" },
  NORMAL = { style = "orb", glitz = "star" },
}

local TYPE_CONTACT = {
  FIRE = "flame",
  WATER = "bubble",
  ELECTRIC = "bolt",
  ICE = "frost",
  POISON = "blob",
  FIGHTING = "impact",
  FLYING = "slash",
  BUG = "slash",
  GHOST = "ghost",
  STEEL = "slash",
  ROCK = "impact",
  GROUND = "impact",
  NORMAL = "slash",
  DRAGON = "slash",
  PSYCHIC = "psy",
  GRASS = "leaf",
}

local STATUS_AURA = {
  PAR = { color = { 1.00, 0.88, 0.18 }, kind = "sparks" },
  FRZ = { color = { 0.55, 0.90, 1.00 }, kind = "ice" },
  PSN = { color = { 0.70, 0.32, 0.82 }, kind = "bubbles" },
  TOX = { color = { 0.55, 0.16, 0.70 }, kind = "bubbles" },
  BRN = { color = { 1.00, 0.42, 0.10 }, kind = "flame" },
  SLP = { color = { 0.72, 0.78, 0.96 }, kind = "zs" },
  CNF = { color = { 0.95, 0.78, 0.22 }, kind = "swirl" },
  LEECH = { color = { 0.28, 0.72, 0.24 }, kind = "seed" },
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
}

function Projectiles.isTravelFx(opts)
  local moveId = tostring((opts or {}).moveId or ""):upper():gsub("%s+", "_")
  local named = MOVE_FX[moveId]
  if not (named and named.style) then
    return false
  end
  return TRAVEL_STYLES[named.style] == true
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

--- Razor Leaf: cyclone gather → staggered spinning blades → cutting slash.
local function drawRazorVolley(g, x, y, ox, oy, t, age, c)
  local dx, dy = x - ox, y - oy
  local len = math.sqrt(dx * dx + dy * dy)
  local nx, ny = 0, 1
  if len > 0.1 then
    nx, ny = -dy / len, dx / len
  end
  local fade = 1
  if t > 0.82 then
    fade = 1 - (t - 0.82) / 0.18
  end
  local spinUp = math.min(1, t / 0.22)
  local launch = math.max(0, (t - 0.16) / 0.84)

  -- Gather cyclone at the caster.
  if spinUp > 0.02 and t < 0.55 then
    local ringFade = (1 - math.max(0, (t - 0.32) / 0.23)) * fade
    g.setColor(c[1], c[2], c[3], 0.18 * ringFade)
    g.ellipse("fill", ox, oy + 2, 7 + spinUp * 4, 3)
    for i = 1, 6 do
      local a = (age or 0) * 14 + i * (math.pi * 2 / 6)
      local r = 5 + spinUp * 3
      local px = ox + math.cos(a) * r
      local py = oy + math.sin(a) * r * 0.42 - 1
      drawLeafBlade(g, px, py, a + math.pi * 0.5, 0.55 + spinUp * 0.2, c,
        0.7 * ringFade)
    end
  end

  -- Staggered flying blades with a weaving scatter.
  local n = 7
  for i = 1, n do
    local delay = (i - 1) * 0.09
    local u = (launch - delay) / math.max(0.35, 1 - delay)
    if u > 0 and u < 1.15 then
      local along = math.min(1, u)
      local side = ((i % 2) * 2 - 1)
      local weave = math.sin(along * math.pi * 1.6 + i) * (4.5 + (i % 3))
      local px = ox + dx * along + nx * weave * side * 0.55
      local py = oy + dy * along + ny * weave * side * 0.35
          - math.sin(along * math.pi) * 3
      local rot = (age or 0) * (16 + i * 1.4) + i * 0.9
      local aLeaf = fade * (u < 1 and 0.95 or (1.15 - u) / 0.15)
      drawLeafBlade(g, px, py, rot, 0.85 + (i % 3) * 0.12, c, aLeaf)
      if along > 0.08 and along < 0.95 then
        g.setColor(c[1], c[2], c[3], 0.35 * aLeaf)
        g.setLineWidth(1.4)
        g.line(px - dx * 0.08, py - dy * 0.08, px, py)
      end
      -- Cutting flashes as blades reach the foe.
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

  -- Impact leaf burst past the target.
  if t > 0.72 then
    local burst = (t - 0.72) / 0.28
    for i = 1, 5 do
      local a = i * 1.256 + (age or 0) * 2
      local dist = burst * (6 + i)
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

local function drawMove(g, p, x, y)
  local c = p.color or { 0.92, 0.92, 1.00 }
  local glitz = p.glitz or "orb"
  local age = p.age or 0
  local trail = trailPoints(p, x, y, (glitz == "flame" or glitz == "bubble") and 8 or 3,
    (glitz == "flame" or glitz == "bubble") and 3.2 or 4)

  if glitz == "flame" then
    for i = #trail, 1, -1 do
      local tp = trail[i]
      local wobble = math.sin(age * 22 + i * 1.7) * 1.8
      local nx = -(p.dirY or 0) * wobble
      local ny = (p.dirX or 1) * wobble
      local r = 5.5 - (i - 1) * 0.45
      g.setColor(c[1], c[2] * 0.35, 0.02, 0.28 * tp.a)
      g.circle("fill", tp.x + nx * 0.4, tp.y + ny * 0.4 - (i - 1) * 0.6, r + 2)
      g.setColor(c[1], c[2] * 0.55, 0.05, 0.6 * tp.a)
      g.circle("fill", tp.x + nx, tp.y + ny - (i - 1) * 0.5, r)
    end
    -- Embers peeling off the tip.
    for i = 1, 5 do
      local a = age * 14 + i * 2.1
      local d = 3 + (i % 3) * 2
      g.setColor(1, 0.7 + (i % 2) * 0.2, 0.2, 0.7)
      g.circle("fill",
        x + math.cos(a) * d * 0.6 - (p.dirX or 0) * (i + 1),
        y + math.sin(a) * d * 0.5 - 2 - i * 0.4,
        1.4 - i * 0.12)
    end
    g.setColor(1, 0.95, 0.55, 0.95)
    g.circle("fill", x, y, 2.8)
    g.setColor(1, 1, 1, 0.85)
    g.circle("fill", x, y - 0.5, 1.2)
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
    g.setColor(c[1], c[2], c[3], 0.95)
    g.polygon("fill", x - 3, y + 2, x + 3, y + 2, x + 2, y - 3, x - 2, y - 2)
    g.setColor(1, 1, 1, 0.35)
    g.polygon("fill", x - 1, y - 1, x + 2, y - 2, x + 1, y)
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
    g.setColor(c[1], c[2], c[3], fade)
    g.setLineWidth(3)
    g.line(x - 10 + t * 4, y - 2, x + 6, y + 1)
    g.setLineWidth(1)
    g.line(x - 8 + t * 4, y + 3, x + 4, y + 4)
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

  if glitz == "flame" or glitz == "bubble" or glitz == "blob"
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

local function drawEffect(g, p, x, y, ox, oy)
  local c = p.color or { 0.92, 0.92, 1.00 }
  local t = math.min(1, (p.age or 0) / math.max(0.01, p.duration or 1))
  local glitz = p.glitz
  ox = ox or x
  oy = oy or y

  if p.style == "beam" then
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
          g.setColor(c[1], c[2], c[3], 0.85 * fadeIce)
          g.polygon("fill",
            pt(0, -2.4), pt(0.9, 0), pt(0, 2.4), pt(-0.9, 0))
          g.setColor(1, 1, 1, 0.7 * fadeIce)
          g.polygon("fill",
            pt(0, -1.1), pt(0.35, 0), pt(0, 0.5), pt(-0.2, -0.15))
        end
      end
    else
      g.setColor(c[1], c[2], c[3], 0.34)
      g.setLineWidth(thick)
      g.line(ox, oy, x, y)
      g.setColor(1, 1, 1, 0.9)
      g.setLineWidth(2)
      g.line(ox, oy, x, y)
      if glitz == "frost" or glitz == "psy" or glitz == "ghost" then
        for i = 1, 3 do
          local u = i / 4
          local px = ox + (x - ox) * u
          local py = oy + (y - oy) * u
          g.setColor(c[1], c[2], c[3], 0.7 * (1 - t))
          g.circle("fill", px, py, 2)
        end
      end
    end
  elseif p.style == "shadow" then
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
  elseif p.style == "shade_smoke" then
    drawShadeSmoke(g, x, y, t, p.age, c)
  elseif p.style == "bolt" then
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
  elseif p.style == "area" then
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
        local a = i * 1.256 + t * 4
        g.setColor(c[1], c[2] * 0.6, 0.1, 0.55 * (1 - t))
        g.circle("fill", x + math.cos(a) * radius * 0.55,
          y + math.sin(a) * radius * 0.55 - 2, 3)
      end
    end
  elseif p.style == "wave" then
    local radius = 6 + t * (p.radius or 20)
    for i = 1, 3 do
      local r = radius - (i - 1) * 5
      if r > 0 then
        g.setColor(c[1], c[2], c[3], (0.55 - i * 0.12) * (1 - t))
        g.setLineWidth(2)
        g.circle("line", x, y + 2, r)
      end
    end
  elseif p.style == "surf" then
    drawSurfTide(g, x, y, ox, oy, t, p.age, c, p.radius)
  elseif p.style == "razor" then
    drawRazorVolley(g, x, y, ox, oy, t, p.age, c)
  elseif p.style == "swift" then
    drawSwiftStars(g, x, y, ox, oy, t, p.age, c)
  elseif p.style == "spiral" then
    if glitz == "psy" then
      drawPsyAura(g, x, y, ox, oy, t, p.age, c, { crush = true })
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
  elseif p.style == "aura" then
    drawPsyAura(g, x, y, ox, oy, t, p.age, c, {
      crush = (glitz ~= "confuse"),
      confuse = (glitz == "confuse"),
    })
  elseif p.style == "seed" then
    drawSeedPlant(g, x, y, ox, oy, t, p.age, c)
  elseif p.style == "stream" then
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
      for i = 0, n do
        local u = i / n
        -- Particles lag slightly behind the tip so the stream fills in.
        local along = u * math.min(1, t * 1.15 + 0.08)
        local wobble = math.sin(age * 18 + i * 1.6) * (2.8 + u * 2)
            + math.cos(age * 11 + i * 2.3) * 1.4
        local px = ox + dx * along + nx * wobble
        local py = oy + dy * along + ny * wobble - u * 2
        local r = 2.2 + (1 - u) * 3.5 + math.sin(age * 20 + i) * 0.6
        local a = (0.25 + 0.55 * (1 - u)) * (1 - t * 0.2)
        g.setColor(c[1], c[2] * 0.3, 0.02, a * 0.45)
        g.circle("fill", px, py - 1, r + 2)
        g.setColor(c[1], c[2] * 0.55, 0.08, a)
        g.circle("fill", px, py, r)
        if i % 3 == 0 then
          g.setColor(1, 0.9, 0.4, a * 0.85)
          g.circle("fill", px, py - 0.5, math.max(0.8, r * 0.35))
        end
      end
      -- Tip bloom + embers.
      g.setColor(1, 0.55, 0.12, 0.45)
      g.circle("fill", x, y, 7)
      for i = 1, 6 do
        local a = age * 16 + i * 1.9
        g.setColor(1, 0.75, 0.25, 0.75)
        g.circle("fill",
          x + math.cos(a) * (3 + i % 3),
          y + math.sin(a) * 2 - 2,
          1.5)
      end
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
    drawMove(g, p, x, y)
  elseif p.style == "multi" then
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
  elseif p.style == "drain" then
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
  elseif p.style == "contact" then
    drawContact(g, p, x, y, t)
  elseif p.style == "bonk" then
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
  elseif p.style == "status" then
    for i = 1, 5 do
      local a = t * math.pi * 4 + i * math.pi * 0.4
      local r = 5 + t * 8
      g.setColor(c[1], c[2], c[3], 1 - t * 0.45)
      g.circle("fill", x + math.cos(a) * r, y + math.sin(a) * r, 2)
    end
  elseif p.style == "heal" then
    for i = 1, 3 do
      local hx = (i - 2) * 5
      g.setColor(c[1], c[2], c[3], 1 - t)
      g.rectangle("fill", x + hx - 1, y + 7 - t * 18, 3, 7)
      g.rectangle("fill", x + hx - 3, y + 9 - t * 18, 7, 3)
    end
  elseif p.style == "puff" then
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
  elseif p.style == "dig_burst" then
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
  elseif p.style == "fly_gust" then
    -- Wind ribbons climbing (or diving) with the flyer.
    local fade = 1 - t
    local age = p.age or 0
    local rising = (oy or y) >= (y - 1)
    for i = 1, 6 do
      local u = i / 6
      local along = rising and (-u * (12 + t * 14)) or (u * (10 + t * 12))
      local sway = math.sin(age * 10 + i * 1.7) * (3 + u * 2)
      local px = x + sway
      local py = y + along
      g.setColor(c[1], c[2], c[3], (0.55 - u * 0.25) * fade)
      g.setLineWidth(1.6)
      g.line(px - 2, py + 2, px + 2, py - 3)
      g.setColor(1, 1, 1, 0.35 * fade * (1 - u))
      g.circle("fill", px, py, 1.2)
    end
    g.setColor(c[1], c[2], c[3], 0.25 * fade)
    g.ellipse("fill", x, y + 2, 7 + t * 4, 2.5)
  elseif p.style == "power_hit" then
    drawPowerBurst(g, x, y, t, p.age, c, { impact = false })
  elseif p.style == "power_impact" then
    drawPowerBurst(g, x, y, t, p.age, c, { impact = true })
  elseif p.style == "recall" then
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
  end
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
      local h = 3.4 + (i % 2) * 1.3
      local w = 1.5 + (1 - drift) * 0.55
      local a = 0.30 + 0.55 * (1 - drift)
      g.setColor(c[1], c[2] * 0.42, 0.04, a * 0.55)
      if g.polygon then
        g.polygon("fill",
          px, py - h,
          px + w, py + 1,
          px, py + 2.2,
          px - w, py + 1)
      else
        g.circle("fill", px, py, w + 0.4)
      end
      g.setColor(1.00, 0.78, 0.22, a)
      g.circle("fill", px, py + 0.3, 1.15)
      g.setColor(1, 1, 1, a * 0.5)
      g.circle("fill", px, py, 0.45)
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
    onDone = spec.onDone,
    pinTip = spec.pinTip,
    followSide = spec.followSide,
    followEnt = spec.followEnt,
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
  for _, item in ipairs({
    { ent = session.playerMon, battler = battle and battle.player },
    { ent = session.enemyMon, battler = battle and battle.enemy },
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
    if ent and not ent.hidden and not ent._removed and not ent._fainting
        and ((status and STATUS_AURA[status]) or confused or leech) then
      local wx, wy = center(session, ent)
      if wx then
        local x = wx - camX
        local y = wy - camY
        if type(mapFn) == "function" then
          x, y = mapFn(x, y)
        end
        if status and STATUS_AURA[status] then
          drawStatusAura(g, x, y, status, phase)
        end
        if confused then
          drawStatusAura(g, x, y, "CNF", phase)
        end
        if leech then
          drawStatusAura(g, x, y, "LEECH", phase)
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
  return spawn(session, {
    kind = "effect",
    style = "contact",
    glitz = glitz,
    sx = x, sy = y, ex = x, ey = y,
    duration = 0.26,
    arc = 0,
    color = fx.color or TYPE_COLORS[fx.moveType],
  })
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

  if fx.style == "seed" then
    local sx, sy = center(session, fromEnt)
    if not sx then
      sx, sy = ex, ey
    end
    return spawn(session, {
      kind = "effect",
      style = "seed",
      glitz = fx.glitz or "leaf",
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = fx.duration or 0.58,
      arc = 8,
      color = fx.color or TYPE_COLORS.GRASS,
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

local function trainerOrigin(session, side)
  local home = session and session.grid and session.grid.home
  local slot = home and ((side == "player") and home.playerTrainer or home.enemyTrainer)
  if slot then
    local sx, sy = Coords.padCenterPx(session.grid, slot.u, slot.v)
    return sx, sy - 7
  end
  if side == "player" then
    return center(session, session.playerMon)
  end
  -- Trainer battles keep session.foe parked on the enemy edge.
  local foe = session and session.foe
  if foe and type(foe.px) == "number" then
    return foe.px + 8, foe.py
  end
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
  local ex, ey = center(session, target)
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
    pinTip = true,
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
    if p.pinTip then
      -- Recall laser: tip locked on the mon that was recalled, not whichever
      -- battler currently occupies that side (send-out would steal the beam).
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
