local script = (arg and arg[0]) or "field_battle/tests/run_grid_tests.lua"
local root = script:gsub("[/\\]tests[/\\][^/\\]+$", "")

local function load(name)
  local chunk, err = loadfile(root .. "/" .. name)
  assert(chunk, err)
  return chunk()
end

local function eq(actual, expected, label)
  assert(actual == expected, ("%s: expected %s, got %s")
    :format(label or "value", tostring(expected), tostring(actual)))
end

local function truthy(value, label)
  assert(value, label or "expected truthy value")
end

local Coords = load("coords.lua")
package.loaded.coords = Coords
local Themes = load("themes.lua")
package.loaded.themes = Themes
local Grid = load("grid.lua")
local Layout = load("layout.lua")
local Arena = load("arena.lua")
local Survey = load("survey.lua")
local Cues = load("cues.lua")
local Callouts = load("callouts.lua")
local Projectiles = load("projectiles.lua")
local UI = load("ui.lua")
local Lifecycle = load("lifecycle.lua")
local Compat = load("compat.lua")
local Sprites = load("sprites.lua")
local Cast = load("cast.lua")
local Spectators = load("spectators.lua")
local Wildlife = load("wildlife.lua")
local FieldFactory = load("init.lua")
local FieldBattle = FieldFactory({ load = function() return {} end })
local Hooks = load("hooks.lua")

local tests = {}

function tests.field_allows_learn_move_textbox()
  local battle = {
    _arAnimeField = true,
    game = {
      stack = {
        states = {},
        top = function(self)
          return self.states[#self.states]
        end,
      },
    },
  }
  battle.game.stack.states = { battle }
  truthy(not Compat.fieldAllowsStackedBottomUI(battle),
    "no stacked prompt while battle is top")

  local textBox = { boxTx = 0, boxTy = 12, shown = {} } -- translucent TextBox
  battle.game.stack.states = { battle, textBox }
  truthy(Compat.fieldAllowsStackedBottomUI(battle),
    "learn-move TextBox may paint over FIELD")

  local party = { isOpaque = true, screenId = "PartyMenu" }
  battle.game.stack.states = { battle, party }
  truthy(not Compat.fieldAllowsStackedBottomUI(battle),
    "opaque party menu does not unhide battle chrome")

  -- BATTLE STAGE = AUTO uses the same helper (speech bubbles hide the slab).
  local autoBattle = {
    game = {
      stack = {
        states = {},
        top = function(self)
          return self.states[#self.states]
        end,
      },
    },
  }
  autoBattle.game.stack.states = { autoBattle, textBox }
  truthy(Compat.fieldAllowsStackedBottomUI(autoBattle),
    "AUTO also unhides learn-move TextBox over hidden dialogue")
end

function tests.field_drops_classic_white_overlay()
  eq(Hooks.shouldDropFieldFill("fill", 0, 0, 160, 144, 1, 1, 1, 1),
    "clear", "opaque battle-field fill")
  eq(Hooks.shouldDropFieldFill("fill", 0, 0, 160, 144, 1, 1, 1, nil),
    "clear", "opaque fill with implicit alpha")
  eq(Hooks.shouldDropFieldFill("fill", 0, 0, 160, 144, 1, 1, 1, 0.85),
    "drop", "translucent attack flash")
  eq(Hooks.shouldDropFieldFill("fill", 0, 64, 160, 80, 1, 1, 1, 1),
    false, "compact FIELD box stays")
  eq(Hooks.shouldDropFieldFill("fill", 0, 0, 160, 144, 0, 0, 0, 1),
    false, "black fill is not the overlay")
  eq(Hooks.shouldDropFieldFill("line", 0, 0, 160, 144, 1, 1, 1, 1),
    false, "stroke is not the overlay")
end

function tests.b_pauses_move_field_hud()
  local function press(key)
    return {
      wasPressed = function(_, name)
        return name == key
      end,
    }
  end

  truthy(Hooks.fieldPausePressed(press("b"), { phase = "moveSelect" }),
    "B on the move diamond is pause")
  truthy(Hooks.fieldPausePressed(press("b"), {
    phase = "menu",
    _arFieldPreferMoves = true,
  }), "B on the sticky command frame is pause")
  truthy(not Hooks.fieldPausePressed(press("b"), { phase = "messages" }),
    "B during dialogue is not field pause")
  truthy(not Hooks.fieldPausePressed(press("a"), { phase = "moveSelect" }),
    "A on the diamond is not pause")
  truthy(not Hooks.fieldPausePressed(nil, { phase = "moveSelect" }),
    "missing input is not pause")

  local battle = {
    phase = "moveSelect",
    moveSwapIndex = 2,
    _arFieldPreferMoves = true,
  }
  truthy(Hooks.applyFieldPause(battle), "pause from diamond")
  eq(battle.phase, "menu", "diamond yields the command menu")
  eq(battle.menuIndex, 1, "command cursor defaults to FIGHT")
  eq(battle.moveSwapIndex, nil, "swap cursor clears")
  truthy(not battle._arFieldPreferMoves, "pause clears sticky moves")
  truthy(battle._arFieldCommandHold, "pause holds command")

  battle = { phase = "menu", _arFieldPreferMoves = true }
  truthy(Hooks.applyFieldPause(battle), "pause on sticky command frame")
  truthy(not battle._arFieldPreferMoves, "sticky latch clears")
  truthy(battle._arFieldCommandHold, "sticky command stays held")

  battle = { phase = "messages", _arFieldPreferMoves = true }
  truthy(not Hooks.applyFieldPause(battle), "dialogue B is not field pause")
  truthy(battle._arFieldPreferMoves, "message B leaves the move latch")
end

function tests.faint_drops_sticky_move_diamond()
  truthy(not Hooks.playerMustSwitch({
    player = { mon = { hp = 12 }, curMoves = { {} } },
  }), "healthy mon does not force a switch")
  truthy(Hooks.playerMustSwitch({
    player = { mon = { hp = 0 }, curMoves = { {} } },
  }), "HP 0 forces a switch")
  truthy(Hooks.playerMustSwitch({
    sendingOut = true,
    player = { mon = { hp = 20 } },
  }), "send-out forces a switch")
  truthy(Hooks.playerMustSwitch({
    player = { shownHP = 0, mon = { hp = 4 } },
  }), "empty shown HP forces a switch")
  truthy(not Hooks.foeIsDown({
    enemy = { mon = { hp = 12 } },
  }), "healthy foe does not drop the diamond")
  truthy(Hooks.foeIsDown({
    enemy = { mon = { hp = 0 } },
  }), "KO'd foe drops the diamond")
  truthy(Hooks.foeIsDown({
    enemy = { shownHP = 0, mon = { hp = 8 } },
  }), "empty foe bar drops the diamond")
end

function tests.supported_battle_gate()
  local mod = {
    options = {
      get = function(_, key)
        if key == "battle_stage" then
          return "FIELD"
        end
      end,
    },
  }
  truthy(FieldBattle.shouldUse(mod, { kind = "wild" }), "wild battle uses field")
  truthy(FieldBattle.shouldUse(mod, { kind = "trainer" }), "trainer battle uses field")
  truthy(not FieldBattle.shouldUse(mod, { kind = "trainer", double = true }),
    "double battle stays vanilla")
  truthy(not FieldBattle.shouldUse(mod, { kind = "link", link = true }), "link stays vanilla")
  truthy(not FieldBattle.shouldUse(mod, { kind = "wild", demo = true }), "demo stays vanilla")
  mod.options.get = function() return "AUTO" end
  truthy(not FieldBattle.shouldUse(mod, { kind = "wild" }), "disabled stage stays vanilla")
end

function tests.voxel_compat_gates_only_field_staging()
  local activeBattle
  local calls = { begin = 0, update = 0, finish = 0 }
  local OB = {
    begin = function()
      calls.begin = calls.begin + 1
      return "original"
    end,
    ensure = function() return "ensured" end,
    update = function() calls.update = calls.update + 1 end,
    finish = function() calls.finish = calls.finish + 1 end,
    arena = function() return {} end,
  }
  local mod = {
    find = function()
      return {
        exports = {
          lib = {
            require = function(name)
              if name == "OverworldBattle" then
                return OB
              end
            end,
          },
        },
      }
    end,
  }
  local FBV = {
    shouldUse = function(_, battle)
      return battle and (battle.kind == "wild" or battle.kind == "trainer")
        and not battle.demo
    end,
    Lifecycle = {
      liveBattle = function()
        return activeBattle
      end,
    },
  }
  local oldPreload = package.preload["src.core.Game"]
  local oldLoaded = package.loaded["src.core.Game"]
  package.loaded["src.core.Game"] = nil
  package.preload["src.core.Game"] = function() return {} end

  Compat.suppressDramaticShape(FBV, mod)
  eq(OB.begin({}, { kind = "wild" }), false, "field skips staged voxel arena")
  eq(calls.begin, 0, "field does not call staged arena begin")
  eq(OB.begin({}, { kind = "script", demo = true }), "original",
    "non-field battle keeps companion behavior")
  eq(calls.begin, 1, "non-field battle reaches original begin")

  activeBattle = { kind = "wild" }
  OB.update(1 / 60)
  eq(calls.update, 0, "active field session skips staged arena update")
  activeBattle = nil
  OB.update(1 / 60)
  eq(calls.update, 1, "free-roam pipeline update remains available")

  package.preload["src.core.Game"] = oldPreload
  package.loaded["src.core.Game"] = oldLoaded
end

function tests.coordinate_round_trips()
  local rect = { minX = 8, maxX = 16, minY = 20, maxY = 24 }
  for _, axis in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    local grid = Coords.applyLayout({}, Coords.layoutPad(rect, axis[1], axis[2]))
    for u = 0, grid.sizeU - 1 do
      for v = 0, grid.sizeV - 1 do
        local wx, wy = Coords.padToWorld(grid, u, v)
        local ru, rv = Coords.worldToPad(grid, wx, wy)
        eq(ru, u, "round-trip u")
        eq(rv, v, "round-trip v")
        local px, py = Coords.padToPx(grid, u, v)
        eq(px, wx * 16, "pixel x")
        eq(py, wy * 16, "pixel y")
      end
    end
  end
end

function tests.read_only_walkable_envelope()
  local plan = Layout.plan(10, 10, 14, 10)
  local calls = { walk = 0, water = 0 }
  local map = {
    inBounds = function() return true end,
    isWaterCell = function(_, x, y)
      calls.water = calls.water + 1
      return x == 13 and y == 12
    end,
    isWalkableCell = function(_, x, y)
      calls.walk = calls.walk + 1
      return not (x == 12 and y == 9)
    end,
    isGrassCell = function() return false end,
    warpAtCell = function(_, x, y)
      return x == 11 and y == 8 and { map = "elsewhere" } or nil
    end,
  }
  local obstacle = { cellX = 15, cellY = 11 }
  local envelope = Survey.build(map, plan, {
    entityPools = { { obstacle } },
  })
  -- Tight opening (trainers ± back of adjacent mons) + EXTRA_U/HALF_V roam room.
  eq(envelope.pad.sizeU, 8, "free-tile envelope width")
  eq(envelope.pad.sizeV, 5, "free-tile envelope height")
  truthy(envelope.readOnly, "survey is explicitly read-only")
  truthy(calls.walk > 0 and calls.water > 0, "survey queries map traversal")

  for _, world in ipairs({ { 13, 12 }, { 12, 9 }, { 11, 8 }, { 15, 11 } }) do
    local u, v = Coords.worldToPad(envelope.pad, world[1], world[2])
    truthy(not envelope.walkable[Coords.key(u, v)],
      "blocked terrain/entity excluded from land envelope")
  end

  local arena = Arena.generate(nil, plan, 123, envelope)
  local grid = Grid.build(arena, plan)
  eq(grid.sizeU, 8, "grid adopts surveyed width")
  eq(grid.sizeV, 5, "grid adopts surveyed height")
  local wu, wv = Coords.worldToPad(envelope.pad, 13, 12)
  truthy(envelope.water[Coords.key(wu, wv)], "water cells stay in the water mask")
  truthy(grid.water[Coords.key(wu, wv)], "grid keeps surveyed water")
  truthy(not Grid.isFree(grid, wu, wv), "anonymous movement rejects water")
  truthy(not Grid.isFree(grid, wu, wv, "landmon", { canSwim = false }),
    "non-Water mons stay off water")
  truthy(Grid.isFree(grid, wu, wv, "squirtle", { canSwim = true }),
    "Water-type mons may enter surveyed water")
end

function tests.water_types_may_step_onto_water()
  local plan = Layout.plan(10, 10, 14, 10)
  local map = {
    inBounds = function() return true end,
    isWaterCell = function(_, x, y)
      return x == 12 and y == 10
    end,
    isWalkableCell = function(_, x, y)
      return not (x == 12 and y == 10)
    end,
    isGrassCell = function() return false end,
    warpAtCell = function() return nil end,
  }
  local envelope = Survey.build(map, plan, {})
  local grid = Grid.build(Arena.generate(nil, plan, 1, envelope), plan)
  local landU, landV = Coords.worldToPad(envelope.pad, 11, 10)
  local waterU, waterV = Coords.worldToPad(envelope.pad, 12, 10)
  truthy(Grid.isFree(grid, landU, landV), "land cell is free")
  truthy(Grid.isWater(grid, waterU, waterV), "target is water")

  local fire = {
    id = "charmander", padU = landU, padV = landV, canSwim = false,
  }
  Grid.occupy(grid, fire.id, landU, landV)
  truthy(not Grid.step(grid, fire, waterU - landU, waterV - landV),
    "Fire mon cannot step onto water")

  local waterMon = {
    id = "squirtle", padU = landU, padV = landV, canSwim = true,
  }
  Grid.release(grid, fire.id)
  Grid.occupy(grid, waterMon.id, landU, landV)
  truthy(Grid.step(grid, waterMon, waterU - landU, waterV - landV),
    "Water mon can step onto water")
  eq(waterMon.padU, waterU, "water mon occupies water pad u")
  eq(waterMon.padV, waterV, "water mon occupies water pad v")

  truthy(Sprites.isWaterType({ curTypes = { "WATER" } }), "curTypes WATER")
  truthy(Sprites.isWaterType({ curTypes = { "WATER", "FLYING" } }), "dual Water")
  truthy(not Sprites.isWaterType({ curTypes = { "FIRE" } }), "Fire is not Water")
  truthy(Sprites.isWaterType({ def = { types = { "WATER" } } }), "def.types WATER")
end

function tests.survey_relocates_mons_off_buildings()
  -- Mid-strip formation lands mon homes on solid roof tiles; survey must
  -- snap them onto open path cells and never force-mark roofs walkable.
  local plan = Layout.plan(8, 10, 16, 10)
  local solid = {
    [12] = true, [13] = true, -- planned mon/mid cells
  }
  local map = {
    inBounds = function() return true end,
    isWaterCell = function() return false end,
    isGrassCell = function() return false end,
    isWalkableCell = function(_, x, y)
      if y ~= 10 then
        return false
      end
      return not solid[x]
    end,
    warpAtCell = function() return nil end,
  }
  local player = { cellX = 8, cellY = 10 }

  -- Force planned mon/trainer cells onto solid x=12/13.
  plan.pMonX, plan.pMonY = 12, 10
  plan.eMonX, plan.eMonY = 13, 10
  plan.pCellX, plan.pCellY = 12, 10
  plan.eCellX, plan.eCellY = 13, 10

  local envelope = Survey.build(map, plan, { player = player })
  local pU, pV = Coords.worldToPad(envelope.pad, plan.pMonX, plan.pMonY)
  local eU, eV = Coords.worldToPad(envelope.pad, plan.eMonX, plan.eMonY)
  truthy(envelope.walkable[Coords.key(pU, pV)], "player mon on surveyed walkable")
  truthy(envelope.walkable[Coords.key(eU, eV)], "enemy mon on surveyed walkable")
  truthy(Survey.cellAllowed(map, plan.pMonX, plan.pMonY),
    "player mon world cell is collision-legal")
  truthy(Survey.cellAllowed(map, plan.eMonX, plan.eMonY),
    "enemy mon world cell is collision-legal")
  truthy(not solid[plan.pMonX], "player mon left the roof")
  truthy(not solid[plan.eMonX], "enemy mon left the roof")

  -- Roofs must stay out of the walkable mask (no force-allow fallback).
  for x = 12, 13 do
    local u, v = Coords.worldToPad(envelope.pad, x, 10)
    if Coords.inPad(envelope.pad, u, v) then
      truthy(not envelope.walkable[Coords.key(u, v)],
        "solid roof stays illegal in walkable mask")
    end
  end
end

function tests.compact_field_ui_tracks_engine_cursors()
  local battle = { phase = "menu", menuIndex = 3 }
  local state = UI.layoutState(battle)
  truthy(not state.showHUD and state.showCommand,
    "battler entities own HP bars while command panel is visible")
  eq(state.menuIndex, 3, "command cursor remains BattleState-owned")
  battle.phase, battle.moveIndex = "moveSelect", 4
  battle.player = {
    curMoves = {
      { id = "TACKLE" }, { id = "GROWL" }, { id = "TAIL_WHIP" }, { id = "SCRATCH" },
    },
  }
  battle.data = {
    moves = {
      TACKLE = { name = "TACKLE" },
      GROWL = { name = "GROWL" },
      TAIL_WHIP = { name = "TAIL WHIP" },
      SCRATCH = { name = "SCRATCH" },
    },
  }
  state = UI.layoutState(battle)
  truthy(state.showMoves and not state.showCommand, "move panel replaces command panel")
  eq(state.moveIndex, 4, "move cursor remains BattleState-owned")
  battle.phase = "messages"
  state = UI.layoutState(battle)
  truthy(state.showDialogue, "message phase keeps a no-bubble fallback")
  battle._arFieldBubbleDialogue = true
  state = UI.layoutState(battle)
  truthy(not state.showDialogue, "speech popup replaces the bottom dialogue panel")
end

function tests.move_hud_shows_b_pause_hint()
  local drawn = {}
  package.loaded["src.render.Font"] = {
    draw = function(text)
      drawn[#drawn + 1] = text
    end,
    width = function()
      return 8
    end,
  }
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      rectangle = function() end,
      push = function() end,
      pop = function() end,
    },
  }
  local battle = {
    _arAnimeField = true,
    phase = "moveSelect",
    moveIndex = 1,
    player = {
      curMoves = {
        { id = "TACKLE" }, { id = "GROWL" }, { id = "TAIL_WHIP" }, { id = "SCRATCH" },
      },
    },
    data = {
      moves = {
        TACKLE = { name = "TACKLE" },
        GROWL = { name = "GROWL" },
        TAIL_WHIP = { name = "TAIL WHIP" },
        SCRATCH = { name = "SCRATCH" },
      },
    },
    game = {
      renderer = {
        uiSize = function() return 160, 144 end,
        worldViewSize = function() return 160, 144 end,
        fitScale = function() return 1 end,
      },
      overworld = { camera = { x = 0, y = 0 }, entities = {} },
    },
  }
  UI.draw(battle)
  love = prevLove
  package.loaded["src.render.Font"] = nil
  local hinted = false
  for i = 1, #drawn do
    if drawn[i] == "B PAUSE" then
      hinted = true
      break
    end
  end
  truthy(hinted, "move HUD tells the player to pause with B")
end

function tests.hp_chip_stays_on_screen_near_top()
  local x, y = UI.clampHpChip(80, -12, 160, 144)
  eq(y, UI.HP_CHIP_TOP, "negative bar Y pins to the top margin")
  x, y = UI.clampHpChip(80, 0, 160, 144)
  eq(y, UI.HP_CHIP_TOP, "bar at y=0 is still fully visible")
  x, y = UI.clampHpChip(80, 40, 160, 144)
  eq(x, 80, "in-view bar keeps its X")
  eq(y, 40, "in-view bar keeps its Y")
  x = select(1, UI.clampHpChip(-20, 40, 160, 144))
  truthy(x - math.floor(UI.HP_CHIP_W / 2) >= 1, "left edge stays on canvas")

  local painted = {}
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      rectangle = function(_, x, y)
        painted[#painted + 1] = { x = x, y = y }
      end,
      polygon = function() end,
      push = function() end,
      pop = function() end,
      translate = function() end,
      scale = function() end,
      print = function() end,
    },
  }
  local enemy = {
    _arFieldBattler = true,
    _arFieldSide = "enemy",
    px = 80,
    py = 4,
    _fieldBarLift = 24,
    hidden = false,
  }
  local battle = {
    _arAnimeField = true,
    player = { shownHP = 20, mon = { name = "EKANS", stats = { hp = 20 } } },
    enemy = { shownHP = 30, mon = { name = "GEODUDE", stats = { hp = 30 } } },
    game = {
      overworld = {
        camera = { x = 0, y = 0 },
        entities = { enemy },
      },
      renderer = {
        uiSize = function() return 160, 144 end,
        worldViewSize = function() return 160, 144 end,
        fitScale = function() return 1 end,
      },
    },
  }
  UI.drawWorldHP(battle, 0, 0, "ui")
  love = prevLove
  truthy(#painted > 0, "HP chip paints")
  local minY = 999
  for i = 1, #painted do
    if painted[i].y < minY then
      minY = painted[i].y
    end
  end
  truthy(minY >= UI.HP_CHIP_TOP, "top-of-screen mon does not clip its HP chip")
end

function tests.focus_bar_paints_above_hp_when_enabled()
  local prevVisible, prevRatio = UI.focusBarVisible, UI.focusRatio
  UI.focusBarVisible = function() return true end
  UI.focusRatio = function(_, isPlayer)
    return isPlayer and 0.8 or 0.4
  end
  local painted = {}
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      rectangle = function(_, x, y)
        painted[#painted + 1] = { x = x, y = y }
      end,
      polygon = function() end,
      push = function() end,
      pop = function() end,
      translate = function() end,
      scale = function() end,
      print = function() end,
    },
  }
  local enemy = {
    _arFieldBattler = true,
    _arFieldSide = "enemy",
    px = 80,
    py = 40,
    _fieldBarLift = 10,
    hidden = false,
  }
  local battle = {
    _arAnimeField = true,
    player = { shownHP = 20, mon = { name = "EKANS", stats = { hp = 20 } } },
    enemy = { shownHP = 30, mon = { name = "GEODUDE", stats = { hp = 30 } } },
    game = {
      overworld = {
        camera = { x = 0, y = 0 },
        entities = { enemy },
      },
      renderer = {
        uiSize = function() return 160, 144 end,
        worldViewSize = function() return 160, 144 end,
        fitScale = function() return 1 end,
      },
    },
  }
  UI.drawWorldHP(battle, 0, 0, "ui")
  love = prevLove
  UI.focusBarVisible, UI.focusRatio = prevVisible, prevRatio
  truthy(#painted >= 4, "focus bar adds extra rects above the HP chip")
  local ys = {}
  for i = 1, #painted do
    ys[#ys + 1] = painted[i].y
  end
  table.sort(ys)
  truthy(ys[1] < ys[#ys], "focus bar sits above the HP bar")
  truthy(battle._arFocusBarShown and battle._arFocusBarShown.enemy ~= nil,
    "shown focus eases toward the live ratio")
end

function tests.focus_bar_gap_flush_vs_one_pixel()
  local prevVisible, prevRatio, prevGap = UI.focusBarVisible, UI.focusRatio, UI.focusBarGap
  UI.focusBarVisible = function() return true end
  UI.focusRatio = function() return 1 end
  local function paintY(gap)
    UI.focusBarGap = function() return gap end
    local ys = {}
    local prevLove = love
    love = {
      graphics = {
        setColor = function() end,
        rectangle = function(_, _, y)
          ys[#ys + 1] = y
        end,
        polygon = function() end,
        push = function() end,
        pop = function() end,
        translate = function() end,
        scale = function() end,
        print = function() end,
      },
    }
    local enemy = {
      _arFieldBattler = true,
      _arFieldSide = "enemy",
      px = 80,
      py = 40,
      _fieldBarLift = 10,
      hidden = false,
    }
    local battle = {
      _arAnimeField = true,
      player = { shownHP = 20, mon = { name = "EKANS", stats = { hp = 20 } } },
      enemy = { shownHP = 30, mon = { name = "GEODUDE", stats = { hp = 30 } } },
      game = {
        overworld = {
          camera = { x = 0, y = 0 },
          entities = { enemy },
        },
        renderer = {
          uiSize = function() return 160, 144 end,
          worldViewSize = function() return 160, 144 end,
          fitScale = function() return 1 end,
        },
      },
    }
    UI.drawWorldHP(battle, 0, 0, "ui")
    love = prevLove
    table.sort(ys)
    return ys[1]
  end
  local flushY = paintY(0)
  local gappedY = paintY(1)
  UI.focusBarVisible, UI.focusRatio, UI.focusBarGap = prevVisible, prevRatio, prevGap
  truthy(gappedY < flushY, "1PX gap lifts the focus bar one pixel above flush")
end

function tests.compact_arena_keeps_cast_lanes_clear()
  local player = { cellX = 10, cellY = 10, facing = "right" }
  local fx, fy = Layout.wildAnchor(player)
  local plan = Layout.plan(player.cellX, player.cellY, fx, fy)
  eq(plan.pCellX, player.cellX, "wild pad starts at player")
  eq(math.abs(plan.pMonX - plan.eMonX), 1, "wild mons start adjacent")
  local arena = Arena.generate(nil, plan, 12345)
  eq(arena.pad.sizeU, 4, "tight arena width")
  eq(arena.pad.sizeV, 3, "arena height")

  local homes = {
    { plan.pMonX, plan.pMonY },
    { plan.eMonX, plan.eMonY },
  }
  for _, home in ipairs(homes) do
    local hu, hv = Coords.worldToPad(arena.pad, home[1], home[2])
    for _, slot in ipairs(arena.coverSlots or {}) do
      truthy(not (slot.u == hu and math.abs(slot.v - hv) <= 1),
        "props stay out of battler dodge lanes")
    end
  end
end

function tests.trainer_layout_resolves_engaged_npc()
  local player = { cellX = 4, cellY = 6 }
  local trainer = {
    id = "route_trainer_1",
    cellX = 4,
    cellY = 2,
    def = { trainerClass = "OPP_YOUNGSTER" },
  }
  local overworld = {
    player = player,
    entities = { player, trainer },
    npcPool = { route_trainer_1 = trainer },
  }
  local battle = {
    kind = "trainer",
    checkpointOrigin = { npcId = "route_trainer_1" },
  }
  eq(Layout.findFoeTrainer(overworld, battle), trainer, "resolve engaged trainer")
  local plan = Layout.plan(player.cellX, player.cellY, trainer.cellX, trainer.cellY)
  eq(math.abs(plan.pCellY - plan.eCellY), 3, "trainer edges span tight pad")
  eq(math.abs(plan.pMonY - plan.eMonY), 1, "mons start on adjacent tiles")
end

local function sampleGrid()
  local plan = Layout.plan(10, 10, 18, 10)
  return Grid.build(nil, plan), plan
end

function tests.nearby_trainers_spectate_and_restore()
  local player = {
    cellX = 10, cellY = 10, px = 160, py = 160,
    facing = "up", frozen = false, wanders = false,
  }
  local foe = {
    id = "foe", cellX = 14, cellY = 10, px = 224, py = 160,
    facing = "left", trainer = true,
    def = { trainerClass = "OPP_YOUNGSTER", name = "JOEY" },
  }
  local bystander = {
    id = "watcher", name = "SAM",
    cellX = 12, cellY = 12, px = 192, py = 192,
    facing = "down", frozen = false, wanders = true,
    trainer = true,
    def = { trainerClass = "OPP_LASS", name = "SAM" },
  }
  local far = {
    id = "far", cellX = 30, cellY = 30, px = 480, py = 480,
    trainer = true, def = { trainerClass = "OPP_BUG_CATCHER" },
  }
  local map = {
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 40 and y < 40
    end,
    isWalkableCell = function(_, x, y)
      return true
    end,
    isWaterCell = function() return false end,
  }
  local ow = {
    player = player,
    map = map,
    entities = { player, foe, bystander, far },
    npcs = {},
    npcPool = { foe = foe, watcher = bystander, far = far },
  }
  local grid, plan = sampleGrid()
  -- Align plan mid with the staged fight so radius checks match.
  plan.midX, plan.midY = 12, 10
  local session = {
    midX = 12,
    midY = 10,
    plan = plan,
    grid = grid,
    foe = foe,
    _deps = {
      Layout = Layout,
      Survey = Survey,
      Grid = Grid,
      Coords = Coords,
      Lifecycle = Lifecycle,
    },
  }
  local battle = { game = { overworld = ow }, kind = "trainer" }

  local gathered = Spectators.gather(ow, session)
  eq(#gathered, 1, "only nearby trainer gathered")
  eq(gathered[1].ent, bystander, "bystander is the nearby trainer")

  local n = Spectators.begin(session, battle, session._deps)
  eq(n, 1, "one spectator staged")
  eq(#session.spectators, 1, "session tracks spectator")
  local spec = session.spectators[1]
  truthy(spec.pose, "spectator pose snapshotted")
  eq(spec.pose.cellX, 12, "snapshot keeps start cell")
  eq(bystander.frozen, true, "spectator frozen for FIELD")
  eq(bystander.wanders, false, "spectator wander disabled")
  truthy(bystander._arFieldSpectator, "spectator flagged")
  truthy(spec.spotX ~= nil, "watching spot assigned")

  -- Drive soft steps until arrival (or timeout).
  for _ = 1, 240 do
    Spectators.tick(session, 1 / 30, session._deps)
    if spec.arrived then
      break
    end
  end
  truthy(spec.arrived, "spectator walks to watching tile")
  eq(bystander.cellX, spec.spotX, "cell matches spot x")
  eq(bystander.cellY, spec.spotY, "cell matches spot y")

  -- Face the duel mid.
  local fx, fy = 12, 10
  local dx = fx - bystander.cellX
  local dy = fy - bystander.cellY
  local expect
  if math.abs(dx) >= math.abs(dy) then
    expect = dx >= 0 and "right" or "left"
  else
    expect = dy >= 0 and "down" or "up"
  end
  eq(bystander.facing, expect, "spectator faces the battle")

  -- Force a shoutout for coverage.
  session._specShoutCD = 0
  Spectators.SHOUT_CHANCE = 1
  Spectators.tick(session, 0.05, session._deps)
  truthy(session._specShout and session._specShout.text, "rare shoutout fired")
  Spectators.SHOUT_CHANCE = 0.10

  Spectators.finish(session, session._deps)
  eq(session.spectators, nil, "spectators cleared")
  eq(bystander.cellX, 12, "pose restored x")
  eq(bystander.cellY, 12, "pose restored y")
  eq(bystander.facing, "down", "pose restored facing")
  eq(bystander.frozen, false, "frozen restored")
  eq(bystander.wanders, true, "wanders restored")
  eq(bystander._arFieldSpectator, nil, "flag cleared")
end

function tests.engaged_trainers_face_each_other()
  local grid, plan = sampleGrid()
  local player = {
    cellX = plan.pCellX, cellY = plan.pCellY,
    px = plan.pCellX * 16, py = plan.pCellY * 16,
    padU = grid.home.playerTrainer.u, padV = grid.home.playerTrainer.v,
    facing = "up",
  }
  local foe = {
    cellX = plan.eCellX, cellY = plan.eCellY,
    px = plan.eCellX * 16, py = plan.eCellY * 16,
    padU = grid.home.enemyTrainer.u, padV = grid.home.enemyTrainer.v,
    facing = "up",
  }
  local battle = {
    game = { overworld = { player = player, camera = { x = 0, y = 0 } } },
    animPlaying = false,
  }
  local session = {
    state = Lifecycle.STATE.Live,
    live = true,
    grid = grid,
    plan = plan,
    midX = plan.midX,
    midY = plan.midY,
    foe = foe,
    playerMon = {
      cellX = plan.pMonX, cellY = plan.pMonY,
      padU = grid.home.player.u, padV = grid.home.player.v,
      anim = "idle",
    },
    enemyMon = {
      cellX = plan.eMonX, cellY = plan.eMonY,
      padU = grid.home.enemy.u, padV = grid.home.enemy.v,
      anim = "idle",
    },
    _deps = {
      Grid = Grid,
      Cast = { tick = function() end },
      Cues = {
        pumpCurrent = function() end,
        tickReturns = function() end,
      },
      Anims = { cache = function() end },
      Projectiles = { tick = function() end },
    },
  }
  Lifecycle._testBind(battle, session)
  -- Face-acc fires every 0.15s; drive past one interval.
  Lifecycle.tick(battle, 0.20, session._deps)
  eq(player.facing, plan.playerFace, "player trainer faces foe trainer")
  eq(foe.facing, plan.foeFace, "foe trainer faces player trainer")
  Lifecycle._testUnbind(battle)
end

local function chebyshevDist(ax, ay, bx, by)
  return math.max(math.abs((ax or 0) - (bx or 0)), math.abs((ay or 0) - (by or 0)))
end

function tests.overworld_wildlife_scatters_and_restores()
  local grid, plan = sampleGrid()
  plan.midX, plan.midY = 12, 10
  local player = {
    cellX = 10, cellY = 10, px = 160, py = 160, facing = "right",
  }
  local wildNear = {
    id = "wild_rattata",
    overworldWildSpawn = true,
    _owwildEntity = true,
    species = "RATTATA",
    cellX = 12, cellY = 11, px = 192, py = 176,
    facing = "down", frozen = false, wanders = true,
    behaviorState = "AVAILABLE",
    state = "AVAILABLE",
  }
  local wildFar = {
    id = "wild_far",
    overworldWildSpawn = true,
    _owwildEntity = true,
    cellX = 28, cellY = 28, px = 448, py = 448,
    state = "AVAILABLE",
  }
  local ambient = {
    id = "town_mon",
    wildsAmbientPokemon = true,
    overworldWildSpawn = false,
    cellX = 12, cellY = 12, px = 192, py = 192,
  }
  local follower = {
    id = "follower",
    isFollower = true,
    cellX = 11, cellY = 10, px = 176, py = 160,
  }
  local map = {
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 40 and y < 40
    end,
    isWalkableCell = function() return true end,
    isWaterCell = function() return false end,
  }
  local ow = {
    player = player,
    map = map,
    entities = { player, wildNear, wildFar, ambient, follower },
  }
  local session = {
    midX = 12,
    midY = 10,
    plan = plan,
    grid = grid,
    _deps = {
      Layout = Layout,
      Survey = Survey,
      Grid = Grid,
      Coords = Coords,
      Lifecycle = Lifecycle,
    },
  }
  local battle = { game = { overworld = ow }, kind = "wild" }

  truthy(Wildlife.isRoaming(wildNear, player, nil, Lifecycle),
    "roaming wild is eligible")
  truthy(not Wildlife.isRoaming(ambient, player, nil, Lifecycle),
    "ambient town mon skipped")
  truthy(not Wildlife.isRoaming(follower, player, nil, Lifecycle),
    "follower skipped")

  local gathered = Wildlife.gather(ow, session)
  eq(#gathered, 1, "only nearby wild gathered")
  eq(gathered[1].ent, wildNear, "near wild selected")

  local n = Wildlife.begin(session, battle, session._deps)
  eq(n, 1, "one wild staged to scatter")
  local w = session.wildlife[1]
  truthy(w.pose, "pose snapshotted")
  eq(w.pose.cellX, 12, "snapshot start x")
  eq(wildNear.frozen, true, "wild frozen during FIELD")
  truthy(wildNear._arFieldWildlife, "wildlife flag set")
  truthy(w.spotX ~= nil, "flee spot assigned")
  truthy(chebyshevDist(w.spotX, w.spotY, 12, 10) >= Wildlife.FLEE_MIN,
    "flee spot is away from mid")

  for _ = 1, 300 do
    Wildlife.tick(session, 1 / 30, session._deps)
    if w.arrived then
      break
    end
  end
  truthy(w.arrived, "wild finishes scatter walk")
  eq(wildNear.cellX, w.spotX, "cell matches flee x")
  eq(wildNear.cellY, w.spotY, "cell matches flee y")

  Wildlife.finish(session, session._deps)
  eq(session.wildlife, nil, "wildlife cleared")
  eq(wildNear.cellX, 12, "pose restored x")
  eq(wildNear.cellY, 11, "pose restored y")
  eq(wildNear.facing, "down", "pose restored facing")
  eq(wildNear.frozen, false, "frozen restored")
  eq(wildNear._arFieldWildlife, nil, "flag cleared")
  eq(wildNear.behaviorState, "AVAILABLE", "behavior restored")
end

function tests.occupancy_and_movement()
  local grid = sampleGrid()
  eq(grid.sizeU, 4, "tight pad width")
  eq(grid.sizeV, 3, "compact pad height")
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  eq(math.abs(pHome.u - eHome.u), 1, "opening homes are adjacent")
  local p = { id = "player", padU = pHome.u, padV = pHome.v }
  local e = { id = "enemy", padU = eHome.u, padV = eHome.v }
  truthy(Grid.setPad(grid, p, p.padU, p.padV), "place player")
  truthy(Grid.setPad(grid, e, e.padU, e.padV), "place enemy")
  truthy(not Grid.setPad(grid, { id = "other" }, p.padU, p.padV),
    "reject occupied cell")
  eq(Grid.occupy(grid, "intruder", p.padU, p.padV), false,
    "occupy does not steal a taken cell")
  eq(grid.occ[Coords.key(p.padU, p.padV)], p.id, "original occupant kept")

  local relocated = { id = "spawn" }
  truthy(Grid.placeOnFreePad(grid, relocated, p.padU, p.padV),
    "send-out relocates off an occupied home")
  truthy(relocated.padU ~= p.padU or relocated.padV ~= p.padV,
    "relocated spawn is on a different pad")
  eq(grid.occ[Coords.key(p.padU, p.padV)], p.id, "home occupant is unchanged")
  eq(grid.occ[Coords.key(relocated.padU, relocated.padV)], relocated.id,
    "spawn occupies the empty neighbor")

  -- World-cell reservation: the foe's tile is not a legal send-out even if
  -- pad occupancy was cleared.
  Grid.release(grid, e.id)
  local wx, wy = Coords.padToWorld(grid, e.padU, e.padV)
  local worldKey = tostring(wx) .. ":" .. tostring(wy)
  local spawn = { id = "player-sendout" }
  truthy(Grid.placeOnFreePad(grid, spawn, e.padU, e.padV, spawn.id, {
    [worldKey] = true,
  }), "send-out finds a pad when the foe tile is world-blocked")
  truthy(spawn.padU ~= e.padU or spawn.padV ~= e.padV,
    "send-out does not land on the foe's world cell")
  Grid.release(grid, spawn.id)
  truthy(Grid.setPad(grid, e, e.padU, e.padV), "restore foe occupancy")

  local homeU, homeV = p.padU, p.padV
  -- Already adjacent: lunge cannot occupy the foe tile.
  truthy(not Grid.attackStep(grid, p, e), "adjacent attack does not step onto foe")
  eq(p.padU, homeU, "stays on home when already adjacent")
  -- Give one free cell between mons (tight pad still has room at the foe edge).
  truthy(Grid.setPad(grid, e, eHome.u + 1, eHome.v), "slide foe back for step test")
  truthy(Grid.attackStep(grid, p, e), "attack step with room")
  eq(p.padU, homeU + 1, "attack advances on u axis")
  truthy(Grid.returnHome(grid, p), "return after attack")
  eq(p.padU, homeU, "returned u")
  eq(p.padV, homeV, "returned v")

  -- Close-the-gap: from farther than one tile, occupy a cell adjacent to the foe.
  -- Foe is already one cell past home from the attack-step setup (distance 2).
  truthy(Grid.padDistance(grid, p, e) > 1, "foe is more than a tile away")
  local originU, originV = p.padU, p.padV
  truthy(Grid.closeGap(grid, p, e), "close gap toward the foe")
  eq(Grid.padDistance(grid, p, e), 1, "lands adjacent, not on the foe")
  eq(p._returnU, nil, "close-gap does not stash the opening cell")
  truthy(Grid.withdrawFromFoe(grid, p, e), "withdraw after close-gap")
  local after = Grid.padDistance(grid, p, e)
  truthy(after >= 1 and after <= 2, "withdraw stays one to two tiles from the foe")
  eq(p._meleeAnchor, true, "withdraw re-anchors idle roam to the foe")
  eq(p.homePadU, p.padU, "new home is the withdraw cell")
  truthy(p.padU ~= originU or p.padV ~= originV or after == 2,
    "does not snap back to the far opening cell")
  p._meleeAnchor = nil
  truthy(Grid.setPad(grid, p, originU, originV), "reset player for adjacent no-op")
  truthy(Grid.setPad(grid, e, eHome.u, eHome.v), "restore adjacent homes")
  truthy(not Grid.closeGap(grid, p, e), "already-adjacent close-gap is a no-op")

  Grid.clear(grid)
  eq(next(grid.occ), nil, "clear occupancy")
end

function tests.blocked_cells()
  local plan = Layout.plan(0, 0, 8, 0)
  local grid = Grid.build({
    pad = Coords.layoutPad({ minX = 2, maxX = 6, minY = -1, maxY = 1 }, 1, 0),
    coverSlots = { { u = 2, v = 0, kind = "rock" } },
  }, plan)
  truthy(Grid.isBlocked(grid, 2, 0), "cover blocks its pad cell")
  truthy(not Grid.isFree(grid, 2, 0), "blocked cell is unavailable")
end

function tests.powerful_moves_push_and_impact()
  truthy(Projectiles.isPowerfulMove({ moveId = "HYDRO_PUMP" }), "hydro pump is powerful")
  truthy(Projectiles.isPowerfulMove({ moveId = "BODY_SLAM" }), "body slam is powerful")
  truthy(Projectiles.isPowerfulMove({ movePower = 100 }), "100+ BP counts as powerful")
  truthy(not Projectiles.isPowerfulMove({ moveId = "TACKLE", movePower = 35 }),
    "weak move is not powerful")

  local plan = Layout.plan(0, 0, 8, 0)
  local grid = Grid.build({
    pad = Coords.layoutPad({ minX = 0, maxX = 8, minY = -1, maxY = 1 }, 1, 0),
    coverSlots = { { u = 6, v = 0, kind = "rock" } },
  }, plan)
  local player = { id = "player", padU = 2, padV = 0 }
  local enemy = {
    id = "enemy", padU = 4, padV = 0,
    play = function(self, kind) self.lastAnim = kind end,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)

  local su, sv = Grid.pushDir(grid, enemy, player)
  eq(su, 1, "target shoves away from attacker on u")
  eq(sv, 0, "no lateral push on this axis")

  local obs = Grid.obstacleBehind(grid, enemy, player, 2)
  truthy(obs, "cover within two tiles behind target")
  eq(obs.kind, "prop", "cover reads as prop obstacle")
  eq(obs.dist, 2, "rock sits two cells behind")

  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 20,
    _battle = { kind = "wild" },
    _deps = { Projectiles = Projectiles },
  }
  local startU = enemy.padU
  truthy(Cues.apply(session, "enemy", "hit", Grid, nil, nil, {
    moveId = "FIRE_BLAST",
    moveType = "FIRE",
    category = "special",
  }), "powerful hit cue")
  eq(enemy.lastAnim, "hit", "heavy hit animation")
  truthy(enemy._heavyHit, "heavy hit flag set for sprite knockback")
  eq(enemy.padU, startU + 1, "powerful hit pushes one tile before rock")
  eq(#(session.projectiles or {}), 2, "power hit + wall impact FX")
  local styles = {}
  for i = 1, #(session.projectiles or {}) do
    styles[session.projectiles[i].style] = true
  end
  truthy(styles.power_hit, "typed burst on the mon")
  truthy(styles.power_impact, "impact burst at the obstacle")

  Projectiles.clear(session)
  enemy.padU = 4
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  enemy._heavyHit = nil
  enemy.lastAnim = nil
  truthy(Cues.apply(session, "enemy", "hit", Grid, nil, nil, {
    moveId = "TACKLE",
    movePower = 35,
    moveType = "NORMAL",
    category = "physical",
    push = false,
  }), "weak physical hit cue")
  eq(enemy.lastAnim, "hit", "weak hit still plays a flinch")
  truthy(not enemy._heavyHit, "weak hit is not a heavy knock")
  local weakStyles = {}
  for i = 1, #(session.projectiles or {}) do
    weakStyles[session.projectiles[i].style] = true
  end
  truthy(weakStyles.light_hit, "weak physical hit paints a spark on the target")
  truthy(not weakStyles.power_hit, "weak hit does not use the heavy burst")
end

function tests.physical_jumps_cover()
  local plan = Layout.plan(0, 0, 8, 0)
  local grid = Grid.build({
    pad = Coords.layoutPad({ minX = 0, maxX = 8, minY = -1, maxY = 1 }, 1, 0),
    coverSlots = { { u = 4, v = 0, kind = "rock" } },
  }, plan)
  local player = {
    id = "player", padU = 1, padV = 0,
    play = function(self, kind) self.lastAnim = kind end,
  }
  local enemy = {
    id = "enemy", padU = 7, padV = 0,
    play = function(self, kind) self.lastAnim = kind end,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  truthy(Grid.pathObstructed(grid, player, enemy), "cover sits on the fight axis")

  local overworld = { entities = { player, enemy } }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 5,
    _deps = { Projectiles = Projectiles },
    _battle = { game = { overworld = overworld } },
  }
  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil,
    { category = "physical", moveType = "NORMAL" }), "physical over cover")
  eq(player.padU, 6, "close-the-gap lands adjacent to the foe")
  eq(player.lastAnim, nil, "jump waits until the sprite is in reach")
  eq(#(session.projectiles or {}), 0, "contact waits until the close lands")
  truthy(not Cues.inMeleeReach(player, enemy), "still closing across the pad")
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, nil, "same tick as the cue does not punch")
  player.basePx, player.basePy = player.targetPx, player.targetPy
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, "jump", "jump plays once within one tile")
  local fx = session.projectiles and session.projectiles[1]
  truthy(fx and fx.style == "contact", "physical keeps contact-only FX")
  eq(fx.sx, fx.ex, "no traveling physical projectile")
end

function tests.close_the_gap_physicals()
  local snorlax = Cues.closeGapSpeed({ _closeGapStats = { speed = 30, attack = 110 } })
  local dragonite = Cues.closeGapSpeed({ _closeGapStats = { speed = 80, attack = 134 } })
  local weakSlow = Cues.closeGapSpeed({ _closeGapStats = { speed = 30, attack = 40 } })
  local magikarp = Cues.closeGapSpeed({ _closeGapStats = { speed = 80, attack = 10 } })
  local electrode = Cues.closeGapSpeed({ _closeGapStats = { speed = 140, attack = 50 } })
  local rocket = Cues.closeGapSpeed({ _closeGapStats = { speed = 250, attack = 250 } })
  truthy(snorlax < dragonite, "snorlax closes slower than dragonite")
  truthy(snorlax > weakSlow, "snorlax's attack boosts a slow gait")
  truthy(electrode > magikarp, "higher speed closes faster")
  truthy(rocket <= 86, "dash speed is capped")
  truthy(snorlax >= 22, "even slow mons still close")

  local plan = Layout.plan(0, 0, 8, 0)
  local grid = Grid.build({
    pad = Coords.layoutPad({ minX = 0, maxX = 8, minY = -1, maxY = 1 }, 1, 0),
  }, plan)
  local player = {
    id = "player", padU = 1, padV = 0,
    play = function(self, kind) self.lastAnim = kind end,
  }
  local enemy = {
    id = "enemy", padU = 7, padV = 0,
    play = function(self, kind) self.lastAnim = kind end,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    closeTheGap = false,
    _now = 5,
    _deps = { Projectiles = Projectiles },
    _battle = { game = { overworld = { entities = { player, enemy } } } },
  }
  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil,
    { category = "physical", moveType = "NORMAL" }), "physical with gap off")
  eq(player.padU, 2, "toggle off keeps the one-cell lunge")
  eq(player.lastAnim, "attack", "short lunge punches immediately")

  Grid.setPad(grid, player, 1, 0)
  player._attackStepped = nil
  player._returnAt = nil
  player._pendingCloseStrike = nil
  player._closeStrikeDeadline = nil
  player.lastAnim = nil
  Projectiles.clear(session)
  session.closeTheGap = true
  session._now = 8
  session._lastCueAt = nil
  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil,
    { category = "physical", moveType = "NORMAL" }), "physical with gap on")
  eq(player.padU, 6, "toggle on occupies the adjacent approach cell")
  eq(player.lastAnim, nil, "walk close delays the punch")
  truthy(player._pendingCloseStrike, "strike waits for melee reach")
  truthy(Cues.closeGapHoldActive(session), "logic clock holds during the walk")
  truthy(Cues.shouldHoldEngineHit(session, { user = { isPlayer = true } }),
    "engine damage waits for the walk")
  truthy(not Cues.inMeleeReach(player, enemy), "sprite has not arrived yet")
  -- Occupancy / draw target already sit on the approach cell; feet have not.
  player.px, player.py = player.targetPx, player.targetPy
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, nil, "HUD confirm tick does not punch")
  player.basePx, player.basePy = player.targetPx, player.targetPy
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, "attack", "punch plays once within one tile")
  eq(Cues.shouldHoldEngineHit(session, { user = { isPlayer = true } }), false,
    "engine damage resumes after the punch")
  truthy(player._withdrawAfterStrike, "close-in schedules a withdraw, not home")
  eq(player._returnAt, 8.48, "withdraw waits for attack presentation")
  session._now = player._returnAt
  Cues.tickReturns(session, Grid)
  local after = Grid.padDistance(grid, player, enemy)
  truthy(after >= 1 and after <= 2, "post-strike roam stays 1–2 tiles from the foe")
  eq(player.padU == 1, false, "does not walk back to the opening cell")
  eq(player._meleeAnchor, true, "idle roam follows the foe after the strike")
  eq(player._withdrawAfterStrike, nil, "withdraw flag clears")

  Grid.setPad(grid, player, 1, 0)
  player._meleeAnchor = true
  local far = Grid.padDistance(grid, player, enemy)
  truthy(Grid.idleWander(grid, player, "player", enemy),
    "melee wander steps when farther than two tiles")
  truthy(Grid.padDistance(grid, player, enemy) < far,
    "melee wander closes back toward the 1–2 ring")

  -- Adjacent + option on: announce still must not punch; the strike is the
  -- arrival beat, not HUD confirm.
  Grid.setPad(grid, player, 6, 0)
  player.basePx, player.basePy = player.targetPx, player.targetPy
  player.px, player.py = player.targetPx, player.targetPy
  player._attackStepped = nil
  player._returnAt = nil
  player._pendingCloseStrike = nil
  player._closeStrikeWait = nil
  player.lastAnim = nil
  session._lastCueAt = nil
  session._now = 11
  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil,
    { category = "physical", moveType = "NORMAL" }), "adjacent physical with gap on")
  eq(player.lastAnim, nil, "adjacent cue still waits one present tick")
  truthy(player._pendingCloseStrike, "adjacent strike is still gated")
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, nil, "arming tick does not punch")
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, "attack", "adjacent punch plays on the next present tick")
end

function tests.close_gap_powerful_hit_pushes_two()
  local plan = Layout.plan(0, 0, 12, 0)
  local grid = Grid.build({
    pad = Coords.layoutPad({ minX = 0, maxX = 12, minY = -1, maxY = 1 }, 1, 0),
  }, plan)
  local player = {
    id = "player", padU = 1, padV = 0,
    play = function(self, kind) self.lastAnim = kind end,
  }
  local enemy = {
    id = "enemy", padU = 6, padV = 0,
    play = function(self, kind) self.lastAnim = kind end,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    closeTheGap = true,
    _now = 4,
    _deps = { Projectiles = Projectiles, Grid = Grid },
    _battle = { game = { overworld = { entities = { player, enemy } } } },
  }
  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil, {
    category = "physical", moveId = "BODY_SLAM", moveType = "NORMAL",
    movePower = 85,
  }), "body slam closes the gap")
  eq(player.padU, 5, "occupancy sits adjacent before the punch")
  eq(enemy.padU, 6, "foe has not been shoved during the walk")
  truthy(Cues.holdCloseHit(session, "enemy", {
    category = "physical", moveId = "BODY_SLAM", movePower = 85,
  }), "damage_dealt during the walk is stashed")
  Cues.tickReturns(session, Grid)
  eq(enemy.padU, 6, "arming tick does not shove")
  player.basePx, player.basePy = player.targetPx, player.targetPy
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, "attack", "punch lands in melee")
  eq(enemy.padU, 8, "powerful close-in hit pushes two tiles")
  truthy(enemy._heavyHit, "heavy hit flag set")
  eq(enemy.lastAnim, "hit", "foe plays the hit")
end

function tests.bite_closes_gap_when_typed_special()
  local plan = Layout.plan(0, 0, 8, 0)
  local grid = Grid.build({
    pad = Coords.layoutPad({ minX = 0, maxX = 8, minY = -1, maxY = 1 }, 1, 0),
  }, plan)
  local player = {
    id = "player", padU = 1, padV = 0,
    play = function(self, kind) self.lastAnim = kind end,
  }
  local enemy = {
    id = "enemy", padU = 7, padV = 0,
    play = function(self, kind) self.lastAnim = kind end,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    closeTheGap = true,
    _now = 3,
    _deps = { Projectiles = Projectiles },
    _battle = { game = { overworld = { entities = { player, enemy } } } },
  }
  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil, {
    category = "special", moveId = "BITE", moveType = "DARK",
  }), "dark bite still applies")
  eq(player.padU, 6, "bite closes the gap instead of casting in place")
  truthy(player._pendingCloseStrike, "bite punch waits for melee reach")
  eq(player.lastAnim, nil, "cast anim does not play on a contact bite")
end

function tests.special_trajectories_track_mons()
  local grid = sampleGrid()
  local player = {
    id = "player",
    padU = grid.home.player.u,
    padV = grid.home.player.v,
    px = 16, py = 32,
  }
  local enemy = {
    id = "enemy",
    padU = grid.home.enemy.u,
    padV = grid.home.enemy.v,
    px = 96, py = 40,
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _battle = { game = { overworld = { entities = { player, enemy } } } },
    _deps = { Projectiles = Projectiles },
  }
  local orb = Projectiles.move(session, "player", {
    category = "special", moveType = "FIRE",
  })
  eq(orb.sx, 24, "special starts at player sprite center x")
  eq(orb.sy, 36, "special starts at player sprite center y")
  eq(orb.ex, 104, "special ends at enemy sprite center x")
  eq(orb.ey, 44, "special ends at enemy sprite center y")
  truthy(orb.sx < orb.ex, "player special travels toward enemy")

  local reverse = Projectiles.move(session, "enemy", {
    category = "special", moveType = "WATER",
  })
  truthy(reverse.sx > reverse.ex, "enemy special travels toward player")

  local beam = Projectiles.move(session, "player", {
    category = "special", moveType = "ELECTRIC",
  })
  eq(beam.style, "beam", "beam specials keep line trajectory")
  eq(beam.sx, orb.sx, "beam shares attacker origin")
  eq(beam.ex, orb.ex, "beam shares defender target")

  local hop = Projectiles.move(session, "player", {
    category = "special", jump = true, moveType = "FIRE",
  })
  truthy(hop.arc > orb.arc, "specials arc higher over blockers")
end

function tests.cues_and_dedupe()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v,
    play = function(self, kind) self.lastAnim = kind end,
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    play = function(self, kind) self.lastAnim = kind end,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  -- Opening homes are adjacent; open one cell so the physical lunge can step.
  truthy(Grid.setPad(grid, enemy, eHome.u + 1, eHome.v), "room for attack step")
  enemy.basePx, enemy.basePy = enemy.targetPx, enemy.targetPy
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 10,
    _battle = { kind = "wild" },
    _deps = { Projectiles = Projectiles },
  }

  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil,
    { category = "physical" }), "physical attack cue")
  truthy(player._attackStepped, "physical attack owns one grid step")
  eq(player.lastAnim, nil, "punch waits until the sprite is in reach")
  Cues.tickReturns(session, Grid)
  player.basePx, player.basePy = player.targetPx, player.targetPy
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, "attack", "physical attack animation")
  eq(player._returnAt, 10.48, "withdraw waits for attack presentation")
  truthy(player._withdrawAfterStrike, "physical close-in withdraws after the punch")
  truthy(Cues.shouldSkipEvent(session, "player", "attack"), "dedupe same cue")

  -- Night Shade is Gen1 physical (Ghost) + 0 BP, but must cast a travel shadow.
  session._now = 12.5
  session._lastCueAt = nil
  player._attackStepped = nil
  player._returnAt = nil
  player._pendingCloseStrike = nil
  player.lastAnim = nil
  Projectiles.clear(session)
  Grid.setPad(grid, player, pHome.u, pHome.v)
  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil, {
    category = "physical",
    moveType = "GHOST",
    moveId = "NIGHT_SHADE",
  }), "night shade attack cue")
  eq(player.lastAnim, "cast", "night shade casts in place")
  truthy(not player._attackStepped, "night shade does not lunge")
  eq(#(session.projectiles or {}), 1, "night shade spawns shadow projectile")
  eq(session.projectiles[1].style, "shadow", "night shade shadow style from cue")

  session._now = 14
  truthy(not Cues.shouldSkipEvent(session, "player", "attack"), "dedupe expires")
  -- Same named special stays locked past the toast window (issue #3).
  session._now = 16
  session._lastCueAt = nil
  player.lastAnim = nil
  Projectiles.clear(session)
  Grid.setPad(grid, player, pHome.u, pHome.v)
  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil, {
    category = "special",
    moveType = "PSYCHIC",
    moveId = "PSYCHIC",
  }), "psychic attack cue")
  eq(#(session.projectiles or {}), 1, "psychic spawns once")
  session._now = 20
  truthy(Cues.shouldSkipEvent(session, "player", "attack", { moveId = "PSYCHIC" }),
    "same moveId stays locked after 1.25s")
  local psychicBattle = {
    current = {
      arFieldCue = {
        side = "player", kind = "attack", category = "special",
        moveId = "PSYCHIC", moveType = "PSYCHIC",
      },
    },
  }
  eq(Cues.pumpCurrent(session, psychicBattle, Grid, nil), false,
    "pumpCurrent does not replay psychic")
  eq(#(session.projectiles or {}), 1, "no second psychic projectile")
  truthy(not Cues.shouldSkipEvent(session, "player", "attack", {
    moveId = "PSYCHIC", isCalled = true,
  }), "Again! isCalled may strike again")

  session._now = 21
  truthy(Cues.apply(session, "enemy", "hit", Grid, nil, nil,
    { category = "special", push = false }), "hit cue")
  eq(enemy.lastAnim, "hit", "hit animation")

  local playerU, playerV = player.padU, player.padV
  local enemyU, enemyV = enemy.padU, enemy.padV
  session._now = 14
  truthy(Cues.apply(session, "player", "selfhit", Grid, nil, nil), "selfhit cue")
  eq(player.lastAnim, "selfhit", "self-hit plays a stumble")
  eq(player.padU, playerU, "self-hit does not change the user's pad")
  eq(player.padV, playerV, "self-hit stays on the user's cell")
  eq(enemy.padU, enemyU, "self-hit does not knock the foe")
  eq(enemy.padV, enemyV, "self-hit leaves the other pad alone")
  truthy(Cues.shouldSkipEvent(session, "player", "selfhit"), "dedupe self-hit")
  truthy(not Cues.shouldSkipEvent(session, "player", "hit"),
    "self-hit does not swallow a later hit")

  session._now = 16
  truthy(Cues.apply(session, "enemy", "faint", Grid, nil, nil), "faint cue")
  eq(enemy.lastAnim, "faint", "faint plays collapse")
  truthy(Cues.shouldSkipEvent(session, "enemy", "faint"), "dedupe faint")

  -- Player faint: HP-zero apply plays the laser; dialogue must not.
  Projectiles.clear(session)
  grid.home.playerTrainer = { u = pHome.u - 1, v = pHome.v }
  player.px, player.py = 16, 32
  session._now = 20
  session._lastCueAt = nil
  player._fainting = nil
  player._faintDone = nil
  player._recallDone = nil
  player.anim = nil
  player.lastAnim = nil
  truthy(Cues.apply(session, "player", "faint", Grid, nil, nil),
    "player faint cue")
  eq(player.lastAnim, "recall", "player faint uses trainer recall")
  local function countStyle(style)
    local n = 0
    for i = 1, #(session.projectiles or {}) do
      if session.projectiles[i].style == style then
        n = n + 1
      end
    end
    return n
  end
  eq(countStyle("recall"), 1, "one recall laser on faint")
  session._now = 24
  truthy(Cues.shouldSkipEvent(session, "player", "faint"),
    "faint stays skipped while the mon is exiting")
  truthy(Cues.apply(session, "player", "faint", Grid, nil, nil),
    "second faint cue is idempotent")
  eq(countStyle("recall"), 1, "repeat faint apply does not fire a second laser")

  -- Dialogue pump on a replacement mon (HP already 0 on the previous one).
  Projectiles.clear(session)
  player._fainting = nil
  player._faintDone = nil
  player._recallDone = nil
  player.anim = "idle"
  player.lastAnim = nil
  local battle = {
    current = { arFieldCue = { side = "player", kind = "faint" } },
  }
  eq(Cues.pumpCurrent(session, battle, Grid, nil), false,
    "faint dialogue cue is ignored")
  eq(countStyle("recall"), 0, "faint dialogue does not fire the recall laser")
  eq(player.lastAnim, nil, "faint dialogue does not start the exit anim")
end

function tests.faint_follows_hp_bar_not_dialogue()
  local grid = sampleGrid()
  local pHome = grid.home.player
  grid.home.playerTrainer = { u = pHome.u - 1, v = pHome.v }
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v,
    px = 16, py = 32,
    play = function(self, kind) self.lastAnim = kind end,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  local battle = {
    kind = "wild",
    player = { isPlayer = true, shownHP = 20, mon = { hp = 20, species = "PIKACHU" } },
    enemy = { shownHP = 18, mon = { hp = 18, species = "RATTATA" } },
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = { id = "enemy" },
    _now = 30,
    _battle = battle,
    _deps = { Cues = Cues, Grid = Grid, Projectiles = Projectiles },
  }
  session._deps.Cues = Cues
  Lifecycle._testBind(battle, session)

  local function countStyle(style)
    local n = 0
    for i = 1, #(session.projectiles or {}) do
      if session.projectiles[i].style == style then
        n = n + 1
      end
    end
    return n
  end

  Lifecycle.watchHpFaint(battle)
  Lifecycle.onFainted(battle, "player")
  eq(countStyle("recall"), 0, "faint event is ignored while the bar is draining")
  eq(player.lastAnim, nil, "no recall anim while shownHP > 0")

  battle.player.shownHP = 0
  battle.player.mon.hp = 0
  Lifecycle.watchHpFaint(battle)
  eq(player.lastAnim, "recall", "recall starts when the HP bar hits 0")
  eq(countStyle("recall"), 1, "one recall laser when the bar empties")

  Lifecycle.onFainted(battle, "player")
  eq(countStyle("recall"), 1, "battle.fainted after the bar does not replay the laser")

  Projectiles.clear(session)
  player._fainting = nil
  player._faintDone = nil
  player._recallDone = nil
  player.lastAnim = nil
  session._barHP = nil
  battle.player.shownHP = 12
  Lifecycle.watchHpFaint(battle)
  battle.current = { text = "PIKACHU\nfainted!", arFieldCue = { side = "player", kind = "faint" } }
  eq(Cues.pumpCurrent(session, battle, Grid, nil), false,
    "fainted dialogue does not apply the exit")
  eq(countStyle("recall"), 0, "dialogue pump does not fire the laser")
  eq(player.lastAnim, nil, "dialogue does not start recall")

  Lifecycle._testUnbind(battle)
end

function tests.self_damage_tags_field_cue()
  local battle = {
    nextInsert = 2,
    queue = {
      { text = "PIKACHU\nis confused!" },
      { text = "It hurt itself in\nits confusion!" },
    },
  }
  truthy(Cues.isSelfDamageText("It hurt itself in\nits confusion!"),
    "confusion self-hit is self-damage")
  truthy(Cues.tagSelfDamage(battle, battle.queue[2].text), "tags hurt-itself line")
  eq(battle.queue[2].arFieldCue.kind, "selfhit", "cue kind is selfhit")
  eq(battle.queue[2].arFieldCue.side, "player", "confused line names the player")

  battle = {
    nextInsert = 2,
    queue = {
      { text = "Enemy EKANS\nis confused!" },
      { text = "It hurt itself in\nits confusion!" },
    },
  }
  truthy(Cues.tagSelfDamage(battle, "hurt itself", "enemy"),
    "statusInterrupt side hint tags the foe")
  eq(battle.queue[2].arFieldCue.side, "enemy", "hint wins for nameless line")

  battle = {
    nextInsert = 1,
    queue = {
      { text = "CHARIZARD's\nhit with recoil!" },
    },
  }
  truthy(Cues.tagSelfDamage(battle, battle.queue[1].text), "tags recoil")
  eq(battle.queue[1].arFieldCue.side, "player", "recoil without Enemy is player")

  battle = {
    nextInsert = 1,
    queue = {
      { text = "Enemy RHYDON\nkept going and\ncrashed!" },
    },
  }
  truthy(Cues.tagSelfDamage(battle, battle.queue[1].text), "tags crash")
  eq(battle.queue[1].arFieldCue.side, "enemy", "Enemy prefix is the foe")
  eq(Cues.isSelfDamageText("PIKACHU\nis confused!"), false,
    "confused announcement is not a self-hit")

  battle = {
    nextInsert = 1,
    queue = {
      { text = "PIKACHU\nfainted!" },
    },
  }
  truthy(Cues.tagFaint(battle, battle.queue[1].text), "tags player faint")
  eq(battle.queue[1].arFieldCue.kind, "faint", "faint cue kind")
  eq(battle.queue[1].arFieldCue.side, "player", "player faint has no Enemy prefix")

  battle = {
    nextInsert = 1,
    queue = {
      { text = "Enemy EKANS\nfainted!" },
    },
  }
  truthy(Cues.tagFaint(battle, battle.queue[1].text), "tags foe faint")
  eq(battle.queue[1].arFieldCue.side, "enemy", "Enemy faint uses foe side")
  eq(Cues.tagFaint(battle, "A critical hit!"), false, "non-faint text is ignored")
end

function tests.attack_overlap_fires_foe_dodge()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v,
    play = function(self, kind) self.lastAnim = kind end,
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    play = function(self, kind) self.lastAnim = kind end,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 30,
    _deps = { Projectiles = Projectiles, Callouts = Callouts },
  }

  local battle = {
    current = {
      text = "SURF!",
      arFieldCue = {
        side = "player", kind = "attack",
        category = "special", moveId = "SURF", moveType = "WATER",
      },
      arOverlapReact = {
        { side = "enemy", kind = "dodge", text = "BROCK:\nOnix, dodge!", bubble = "foe" },
      },
    },
    queue = {},
  }
  truthy(Cues.pumpCurrent(session, battle, Grid, nil), "attack + dodge pump")
  eq(player.lastAnim, "cast", "surf casts in place")
  eq(enemy.lastAnim, "dodge", "foe dodges on the same beat")
  truthy(session._trainerCallouts and session._trainerCallouts.foe
      and session._trainerCallouts.foe[1], "Move! overlay is up")
  eq(session._trainerCallouts.foe[1].text, "BROCK:\nOnix, dodge!", "overlay text")

  -- Foe move order is pinned to the attack cue, not say()-time.
  session._now = 31
  session._lastCueAt = nil
  session._lastCueMoveId = nil
  player.lastAnim = nil
  enemy.lastAnim = nil
  session._trainerCallouts = nil
  Projectiles.clear(session)
  battle = {
    current = {
      text = "Enemy ONIX\nused SURF!",
      arFieldCue = {
        side = "enemy", kind = "attack",
        category = "special", moveId = "SURF", moveType = "WATER",
      },
      arNpcCallout = "BROCK:\nOnix, use Surf!",
      arNpcCalloutKind = "order",
    },
    queue = {},
  }
  truthy(Cues.pumpCurrent(session, battle, Grid, nil), "foe order pumps with attack")
  eq(enemy.lastAnim, "cast", "foe surf casts on the same beat")
  eq(session._trainerCallouts.foe[1].text, "BROCK:\nOnix, use Surf!",
    "order callout opens with the FX")
  eq(battle.current._arNpcCalloutDone, true, "order is not pushed again")

  -- Cue already fired, order stamped late — still open the box.
  session._trainerCallouts = nil
  battle.current._arFieldCueDone = true
  battle.current._arNpcCalloutDone = nil
  battle.current.arNpcCallout = "YOUNGSTER:\nOnix, use Surf!"
  truthy(Cues.pumpCurrent(session, battle, Grid, nil), "late order still pumps")
  eq(session._trainerCallouts.foe[1].text, "YOUNGSTER:\nOnix, use Surf!",
    "order opens even after the FX already started")

  -- Lookahead: queued dodge toast after the announce.
  session._now = 32
  session._lastCueAt = nil
  session._lastCueMoveId = nil
  player.lastAnim = nil
  enemy.lastAnim = nil
  session._trainerCallouts = nil
  Projectiles.clear(session)
  local queued = {
    text = "MOVE!",
    bubble = "foe",
    arFieldCue = { side = "enemy", kind = "dodge" },
  }
  battle = {
    current = {
      text = "SURF!",
      arFieldCue = {
        side = "player", kind = "attack",
        category = "special", moveId = "HYDRO_PUMP", moveType = "WATER",
      },
    },
    queue = { queued },
  }
  truthy(Cues.pumpCurrent(session, battle, Grid, nil), "lookahead dodge pumps")
  eq(enemy.lastAnim, "dodge", "queued dodge plays with the attack")
  eq(queued._arOverlapShown, true, "queued toast is consumed")
  eq(queued._arFieldCueDone, true, "queued cue will not replay")

  -- Late attach after the attack cue already fired (choose-lead / flush).
  session._now = 34
  enemy.lastAnim = nil
  session._trainerCallouts = nil
  battle.current._arFieldCueDone = true
  battle.current.arOverlapReact = {
    { side = "enemy", kind = "dodge", text = "Move!", bubble = "foe" },
  }
  battle.queue = {}
  truthy(Cues.pumpCurrent(session, battle, Grid, nil), "late overlap still fires")
  eq(enemy.lastAnim, "dodge", "dodge plays after a late attach")

  -- Narrator dodge results stay out of the NPC overlay.
  session._now = 36
  enemy.lastAnim = nil
  session._trainerCallouts = nil
  battle.current._arFieldCueDone = true
  battle.current.arOverlapReact = {
    { side = "enemy", kind = "dodge", text = "Slowpoke dodged it!", bubble = "foe" },
  }
  battle.queue = {}
  truthy(Cues.pumpCurrent(session, battle, Grid, nil), "narrative dodge still animates")
  eq(enemy.lastAnim, "dodge", "dodge cue still plays")
  truthy(not (session._trainerCallouts and session._trainerCallouts.foe),
    "dodged-it is not an NPC overlay")
end

function tests.callout_filters_narrative_and_sits_outside_fight()
  truthy(not Callouts.isTrainerSpeech("Slowpoke dodged it!"),
    "dodge result is narrative")
  truthy(not Callouts.isTrainerSpeech("But Slowpoke\ndodged aside!"),
    "whiff line is narrative")
  truthy(not Callouts.isTrainerSpeech("Enemy SLOWPOKE\nused SURF!"),
    "engine used-move is narrative")
  truthy(not Callouts.isTrainerSpeech("Go! SLOWPOKE!"),
    "send-out is narrative")
  truthy(not Callouts.isTrainerSpeech("Enemy SLOWPOKE\nis about to use\nPSYCHIC!"),
    "switch warning is narrative")
  truthy(not Callouts.isTrainerSpeech("Will RED\nchange POKéMON?"),
    "switch prompt is narrative")
  truthy(Callouts.isEnginePrompt("PSYCHIC is about to use\nSLOWPOKE!"),
    "about-to-use is an engine prompt")
  truthy(Callouts.isEnginePrompt("PIKACHU is trying to learn\nTHUNDERBOLT!"),
    "learn-move announce is an engine prompt")
  truthy(Callouts.isEnginePrompt("Delete an older move to make\nroom for THUNDERBOLT?"),
    "forget-move YES-NO is an engine prompt")
  truthy(Callouts.isEnginePrompt("PIKACHU forgot TACKLE!"),
    "forgot-move confirm is an engine prompt")
  truthy(Callouts.isTrainerSpeech("BROCK:\nOnix, dodge!"),
    "named trainer order is NPC")
  truthy(Callouts.isTrainerSpeech("YOUNGSTER:\nWow, a Slowpoke!"),
    "banter is NPC")
  truthy(Callouts.isTrainerSpeech("Onix!\nUse Surf!"),
    "generic foe order is NPC")
  truthy(Callouts.isTrainerSpeech("Onix!\nSurf!"),
    "short generic order is NPC")
  truthy(Callouts.isTrainerSpeech("Onix, get aside!"),
    "get-aside order is NPC")
  truthy(Callouts.isTrainerSpeech("BROCK: Too slow! Onix, counter!"),
    "named taunt is still NPC")

  local x, y, w, h, place = Callouts.dockRect(23, 119)
  eq(place, "above_box", "foe box sits above the regular dialogue slab")
  eq(x, 4, "full-width box matches the vanilla box")
  eq(w, 152, "box uses the dialogue width")
  eq(y + 23 + 2, 119, "gap sits between foe box and vanilla box")
  truthy(y >= 2, "box stays on the UI")
  local _, ySlot, _, _, placeSlot = Callouts.dockRect(23, nil)
  eq(placeSlot, "slot", "standalone box uses the vanilla slot")
  eq(ySlot, 119, "empty narrator leaves the foe box at the bottom")

  local session = {}
  truthy(Callouts.push(session, "foe", "BROCK:\nOnix, dodge!", { kind = "react" }),
    "first push sticks")
  Callouts.tick(session, 0.4)
  local liveAge = session._trainerCallouts.foe[1].age
  truthy(Callouts.push(session, "foe", "BROCK:\nOnix, dodge!"), "duplicate of live line")
  eq(#session._trainerCallouts.foe, 1, "same line is not stacked")
  eq(session._trainerCallouts.foe[1].age, liveAge,
    "re-push does not restart the hold")
  truthy(Callouts.ownsText(session, "BROCK:\nOnix, dodge!"), "owns the live line")
  truthy(Callouts.push(session, "foe", "Onix!\nUse Surf!", { kind = "order" }),
    "new order replaces the live shout")
  eq(#session._trainerCallouts.foe, 1, "emitted line is not queued behind")
  eq(session._trainerCallouts.foe[1].text, "Onix!\nUse Surf!",
    "latest callout is showing")
  truthy(Callouts.push(session, "foe", "Onix! Move!", { kind = "react", urgent = true }),
    "urgent react replaces")
  eq(session._trainerCallouts.foe[1].text, "Onix! Move!", "react is showing")
  eq(#session._trainerCallouts.foe, 1, "previous order is dropped")
  Callouts.tick(session, Callouts.HOLD_REACT + Callouts.FADE + 0.05)
  truthy(not (session._trainerCallouts and session._trainerCallouts.foe
      and session._trainerCallouts.foe[1]),
    "emitted callout is not replayed after the hold")

  -- Re-arm a shout to test dismiss on menu / learn-move.
  truthy(Callouts.push(session, "foe", "BROCK:\nOnix, dodge!", { kind = "react" }),
    "re-arm after expiry")
  Callouts.tick(session, 0.2, { phase = "menu" })
  truthy(not (session._trainerCallouts and session._trainerCallouts.foe),
    "command menu dismisses a used-move callout")

  truthy(Callouts.push(session, "foe", "BROCK:\nOnix, use Surf!", { kind = "order" }),
    "order before learn-move")
  local held = {
    game = {
      stack = {
        states = {},
        top = function(self)
          return self.states[#self.states]
        end,
      },
    },
  }
  local learnBox = { boxTx = 0, boxTy = 12 }
  held.game.stack.states = { held, learnBox }
  truthy(Callouts.shouldHold(held), "stacked TextBox yields the foe overlay")
  Callouts.tick(session, 1, held)
  truthy(not (session._trainerCallouts and session._trainerCallouts.foe),
    "learn-move drops the live callout instead of resuming it later")
  held.game.stack.states = { held }
  truthy(not Callouts.shouldHold(held), "yield ends when battle is top again")
end

function tests.dig_fly_vanish_and_emerge()
  eq(Cues.vanishKind("DIG"), "dig", "DIG is a dig vanish")
  eq(Cues.vanishKind("FLY"), "fly", "FLY is a fly vanish")
  eq(Cues.vanishKind("SOLARBEAM"), nil, "SolarBeam does not vanish")

  local grid = sampleGrid()
  local playerMon = {
    id = "p", padU = grid.home.player.u, padV = grid.home.player.v,
    cellX = 10, cellY = 10, px = 160, py = 160, basePx = 160, basePy = 160,
    _arFieldBattler = true,
    sprite = { id = "test" },
    play = function(self, kind) self.anim = kind end,
    pose = function(self)
      if self._removed then return nil end
      if self.hidden and not self._fieldVanished then return nil end
      return self.sprite, self.px, self.py, "down", 0, false
    end,
    _battleBattler = { invulnerable = true, charging = { id = "DIG" } },
  }
  local enemyMon = {
    id = "e", padU = grid.home.enemy.u, padV = grid.home.enemy.v,
    cellX = 12, cellY = 10, px = 192, py = 160, basePx = 192, basePy = 160,
    play = function(self, kind) self.anim = kind end,
  }
  Grid.occupy(grid, "p", playerMon.padU, playerMon.padV)
  Grid.occupy(grid, "e", enemyMon.padU, enemyMon.padV)
  local ow = { entities = { playerMon, enemyMon } }
  local session = {
    live = true,
    grid = grid,
    playerMon = playerMon,
    enemyMon = enemyMon,
    _battle = { game = { overworld = ow } },
    _deps = { Grid = Grid, Projectiles = Projectiles, Cast = Cast },
    _now = 10,
  }

  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil, {
    category = "physical", moveId = "DIG",
  }), "charge-turn dig redirects")
  eq(playerMon.anim, "vanish_dig", "dig charge plays vanish_dig")
  eq(session._lastCueKind, "vanish", "last cue is vanish")

  -- Finished dig hold: stay on ow.entities with a real pose (voxel-safe).
  playerMon._fieldVanished = true
  playerMon.hidden = false
  playerMon.anim = "buried"
  Cast.tick(session, 1 / 60)
  truthy(not playerMon._arFieldDetached, "dig does not detach from scene")
  local stillListed = false
  for i = 1, #ow.entities do
    if ow.entities[i] == playerMon then
      stillListed = true
    end
  end
  truthy(stillListed, "dig keeps sprite on ow.entities")
  local posed = playerMon:pose()
  truthy(posed, "pose returns sprite while buried")

  local digFx = Projectiles.vanish(session, "player", "dig")
  eq(digFx.style, "dig_burst", "dig vanish uses dirt burst")
  local flyFx = Projectiles.vanish(session, "enemy", "fly")
  eq(flyFx.style, "fly_gust", "fly vanish uses wind gust")

  playerMon._battleBattler.invulnerable = nil
  playerMon._battleBattler.charging = nil
  playerMon.anim = "buried"

  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil, {
    category = "physical", moveId = "DIG",
  }), "release dig emerges first")
  eq(playerMon.anim, "emerge_dig", "release starts emerge_dig")
  truthy(playerMon._pendingReleaseAttack, "release strike scheduled")
  truthy(playerMon._releaseAt, "release timer set")

  session._now = playerMon._releaseAt + 0.01
  Cues.tickReturns(session, Grid)
  eq(playerMon._pendingReleaseAttack, nil, "pending strike consumed")
  eq(playerMon.hidden, false, "visible after release strike")
  truthy(playerMon.anim == "attack" or playerMon.anim == "jump" or playerMon.anim == "cast",
    "release strike plays an attack anim")

  local battle = {
    queue = {
      { text = "PIKACHU\ndug a hole!" },
    },
    nextInsert = 1,
  }
  truthy(Cues.tagChargeVanish(battle, battle.queue[1].text), "tags dug-a-hole")
  eq(battle.queue[1].arFieldCue.kind, "vanish", "charge text cue is vanish")
  eq(battle.queue[1].arFieldCue.vanish, "dig", "charge text flavor is dig")

  battle.queue[1] = { text = "Enemy PIDGEY\nflew up high!" }
  truthy(Cues.tagChargeVanish(battle, battle.queue[1].text), "tags flew-up")
  eq(battle.queue[1].arFieldCue.vanish, "fly", "fly charge flavor")
  eq(battle.queue[1].arFieldCue.side, "enemy", "enemy charge side")
end

function tests.world_space_projectiles()
  local grid = sampleGrid()
  local player = {
    id = "player",
    padU = grid.home.player.u,
    padV = grid.home.player.v,
  }
  local enemy = {
    id = "enemy",
    padU = grid.home.enemy.u,
    padV = grid.home.enemy.v,
  }
  local overworld = { entities = { player, enemy } }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _battle = { game = { overworld = overworld } },
  }

  local move = Projectiles.move(session, "player", { moveType = "FIRE" })
  truthy(move and move._arFieldProjectile, "spawn move projectile")
  truthy(type(move.cellX) == "number" and type(move.cellY) == "number",
    "projectile satisfies overworld cell contract")
  eq(overworld.entities[#overworld.entities], enemy,
    "projectile stays off the voxel entity list")
  eq(#overworld.entities, 2, "live map cast is unchanged by a projectile")
  Projectiles.tick(session, 0.17)
  truthy(move.px > move.sx and move.px < move.ex, "projectile travels between mons")
  eq(move.cellX, math.floor(move.px / 16), "projectile keeps world cell synchronized")
  Projectiles.tick(session, 0.30)
  eq(#session.projectiles, 0, "move projectile cleans itself up")

  local beam = Projectiles.move(session, "player", { moveType = "ELECTRIC" })
  eq(beam.style, "beam", "energy type uses top-down beam")
  local area = Projectiles.move(session, "enemy", {
    moveType = "GROUND", moveId = "EARTHQUAKE",
  })
  eq(area.style, "area", "area move uses world-space ring")
  eq(Projectiles.contact(session, "player", { moveType = "NORMAL" }).style,
    "contact", "physical choreography gets contact slash")
  eq(Projectiles.status(session, "player", { moveType = "GRASS" }).style,
    "status", "status move gets orbit effect")
  eq(Projectiles.heal(session, "player").style, "heal", "healing effect available")
  eq(Projectiles.selfHit(session, "player").style, "bonk",
    "self-hit paints a bonk burst on the user")
  eq(Projectiles.faint(session, "enemy").style, "puff",
    "faint paints a dust puff on the fallen mon")
  local home = {
    playerTrainer = { u = grid.home.player.u - 1, v = grid.home.player.v },
    enemyTrainer = { u = grid.home.enemy.u + 1, v = grid.home.enemy.v },
  }
  session.grid.home = home
  session.foe = { px = 90, py = 32 }
  session._battle = { kind = "trainer", game = { overworld = overworld } }
  player.px, player.py = 16, 32
  enemy.px, enemy.py = 80, 32
  local beam = Projectiles.recallBeam(session, "player")
  truthy(beam and beam.style == "recall", "player recall fires red laser")
  truthy(beam.pinTip, "recall tip stays on the mon")
  eq(beam.followEnt, player, "recall laser is pinned to the recalled mon")
  eq(Projectiles.recallBeam(session, "enemy").style, "recall",
    "trainer foe recall fires red laser")
  player._arFieldSide = "player"
  eq(Projectiles.recallBeam(session, "enemy", { target = player }), nil,
    "enemy recall cannot target the player send-out")
  session.foe = nil
  session._battle = { kind = "wild", game = { overworld = overworld } }
  eq(Projectiles.recallBeam(session, "enemy"), nil,
    "wild foe has no trainer recall laser")
  Projectiles.clear(session)

  local flamethrower = Projectiles.move(session, "player", {
    moveType = "FIRE", moveId = "FLAMETHROWER",
  })
  eq(flamethrower.style, "stream", "named fire move uses stream glitz")
  eq(flamethrower.glitz, "flame", "flamethrower paints flame trail")
  truthy((flamethrower.duration or 0) >= 0.45, "flamethrower holds a longer stream")
  truthy(flamethrower.sx < flamethrower.ex, "flamethrower travels toward the foe")
  local ember = Projectiles.move(session, "player", {
    moveType = "FIRE", moveId = "EMBER",
  })
  eq(ember.style, "ember", "ember uses bouncing flame tongues")
  eq(ember.glitz, "flame", "ember paints flame glitz")
  truthy(ember.sx < ember.ex, "ember travels toward the foe")
  truthy((ember.arc or 0) >= 10, "ember arcs like bouncing fireballs")
  truthy(Projectiles.isTravelFx({
    moveType = "FIRE", moveId = "EMBER",
  }), "ember is a travel FX")
  local fireBlast = Projectiles.move(session, "player", {
    moveType = "FIRE", moveId = "FIRE_BLAST",
  })
  eq(fireBlast.style, "blast", "fire blast uses a traveling fireball")
  eq(fireBlast.glitz, "flame", "fire blast paints flame tongues")
  truthy(fireBlast.sx < fireBlast.ex, "fire blast travels toward the foe")
  truthy(Projectiles.isTravelFx({
    moveType = "FIRE", moveId = "FIRE_BLAST",
  }), "fire blast is a travel FX")
  local fireSpin = Projectiles.move(session, "player", {
    moveType = "FIRE", moveId = "FIRE_SPIN",
  })
  eq(fireSpin.style, "spiral", "fire spin swirls around the foe")
  eq(fireSpin.glitz, "flame", "fire spin paints flame tongues")
  local gust = Projectiles.move(session, "player", {
    moveType = "FLYING", moveId = "GUST",
  })
  eq(gust.style, "gust", "gust uses a traveling wind projectile")
  eq(gust.glitz, "wind", "gust paints wind crescents")
  truthy(gust.sx < gust.ex, "gust travels toward the foe")
  truthy((gust.duration or 0) >= 0.5, "gust holds a longer draft")
  truthy(Projectiles.isTravelFx({
    moveType = "FLYING", moveId = "GUST",
  }), "gust is a travel FX")
  truthy(not Projectiles.isContactFx({ moveId = "GUST" }), "gust is not contact FX")
  truthy(not Cues.isMeleeAttack({
    category = "physical", moveId = "GUST", moveType = "FLYING",
  }, Projectiles), "gust stays a travel cast even though Flying is physical")
  local wing = Projectiles.contact(session, "player", {
    moveType = "FLYING", moveId = "WING_ATTACK",
  })
  eq(wing.glitz, "wing", "wing attack uses a wing slash")
  local flyHit = Projectiles.contact(session, "player", {
    moveType = "FLYING", moveId = "FLY",
  })
  eq(flyHit.glitz, "wing", "fly strike uses a wing slash")
  local sky = Projectiles.contact(session, "player", {
    moveType = "FLYING", moveId = "SKY_ATTACK",
  })
  eq(sky.glitz, "wing", "sky attack uses a wing slash")
  local bubblebeam = Projectiles.move(session, "player", {
    moveType = "WATER", moveId = "BUBBLEBEAM",
  })
  eq(bubblebeam.style, "stream", "bubble beam uses stream particles")
  eq(bubblebeam.glitz, "bubble", "bubble beam paints bubble particles")
  local thunderbolt = Projectiles.move(session, "player", {
    moveType = "ELECTRIC", moveId = "THUNDERBOLT",
  })
  eq(thunderbolt.style, "beam", "thunderbolt is a beam")
  eq(thunderbolt.glitz, "bolt", "thunderbolt uses lightning bolt glitz")
  local iceBeam = Projectiles.move(session, "player", {
    moveType = "ICE", moveId = "ICE_BEAM",
  })
  eq(iceBeam.style, "beam", "ice beam is a bolt-style beam")
  eq(iceBeam.glitz, "icebolt", "ice beam uses ice bolt glitz")
  eq(iceBeam.color[3], 1.00, "ice beam uses crisp ice blue")
  truthy(iceBeam.sx < iceBeam.ex, "ice beam travels toward the foe")
  local shock = Projectiles.move(session, "enemy", {
    moveType = "ELECTRIC", moveId = "THUNDERSHOCK",
  })
  eq(shock.glitz, "bolt", "thundershock uses lightning bolt glitz")
  local nightShade = Projectiles.move(session, "player", {
    moveType = "GHOST", moveId = "NIGHT_SHADE",
  })
  eq(nightShade.style, "shadow", "night shade uses slithering shadow")
  eq(nightShade.glitz, "shade", "night shade uses shade glitz")
  truthy((nightShade.duration or 0) >= 0.5, "night shade holds a longer ribbon")
  truthy(Projectiles.isTravelFx({
    moveType = "GHOST", moveId = "NIGHT_SHADE",
  }), "night shade is a travel FX")
  local surf = Projectiles.move(session, "player", {
    moveType = "WATER", moveId = "SURF",
  })
  eq(surf.style, "surf", "surf uses rushing tide animation")
  eq(surf.glitz, "tide", "surf uses tide glitz")
  truthy(surf.sx < surf.ex, "surf travels toward the foe")
  truthy((surf.duration or 0) >= 0.6, "surf holds a longer surge")
  truthy(Projectiles.isTravelFx({
    moveType = "WATER", moveId = "SURF",
  }), "surf is a travel FX")
  local razor = Projectiles.move(session, "player", {
    moveType = "GRASS", moveId = "RAZOR_LEAF",
  })
  eq(razor.style, "razor", "razor leaf uses spinning blade animation")
  eq(razor.glitz, "blade", "razor leaf uses blade glitz")
  truthy(razor.sx < razor.ex, "razor leaf travels toward the foe")
  truthy((razor.duration or 0) >= 0.5, "razor leaf holds a longer volley")
  truthy(Projectiles.isTravelFx({
    moveType = "GRASS", moveId = "RAZOR_LEAF",
  }), "razor leaf is a travel FX")
  local swift = Projectiles.move(session, "player", {
    moveType = "NORMAL", moveId = "SWIFT",
  })
  eq(swift.style, "swift", "swift uses flying star animation")
  eq(swift.glitz, "star", "swift uses star glitz")
  truthy(swift.sx < swift.ex, "swift travels toward the foe")
  truthy((swift.duration or 0) >= 0.5, "swift holds a longer volley")
  truthy(Projectiles.isTravelFx({
    moveType = "NORMAL", moveId = "SWIFT",
  }), "swift is a travel FX")
  Projectiles.clear(session)
  local quake = Projectiles.move(session, "player", {
    moveType = "GROUND", moveId = "EARTHQUAKE",
  })
  eq(quake.style, "area", "earthquake keeps a world-space rumble")
  eq(quake.glitz, "quake", "earthquake uses quake glitz")
  local digs = 0
  for i = 1, #(session.projectiles or {}) do
    if session.projectiles[i].style == "dig_burst" then
      digs = digs + 1
    end
  end
  truthy(digs >= 4, "earthquake pops dig bursts across the pad")
  local psychic = Projectiles.move(session, "player", {
    moveType = "PSYCHIC", moveId = "PSYCHIC",
  })
  eq(psychic.style, "aura", "psychic uses enveloping aura")
  eq(psychic.glitz, "psy", "psychic uses crush aura glitz")
  truthy(psychic.pinTip, "psychic aura stays on the target")
  local psychicM = Projectiles.move(session, "player", {
    moveType = "PSYCHIC", moveId = "PSYCHIC_M",
  })
  eq(psychicM.style, "aura", "PSYCHIC_M aliases psychic aura")
  local confusion = Projectiles.move(session, "enemy", {
    moveType = "PSYCHIC", moveId = "CONFUSION",
  })
  eq(confusion.style, "aura", "confusion uses enveloping aura")
  eq(confusion.glitz, "confuse", "confusion uses dizzy aura glitz")
  local leechSeed = Projectiles.status(session, "player", {
    moveType = "GRASS", moveId = "LEECH_SEED",
  })
  eq(leechSeed.style, "seed", "leech seed uses planting animation")
  eq(leechSeed.glitz, "leaf", "leech seed uses leaf glitz")
  truthy(leechSeed.sx < leechSeed.ex, "leech seed travels toward the foe")
  truthy(leechSeed.pinTip, "leech seed plants on the target")
  local supersonic = Projectiles.status(session, "player", {
    moveType = "NORMAL", moveId = "SUPERSONIC",
  })
  eq(supersonic.style, "sonic", "supersonic uses traveling sound rings")
  eq(supersonic.glitz, "ring", "supersonic uses ring glitz")
  truthy(supersonic.sx < supersonic.ex, "supersonic travels toward the foe")
  truthy(supersonic.pinTip, "supersonic rings lock onto the target")
  local confuseRay = Projectiles.status(session, "player", {
    moveType = "GHOST", moveId = "CONFUSE_RAY",
  })
  eq(confuseRay.style, "ray", "confuse ray uses a smog wad")
  eq(confuseRay.glitz, "confuse", "confuse ray uses dizzy glitz")
  truthy(confuseRay.sx < confuseRay.ex, "confuse ray travels toward the foe")
  truthy(confuseRay.pinTip, "confuse ray locks onto the target")
  truthy(Projectiles.isTravelFx({
    moveType = "NORMAL", moveId = "SUPERSONIC",
  }), "supersonic is a travel FX")
  truthy(Projectiles.isTravelFx({
    moveType = "GHOST", moveId = "CONFUSE_RAY",
  }), "confuse ray is a travel FX")
  truthy(Projectiles.isTravelFx({
    moveType = "PSYCHIC", moveId = "PSYCHIC",
  }), "psychic is a travel FX")
  local slash = Projectiles.contact(session, "player", {
    moveType = "NORMAL", moveId = "SLASH",
  })
  eq(slash.glitz, "slash", "slash contact keeps cut glitz")
  local bite = Projectiles.contact(session, "player", {
    moveType = "NORMAL", moveId = "BITE",
  })
  eq(bite.glitz, "bite", "bite contact uses jaw glitz")
  truthy(Projectiles.isContactFx({ moveId = "BITE" }), "bite is contact FX")
  truthy(Projectiles.isContactFx({ moveId = "FIRE_PUNCH" }), "fire punch is contact FX")
  truthy(not Projectiles.isTravelFx({ moveId = "BITE" }), "bite is not travel FX")
  truthy(Cues.isMeleeAttack({
    category = "special", moveId = "BITE", moveType = "DARK",
  }, Projectiles), "dark bite still counts as melee")
  truthy(Cues.isMeleeAttack({
    category = "special", moveId = "FIRE_PUNCH", moveType = "FIRE",
  }, Projectiles), "fire punch still counts as melee")
  truthy(not Cues.isMeleeAttack({
    category = "physical", moveId = "NIGHT_SHADE", moveType = "GHOST",
  }, Projectiles), "night shade stays a travel cast")
  local pound = Projectiles.contact(session, "player", {
    moveType = "NORMAL", moveId = "POUND",
  })
  eq(pound.glitz, "slap", "pound uses a slap contact")
  local scratch = Projectiles.contact(session, "player", {
    moveType = "NORMAL", moveId = "SCRATCH",
  })
  eq(scratch.glitz, "slash", "scratch uses slash contact")
  local peck = Projectiles.contact(session, "player", {
    moveType = "FLYING", moveId = "PECK",
  })
  eq(peck.glitz, "pierce", "peck uses pierce contact")
  local sting = Projectiles.contact(session, "player", {
    moveType = "POISON", moveId = "POISON_STING",
  })
  eq(sting.glitz, "sting", "poison sting uses a stinger")
  local payday = Projectiles.contact(session, "player", {
    moveType = "NORMAL", moveId = "PAY_DAY",
  })
  eq(payday.glitz, "coin", "pay day tosses coin sparks")
  local light = Projectiles.lightHit(session, "enemy", {
    moveType = "NORMAL", moveId = "TACKLE",
  })
  eq(light.style, "light_hit", "weak physicals get a light hit burst")
  eq(light.glitz, "impact", "tackle light hit keeps impact glitz")
  Projectiles.clear(session)

  local resolved = false
  Projectiles.ball(session, {
    shakes = 2,
    onDone = function() resolved = true end,
  })
  Projectiles.tick(session, 1)
  truthy(resolved, "ball resolves after flight and shakes")
  eq(#session.projectiles, 0, "ball projectile cleans itself up")
end

function tests.supersonic_and_confuse_ray_paint()
  local calls = { arc = 0, line = 0, circle = 0, ellipse = 0 }
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      setLineWidth = function() end,
      line = function() calls.line = calls.line + 1 end,
      arc = function() calls.arc = calls.arc + 1 end,
      ellipse = function() calls.ellipse = calls.ellipse + 1 end,
      circle = function() calls.circle = calls.circle + 1 end,
      rectangle = function() end,
      polygon = function() end,
    },
  }
  local grid = sampleGrid()
  local player = {
    id = "player",
    padU = grid.home.player.u,
    padV = grid.home.player.v,
    px = 16, py = 32,
  }
  local enemy = {
    id = "enemy",
    padU = grid.home.enemy.u,
    padV = grid.home.enemy.v,
    px = 80, py = 32,
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _battle = { game = { overworld = { entities = { player, enemy } } } },
  }
  local sonic = Projectiles.status(session, "player", {
    moveType = "NORMAL", moveId = "SUPERSONIC",
  })
  sonic.age = 0.35
  sonic:draw(0, 0)
  truthy(calls.arc > 0, "supersonic paints traveling sound arcs")

  calls.arc, calls.line, calls.circle, calls.ellipse = 0, 0, 0, 0
  local ray = Projectiles.status(session, "player", {
    moveType = "GHOST", moveId = "CONFUSE_RAY",
  })
  ray.age = 0.28
  ray:draw(0, 0)
  truthy(calls.ellipse > 0, "confuse ray paints a short smog wad")
  truthy(calls.circle > 0, "confuse ray paints smog wisps")
  truthy(calls.line > 0, "confuse ray leaves a light trail")
  love = prevLove
end

function tests.fire_tongues_and_gust_paint()
  local calls = { polygon = 0, arc = 0, circle = 0, ellipse = 0, line = 0 }
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      setLineWidth = function() end,
      line = function() calls.line = calls.line + 1 end,
      arc = function() calls.arc = calls.arc + 1 end,
      ellipse = function() calls.ellipse = calls.ellipse + 1 end,
      circle = function() calls.circle = calls.circle + 1 end,
      rectangle = function() end,
      polygon = function() calls.polygon = calls.polygon + 1 end,
    },
  }
  local grid = sampleGrid()
  local player = {
    id = "player",
    padU = grid.home.player.u,
    padV = grid.home.player.v,
    px = 16, py = 32,
  }
  local enemy = {
    id = "enemy",
    padU = grid.home.enemy.u,
    padV = grid.home.enemy.v,
    px = 80, py = 32,
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _battle = { game = { overworld = { entities = { player, enemy } } } },
  }

  local ember = Projectiles.move(session, "player", {
    moveType = "FIRE", moveId = "EMBER",
  })
  ember.age = 0.28
  ember:draw(0, 0)
  truthy(calls.polygon > 0, "ember paints flame-tongue polygons, not red blobs")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local flamethrower = Projectiles.move(session, "player", {
    moveType = "FIRE", moveId = "FLAMETHROWER",
  })
  flamethrower.age = 0.22
  flamethrower:draw(0, 0)
  truthy(calls.polygon > 0, "flamethrower paints a jet of flame tongues")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local blast = Projectiles.move(session, "player", {
    moveType = "FIRE", moveId = "FIRE_BLAST",
  })
  blast.age = 0.50
  blast:draw(0, 0)
  truthy(calls.polygon > 0, "fire blast paints a star of flame tongues")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local gust = Projectiles.move(session, "player", {
    moveType = "FLYING", moveId = "GUST",
  })
  gust.age = 0.32
  gust:draw(0, 0)
  truthy(calls.arc > 0, "gust paints traveling wind crescents")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local wing = Projectiles.contact(session, "player", {
    moveType = "FLYING", moveId = "WING_ATTACK",
  })
  wing.age = 0.12
  wing:draw(0, 0)
  truthy(calls.arc > 0, "wing attack paints a flying crescent slash")
  love = prevLove
end

function tests.camera_avoids_battle_menu()
  local grid = sampleGrid()
  local followed
  local camera = {
    follow = function(_, x, y)
      followed = { x = x, y = y }
    end,
  }
  local battle = {
    game = {
      overworld = { camera = camera },
      renderer = { worldViewSize = function() return 160, 144 end },
    },
  }
  local player = { padU = grid.home.player.u, padV = grid.home.player.v }
  local enemy = { padU = grid.home.enemy.u, padV = grid.home.enemy.v }
  Lifecycle._testBind(battle, {
    state = Lifecycle.STATE.Live,
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    envelope = { gridRect = grid.worldRect },
  })
  -- No prior camera pose → settle on the opening formation immediately.
  Lifecycle.focusCamera(battle)
  Lifecycle._testUnbind(battle)

  truthy(followed, "camera follows field cast")
  local px, py = Coords.padCenterPx(grid, player.padU, player.padV)
  local ex, ey = Coords.padCenterPx(grid, enemy.padU, enemy.padV)
  eq(followed.y, (py + ey) / 2 + Lifecycle.CAMERA_UI_BIAS_Y,
    "camera stably frames the fight above the menu")
end

function tests.camera_pans_to_envelope()
  local grid = sampleGrid()
  local followed
  local camera = {
    -- Seed away from the envelope so focusCamera must ease, not snap.
    x = 0,
    y = 0,
    follow = function(self, x, y, vw, vh)
      vw, vh = vw or 160, vh or 144
      self.x = x - (vw / 2 - 16)
      self.y = y - (vh / 2 - 8)
      followed = { x = x, y = y }
    end,
  }
  local battle = {
    game = {
      overworld = { camera = camera },
      renderer = { worldViewSize = function() return 160, 144 end },
    },
  }
  local player = { padU = grid.home.player.u, padV = grid.home.player.v }
  local enemy = { padU = grid.home.enemy.u, padV = grid.home.enemy.v }
  Lifecycle._testBind(battle, {
    state = Lifecycle.STATE.Live,
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    envelope = { gridRect = grid.worldRect },
  })

  local px, py = Coords.padCenterPx(grid, player.padU, player.padV)
  local ex, ey = Coords.padCenterPx(grid, enemy.padU, enemy.padV)
  local targetX = (px + ex) / 2
  local targetY = (py + ey) / 2 + Lifecycle.CAMERA_UI_BIAS_Y

  Lifecycle.focusCamera(battle, 1 / 60)
  truthy(followed, "camera begins soft pan")
  local mid1 = followed
  truthy(math.abs(mid1.x - targetX) > 1 or math.abs(mid1.y - targetY) > 1,
    "first frame has not snapped to envelope")

  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  Lifecycle._testUnbind(battle)

  eq(followed.x, targetX, "pan settles on fight center X")
  eq(followed.y, targetY, "pan settles on fight center Y above menu")
end

function tests.camera_tracks_live_battlers()
  local grid = sampleGrid()
  local followed
  local camera = {
    x = 0,
    y = 0,
    follow = function(self, x, y, vw, vh)
      vw, vh = vw or 160, vh or 144
      self.x = x - (vw / 2 - 16)
      self.y = y - (vh / 2 - 8)
      followed = { x = x, y = y }
    end,
  }
  local battle = {
    game = {
      overworld = { camera = camera },
      renderer = { worldViewSize = function() return 160, 144 end },
    },
  }
  local player = { padU = grid.home.player.u, padV = grid.home.player.v }
  local enemy = { padU = grid.home.enemy.u, padV = grid.home.enemy.v }
  Lifecycle._testBind(battle, {
    state = Lifecycle.STATE.Live,
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    envelope = { gridRect = grid.worldRect },
  })

  Lifecycle.focusCamera(battle)
  local startX = followed.x
  -- Knock / cover: foe steps several pads off the opening formation.
  enemy.padU = grid.home.enemy.u + 3
  enemy.padV = (grid.home.enemy.v or 0) + 2
  local px, py = Coords.padCenterPx(grid, player.padU, player.padV)
  local ex, ey = Coords.padCenterPx(grid, enemy.padU, enemy.padV)
  local wantX = (px + ex) / 2
  local wantY = (py + ey) / 2 + Lifecycle.CAMERA_UI_BIAS_Y
  local rect = grid.worldRect
  local cell = Coords.CELL
  local pad = Lifecycle.CAMERA_CLAMP_PAD
  local minX = rect.minX * cell + cell / 2 - pad
  local maxX = rect.maxX * cell + cell / 2 + pad
  local minY = rect.minY * cell + cell / 2 - pad
  local maxY = rect.maxY * cell + cell / 2 + pad
  if wantX < minX then wantX = minX elseif wantX > maxX then wantX = maxX end
  local actionY = (py + ey) / 2
  if actionY < minY then actionY = minY elseif actionY > maxY then actionY = maxY end
  wantY = actionY + Lifecycle.CAMERA_UI_BIAS_Y

  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  Lifecycle._testUnbind(battle)

  truthy(math.abs(followed.x - startX) > 2, "camera leaves the static envelope lock")
  eq(followed.x, wantX, "pan settles on live battler midpoint X")
  eq(followed.y, wantY, "pan settles on live battler midpoint Y above menu")
end

function tests.camera_mouse_look_then_returns()
  local grid = sampleGrid()
  local followed
  local camera = {
    x = 0,
    y = 0,
    follow = function(self, x, y, vw, vh)
      vw, vh = vw or 160, vh or 144
      self.x = x - (vw / 2 - 16)
      self.y = y - (vh / 2 - 8)
      followed = { x = x, y = y }
    end,
  }
  local battle = {
    game = {
      overworld = { camera = camera },
      renderer = { worldViewSize = function() return 160, 144 end },
    },
  }
  local player = { padU = grid.home.player.u, padV = grid.home.player.v }
  local enemy = { padU = grid.home.enemy.u, padV = grid.home.enemy.v }
  local session = {
    state = Lifecycle.STATE.Live,
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    envelope = { gridRect = grid.worldRect },
    _mouseLookInjected = true,
  }
  Lifecycle._testBind(battle, session)

  local nx, ny = Lifecycle.mouseLookFromWindow(160, 72, 160, 144)
  eq(nx, 1, "right edge is +1 look X")
  eq(ny, 0, "vertical center is 0 look Y")

  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  local restX = followed.x
  local restY = followed.y

  Lifecycle.noteMouseLook(session, 1, 0, 8)
  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  truthy(followed.x > restX + 8, "mouse motion peeks the camera to the right")
  local peekedX = followed.x

  session.mouseLookT = 0
  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  Lifecycle._testUnbind(battle)

  eq(followed.x, restX, "idle mouse returns camera X to auto framing")
  eq(followed.y, restY, "idle mouse returns camera Y to auto framing")
  truthy(peekedX ~= restX, "look-around actually moved the camera")
end

function tests.sprite_cast_and_animation()
  local grid, plan = sampleGrid()
  local overworld = { entities = {} }
  local battle = {
    game = { overworld = overworld },
    player = { mon = { species = "TEST_PLAYER" } },
    enemy = { mon = { species = "TEST_ENEMY" } },
  }
  local session = { plan = plan, grid = grid }
  local enemy = Cast.stageEnemy(session, battle, nil, Sprites, Grid)
  local player = Cast.stagePlayer(session, battle, nil, Sprites, Grid)

  truthy(player and enemy, "stage both battlers")
  eq(player._battleBattler, battle.player, "player bar binds live battler")
  eq(enemy._battleBattler, battle.enemy, "enemy bar binds live battler")
  eq(player.padU, grid.home.player.u, "player starts at home u")
  eq(enemy.padU, grid.home.enemy.u, "enemy starts at home u")
  eq(grid.occ[Coords.key(player.padU, player.padV)], player.id,
    "player occupies tracked cell")
  eq(grid.occ[Coords.key(enemy.padU, enemy.padV)], enemy.id,
    "enemy occupies tracked cell")

  player:play("attack")
  for _ = 1, 30 do
    Cast.tick(session, 1 / 60)
  end
  eq(player.anim, "idle", "attack returns to idle")
  Cast.tick(session, 0.10)
  eq(player.px, player.basePx, "idle bob has no horizontal sway")
  truthy(player.py ~= player.basePy, "idle pose bobs vertically")

  enemy:play("faint")
  for _ = 1, 55 do
    Cast.tick(session, 1 / 60)
  end
  truthy(enemy._faintDone, "faint animation completes")
  truthy(enemy.hidden, "fainted sprite hides after the collapse")
end

function tests.tick_does_not_replay_attack_while_react_holds_anim()
  -- Issue #3: REACT leaves battle.animPlaying true after the FIELD clip
  -- returns to idle. Tick must not start a second (or third) attack.
  local grid, plan = sampleGrid()
  local overworld = { entities = {} }
  local battle = {
    game = { overworld = overworld },
    player = { mon = { species = "TEST_PLAYER" } },
    enemy = { mon = { species = "TEST_ENEMY" } },
    animPlaying = true,
    moveAnimRow = { anim = "TACKLE", attackerIsPlayer = false },
  }
  local session = {
    state = Lifecycle.STATE.Live,
    live = true,
    plan = plan,
    grid = grid,
    _battle = battle,
  }
  local deps = {
    Cast = Cast,
    Sprites = Sprites,
    Grid = Grid,
    Projectiles = { tick = function() end, syncCoverHold = function() end },
    Cues = {
      pumpCurrent = function() end,
      tickReturns = function() end,
    },
    Anims = { cache = function() end },
  }
  session._deps = deps
  session.playerMon = Cast.stagePlayer(session, battle, nil, Sprites, Grid)
  session.enemyMon = Cast.stageEnemy(session, battle, nil, Sprites, Grid)
  Lifecycle._testBind(battle, session)

  session.enemyMon:play("attack")
  for _ = 1, 40 do
    Lifecycle.tick(battle, 1 / 60, deps)
  end
  eq(session.enemyMon.anim, "idle", "first FIELD swing finished")
  Lifecycle.tick(battle, 1 / 60, deps)
  eq(session.enemyMon.anim, "idle",
    "REACT hold must not restart the attack clip")
  Lifecycle._testUnbind(battle)
end

function tests.switch_and_capture_choreography()
  local grid, plan = sampleGrid()
  local overworld = { entities = {} }
  local battle = {
    game = { overworld = overworld },
    player = { mon = { species = "FIRST_MON" } },
    enemy = { mon = { species = "WILD_MON" } },
  }
  local session = {
    state = Lifecycle.STATE.Live,
    live = true,
    plan = plan,
    grid = grid,
    _battle = battle,
  }
  local deps = {
    Cast = Cast,
    Sprites = Sprites,
    Grid = Grid,
    Projectiles = Projectiles,
    Cues = {
      pumpCurrent = function() end,
      tickReturns = function() end,
    },
    Anims = { cache = function() end },
  }
  session._deps = deps
  session.playerMon = Cast.stagePlayer(session, battle, nil, Sprites, Grid)
  session.enemyMon = Cast.stageEnemy(session, battle, nil, Sprites, Grid)
  Lifecycle._testBind(battle, session)

  local old = session.playerMon
  battle.player = { mon = { species = "SECOND_MON" } }
  Lifecycle.syncMons(battle, nil, deps)
  eq(old.anim, "recall", "old battler recalls before switch")
  truthy(session.pendingSwitch and session.pendingSwitch.player,
    "replacement waits for recall")
  eq(session.enemyMon.anim, "sendout", "foe is not recalled on a player switch")
  eq(session.pendingSwitch.enemy, nil, "player switch does not queue a foe send-out")
  Lifecycle.tick(battle, 0.55, deps)
  eq(session.playerMon.species, "SECOND_MON", "replacement species staged")
  truthy(session.playerMon._sendoutStarted, "replacement uses send-out animation")
  truthy(old._arFieldDetached or old._recallDone,
    "recalled mon left the live entity list")
  eq(session.enemyMon.species, "WILD_MON", "foe species unchanged after player switch")
  truthy(session.enemyMon.anim ~= "recall", "foe stays off the recall path")

  Projectiles.clear(session)
  local fainted = session.playerMon
  fainted._fainting = true
  fainted.anim = "recall"
  local foeAnim = session.enemyMon.anim
  battle.player = { mon = { species = "THIRD_MON" } }
  Lifecycle.syncMons(battle, nil, deps, "player")
  local beams = 0
  for i = 1, #(session.projectiles or {}) do
    if session.projectiles[i].style == "recall" then
      beams = beams + 1
    end
  end
  eq(beams, 0, "switch after faint does not fire a second recall laser")
  eq(fainted.anim, "recall", "already-recalling anim is not restarted")
  eq(session.enemyMon.anim, foeAnim, "player faint/send-out does not animate the foe")
  eq(session.pendingSwitch.enemy, nil, "player faint does not queue a foe recall")

  -- Foe wandered onto player home: send-out must not steal that tile.
  local foe = session.enemyMon
  local pHome = grid.home.player
  Grid.release(grid, session.playerMon.id)
  truthy(Grid.setPad(grid, foe, pHome.u, pHome.v), "foe can stand on empty player home")
  local foePadU, foePadV = foe.padU, foe.padV
  battle.player = { mon = { species = "FOURTH_MON" } }
  local spawned = Cast.replace(session, battle, nil, Sprites, Grid, "player",
    battle.player)
  truthy(spawned, "replacement still stages")
  eq(session.enemyMon, foe, "opposing sprite is not replaced")
  truthy(not foe.hidden and not foe._removed, "opposing sprite stays visible")
  eq(foe.padU, foePadU, "foe keeps its pad u")
  eq(foe.padV, foePadV, "foe keeps its pad v")
  eq(grid.occ[Coords.key(foe.padU, foe.padV)], foe.id, "foe still owns its cell")
  truthy(spawned.padU ~= foe.padU or spawned.padV ~= foe.padV,
    "send-out landed on an empty tile")
  eq(spawned.species, "FOURTH_MON", "new player species staged beside the foe")

  local savedEnemyMon = battle.enemy.mon
  battle.enemy.mon = nil
  Lifecycle.syncMons(battle, nil, deps)
  eq(session.enemyMon.anim, foeAnim, "missing foe species does not recall the live foe")
  battle.enemy.mon = savedEnemyMon

  truthy(Lifecycle.capture(battle, { caught = true, shakes = 1 }),
    "capture choreography starts")
  Projectiles.tick(session, 1)
  eq(session.enemyMon.anim, "capture", "caught target enters capture animation")
  Cast.tick(session, 0.5)
  truthy(session.enemyMon._captureDone, "capture animation completes")
  Lifecycle._testUnbind(battle)
end

function tests.lifecycle_cleanup_restores_world()
  local player = {
    cellX = 9, cellY = 9, px = 144, py = 144,
    facing = "left", frozen = false, wanders = true, inputLocked = true,
  }
  local npc = { id = "npc" }
  local transient = { id = "field", _arFieldBattler = true }
  local worldEntities = { player, npc, transient }
  local followed = false
  local overworld = {
    player = player,
    engaging = true,
    _arFieldEngaging = true,
    entities = worldEntities,
    camera = {
      x = 200, y = 200,
      follow = function(self, x, y, vw, vh)
        vw, vh = vw or 160, vh or 144
        self.x = x - (vw / 2 - 16)
        self.y = y - (vh / 2 - 8)
        followed = (x == 144 and y == 144)
      end,
    },
  }
  local battle = { game = { overworld = overworld }, _arAnimeField = true }
  local grid = sampleGrid()
  local pose = Layout.copyPose(player)
  player.cellX, player.cellY, player.px, player.py = 20, 20, 320, 320
  player.frozen, player.wanders = true, false

  local ended = false
  local voxel3d = {
    camera = { kind = "battle" },
    endScene = function()
      ended = true
    end,
  }
  local voxelState = { ready = false }
  local finishCalls = 0
  Lifecycle._testBind(battle, {
    state = Lifecycle.STATE.Live,
    live = true,
    playerPose = pose,
    savedEntities = worldEntities,
    grid = grid,
    voxelSaved = 2,
    _mod = {
      find = function()
        return {
          exports = {
            lib = {
              require = function(name)
                if name == "OverworldBattle" then
                  return {
                    finish = function()
                      finishCalls = finishCalls + 1
                    end,
                  }
                end
                if name == "Voxel3D" then
                  return voxel3d
                end
                if name == "VoxelState" then
                  return voxelState
                end
              end,
            },
          },
        }
      end,
    },
    _deps = { Layout = Layout, Grid = Grid, Compat = Compat },
  })
  local setCalls = {}
  package.loaded["src.render.Pipelines"] = {
    level = function() return 2 end,
    setLevel = function(name, level)
      setCalls[#setCalls + 1] = { name, level }
    end,
  }
  Lifecycle.finish(battle, { Layout = Layout, Grid = Grid, Compat = Compat })
  package.loaded["src.render.Pipelines"] = nil

  eq(player.cellX, 9, "restore player cell x")
  eq(player.cellY, 9, "restore player cell y")
  eq(player.facing, "left", "restore player facing")
  eq(player.padU, nil, "clear temporary player pad coordinate")
  eq(player.padV, nil, "clear temporary player pad coordinate")
  eq(player.inputLocked, false, "unlock player")
  eq(overworld.entities, worldEntities, "restore original entities table")
  eq(overworld.entities[1], player, "restore player entity")
  eq(overworld.entities[2], npc, "restore npc entity")
  eq(overworld.entities[3], nil, "remove field entity")
  truthy(followed, "camera follows player after restore")
  truthy(overworld.cameraPan and overworld.cameraPan.arFieldReturn,
    "exit soft-pan starts instead of hard snap")
  truthy(math.abs(overworld.cameraPan.ox) > 1 or math.abs(overworld.cameraPan.oy) > 1,
    "exit pan retains battle framing offset")
  eq(battle._arAnimeField, nil, "clear battle marker")
  eq(Lifecycle.get(battle), nil, "remove session")
  eq(#setCalls, 0, "voxel restore does not bounce through off")
  eq(finishCalls, 3, "release OverworldBattle.finish on DS/voxel mods")
  eq(voxel3d.camera, nil, "clear leftover Voxel3D.camera")
  truthy(ended, "unbind leftover Voxel3D scene canvas")
  eq(voxelState.ready, true, "voxel tween is allowed to resume")
end

function tests.camera_pans_to_player_on_finish()
  local player = { px = 144, py = 144 }
  local camera = { x = 40, y = 20 }
  function camera:follow(px, py, vw, vh)
    vw, vh = vw or 160, vh or 144
    self.x = px - (vw / 2 - 16)
    self.y = py - (vh / 2 - 8)
  end
  local overworld = { player = player, camera = camera, entities = { player } }
  local battle = { game = { overworld = overworld }, _arAnimeField = true }
  Lifecycle._testBind(battle, {
    state = Lifecycle.STATE.Live,
    live = true,
    playerPose = { cellX = 9, cellY = 9, px = 144, py = 144, facing = "down" },
    savedEntities = overworld.entities,
    _deps = { Layout = Layout, Grid = Grid, Compat = Compat },
  })
  Lifecycle.finish(battle, { Layout = Layout, Grid = Grid, Compat = Compat })
  truthy(overworld.cameraPan and overworld.cameraPan.arFieldReturn,
    "return pan armed")
  local startOx = overworld.cameraPan.ox
  local startOy = overworld.cameraPan.oy
  truthy(math.abs(startOx) > 1 or math.abs(startOy) > 1, "non-zero exit offset")

  for _ = 1, 180 do
    Lifecycle.tickReturnCamera(overworld, 1 / 60)
  end
  eq(overworld.cameraPan, nil, "return pan settles onto player")
end

function tests.parks_overworld_follower_during_field()
  local player = { id = "red" }
  local follower = {
    id = "pikachu",
    isFollower = true,
    sprite = { def = { id = "SPRITE_PIKACHU" } },
  }
  local npc = { id = "npc" }
  local battler = { id = "field", _arFieldBattler = true }
  local worldEntities = { player, follower, npc, battler }
  local overworld = { player = player, entities = worldEntities }
  local session = { foe = nil, parkedFollowers = nil }
  truthy(Lifecycle.isOverworldFollower(follower, player, nil),
    "party follower is detected")
  truthy(not Lifecycle.isOverworldFollower(player, player, nil),
    "player is not parked as a follower")
  truthy(not Lifecycle.isOverworldFollower(battler, player, nil),
    "field battler is not parked as a follower")
  Lifecycle.parkOverworldFollowers(session, overworld)
  eq(overworld.entities[1], player, "player stays on the live voxel list")
  eq(overworld.entities[2], npc, "npcs stay on the live voxel list")
  eq(overworld.entities[3], battler, "field battler stays on the live voxel list")
  eq(overworld.entities[4], nil, "follower leaves the live voxel list")
  eq(follower.hidden, true, "parked follower is hidden")
  eq(overworld.entities, worldEntities, "park keeps the same entity table")

  -- Once our send-out is on the map, PikachuFollower.current() may return the
  -- wild/enemy sprite as the "lead". That must not hide the live opponent.
  local prevPF = package.loaded["src.world.PikachuFollower"]
  package.loaded["src.world.PikachuFollower"] = {
    current = function()
      return battler
    end,
  }
  Lifecycle.parkOverworldFollowers(session, overworld)
  local foeListed = false
  for i = 1, #overworld.entities do
    if overworld.entities[i] == battler then
      foeListed = true
    end
  end
  truthy(foeListed, "lead-follower lookup does not park the field foe")
  truthy(not battler.hidden, "field foe stays visible after player send-out")
  package.loaded["src.world.PikachuFollower"] = prevPF
  Lifecycle.restoreOverworldFollowers(session, overworld)
  eq(overworld.entities[2], follower, "follower returns at its original index")
  eq(follower.hidden, false, "restored follower is visible")
  eq(follower._arFieldParked, nil, "park marker is cleared")
end

function tests.player_sendout_leaves_foe_on_field()
  local grid, plan = sampleGrid()
  local overworld = { entities = {} }
  local battle = {
    game = { overworld = overworld },
    player = { mon = { species = "MY_MON" } },
    enemy = { mon = { species = "WILD_MON" } },
    _arFieldRevealPlayer = true,
  }
  local session = {
    state = Lifecycle.STATE.Live,
    live = true,
    plan = plan,
    grid = grid,
    awaitPlayerMon = true,
    _battle = battle,
  }
  local deps = {
    Cast = Cast,
    Sprites = Sprites,
    Grid = Grid,
    Projectiles = Projectiles,
    Cues = {
      pumpCurrent = function() end,
      tickReturns = function() end,
      apply = function() end,
    },
    Anims = { cache = function() end },
  }
  session._deps = deps
  local foe = Cast.stageEnemy(session, battle, nil, Sprites, Grid)
  session.enemyMon = foe
  Lifecycle._testBind(battle, session)
  Lifecycle.syncMons(battle, nil, deps, nil)
  truthy(session.playerMon, "player send-out stages")
  eq(session.awaitPlayerMon, false, "player reveal completes")
  eq(session.enemyMon, foe, "foe entity is not replaced")
  eq(foe.anim, "sendout", "foe is not recalled on player spawn")
  truthy(not foe.hidden and not foe._removed, "foe stays visible")
  local listed = false
  for i = 1, #overworld.entities do
    if overworld.entities[i] == foe then
      listed = true
    end
  end
  truthy(listed, "foe stays on the overworld list")
  Lifecycle._testUnbind(battle)
end

function tests.player_callin_does_not_recall_foe()
  local grid, plan = sampleGrid()
  local overworld = { entities = {} }
  local enemyBattler = { mon = { species = "GEODUDE" } }
  local battle = {
    game = { overworld = overworld },
    player = { mon = { species = "PIKACHU" } },
    enemy = enemyBattler,
    sendingOut = true,
    kind = "trainer",
  }
  local session = {
    state = Lifecycle.STATE.Live,
    live = true,
    plan = plan,
    grid = grid,
    awaitPlayerMon = false,
    foe = { px = 90, py = 32 },
    _battle = battle,
  }
  local deps = {
    Cast = Cast,
    Sprites = Sprites,
    Grid = Grid,
    Projectiles = Projectiles,
    Cues = {
      pumpCurrent = function() end,
      tickReturns = function() end,
      apply = function() end,
    },
    Anims = { cache = function() end },
  }
  session._deps = deps
  local foe = Cast.stageEnemy(session, battle, nil, Sprites, Grid)
  foe._spriteSpecies = "GEODUDE"
  -- Engine often reports a dex id after send-out; that is not a switch.
  battle.enemy = { mon = { species = 74 } }
  local spawned = Cast.stagePlayer(session, battle, nil, Sprites, Grid)
  Lifecycle._testBind(battle, session)
  Projectiles.clear(session)
  Lifecycle.syncMons(battle, nil, deps, nil)
  eq(session.enemyMon, foe, "foe is not replaced during player call-in")
  eq(foe.anim, "sendout", "foe is not shrunk by the recall laser")
  truthy(not foe.hidden and not foe._removed, "foe stays visible")
  local beams = 0
  for i = 1, #(session.projectiles or {}) do
    if session.projectiles[i].style == "recall" then
      beams = beams + 1
    end
  end
  eq(beams, 0, "player call-in does not fire a recall laser")
  truthy(spawned and spawned.anim == "sendout", "player uses send-out grow")
  eq(Cues.apply(session, "enemy", "recall", Grid, nil, battle), true)
  eq(foe.anim, "sendout", "recall cue is ignored while the player is calling in")
  Lifecycle._testUnbind(battle)
end

function tests.status_auras_follow_field_mons()
  local calls = { sparks = 0, ice = 0, bubbles = 0, zs = 0, swirl = 0, seed = 0, flame = 0, cover = 0 }
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      setLineWidth = function() end,
      line = function() calls.sparks = calls.sparks + 1 end,
      rectangle = function() calls.zs = calls.zs + 1; calls.seed = calls.seed + 1 end,
      arc = function() calls.swirl = calls.swirl + 1 end,
      ellipse = function(mode)
        if mode == "fill" then
          calls.ice = calls.ice + 1
          calls.seed = calls.seed + 1
          calls.cover = calls.cover + 1
        else
          calls.bubbles = calls.bubbles + 1
          calls.seed = calls.seed + 1
        end
      end,
      circle = function(mode)
        if mode == "fill" then
          calls.ice = calls.ice + 1
        else
          calls.bubbles = calls.bubbles + 1
        end
      end,
      polygon = function()
        calls.ice = calls.ice + 1
        calls.flame = calls.flame + 1
        calls.cover = calls.cover + 1
      end,
    },
    timer = { getTime = function() return 1.25 end },
  }
  local session = {
    live = true,
    playerMon = { px = 16, py = 32 },
    enemyMon = { px = 80, py = 32 },
  }
  local battle = {
    player = { mon = { status = "PAR" } },
    enemy = { mon = { status = "FRZ" } },
  }
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  truthy(calls.sparks > 0, "paralysis paints spark ticks")
  truthy(calls.ice > 0, "freeze paints ice shell")

  calls.sparks, calls.ice, calls.bubbles, calls.zs, calls.swirl = 0, 0, 0, 0, 0
  battle.player.mon.status = "PSN"
  battle.enemy.mon.status = "TOX"
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  truthy(calls.bubbles > 0, "poison paints rising bubbles")

  calls.sparks, calls.ice, calls.bubbles, calls.zs, calls.swirl = 0, 0, 0, 0, 0
  battle.player.mon.status = "SLP"
  battle.enemy.mon.status = nil
  battle.enemy.confusedTurns = 3
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  truthy(calls.zs > 0, "sleep paints rising Zs")
  truthy(calls.swirl > 0, "confusion paints circling birds")

  calls.sparks, calls.ice, calls.bubbles, calls.zs, calls.swirl, calls.seed, calls.flame =
      0, 0, 0, 0, 0, 0, 0
  battle.player.mon.status = "BRN"
  battle.enemy.confusedTurns = nil
  battle.enemy.leechSeeded = nil
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  truthy(calls.flame > 0, "burn paints rising ember tongues")

  calls.sparks, calls.ice, calls.bubbles, calls.zs, calls.swirl, calls.seed, calls.flame =
      0, 0, 0, 0, 0, 0, 0
  battle.player.mon.status = nil
  battle.enemy.confusedTurns = nil
  battle.enemy.leechSeeded = true
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  truthy(calls.seed > 0, "leech seed paints pulsing grass on the seeded mon")

  calls.sparks, calls.ice, calls.bubbles, calls.zs, calls.swirl, calls.seed, calls.flame, calls.cover =
      0, 0, 0, 0, 0, 0, 0, 0
  battle.player.mon.status = nil
  battle.enemy.confusedTurns = nil
  battle.enemy.leechSeeded = nil
  battle.player._arFieldCover = true
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  truthy(calls.cover > 0, "cover paints a crouch shade when no prop is nearby")

  battle.player.mon.status = nil
  battle.player._arFieldCover = nil
  battle.enemy.confusedTurns = nil
  battle.enemy.leechSeeded = nil
  calls.sparks, calls.ice, calls.bubbles, calls.zs, calls.swirl, calls.seed, calls.flame, calls.cover =
      0, 0, 0, 0, 0, 0, 0, 0
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  eq(calls.sparks + calls.ice + calls.bubbles + calls.zs + calls.swirl
      + calls.seed + calls.flame + calls.cover, 0,
    "healthy mons have no status aura")
  love = prevLove
end

function tests.cover_aura_follows_tile_and_scene()
  local ent = { padU = 1, padV = 2, cellX = 10, cellY = 12 }
  local session = {
    coverKind = "CRATE",
    coverScene = "gym",
    grid = { water = {} },
  }
  eq(Projectiles.coverFlavor(session, ent), "crate", "gym kit is wooden crates")

  session.coverKind, session.coverScene = "ROCK", "cave"
  eq(Projectiles.coverFlavor(session, ent), "rock", "cave kit is stone")

  session.coverKind, session.coverScene = "TREE", "forest"
  eq(Projectiles.coverFlavor(session, ent), "tree", "forest kit is leaves")

  session.coverKind, session.coverScene = "TREE", "route"
  eq(Projectiles.coverFlavor(session, ent), "tree", "route TREE kind stays leafy")

  session.coverKind, session.coverScene = "ROCK", "water"
  eq(Projectiles.coverFlavor(session, ent), "water", "ocean / seafoam kit is foam")

  session.coverKind, session.coverScene = "ROCK", "grave"
  eq(Projectiles.coverFlavor(session, ent), "grave", "tower kit is weeds")

  session.coverKind, session.coverScene = "CRATE", "gym"
  session.grid.water[Coords.key(1, 2)] = true
  eq(Projectiles.coverFlavor(session, ent), "water", "water pad tile overrides gym crates")
  session.grid.water[Coords.key(1, 2)] = nil

  local battle = {
    game = {
      overworld = {
        map = {
          isWaterCell = function() return false end,
          isGrassCell = function(_, x, y) return x == 10 and y == 12 end,
        },
      },
    },
  }
  eq(Projectiles.coverFlavor(session, ent, battle), "grass",
    "grass underfoot overrides gym crates")

  session.coverKind, session.coverScene = "TREE", "forest"
  eq(Projectiles.coverFlavor(session, ent, battle), "grass",
    "grass tile overrides forest leaves")

  session.covers = { { px = 16, py = 32, kind = "ROCK" } }
  ent.px, ent.py = 18, 34
  eq(Projectiles.coverFlavor(session, ent, battle), "rock",
    "nearby rock prop wins over grass tile")
end

function tests.cover_hold_grows_nearest_prop()
  local session = {
    live = true,
    playerMon = { px = 16, py = 32, basePx = 16, basePy = 32 },
    enemyMon = { px = 80, py = 32, basePx = 80, basePy = 32 },
    covers = {
      { px = 20, py = 36, kind = "ROCK", coverGrow = 0 },
      { px = 90, py = 8, kind = "TREE", coverGrow = 0 },
    },
  }
  local battle = {
    player = { _arFieldCover = true, mon = {} },
    enemy = { mon = {} },
  }
  Projectiles.syncCoverHold(session, battle, 1)
  truthy((session.covers[1].coverGrow or 0) > 0.5, "nearest rock thickens")
  eq(session.covers[2].coverGrow, 0, "far tree stays idle")
  truthy((session.playerMon.coverBlend or 0) > 0.5, "covered mon tucks")
  eq(session.playerMon._coverHeld, true, "cover pins the mon")
  eq(session.playerMon.coverTx, 20, "tuck aims at the rock")
  session.playerMon.wanderTx, session.playerMon.wanderTy = 40, 40
  Projectiles.syncCoverHold(session, battle, 1)
  eq(session.playerMon.wanderTx, nil, "cover cancels idle wander")
  Projectiles.syncCoverHold(session, { player = { mon = {} }, enemy = { mon = {} } }, 1)
  eq(session.covers[1].coverGrow, 0, "prop shrinks when cover drops")
  eq(session.playerMon.coverBlend, 0, "tuck eases out")
  eq(session.playerMon._coverHeld, false, "pin releases")
end

function tests.cover_hold_skips_sticker_when_prop_nearby()
  local calls = { cover = 0 }
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      setLineWidth = function() end,
      line = function() end,
      rectangle = function() end,
      arc = function() end,
      ellipse = function(mode)
        if mode == "fill" then
          calls.cover = calls.cover + 1
        end
      end,
      circle = function() end,
      polygon = function()
        calls.cover = calls.cover + 1
      end,
    },
    timer = { getTime = function() return 1.25 end },
  }
  local session = {
    live = true,
    playerMon = { px = 16, py = 32 },
    enemyMon = { px = 80, py = 32 },
    covers = { { px = 18, py = 34, kind = "CRATE" } },
  }
  local battle = {
    player = { _arFieldCover = true, mon = {} },
    enemy = { mon = {} },
  }
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  eq(calls.cover, 0, "no sprite-glued crate when a pad prop is the cover")
  session.covers = nil
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  truthy(calls.cover > 0, "crouch shade paints when nothing is nearby to hide behind")
  love = prevLove
end

function tests.cover_surface_follows_tile()
  local ent = { padU = 1, padV = 1, cellX = 4, cellY = 5, px = 16, py = 32 }
  local session = { grid = { water = {}, sizeU = 6, sizeV = 4 }, coverScene = "gym" }
  eq(Projectiles.coverSurface(session, ent), "open", "bare indoor tile is open")

  session.grid.water[Coords.key(1, 1)] = true
  eq(Projectiles.coverSurface(session, ent), "water", "water pad is a dive")
  session.grid.water[Coords.key(1, 1)] = nil

  local battle = {
    game = {
      overworld = {
        map = {
          isWaterCell = function() return false end,
          isGrassCell = function(_, x, y) return x == 4 and y == 5 end,
        },
      },
    },
  }
  eq(Projectiles.coverSurface(session, ent, battle), "grass", "grass tile underfoot")

  eq(Projectiles.coverSurface({ coverScene = "cave", grid = {} }, { padU = 0, padV = 0 }),
    "cave", "cave kit clusters stones")
end

function tests.seek_wall_cover_prefers_corner()
  local plan = Layout.plan(0, 0, 6, 0)
  local pad = Coords.layoutPad({ minX = 0, maxX = 6, minY = 0, maxY = 4 }, 1, 0)
  local walkable = {}
  for u = 0, pad.sizeU - 1 do
    for v = 0, pad.sizeV - 1 do
      walkable[Coords.key(u, v)] = true
    end
  end
  for v = 0, pad.sizeV - 1 do
    walkable[Coords.key(0, v)] = false
  end
  for u = 0, pad.sizeU - 1 do
    walkable[Coords.key(u, 0)] = false
  end
  local grid = Grid.build({ pad = pad, walkable = walkable }, plan)
  local player = { id = "p", padU = 2, padV = 2 }
  local enemy = { id = "e", padU = 5, padV = 2 }
  truthy(Grid.setPad(grid, player, 2, 2), "place player")
  truthy(Grid.setPad(grid, enemy, 5, 2), "place foe")
  truthy(Grid.seekWallCover(grid, player, enemy), "cover steps to a wall")
  local hug = Grid.wallHug(grid, player)
  truthy(hug, "ended on a wall-hugging cell")
  truthy(hug.corner, "prefers the inside corner")
end

function tests.cover_hold_paints_grass_underfoot()
  local calls = { grass = 0 }
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      setLineWidth = function() end,
      line = function() end,
      rectangle = function() end,
      arc = function() end,
      ellipse = function() end,
      circle = function() end,
      polygon = function() calls.grass = calls.grass + 1 end,
    },
    timer = { getTime = function() return 1.0 end },
  }
  local session = {
    live = true,
    playerMon = { px = 16, py = 32, padU = 1, padV = 1, cellX = 4, cellY = 5 },
    enemyMon = { px = 80, py = 32 },
    covers = { { px = 18, py = 34, kind = "CRATE" } },
  }
  local battle = {
    player = { _arFieldCover = true, mon = {} },
    enemy = { mon = {} },
    game = {
      overworld = {
        map = {
          isWaterCell = function() return false end,
          isGrassCell = function(_, x, y) return x == 4 and y == 5 end,
        },
      },
    },
  }
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  truthy(calls.grass > 0, "grass blades paint under a crouch even next to a crate")
  love = prevLove
end

function tests.cover_hold_paints_cave_rocks()
  local calls = { rocks = 0 }
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      setLineWidth = function() end,
      line = function() end,
      rectangle = function() end,
      arc = function() end,
      ellipse = function() end,
      circle = function() end,
      polygon = function() calls.rocks = calls.rocks + 1 end,
    },
    timer = { getTime = function() return 1.0 end },
  }
  local session = {
    live = true,
    coverScene = "cave",
    playerMon = { px = 16, py = 32, padU = 1, padV = 1 },
    enemyMon = { px = 80, py = 32 },
  }
  local battle = { player = { _arFieldCover = true, mon = {} }, enemy = { mon = {} } }
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  truthy(calls.rocks > 0, "cave cover clusters little rocks around the mon")
  love = prevLove
end

function tests.cover_cue_uses_wall_when_no_prop()
  local plan = Layout.plan(0, 0, 6, 0)
  local pad = Coords.layoutPad({ minX = 0, maxX = 6, minY = 0, maxY = 4 }, 1, 0)
  local walkable = {}
  for u = 0, pad.sizeU - 1 do
    for v = 0, pad.sizeV - 1 do
      walkable[Coords.key(u, v)] = true
    end
  end
  for v = 0, pad.sizeV - 1 do
    walkable[Coords.key(0, v)] = false
  end
  local grid = Grid.build({ pad = pad, walkable = walkable }, plan)
  local player = {
    id = "p", padU = 2, padV = 2,
    play = function(self, kind) self.lastAnim = kind end,
  }
  local enemy = { id = "e", padU = 5, padV = 2 }
  Grid.setPad(grid, player, 2, 2)
  Grid.setPad(grid, enemy, 5, 2)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    coverSlots = {},
  }
  truthy(Cues.apply(session, "player", "cover", Grid), "cover cue fires")
  eq(player.lastAnim, "cover", "wall hide plays cover, not a dodge")
  eq(player.padU, 1, "steps beside the wall")
end

function tests.field_overlay_draws_projectiles()
  local drawn = 0
  local projectile = {
    _removed = false,
    draw = function(_, _camX, _camY, mapFn)
      drawn = drawn + 1
      if mapFn then
        local x, y = mapFn(10, 20)
        truthy(type(x) == "number" and type(y) == "number", "ui map returns numbers")
      end
    end,
  }
  local battle = {
    game = {
      overworld = { camera = { x = 0, y = 0 } },
      renderer = {
        uiSize = function() return 160, 144 end,
        worldViewSize = function() return 320, 288 end,
        fitScale = function() return 4 end,
      },
    },
  }
  local session = {
    state = Lifecycle.STATE.Live,
    live = true,
    projectiles = { projectile },
    _battle = battle,
  }
  Projectiles.drawUi(session, battle)
  Projectiles.drawUi(session, battle)
  eq(drawn, 2, "ui overlay paints projectiles each drawUi call")
end

function tests.world_view_maps_to_ui_canvas()
  local ren = {
    uiSize = function() return 160, 144 end,
    worldViewSize = function() return 320, 288 end,
    fitScale = function() return 4 end,
  }
  -- Same pixel scale: world center → UI center.
  local ux, uy = Coords.worldViewToUi(160, 144, ren)
  eq(ux, 80, "wide world center maps to UI center x")
  eq(uy, 72, "wide world center maps to UI center y")
  -- A point 40px right of world center lands 40px right of UI center.
  ux = select(1, Coords.worldViewToUi(200, 144, ren))
  eq(ux, 120, "world offset preserves screen delta when scales match")
end

function tests.field_sprite_style_aliases()
  eq(Sprites.normalizeSpriteStyle("GSC"), "followers", "GSC → followers")
  eq(Sprites.normalizeSpriteStyle("HGSS"), "pokemmo", "HGSS → pokemmo")
  eq(Sprites.normalizeSpriteStyle("POKEDEX"), "pokedex", "POKEDEX")
  eq(Sprites.normalizeSpriteStyle("followers"), "followers", "wilds followers")
end

function tests.field_sprite_style_auto_without_wilds()
  local mod = {
    options = {
      get = function(_, key)
        if key == "field_sprites" then
          return "AUTO"
        end
      end,
    },
  }
  eq(Sprites.fieldSpriteStyle(mod), "followers", "AUTO defaults to GSC followers")
end

function tests.field_sprite_style_auto_matches_wilds()
  local mod = {
    options = {
      get = function(_, key)
        if key == "field_sprites" then
          return "AUTO"
        end
      end,
    },
    find = function(_, id)
      if id == "overworld_wild_spawns" then
        return {
          exports = {
            spriteStyle = function()
              return "pokemmo"
            end,
          },
        }
      end
    end,
  }
  eq(Sprites.fieldSpriteStyle(mod), "pokemmo", "AUTO follows Wilds Sprite Style")
end

function tests.field_sprite_style_explicit_hgss()
  local mod = {
    options = {
      get = function(_, key)
        if key == "field_sprites" then
          return "HGSS"
        end
      end,
    },
    find = function()
      return {
        exports = {
          spriteStyle = function()
            return "followers"
          end,
        },
      }
    end,
  }
  eq(Sprites.fieldSpriteStyle(mod), "pokemmo", "explicit HGSS wins over Wilds")
end

function tests.resolve_sheet_uses_pokepc_export()
  local mod = {
    options = {
      get = function()
        return "GSC"
      end,
    },
    find = function(_, id)
      if id == "PokePCFollowers_VoxelMerge" then
        return {
          exports = {
            assetPath = function(species)
              return "/tmp/fake_follower_" .. tostring(species) .. ".png"
            end,
          },
        }
      end
    end,
  }
  local sheet = Sprites.resolveSheet(mod, nil, "CHARMANDER")
  truthy(sheet and sheet.image, "PokePC export supplies a sheet")
  eq(sheet.image, "/tmp/fake_follower_CHARMANDER.png", "PokePC path")
  eq(sheet.frames, 6, "GSC sheets walk")
end

function tests.resolve_sheet_prefers_wilds_export()
  local mod = {
    options = {
      get = function()
        return "HGSS"
      end,
    },
    find = function(_, id)
      if id == "overworld_wild_spawns" then
        return {
          exports = {
            resolveFollowerSprite = function(opts)
              return {
                image = "/wilds/" .. tostring(opts.style) .. "/" .. tostring(opts.species) .. ".png",
                frames = 6,
                walker = true,
                providerId = "pokemmo",
              }
            end,
          },
        }
      end
    end,
  }
  local sheet = Sprites.resolveSheet(mod, nil, "PIKACHU")
  eq(sheet.image, "/wilds/pokemmo/PIKACHU.png", "Wilds resolver used for HGSS")
  eq(sheet.providerId, "pokemmo", "provider id kept")
end

local count = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then
    io.stderr:write(("FAIL %s: %s\n"):format(name, tostring(err)))
    os.exit(1)
  end
  count = count + 1
  io.stdout:write(("ok %s\n"):format(name))
end

io.stdout:write(("%d field battle tests passed\n"):format(count))
