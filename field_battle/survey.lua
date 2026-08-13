-- Field battle — read-only walkability survey for bounded free-tile combat.
-- The live map is queried once at staging; it is never modified.

local Coords = require("coords")

local Survey = {}

Survey.EXTRA_U = 2
Survey.HALF_V = 3

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

function Survey.cellAllowed(map, wx, wy)
  if not map then
    return true
  end
  local inBounds = callBool(map, "inBounds", wx, wy)
  if inBounds == false then
    return false
  end
  if callBool(map, "isWaterCell", wx, wy) == true then
    return false
  end
  if hasAt(map, "warpAtCell", wx, wy)
      or callBool(map, "isWarpTileCell", wx, wy) == true then
    return false
  end
  local walkable = callBool(map, "isWalkableCell", wx, wy)
  local grass = callBool(map, "isGrassCell", wx, wy)
  if walkable == false and grass ~= true then
    return false
  end
  return true
end

local function forceCell(out, layout, wx, wy)
  if wx == nil or wy == nil then return end
  local u, v = Coords.worldToPad(layout, wx, wy)
  if Coords.inPad(layout, u, v) then
    out[Coords.key(u, v)] = true
  end
end

local function relocateMon(plan, layout, walkable, side, occupied)
  local xKey = side == "player" and "pMonX" or "eMonX"
  local yKey = side == "player" and "pMonY" or "eMonY"
  local wantedU, wantedV = Coords.worldToPad(layout, plan[xKey], plan[yKey])
  local wantedKey = Coords.key(wantedU, wantedV)
  if walkable[wantedKey] and not occupied[wantedKey] then
    occupied[wantedKey] = true
    return
  end
  local midU = math.floor(((layout.sizeU or 1) - 1) / 2)
  local best, bestScore
  for u = 0, (layout.sizeU or 1) - 1 do
    for v = 0, (layout.sizeV or 1) - 1 do
      local key = Coords.key(u, v)
      if walkable[key] and not occupied[key] then
        local sidePenalty = 0
        if side == "player" and u >= midU then sidePenalty = 20 end
        if side == "enemy" and u <= midU then sidePenalty = 20 end
        local score = math.abs(u - wantedU) + math.abs(v - wantedV) + sidePenalty
        if not bestScore or score < bestScore then
          best, bestScore = { u = u, v = v }, score
        end
      end
    end
  end
  if best then
    local wx, wy = Coords.padToWorld(layout, best.u, best.v)
    plan[xKey], plan[yKey] = wx, wy
    occupied[Coords.key(best.u, best.v)] = true
  else
    walkable[wantedKey] = true
    occupied[wantedKey] = true
  end
end

function Survey.build(map, plan, opts)
  opts = opts or {}
  local rect = Survey.envelopeRect(plan, opts.extraU, opts.halfV)
  local layout = Coords.layoutPad(rect, plan and plan.sx or 1, plan and plan.sy or 0)
  local walkable = {}
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
      if not occupiedWorld[worldKey] and Survey.cellAllowed(map, wx, wy) then
        walkable[Coords.key(u, v)] = true
      end
    end
  end

  -- Trainers stand on cells already occupied in the live map. Preserve those
  -- anchors, then relocate only Pokémon homes if a nearby tile is unsuitable.
  forceCell(walkable, layout, plan and plan.pCellX, plan and plan.pCellY)
  if plan and plan.hasFoeTrainer then
    forceCell(walkable, layout, plan.eCellX, plan.eCellY)
  end
  local occupied = {}
  if plan then
    local pu, pv = Coords.worldToPad(layout, plan.pCellX, plan.pCellY)
    occupied[Coords.key(pu, pv)] = true
    if plan.hasFoeTrainer then
      local eu, ev = Coords.worldToPad(layout, plan.eCellX, plan.eCellY)
      occupied[Coords.key(eu, ev)] = true
    end
    relocateMon(plan, layout, walkable, "player", occupied)
    relocateMon(plan, layout, walkable, "enemy", occupied)
  end

  return {
    gridRect = rect,
    pad = layout,
    walkable = walkable,
    readOnly = true,
  }
end

return Survey
