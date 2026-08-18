-- Field battle — pad ↔ world ↔ pixel conversions.
--
-- Pad cell (u, v) is truth in Live; world cells (cellX/cellY) and pixels
-- (px/py) are derived for drawing and entity sync. axes(sx,sy) builds the
-- fight-forward (u) and lateral (v) basis from the player→foe vector.

local Coords = {}
Coords.CELL = 16

local function unitCardinal(sx, sy)
  sx = sx or 1
  sy = sy or 0
  if math.abs(sx) >= math.abs(sy) then
    if sx == 0 and sy == 0 then
      return 1, 0
    end
    return (sx >= 0) and 1 or -1, 0
  end
  return 0, (sy >= 0) and 1 or -1
end

--- Fight axis → pad axes. v is 90° CCW from u (dodge / lateral).
function Coords.axes(sx, sy)
  local ux, uy = unitCardinal(sx, sy)
  return { x = ux, y = uy }, { x = -uy, y = ux }
end

function Coords.key(u, v)
  u = math.floor((tonumber(u) or 0) + 0.5)
  v = math.floor((tonumber(v) or 0) + 0.5)
  return tostring(u) .. "," .. tostring(v)
end

--- Fit a world-cell AABB onto pad axes. Origin is the player-side corner
--- so u runs player → foe and v is the perpendicular dodge axis.
function Coords.layoutPad(rect, sx, sy)
  local uAxis, vAxis = Coords.axes(sx, sy)
  local minX = (rect and rect.minX) or 0
  local maxX = (rect and rect.maxX) or minX
  local minY = (rect and rect.minY) or 0
  local maxY = (rect and rect.maxY) or minY

  local originWx, originWy
  if uAxis.x ~= 0 then
    originWx = (uAxis.x > 0) and minX or maxX
  else
    originWx = (vAxis.x > 0) and minX or maxX
  end
  if uAxis.y ~= 0 then
    originWy = (uAxis.y > 0) and minY or maxY
  else
    originWy = (vAxis.y > 0) and minY or maxY
  end

  local function pu(wx, wy)
    return (wx - originWx) * uAxis.x + (wy - originWy) * uAxis.y
  end
  local function pv(wx, wy)
    return (wx - originWx) * vAxis.x + (wy - originWy) * vAxis.y
  end

  local maxU, maxV = 0, 0
  local corners = {
    { minX, minY }, { maxX, minY }, { minX, maxY }, { maxX, maxY },
  }
  for i = 1, 4 do
    local u = pu(corners[i][1], corners[i][2])
    local v = pv(corners[i][1], corners[i][2])
    if u > maxU then
      maxU = u
    end
    if v > maxV then
      maxV = v
    end
  end

  return {
    originWx = originWx,
    originWy = originWy,
    uAxis = uAxis,
    vAxis = vAxis,
    sizeU = maxU + 1,
    sizeV = maxV + 1,
    minX = minX,
    maxX = maxX,
    minY = minY,
    maxY = maxY,
  }
end

function Coords.applyLayout(g, layout)
  if not (g and layout) then
    return g
  end
  g.originWx = layout.originWx
  g.originWy = layout.originWy
  g.uAxis = layout.uAxis
  g.vAxis = layout.vAxis
  g.sizeU = layout.sizeU
  g.sizeV = layout.sizeV
  g.minX = layout.minX
  g.maxX = layout.maxX
  g.minY = layout.minY
  g.maxY = layout.maxY
  return g
end

function Coords.worldToPad(g, wx, wy)
  if not g then
    return 0, 0
  end
  local ux = g.uAxis and g.uAxis.x or 1
  local uy = g.uAxis and g.uAxis.y or 0
  local vx = g.vAxis and g.vAxis.x or 0
  local vy = g.vAxis and g.vAxis.y or 1
  local ox, oy = g.originWx or 0, g.originWy or 0
  local u = (wx - ox) * ux + (wy - oy) * uy
  local v = (wx - ox) * vx + (wy - oy) * vy
  return math.floor(u + 0.5), math.floor(v + 0.5)
end

function Coords.padToWorld(g, u, v)
  if not g then
    return u or 0, v or 0
  end
  local ux = g.uAxis and g.uAxis.x or 1
  local uy = g.uAxis and g.uAxis.y or 0
  local vx = g.vAxis and g.vAxis.x or 0
  local vy = g.vAxis and g.vAxis.y or 1
  local ox, oy = g.originWx or 0, g.originWy or 0
  u, v = u or 0, v or 0
  return ox + u * ux + v * vx, oy + u * uy + v * vy
end

function Coords.padToPx(g, u, v)
  local wx, wy = Coords.padToWorld(g, u, v)
  return wx * Coords.CELL, wy * Coords.CELL
end

function Coords.padCenterPx(g, u, v)
  local px, py = Coords.padToPx(g, u, v)
  return px + 8, py + 8
end

function Coords.inPad(g, u, v)
  if not g then
    return false
  end
  u = math.floor((u or 0) + 0.5)
  v = math.floor((v or 0) + 0.5)
  local su, sv = g.sizeU or 0, g.sizeV or 0
  return u >= 0 and v >= 0 and u < su and v < sv
end

function Coords.clampPad(g, u, v)
  u = math.floor((u or 0) + 0.5)
  v = math.floor((v or 0) + 0.5)
  local su = math.max(1, g and g.sizeU or 1)
  local sv = math.max(1, g and g.sizeV or 1)
  if u < 0 then
    u = 0
  elseif u > su - 1 then
    u = su - 1
  end
  if v < 0 then
    v = 0
  elseif v > sv - 1 then
    v = sv - 1
  end
  return u, v
end

--- World delta of a pad step (for facing / camera).
function Coords.padDeltaToWorld(g, du, dv)
  local ux = g and g.uAxis and g.uAxis.x or 1
  local uy = g and g.uAxis and g.uAxis.y or 0
  local vx = g and g.vAxis and g.vAxis.x or 0
  local vy = g and g.vAxis and g.vAxis.y or 1
  du, dv = du or 0, dv or 0
  return du * ux + dv * vx, du * uy + dv * vy
end

--- Map a point on the world canvas (cam-relative pixels) onto the UI canvas.
--- World survey zoom uses a larger/smaller view than the classic 160×144 UI;
--- both are centered in the window, so this matches Renderer letterboxing.
function Coords.worldViewToUi(sx, sy, ren)
  sx = tonumber(sx) or 0
  sy = tonumber(sy) or 0
  if type(ren) ~= "table" then
    return sx, sy
  end
  local uiw, uih = 160, 144
  local vw, vh = uiw, uih
  if type(ren.uiSize) == "function" then
    local a, b = ren:uiSize()
    if type(a) == "number" then
      uiw, uih = a, b or uih
    end
  end
  if type(ren.worldViewSize) == "function" then
    local a, b = ren:worldViewSize()
    if type(a) == "number" and a > 0 then
      vw, vh = a, b or vh
    end
  end
  if vw < 1 or vh < 1 then
    return sx, sy
  end
  local Sp = 1
  if type(ren.fitScale) == "function" then
    Sp = tonumber(ren:fitScale()) or 1
  end
  if Sp < 1 then
    Sp = 1
  end
  local sp = Sp
  local okZ, Zoom = pcall(require, "src.render.Zoom")
  if okZ and Zoom and type(Zoom.scale) == "function" then
    sp = tonumber(Zoom.scale(Sp)) or Sp
  end
  if sp < 1 then
    sp = 1
  end
  local ux = (uiw * 0.5) + (sx - vw * 0.5) * (sp / Sp)
  local uy = (uih * 0.5) + (sy - vh * 0.5) * (sp / Sp)
  return ux, uy
end

return Coords
