-- Visual sandbox for field sprites, cues, and authored rounds.
-- Run from the mod root:  ./field/lab/run.sh

local function labDir()
  if love and love.filesystem and type(love.filesystem.getSource) == "function" then
    local src = love.filesystem.getSource()
    if type(src) == "string" and src ~= "" then
      return src:gsub("[/\\]+$", "")
    end
  end
  local info = debug.getinfo(1, "S")
  local src = info and info.source
  if type(src) == "string" then
    return src:gsub("^@", ""):gsub("[/\\]main%.lua$", "")
  end
  return "."
end

local function modRootFromLab(dir)
  return dir:gsub("[/\\]field[/\\]lab$", "")
end

local Boot = require("boot")
local Stage = require("stage")
local Roster = require("roster")
local Hud = require("hud")

local mods
local stage
local hud
local onceFrames = 0
local once = false
for i = 1, #(arg or {}) do
  if arg[i] == "--once" then
    once = true
  end
end

function love.load()
  local root = modRootFromLab(labDir())
  mods = Boot(root)
  if love.graphics and type(love.graphics.setDefaultFilter) == "function" then
    love.graphics.setDefaultFilter("nearest", "nearest")
  end
  local roster = Roster.scan(root)
  stage = Stage.new(mods, {
    auto = false,
    roster = roster,
    playerIndex = Roster.indexOf(roster, 25),
    enemyIndex = Roster.indexOf(roster, 76),
  })
  hud = Hud.new(stage)
end

function love.update(dt)
  if stage then
    stage:tick(dt)
  end
  if once then
    onceFrames = onceFrames + 1
    if onceFrames >= 4 then
      love.event.quit()
    end
  end
end

function love.draw()
  if not stage then
    return
  end
  local g = love.graphics
  g.clear(0.10, 0.14, 0.11, 1)
  local zoom = stage.zoom or 2
  g.push()
  g.scale(zoom, zoom)
  stage:drawWorld()
  g.pop()
  if hud then
    hud:draw()
  end
end

function love.keypressed(key)
  if hud and hud:keypressed(key) then
    return
  end
  if key == "escape" then
    love.event.quit()
    return
  end
  if key == "a" then
    stage:setAuto(not stage.auto)
    return
  end
  if key == "l" then
    stage:loadRound()
    return
  end
  if key == "o" then
    stage:injectProps(2 + math.random(3))
    return
  end
  if key == "t" then
    Stage.cycleScene(stage, 1)
    return
  end
  if key == "k" then
    local script = stage.script
    Stage.rebuild(stage)
    stage.script = script
    stage.auto = false
    return
  end
  if key == "[" then
    stage:cycleSpecies(hud and hud.side or "player", -1)
    return
  end
  if key == "]" then
    stage:cycleSpecies(hud and hud.side or "player", 1)
    return
  end
  if key == "x" then
    stage:swapSides()
    return
  end
  if key == "y" then
    stage:randomPair()
    return
  end
  if key == "h" then
    stage:heal()
    return
  end
end

function love.textinput(text)
  if hud then
    hud:textinput(text)
  end
end

function love.mousepressed(x, y, button)
  if hud and (button == 1 or button == 2) then
    hud:click(x, y, button)
  end
end

function love.wheelmoved(x, y)
  local mx, my = 0, 0
  if love.mouse then
    mx, my = love.mouse.getPosition()
  end
  if hud and hud:wheel(mx, my, y) then
    return
  end
  local zoom = (stage.zoom or 2) + (y > 0 and 0.25 or -0.25)
  if zoom < 1 then
    zoom = 1
  elseif zoom > 6 then
    zoom = 6
  end
  stage.zoom = zoom
end
