-- Field battle — scatter nearby overworld wildlife.
--
-- Roaming Wilds of Kanto mons (overworldWildSpawn) freeze under ow.engaging.
-- Soft-walk them away from the fight mid so they don't stand in the duel,
-- then restore poses on finish. Followers, FIELD battlers, ambient town
-- décor, and trainers are never recruited.

local Coords = require("coords")

local Wildlife = {}

-- Slightly larger than spectator radius so mons near the pad leave.
Wildlife.RADIUS = 7
Wildlife.MAX = 10
Wildlife.STEP_SPEED = 56
-- Prefer fleeing at least this far from mid.
Wildlife.FLEE_MIN = 5
Wildlife.FLEE_MAX = 9

local function chebyshev(ax, ay, bx, by)
  return math.max(math.abs((ax or 0) - (bx or 0)), math.abs((ay or 0) - (by or 0)))
end

local function isFieldActor(e)
  return e and (e._arFieldBattler or e._fbv or e._arFieldCover
    or e._arFieldTrainerId or e._arFieldSpectator or e._arFieldWildlife)
end

function Wildlife.isRoaming(e, player, foe, Lifecycle)
  if not e or e == player or e == foe then
    return false
  end
  if e.hidden or e._removed then
    return false
  end
  if isFieldActor(e) or e._arFieldParked then
    return false
  end
  if Lifecycle and type(Lifecycle.isOverworldFollower) == "function"
    and Lifecycle.isOverworldFollower(e, player, foe) then
    return false
  end
  -- Ambient town décor stays put.
  if e.wildsAmbientPokemon == true then
    return false
  end
  if e.overworldWildSpawn ~= true and e._owwildEntity ~= true then
    return false
  end
  -- Hidden grass/cave markers with no sprite: leave alone.
  if e.hiddenEncounter and e.visibleSprite == false then
    return false
  end
  if e.state == "REMOVED" or e.state == "IN_BATTLE" or e.state == "in_battle" then
    return false
  end
  return true
end

local function reservedCells(session)
  local reserved = {}
  local function mark(wx, wy)
    if wx ~= nil and wy ~= nil then
      reserved[Coords.key(wx, wy)] = true
    end
  end
  local plan = session.plan or {}
  mark(plan.pCellX, plan.pCellY)
  mark(plan.eCellX, plan.eCellY)
  mark(plan.pMonX, plan.pMonY)
  mark(plan.eMonX, plan.eMonY)
  mark(plan.midX, plan.midY)
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
  local wild = session.wildlife
  if type(wild) == "table" then
    for i = 1, #wild do
      local w = wild[i]
      if w and w.spotX ~= nil then
        mark(w.spotX, w.spotY)
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
    if e and e ~= ignore and not e.hidden and not e._removed then
      -- Wilds are passable but still occupy a cell visually; treat as blocking
      -- for scatter targets so two mons don't stack.
      if (e.cellX == wx and e.cellY == wy)
        or (e.targetX == wx and e.targetY == wy)
        or (e._wildTargetX == wx and e._wildTargetY == wy)
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

--- Prefer tiles farther from the fight mid (flee outward).
function Wildlife.scoreSpot(ent, wx, wy, midX, midY)
  local fromMid = chebyshev(wx, wy, midX, midY)
  local fromEnt = chebyshev(ent.cellX, ent.cellY, wx, wy)
  -- Maximize distance from mid; lightly prefer short travel.
  local score = -fromMid * 6 + fromEnt * 2
  if fromMid < Wildlife.FLEE_MIN then
    score = score + 40
  elseif fromMid > Wildlife.FLEE_MAX then
    score = score + (fromMid - Wildlife.FLEE_MAX) * 2
  end
  return score
end

function Wildlife.pickSpot(map, ow, session, ent, reserved)
  if not ent then
    return nil, nil
  end
  local midX = session.midX or 0
  local midY = session.midY or 0
  reserved = reserved or reservedCells(session)
  local cx, cy = ent.cellX or midX, ent.cellY or midY
  -- Prefer fleeing along the vector away from mid.
  local awayX = cx - midX
  local awayY = cy - midY
  if awayX == 0 and awayY == 0 then
    awayX, awayY = 1, 0
  end
  local bestX, bestY, bestScore = nil, nil, nil
  local radius = Wildlife.FLEE_MAX
  for dx = -radius, radius do
    for dy = -radius, radius do
      local wx, wy = midX + dx, midY + dy
      local fromMid = chebyshev(wx, wy, midX, midY)
      if fromMid >= Wildlife.FLEE_MIN and fromMid <= Wildlife.FLEE_MAX then
        -- Prefer the half-plane away from mid relative to the mon's start.
        local dot = (wx - midX) * awayX + (wy - midY) * awayY
        if dot >= 0 and cellFree(map, ow, session, wx, wy, ent, reserved) then
          local score = Wildlife.scoreSpot(ent, wx, wy, midX, midY)
          if not bestScore or score < bestScore then
            bestScore, bestX, bestY = score, wx, wy
          end
        end
      end
    end
  end
  -- Fallback: any free flee ring tile.
  if not bestX then
    for dx = -radius, radius do
      for dy = -radius, radius do
        local wx, wy = midX + dx, midY + dy
        local fromMid = chebyshev(wx, wy, midX, midY)
        if fromMid >= Wildlife.FLEE_MIN
          and cellFree(map, ow, session, wx, wy, ent, reserved) then
          local score = Wildlife.scoreSpot(ent, wx, wy, midX, midY)
          if not bestScore or score < bestScore then
            bestScore, bestX, bestY = score, wx, wy
          end
        end
      end
    end
  end
  return bestX, bestY
end

function Wildlife.gather(ow, session)
  local out = {}
  if not (ow and session) then
    return out
  end
  local player = ow.player
  local foe = session.foe
  local midX = session.midX or 0
  local midY = session.midY or 0
  local radius = Wildlife.RADIUS
  local Lifecycle = session._deps and session._deps.Lifecycle
  local seen = {}

  local function consider(e)
    if not e or seen[e] then
      return
    end
    if not Wildlife.isRoaming(e, player, foe, Lifecycle) then
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

  table.sort(out, function(a, b)
    return (a.dist or 0) < (b.dist or 0)
  end)
  while #out > Wildlife.MAX do
    out[#out] = nil
  end
  return out
end

local function beginStep(ent, nx, ny)
  local cx, cy = ent.cellX or 0, ent.cellY or 0
  local dx, dy = nx - cx, ny - cy
  if dx == 0 and dy == 0 then
    return false
  end
  if math.abs(dx) >= math.abs(dy) then
    nx = cx + (dx > 0 and 1 or -1)
    ny = cy
  else
    nx = cx
    ny = cy + (dy > 0 and 1 or -1)
  end
  ent._stepTX, ent._stepTY = nx * 16, ny * 16
  ent._wildTargetX, ent._wildTargetY = nx, ny
  ent.targetX, ent.targetY = nx, ny
  if math.abs(nx - cx) >= math.abs(ny - cy) then
    ent.facing = (nx - cx) >= 0 and "right" or "left"
  else
    ent.facing = (ny - cy) >= 0 and "down" or "up"
  end
  ent.moving = true
  return true
end

local function stepLerp(ent, dt)
  if not (ent and ent._stepTX and ent._stepTY) then
    return false
  end
  local px, py = ent.px or 0, ent.py or 0
  local dx = ent._stepTX - px
  local dy = ent._stepTY - py
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 1.5 then
    ent.px, ent.py = ent._stepTX, ent._stepTY
    if ent._wildTargetX ~= nil then
      ent.cellX, ent.cellY = ent._wildTargetX, ent._wildTargetY
    end
    ent._stepTX, ent._stepTY = nil, nil
    ent._wildTargetX, ent._wildTargetY = nil, nil
    ent.targetX, ent.targetY = nil, nil
    ent.moving = false
    return true
  end
  local step = math.min(dist, Wildlife.STEP_SPEED * (dt or 1 / 60))
  ent.px = px + dx / dist * step
  ent.py = py + dy / dist * step
  return false
end

function Wildlife.begin(session, battle, deps)
  if not session then
    return 0
  end
  deps = deps or session._deps
  session._deps = deps or session._deps
  local ow = battle and battle.game and battle.game.overworld
  if not ow then
    session.wildlife = {}
    return 0
  end
  local Layout = deps and deps.Layout
  local map = ow.map
  local gathered = Wildlife.gather(ow, session)
  local reserved = reservedCells(session)
  local list = {}

  for i = 1, #gathered do
    local ent = gathered[i].ent
    local spotX, spotY = Wildlife.pickSpot(map, ow, session, ent, reserved)
    if spotX ~= nil then
      reserved[Coords.key(spotX, spotY)] = true
      local pose = Layout and Layout.copyPose and Layout.copyPose(ent) or nil
      ent._arFieldWildlife = true
      ent.frozen = true
      ent.wanders = false
      ent.moving = false
      -- Nudge Wilds AI into a held flee-ish state if present.
      if ent.behaviorState ~= nil and ent.behaviorState ~= "REMOVED" then
        ent._arFieldWildBehavior = ent.behaviorState
        ent.behaviorState = "fleeing"
      end
      list[#list + 1] = {
        ent = ent,
        pose = pose,
        spotX = spotX,
        spotY = spotY,
        delay = 0.08 + (#list) * 0.10,
        arrived = (ent.cellX == spotX and ent.cellY == spotY),
      }
    end
  end

  session.wildlife = list
  return #list
end

function Wildlife.tick(session, dt, deps)
  local list = session and session.wildlife
  if type(list) ~= "table" or #list == 0 then
    return
  end
  dt = dt or 1 / 60

  for i = 1, #list do
    local w = list[i]
    local ent = w and w.ent
    if ent and not ent._removed then
      if w.delay and w.delay > 0 then
        w.delay = w.delay - dt
      elseif not w.arrived then
        if ent._stepTX then
          stepLerp(ent, dt)
        elseif ent.cellX == w.spotX and ent.cellY == w.spotY then
          w.arrived = true
          ent.moving = false
        else
          beginStep(ent, w.spotX, w.spotY)
        end
      end
    end
  end
end

function Wildlife.finish(session, deps)
  local list = session and session.wildlife
  if type(list) ~= "table" then
    return
  end
  deps = deps or session._deps
  local Layout = deps and deps.Layout
  for i = 1, #list do
    local w = list[i]
    local ent = w and w.ent
    if ent then
      ent._stepTX, ent._stepTY = nil, nil
      ent._wildTargetX, ent._wildTargetY = nil, nil
      ent.targetX, ent.targetY = nil, nil
      ent.moving = false
      ent._arFieldWildlife = nil
      if ent._arFieldWildBehavior ~= nil then
        ent.behaviorState = ent._arFieldWildBehavior
        ent._arFieldWildBehavior = nil
      end
      if Layout and w.pose then
        Layout.applyPose(ent, w.pose)
      end
    end
  end
  session.wildlife = nil
end

return Wildlife
