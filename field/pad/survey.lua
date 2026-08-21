-- Field battle — read-only walkability survey for bounded free-tile combat.
--
-- Queried once at staging from the live map (collision / water / warps /
-- blocking entities). Land walkables become grid.walkable; water cells become
-- grid.water (Water-type mons only). The map itself is never edited.
-- EXTRA_U / HALF_V grow the fight envelope beyond the opening so mons can
-- expand out from their start tiles during the battle.
--
-- Formation cells from Layout.plan are snapped onto surveyed land tiles;
-- illegal homes are never force-marked walkable (that parked mons under roofs).

local Coords = require("coords")

local Survey = {}

-- Roam room beyond each trainer edge (opening is already compact).
Survey.EXTRA_U = 2
-- Lateral half-width of the surveyed envelope (opening LATERAL is 1).
Survey.HALF_V = 2

local function callBool(obj, name, ...)
  local fn = obj and obj[name]
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, obj, ...)
  if not ok then
    return nil
  end
  return value == true
end

local function hasAt(obj, name, ...)
  local fn = obj and obj[name]
  if type(fn) ~= "function" then
    return false
  end
  local ok, value = pcall(fn, obj, ...)
  return ok and value ~= nil and value ~= false
end

function Survey.envelopeRect(plan, extraU, halfV)
  plan = plan or {}
  extraU = extraU or Survey.EXTRA_U
  halfV = halfV or Survey.HALF_V
  local sx, sy = plan.sx or 1, plan.sy or 0
  local ptx, pty = plan.pCellX or 0, plan.pCellY or 0
  local etx, ety = plan.eCellX or ptx, plan.eCellY or pty
  ptx, pty = ptx - sx * extraU, pty - sy * extraU
  etx, ety = etx + sx * extraU, ety + sy * extraU
  local minX, maxX = math.min(ptx, etx), math.max(ptx, etx)
  local minY, maxY = math.min(pty, ety), math.max(pty, ety)
  if sx ~= 0 then
    minY = (plan.midY or 0) - halfV
    maxY = (plan.midY or 0) + halfV
  else
    minX = (plan.midX or 0) - halfV
    maxX = (plan.midX or 0) + halfV
  end
  return { minX = minX, maxX = maxX, minY = minY, maxY = maxY }
end

local function cellInBounds(map, wx, wy)
  local inBounds = callBool(map, "inBounds", wx, wy)
  return inBounds ~= false
end

local function cellIsWarp(map, wx, wy)
  return hasAt(map, "warpAtCell", wx, wy)
      or callBool(map, "isWarpTileCell", wx, wy) == true
end

--- Surfable water inside the fight envelope (Water-type mons only).
function Survey.cellWater(map, wx, wy)
  if not map then
    return false
  end
  if not cellInBounds(map, wx, wy) or cellIsWarp(map, wx, wy) then
    return false
  end
  return callBool(map, "isWaterCell", wx, wy) == true
end

--- Land walkable (excludes water). Used for formation homes + non-Water mons.
function Survey.cellAllowed(map, wx, wy)
  if not map then
    return true
  end
  if not cellInBounds(map, wx, wy) then
    return false
  end
  if Survey.cellWater(map, wx, wy) then
    return false
  end
  if cellIsWarp(map, wx, wy) then
    return false
  end
  local walkable = callBool(map, "isWalkableCell", wx, wy)
  local grass = callBool(map, "isGrassCell", wx, wy)
  -- Require an explicit walkable/grass yes. Unknown (nil) is not a free pass
  -- when the map exposes collision predicates.
  if walkable == true or grass == true then
    return true
  end
  if walkable == false then
    return false
  end
  -- No isWalkableCell on the map object: keep prior permissive behavior.
  if type(map.isWalkableCell) ~= "function" then
    return true
  end
  return false
end

--- Prefer open tiles; penalize wall-hugging cells (roofs / building edges).
local function opennessPenalty(layout, walkable, u, v)
  local pen = 0
  for du = -1, 1 do
    for dv = -1, 1 do
      if not (du == 0 and dv == 0) then
        local nu, nv = u + du, v + dv
        if not Coords.inPad(layout, nu, nv) then
          pen = pen + 2
        elseif not walkable[Coords.key(nu, nv)] then
          pen = pen + 4
        end
      end
    end
  end
  return pen
end

local function relocateAnchor(plan, layout, walkable, occupied, xKey, yKey, preferSide)
  local wx, wy = plan[xKey], plan[yKey]
  if wx == nil or wy == nil then
    return false
  end
  local wantedU, wantedV = Coords.worldToPad(layout, wx, wy)
  local wantedKey = Coords.key(wantedU, wantedV)
  if walkable[wantedKey] and not occupied[wantedKey] then
    -- Still prefer a more open neighbor when the planned cell hugs a wall.
    local hug = opennessPenalty(layout, walkable, wantedU, wantedV)
    if hug <= 8 then
      occupied[wantedKey] = true
      return true
    end
  end

  local midU = math.floor(((layout.sizeU or 1) - 1) / 2)
  local best, bestScore
  for u = 0, (layout.sizeU or 1) - 1 do
    for v = 0, (layout.sizeV or 1) - 1 do
      local key = Coords.key(u, v)
      if walkable[key] and not occupied[key] then
        local sidePenalty = 0
        if preferSide == "player" and u >= midU then
          sidePenalty = 20
        elseif preferSide == "enemy" and u <= midU then
          sidePenalty = 20
        end
        local score = math.abs(u - wantedU) + math.abs(v - wantedV)
            + sidePenalty
            + opennessPenalty(layout, walkable, u, v)
        if not bestScore or score < bestScore then
          best, bestScore = { u = u, v = v }, score
        end
      end
    end
  end
  if not best then
    return false
  end
  local nx, ny = Coords.padToWorld(layout, best.u, best.v)
  plan[xKey], plan[yKey] = nx, ny
  occupied[Coords.key(best.u, best.v)] = true
  return true
end

local function seedFallback(walkable, layout, occupied, map, wx, wy, plan, xKey, yKey)
  if wx == nil or wy == nil then
    return false
  end
  if not Survey.cellAllowed(map, wx, wy) then
    return false
  end
  local u, v = Coords.worldToPad(layout, wx, wy)
  if not Coords.inPad(layout, u, v) then
    return false
  end
  local key = Coords.key(u, v)
  if occupied[key] then
    return false
  end
  walkable[key] = true
  plan[xKey], plan[yKey] = wx, wy
  occupied[key] = true
  return true
end

local function buildOnce(map, plan, opts, extraU, halfV)
  local rect = Survey.envelopeRect(plan, extraU, halfV)
  local layout = Coords.layoutPad(rect, plan and plan.sx or 1, plan and plan.sy or 0)
  local walkable = {}
  local water = {}
  local occupiedWorld = {}
  for _, pool in ipairs(opts.entityPools or {}) do
    for i = 1, #(pool or {}) do
      local ent = pool[i]
      if ent and ent ~= opts.player and ent ~= opts.foe
          and ent.cellX ~= nil and ent.cellY ~= nil then
        occupiedWorld[tostring(ent.cellX) .. ":" .. tostring(ent.cellY)] = true
      end
    end
  end
  for u = 0, layout.sizeU - 1 do
    for v = 0, layout.sizeV - 1 do
      local wx, wy = Coords.padToWorld(layout, u, v)
      local worldKey = tostring(wx) .. ":" .. tostring(wy)
      if not occupiedWorld[worldKey] then
        if Survey.cellWater(map, wx, wy) then
          water[Coords.key(u, v)] = true
        elseif Survey.cellAllowed(map, wx, wy) then
          walkable[Coords.key(u, v)] = true
        end
      end
    end
  end

  local occupied = {}
  if plan then
    -- Snap trainers first so parkTrainer never lands on roofs / solid tiles.
    if not relocateAnchor(plan, layout, walkable, occupied,
        "pCellX", "pCellY", "player") then
      local p = opts.player
      seedFallback(walkable, layout, occupied, map,
        p and p.cellX, p and p.cellY, plan, "pCellX", "pCellY")
    end
    if plan.hasFoeTrainer then
      if not relocateAnchor(plan, layout, walkable, occupied,
          "eCellX", "eCellY", "enemy") then
        local f = opts.foe
        seedFallback(walkable, layout, occupied, map,
          f and f.cellX, f and f.cellY, plan, "eCellX", "eCellY")
      end
    end
    if not relocateAnchor(plan, layout, walkable, occupied,
        "pMonX", "pMonY", "player") then
      local p = opts.player
      seedFallback(walkable, layout, occupied, map,
        p and p.cellX, p and p.cellY, plan, "pMonX", "pMonY")
    end
    if not relocateAnchor(plan, layout, walkable, occupied,
        "eMonX", "eMonY", "enemy") then
      local f = opts.foe
      if not seedFallback(walkable, layout, occupied, map,
          f and f.cellX, f and f.cellY, plan, "eMonX", "eMonY") then
        local p = opts.player
        seedFallback(walkable, layout, occupied, map,
          p and p.cellX, p and p.cellY, plan, "eMonX", "eMonY")
      end
    end
  end

  local walkCount = 0
  for _ in pairs(walkable) do
    walkCount = walkCount + 1
  end

  return {
    gridRect = rect,
    pad = layout,
    walkable = walkable,
    water = water,
    readOnly = true,
    walkCount = walkCount,
  }
end

function Survey.build(map, plan, opts)
  opts = opts or {}
  local extraU = opts.extraU or Survey.EXTRA_U
  local halfV = opts.halfV or Survey.HALF_V
  local best
  -- Widen the envelope when the strip is mostly buildings / water.
  for attempt = 0, 2 do
    local result = buildOnce(map, plan, opts, extraU + attempt * 2, halfV + attempt)
    best = result
    if result and plan and plan.pMonX ~= nil and plan.eMonX ~= nil then
      local pU, pV = Coords.worldToPad(result.pad, plan.pMonX, plan.pMonY)
      local eU, eV = Coords.worldToPad(result.pad, plan.eMonX, plan.eMonY)
      if result.walkable[Coords.key(pU, pV)]
          and result.walkable[Coords.key(eU, eV)]
          and (result.walkCount or 0) >= 4 then
        return result
      end
    elseif result and (result.walkCount or 0) >= 4 then
      return result
    end
  end
  return best
end

return Survey
