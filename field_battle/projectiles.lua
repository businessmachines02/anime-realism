-- Field battle — world-space projectiles for hybrid flat/voxel maps.
--
-- Simulated in world pixels; painted on the battle UI overlay with
-- world→UI mapping (same as HP bars) so FX survive 3D/world overrides.
-- Kept off ow.entities: Dramatic Shape's voxel pass wedges on nil sprites.
--
-- Movepool: named Gen1 moves + type defaults pick style / glitz. Persistent
-- PAR / FRZ / PSN auras are drawn around live field sprites each frame.

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
  ICE_BEAM = { style = "beam", glitz = "frost" },
  AURORA_BEAM = { style = "beam", glitz = "frost" },
  PSYBEAM = { style = "beam", glitz = "psy" },
  THUNDERBOLT = { style = "beam", glitz = "bolt" },
  THUNDERSHOCK = { style = "beam", glitz = "bolt", duration = 0.22 },
  THUNDER = { style = "bolt", duration = 0.38 },
  FLAMETHROWER = { style = "stream", glitz = "flame", duration = 0.40 },
  FIRE_BLAST = { style = "area", glitz = "flame", radius = 24, duration = 0.50 },
  EMBER = { style = "orb", glitz = "flame", arc = 10 },
  FIRE_SPIN = { style = "spiral", glitz = "flame", duration = 0.48 },
  HYDRO_PUMP = { style = "stream", glitz = "bubble", duration = 0.40 },
  WATER_GUN = { style = "orb", glitz = "bubble" },
  BUBBLEBEAM = { style = "stream", glitz = "bubble" },
  BUBBLE = { style = "orb", glitz = "bubble", arc = 12 },
  SURF = { style = "wave", duration = 0.48, radius = 22 },
  BLIZZARD = { style = "area", glitz = "frost", radius = 22 },
  PSYCHIC = { style = "spiral", glitz = "psy", duration = 0.50 },
  CONFUSION = { style = "orb", glitz = "psy", arc = 14 },
  DREAM_EATER = { style = "drain", glitz = "psy", duration = 0.52 },
  MEGA_DRAIN = { style = "drain", glitz = "leaf", duration = 0.48 },
  GIGA_DRAIN = { style = "drain", glitz = "leaf", duration = 0.52 },
  ABSORB = { style = "drain", glitz = "leaf", duration = 0.42 },
  RAZOR_LEAF = { style = "multi", glitz = "leaf", duration = 0.36 },
  PETAL_DANCE = { style = "multi", glitz = "leaf", duration = 0.44 },
  VINE_WHIP = { style = "stream", glitz = "leaf" },
  SLUDGE = { style = "orb", glitz = "blob", arc = 9 },
  SLUDGE_BOMB = { style = "orb", glitz = "blob", arc = 12 },
  ACID = { style = "stream", glitz = "blob" },
  SMOG = { style = "area", glitz = "blob", radius = 16 },
  TOXIC = { style = "status", glitz = "blob", duration = 0.55 },
  EARTHQUAKE = { style = "area", glitz = "quake", radius = 22 },
  FISSURE = { style = "area", glitz = "quake", radius = 18 },
  ROCK_SLIDE = { style = "area", glitz = "rock", radius = 20 },
  ROCK_THROW = { style = "orb", glitz = "rock", arc = 16 },
  EXPLOSION = { style = "area", glitz = "burst", radius = 28, duration = 0.55 },
  SELFDESTRUCT = { style = "area", glitz = "burst", radius = 26, duration = 0.52 },
  SWIFT = { style = "multi", glitz = "star", duration = 0.38 },
  TRI_ATTACK = { style = "multi", glitz = "tri", duration = 0.40 },
  NIGHT_SHADE = { style = "beam", glitz = "ghost" },
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
}

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

local function drawMove(g, p, x, y)
  local c = p.color or { 0.92, 0.92, 1.00 }
  local glitz = p.glitz or "orb"
  local trail = trailPoints(p, x, y, (glitz == "flame" or glitz == "bubble") and 5 or 3, 4)

  if glitz == "flame" then
    for i = 1, #trail do
      local tp = trail[i]
      local r = 5 - (i - 1) * 0.7
      g.setColor(c[1], c[2] * 0.55, 0.05, 0.55 * tp.a)
      g.circle("fill", tp.x, tp.y - (i - 1), r)
    end
    g.setColor(1, 0.92, 0.45, 0.95)
    g.circle("fill", x, y, 2.5)
    return
  end

  if glitz == "bubble" then
    for i = 1, #trail do
      local tp = trail[i]
      local r = 3.5 - (i - 1) * 0.35
      g.setColor(c[1], c[2], c[3], 0.35 * tp.a)
      g.circle("line", tp.x, tp.y + math.sin((p.age or 0) * 18 + i) * 1.2, r)
      g.setColor(1, 1, 1, 0.55 * tp.a)
      g.circle("fill", tp.x - 1, tp.y - 1, 1)
    end
    g.setColor(c[1], c[2], c[3], 0.85)
    g.circle("fill", x, y, 3.5)
    g.setColor(1, 1, 1, 0.9)
    g.circle("fill", x - 1, y - 1, 1.2)
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
    if glitz == "bolt" then
      local mx = (ox + x) * 0.5 + math.sin((p.age or 0) * 40) * 3
      local my = (oy + y) * 0.5 + math.cos((p.age or 0) * 36) * 2
      g.setColor(c[1], c[2], c[3], 0.4)
      g.setLineWidth(thick)
      g.line(ox, oy, mx, my)
      g.line(mx, my, x, y)
      g.setColor(1, 1, 1, 0.95)
      g.setLineWidth(2)
      g.line(ox, oy, mx, my)
      g.line(mx, my, x, y)
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
  elseif p.style == "bolt" then
    -- Vertical thunder strike onto the target.
    local top = y - 28 + t * 8
    local mid = y - 12
    local jx = math.sin((p.age or 0) * 50) * 4
    g.setColor(c[1], c[2], c[3], 0.85 * (1 - t * 0.4))
    g.setLineWidth(3)
    g.line(x + jx, top, x - jx, mid)
    g.line(x - jx, mid, x, y)
    g.setColor(1, 1, 1, 0.9 * (1 - t))
    g.setLineWidth(1)
    g.line(x + jx * 0.5, top, x, y)
    g.setColor(c[1], c[2], c[3], 0.35 * (1 - t))
    g.circle("fill", x, y, 6 + t * 8)
  elseif p.style == "area" then
    local radius = 3 + math.sin(t * math.pi) * (p.radius or 18)
    g.setColor(c[1], c[2], c[3], 0.30 * (1 - t))
    g.circle("fill", x, y, radius)
    g.setColor(c[1], c[2], c[3], 0.9 * (1 - t))
    g.setLineWidth(2)
    g.circle("line", x, y, radius)
    if glitz == "quake" then
      for i = 1, 3 do
        local a = t * math.pi * 2 + i * 2.1
        g.line(x + math.cos(a) * radius * 0.4, y + math.sin(a) * 2,
          x + math.cos(a) * radius, y + math.sin(a) * 3)
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
  elseif p.style == "spiral" then
    for i = 1, 8 do
      local a = t * math.pi * 5 + i * 0.7
      local r = 3 + i * 1.6 * (0.35 + 0.65 * math.sin(t * math.pi))
      g.setColor(c[1], c[2], c[3], 0.85 * (1 - t * 0.5))
      g.circle("fill", x + math.cos(a) * r, y + math.sin(a) * r, 2)
    end
    g.setColor(1, 1, 1, 0.55 * (1 - t))
    g.circle("line", x, y, 5 + t * 8)
  elseif p.style == "stream" then
    -- Traveling stream painted as a thick beam segment that follows px/py.
    local backX = x - (p.dirX or 0) * 14
    local backY = y - (p.dirY or 0) * 14
    g.setColor(c[1], c[2], c[3], 0.4)
    g.setLineWidth(6)
    g.line(backX, backY, x, y)
    g.setColor(1, 1, 1, 0.85)
    g.setLineWidth(2)
    g.line(backX, backY, x, y)
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
    age = 0,
    duration = spec.duration or 0.36,
    hold = spec.hold or 0,
    arc = spec.arc or 8,
    color = spec.color,
    style = spec.style,
    glitz = spec.glitz,
    radius = spec.radius,
    onDone = spec.onDone,
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
    if ent and not ent.hidden and not ent._removed and status and STATUS_AURA[status] then
      local wx, wy = center(session, ent)
      if wx then
        local x = wx - camX
        local y = wy - camY
        if type(mapFn) == "function" then
          x, y = mapFn(x, y)
        end
        drawStatusAura(g, x, y, status, phase)
      end
    end
  end
  g.setColor(1, 1, 1, 1)
  if g.setLineWidth then
    g.setLineWidth(1)
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

  if fx.style == "area" or fx.style == "wave" or fx.style == "bolt"
      or fx.style == "spiral" or fx.style == "multi" then
    return spawn(session, {
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
  local target = opts.target == "foe"
    and ((side == "player") and session.enemyMon or session.playerMon)
    or ((side == "player") and session.playerMon or session.enemyMon)
  local x, y = center(session, target)
  if not x then return nil end
  local fx = resolveFx(opts)
  return spawn(session, {
    kind = "effect",
    style = "status",
    glitz = fx.glitz,
    sx = x, sy = y, ex = x, ey = y,
    duration = 0.48,
    arc = 0,
    color = fx.color or TYPE_COLORS[fx.moveType],
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
    local t = math.min(1, p.age / math.max(0.01, p.duration))
    p.px = p.sx + (p.ex - p.sx) * t
    p.py = p.sy + (p.ey - p.sy) * t - math.sin(t * math.pi) * (p.arc or 0)
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
