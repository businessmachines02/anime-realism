-- Reference-style FIELD UI.
-- Draw-only: BattleState still owns phases, cursors, input, and turn logic.

local UI = {}

UI.WIDTH = 160
UI.HEIGHT = 144

local function font()
  local ok, Font = pcall(require, "src.render.Font")
  return ok and Font or nil
end

local function clamp01(n)
  n = tonumber(n) or 0
  if n < 0 then return 0 end
  if n > 1 then return 1 end
  return n
end

local function battlerHP(battler)
  local mon = battler and battler.mon
  local maxHP = mon and mon.stats and tonumber(mon.stats.hp) or 1
  local hp = tonumber(battler and battler.shownHP) or tonumber(mon and mon.hp) or 0
  return clamp01(hp / math.max(1, maxHP))
end

local function fitText(Font, value, maxWidth)
  local text = tostring(value or "POKéMON")
  if not (Font and type(Font.width) == "function") then
    return text
  end
  if Font.width(text) <= maxWidth then
    return text
  end
  while #text > 1 and Font.width(text .. "+") > maxWidth do
    text = text:sub(1, -2)
  end
  return text .. "+"
end

local function box(g, x, y, w, h)
  g.setColor(0.96, 0.92, 0.82, 0.96)
  g.rectangle("fill", x, y, w, h)
  g.setColor(0.10, 0.07, 0.06, 1)
  g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  if w > 3 and h > 3 then
    g.rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3)
  end
end

local function hpBar(g, x, y, w, ratio)
  ratio = clamp01(ratio)
  g.setColor(0.12, 0.09, 0.08, 1)
  g.rectangle("fill", x, y, w, 4)
  g.setColor(0.96, 0.92, 0.78, 1)
  g.rectangle("fill", x + 1, y + 1, w - 2, 2)
  local fill = math.floor((w - 2) * ratio + 0.5)
  if fill > 0 then
    if ratio <= 0.2 then
      g.setColor(0.78, 0.18, 0.12, 1)
    elseif ratio <= 0.5 then
      g.setColor(0.88, 0.62, 0.12, 1)
    else
      g.setColor(0.20, 0.62, 0.24, 1)
    end
    g.rectangle("fill", x + 1, y + 1, fill, 2)
  end
end

function UI.active(battle)
  return battle ~= nil
    and (battle._arAnimeField or battle._arFieldCombat or battle._arFieldStandalone)
end

function UI.layoutState(battle)
  local phase = battle and battle.phase or ""
  return {
    phase = phase,
    showHUD = false,
    showCommand = phase == "menu",
    showMoves = phase == "moveSelect" or phase == "mimicSelect",
    showDialogue = phase == "messages" and not battle._arFieldBubbleDialogue,
    menuIndex = battle and battle.menuIndex or 1,
    moveIndex = phase == "mimicSelect"
      and (battle and battle.mimicIndex or 1)
      or (battle and battle.moveIndex or 1),
  }
end

local function fieldEntity(battle, side)
  local ow = battle and battle.game and battle.game.overworld
  for i = 1, #(ow and ow.entities or {}) do
    local ent = ow.entities[i]
    if ent and ent._arFieldBattler and ent._arFieldSide == side
        and not ent.hidden and not ent._removed then
      return ent
    end
  end
  return nil
end

local function drawWorldHP(g, battle)
  local ow = battle and battle.game and battle.game.overworld
  local cam = ow and ow.camera
  if not cam then return end
  for _, item in ipairs({
    { side = "player", battler = battle.player },
    { side = "enemy", battler = battle.enemy },
  }) do
    local ent = fieldEntity(battle, item.side)
    if ent then
      local x = math.floor((ent.px or 0) - (cam.x or 0) + 8.5)
      local y = math.floor((ent.py or 0) - (cam.y or 0) - 5.5)
      x = math.max(12, math.min(148, x))
      y = math.max(3, math.min(136, y))
      hpBar(g, x - 11, y, 22, battlerHP(item.battler))
      -- Tiny downward pointer keeps the bar visually attached to its Pokémon.
      g.setColor(0.12, 0.09, 0.08, 1)
      g.polygon("fill", x - 1, y + 4, x + 1, y + 4, x, y + 6)
    end
  end
end

local function drawScaled(g, Font, text, x, y, scale)
  if not (Font and type(Font.draw) == "function") then return end
  g.push()
  g.translate(x, y)
  g.scale(scale, scale)
  Font.draw(text, 0, 0)
  g.pop()
end

local function drawCodeScaled(g, Font, code, x, y, scale)
  if not (Font and type(Font.drawCode) == "function") then return end
  g.push()
  g.translate(x, y)
  g.scale(scale, scale)
  Font.drawCode(code, 0, 0)
  g.pop()
end

local function commandLabels(battle)
  if battle and battle.safari then
    return { "BALL", "BAIT", "ROCK", "RUN" }
  end
  return { "FIGHT", "PKMN", "ITEM", "RUN" }
end

local function drawCommand(g, Font, battle)
  local x, y, w, h = 94, 110, 64, 32
  box(g, x, y, w, h)
  local labels = commandLabels(battle)
  local index = math.max(1, math.min(4, battle.menuIndex or 1))
  for i = 1, 4 do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local tx = x + 10 + col * 29
    local ty = y + 5 + row * 13
    drawScaled(g, Font, labels[i], tx, ty, 0.72)
    if i == index then
      drawCodeScaled(g, Font, 0xED, tx - 7, ty, 0.72)
    end
  end
end

local function moveRows(battle)
  if battle.phase == "mimicSelect" then
    return battle.mimicMoves or {}
  end
  return battle.player and battle.player.curMoves or {}
end

local function moveName(battle, move)
  if not move then return "-" end
  local def = battle.data and battle.data.moves and battle.data.moves[move.id]
  return def and def.name or tostring(move.id or "-")
end

local function drawMoves(g, Font, battle)
  local x, y, w, h = 34, 96, 124, 46
  box(g, x, y, w, h)
  local rows = moveRows(battle)
  local index = battle.phase == "mimicSelect"
    and (battle.mimicIndex or 1) or (battle.moveIndex or 1)
  for i = 1, math.min(4, #rows) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local cx = x + 3 + col * 60
    local cy = y + 3 + row * 16
    local selected = i == index
    if selected then
      g.setColor(0.18, 0.29, 0.48, 1)
    else
      g.setColor(0.90, 0.87, 0.76, 1)
    end
    g.rectangle("fill", cx, cy, 58, 15)
    g.setColor(0.10, 0.08, 0.06, 1)
    g.rectangle("line", cx + 0.5, cy + 0.5, 57, 14)
    g.setColor(selected and 1 or 0.10, selected and 1 or 0.08,
      selected and 1 or 0.06, 1)
    drawScaled(g, Font,
      fitText(Font, moveName(battle, rows[i]), 82), cx + 7, cy + 3, 0.62)
    if i == index then
      drawCodeScaled(g, Font, 0xED, cx + 1, cy + 3, 0.62)
    elseif battle.moveSwapIndex == i then
      drawCodeScaled(g, Font, 0xEC, cx + 1, cy + 3, 0.62)
    end
  end
  if battle.phase == "moveSelect" then
    local move = rows[index]
    if move and Font and type(Font.draw) == "function" then
      local def = battle.data and battle.data.moves and battle.data.moves[move.id]
      local typeName = def and def.type and tostring(def.type):gsub("_TYPE$", "") or ""
      local pp = tonumber(move.pp) or 0
      local maxPP = def and ((def.pp or 0)
        + (move.ppUps or 0) * math.floor((def.pp or 0) / 5)) or pp
      g.setColor(0.10, 0.08, 0.06, 1)
      g.line(x + 3, y + h - 11.5, x + w - 3, y + h - 11.5)
      drawScaled(g, Font, fitText(Font, typeName, 72),
        x + 5, y + h - 9, 0.58)
      drawScaled(g, Font, ("PP %d/%d"):format(pp, maxPP),
        x + 78, y + h - 9, 0.58)
    end
  end
end

local function drawDialogue(g, Font, battle)
  local shown = battle.shown or {}
  if #shown == 0 and not (battle.current or battle.msgHold
      or battle.msgWaiting or battle.msgPrompt) then
    return
  end
  local x, y, w, h = 4, 119, 152, 23
  box(g, x, y, w, h)
  g.setColor(0.08, 0.06, 0.05, 1)
  local first = math.max(1, #shown - 1)
  for lineIndex = first, #shown do
    local line = shown[lineIndex]
    local ty = y + 3 + (lineIndex - first) * 9
    if Font and type(Font.drawCode) == "function" then
      for i = 1, math.min(#line, 18) do
        Font.drawCode(line[i], x + 5 + (i - 1) * 8, ty)
      end
    end
  end
  if (battle.msgWaiting or battle.msgPrompt)
      and (battle.frame or 0) % 60 < 30 then
    if Font and type(Font.drawCode) == "function" then
      Font.drawCode(0xEE, x + w - 11, y + h - 9)
    end
  end
end

function UI.draw(battle)
  if not (UI.active(battle) and love and love.graphics) then
    return
  end
  local g = love.graphics
  local Font = font()
  local state = UI.layoutState(battle)
  g.push("all")
  if state.showCommand then
    drawCommand(g, Font, battle)
  elseif state.showMoves then
    drawMoves(g, Font, battle)
  elseif state.showDialogue then
    drawDialogue(g, Font, battle)
  end
  g.setColor(1, 1, 1, 1)
  g.pop()
end

return UI
