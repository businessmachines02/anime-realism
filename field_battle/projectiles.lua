-- Field battle — world-space projectiles for hybrid flat/voxel maps.
--
-- Drawn from Lifecycle.drawWorldOverlay, not ow.entities. Dramatic Shape's
-- voxel pass calls e:pose() then sprite.def; a nil sprite wedges the 3D
-- canvas for the rest of the session. Spawned from battle.move_used /
-- ball_thrown cues via hooks.lua.

local Coords = require("coords")

local Projectiles = {}

local TYPE_COLORS = {
  FIRE = { 1.00, 0.34, 0.12 },
  WATER = { 0.20, 0.58, 1.00 },
  ELECTRIC = { 1.00, 0.88, 0.18 },
  GRASS = { 0.30, 0.82, 0.28 },
  ICE = { 0.52, 0.90, 1.00 },
  PSYCHIC = { 0.92, 0.34, 0.82 },
  GHOST = { 0.52, 0.36, 0.72 },
  POISON = { 0.66, 0.30, 0.78 },
  ROCK = { 0.66, 0.56, 0.34 },
  GROUND = { 0.72, 0.52, 0.28 },
}

local AREA_MOVES = {
  EARTHQUAKE = true, SURF = true, BLIZZARD = true, EXPLOSION = true,
  SELFDESTRUCT = true, ROCK_SLIDE = true, SWIFT = true,
}

local BEAM_TYPES = {
  ELECTRIC = true, ICE = true, PSYCHIC = true, GHOST = true,
}

local function center(session, ent)
  if not ent then
    return nil, nil
  end
  if session and session.grid and ent.padU ~= nil then
    local x, y = Coords.padCenterPx(session.grid, ent.padU, ent.padV)
    return x, y - 4
  end
  return (ent.px or ent.basePx or 0) + 8, (ent.py or ent.basePy or 0) + 4
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

local function drawMove(g, p, x, y)
  local c = p.color or { 0.92, 0.92, 1.00 }
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

local function drawEffect(g, p, x, y)
  local c = p.color or { 0.92, 0.92, 1.00 }
  local t = math.min(1, (p.age or 0) / math.max(0.01, p.duration or 1))
  if p.style == "beam" then
    g.setColor(c[1], c[2], c[3], 0.34)
    g.setLineWidth(5)
    g.line((p.sx or 0) - (p.camX or 0), (p.sy or 0) - (p.camY or 0), x, y)
    g.setColor(1, 1, 1, 0.9)
    g.setLineWidth(2)
    g.line((p.sx or 0) - (p.camX or 0), (p.sy or 0) - (p.camY or 0), x, y)
  elseif p.style == "area" then
    local radius = 3 + math.sin(t * math.pi) * (p.radius or 18)
    g.setColor(c[1], c[2], c[3], 0.30 * (1 - t))
    g.circle("fill", x, y, radius)
    g.setColor(c[1], c[2], c[3], 0.9 * (1 - t))
    g.setLineWidth(2)
    g.circle("line", x, y, radius)
  elseif p.style == "contact" then
    local reach = 3 + t * 9
    g.setColor(c[1], c[2], c[3], 1 - t)
    g.setLineWidth(2)
    g.line(x - reach, y + reach, x + reach, y - reach)
    g.line(x - reach * 0.6, y - reach, x + reach * 0.6, y + reach)
  elseif p.style == "status" then
    for i = 1, 4 do
      local a = t * math.pi * 4 + i * math.pi * 0.5
      local r = 5 + t * 7
      g.setColor(c[1], c[2], c[3], 1 - t * 0.45)
      g.circle("fill", x + math.cos(a) * r, y + math.sin(a) * r, 2)
    end
  elseif p.style == "heal" then
    for i = 1, 3 do
      local ox = (i - 2) * 5
      g.setColor(c[1], c[2], c[3], 1 - t)
      g.rectangle("fill", x + ox - 1, y + 7 - t * 18, 3, 7)
      g.rectangle("fill", x + ox - 3, y + 9 - t * 18, 7, 3)
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
  function p:draw(camX, camY)
    if self._removed or not (love and love.graphics) then
      return
    end
    local g = love.graphics
    self.camX, self.camY = camX or 0, camY or 0
    local x = (self.px or 0) - (camX or 0)
    local y = (self.py or 0) - (camY or 0)
    if self.kind == "ball" then
      drawBall(g, x, y)
    elseif self.kind == "effect" then
      drawEffect(g, self, x, y)
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

function Projectiles.draw(session, camX, camY)
  local list = session and session.projectiles
  if type(list) ~= "table" then
    return
  end
  for i = 1, #list do
    local p = list[i]
    if p and not p._removed and type(p.draw) == "function" then
      p:draw(camX, camY)
    end
  end
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
  local moveType = tostring(opts.moveType or ""):upper()
  local moveId = tostring(opts.moveId or ""):upper()
  local color = TYPE_COLORS[moveType]
  if AREA_MOVES[moveId] then
    return spawn(session, {
      kind = "effect",
      style = "area",
      sx = ex, sy = ey, ex = ex, ey = ey,
      duration = 0.45,
      arc = 0,
      radius = 20,
      color = color,
    })
  end
  if BEAM_TYPES[moveType] then
    return spawn(session, {
      kind = "effect",
      style = "beam",
      sx = sx, sy = sy, ex = ex, ey = ey,
      duration = 0.28,
      arc = 0,
      color = color,
    })
  end
  return spawn(session, {
    kind = "move",
    sx = sx, sy = sy,
    ex = ex, ey = ey,
    duration = 0.34,
    arc = 5,
    color = color,
  })
end

function Projectiles.contact(session, side, opts)
  opts = opts or {}
  local target = (side == "player") and session.enemyMon or session.playerMon
  local x, y = center(session, target)
  if not x then return nil end
  return spawn(session, {
    kind = "effect",
    style = "contact",
    sx = x, sy = y, ex = x, ey = y,
    duration = 0.24,
    arc = 0,
    color = TYPE_COLORS[tostring(opts.moveType or ""):upper()],
  })
end

function Projectiles.status(session, side, opts)
  opts = opts or {}
  local target = opts.target == "foe"
    and ((side == "player") and session.enemyMon or session.playerMon)
    or ((side == "player") and session.playerMon or session.enemyMon)
  local x, y = center(session, target)
  if not x then return nil end
  return spawn(session, {
    kind = "effect",
    style = "status",
    sx = x, sy = y, ex = x, ey = y,
    duration = 0.48,
    arc = 0,
    color = TYPE_COLORS[tostring(opts.moveType or ""):upper()],
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
