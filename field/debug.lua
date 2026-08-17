-- Field battle — dev-only pad grid overlay (occupancy, blocked, homes).
-- Enable via anime_realism `dev_overlay`. Colors:
--   red tint     blocked (survey)
--   yellow tint  occupied
--   green tint   home pads
--   faint fill   walkable empty

local Coords = require("coords")

local Debug = {}

local function camXY(battle)
  local cam = battle and battle.game and battle.game.overworld
      and battle.game.overworld.camera
  if not cam then
    return 0, 0
  end
  return cam.x or 0, cam.y or 0
end

local function cellColor(g, u, v, homes)
  if g.blocked[Coords.key(u, v)] then
    return 0.85, 0.2, 0.15, 0.45
  end
  local who = g.occ[Coords.key(u, v)]
  if who then
    return 0.95, 0.85, 0.15, 0.40
  end
  if homes[Coords.key(u, v)] then
    return 0.2, 0.85, 0.45, 0.35
  end
  return 1, 1, 1, 0.12
end

function Debug.draw(session, battle)
  if not (session and session.live and session.grid) then
    return
  end
  if not (love and love.graphics) then
    return
  end
  local g = session.grid
  if not (g.sizeU and g.sizeV and g.uAxis) then
    return
  end
  local camX, camY = camXY(battle)
  local homeTag = {
    player = "P",
    enemy = "E",
    playerTrainer = "PT",
    enemyTrainer = "ET",
  }
  local homes = {}
  if g.home then
    for name, h in pairs(g.home) do
      if h and h.u ~= nil then
        homes[Coords.key(h.u, h.v)] = homeTag[name] or name
      end
    end
  end

  local lg = love.graphics
  lg.push()
  local font = lg.getFont and lg.getFont()
  for u = 0, (g.sizeU or 1) - 1 do
    for v = 0, (g.sizeV or 1) - 1 do
      local px, py = Coords.padToPx(g, u, v)
      local x, y = px - camX, py - camY
      local r, gr, b, a = cellColor(g, u, v, homes)
      lg.setColor(r, gr, b, a)
      lg.rectangle("fill", x, y, 16, 16)
      lg.setColor(r, gr, b, math.min(1, a + 0.35))
      lg.rectangle("line", x, y, 16, 16)
      local who = g.occ[Coords.key(u, v)]
      local label = homes[Coords.key(u, v)]
      if who or label then
        lg.setColor(1, 1, 1, 0.9)
        local text = label or tostring(who):gsub("^ar_fbv_", "")
        if #text > 4 then
          text = text:sub(1, 4)
        end
        if font and lg.print then
          lg.print(text, x + 1, y + 1)
        end
      end
    end
  end
  lg.setColor(1, 1, 1, 1)
  lg.pop()
end

return Debug
