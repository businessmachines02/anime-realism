-- Field battle — async trainer callout bubbles (UI overlay).
--
-- Queue-synced narrator toasts still paint from main.lua; player/foe trainer
-- lines push here on enqueue so they can linger while the battle queue advances.

local Callouts = {}

Callouts.HOLD = 2.0
Callouts.FADE = 0.35
Callouts.POP = 0.14
Callouts.MAX_PER_SIDE = 2

local function font()
  local ok, Font = pcall(require, "src.render.Font")
  return ok and Font or nil
end

function Callouts.anchor(session, side, ow, battle)
  if not (session and side and side ~= "narrator") then
    return nil, nil
  end
  local ent
  if side == "player" then
    ent = ow and ow.player
  else
    ent = session.foe or session.enemyMon
  end
  if not ent then
    return nil, nil
  end
  if ent._fieldScreenX and ent._fieldScreenY then
    return ent._fieldScreenX, ent._fieldScreenY
  end
  -- Fallback when overlay draw order skipped a world stamp this frame.
  local cam = ow and ow.camera
  if not (cam and ent.px) then
    return nil, nil
  end
  local Coords = (session._deps and session._deps.Coords)
    or (package.loaded and package.loaded["coords"])
  if not Coords or type(Coords.worldViewToUi) ~= "function" then
    local ok, mod = pcall(require, "coords")
    Coords = ok and mod or nil
  end
  if not Coords then
    return nil, nil
  end
  local lift = ent._fieldBarLift or 14
  local wx = (ent.px or 0) - (cam.x or 0) + 8
  local wy = (ent.py or 0) - (cam.y or 0) - lift
  local ren = battle and battle.game and battle.game.renderer
  if type(Coords.worldViewToUi) == "function" then
    return Coords.worldViewToUi(wx, wy, ren)
  end
  return wx, wy
end

function Callouts.verticalAxis(session, side, ow)
  local ent
  if side == "player" then
    ent = ow and ow.player
  else
    ent = session and (session.foe or session.enemyMon)
  end
  local f = ent and ent.facing
  if f == "up" or f == "down" then
    return true
  end
  local plan = session and session.plan
  if plan and type(plan.sx) == "number" and type(plan.sy) == "number" then
    if plan.sx == 0 and plan.sy ~= 0 then
      return true
    end
    if math.abs(plan.sy) > math.abs(plan.sx) then
      return true
    end
  end
  return false
end

-- Returns x, y, anchorX, anchorY, placement ("above" | "left" | "right").
function Callouts.bubbleRect(session, side, ow, battle, bw, bh)
  local ax, ay = Callouts.anchor(session, side, ow, battle)
  if not ax then
    return nil
  end
  bw = bw or 48
  bh = bh or 16
  local vertical = Callouts.verticalAxis(session, side, ow)
  local gap = 6
  local x, y, placement

  if vertical then
    y = math.floor(ay - bh * 0.5)
    -- Vertical duels: open bubbles to the sides of each trainer column.
    if side == "player" then
      x = ax - bw - gap
      placement = "left"
      if x < 1 then
        x = ax + gap
        placement = "right"
      end
    else
      x = ax + gap
      placement = "right"
      if x + bw > 159 then
        x = ax - bw - gap
        placement = "left"
      end
    end
  else
    placement = "above"
    x = math.floor(ax - bw / 2)
    y = math.floor(ay - bh - 8)
  end

  x = math.max(1, math.min(159 - bw, x))
  y = math.max(1, math.min(144 - bh, y))
  return x, y, ax, ay, placement
end

function Callouts.push(session, side, text, opts)
  if not (session and side and side ~= "narrator") then
    return false
  end
  text = tostring(text or ""):gsub("\v", "\n"):match("^%s*(.-)%s*$") or ""
  if text == "" then
    return false
  end
  opts = type(opts) == "table" and opts or {}
  session._trainerCallouts = session._trainerCallouts or {}
  local q = session._trainerCallouts[side]
  if not q then
    q = {}
    session._trainerCallouts[side] = q
  end
  q[#q + 1] = {
    text = text,
    age = 0,
    hold = Callouts.HOLD,
    threat = opts.threat == true,
  }
  while #q > Callouts.MAX_PER_SIDE do
    table.remove(q, 1)
  end
  return true
end

function Callouts.tick(session, dt)
  local all = session and session._trainerCallouts
  if not all then
    return
  end
  dt = dt or (1 / 60)
  for side, q in pairs(all) do
    for i = #q, 1, -1 do
      local toast = q[i]
      toast.age = (toast.age or 0) + dt
      local total = (toast.hold or Callouts.HOLD) + Callouts.FADE
      if toast.age >= total then
        table.remove(q, i)
      end
    end
    if #q == 0 then
      all[side] = nil
    end
  end
end

function Callouts.finish(session)
  if session then
    session._trainerCallouts = nil
  end
end

local function wrapText(Font, text, maxPx)
  local lines = {}
  local raw = tostring(text or ""):gsub("\v", "\n")
  local function flushWord(word)
    while word ~= "" do
      if Font.width(word) <= maxPx then
        return word
      end
      local cut = 1
      while cut < #word and Font.width(word:sub(1, cut + 1)) <= maxPx do
        cut = cut + 1
      end
      if cut < 1 then
        cut = 1
      end
      lines[#lines + 1] = word:sub(1, cut)
      word = word:sub(cut + 1)
    end
    return ""
  end
  for chunk in (raw .. "\n"):gmatch("(.-)\n") do
    chunk = chunk:match("^%s*(.-)%s*$") or chunk
    if chunk ~= "" then
      local line = ""
      for word in chunk:gmatch("%S+") do
        local trial = (line == "") and word or (line .. " " .. word)
        if Font.width(trial) <= maxPx then
          line = trial
        else
          if line ~= "" then
            lines[#lines + 1] = line
          end
          line = flushWord(word)
        end
      end
      if line ~= "" then
        lines[#lines + 1] = line
      end
    end
  end
  return lines
end

local function toastAlpha(age, hold)
  age = age or 0
  hold = hold or Callouts.HOLD
  if age < Callouts.POP then
    return age / Callouts.POP
  end
  if age > hold then
    return math.max(0, 1 - (age - hold) / Callouts.FADE)
  end
  return 1
end

local function drawBubble(g, Font, text, anchorX, anchorY, alpha, threat)
  if alpha <= 0 then
    return
  end
  local maxInner = 96
  local padX, padY = 4, 3
  local lineH = 8
  local lines = wrapText(Font, text, maxInner)
  if #lines == 0 then
    lines[1] = ""
  end
  local maxLines = 4
  if #lines > maxLines then
    local trimmed = {}
    for i = 1, maxLines - 1 do
      trimmed[i] = lines[i]
    end
    trimmed[maxLines] = "..."
    lines = trimmed
  end
  local contentW = 0
  for i = 1, #lines do
    contentW = math.max(contentW, Font.width(lines[i]))
  end
  contentW = math.max(32, math.min(maxInner, contentW))
  local bw = contentW + padX * 2
  local bh = padY * 2 + #lines * lineH
  local x = math.floor(anchorX - bw / 2)
  local y = math.floor(anchorY - bh - 9)
  x = math.max(1, math.min(159 - bw, x))
  if y < 1 then
    y = 1
  end

  local fillR, fillG, fillB = 1, 1, 1
  if threat then
    fillR, fillG, fillB = 1.00, 0.78, 0.74
  end

  g.push("all")
  g.setColor(fillR, fillG, fillB, alpha)
  g.rectangle("fill", x, y, bw, bh)
  g.setColor(0, 0, 0, alpha)
  g.rectangle("line", x + 0.5, y + 0.5, bw - 1, bh - 1)
  g.rectangle("line", x + 1.5, y + 1.5, bw - 3, bh - 3)

  local tailX = math.max(x + 5, math.min(x + bw - 5, anchorX))
  g.setColor(fillR, fillG, fillB, alpha)
  g.polygon("fill", tailX - 4, y + bh - 1,
    tailX + 4, y + bh - 1, anchorX, math.min(anchorY - 2, y + bh + 6))
  g.setColor(0, 0, 0, alpha)
  g.line(tailX - 4, y + bh - 1,
    anchorX, math.min(anchorY - 2, y + bh + 6))
  g.line(anchorX, math.min(anchorY - 2, y + bh + 6),
    tailX + 4, y + bh - 1)

  g.setColor(0, 0, 0, alpha)
  local textX = x + padX
  local ty = y + padY
  for i = 1, #lines do
    local codes = Font.encode(lines[i])
    local tx = textX
    for j = 1, #codes do
      Font.drawCode(codes[j], tx, ty)
      tx = tx + (Font.advanceOf(codes[j]) or 8)
    end
    ty = ty + lineH
  end
  g.setColor(1, 1, 1, 1)
  g.pop()
end

local function looksThreat(text, side, flagged)
  if flagged then
    return true
  end
  if side ~= "foe" then
    return false
  end
  local s = tostring(text or ""):upper()
  return s:find("\nUSE ", 1, true) ~= nil
    or s:find(", USE ", 1, true) ~= nil
    or s:find("\nGO! ", 1, true) ~= nil
end

function Callouts.draw(session, battle)
  if not (session and session._trainerCallouts and love and love.graphics) then
    return
  end
  local Font = font()
  if not Font then
    return
  end
  local ow = battle and battle.game and battle.game.overworld
  local g = love.graphics
  for si = 1, 2 do
    local side = (si == 1) and "player" or "foe"
    local q = session._trainerCallouts[side]
    if q then
      local ax, ay = Callouts.anchor(session, side, ow, battle)
      if ax then
        for i = 1, #q do
          local toast = q[i]
          local alpha = toastAlpha(toast.age, toast.hold)
          local stackLift = (#q - i) * 14
          drawBubble(g, Font, toast.text, ax, ay - stackLift, alpha,
            looksThreat(toast.text, side, toast.threat))
        end
      end
    end
  end
end

return Callouts
