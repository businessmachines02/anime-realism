-- Field battle — nearby trainer spectators.
--
-- When a FIELD fight starts, trainer NPCs within a Chebyshev radius of the
-- fight mid walk to a free watching tile and face the mons. Soft pixel lerps
-- (same pattern as engaged trainers) because the overworld update is frozen
-- under the battle stack. Teardown restores each spectator's pre-fight pose.
-- Uncommon async shoutouts draw as floating world toasts (never battle queue).

local Coords = require("coords")

local Spectators = {}

-- ~4-tile radius around the fight mid (9×9 search window).
Spectators.RADIUS = 4
Spectators.MAX = 4
Spectators.STEP_SPEED = 48
-- Prefer watching from just outside the tight formation rather than mid-pad.
Spectators.RIM_MIN = 2
Spectators.RIM_MAX = 5
-- Shoutouts: rare, non-blocking, one at a time.
Spectators.SHOUT_CHECK = 2.8
Spectators.SHOUT_CHANCE = 0.10
Spectators.SHOUT_COOLDOWN = 6.0
Spectators.SHOUT_HOLD = 2.4

local SHOUTS = {
  "%s:\nWhoa!",
  "%s:\nNice one!",
  "%s:\nGo for it!",
  "%s:\nWhat a move!",
  "%s:\nIncredible!",
  "%s:\nDon't blink!",
  "%s:\nSo cool!",
  "%s:\nI can't look\naway!",
  "%s:\nMy turn next!",
  "%s:\nTeach me that!",
}

local function rr(...)
  local random = (love and love.math and love.math.random) or math.random
  return random(...)
end

local function chebyshev(ax, ay, bx, by)
  return math.max(math.abs((ax or 0) - (bx or 0)), math.abs((ay or 0) - (by or 0)))
end

local function faceToward(ent, tx, ty)
  if not ent then
    return
  end
  local dx = (tx or 0) - (ent.cellX or 0)
  local dy = (ty or 0) - (ent.cellY or 0)
  if math.abs(dx) >= math.abs(dy) then
    ent.facing = dx >= 0 and "right" or "left"
  else
    ent.facing = dy >= 0 and "down" or "up"
  end
end

local function battleFocus(session)
  local p, e = session.playerMon, session.enemyMon
  if p and e and not p._removed and not e._removed then
    return math.floor(((p.cellX or 0) + (e.cellX or 0)) / 2),
      math.floor(((p.cellY or 0) + (e.cellY or 0)) / 2)
  end
  if p and not p._removed then
    return p.cellX or session.midX, p.cellY or session.midY
  end
  if e and not e._removed then
    return e.cellX or session.midX, e.cellY or session.midY
  end
  return session.midX or 0, session.midY or 0
end

local function isTrainerNpc(e)
  if not e then
    return false
  end
  local def = e.def
  return e.trainer == true
    or e.trainerClass ~= nil
    or (def and (def.trainerClass ~= nil or def.trainer == true))
end

local function displayName(e)
  if not e then
    return "TRAINER"
  end
  if type(e.name) == "string" and e.name ~= "" then
    return e.name
  end
  local def = e.def
  if def and type(def.name) == "string" and def.name ~= "" then
    return def.name
  end
  if type(e.id) == "string" and e.id ~= "" then
    return tostring(e.id):gsub("^%l", string.upper)
  end
  return "TRAINER"
end

local function isFieldActor(e)
  return e and (e._arFieldBattler or e._fbv or e._arFieldTrainerId
    or e._arFieldSpectator)
end

--- Reserved world cells: formation + other spectator claims.
local function reservedCells(session)
  local reserved = {}
  local plan = session.plan or {}
  local function mark(wx, wy)
    if wx ~= nil and wy ~= nil then
      reserved[Coords.key(wx, wy)] = true
    end
  end
  mark(plan.pCellX, plan.pCellY)
  mark(plan.eCellX, plan.eCellY)
  mark(plan.pMonX, plan.pMonY)
  mark(plan.eMonX, plan.eMonY)
  mark(plan.midX, plan.midY)
  -- Also reserve current engaged trainer pads if they differ.
  local home = session.grid and session.grid.home
  if home and session.grid then
    for _, slot in pairs(home) do
      if slot and slot.u ~= nil then
        local wx, wy = Coords.padToWorld(session.grid, slot.u, slot.v)
        mark(wx, wy)
      end
    end
  end
  local specs = session.spectators
  if type(specs) == "table" then
    for i = 1, #specs do
      local s = specs[i]
      if s and s.spotX ~= nil then
        mark(s.spotX, s.spotY)
      end
    end
  end
  return reserved
end

local function cellOccupied(ow, wx, wy, ignore)
  local entities = ow and ow.entities
  if type(entities) ~= "table" then
    return false
  end
  for i = 1, #entities do
    local e = entities[i]
    if e and e ~= ignore and not e.passable and not e.hidden and not e._removed then
      if (e.cellX == wx and e.cellY == wy)
        or (e.targetX == wx and e.targetY == wy)
        or (e._specTargetX == wx and e._specTargetY == wy) then
        return true
      end
    end
  end
  return false
end

local function cellFree(map, ow, session, wx, wy, ignore, reserved)
  local Survey = session._deps and session._deps.Survey
  if Survey and type(Survey.cellAllowed) == "function" then
    if not Survey.cellAllowed(map, wx, wy) then
      return false
    end
  elseif map and type(map.isWalkableCell) == "function" then
    local ok, walk = pcall(map.isWalkableCell, map, wx, wy)
    if not (ok and walk) then
      return false
    end
  end
  if reserved and reserved[Coords.key(wx, wy)] then
    return false
  end
  if cellOccupied(ow, wx, wy, ignore) then
    return false
  end
  return true
end

--- Score a watching tile: close to the NPC, near the fight rim, facing mid.
function Spectators.scoreSpot(npc, wx, wy, midX, midY)
  local fromNpc = chebyshev(npc.cellX, npc.cellY, wx, wy)
  local fromMid = chebyshev(wx, wy, midX, midY)
  local score = fromNpc * 4 + fromMid * 2
  -- Prefer the watching ring (not on top of the duel, not too far).
  if fromMid < Spectators.RIM_MIN then
    score = score + 18
  elseif fromMid > Spectators.RIM_MAX then
    score = score + (fromMid - Spectators.RIM_MAX) * 3
  else
    score = score - 4
  end
  return score
end

function Spectators.pickSpot(map, ow, session, npc, reserved)
  if not npc then
    return nil, nil
  end
  local midX = session.midX or 0
  local midY = session.midY or 0
  reserved = reserved or reservedCells(session)
  local bestX, bestY, bestScore = nil, nil, nil
  local radius = Spectators.RADIUS + 1
  for dx = -radius, radius do
    for dy = -radius, radius do
      local wx, wy = midX + dx, midY + dy
      if cellFree(map, ow, session, wx, wy, npc, reserved) then
        local score = Spectators.scoreSpot(npc, wx, wy, midX, midY)
        if not bestScore or score < bestScore then
          bestScore, bestX, bestY = score, wx, wy
        end
      end
    end
  end
  -- Fall back: stay put if the current tile is already fine.
  if not bestX then
    local cx, cy = npc.cellX, npc.cellY
    if cx ~= nil and cellFree(map, ow, session, cx, cy, npc, reserved) then
      return cx, cy
    end
    return nil, nil
  end
  return bestX, bestY
end

function Spectators.gather(ow, session)
  local out = {}
  if not (ow and session) then
    return out
  end
  local player = ow.player
  local foe = session.foe
  local midX = session.midX or 0
  local midY = session.midY or 0
  local radius = Spectators.RADIUS
  local Lifecycle = session._deps and session._deps.Lifecycle
  local seen = {}

  local function consider(e)
    if not e or seen[e] or e == player or e == foe then
      return
    end
    if e.hidden or e._removed or e.passable then
      return
    end
    if isFieldActor(e) or e._arFieldParked then
      return
    end
    if Lifecycle and type(Lifecycle.isOverworldFollower) == "function"
      and Lifecycle.isOverworldFollower(e, player, foe) then
      return
    end
    if not isTrainerNpc(e) then
      return
    end
    local d = chebyshev(e.cellX, e.cellY, midX, midY)
    if d > radius then
      return
    end
    seen[e] = true
    out[#out + 1] = { ent = e, dist = d }
  end

  for _, pool in ipairs({ ow.entities or {}, ow.npcs or {} }) do
    for i = 1, #pool do
      consider(pool[i])
    end
  end
  if type(ow.npcPool) == "table" then
    for _, e in pairs(ow.npcPool) do
      consider(e)
    end
  end

  table.sort(out, function(a, b)
    return (a.dist or 0) < (b.dist or 0)
  end)
  while #out > Spectators.MAX do
    out[#out] = nil
  end
  return out
end

local function occupyPadIfMapped(session, Grid, npc, wx, wy, occId)
  local grid = session.grid
  if not (grid and Grid and wx ~= nil and type(Coords.worldToPad) == "function") then
    return
  end
  local u, v = Coords.worldToPad(grid, wx, wy)
  if not Coords.inPad(grid, u, v) then
    npc.padU, npc.padV = nil, nil
    return
  end
  if type(Grid.occupy) == "function" then
    Grid.occupy(grid, occId, u, v)
  end
  npc.padU, npc.padV = u, v
end

local function beginStep(npc, nx, ny)
  local cx, cy = npc.cellX or 0, npc.cellY or 0
  local dx, dy = nx - cx, ny - cy
  if dx == 0 and dy == 0 then
    return false
  end
  -- One cardinal step at a time.
  if math.abs(dx) >= math.abs(dy) then
    nx = cx + (dx > 0 and 1 or -1)
    ny = cy
  else
    nx = cx
    ny = cy + (dy > 0 and 1 or -1)
  end
  npc._stepTX, npc._stepTY = nx * 16, ny * 16
  npc._specTargetX, npc._specTargetY = nx, ny
  npc.targetX, npc.targetY = nx, ny
  if math.abs(nx - cx) >= math.abs(ny - cy) then
    npc.facing = (nx - cx) >= 0 and "right" or "left"
  else
    npc.facing = (ny - cy) >= 0 and "down" or "up"
  end
  npc.moving = true
  return true
end

local function stepLerp(npc, dt)
  if not (npc and npc._stepTX and npc._stepTY) then
    return false
  end
  local px, py = npc.px or 0, npc.py or 0
  local dx = npc._stepTX - px
  local dy = npc._stepTY - py
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 1.5 then
    npc.px, npc.py = npc._stepTX, npc._stepTY
    if npc._specTargetX ~= nil then
      npc.cellX, npc.cellY = npc._specTargetX, npc._specTargetY
    end
    npc._stepTX, npc._stepTY = nil, nil
    npc._specTargetX, npc._specTargetY = nil, nil
    npc.targetX, npc.targetY = nil, nil
    npc.moving = false
    return true
  end
  local step = math.min(dist, Spectators.STEP_SPEED * (dt or 1 / 60))
  npc.px = px + dx / dist * step
  npc.py = py + dy / dist * step
  return false
end

function Spectators.begin(session, battle, deps)
  if not session then
    return 0
  end
  deps = deps or session._deps
  session._deps = deps or session._deps
  local ow = battle and battle.game and battle.game.overworld
  if not ow then
    session.spectators = {}
    return 0
  end
  local Layout = deps and deps.Layout
  local Grid = deps and deps.Grid
  local map = ow.map
  local gathered = Spectators.gather(ow, session)
  local reserved = reservedCells(session)
  local list = {}

  for i = 1, #gathered do
    local ent = gathered[i].ent
    local spotX, spotY = Spectators.pickSpot(map, ow, session, ent, reserved)
    if spotX ~= nil then
      reserved[Coords.key(spotX, spotY)] = true
      local pose = Layout and Layout.copyPose and Layout.copyPose(ent) or nil
      local occId = "ar_field_spec_" .. tostring(i)
      ent._arFieldSpectator = true
      ent._arFieldSpectatorId = occId
      ent.frozen = true
      ent.wanders = false
      ent.moving = false
      occupyPadIfMapped(session, Grid, ent, spotX, spotY, occId)
      list[#list + 1] = {
        ent = ent,
        pose = pose,
        spotX = spotX,
        spotY = spotY,
        occId = occId,
        delay = 0.25 + (#list) * 0.18,
        arrived = (ent.cellX == spotX and ent.cellY == spotY),
      }
      if list[#list].arrived then
        local fx, fy = battleFocus(session)
        faceToward(ent, fx, fy)
      end
    end
  end

  session.spectators = list
  session._specShoutCD = 1.5 + rr() * 2
  session._specShout = nil
  return #list
end

function Spectators.tick(session, dt, deps)
  local list = session and session.spectators
  if type(list) ~= "table" or #list == 0 then
    return
  end
  deps = deps or session._deps
  local Grid = deps and deps.Grid
  dt = dt or 1 / 60

  for i = 1, #list do
    local s = list[i]
    local ent = s and s.ent
    if ent and not ent._removed then
      if s.delay and s.delay > 0 then
        s.delay = s.delay - dt
      elseif not s.arrived then
        if ent._stepTX then
          if stepLerp(ent, dt) then
            occupyPadIfMapped(session, Grid, ent, ent.cellX, ent.cellY, s.occId)
          end
        elseif ent.cellX == s.spotX and ent.cellY == s.spotY then
          s.arrived = true
          ent.moving = false
          local fx, fy = battleFocus(session)
          faceToward(ent, fx, fy)
        else
          beginStep(ent, s.spotX, s.spotY)
        end
      else
        -- Keep facing the live duel while idle.
        s._faceAcc = (s._faceAcc or 0) + dt
        if s._faceAcc >= 0.35 then
          s._faceAcc = 0
          if not ent._stepTX then
            local fx, fy = battleFocus(session)
            faceToward(ent, fx, fy)
          end
        end
      end
    end
  end

  -- Async shoutouts (non-blocking overlay).
  if session._specShout then
    session._specShout.t = (session._specShout.t or 0) - dt
    if session._specShout.t <= 0 then
      session._specShout = nil
      session._specShoutCD = Spectators.SHOUT_COOLDOWN + rr() * 3
    end
  else
    session._specShoutCD = (session._specShoutCD or Spectators.SHOUT_CHECK) - dt
    if session._specShoutCD <= 0 then
      session._specShoutCD = Spectators.SHOUT_CHECK + rr() * 1.5
      local ready = {}
      for i = 1, #list do
        local s = list[i]
        if s and s.arrived and s.ent and not s.ent._removed and not s.ent._stepTX then
          ready[#ready + 1] = s
        end
      end
      if #ready > 0 and rr() <= Spectators.SHOUT_CHANCE then
        local pick = ready[rr(1, #ready)]
        local line = SHOUTS[rr(1, #SHOUTS)]
        local text = string.format(line, displayName(pick.ent))
        session._specShout = {
          ent = pick.ent,
          text = text,
          t = Spectators.SHOUT_HOLD,
        }
      end
    end
  end
end

function Spectators.finish(session, deps)
  local list = session and session.spectators
  if type(list) ~= "table" then
    return
  end
  deps = deps or session._deps
  local Layout = deps and deps.Layout
  local Grid = deps and deps.Grid
  for i = 1, #list do
    local s = list[i]
    local ent = s and s.ent
    if ent then
      ent._stepTX, ent._stepTY = nil, nil
      ent._specTargetX, ent._specTargetY = nil, nil
      ent.targetX, ent.targetY = nil, nil
      ent.moving = false
      ent._arFieldSpectator = nil
      ent._arFieldSpectatorId = nil
      if Layout and s.pose then
        Layout.applyPose(ent, s.pose)
      end
    end
  end
  session.spectators = nil
  session._specShout = nil
  session._specShoutCD = nil
end

local function drawToast(g, text, sx, sy)
  if not (g and text and type(g.print) == "function") then
    return
  end
  local lines = {}
  for line in tostring(text):gmatch("[^\n]+") do
    lines[#lines + 1] = line
  end
  if #lines == 0 then
    return
  end
  local pad = 2
  local lineH = 8
  local w = 0
  for i = 1, #lines do
    local lw = 0
    if type(g.getFont) == "function" then
      local font = g.getFont()
      if font and type(font.getWidth) == "function" then
        lw = font:getWidth(lines[i])
      end
    end
    if lw == 0 then
      lw = #lines[i] * 4
    end
    if lw > w then
      w = lw
    end
  end
  local h = #lines * lineH
  local x = math.floor(sx - w / 2 - pad)
  local y = math.floor(sy - h - pad * 2 - 2)
  if type(g.setColor) == "function" then
    g.setColor(1, 1, 1, 0.92)
  end
  if type(g.rectangle) == "function" then
    g.rectangle("fill", x, y, w + pad * 2, h + pad * 2)
  end
  if type(g.setColor) == "function" then
    g.setColor(0.15, 0.15, 0.18, 1)
  end
  for i = 1, #lines do
    g.print(lines[i], x + pad, y + pad + (i - 1) * lineH)
  end
  if type(g.setColor) == "function" then
    g.setColor(1, 1, 1, 1)
  end
end

function Spectators.draw(session, camX, camY, ren)
  local shout = session and session._specShout
  if not shout or not shout.ent then
    return
  end
  -- World-canvas toast (same space as floor/cover overlays).
  local ent = shout.ent
  local sx = (ent.px or 0) - (camX or 0) + 8
  local sy = (ent.py or 0) - (camY or 0) - 4
  local g = love and love.graphics
  drawToast(g, shout.text, sx, sy)
end

return Spectators
