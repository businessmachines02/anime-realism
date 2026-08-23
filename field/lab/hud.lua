-- Lab chrome: matchup, authored round, roster picker.

local Roster = require("roster")
local Species = require("species")
local Script = require("script")

local Hud = {}

local ROW_H = 16
local VISIBLE = 20
local SCRIPT_W = 300
local SCRIPT_VISIBLE = 22
local STRIP_H = 108
local PALETTE_H = 78

function Hud.new(stage)
  return setmetatable({
    stage = stage,
    open = false,
    side = "player",
    filter = "",
    cursor = 1,
    scroll = 0,
    scriptScroll = 0,
    hits = {},
  }, { __index = Hud })
end

function Hud.toggle(self, side)
  if side then
    self.side = side
  end
  self.open = not self.open
  if self.open then
    self.filter = ""
    Hud.focusSide(self, self.side)
  end
end

function Hud.filtered(self)
  return Roster.filter(self.stage.roster or {}, self.filter)
end

function Hud.cursorOf(self, rosterIndex)
  local rows = Hud.filtered(self)
  for i = 1, #rows do
    if rows[i]._index == rosterIndex then
      return i
    end
  end
  return 1
end

function Hud.focusSide(self, side)
  self.side = side or self.side
  self.cursor = Hud.cursorOf(
    self, self.stage[self.side == "enemy" and "enemyIndex" or "playerIndex"] or 1)
  Hud.clamp(self)
end

function Hud.clamp(self)
  local rows = Hud.filtered(self)
  if self.cursor < 1 then
    self.cursor = 1
  end
  if self.cursor > #rows then
    self.cursor = math.max(1, #rows)
  end
  if self.cursor < self.scroll + 1 then
    self.scroll = math.max(0, self.cursor - 1)
  end
  if self.cursor > self.scroll + VISIBLE then
    self.scroll = self.cursor - VISIBLE
  end
end

function Hud.move(self, dir)
  self.cursor = self.cursor + dir
  Hud.clamp(self)
end

function Hud.apply(self, index)
  local rows = Hud.filtered(self)
  local row = rows[index or self.cursor]
  if not row then
    return
  end
  local src = row._index or Roster.indexOf(self.stage.roster, row.dex)
  self.stage:setSpecies(self.side, src)
  self.cursor = index or self.cursor
end

function Hud.addMove(self, side, slot)
  local pool = side == "enemy" and self.stage.enemyMoves or self.stage.playerMoves
  local move = pool and pool[slot]
  if not move then
    return
  end
  self.side = side
  self.stage.script:addAttack(side, move)
end

function Hud.addReact(self, side, kind)
  self.side = side or self.side
  self.stage.script:addReact(self.side, kind)
end

local function hpOf(stage, side)
  local b = stage.battle and (side == "enemy" and stage.battle.enemy or stage.battle.player)
  local mon = b and b.mon
  local hp = tonumber(mon and mon.hp)
  local maxHP = tonumber(mon and mon.stats and mon.stats.hp) or 80
  return hp or maxHP, maxHP
end

local function statusText(stage)
  if stage.auto then
    return "REC AI  " .. #(stage.script.beats or {}) .. " beats"
  end
  if stage.hold and (stage.queue[1] or (stage.wait or 0) > 0) then
    return "PAUSED"
  end
  if stage.queue[1] then
    local n = #(stage.script.beats or {})
    return string.format("PLAYING  %d/%d", stage.script.playIndex or 0, n)
  end
  local n = #(stage.script.beats or {})
  if n < 1 then
    return "COMPOSE"
  end
  return string.format("READY  %d beats", n)
end

local function hit(self, id, x, y, w, h, extra)
  local row = { id = id, x = x, y = y, w = w, h = h }
  if extra then
    for k, v in pairs(extra) do
      row[k] = v
    end
  end
  self.hits[#self.hits + 1] = row
end

function Hud.drawStrip(self, g, w)
  local stage = self.stage
  g.setColor(0.05, 0.06, 0.05, 0.86)
  g.rectangle("fill", 0, 0, w, STRIP_H)
  g.setColor(0.95, 0.92, 0.82, 1)
  g.print(statusText(stage)
    .. "   " .. tostring(stage.sceneId or "")
    .. "   zoom x" .. string.format("%.1f", stage.zoom or 2)
    .. "   write " .. string.upper(self.side), 12, 6)

  local function sideLine(side, y, r, gg, b)
    local row = stage.roster[side == "enemy" and stage.enemyIndex or stage.playerIndex]
    local name = side == "enemy" and stage.enemyName or stage.playerName
    local types = side == "enemy" and stage.enemyTypes or stage.playerTypes
    local moves = side == "enemy" and stage.enemyMoves or stage.playerMoves
    local hp, maxHP = hpOf(stage, side)
    local tag = Species.typeTag(types)
    local writing = self.side == side
    g.setColor(r, gg, b, writing and 1 or 0.72)
    g.print(string.format("%s  #%03d  %s   %s",
      side == "enemy" and "ENEMY " or "PLAYER",
      (row and row.dex) or 0, name or "?", tag), 12, y)
    hit(self, "roster", 8, y - 2, 280, 16, { side = side })
    hit(self, "write", 8, y - 2, 70, 16, { side = side })
    local ratio = maxHP > 0 and (hp / maxHP) or 0
    g.setColor(0.18, 0.20, 0.16, 1)
    g.rectangle("fill", 12, y + 14, 160, 5)
    g.setColor(0.35 + (1 - ratio) * 0.5, 0.28 + ratio * 0.55, 0.22, 1)
    g.rectangle("fill", 12, y + 14, math.floor(160 * ratio), 5)
    g.setColor(0.80, 0.82, 0.74, 1)
    local x = 180
    g.print(string.format("HP %d/%d", hp, maxHP), x, y + 11)
    x = x + 86
    for i = 1, math.min(4, #(moves or {})) do
      local id = moves[i].id
      local font = g.getFont()
      local tw = ((font and font.getWidth) and font:getWidth(id) or (#id * 7)) + 10
      g.setColor(0.22, 0.26, 0.18, 0.95)
      g.rectangle("fill", x, y + 10, tw, 14)
      g.setColor(0.92, 0.90, 0.80, 1)
      g.print(id, x + 5, y + 11)
      hit(self, "move", x, y + 10, tw, 14, { side = side, slot = i })
      x = x + tw + 6
    end
  end
  sideLine("player", 24, 0.55, 0.85, 1.0)
  sideLine("enemy", 52, 1.0, 0.55, 0.45)

  g.setColor(0.75, 0.78, 0.70, 1)
  g.print("click a move to queue it    Tab roster    Left/Right write side    1-4 same", 12, 88)
end

function Hud.drawScript(self, g, w, h)
  local stage = self.stage
  local script = stage.script
  local panelX = w - SCRIPT_W - 10
  local panelY = STRIP_H + 8
  local panelH = h - STRIP_H - PALETTE_H - 16
  g.setColor(0.07, 0.08, 0.07, 0.92)
  g.rectangle("fill", panelX, panelY, SCRIPT_W, panelH)
  g.setColor(0.95, 0.92, 0.82, 1)
  g.print("ROUND", panelX + 10, panelY + 8)

  local btns = {
    { id = "play", label = "PLAY" },
    { id = "step", label = "STEP" },
    { id = "again", label = "AGAIN" },
    { id = "clear", label = "CLEAR" },
  }
  local bx = panelX + 10
  for i = 1, #btns do
    local bw = 66
    g.setColor(0.24, 0.32, 0.20, 1)
    g.rectangle("fill", bx, panelY + 26, bw, 18)
    g.setColor(0.94, 0.93, 0.84, 1)
    g.print(btns[i].label, bx + 8, panelY + 28)
    hit(self, btns[i].id, bx, panelY + 26, bw, 18)
    bx = bx + bw + 6
  end

  local rows = script.beats
  local replies = Script.replyMarks(script)
  local y0 = panelY + 54
  if self.scriptScroll < 0 then
    self.scriptScroll = 0
  end
  local maxScroll = math.max(0, #rows - SCRIPT_VISIBLE)
  if self.scriptScroll > maxScroll then
    self.scriptScroll = maxScroll
  end
  if script.playIndex > 0 then
    if script.playIndex < self.scriptScroll + 1 then
      self.scriptScroll = math.max(0, script.playIndex - 1)
    elseif script.playIndex > self.scriptScroll + SCRIPT_VISIBLE then
      self.scriptScroll = script.playIndex - SCRIPT_VISIBLE
    end
  end
  if #rows < 1 then
    g.setColor(0.62, 0.64, 0.58, 1)
    g.print("Build an exchange, then Play.", panelX + 10, y0)
    g.print("1. one side uses a move", panelX + 10, y0 + 16)
    g.print("2. other side FIRE / CHARGE / DODGE", panelX + 10, y0 + 32)
    g.print("3. those two play at the same time", panelX + 10, y0 + 48)
  else
    for n = 1, SCRIPT_VISIBLE do
      local i = self.scriptScroll + n
      local beat = rows[i]
      if not beat then
        break
      end
      local y = y0 + (n - 1) * ROW_H
      if i == script.cursor then
        g.setColor(0.26, 0.36, 0.22, 1)
        g.rectangle("fill", panelX + 6, y - 1, SCRIPT_W - 12, ROW_H)
      end
      if i == script.playIndex then
        g.setColor(1.0, 0.86, 0.32, 1)
      elseif beat.side == "enemy" then
        g.setColor(1.0, 0.62, 0.50, 1)
      else
        g.setColor(0.70, 0.88, 1.0, 1)
      end
      local mark = replies[i] and "  -> " or ""
      g.print(string.format("%2d%s%s", i, mark, Script.label(beat)), panelX + 12, y)
      hit(self, "beat", panelX + 6, y - 1, SCRIPT_W - 12, ROW_H, { index = i })
    end
  end
  g.setColor(0.62, 0.64, 0.58, 1)
  g.print("Backspace delete   N step   R again", panelX + 10, panelY + panelH - 20)
end

function Hud.drawPalette(self, g, w, h)
  local stage = self.stage
  local y = h - PALETTE_H
  g.setColor(0.05, 0.06, 0.05, 0.88)
  g.rectangle("fill", 0, y, w, PALETTE_H)
  local side = self.side
  local pool = side == "enemy" and stage.enemyMoves or stage.playerMoves
  local function sideChip(label, who, x0)
    local on = self.side == who
    g.setColor(on and (who == "enemy" and { 0.55, 0.22, 0.16, 1 } or { 0.16, 0.32, 0.42, 1 })
      or { 0.16, 0.16, 0.14, 1 })
    g.rectangle("fill", x0, y + 6, 70, 18)
    g.setColor(on and { 1, 1, 1, 1 } or { 0.7, 0.7, 0.65, 1 })
    g.print(label, x0 + 8, y + 8)
    hit(self, "write", x0, y + 6, 70, 18, { side = who })
  end
  sideChip("PLAYER", "player", 12)
  sideChip("ENEMY", "enemy", 88)

  local x = 168
  for i = 1, math.min(4, #(pool or {})) do
    local id = pool[i].id
    local font = g.getFont()
    local tw = ((font and font.getWidth) and font:getWidth(i .. " " .. id) or (#id * 7 + 16)) + 18
    g.setColor(0.22, 0.26, 0.18, 1)
    g.rectangle("fill", x, y + 6, tw, 18)
    g.setColor(0.94, 0.92, 0.82, 1)
    g.print(i .. " " .. id, x + 6, y + 8)
    hit(self, "move", x, y + 6, tw, 18, { side = side, slot = i })
    x = x + tw + 6
  end

  x = 12
  for i = 1, #Script.REACTS do
    local row = Script.REACTS[i]
    local label = row.key:upper() .. " " .. row.label
    local font = g.getFont()
    local tw = ((font and font.getWidth) and font:getWidth(label) or (#label * 7)) + 14
    g.setColor(0.20, 0.18, 0.16, 1)
    g.rectangle("fill", x, y + 32, tw, 18)
    g.setColor(0.90, 0.88, 0.78, 1)
    g.print(label, x + 6, y + 34)
    hit(self, "react", x, y + 32, tw, 18, { kind = row.id })
    x = x + tw + 6
  end
  g.setColor(0.70, 0.72, 0.64, 1)
  g.print("Space play    A rec AI    L load last    K reset pad    T theme    O props", 12, y + 56)
end

function Hud.drawRoster(self, g, w, h)
  if not self.open then
    return
  end
  local panelW = 360
  local panelX = 16
  local panelY = STRIP_H + 8
  local panelH = math.min(VISIBLE * ROW_H + 48, h - STRIP_H - PALETTE_H - 20)
  g.setColor(0.08, 0.09, 0.08, 0.94)
  g.rectangle("fill", panelX, panelY, panelW, panelH)
  g.setColor(0.95, 0.92, 0.82, 1)
  local title = (self.side == "enemy" and "SPAWN ENEMY" or "SPAWN PLAYER")
  g.print(title .. "   filter: " .. (self.filter ~= "" and self.filter or "_"), panelX + 8, panelY + 8)

  local rows = Hud.filtered(self)
  Hud.clamp(self)
  local y0 = panelY + 30
  local shown = math.floor((panelH - 48) / ROW_H)
  for n = 1, shown do
    local i = self.scroll + n
    local row = rows[i]
    if not row then
      break
    end
    local y = y0 + (n - 1) * ROW_H
    if i == self.cursor then
      g.setColor(0.28, 0.42, 0.22, 1)
      g.rectangle("fill", panelX + 4, y - 1, panelW - 8, ROW_H)
    end
    local mine = (self.side == "enemy" and self.stage.enemyIndex or self.stage.playerIndex)
    if (row._index or i) == mine then
      g.setColor(1.0, 0.92, 0.35, 1)
    else
      g.setColor(0.92, 0.90, 0.82, 1)
    end
    local tag = Species.typeTag(Species.types(row.dex))
    g.print(string.format("#%03d  %-12s  %s", row.dex, row.name, tag), panelX + 10, y)
    hit(self, "row", panelX + 4, y - 1, panelW - 8, ROW_H, { index = i })
  end
  g.setColor(0.65, 0.68, 0.60, 1)
  g.print(#rows .. " kits    Enter spawn    Esc close", panelX + 8, panelY + panelH - 18)
end

function Hud.draw(self)
  if not (love and love.graphics and self.stage) then
    return
  end
  local g = love.graphics
  local w, h = g.getWidth(), g.getHeight()
  self.hits = {}
  Hud.drawStrip(self, g, w)
  Hud.drawScript(self, g, w, h)
  Hud.drawPalette(self, g, w, h)
  Hud.drawRoster(self, g, w, h)
  g.setColor(1, 1, 1, 1)
end

function Hud.hitAt(self, x, y)
  for i = #self.hits, 1, -1 do
    local b = self.hits[i]
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      return b
    end
  end
  return nil
end

function Hud.keypressed(self, key)
  if key == "tab" then
    Hud.toggle(self)
    return true
  end
  if (key == "p" or key == "e") and not self.open then
    self._ignoreText = true
    Hud.toggle(self, key == "e" and "enemy" or "player")
    return true
  end
  if self.open then
    if key == "escape" then
      self.open = false
      return true
    end
    if key == "left" then
      Hud.focusSide(self, "player")
      return true
    end
    if key == "right" then
      Hud.focusSide(self, "enemy")
      return true
    end
    if key == "up" then
      Hud.move(self, -1)
      return true
    end
    if key == "down" then
      Hud.move(self, 1)
      return true
    end
    if key == "pageup" then
      Hud.move(self, -VISIBLE)
      return true
    end
    if key == "pagedown" then
      Hud.move(self, VISIBLE)
      return true
    end
    if key == "return" or key == "kpenter" then
      Hud.apply(self)
      return true
    end
    if key == "backspace" then
      self.filter = self.filter:sub(1, math.max(0, #self.filter - 1))
      self.cursor = 1
      Hud.clamp(self)
      return true
    end
    return true
  end

  if key == "space" then
    self.stage:toggleHold()
    return true
  end
  if key == "n" then
    self.stage:stepScript()
    return true
  end
  if key == "r" then
    self.stage:replayScript()
    return true
  end
  if key == "backspace" then
    self.stage.script:remove()
    return true
  end
  if key == "delete" then
    self.stage.script:clear()
    return true
  end
  if key == "left" then
    self.side = "player"
    return true
  end
  if key == "right" then
    self.side = "enemy"
    return true
  end
  if key == "up" then
    local script = self.stage.script
    script.cursor = math.max(1, (script.cursor or 1) - 1)
    return true
  end
  if key == "down" then
    local script = self.stage.script
    script.cursor = math.min(#script.beats, (script.cursor or 1) + 1)
    return true
  end
  local digit = tonumber(key:match("^(%d)$") or key:match("^kp(%d)$"))
  if digit and digit >= 1 and digit <= 4 then
    Hud.addMove(self, self.side, digit)
    return true
  end
  for i = 1, #Script.REACTS do
    local row = Script.REACTS[i]
    if key == row.key then
      Hud.addReact(self, self.side, row.id)
      return true
    end
  end
  return false
end

function Hud.textinput(self, text)
  if self._ignoreText then
    self._ignoreText = nil
    return true
  end
  if not self.open then
    return false
  end
  if text == "\t" or text == "\n" then
    return true
  end
  self.filter = (self.filter .. text):upper()
  self.cursor = 1
  Hud.clamp(self)
  return true
end

function Hud.wheel(self, x, y, dy)
  if self.open then
    Hud.move(self, dy > 0 and -3 or 3)
    return true
  end
  local w = love.graphics.getWidth()
  if x and x >= w - SCRIPT_W - 10 then
    self.scriptScroll = self.scriptScroll + (dy > 0 and -3 or 3)
    return true
  end
  return false
end

function Hud.click(self, x, y, button)
  local cell = Hud.hitAt(self, x, y)
  if not cell then
    return false
  end
  if button == 2 and cell.id == "beat" then
    self.stage.script:remove(cell.index)
    return true
  end
  if cell.id == "roster" then
    if self.open and self.side == cell.side then
      self.open = false
    else
      self.open = true
      self.filter = ""
      Hud.focusSide(self, cell.side)
    end
    return true
  end
  if cell.id == "write" then
    self.side = cell.side
    return true
  end
  if cell.id == "move" then
    Hud.addMove(self, cell.side, cell.slot)
    return true
  end
  if cell.id == "react" then
    Hud.addReact(self, self.side, cell.kind)
    return true
  end
  if cell.id == "beat" then
    self.stage.script.cursor = cell.index
    if button == 1 then
      self.side = self.stage.script.beats[cell.index].side
    end
    return true
  end
  if cell.id == "play" then
    self.stage:playScript(1)
    return true
  end
  if cell.id == "step" then
    self.stage:stepScript()
    return true
  end
  if cell.id == "again" then
    self.stage:replayScript()
    return true
  end
  if cell.id == "clear" then
    self.stage.script:clear()
    return true
  end
  if cell.id == "row" then
    self.cursor = cell.index
    Hud.apply(self, cell.index)
    return true
  end
  return false
end

return Hud
