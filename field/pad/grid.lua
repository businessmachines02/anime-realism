-- Field battle — pad cell occupancy + step helpers.
--
-- Authoritative position is pad (u, v). Pixels are presentation only and
-- follow via Coords.padToPx + Cast lerp. Occupancy (`grid.occ`) and
-- walkability (`grid.blocked` from Survey) gate steps; trainers may
-- dodge-aside when a mon steps onto/beside their cell.

local Coords = require("coords")

local Grid = {}

local function key(u, v)
  return Coords.key(u, v)
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

local function padOf(g, ent)
  if not ent then
    return 0, 0
  end
  if ent.padU ~= nil and ent.padV ~= nil then
    return ent.padU, ent.padV
  end
  -- Never treat world cells as pad indices; convert at the boundary.
  if g and ent.cellX ~= nil and ent.cellY ~= nil then
    return Coords.worldToPad(g, ent.cellX, ent.cellY)
  end
  return 0, 0
end

--- Sync cached world cell + pixel target from pad. Does not touch occupancy.
function Grid.syncPx(g, ent)
  if not (g and ent and ent.padU ~= nil) then
    return
  end
  local wx, wy = Coords.padToWorld(g, ent.padU, ent.padV)
  ent.cellX, ent.cellY = wx, wy
  local px, py = Coords.padToPx(g, ent.padU, ent.padV)
  ent.targetPx, ent.targetPy = px, py
end

--- Build a grid from arena generate result + layout plan (pad axes).
function Grid.build(arenaEdits, plan)
  local sx = plan and plan.sx or 1
  local sy = plan and plan.sy or 0
  local rect = (arenaEdits and arenaEdits.gridRect) or worldRectFromPlan(plan)
  local layout = (arenaEdits and arenaEdits.pad) or Coords.layoutPad(rect, sx, sy)
  local g = {
    blocked = {},
    occ = {},
    props = {},
    home = {},
    walkable = arenaEdits and arenaEdits.walkable or nil,
    water = arenaEdits and arenaEdits.water or nil,
    worldRect = rect,
    sx = sx,
    sy = sy,
  }
  Coords.applyLayout(g, layout)

  local slots = arenaEdits and arenaEdits.coverSlots
  if type(slots) == "table" then
    for i = 1, #slots do
      local s = slots[i]
      if s and s.u ~= nil and s.v ~= nil then
        -- Pad-native session props (one blocked cell each).
        g.blocked[key(s.u, s.v)] = true
        local wx, wy = Coords.padToWorld(g, s.u, s.v)
        g.props[#g.props + 1] = {
          u = s.u, v = s.v,
          wx = wx, wy = wy,
          cx = s.cx or wx, cy = s.cy or wy,
          kind = s.kind,
          px = s.px, py = s.py,
        }
      elseif s and s.cx and s.cy then
        -- Legacy world-block props (2×2 cells) for older tests / callers.
        for dx = 0, 1 do
          for dy = 0, 1 do
            local wx, wy = s.cx + dx, s.cy + dy
            local u, v = Coords.worldToPad(g, wx, wy)
            g.blocked[key(u, v)] = true
            g.props[#g.props + 1] = {
              u = u, v = v,
              wx = wx, wy = wy,
              cx = wx, cy = wy,
              kind = s.kind,
              px = s.px, py = s.py,
            }
          end
        end
      end
    end
  end

  if plan then
    local function homeAt(wx, wy)
      local u, v = Coords.worldToPad(g, wx, wy)
      return { u = u, v = v }
    end
    if plan.pMonX and plan.pMonY then
      g.home.player = homeAt(plan.pMonX, plan.pMonY)
    end
    if plan.eMonX and plan.eMonY then
      g.home.enemy = homeAt(plan.eMonX, plan.eMonY)
    end
    if plan.pCellX and plan.pCellY then
      g.home.playerTrainer = homeAt(plan.pCellX, plan.pCellY)
    end
    if plan.eCellX and plan.eCellY then
      g.home.enemyTrainer = homeAt(plan.eCellX, plan.eCellY)
    end
  end
  return g
end

function Grid.padOf(g, ent)
  return padOf(g, ent)
end

function Grid.inPad(g, u, v)
  return Coords.inPad(g, u, v)
end

--- World-cell AABB (carve identity / debug). Prefer Grid.inPad for occupancy.
function Grid.inBounds(g, cx, cy)
  if not g then
    return false
  end
  if g.sizeU and g.uAxis then
    local u, v = Coords.worldToPad(g, cx, cy)
    return Coords.inPad(g, u, v)
  end
  return cx >= (g.minX or 0) and cx <= (g.maxX or 0)
      and cy >= (g.minY or 0) and cy <= (g.maxY or 0)
end

function Grid.isBlocked(g, u, v)
  return g and g.blocked[key(u, v)] == true
end

function Grid.isWater(g, u, v)
  return g and type(g.water) == "table" and g.water[key(u, v)] == true
end

--- True when this pad cell is legal for `ent` (or land-only when ent is nil).
function Grid.canTraverse(g, u, v, ent)
  if not Grid.inPad(g, u, v) then
    return false
  end
  if Grid.isWater(g, u, v) then
    return ent and ent.canSwim == true
  end
  if g and type(g.walkable) == "table" then
    return g.walkable[key(u, v)] == true
  end
  return true
end

function Grid.inEnvelope(g, u, v, ent)
  return Grid.canTraverse(g, u, v, ent)
end

function Grid.isFree(g, u, v, ignoreId, ent)
  if not Grid.canTraverse(g, u, v, ent) or Grid.isBlocked(g, u, v) then
    return false
  end
  local who = g.occ[key(u, v)]
  return who == nil or who == ignoreId
end

function Grid.occupy(g, id, u, v)
  if not g or not id then
    return false
  end
  if u ~= nil and v ~= nil then
    local who = g.occ[key(u, v)]
    if who and who ~= id then
      return false
    end
  end
  Grid.release(g, id)
  if u ~= nil and v ~= nil then
    g.occ[key(u, v)] = id
  end
  return true
end

function Grid.release(g, id)
  if not (g and id) then
    return
  end
  for k, who in pairs(g.occ) do
    if who == id then
      g.occ[k] = nil
    end
  end
end

function Grid.clear(g)
  if g then
    g.occ = {}
  end
end

function Grid.lane(g, u)
  local n = (g and g.sizeU) or 1
  u = u or 0
  if u < n / 3 then
    return "player"
  end
  if u > (2 * n) / 3 then
    return "enemy"
  end
  return "mid"
end

--- Nearest legal empty pad, preferring `(u, v)`. Never returns a cell owned
--- by another occupant (`ignoreId` may keep the caller's current tile).
--- `blockedWorld` is an optional set of `"wx:wy"` keys that are already
--- taken on the overworld (trainers, props, the other battler).
function Grid.pickFreePad(g, u, v, ent, ignoreId, blockedWorld)
  if not g then
    return nil, nil
  end
  ignoreId = ignoreId or (ent and ent.id)
  local function worldFree(nu, nv)
    if type(blockedWorld) ~= "table" then
      return true
    end
    local wx, wy = Coords.padToWorld(g, nu, nv)
    return blockedWorld[tostring(wx) .. ":" .. tostring(wy)] ~= true
  end
  local function free(nu, nv)
    return Grid.isFree(g, nu, nv, ignoreId, ent) and worldFree(nu, nv)
  end
  if u ~= nil and v ~= nil and free(u, v) then
    return u, v
  end
  local originU = u or 0
  local originV = v or 0
  local su = g.sizeU or 0
  local sv = g.sizeV or 0
  local maxR = math.max(su, sv, 1)
  for radius = 1, maxR do
    for du = -radius, radius do
      for dv = -radius, radius do
        if math.max(math.abs(du), math.abs(dv)) == radius then
          local nu, nv = originU + du, originV + dv
          if free(nu, nv) then
            return nu, nv
          end
        end
      end
    end
  end
  -- Last resort: any pad whose world cell is not the other battler / a prop,
  -- even if a trainer is standing there. Never land on blockedWorld.
  for nu = 0, su - 1 do
    for nv = 0, sv - 1 do
      if Grid.canTraverse(g, nu, nv, ent) and worldFree(nu, nv) then
        local who = g.occ[key(nu, nv)]
        if who == nil or who == ignoreId then
          return nu, nv
        end
      end
    end
  end
  for nu = 0, su - 1 do
    for nv = 0, sv - 1 do
      if worldFree(nu, nv) and Grid.inPad(g, nu, nv) then
        return nu, nv
      end
    end
  end
  return nil, nil
end

--- Occupy a free pad for `ent`, relocating if `(u, v)` is taken. Snaps pixels
--- onto that cell so a send-out never shares the other battler's tile.
function Grid.placeOnFreePad(g, ent, u, v, ignoreId, blockedWorld)
  if not (g and ent) then
    return false
  end
  u = u or ent.padU
  v = v or ent.padV
  local nu, nv = Grid.pickFreePad(g, u, v, ent, ignoreId, blockedWorld)
  if nu == nil then
    return false
  end
  Grid.release(g, ent.id)
  g.occ[key(nu, nv)] = ent.id
  ent.padU, ent.padV = nu, nv
  Grid.syncPx(g, ent)
  local px, py = ent.targetPx, ent.targetPy
  if px ~= nil then
    ent.basePx, ent.basePy = px, py
    ent.px, ent.py = px, py
  end
  return true
end

--- Step one pad cell if free. Mutates pad only; pixels via syncPx.
function Grid.step(g, ent, du, dv)
  if not (g and ent) then
    return false
  end
  local u, v = padOf(g, ent)
  u = u + (du or 0)
  v = v + (dv or 0)
  if not Grid.isFree(g, u, v, ent.id, ent) then
    return false
  end
  Grid.occupy(g, ent.id, u, v)
  ent.padU, ent.padV = u, v
  Grid.syncPx(g, ent)
  ent.basePx = ent.basePx or ent.targetPx
  ent.basePy = ent.basePy or ent.targetPy
  return true
end

function Grid.setPad(g, ent, u, v)
  if not (g and ent and Grid.isFree(g, u, v, ent.id, ent)) then
    return false
  end
  Grid.occupy(g, ent.id, u, v)
  ent.padU, ent.padV = u, v
  Grid.syncPx(g, ent)
  ent.basePx = ent.basePx or ent.targetPx
  ent.basePy = ent.basePy or ent.targetPy
  return true
end

--- World-cell wrapper (converts at the boundary). Prefer setPad.
function Grid.setCell(g, ent, cx, cy)
  if not (g and ent) then
    return false
  end
  local u, v = Coords.worldToPad(g, cx, cy)
  return Grid.setPad(g, ent, u, v)
end

function Grid.homePad(g, side)
  local h = g and g.home and g.home[side]
  if h then
    return h.u, h.v
  end
  return nil, nil
end

function Grid.homeCell(g, side)
  local u, v = Grid.homePad(g, side)
  if u ~= nil then
    return Coords.padToWorld(g, u, v)
  end
  return nil, nil
end

function Grid.dodge(g, ent, towardEnt)
  if not (g and ent) then
    return false
  end
  local dv = 1
  if towardEnt then
    local _, ev = padOf(g, ent)
    local _, fv = padOf(g, towardEnt)
    if (ev - fv) < 0 then
      dv = -1
    end
  end
  if Grid.step(g, ent, 0, dv) then
    return true
  end
  if Grid.step(g, ent, 0, -dv) then
    return true
  end
  return false
end

function Grid.attackStep(g, ent, foeEnt)
  if not (g and ent and foeEnt) then
    return false
  end
  local u = padOf(g, ent)
  local fu = padOf(g, foeEnt)
  local du = 0
  if fu > u then
    du = 1
  elseif fu < u then
    du = -1
  end
  ent._returnU, ent._returnV = padOf(g, ent)
  return Grid.step(g, ent, du, 0)
end

--- Chebyshev pad distance between two entities.
function Grid.padDistance(g, a, b)
  if not (a and b) then
    return 0
  end
  local u, v = padOf(g, a)
  local fu, fv = padOf(g, b)
  return math.max(math.abs(fu - u), math.abs(fv - v))
end

--- Occupy a free cell adjacent to the foe when more than one tile away.
--- Pixels lerp via syncPx; occupancy jumps to the approach cell.
function Grid.closeGap(g, ent, foeEnt)
  if not (g and ent and foeEnt) then
    return false
  end
  local u, v = padOf(g, ent)
  local fu, fv = padOf(g, foeEnt)
  if math.max(math.abs(fu - u), math.abs(fv - v)) <= 1 then
    return false
  end
  local bestU, bestV, bestScore
  for du = -1, 1 do
    for dv = -1, 1 do
      if not (du == 0 and dv == 0) then
        local nu, nv = fu + du, fv + dv
        if Grid.isFree(g, nu, nv, ent.id, ent) then
          local away = math.max(math.abs(nu - u), math.abs(nv - v))
          local axis = (nv == v or nv == fv) and 0 or 1
          local score = away * 10 + axis
          if not bestScore or score < bestScore then
            bestU, bestV, bestScore = nu, nv, score
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
  return Grid.setPad(g, ent, bestU, bestV)
end

local function rng()
  return (love and love.math and love.math.random) or math.random
end

local function pickCell(list)
  if not list or #list == 0 then
    return nil
  end
  return list[rng()(1, #list)]
end

--- Re-anchor one or two tiles from the foe (slight withdraw after a close-in).
function Grid.withdrawFromFoe(g, ent, foeEnt)
  if not (g and ent and foeEnt) then
    return false
  end
  local u, v = padOf(g, ent)
  local fu, fv = padOf(g, foeEnt)
  local ring2, ring1 = {}, {}
  for du = -2, 2 do
    for dv = -2, 2 do
      local dist = math.max(math.abs(du), math.abs(dv))
      if dist >= 1 and dist <= 2 then
        local nu, nv = fu + du, fv + dv
        if Grid.isFree(g, nu, nv, ent.id, ent) then
          local cell = { u = nu, v = nv }
          if dist == 2 then
            ring2[#ring2 + 1] = cell
          elseif not (nu == u and nv == v) then
            ring1[#ring1 + 1] = cell
          end
        end
      end
    end
  end
  local choice = pickCell(ring2) or pickCell(ring1)
  local function anchor(nu, nv)
    ent.homePadU, ent.homePadV = nu, nv
    ent._meleeAnchor = true
    ent._returnU, ent._returnV = nil, nil
  end
  if not choice then
    anchor(u, v)
    return false
  end
  if not Grid.setPad(g, ent, choice.u, choice.v) then
    anchor(u, v)
    return false
  end
  anchor(choice.u, choice.v)
  return true
end

function Grid.returnHome(g, ent)
  if not (g and ent) then
    return false
  end
  local u = ent._returnU or ent.homePadU
  local v = ent._returnV or ent.homePadV
  ent._returnU, ent._returnV = nil, nil
  if u ~= nil and v ~= nil then
    return Grid.setPad(g, ent, u, v)
  end
  if ent._returnCx and ent._returnCy then
    local ok = Grid.setCell(g, ent, ent._returnCx, ent._returnCy)
    ent._returnCx, ent._returnCy = nil, nil
    return ok
  end
  if ent.homeCellX and ent.homeCellY then
    return Grid.setCell(g, ent, ent.homeCellX, ent.homeCellY)
  end
  return false
end

function Grid.knockback(g, ent, fromEnt)
  if not (g and ent) then
    return false
  end
  local du, dv = 0, 0
  if fromEnt then
    local u, v = padOf(g, ent)
    local fu, fv = padOf(g, fromEnt)
    du, dv = u - fu, v - fv
  else
    du, dv = -1, 0
  end
  local su = du == 0 and 0 or (du > 0 and 1 or -1)
  local sv = dv == 0 and 0 or (dv > 0 and 1 or -1)
  if math.abs(du) >= math.abs(dv) then
    sv = 0
  else
    su = 0
  end
  return Grid.step(g, ent, su, sv)
end

--- True when a cover prop / third party sits between two battlers on the pad.
function Grid.pathObstructed(g, fromEnt, toEnt)
  if not (g and fromEnt and toEnt) then
    return false
  end
  local u0, v0 = padOf(g, fromEnt)
  local u1, v1 = padOf(g, toEnt)
  local du, dv = u1 - u0, v1 - v0
  local steps = math.max(math.abs(du), math.abs(dv))
  if steps <= 1 then
    return false
  end
  local fromId = fromEnt.id
  local toId = toEnt.id
  for i = 1, steps - 1 do
    local t = i / steps
    local u = math.floor(u0 + du * t + 0.5)
    local v = math.floor(v0 + dv * t + 0.5)
    if Grid.isBlocked(g, u, v) then
      return true
    end
    local who = g.occ and g.occ[key(u, v)]
    if who ~= nil and who ~= fromId and who ~= toId then
      return true
    end
  end
  return false
end

--- Cardinal walls / pad edges / blocked props adjacent to a pad cell.
function Grid.wallDirs(g, u, v, ent)
  local hits = {}
  if not g or u == nil or v == nil then
    return hits
  end
  local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
  for i = 1, 4 do
    local d = dirs[i]
    local nu, nv = u + d[1], v + d[2]
    local kind = nil
    if not Grid.inPad(g, nu, nv) then
      kind = "edge"
    elseif Grid.isBlocked(g, nu, nv) then
      kind = "prop"
    elseif not Grid.canTraverse(g, nu, nv, ent) then
      kind = "wall"
    end
    if kind then
      hits[#hits + 1] = { u = d[1], v = d[2], kind = kind }
    end
  end
  return hits
end

--- Strongest adjacent wall/corner from `ent`'s current cell, or nil.
function Grid.wallHug(g, ent)
  local u, v = padOf(g, ent)
  local hits = Grid.wallDirs(g, u, v, ent)
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
function Grid.seekCover(g, ent, foeEnt)
  if not (g and ent) or not g.props or #g.props == 0 then
    return false
  end
  local best, bestScore = nil, -1e9
  local fu, fv
  if foeEnt then
    fu, fv = padOf(g, foeEnt)
  end
  local eu, ev = padOf(g, ent)
  for i = 1, #g.props do
    local p = g.props[i]
    local pu, pv = p.u, p.v
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local u, v = pu + d[1], pv + d[2]
      if Grid.isFree(g, u, v, ent.id, ent) then
        local score = -math.abs(u - eu) - math.abs(v - ev)
        if fu then
          -- Prefer far on u from the foe, and prop between us and foe.
          score = score + math.abs(u - fu) * 0.35
          local toFoeU, toFoeV = fu - u, (fv or 0) - v
          local toPropU, toPropV = pu - u, pv - v
          local fl = math.sqrt(toFoeU * toFoeU + toFoeV * toFoeV)
          local pl = math.sqrt(toPropU * toPropU + toPropV * toPropV)
          if fl > 0.1 and pl > 0.1 then
            score = score + ((toFoeU / fl) * (toPropU / pl) + (toFoeV / fl) * (toPropV / pl)) * 4
          end
        end
        if score > bestScore then
          bestScore, best = score, { u = u, v = v }
        end
      end
    end
  end
  if best then
    return Grid.setPad(g, ent, best.u, best.v)
  end
  return false
end

--- Step onto a nearby wall-hugging / corner cell (buildings, cave edges).
function Grid.seekWallCover(g, ent, foeEnt)
  if not (g and ent) then
    return false
  end
  local eu, ev = padOf(g, ent)
  local fu, fv
  if foeEnt then
    fu, fv = padOf(g, foeEnt)
  end
  local best, bestScore = nil, 0.5
  for du = -2, 2 do
    for dv = -2, 2 do
      local u, v = eu + du, ev + dv
      if Grid.isFree(g, u, v, ent.id, ent) then
        local hugs = Grid.wallDirs(g, u, v, ent)
        if #hugs > 0 then
          local score = #hugs * 3.2 - math.abs(du) - math.abs(dv)
          if #hugs >= 2 then
            score = score + 6
          end
          if fu then
            score = score + math.abs(u - fu) * 0.35
            for i = 1, #hugs do
              local h = hugs[i]
              if (u - fu) * h.u + (v - (fv or v)) * h.v < 0 then
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
    return Grid.setPad(g, ent, best.u, best.v)
  end
  return false
end

local function shuffleDirs(dirs, rr)
  for i = #dirs, 2, -1 do
    local j = rr(1, i)
    dirs[i], dirs[j] = dirs[j], dirs[i]
  end
  return dirs
end

--- Idle roam in the 1–2 tile ring around the foe after a close-in strike.
local function wanderNearFoe(g, ent, foeEnt)
  local u, v = padOf(g, ent)
  local fu, fv = padOf(g, foeEnt)
  local here = math.max(math.abs(u - fu), math.abs(v - fv))
  local rr = rng()
  local dirs = shuffleDirs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }, rr)

  local function tryStep(okDist)
    for i = 1, #dirs do
      local nu = u + dirs[i][1]
      local nv = v + dirs[i][2]
      local dist = math.max(math.abs(nu - fu), math.abs(nv - fv))
      if okDist(dist) and Grid.step(g, ent, dirs[i][1], dirs[i][2]) then
        return true
      end
    end
    return false
  end

  if here > 2 then
    return tryStep(function(dist)
      return dist < here and dist >= 1
    end)
  end
  if here < 1 then
    return tryStep(function(dist)
      return dist >= 1 and dist <= 2
    end)
  end
  if here == 1 and rr() <= 0.55 then
    if tryStep(function(dist) return dist == 2 end) then
      return true
    end
  end
  if here == 2 and rr() <= 0.50 then
    if tryStep(function(dist) return dist == 2 end) then
      return true
    end
  end
  return tryStep(function(dist)
    return dist >= 1 and dist <= 2
  end)
end

function Grid.idleWander(g, ent, side, foeEnt)
  if not (g and ent) then
    return false
  end
  if ent._meleeAnchor and foeEnt then
    return wanderNearFoe(g, ent, foeEnt)
  end
  local hu, hv = Grid.homePad(g, side)
  if hu == nil then
    if ent.homePadU ~= nil then
      hu, hv = ent.homePadU, ent.homePadV
    else
      hu, hv = padOf(g, ent)
    end
  end
  local u, v = padOf(g, ent)
  local here = math.abs(u - hu) + math.abs(v - hv)
  local rr = rng()

  local function tryStepTowardHome()
    local dirs = {}
    local du, dv = hu - u, hv - v
    if du ~= 0 then dirs[#dirs + 1] = { du > 0 and 1 or -1, 0 } end
    if dv ~= 0 then dirs[#dirs + 1] = { 0, dv > 0 and 1 or -1 } end
    for i = 1, #dirs do
      if Grid.step(g, ent, dirs[i][1], dirs[i][2]) then
        return true
      end
    end
    return false
  end

  -- Bounded free roaming: settle one cell at a time instead of teleporting.
  if here >= 2 then
    return tryStepTowardHome()
  end
  if here == 1 and rr() <= 0.62 then
    return tryStepTowardHome()
  end

  -- Wander one step, but never beyond two cells from home.
  local dirs = shuffleDirs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }, rr)
  for i = 1, #dirs do
    local nu = u + dirs[i][1]
    local nv = v + dirs[i][2]
    if math.abs(nu - hu) + math.abs(nv - hv) <= 2
        and Grid.step(g, ent, dirs[i][1], dirs[i][2]) then
      return true
    end
  end
  return false
end

--- Unit pad step away from `fromEnt` (knockback / push direction).
function Grid.pushDir(g, ent, fromEnt)
  if not (g and ent) then
    return 0, 0
  end
  local u, v = padOf(g, ent)
  local du, dv = 0, 0
  if fromEnt then
    local fu, fv = padOf(g, fromEnt)
    du, dv = u - fu, v - fv
  else
    du = -1
  end
  local su = du == 0 and 0 or (du > 0 and 1 or -1)
  local sv = dv == 0 and 0 or (dv > 0 and 1 or -1)
  if math.abs(du) >= math.abs(dv) then
    sv = 0
  else
    su = 0
  end
  if su == 0 and sv == 0 then
    su = -1
  end
  return su, sv
end

--- Wall, cover prop, or pad edge within `range` cells behind the target.
function Grid.obstacleBehind(g, ent, fromEnt, range)
  if not (g and ent) then
    return nil
  end
  range = range or 2
  local u, v = padOf(g, ent)
  local su, sv = Grid.pushDir(g, ent, fromEnt)
  for dist = 1, range do
    local tu, tv = u + su * dist, v + sv * dist
    if not Grid.inPad(g, tu, tv) then
      return { u = tu, v = tv, dist = dist, kind = "edge" }
    end
    if Grid.isBlocked(g, tu, tv) then
      return { u = tu, v = tv, dist = dist, kind = "prop" }
    end
    if not Grid.canTraverse(g, tu, tv, ent) then
      return { u = tu, v = tv, dist = dist, kind = "wall" }
    end
  end
  return nil
end

--- Push the target up to `maxTiles` pad cells away from the attacker.
function Grid.knockbackTiles(g, ent, fromEnt, maxTiles)
  if not (g and ent) then
    return 0
  end
  maxTiles = maxTiles or 2
  local su, sv = Grid.pushDir(g, ent, fromEnt)
  local moved = 0
  for _ = 1, maxTiles do
    if Grid.step(g, ent, su, sv) then
      moved = moved + 1
    else
      break
    end
  end
  return moved
end

return Grid
