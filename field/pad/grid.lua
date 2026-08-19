-- Field battle — who is standing on which pad cell, and how they step.
--
-- The pad (u, v) is the real position. Pixels are just the drawing lerp
-- (Coords.padToPx). Occupancy (grid.occ) and walkability (from Survey)
-- decide whether a step is legal. Trainers may step aside when a mon
-- lands on or beside them.
--
-- u runs player → foe. v is the dodge / knock axis.
--
-- Where to look:
--   BUILD / QUERY     make a grid, occupy, is this cell free
--   PLACE / STEP      put a mon on a cell, take one step
--   FIGHT MOTION      dodge, close-the-gap, withdraw, knockback
--   COVER             tuck behind a prop or a wall
--   IDLE              roam near the foe after a close-in, or near home

local Coords = require("coords")

local Grid = {}

local CARDINALS = {
  { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
}

local function padKey(u, v)
  return Coords.key(u, v)
end

local function randomFn()
  return (love and love.math and love.math.random) or math.random
end

local function pickCell(list)
  if not list or #list == 0 then
    return nil
  end
  return list[randomFn()(1, #list)]
end

--- One cardinal step from a delta (the longer axis wins).
local function unitStep(deltaU, deltaV)
  local stepU = deltaU == 0 and 0 or (deltaU > 0 and 1 or -1)
  local stepV = deltaV == 0 and 0 or (deltaV > 0 and 1 or -1)
  if math.abs(deltaU) >= math.abs(deltaV) then
    stepV = 0
  else
    stepU = 0
  end
  return stepU, stepV
end

local function worldRectFromPlan(plan)
  if not plan then
    return { minX = 0, maxX = 0, minY = 0, maxY = 0 }
  end
  local lateral = plan.padHalfV or 1
  local minX = math.min(plan.pCellX or 0, plan.eCellX or 0)
  local maxX = math.max(plan.pCellX or 0, plan.eCellX or 0)
  local minY = math.min(plan.pCellY or 0, plan.eCellY or 0)
  local maxY = math.max(plan.pCellY or 0, plan.eCellY or 0)
  if (plan.sx or 0) ~= 0 then
    minY = (plan.midY or 0) - lateral
    maxY = (plan.midY or 0) + lateral
  else
    minX = (plan.midX or 0) - lateral
    maxX = (plan.midX or 0) + lateral
  end
  return { minX = minX, maxX = maxX, minY = minY, maxY = maxY }
end

local function padOf(grid, ent)
  if not ent then
    return 0, 0
  end
  if ent.padU ~= nil and ent.padV ~= nil then
    return ent.padU, ent.padV
  end
  -- Never treat world cells as pad indices; convert at the boundary.
  if grid and ent.cellX ~= nil and ent.cellY ~= nil then
    return Coords.worldToPad(grid, ent.cellX, ent.cellY)
  end
  return 0, 0
end

-- ---------------------------------------------------------------------------
-- BUILD / QUERY
-- ---------------------------------------------------------------------------

--- Sync cached world cell + pixel target from pad. Does not touch occupancy.
function Grid.syncPx(grid, ent)
  if not (grid and ent and ent.padU ~= nil) then
    return
  end
  local worldX, worldY = Coords.padToWorld(grid, ent.padU, ent.padV)
  ent.cellX, ent.cellY = worldX, worldY
  local pixelX, pixelY = Coords.padToPx(grid, ent.padU, ent.padV)
  ent.targetPx, ent.targetPy = pixelX, pixelY
end

--- Build a grid from arena generate result + layout plan (pad axes).
function Grid.build(arenaEdits, plan)
  local axisX = plan and plan.sx or 1
  local axisY = plan and plan.sy or 0
  local rect = (arenaEdits and arenaEdits.gridRect) or worldRectFromPlan(plan)
  local layout = (arenaEdits and arenaEdits.pad) or Coords.layoutPad(rect, axisX, axisY)
  local grid = {
    blocked = {},
    occ = {},
    props = {},
    home = {},
    walkable = arenaEdits and arenaEdits.walkable or nil,
    water = arenaEdits and arenaEdits.water or nil,
    worldRect = rect,
    sx = axisX,
    sy = axisY,
  }
  Coords.applyLayout(grid, layout)

  local slots = arenaEdits and arenaEdits.coverSlots
  if type(slots) == "table" then
    for i = 1, #slots do
      local slot = slots[i]
      if slot and slot.u ~= nil and slot.v ~= nil then
        -- Pad-native session props (one blocked cell each).
        grid.blocked[padKey(slot.u, slot.v)] = true
        local worldX, worldY = Coords.padToWorld(grid, slot.u, slot.v)
        grid.props[#grid.props + 1] = {
          u = slot.u, v = slot.v,
          wx = worldX, wy = worldY,
          cx = slot.cx or worldX, cy = slot.cy or worldY,
          kind = slot.kind,
          px = slot.px, py = slot.py,
        }
      elseif slot and slot.cx and slot.cy then
        -- Legacy world-block props (2×2 cells) for older tests / callers.
        for dx = 0, 1 do
          for dy = 0, 1 do
            local worldX, worldY = slot.cx + dx, slot.cy + dy
            local u, v = Coords.worldToPad(grid, worldX, worldY)
            grid.blocked[padKey(u, v)] = true
            grid.props[#grid.props + 1] = {
              u = u, v = v,
              wx = worldX, wy = worldY,
              cx = worldX, cy = worldY,
              kind = slot.kind,
              px = slot.px, py = slot.py,
            }
          end
        end
      end
    end
  end

  if plan then
    local function homeAt(worldX, worldY)
      local u, v = Coords.worldToPad(grid, worldX, worldY)
      return { u = u, v = v }
    end
    if plan.pMonX and plan.pMonY then
      grid.home.player = homeAt(plan.pMonX, plan.pMonY)
    end
    if plan.eMonX and plan.eMonY then
      grid.home.enemy = homeAt(plan.eMonX, plan.eMonY)
    end
    if plan.pCellX and plan.pCellY then
      grid.home.playerTrainer = homeAt(plan.pCellX, plan.pCellY)
    end
    if plan.eCellX and plan.eCellY then
      grid.home.enemyTrainer = homeAt(plan.eCellX, plan.eCellY)
    end
  end
  return grid
end

function Grid.padOf(grid, ent)
  return padOf(grid, ent)
end

function Grid.inPad(grid, u, v)
  return Coords.inPad(grid, u, v)
end

--- World-cell AABB (carve identity / debug). Prefer Grid.inPad for occupancy.
function Grid.inBounds(grid, cellX, cellY)
  if not grid then
    return false
  end
  if grid.sizeU and grid.uAxis then
    local u, v = Coords.worldToPad(grid, cellX, cellY)
    return Coords.inPad(grid, u, v)
  end
  return cellX >= (grid.minX or 0) and cellX <= (grid.maxX or 0)
      and cellY >= (grid.minY or 0) and cellY <= (grid.maxY or 0)
end

function Grid.isBlocked(grid, u, v)
  return grid and grid.blocked[padKey(u, v)] == true
end

function Grid.isWater(grid, u, v)
  return grid and type(grid.water) == "table" and grid.water[padKey(u, v)] == true
end

--- True when this pad cell is legal for `ent` (or land-only when ent is nil).
function Grid.canTraverse(grid, u, v, ent)
  if not Grid.inPad(grid, u, v) then
    return false
  end
  if Grid.isWater(grid, u, v) then
    return ent and ent.canSwim == true
  end
  if grid and type(grid.walkable) == "table" then
    return grid.walkable[padKey(u, v)] == true
  end
  return true
end

function Grid.inEnvelope(grid, u, v, ent)
  return Grid.canTraverse(grid, u, v, ent)
end

function Grid.isFree(grid, u, v, ignoreId, ent)
  if not Grid.canTraverse(grid, u, v, ent) or Grid.isBlocked(grid, u, v) then
    return false
  end
  local occupant = grid.occ[padKey(u, v)]
  return occupant == nil or occupant == ignoreId
end

function Grid.occupy(grid, id, u, v)
  if not grid or not id then
    return false
  end
  if u ~= nil and v ~= nil then
    local occupant = grid.occ[padKey(u, v)]
    if occupant and occupant ~= id then
      return false
    end
  end
  Grid.release(grid, id)
  if u ~= nil and v ~= nil then
    grid.occ[padKey(u, v)] = id
  end
  return true
end

function Grid.release(grid, id)
  if not (grid and id) then
    return
  end
  for occKey, occupant in pairs(grid.occ) do
    if occupant == id then
      grid.occ[occKey] = nil
    end
  end
end

function Grid.clear(grid)
  if grid then
    grid.occ = {}
  end
end

function Grid.lane(grid, u)
  local sizeU = (grid and grid.sizeU) or 1
  u = u or 0
  if u < sizeU / 3 then
    return "player"
  end
  if u > (2 * sizeU) / 3 then
    return "enemy"
  end
  return "mid"
end

-- ---------------------------------------------------------------------------
-- PLACE / STEP
-- ---------------------------------------------------------------------------

--- Nearest legal empty pad, preferring `(u, v)`. Never returns a cell owned
--- by another occupant (`ignoreId` may keep the caller's current tile).
--- `blockedWorld` is an optional set of `"worldX:worldY"` keys that are already
--- taken on the overworld (trainers, props, the other battler).
function Grid.pickFreePad(grid, u, v, ent, ignoreId, blockedWorld)
  if not grid then
    return nil, nil
  end
  ignoreId = ignoreId or (ent and ent.id)
  local function worldFree(nextU, nextV)
    if type(blockedWorld) ~= "table" then
      return true
    end
    local worldX, worldY = Coords.padToWorld(grid, nextU, nextV)
    return blockedWorld[tostring(worldX) .. ":" .. tostring(worldY)] ~= true
  end
  local function free(nextU, nextV)
    return Grid.isFree(grid, nextU, nextV, ignoreId, ent) and worldFree(nextU, nextV)
  end
  if u ~= nil and v ~= nil and free(u, v) then
    return u, v
  end
  local originU = u or 0
  local originV = v or 0
  local sizeU = grid.sizeU or 0
  local sizeV = grid.sizeV or 0
  local maxRadius = math.max(sizeU, sizeV, 1)
  for radius = 1, maxRadius do
    for deltaU = -radius, radius do
      for deltaV = -radius, radius do
        if math.max(math.abs(deltaU), math.abs(deltaV)) == radius then
          local nextU, nextV = originU + deltaU, originV + deltaV
          if free(nextU, nextV) then
            return nextU, nextV
          end
        end
      end
    end
  end
  -- Last resort: any pad whose world cell is not the other battler / a prop,
  -- even if a trainer is standing there. Never land on blockedWorld.
  for nextU = 0, sizeU - 1 do
    for nextV = 0, sizeV - 1 do
      if Grid.canTraverse(grid, nextU, nextV, ent) and worldFree(nextU, nextV) then
        local occupant = grid.occ[padKey(nextU, nextV)]
        if occupant == nil or occupant == ignoreId then
          return nextU, nextV
        end
      end
    end
  end
  for nextU = 0, sizeU - 1 do
    for nextV = 0, sizeV - 1 do
      if worldFree(nextU, nextV) and Grid.inPad(grid, nextU, nextV) then
        return nextU, nextV
      end
    end
  end
  return nil, nil
end

--- Occupy a free pad for `ent`, relocating if `(u, v)` is taken. Snaps pixels
--- onto that cell so a send-out never shares the other battler's tile.
function Grid.placeOnFreePad(grid, ent, u, v, ignoreId, blockedWorld)
  if not (grid and ent) then
    return false
  end
  u = u or ent.padU
  v = v or ent.padV
  local nextU, nextV = Grid.pickFreePad(grid, u, v, ent, ignoreId, blockedWorld)
  if nextU == nil then
    return false
  end
  Grid.release(grid, ent.id)
  grid.occ[padKey(nextU, nextV)] = ent.id
  ent.padU, ent.padV = nextU, nextV
  Grid.syncPx(grid, ent)
  local pixelX, pixelY = ent.targetPx, ent.targetPy
  if pixelX ~= nil then
    ent.basePx, ent.basePy = pixelX, pixelY
    ent.px, ent.py = pixelX, pixelY
  end
  return true
end

--- Step one pad cell if free. Mutates pad only; pixels via syncPx.
function Grid.step(grid, ent, deltaU, deltaV)
  if not (grid and ent) then
    return false
  end
  local u, v = padOf(grid, ent)
  u = u + (deltaU or 0)
  v = v + (deltaV or 0)
  if not Grid.isFree(grid, u, v, ent.id, ent) then
    return false
  end
  Grid.occupy(grid, ent.id, u, v)
  ent.padU, ent.padV = u, v
  Grid.syncPx(grid, ent)
  ent.basePx = ent.basePx or ent.targetPx
  ent.basePy = ent.basePy or ent.targetPy
  return true
end

function Grid.setPad(grid, ent, u, v)
  if not (grid and ent and Grid.isFree(grid, u, v, ent.id, ent)) then
    return false
  end
  Grid.occupy(grid, ent.id, u, v)
  ent.padU, ent.padV = u, v
  Grid.syncPx(grid, ent)
  ent.basePx = ent.basePx or ent.targetPx
  ent.basePy = ent.basePy or ent.targetPy
  return true
end

--- World-cell wrapper (converts at the boundary). Prefer setPad.
function Grid.setCell(grid, ent, cellX, cellY)
  if not (grid and ent) then
    return false
  end
  local u, v = Coords.worldToPad(grid, cellX, cellY)
  return Grid.setPad(grid, ent, u, v)
end

function Grid.homePad(grid, side)
  local home = grid and grid.home and grid.home[side]
  if home then
    return home.u, home.v
  end
  return nil, nil
end

function Grid.homeCell(grid, side)
  local u, v = Grid.homePad(grid, side)
  if u ~= nil then
    return Coords.padToWorld(grid, u, v)
  end
  return nil, nil
end

-- ---------------------------------------------------------------------------
-- FIGHT MOTION — dodge, close-the-gap, withdraw, knockback
-- ---------------------------------------------------------------------------

--[[
  Attempts to make the given entity 'ent' dodge on the grid, optionally relative to another entity 'towardEnt'.

  - If 'towardEnt' is given, the function prefers to dodge away from 'towardEnt' along the v-axis (vertical axis of the pad).
    - It compares the v position (padV) of 'ent' and 'towardEnt': 
      - If ent is below towardEnt, it sets deltaV to -1 (move up).
      - Otherwise, deltaV remains 1 (move down).

  - The function tries to step one cell along the v-axis (preferred direction). 
    - If this move succeeds, returns true.
    - If blocked, it then tries to step in the opposite direction along the v-axis.
      - If this move succeeds, returns true.
    - If both moves are blocked, returns false.

  - If 'grid' or 'ent' is missing, returns false.
]]
function Grid.dodge(grid, ent, towardEnt)
  if not (grid and ent) then
    return false
  end
  local deltaV = 1
  if towardEnt then
    local _, entV = padOf(grid, ent)
    local _, foeV = padOf(grid, towardEnt)
    if (entV - foeV) < 0 then
      deltaV = -1
    end
  end
  -- Try to step in the preferred v direction first.
  if Grid.step(grid, ent, 0, deltaV) then
    return true
  end
  -- If blocked, try the opposite v direction.
  if Grid.step(grid, ent, 0, -deltaV) then
    return true
  end
  -- No dodge possible.
  return false
end

function Grid.attackStep(grid, ent, foeEnt)
  if not (grid and ent and foeEnt) then
    return false
  end
  local u = padOf(grid, ent)
  local foeU = padOf(grid, foeEnt)
  local deltaU = 0
  if foeU > u then
    deltaU = 1
  elseif foeU < u then
    deltaU = -1
  end
  ent._returnU, ent._returnV = padOf(grid, ent)
  return Grid.step(grid, ent, deltaU, 0)
end

-- Returns the Chebyshev (maximum axis-aligned) distance between two
-- entities on the grid, i.e., the minimum number of steps required
-- to move from 'a' to 'b' when movement in both axes is allowed.
-- If either entity is missing, returns 0.
function Grid.padDistance(grid, a, b)
  if not (a and b) then
    return 0
  end
  local u, v = padOf(grid, a)
  local foeU, foeV = padOf(grid, b)
  return math.max(math.abs(foeU - u), math.abs(foeV - v))
end

--- Occupy a free cell adjacent to the foe when more than one tile away.
--- Pixels lerp via syncPx; occupancy jumps to the approach cell.
function Grid.closeGap(grid, ent, foeEnt)
  if not (grid and ent and foeEnt) then
    return false
  end
  local u, v = padOf(grid, ent)
  local foeU, foeV = padOf(grid, foeEnt)
  if math.max(math.abs(foeU - u), math.abs(foeV - v)) <= 1 then
    return false
  end
  local bestU, bestV, bestScore
  for deltaU = -1, 1 do
    for deltaV = -1, 1 do
      if not (deltaU == 0 and deltaV == 0) then
        local nextU, nextV = foeU + deltaU, foeV + deltaV
        if Grid.isFree(grid, nextU, nextV, ent.id, ent) then
          local away = math.max(math.abs(nextU - u), math.abs(nextV - v))
          local axis = (nextV == v or nextV == foeV) and 0 or 1
          local score = away * 10 + axis
          if not bestScore or score < bestScore then
            bestU, bestV, bestScore = nextU, nextV, score
          end
        end
      end
    end
  end
  if bestU == nil then
    return false
  end
  -- Stay near the foe after the strike; do not stash the opening cell.
  ent._returnU, ent._returnV = nil, nil
  return Grid.setPad(grid, ent, bestU, bestV)
end

--- Randomly re-anchor to a free pad in the 3x3 area adjacent to the foe, or stay put if not possible.
function Grid.withdrawFromFoe(grid, ent, foeEnt)
  if not (grid and ent and foeEnt) then
    return false
  end
  local u, v = padOf(grid, ent)
  local foeU, foeV = padOf(grid, foeEnt)
  local area3x3 = {}
  for deltaU = -1, 1 do
    for deltaV = -1, 1 do
      local nextU, nextV = foeU + deltaU, foeV + deltaV
      if Grid.isFree(grid, nextU, nextV, ent.id, ent) then
        if not (nextU == u and nextV == v) then
          area3x3[#area3x3 + 1] = { u = nextU, v = nextV }
        end
      end
    end
  end
  local choice = pickCell(area3x3)
  local function anchor(nextU, nextV)
    ent.homePadU, ent.homePadV = nextU, nextV
    ent._meleeAnchor = true
    ent._returnU, ent._returnV = nil, nil
  end
  if not choice then
    anchor(u, v)
    return false
  end
  if not Grid.setPad(grid, ent, choice.u, choice.v) then
    anchor(u, v)
    return false
  end
  anchor(choice.u, choice.v)
  return true
end

function Grid.returnHome(grid, ent)
  if not (grid and ent) then
    return false
  end
  local u = ent._returnU or ent.homePadU
  local v = ent._returnV or ent.homePadV
  ent._returnU, ent._returnV = nil, nil
  if u ~= nil and v ~= nil then
    return Grid.setPad(grid, ent, u, v)
  end
  if ent._returnCx and ent._returnCy then
    local ok = Grid.setCell(grid, ent, ent._returnCx, ent._returnCy)
    ent._returnCx, ent._returnCy = nil, nil
    return ok
  end
  if ent.homeCellX and ent.homeCellY then
    return Grid.setCell(grid, ent, ent.homeCellX, ent.homeCellY)
  end
  return false
end

function Grid.knockback(grid, ent, fromEnt)
  if not (grid and ent) then
    return false
  end
  local deltaU, deltaV = 0, 0
  if fromEnt then
    local u, v = padOf(grid, ent)
    local fromU, fromV = padOf(grid, fromEnt)
    deltaU, deltaV = u - fromU, v - fromV
  else
    deltaU, deltaV = -1, 0
  end
  local stepU, stepV = unitStep(deltaU, deltaV)
  return Grid.step(grid, ent, stepU, stepV)
end

--- True when a cover prop / third party sits between two battlers on the pad.
function Grid.pathObstructed(grid, fromEnt, toEnt)
  if not (grid and fromEnt and toEnt) then
    return false
  end
  local u0, v0 = padOf(grid, fromEnt)
  local u1, v1 = padOf(grid, toEnt)
  local deltaU, deltaV = u1 - u0, v1 - v0
  local steps = math.max(math.abs(deltaU), math.abs(deltaV))
  if steps <= 1 then
    return false
  end
  local fromId = fromEnt.id
  local toId = toEnt.id
  for i = 1, steps - 1 do
    local t = i / steps
    local u = math.floor(u0 + deltaU * t + 0.5)
    local v = math.floor(v0 + deltaV * t + 0.5)
    if Grid.isBlocked(grid, u, v) then
      return true
    end
    local occupant = grid.occ and grid.occ[padKey(u, v)]
    if occupant ~= nil and occupant ~= fromId and occupant ~= toId then
      return true
    end
  end
  return false
end

--- Unit pad step away from `fromEnt` (knockback / push direction).
function Grid.pushDir(grid, ent, fromEnt)
  if not (grid and ent) then
    return 0, 0
  end
  local u, v = padOf(grid, ent)
  local deltaU, deltaV = 0, 0
  if fromEnt then
    local fromU, fromV = padOf(grid, fromEnt)
    deltaU, deltaV = u - fromU, v - fromV
  else
    deltaU = -1
  end
  local stepU, stepV = unitStep(deltaU, deltaV)
  if stepU == 0 and stepV == 0 then
    stepU = -1
  end
  return stepU, stepV
end

--- Wall, cover prop, or pad edge within `range` cells behind the target.
function Grid.obstacleBehind(grid, ent, fromEnt, range)
  if not (grid and ent) then
    return nil
  end
  range = range or 2
  local u, v = padOf(grid, ent)
  local stepU, stepV = Grid.pushDir(grid, ent, fromEnt)
  for dist = 1, range do
    local checkU, checkV = u + stepU * dist, v + stepV * dist
    if not Grid.inPad(grid, checkU, checkV) then
      return { u = checkU, v = checkV, dist = dist, kind = "edge" }
    end
    if Grid.isBlocked(grid, checkU, checkV) then
      return { u = checkU, v = checkV, dist = dist, kind = "prop" }
    end
    if not Grid.canTraverse(grid, checkU, checkV, ent) then
      return { u = checkU, v = checkV, dist = dist, kind = "wall" }
    end
  end
  return nil
end

--- Push the target up to `maxTiles` pad cells away from the attacker.
function Grid.knockbackTiles(grid, ent, fromEnt, maxTiles)
  if not (grid and ent) then
    return 0
  end
  maxTiles = maxTiles or 2
  local stepU, stepV = Grid.pushDir(grid, ent, fromEnt)
  local moved = 0
  for _ = 1, maxTiles do
    if Grid.step(grid, ent, stepU, stepV) then
      moved = moved + 1
    else
      break
    end
  end
  return moved
end

-- ---------------------------------------------------------------------------
-- COVER — tuck behind a prop or a wall
-- ---------------------------------------------------------------------------

--- Cardinal walls / pad edges / blocked props adjacent to a pad cell.
function Grid.wallDirs(grid, u, v, ent)
  local hits = {}
  if not grid or u == nil or v == nil then
    return hits
  end
  for i = 1, #CARDINALS do
    local dir = CARDINALS[i]
    local nextU, nextV = u + dir[1], v + dir[2]
    local kind = nil
    if not Grid.inPad(grid, nextU, nextV) then
      kind = "edge"
    elseif Grid.isBlocked(grid, nextU, nextV) then
      kind = "prop"
    elseif not Grid.canTraverse(grid, nextU, nextV, ent) then
      kind = "wall"
    end
    if kind then
      hits[#hits + 1] = { u = dir[1], v = dir[2], kind = kind }
    end
  end
  return hits
end

--- Strongest adjacent wall/corner from `ent`'s current cell, or nil.
function Grid.wallHug(grid, ent)
  local u, v = padOf(grid, ent)
  local hits = Grid.wallDirs(grid, u, v, ent)
  if #hits == 0 then
    return nil
  end
  local hug = {
    u = hits[1].u,
    v = hits[1].v,
    kind = hits[1].kind,
    corner = #hits >= 2,
    hits = hits,
  }
  if #hits >= 2 then
    hug.u = hits[1].u + hits[2].u
    hug.v = hits[1].v + hits[2].v
  end
  return hug
end

--- Nearest free cell adjacent to a prop, preferring far side on u from foe.
function Grid.seekCover(grid, ent, foeEnt)
  if not (grid and ent) or not grid.props or #grid.props == 0 then
    return false
  end
  local best, bestScore = nil, -1e9
  local foeU, foeV
  if foeEnt then
    foeU, foeV = padOf(grid, foeEnt)
  end
  local entU, entV = padOf(grid, ent)
  for i = 1, #grid.props do
    local prop = grid.props[i]
    local propU, propV = prop.u, prop.v
    for _, dir in ipairs(CARDINALS) do
      local u, v = propU + dir[1], propV + dir[2]
      if Grid.isFree(grid, u, v, ent.id, ent) then
        local score = -math.abs(u - entU) - math.abs(v - entV)
        if foeU then
          -- Prefer far on u from the foe, and prop between us and foe.
          score = score + math.abs(u - foeU) * 0.35
          local toFoeU, toFoeV = foeU - u, (foeV or 0) - v
          local toPropU, toPropV = propU - u, propV - v
          local foeLen = math.sqrt(toFoeU * toFoeU + toFoeV * toFoeV)
          local propLen = math.sqrt(toPropU * toPropU + toPropV * toPropV)
          if foeLen > 0.1 and propLen > 0.1 then
            score = score + ((toFoeU / foeLen) * (toPropU / propLen)
              + (toFoeV / foeLen) * (toPropV / propLen)) * 4
          end
        end
        if score > bestScore then
          bestScore, best = score, { u = u, v = v }
        end
      end
    end
  end
  if best then
    return Grid.setPad(grid, ent, best.u, best.v)
  end
  return false
end

--- Step onto a nearby wall-hugging / corner cell (buildings, cave edges).
function Grid.seekWallCover(grid, ent, foeEnt)
  if not (grid and ent) then
    return false
  end
  local entU, entV = padOf(grid, ent)
  local foeU, foeV
  if foeEnt then
    foeU, foeV = padOf(grid, foeEnt)
  end
  local best, bestScore = nil, 0.5
  for deltaU = -2, 2 do
    for deltaV = -2, 2 do
      local u, v = entU + deltaU, entV + deltaV
      if Grid.isFree(grid, u, v, ent.id, ent) then
        local hugs = Grid.wallDirs(grid, u, v, ent)
        if #hugs > 0 then
          local score = #hugs * 3.2 - math.abs(deltaU) - math.abs(deltaV)
          if #hugs >= 2 then
            score = score + 6
          end
          if foeU then
            score = score + math.abs(u - foeU) * 0.35
            for i = 1, #hugs do
              local hug = hugs[i]
              if (u - foeU) * hug.u + (v - (foeV or v)) * hug.v < 0 then
                score = score + 3.5
              end
            end
          end
          if score > bestScore then
            bestScore, best = score, { u = u, v = v }
          end
        end
      end
    end
  end
  if best then
    return Grid.setPad(grid, ent, best.u, best.v)
  end
  return false
end

-- ---------------------------------------------------------------------------
-- IDLE — roam near the foe after a close-in, or near home
-- ---------------------------------------------------------------------------

local function shuffleDirs(dirs, rand)
  for i = #dirs, 2, -1 do
    local j = rand(1, i)
    dirs[i], dirs[j] = dirs[j], dirs[i]
  end
  return dirs
end

--- Idle roam in the 1–2 tile ring around the foe after a close-in strike.
local function wanderNearFoe(grid, ent, foeEnt)
  local u, v = padOf(grid, ent)
  local foeU, foeV = padOf(grid, foeEnt)
  local distToFoe = math.max(math.abs(u - foeU), math.abs(v - foeV))
  local rand = randomFn()
  local dirs = shuffleDirs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }, rand)

  local function tryStep(okDist)
    for i = 1, #dirs do
      local nextU = u + dirs[i][1]
      local nextV = v + dirs[i][2]
      local dist = math.max(math.abs(nextU - foeU), math.abs(nextV - foeV))
      if okDist(dist) and Grid.step(grid, ent, dirs[i][1], dirs[i][2]) then
        return true
      end
    end
    return false
  end

  if distToFoe > 2 then
    return tryStep(function(dist)
      return dist < distToFoe and dist >= 1
    end)
  end
  if distToFoe < 1 then
    return tryStep(function(dist)
      return dist >= 1 and dist <= 2
    end)
  end
  if distToFoe == 1 and rand() <= 0.55 then
    if tryStep(function(dist) return dist == 2 end) then
      return true
    end
  end
  if distToFoe == 2 and rand() <= 0.50 then
    if tryStep(function(dist) return dist == 2 end) then
      return true
    end
  end
  return tryStep(function(dist)
    return dist >= 1 and dist <= 2
  end)
end

function Grid.idleWander(grid, ent, side, foeEnt)
  if not (grid and ent) then
    return false
  end
  if ent._meleeAnchor and foeEnt then
    return wanderNearFoe(grid, ent, foeEnt)
  end
  local homeU, homeV = Grid.homePad(grid, side)
  if homeU == nil then
    if ent.homePadU ~= nil then
      homeU, homeV = ent.homePadU, ent.homePadV
    else
      homeU, homeV = padOf(grid, ent)
    end
  end
  local u, v = padOf(grid, ent)
  local distFromHome = math.abs(u - homeU) + math.abs(v - homeV)
  local rand = randomFn()

  local function tryStepTowardHome()
    local dirs = {}
    local deltaU, deltaV = homeU - u, homeV - v
    if deltaU ~= 0 then dirs[#dirs + 1] = { deltaU > 0 and 1 or -1, 0 } end
    if deltaV ~= 0 then dirs[#dirs + 1] = { 0, deltaV > 0 and 1 or -1 } end
    for i = 1, #dirs do
      if Grid.step(grid, ent, dirs[i][1], dirs[i][2]) then
        return true
      end
    end
    return false
  end

  -- Bounded free roaming: settle one cell at a time instead of teleporting.
  if distFromHome >= 2 then
    return tryStepTowardHome()
  end
  if distFromHome == 1 and rand() <= 0.62 then
    return tryStepTowardHome()
  end

  -- Wander one step, but never beyond two cells from home.
  local dirs = shuffleDirs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }, rand)
  for i = 1, #dirs do
    local nextU = u + dirs[i][1]
    local nextV = v + dirs[i][2]
    if math.abs(nextU - homeU) + math.abs(nextV - homeV) <= 2
        and Grid.step(grid, ent, dirs[i][1], dirs[i][2]) then
      return true
    end
  end
  return false
end

return Grid
