local script = (arg and arg[0]) or "field/tests/run_grid_tests.lua"
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

local Coords = load("pad/coords.lua")
package.loaded.coords = Coords
local Themes = load("stage/themes.lua")
package.loaded.themes = Themes
local FxCatalog = load("fx/fx_catalog.lua")
package.loaded.fx_catalog = FxCatalog
local Grid = load("pad/grid.lua")
local Layout = load("pad/layout.lua")
local Arena = load("stage/arena.lua")
local Survey = load("pad/survey.lua")
local Cues = load("fx/cues.lua")
Cues.attach(load)
package.loaded.field_type = load("chrome/type.lua")
local Callouts = load("chrome/callouts.lua")
local Projectiles = load("fx/projectiles.lua")
local Audio = load("fx/audio.lua")
local UI = load("chrome/ui.lua")
local Lifecycle = load("session/lifecycle.lua")
UI.sessionOf = function(battle)
  return Lifecycle.get(battle)
end
local Compat = load("session/compat.lua")
local Sprites = load("fx/sprites.lua")
local Cast = load("pad/cast.lua")
local Spectators = load("session/spectators.lua")
local Wildlife = load("session/wildlife.lua")
local FieldFactory = load("init.lua")
local FieldBattle = FieldFactory({ load = function() return {} end })
local Hooks = load("chrome/hooks.lua")
load("chrome/hooks_draw.lua")(Hooks)
load("chrome/hooks_input.lua")(Hooks)
load("chrome/hooks_events.lua")(Hooks)
UI.foeIsDown = Hooks.foeIsDown

do
  local ids = {
    "cave", "city", "forest", "grave", "gym", "indoor", "mountain", "route", "water",
  }
  for i = 1, #ids do
    local ok, layout = pcall(load, "stage/arenas/" .. ids[i] .. ".lua")
    if ok and type(layout) == "table" then
      Themes.registerLayout(layout.id or ids[i], layout)
    end
  end
end

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
  truthy(not Hooks.fieldPausePressed(press("b"), {
    phase = "moveSelect",
    _arAwaitCallout = true,
  }), "delayed callout cannot pause back to FIGHT")
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
  truthy(not Hooks.foeIsDown({
    enemy = { shownHP = 0, mon = { hp = 8 } },
  }), "empty bar on a living foe is send-out, not a KO")
  local faintedMenu = {
    phase = "menu",
    enemy = { mon = { hp = 0 } },
    current = { text = "Enemy RATTATA\nfainted!" },
  }
  truthy(Hooks.holdFightMenu(faintedMenu), "FIGHT stays closed over a fainted foe")
  local state = UI.layoutState(faintedMenu)
  truthy(not state.showCommand, "command HUD does not cover faint text")
  truthy(not state.showMoves, "move HUD does not cover faint text")
  local intro = {
    phase = "menu",
    current = { text = "A wild RATTATA appeared!" },
    player = { mon = { hp = 20 } },
    enemy = { shownHP = 0, mon = { hp = 12 } },
  }
  truthy(not Hooks.holdFightMenu(intro), "opening dialogue does not lock FIGHT")
  truthy(UI.layoutState(intro).showCommand, "opening dialogue still reaches the command menu")
  local sentOut = {
    phase = "messages",
    enemySendingOut = true,
    current = { text = "MISTY sent\nout NINETALES!" },
    enemy = { mon = { hp = 0 } },
  }
  truthy(not Hooks.holdFightMenu(sentOut), "trainer send-out is not a FIGHT hold")
  local staleFlag = {
    phase = "menu",
    current = { text = "MISTY sent\nout NINETALES!" },
    enemy = { mon = { hp = 0 } },
  }
  truthy(not Hooks.holdFightMenu(staleFlag),
    "sent-out line is not a FIGHT hold after enemySendingOut drops")
  truthy(not Hooks.faintScriptLive(staleFlag),
    "sent-out leftover current is not a faint script")
  truthy(UI.layoutState(staleFlag).showCommand,
    "sent-out beat still reaches the command menu")
  local goLine = {
    phase = "menu",
    current = { text = "Go! SQUIRTLE!" },
    sendingOut = true,
    player = { mon = { hp = 20 } },
    enemy = { mon = { hp = 0 } },
  }
  truthy(not Hooks.holdFightMenu(goLine), "Go! send-out is not a FIGHT hold")
  truthy(Hooks.faintScriptLive(faintedMenu), "faint line is a live faint script")
  local playerDown = {
    phase = "menu",
    player = { mon = { hp = 0 } },
    enemy = { mon = { hp = 12 } },
  }
  truthy(not Hooks.holdFightMenu(playerDown), "player faint still reaches PKMN")
  truthy(UI.layoutState(playerDown).showCommand, "player faint keeps the command menu")
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
  mod.options.get = function() return "STADIUM" end
  truthy(FieldBattle.shouldUse(mod, { kind = "wild" }), "legacy STADIUM keeps FIELD")
  mod.options.get = function() return nil end
  truthy(FieldBattle.shouldUse(mod, { kind = "wild" }), "unset stage defaults to FIELD")
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
  -- Opening (trainers ± back of spaced mons) + EXTRA_U/HALF_V roam room.
  eq(envelope.pad.sizeU, 9, "free-tile envelope width")
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
  eq(grid.sizeU, 9, "grid adopts surveyed width")
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
  truthy(Sprites.isFlyingType({ curTypes = { "FIRE", "FLYING" } }), "Charizard flies")
  truthy(Sprites.canTraverseWater({ curTypes = { "FIRE", "FLYING" } }),
    "Flying may hover over water")
  truthy(not Sprites.canTraverseWater({ curTypes = { "FIRE" } }),
    "Fire stays off water")
end

function tests.flying_mons_may_hover_over_water()
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
  local flyer = {
    id = "charizard", padU = landU, padV = landV, canFly = true, canSwim = false,
  }
  Grid.occupy(grid, flyer.id, landU, landV)
  truthy(Grid.step(grid, flyer, waterU - landU, waterV - landV),
    "Flying mon can hover onto water")
  eq(flyer.padU, waterU, "flyer occupies water pad u")
end

function tests.land_mon_shoved_into_water_takes_a_chip()
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
  local fire = {
    id = "charmander", padU = landU, padV = landV, canSwim = false, canFly = false,
    hp = 40,
    play = function(self, kind) self.lastAnim = kind end,
  }
  local foe = {
    id = "foe", padU = landU - 1, padV = landV,
  }
  Grid.occupy(grid, fire.id, landU, landV)
  Grid.occupy(grid, foe.id, foe.padU, foe.padV)
  local moved = Grid.knockbackTiles(grid, fire, foe, 1)
  eq(moved, 1, "shove moves the land mon")
  eq(fire.padU, waterU, "land mon is forced onto water")
  eq(fire.padV, waterV, "land mon water v")
  truthy(fire._waterHazard, "shove marks a water hazard")
  local session = {
    live = true,
    grid = grid,
    playerMon = fire,
    enemyMon = foe,
    _deps = { Projectiles = { lightHit = function() end }, Grid = Grid },
  }
  truthy(Cues.applyWaterHazard(session, "player", Grid, nil), "hazard resolves")
  eq(fire.lastAnim, "tumble", "splash plays tumble")
  eq(fire.hp, 40 - Cues.WATER_HAZARD_CHIP, "water chips HP")
  truthy(not Grid.isWater(grid, fire.padU, fire.padV),
    "land mon scrambles back to dry land")
end

function tests.mons_on_water_use_the_swim_sheet()
  local land = { sprite = { id = "land" }, lift = 8 }
  local swim = { sprite = { id = "swim" }, lift = 8 }
  local grid = { water = {}, originWx = 0, originWy = 0, uAxis = { x = 1, y = 0 }, vAxis = { x = 0, y = 1 } }
  local fire = {
    padU = 2, padV = 0,
    canSwim = false,
    _grid = grid,
    sprite = land.sprite,
    _fieldSurface = "land",
    _surfaceVisuals = { land = land, water = swim },
  }
  grid.water[Coords.key(2, 0)] = true
  truthy(Sprites.feetOnWater(fire), "occupancy on water counts")
  Sprites.syncSurface(fire)
  eq(fire._fieldSurface, "water", "Fire-type on water still swims")
  eq(fire.sprite.id, "swim", "swim sheet is applied")

  fire.padU, fire.padV = 0, 0
  fire._fieldSurface = "land"
  fire.sprite = land.sprite
  fire.basePx, fire.basePy = 2 * 16 + 4, 2
  grid.water[Coords.key(2, 0)] = true
  truthy(Sprites.feetOnWater(fire), "pixels over water count mid-step")
  Sprites.syncSurface(fire)
  eq(fire._fieldSurface, "water", "lerp across a pond uses the swim sheet")

  fire.basePx, fire.basePy = 0, 0
  grid.water[Coords.key(2, 0)] = nil
  Sprites.syncSurface(fire)
  eq(fire._fieldSurface, "land", "back on land restores the land sheet")
end

function tests.dodge_styles_follow_type_and_cycle()
  eq(Sprites.pickDodgeStyle({
    _battleBattler = { curTypes = { "GHOST" } },
  }), "phase", "ghost phases through")
  eq(Sprites.pickDodgeStyle({
    _battleBattler = { curTypes = { "ELECTRIC" } },
  }), "static", "electric static-dashes")
  eq(Sprites.pickDodgeStyle({
    _battleBattler = { curTypes = { "WATER", "FLYING" } },
  }), "lift", "flying beats water on dual-types")
  eq(Sprites.pickDodgeStyle({
    _battleBattler = { curTypes = { "WATER" } },
  }), "splash", "water splashes")
  eq(Sprites.pickDodgeStyle({
    _battleBattler = { curTypes = { "BUG" } },
  }), "burrow", "bugs burrow")
  eq(Sprites.pickDodgeStyle({
    _battleBattler = { curTypes = { "GRASS" } },
  }), "burrow", "grass burrows")
  eq(Sprites.pickDodgeStyle({
    _closeGapStats = { speed = 120 },
  }), "blur", "fast mons blur-step")
  eq(Sprites.pickDodgeStyle({
    _spriteSpecies = "JIGGLYPUFF",
  }), "hop", "round bodies hop")
  local generic = {}
  eq(Sprites.pickDodgeStyle(generic), "sidehop", "first generic is a side-hop")
  eq(Sprites.pickDodgeStyle(generic), "duck", "second generic ducks")
  eq(Sprites.pickDodgeStyle(generic), "lean", "third generic leans")
  eq(Sprites.pickDodgeStyle(generic), "hop", "fourth generic hops")
  eq(Sprites.pickDodgeStyle(generic), "sidehop", "generic cycle wraps")
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
  truthy(state.showDialogue, "message phase keeps the game dialogue box")
  battle._arFieldChipDialogue = true
  state = UI.layoutState(battle)
  truthy(not state.showDialogue, "chip-owned REACT toast does not also fill the game box")
  battle._arFieldChipDialogue = nil
  battle.game = {
    stack = {
      top = function()
        return { isOpaque = false }
      end,
    },
  }
  state = UI.layoutState(battle)
  truthy(not state.showDialogue, "stacked YES-NO / about-to-use owns the box")
  battle.game = nil
  battle.current = { text = "BROCK: Onix, now!" }
  state = UI.layoutState(battle)
  truthy(not state.showDialogue, "trainer banter is not the game box")
  battle.current = { text = "BROCK is\nabout to use" }
  state = UI.layoutState(battle)
  truthy(state.showDialogue, "about-to-use is game dialogue")
end

function tests.status_chip_abbreviations()
  eq(UI.chipAbbrev("Braced right!\nTook it well!"), "BRACE", "brace success")
  eq(UI.chipAbbrev("Braced the\nwrong way!"), nil, "failed brace is not a chip")
  eq(UI.chipAbbrev("Couldn't dodge!\nCaught off-balance!"), nil, "failed dodge is not a chip")
  eq(UI.chipAbbrev("Onix!\nBrace yourself!"), nil, "react order is not a chip")
  eq(UI.chipAbbrev("PIKACHU!\nDodge it!"), nil, "player order is not a chip")
  eq(UI.chipAbbrev("BROCK:\nOnix, dodge!"), nil, "NPC dodge order is not a chip")
  eq(UI.chipAbbrev("COUNTER!"), nil, "counter toast is not inferred")
  local counterBattle = { frame = 4 }
  UI.armStatusChip(counterBattle, "player", "COUNTER")
  eq(counterBattle._arStatusChips.player.text, "COUNTER", "successful counter arms COUNTER")
  eq(UI.chipAbbrev("But SQUIRTLE\ndodged aside!"), "DODGE",
    "success flavor still maps, but is not auto-armed")
  eq(UI.chipAbbrev("Entrenched!\n(3 turns)"), "HOLD", "entrench")
  eq(UI.chipAbbrev("It's super effective!"), nil, "effectiveness stays a toast")
  eq(UI.chipAbbrev("SQUIRTLE used TACKLE!"), nil, "move used stays a toast")
  eq(UI.chipAbbrev("SQUIRTLE's ATTACK fell!"), nil, "stat drop stays a toast")
  eq(UI.chipAbbrev("A wild PIDGEY appeared!"), nil, "intro stays a toast")
  eq(UI.chipSide({ current = { arFieldCue = { side = "enemy" } } }, "x"),
    "enemy", "cue side wins")
  eq(UI.chipAbbrev("TACKLE!"), nil, "attack toast is not a REACT chip")
  local overlap = {
    current = {
      text = "SURF!",
      arFieldCue = { kind = "attack", side = "player" },
      arOverlapReact = {
        { kind = "brace", side = "enemy", text = "Onix!\nBrace yourself!" },
      },
    },
  }
  UI.syncStatusChips(overlap)
  eq(overlap._arStatusChips, nil, "foe order overlap does not arm a chip")
  local battle = { frame = 12 }
  battle.current = {
    text = "But SQUIRTLE\ndodged aside!",
    arFieldCue = { kind = "dodge", side = "enemy" },
  }
  UI.syncStatusChips(battle)
  eq(battle._arStatusChips, nil, "engine miss dodge is not a chip")
  UI.armStatusChip(battle, "player", "DODGE")
  eq(battle._arStatusChips.player.text, "DODGE", "successful REACT! pick arms the chip")
  eq(battle._arStatusChips.player.untilFrame, 12 + UI.CHIP_HOLD, "chip holds a beat")
  UI.armStatusChip(battle, "enemy", "MISS")
  eq(battle._arStatusChips.enemy.text, "MISS", "accuracy miss arms a MISS chip")
end

function tests.mood_portrait_sits_beside_the_sprite()
  eq(UI.FACE_SIZE, 20, "emotion icons are compact")
  eq(UI.FACE_BORDER, 1, "emotion icons have a 1px black frame")
  local pad = UI.HUD_PAD
  local px, py = UI.faceAnchor("player", 40, 80, 28, 0, 160)
  eq(px, pad, "player face hugs the left edge")
  eq(py, pad, "player face sits at the top")
  local ex, ey = UI.faceAnchor("enemy", 120, 80, 28, 0, 160)
  eq(ex, 160 - pad - 28, "foe face hugs the right edge")
  eq(ey, pad, "foe face sits at the top")
  local hx, hy = UI.hpAboveFace(px, py, 28)
  eq(hx, px + 14, "legacy helper still centers HP on the face")
  eq(hy, py - UI.HP_CHIP_H - (UI.HP_FACE_GAP or 0), "legacy helper sits HP above the portrait")
  local mx, my = UI.hpAboveMon(48, 90)
  eq(mx, 48, "field HP is centered on the sprite")
  eq(my, 90 - UI.HP_CHIP_H, "field HP sits just above the sprite")
  local chipX, chipY = UI.moodBesideFace(px, py, 28, "player", 20)
  truthy(chipX > px + 28, "player mood sits inward of the left face")
  chipX = select(1, UI.moodBesideFace(ex, ey, 28, "enemy", 20))
  truthy(chipX < ex, "foe mood sits inward of the right face")
  local stack = 12
  local _, stackedY = UI.faceAnchor("player", 0, 0, 28, stack, 160)
  eq(stackedY, pad + stack, "chips and bars push the face down from the pad")
  eq(UI.hudAnchor("player"), "window-left", "player stack uses the wide left margin")
  eq(UI.hudAnchor("enemy"), "topright", "foe stack uses the wide right margin")
  local bx, by, bw, bh = UI.hudStackBox(px, py, 28, 0)
  truthy(bx <= px, "stack box includes the face left")
  truthy(bx + bw >= px + 28, "stack box includes the face right")
  truthy(by <= py, "stack box includes the HP row")
  truthy(by + bh >= py + 28, "stack box includes the face bottom")
  eq(UI.barLift({ _fieldBarLift = 24, _kitSheet = true, _kitCell = 53 }), 14,
    "tall hop-padded kits still plant HP on the ~24px body")
  eq(UI.barLift({ _fieldBarLift = 24, _kitSheet = true, _kitCell = 32 }), 22,
    "32px kits sit a couple px above the cell top")
end

function tests.hp_stack_does_not_jump_when_mood_appears()
  local function paintBadgeY(mood)
    local prevMood, prevChip = UI.moodOf, UI.moodChip
    UI.moodOf = function()
      return mood
    end
    UI.moodChip = function()
      return { text = "WRRY", fill = { 1, 1, 0.94 } }
    end
    local firstY
    local prevLove = love
    love = {
      graphics = {
        setColor = function() end,
        rectangle = function(_, _, y)
          if firstY == nil then
            firstY = y
          end
        end,
        polygon = function() end,
        push = function() end,
        pop = function() end,
        translate = function() end,
        scale = function() end,
        print = function() end,
      },
    }
    local player = {
      _arFieldBattler = true,
      _arFieldSide = "player",
      px = 20, py = 40, _fieldBarLift = 10, hidden = false,
    }
    local battle = {
      _arAnimeField = true,
      player = { shownHP = 20, mon = { name = "EKANS", stats = { hp = 20 } } },
      game = {
        overworld = {
          camera = { x = 0, y = 0 },
          entities = { player },
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
    UI.moodOf, UI.moodChip = prevMood, prevChip
    return firstY
  end
  eq(paintBadgeY(nil), paintBadgeY("worried"),
    "HP chip stays put when a mood pill appears")
end

function tests.hp_chip_plants_on_the_sprite()
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
    px = 80, py = 64, _fieldBarLift = 10, hidden = false,
  }
  local battle = {
    _arAnimeField = true,
    player = { shownHP = 20, mon = { name = "EKANS", stats = { hp = 20 } } },
    enemy = { shownHP = 30, mon = { name = "GEODUDE", stats = { hp = 30 } } },
    game = {
      overworld = { camera = { x = 0, y = 0 }, entities = { enemy } },
      renderer = {
        uiSize = function() return 160, 144 end,
        worldViewSize = function() return 160, 144 end,
        fitScale = function() return 1 end,
      },
    },
  }
  UI.drawWorldHP(battle, 0, 0, "ui")
  love = prevLove
  local hx, hy = UI.hpAboveMon((enemy.px or 0) + 8, (enemy.py or 0) - 10)
  hx, hy = UI.clampHpChip(hx, hy, 160, 144, 0)
  truthy(#painted > 0, "HP chip paints on the overlay")
  local near = false
  for i = 1, #painted do
    if math.abs((painted[i].x or 0) - (hx - math.floor(UI.HP_CHIP_W / 2))) <= 2 then
      near = true
      break
    end
  end
  truthy(near, "HP chip sits next to the field sprite, not the window corner")
end

function tests.window_faces_hug_true_window_corners()
  local drawn = {}
  local prevFace, prevMood, prevChip = UI.faceFlash, UI.moodOf, UI.moodChip
  UI.faceEnabled = function() return true end
  UI.faceFlash = function(_, isPlayer)
    return { getWidth = function() return 40 end }, 1, isPlayer
  end
  UI.moodOf = function() return nil end
  local prevLove = love
  love = {
    graphics = {
      getWidth = function() return 800 end,
      getHeight = function() return 450 end,
      push = function() end,
      pop = function() end,
      origin = function() end,
      setScissor = function() end,
      setColor = function() end,
      setBlendMode = function() end,
      translate = function() end,
      scale = function() end,
      draw = function(_, x, y)
        drawn[#drawn + 1] = { x = x, y = y }
      end,
    },
  }
  local battle = { _arAnimeField = true }
  local ren = {
    uiScale = function() return 2 end,
    uiSize = function() return 160, 144 end,
    _arFieldFaceBattle = battle,
  }
  truthy(UI.drawWindowFaceHud(ren, { width = 800, height = 450, dpiX = 1, dpiY = 1 }, battle),
    "window faces paint")
  love = prevLove
  UI.faceFlash, UI.moodOf, UI.moodChip = prevFace, prevMood, prevChip
  UI.faceEnabled = nil
  eq(#drawn, 2, "both faces paint")
  local pad = UI.HUD_PAD
  local fs = UI.FACE_SIZE
  eq(drawn[1].x, pad, "player face authors at the left pad")
  eq(drawn[1].y, pad, "player face authors at the top pad")
  eq(drawn[2].x, 160 - pad - fs, "foe face authors at the right pad")
  eq(drawn[2].y, pad, "foe face authors at the top pad")
end

function tests.field_hud_registers_wide_anchors()
  local anchors = {}
  local enemy = {
    _arFieldBattler = true,
    _arFieldSide = "enemy",
    px = 80, py = 40, _fieldBarLift = 10, hidden = false,
  }
  local player = {
    _arFieldBattler = true,
    _arFieldSide = "player",
    px = 20, py = 40, _fieldBarLift = 10, hidden = false,
  }
  local battle = {
    _arAnimeField = true,
    player = { shownHP = 20, mon = { name = "EKANS", stats = { hp = 20 } } },
    enemy = { shownHP = 30, mon = { name = "GEODUDE", stats = { hp = 30 } } },
    game = {
      overworld = {
        camera = { x = 0, y = 0 },
        entities = { player, enemy },
      },
      renderer = {
        uiSize = function() return 160, 144 end,
        worldViewSize = function() return 160, 144 end,
        fitScale = function() return 1 end,
        setBattleUIAnchor = function(_, x, y, w, h, anchor)
          anchors[#anchors + 1] = { x = x, y = y, w = w, h = h, anchor = anchor }
        end,
      },
    },
  }
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      rectangle = function() end,
      polygon = function() end,
      push = function() end,
      pop = function() end,
      translate = function() end,
      scale = function() end,
      print = function() end,
    },
  }
  UI.drawWorldHP(battle, 0, 0, "ui")
  love = prevLove
  eq(#anchors, 0, "HP stacks stay on the battle overlay")
  eq(battle.game.renderer._arFieldHudLeft, nil,
    "no second window blit of the player stack")
end

function tests.field_hud_window_left_blits_from_stored_stack()
  local drawn = {}
  local canvas = {
    getWidth = function() return 160 end,
    getHeight = function() return 144 end,
  }
  local ren = {
    _arFieldHudLeft = { x = 4, y = 4, w = 28, h = 40, canvas = canvas },
    uiScale = function() return 2 end,
    uiSize = function() return 160, 144 end,
  }
  local prevLove = love
  love = {
    graphics = {
      push = function() end,
      pop = function() end,
      origin = function() end,
      setScissor = function() end,
      setColor = function() end,
      newQuad = function(x, y, w, h)
        return { x = x, y = y, w = w, h = h }
      end,
      draw = function(src, quad, x, y, _, sx)
        drawn[#drawn + 1] = { src = src, quad = quad, x = x, y = y, sx = sx }
      end,
    },
  }
  truthy(UI.drawWindowPlayerHud(ren, { width = 800, height = 450, dpiX = 1, dpiY = 1 }),
    "window-left blit runs")
  love = prevLove
  eq(#drawn, 1, "one player stack blit")
  eq(drawn[1].x, 8, "stack docks to window left at authored pad * scale")
  eq(drawn[1].y, 8, "stack docks to window top at authored pad * scale")
  eq(drawn[1].sx, 2, "stack uses the UI scale")
end

function tests.field_hud_does_not_clear_stack_before_anchor()
  local kept = { x = 4, y = 4, w = 28, h = 40, canvas = {} }
  local battle = {
    game = { renderer = { _arFieldHudLeft = kept } },
  }
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      rectangle = function() end,
      polygon = function() end,
      push = function() end,
      pop = function() end,
      translate = function() end,
      scale = function() end,
      print = function() end,
    },
  }
  UI.drawWorldHP(battle, 0, 0, "ui")
  love = prevLove
  eq(battle.game.renderer._arFieldHudLeft, kept,
    "missing battlers do not wipe the window blit box")
end

function tests.field_hud_uses_session_mon_when_off_the_entity_list()
  local painted = 0
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      rectangle = function()
        painted = painted + 1
      end,
      polygon = function() end,
      push = function() end,
      pop = function() end,
      translate = function() end,
      scale = function() end,
      print = function() end,
    },
  }
  local player = {
    _arFieldBattler = true,
    _arFieldSide = "player",
    px = 20, py = 40, _fieldBarLift = 10,
    hidden = true,
  }
  local battle = {
    _arAnimeField = true,
    player = { shownHP = 20, mon = { name = "EKANS", stats = { hp = 20 } } },
    enemy = { shownHP = 20, mon = { name = "GEODUDE", stats = { hp = 20 } } },
    game = {
      overworld = { camera = { x = 0, y = 0 }, entities = {} },
      renderer = {
        uiSize = function() return 160, 144 end,
        worldViewSize = function() return 160, 144 end,
        fitScale = function() return 1 end,
      },
    },
  }
  local session = {
    live = true,
    grid = {},
    playerMon = player,
    enemyMon = nil,
  }
  Lifecycle._testBind(battle, session)
  UI.drawWorldHP(battle, 0, 0, "ui")
  love = prevLove
  Lifecycle._testUnbind(battle)
  truthy(painted > 0, "HP still paints when the mon is off ow.entities")
end

function tests.field_hud_redraws_when_overlay_beats_present_tick()
  local FBV = FieldBattle
  local draws, chrome = 0, 0
  local orig = FBV.drawUI
  local origChrome = FBV.drawChrome
  FBV.drawUI = function()
    draws = draws + 1
  end
  FBV.drawChrome = function()
    chrome = chrome + 1
  end
  local gen, opened = 0, false
  FBV.beginPresentFrame = function()
    if not opened then
      gen = gen + 1
      opened = true
    end
    return gen
  end
  local battle = { _arHudDrew = true }
  FBV.drawFrame(battle)
  eq(draws, 1, "stale _arHudDrew does not skip faces or the command plate")
  FBV.drawFrame(battle)
  eq(draws, 1, "same present gen does not replay FX")
  eq(chrome, 1, "same present gen restamps chrome after the engine clear")
  opened = false
  FBV.drawFrame(battle)
  eq(draws, 2, "next display frame paints again")
  FBV.drawUI = orig
  FBV.drawChrome = origChrome
  FBV.beginPresentFrame = nil
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
      translate = function() end,
      scale = function() end,
    },
  }
  local battle = {
    _arAnimeField = true,
    phase = "moveSelect",
    moveIndex = 1,
    player = {
      curMoves = {
        { id = "TACKLE", pp = 35 }, { id = "GROWL", pp = 40 },
        { id = "TAIL_WHIP", pp = 30 }, { id = "SCRATCH", pp = 0 },
      },
    },
    data = {
      moves = {
        TACKLE = { name = "TACKLE", type = "NORMAL", pp = 35 },
        GROWL = { name = "GROWL", type = "NORMAL", pp = 40 },
        TAIL_WHIP = { name = "TAIL WHIP", type = "NORMAL", pp = 30 },
        SCRATCH = { name = "SCRATCH", type = "NORMAL", pp = 35 },
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
  local listed = false
  local sawHeaderPP = false
  local up, right, left, down = false, false, false, false
  for i = 1, #drawn do
    if drawn[i] == "B Pause" then
      hinted = true
    end
    if drawn[i] == "Tackle" then
      listed = true
    end
    if drawn[i] == "PP 35/35" then
      sawHeaderPP = true
    end
    if drawn[i] == "U" then up = true end
    if drawn[i] == "R" then right = true end
    if drawn[i] == "L" then left = true end
    if drawn[i] == "D" then down = true end
  end
  truthy(hinted, "classic MOVE HUD tells the player to pause with B")
  truthy(listed, "classic MOVE HUD lists move names")
  truthy(sawHeaderPP, "classic MOVE HUD shows selected PP on the B PAUSE row")
  truthy(up and right and left and down,
    "classic MOVE HUD labels slots U/R/L/D")
end

function tests.diamond_move_hud_uses_compass()
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
      translate = function() end,
      scale = function() end,
    },
  }
  local battle = {
    _arAnimeField = true,
    phase = "moveSelect",
    moveIndex = 1,
    player = {
      curMoves = {
        { id = "TACKLE", pp = 35 }, { id = "GROWL", pp = 40 },
        { id = "TAIL_WHIP", pp = 30 }, { id = "SCRATCH", pp = 35 },
      },
    },
    data = {
      moves = {
        TACKLE = { name = "TACKLE", pp = 35 },
        GROWL = { name = "GROWL", pp = 40 },
        TAIL_WHIP = { name = "TAIL WHIP", pp = 30 },
        SCRATCH = { name = "SCRATCH", pp = 35 },
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
  UI.draw(battle, "DIAMOND")
  love = prevLove
  package.loaded["src.render.Font"] = nil
  local hinted, up, right, sawHeaderPP = false, false, false, false
  for i = 1, #drawn do
    if drawn[i] == "B Pause" then hinted = true end
    if drawn[i] == "U" then up = true end
    if drawn[i] == "R" then right = true end
    if drawn[i] == "PP 35/35" then sawHeaderPP = true end
  end
  truthy(hinted, "diamond MOVE HUD keeps the B pause hint")
  truthy(up and right, "diamond MOVE HUD paints the U/R compass labels")
  truthy(sawHeaderPP, "diamond MOVE HUD shows selected PP on the B PAUSE row")
end

function tests.move_hud_pp_label()
  eq(UI.movePPLabel(nil, nil), nil, "missing move has no PP")
  eq(UI.movePPLabel({}, { id = "TACKLE" }), nil, "unset PP is omitted")
  eq(UI.movePPLabel({}, { id = "TACKLE", pp = 12 }), "12", "remaining PP")
  eq(UI.movePPLabel({
    data = { moves = { TACKLE = { pp = 35 } } },
  }, { id = "TACKLE", pp = 12 }, true), "12/35", "remaining over max")
  eq(UI.movePPLabel({}, { struggle = true, pp = 1 }), nil, "struggle has no PP")
end

function tests.hud_text_uses_lowercase_words()
  eq(UI.hudText("FIGHT"), "Fight", "command words use the pixel lowercase")
  eq(UI.hudText("PKMN"), "PKMN", "PKMN stays a tag")
  eq(UI.hudText("B PAUSE"), "B Pause", "hints title-case the words")
  eq(UI.hudText("TACKLE"), "Tackle", "move names title-case")
  eq(UI.hudText("ACID ARMOR"), "Acid Armor", "two-word moves title-case")
  eq(UI.hudText("PP 35/35"), "PP 35/35", "PP stays a tag")
  eq(UI.hudText("Go! SQUIRTLE!"), "Go! Squirtle!",
    "mixed lines only rewrite the ALL-CAPS words")
  local Type = UI.Type
  truthy(Type and Type.FILE:find("pokepixel%-gba", 1, false),
    "HUD typeface is pokepixel-gba")
end

function tests.hud_plate_is_one_glass_alpha()
  eq(UI.hudPanelAlpha(), UI.HUD_PANEL_A, "HUD plate alpha is constant")
  eq(UI.hudPanelAlpha({ _arFieldSession = { coverScene = "cave" } }),
    UI.HUD_PANEL_A, "caves use the same plate")
  eq(UI.hudPanelAlpha({ _arFieldSession = { coverScene = "route" } }),
    UI.HUD_PANEL_A, "routes use the same plate")
end

function tests.dialogue_plate_is_one_light_glass()
  local fill = UI.DIALOGUE_FILL
  truthy(fill and fill[1] > 0.9 and fill[2] > 0.9 and fill[3] > 0.8,
    "plain dialogue is a light plate")
  eq(UI.DIALOGUE_A, 1, "dialogue plate is opaque so the world cannot shimmer through")
  eq(UI.HUD_PANEL_A, 1, "command / move plate is opaque")
  local x, y, w, h = UI.dialogueRect()
  eq(x, 4, "dialogue stays in the bottom slot")
  eq(y, 119, "dialogue sits on the vanilla row")
  eq(w, 152, "dialogue keeps the full-width slot")
end

function tests.move_hud_style_defaults_to_classic()
  eq(UI.moveHudStyle(nil), "CLASSIC", "unset style is classic")
  eq(UI.moveHudStyle("classic"), "CLASSIC", "classic is case-insensitive")
  eq(UI.moveHudStyle("DIAMOND"), "DIAMOND", "diamond is opt-in")
  eq(FieldBattle.moveHudStyle({
    options = { get = function() return nil end },
  }), "CLASSIC", "missing option is classic")
  eq(FieldBattle.moveHudStyle({
    options = {
      get = function(_, key)
        if key == "move_hud" then return "DIAMOND" end
      end,
    },
  }), "DIAMOND", "option selects diamond")
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

function tests.hp_bar_tracks_live_hp()
  local ratio, hp, maxHP = UI.battlerHP({
    shownHP = 0,
    mon = { hp = 12, stats = { hp = 40 } },
  })
  eq(hp, 12, "live HP wins over a drained display numerator")
  eq(maxHP, 40, "max HP comes from stats")
  eq(ratio, 12 / 40, "ratio is remaining over max")

  ratio, hp = UI.battlerHP({
    shownHP = 20,
    mon = { name = "EKANS", stats = { hp = 20 } },
  })
  eq(hp, 20, "shownHP is the fallback when mon.hp is missing")
  eq(ratio, 1, "full shownHP paints a full bar")

  ratio, hp = UI.battlerHP({
    shownHP = 8,
    mon = { hp = 0, stats = { hp = 20 } },
  })
  eq(hp, 0, "fainted mon paints empty even if shownHP lags")
  eq(ratio, 0, "fainted ratio is 0")

  ratio, hp = UI.battlerHP({
    shownHP = 20,
    mon = { hp = 8, stats = { hp = 20 } },
  }, { _arCloseGapApply = { {} } })
  eq(hp, 20, "a stashed travel hit keeps the pre-hit bar")

  local snapBattle = {
    _arRangedHitHold = true,
    _arHeldHpPaint = { player = 20 },
  }
  snapBattle.player = {
    shownHP = 20,
    mon = { hp = 8, stats = { hp = 20 } },
  }
  ratio, hp = UI.battlerHP(snapBattle.player, snapBattle)
  eq(hp, 20, "a charge snapshot keeps the pre-hit bar after live HP drops")

  local inner = UI.HP_BAR_W - 2
  eq(inner, 18, "compact bar is a short track")
  eq(UI.hpFillWidth(inner, 0, 40), 0, "KO is an empty track")
  truthy(UI.hpFillWidth(inner, 1, 100) >= 1, "1 HP still occupies a pixel")
  eq(UI.hpFillWidth(inner, 40, 40), inner, "full HP fills the track")
  eq(UI.hpFillWidth(inner, 20, 40), 9, "half HP is half the track")
  eq(UI.hpFillWidth(inner, 39, 40), 17, "a 1 HP hit on 40 max drops a pixel")
  local low = UI.hpFillWidth(inner, 4, 40)
  truthy(low >= 1, "low but living HP is not rounded to an empty bar")
  eq(UI.easeHpFill(nil, 18), 18, "first paint snaps to the true fill")
  eq(UI.easeHpFill(18, 12), 17, "damage ticks one pixel per frame")
  eq(UI.easeHpFill(18, 18), 18, "settled fill holds")
  eq(UI.easeHpFill(0, 18), 18, "send-out snaps up to full")
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
    return ys[1], ys[#ys]
  end
  local flushTop, flushBot = paintY(0)
  local gappedTop, gappedBot = paintY(1)
  UI.focusBarVisible, UI.focusRatio, UI.focusBarGap = prevVisible, prevRatio, prevGap
  eq(flushBot, gappedBot, "HP bar stays planted on the sprite")
  truthy(gappedTop < flushTop, "1PX gap lifts the focus bar one pixel")
end

function tests.compact_arena_keeps_cast_lanes_clear()
  local player = { cellX = 10, cellY = 10, facing = "right" }
  local fx, fy = Layout.wildAnchor(player)
  local plan = Layout.plan(player.cellX, player.cellY, fx, fy)
  eq(plan.pCellX, player.cellX, "wild pad starts at player")
  eq(math.abs(plan.pMonX - plan.eMonX), 2, "wild mons start one cell apart")
  local arena = Arena.generate(nil, plan, 12345)
  eq(arena.pad.sizeU, 5, "opening arena width")
  eq(arena.pad.sizeV, 3, "arena height")
  truthy(not arena.handcrafted, "tight pad ignores 10x5 hand layouts")

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
  eq(math.abs(plan.pCellY - plan.eCellY), 4, "trainer edges span the opening pad")
  eq(math.abs(plan.pMonY - plan.eMonY), 2, "mons start one cell apart")
end

local function sampleGrid()
  local plan = Layout.plan(10, 10, 18, 10)
  return Grid.build(nil, plan), plan
end

local function loadReactiveDefense()
  local RD = assert(loadfile(root .. "/../battle/rules/reactive_defense.lua"))()
  local FoeAi = assert(loadfile(root .. "/../battle/rules/foe_ai.lua"))()
  FoeAi.attach(RD)
  return RD, FoeAi
end

function tests.cover_can_force_a_miss()
  local RD = assert(loadfile(root .. "/../battle/rules/reactive_defense.lua"))()
  local tackle = { id = "TACKLE", power = 35, category = "physical", type = "NORMAL" }
  local blizzard = { id = "BLIZZARD", power = 120, category = "special", type = "ICE" }
  local battle = {
    player = { stats = { speed = 80, defense = 50, special = 40 } },
    enemy = { stats = { speed = 40, defense = 80, special = 30 } },
  }
  RD.state(battle)
  RD._testRng = function() return 0 end
  local result = RD.resolveIncoming(battle, "cover", nil, {
    user = battle.enemy,
    target = battle.player,
    move = tackle,
  })
  eq(result.forceMiss, true, "cover can make the incoming miss")
  eq(result.coverSoak, false, "a miss does not spend cover durability")
  RD._testRng = function() return 0 end
  result = RD.resolveIncoming(battle, "cover", nil, {
    user = battle.enemy,
    target = battle.player,
    move = blizzard,
  })
  eq(result.forceMiss, false, "pierce moves still find cover")
  truthy(result.coverSoak, "pierce still soaks durability")
  RD._testRng = nil
  RD.clear(battle)
end

function tests.blizzard_uses_a_snow_cone_not_an_area_ring()
  eq(FxCatalog.MOVE_FX.BLIZZARD.style, "blizzard", "Blizzard is its own style")
  truthy(FxCatalog.MOVE_FX.BLIZZARD.style ~= "area", "Blizzard is not a filled ring")
  local grid = sampleGrid()
  local player = {
    id = "player", padU = grid.home.player.u, padV = grid.home.player.v,
    px = 16, py = 32,
  }
  local enemy = {
    id = "enemy", padU = grid.home.enemy.u, padV = grid.home.enemy.v,
    px = 96, py = 40,
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _battle = { kind = "wild" },
  }
  Projectiles.clear(session)
  local storm = Projectiles.move(session, "player", {
    category = "special", moveType = "ICE", moveId = "BLIZZARD",
  })
  truthy(storm, "Blizzard spawned")
  eq(storm.style, "blizzard", "catalog style reaches the projectile")
end

function tests.npc_react_spends_focus_and_mixes_picks()
  local RD = loadReactiveDefense()
  local battle = {
    player = { stats = { speed = 80, defense = 50, special = 60 } },
    enemy = { stats = { speed = 55, defense = 90, special = 40 } },
  }
  local ember = { id = "EMBER", power = 40, category = "special" }
  local hyper = { id = "HYPER_BEAM", power = 150, category = "special" }
  RD.state(battle)
  local side = RD.sideState(battle, false)
  local start = side.focus
  truthy(start >= RD.COST.dodge, "foe starts with enough focus to dodge")
  local spentOk = RD.spend(battle, false, "dodge")
  truthy(spentOk, "foe dodge spends")
  eq(side.focus, start - RD.COST.dodge, "foe dodge costs the same as the player")
  side.focus = 10
  eq(RD.pickFoeReact(battle, ember, true), "commit",
    "drained foe has to take the hit")
  eq(RD.pickFoeReact(battle, hyper, true), "commit",
    "unreactable moves are not dodged")
  side.focus = start
  local seen = { commit = 0, dodge = 0, brace = 0 }
  for _ = 1, 48 do
    local pick = RD.pickFoeReact(battle, ember, true)
    seen[pick] = (seen[pick] or 0) + 1
  end
  truthy(seen.dodge < 48, "ember is not an automatic dodge")
  truthy((seen.commit + seen.brace) > 0, "foe sometimes braces or stands in")
  RD.clear(battle)
end

function tests.dig_fly_hide_turn_passes_react()
  local RD = loadReactiveDefense()
  local dig = { id = "DIG", power = 80, category = "physical", type = "GROUND" }
  local fly = { id = "FLY", power = 70, category = "physical", type = "FLYING" }
  local tackle = { id = "TACKLE", power = 35, category = "physical", type = "NORMAL" }
  local user = {}
  truthy(RD.isVanishHideTurn(user, dig), "first Dig is a hide turn")
  truthy(RD.isVanishHideTurn(user, fly), "first Fly is a hide turn")
  truthy(not RD.isVanishHideTurn(user, tackle), "Tackle is not a hide")
  user.charging = { id = "DIG" }
  truthy(not RD.isVanishHideTurn(user, dig), "second Dig is the strike")
  user.invulnerable = true
  truthy(RD.isVanished(user), "charging Dig is vanished")
  local battle = {
    player = { mon = { level = 20 } },
    enemy = {},
  }
  RD.state(battle)
  local actions = RD.menuActions(battle, dig)
  eq(#actions, 1, "hide turn only lists PASS")
  eq(actions[1].label, "PASS", "the leftover row is PASS")
  eq(RD.pickFoeReact(battle, dig, false), "commit",
    "foe does not lunge at a hole")
  battle.player.invulnerable = true
  battle.player.charging = { id = "FLY" }
  actions = RD.menuActions(battle, tackle)
  eq(actions[1].label, "PASS", "buried defender only gets PASS")
  local React = assert(loadfile(root .. "/../battle/rules/react.lua"))()
  React.bind({
    RD = RD,
    opt = function(key)
      return key == "momentum_counter"
    end,
    pickMode = function()
      return "ALWAYS"
    end,
    playerStatusLocked = function()
      return false
    end,
    foeMoveIsSpecial = function()
      return false
    end,
  })
  local offer = {
    player = { mon = { level = 20 } },
    enemy = {},
  }
  RD.state(offer)
  React.state(offer)
  truthy(not React.shouldOffer(offer, dig), "hide turn does not open REACT")
  offer.enemy.charging = { id = "DIG" }
  truthy(React.shouldOffer(offer, dig), "Dig strike still opens REACT")
  RD.clear(battle)
end

function tests.npc_react_may_fire_when_the_window_is_open()
  local RD, FoeAi = loadReactiveDefense()
  local ember = { id = "EMBER", power = 40, category = "special", type = "FIRE" }
  local tackle = { id = "TACKLE", power = 35, category = "physical", type = "NORMAL" }
  local specialist = {
    player = { stats = { speed = 50, defense = 40, special = 45 } },
    enemy = { stats = { speed = 70, defense = 50, special = 95 } },
  }
  RD.state(specialist)
  local firedClosed = false
  for _ = 1, 32 do
    if RD.pickFoeReact(specialist, tackle, false) == "fire"
      or RD.pickFoeReact(specialist, ember, true) == "fire" then
      firedClosed = true
    end
  end
  truthy(not firedClosed, "FIRE stays off when the window is closed")
  -- Seed a few rolls so a specialist actually takes FIRE sometimes.
  local seen = { commit = 0, dodge = 0, brace = 0, fire = 0 }
  for _ = 1, 80 do
    local pick = RD.pickFoeReact(specialist, tackle, false, { canFireNow = true })
    seen[pick] = (seen[pick] or 0) + 1
  end
  truthy(seen.fire > 0, "a special attacker may FIRE a charging physical")
  truthy(seen.fire < 80, "FIRE is not automatic")
  local clashSeen = 0
  for _ = 1, 80 do
    if RD.pickFoeReact(specialist, ember, true, { canFireNow = true }) == "fire" then
      clashSeen = clashSeen + 1
    end
  end
  truthy(clashSeen > 0, "a special attacker may FIRE into an incoming beam")

  local drained = RD.sideState(specialist, false)
  drained.focus = 10
  eq(RD.pickFoeReact(specialist, tackle, false, { canFireNow = true }), "commit",
    "drained foe cannot FIRE")
  RD.clear(specialist)

  local wall = {
    player = { stats = { speed = 80, defense = 50, special = 60 } },
    enemy = { stats = { speed = 40, defense = 90, special = 35 } },
  }
  RD.state(wall)
  eq(FoeAi.canFireNow(wall, tackle, {
    fieldBattle = true,
    fireRangeOpen = true,
    playerChargeOpen = true,
    shotCount = 1,
    incomingMelee = true,
  }), true, "melee charge at two tiles is a FIRE window")
  eq(FoeAi.canFireNow(wall, ember, {
    fieldBattle = true,
    fireRangeOpen = true,
    shotCount = 1,
  }), true, "incoming special at two tiles is a clash window")
  eq(FoeAi.canFireNow(wall, ember, {
    fieldBattle = true,
    fireRangeOpen = false,
    shotCount = 1,
  }), false, "adjacent melee is too late to FIRE")
  eq(FoeAi.canFireNow(wall, ember, {
    fieldBattle = false,
    fireRangeOpen = true,
    shotCount = 1,
  }), false, "classic battles do not FIRE")
  eq(FoeAi.canFireNow(wall, ember, {
    fieldBattle = true,
    fireRangeOpen = true,
    shotCount = 0,
  }), false, "no ranged specials means no FIRE")
  eq(FoeAi.canFireNow(wall, ember, {
    fieldBattle = true,
    fireRangeOpen = true,
    shotCount = 1,
    alreadyActed = true,
  }), false, "foe who already called cannot FIRE")
  local shots = FoeAi.pickFireShot({
    { moveId = "EMBER", power = 40 },
    { moveId = "FLAMETHROWER", power = 95 },
    { moveId = "SMOKESCREEN", power = 0 },
  })
  eq(shots.moveId, "FLAMETHROWER", "foe FIRE picks the strongest shot")
  eq(FoeAi.pickFireShot({
    { moveId = "EMBER", power = 40 },
    { moveId = "TACKLE", power = 35, checkNow = true },
    { moveId = "FLAMETHROWER", power = 95 },
  }).moveId, "FLAMETHROWER",
    "foe FIRE does not spend the shot on a punch")
  RD.clear(wall)
end

function tests.fire_now_reacts_during_a_charge()
  local RD = assert(loadfile(root .. "/../battle/rules/reactive_defense.lua"))()
  RD._testRng = function() return 1 end
  local battle = {
    player = { stats = { speed = 90, defense = 40, special = 80 } },
    enemy = { stats = { speed = 40, defense = 80, special = 30 } },
  }
  RD.state(battle)
  local tackle = { id = "TACKLE", power = 35, category = "physical", type = "NORMAL" }
  truthy(not RD.isSpecialClashIncoming(tackle), "tackle is not a special clash")
  truthy(RD.isSpecialClashIncoming({
    id = "SWIFT", power = 60, category = "physical", type = "NORMAL",
  }), "swift clashes as a projectile special")
  local actions = RD.menuActions(battle, tackle)
  local ids = {}
  for i = 1, #actions do
    ids[actions[i].id] = true
  end
  truthy(not ids.fire, "FIRE stays off when the charge window is closed")
  actions = RD.menuActions(battle, tackle, {
    canFireNow = true,
    fireHint = "THUNDERBOLT",
  })
  ids = {}
  for i = 1, #actions do
    ids[actions[i].id] = actions[i]
  end
  truthy(ids.fire, "FIRE is on the REACT menu during a charge")
  eq(ids.fire.hint, "THUNDERBOLT", "FIRE names the locked special")
  truthy(not ids.entrench, "entrench yields the diamond slot to FIRE")
  local result = RD.resolveIncoming(battle, "fire", nil, {
    user = battle.enemy,
    target = battle.player,
    move = tackle,
  })
  eq(result.fireNow, true, "FIRE NOW spends this turn's action on the special")
  eq(result.forceMiss, false, "FIRE NOW does not dodge")
  truthy(result.damageMult > 1, "caught casting takes extra if the charge lands")
  eq(RD.REACT_SPECIAL_MULT, 0.75, "a REACT special is a bit weaker (no charge)")
  RD.clear(battle)

  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v,
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    _pendingCloseStrike = { moveId = "QUICK_ATTACK" },
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local battle = { player = { isPlayer = true }, enemy = { isPlayer = false } }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
  }
  truthy(Cues.fireRangeOpen(session),
    "opening homes are a two-tile fire range")
  truthy(Cues.chargeWindowOpen(session),
    "opening homes are still a fire window")
  truthy(Cues.shouldHoldApplyDamage(session, battle, battle.player),
    "the incoming punch still waits")
  truthy(not Cues.shouldHoldApplyDamage(session, battle, battle.enemy),
    "a punch walk does not stash the charger's HP")
  Cues.armRangedHitHold(session, battle)
  battle._arFireNow = true
  truthy(Cues.shouldHoldApplyDamage(session, battle, battle.enemy),
    "FIRE NOW HP waits for the bolt to land")
  battle._arFireNow = nil
  Cues.dropRangedHitHold(session, battle)
  enemy._pendingCloseStrike = nil
  truthy(not Cues.chargeWindowOpen(session), "no charge is not a fire window")
end

function tests.fire_now_only_at_two_tile_gap()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v,
    basePx = 0, basePy = 0,
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    basePx = 32, basePy = 0,
    _pendingCloseStrike = { moveId = "TACKLE" },
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
  }
  eq(math.max(math.abs(eHome.u - pHome.u), math.abs(eHome.v - pHome.v)),
    Cues.FIRE_PAD_RANGE, "homes sit two tiles apart")
  truthy(Cues.fireRangeOpen(session), "FIRE while they are two tiles out")

  -- Occupancy already adjacent; feet still two tiles away.
  enemy.padU = pHome.u + 1
  enemy.padV = pHome.v
  enemy.basePx = 48
  truthy(not Cues.inMeleeReach(player, enemy), "sprite has not arrived")
  truthy(Cues.fireRangeOpen(session),
    "FIRE while they close from two tiles")
  truthy(Cues.chargeWindowOpen(session),
    "pending charge at that gap is still a fire window")

  enemy.basePx = 8
  truthy(Cues.inMeleeReach(player, enemy), "they are in your face")
  truthy(not Cues.fireRangeOpen(session), "no FIRE once they reach melee")
  truthy(not Cues.chargeWindowOpen(session),
    "a punch in your face is not a fire window")

  enemy.basePx = 48
  enemy.padU = pHome.u + 3
  enemy.padV = pHome.v
  truthy(not Cues.fireRangeOpen(session), "three tiles is not the shot")
  enemy._pendingCloseStrike = nil
  enemy.padU = eHome.u
  enemy.padV = eHome.v
  truthy(Cues.fireRangeOpen(session), "homes without a charge are still range")

  -- Your charge: foe FIRE uses the same two-tile / still-closing window.
  player._pendingCloseStrike = { moveId = "TACKLE" }
  player.padU = pHome.u + 1
  player.padV = pHome.v
  player.basePx = 0
  enemy.padU = eHome.u
  enemy.padV = eHome.v
  enemy.basePx = 32
  truthy(not Cues.inMeleeReach(player, enemy), "you have not arrived")
  truthy(Cues.fireRangeOpen(session),
    "foe FIRE while you close from two tiles")
  truthy(Cues.playerChargeWindowOpen(session),
    "your pending charge is their fire window")
  truthy(not Cues.chargeWindowOpen(session),
    "your charge is not the player's FIRE window")
  player.basePx = 8
  truthy(Cues.inMeleeReach(player, enemy), "you reached melee")
  truthy(not Cues.fireRangeOpen(session), "no foe FIRE once you arrive")
end

function tests.far_shot_specials_lose_accuracy()
  eq(Cues.farShotMissChance(2), 0, "opening gap is not a long shot")
  eq(Cues.farShotMissChance(4), 0, "four tiles is still close")
  eq(Cues.farShotMissChance(5), 0.10, "five tiles is a long shot")
  eq(Cues.farShotMissChance(6), 0.15, "six tiles is longer")
  eq(Cues.farShotMissChance(8), 0.20, "farther caps")

  local session = {
    playerMon = { padU = 0, padV = 0 },
    enemyMon = { padU = 6, padV = 0 },
  }
  local alwaysMiss = function() return 0 end
  eq(Cues.applyFarShotAccuracy(session, {
    move = { id = "EMBER", category = "special" },
  }, true, alwaysMiss), false, "far ember can miss extra")
  eq(Cues.applyFarShotAccuracy(session, {
    move = { id = "TACKLE", category = "physical" },
  }, true, alwaysMiss), true, "physicals do not take the long-shot tax")
  eq(Cues.applyFarShotAccuracy(session, {
    move = { id = "SWIFT", category = "special", neverMiss = true },
  }, true, alwaysMiss), true, "never-miss stays never-miss")
  eq(Cues.applyFarShotAccuracy(session, {
    move = { id = "SWIFT", category = "special", accuracy = 0 },
  }, true, alwaysMiss), true, "gen1 never-miss accuracy 0 is skipped")

  session.enemyMon.padU = 2
  eq(Cues.applyFarShotAccuracy(session, {
    move = { id = "EMBER", category = "special" },
  }, true, alwaysMiss), true, "two tiles does not extra-miss")
  eq(Cues.applyFarShotAccuracy(session, {
    move = { id = "EMBER", category = "special" },
  }, false, alwaysMiss), false, "an engine miss stays a miss")
end

function tests.fire_now_hit_stops_the_charge()
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
    _pendingCloseStrike = { moveId = "TACKLE" },
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local startU, startV = enemy.padU, enemy.padV
  local battle = { _arFireNow = true }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 40,
    _deps = { Projectiles = Projectiles },
    _battle = battle,
  }
  truthy(Cues.apply(session, "enemy", "hit", Grid, nil, battle, {
    category = "special", moveId = "WATER_GUN",
  }), "FIRE hit cue")
  truthy(not enemy._pendingCloseStrike, "connecting FIRE cancels the charge")
  truthy(enemy._heavyHit, "charger is knocked back")
  eq(enemy.lastAnim, "tumble", "charger takes the bolt")
  truthy(enemy.padU ~= startU or enemy.padV ~= startV,
    "charger leaves the charge cell")
end

function tests.check_now_hit_stops_the_charge_one_tile()
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
    _pendingCloseStrike = { moveId = "QUICK_ATTACK" },
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local startU = enemy.padU
  local battle = { _arFireNow = true, _arCheckNow = true }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 41,
    _deps = { Projectiles = Projectiles, Grid = Grid },
    _battle = battle,
  }
  truthy(Cues.apply(session, "enemy", "hit", Grid, nil, battle, {
    category = "physical", moveId = "TACKLE",
  }), "CHECK hit cue")
  truthy(not enemy._pendingCloseStrike, "connecting CHECK cancels the charge")
  eq(enemy.lastAnim, "tumble", "charger takes the tackle")
  local moved = math.max(math.abs((enemy.padU or 0) - startU),
    math.abs((enemy.padV or 0) - eHome.v))
  eq(moved, 1, "CHECK knocks the charger one tile, not two")
end

function tests.smog_haze_occupies_the_lane_without_jumping()
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
    _pendingCloseStrike = { moveId = "TACKLE" },
    _cuttingHaze = true,
    hp = 40,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  truthy(not Grid.pathObstructed(grid, player, enemy),
    "open lane is not solid cover")
  local placed = Grid.seedHaze(grid, player, enemy, {
    side = "player", moveId = "SMOG", density = 2, cells = 2,
  })
  truthy(#placed >= 1, "SMOG occupies the fight axis")
  truthy(Grid.hasHaze(grid), "haze layer is live")
  truthy(not Grid.pathObstructed(grid, player, enemy),
    "haze is not solid cover — no jump")
  local startU = enemy.padU
  Grid.closeGap(grid, enemy, player)
  truthy(Grid.isHaze(grid, enemy.padU, enemy.padV)
    or math.max(math.abs(enemy.padU - player.padU), math.abs(enemy.padV - player.padV)) > 1,
    "thick smog stalls the charge instead of landing adjacent")
  truthy(enemy.padU ~= startU or Grid.isHaze(grid, enemy.padU, enemy.padV),
    "charger stepped into the cloud")

  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 50,
    _deps = { Grid = Grid, Projectiles = Projectiles },
    _battle = {},
  }
  Cues.tickReturns(session, Grid)
  truthy(enemy._hazeChipped, "walking into smog chips once")
  truthy(enemy._hazeSlow, "gait slows in the cloud")

  Cues.cutLaneHaze(session, "player", Grid, {
    category = "physical", moveId = "BONE_CLUB",
  })
  truthy(not Grid.hasHaze(grid), "Cubone's club clears the lane")
  Grid.closeGap(grid, enemy, player)
  eq(math.max(math.abs(enemy.padU - player.padU), math.abs(enemy.padV - player.padV)),
    1, "after a cut the charge can finish")
end

function tests.ember_leaves_haze_residue_thunderbolt_clears()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = { id = "player", padU = pHome.u, padV = pHome.v }
  local enemy = { id = "enemy", padU = eHome.u, padV = eHome.v }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  Grid.seedHaze(grid, player, enemy, {
    side = "player", moveId = "SMOKESCREEN", density = 2, cells = 1,
  })
  truthy(Grid.hasHaze(grid), "smokescreen is down")
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _deps = { Grid = Grid, Projectiles = Projectiles },
  }
  Cues.cutLaneHaze(session, "enemy", Grid, {
    category = "special", moveId = "EMBER", movePower = 40,
  })
  truthy(Grid.hasHaze(grid), "Ember 40 leaves residue")
  Cues.cutLaneHaze(session, "enemy", Grid, {
    category = "special", moveId = "THUNDERBOLT", movePower = 95,
  })
  truthy(not Grid.hasHaze(grid), "Thunderbolt cuts the haze")
end

function tests.lane_seed_is_a_chance_and_typed()
  eq(Cues.laneKind({ moveId = "SMOG" }), "poison", "Smog is a poison lane")
  eq(Cues.laneKind({
    moveId = "EMBER", moveType = "FIRE", category = "special",
  }, Projectiles), "fire", "Ember can leave fire")
  eq(Cues.laneKind({
    moveId = "WATER_GUN", moveType = "WATER", category = "special",
  }, Projectiles), "water", "Water Gun can leave water")
  eq(Cues.laneKind({
    moveId = "THUNDERBOLT", moveType = "ELECTRIC", category = "special",
  }, Projectiles), nil, "a bolt clashes, it does not puddle")
  eq(Cues.laneKind({
    moveId = "FIRE_PUNCH", moveType = "FIRE", category = "special",
  }, Projectiles), nil, "Fire Punch is CHECK, not a trail")
  eq(Cues.shouldSeedLane({ moveId = "EMBER", moveType = "FIRE",
    category = "special", forceLane = true }, Projectiles), "fire",
    "tests can force a lane")
  eq(Cues.shouldSeedLane({ moveId = "EMBER", moveType = "FIRE",
    category = "special", forceLane = false }, Projectiles), nil,
    "force off skips the roll")
  eq(Cues.shouldSeedLane({
    moveId = "FLAMETHROWER", moveType = "FIRE", category = "special",
  }, Projectiles, function() return 0 end), "fire", "a low roll seeds")
  eq(Cues.shouldSeedLane({
    moveId = "FLAMETHROWER", moveType = "FIRE", category = "special",
  }, Projectiles, function() return 1 end), nil, "a high roll leaves no lane")
end

function tests.haze_sends_idle_mons_home_to_the_trainer()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v,
    homePadU = pHome.u, homePadV = pHome.v,
  }
  local enemy = { id = "enemy", padU = eHome.u, padV = eHome.v }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  Grid.seedHaze(grid, player, enemy, {
    side = "enemy", moveId = "EMBER", kind = "fire", density = 1, cells = 1,
  })
  truthy(Grid.hasHaze(grid), "fire lane is down")
  local hazeU, hazeV = Grid.firstHazeOnPath(grid, player, enemy)
  truthy(hazeU, "the cloud sits on the fight axis")
  truthy(not Grid.isFree(grid, hazeU, hazeV, "wanderer", { id = "wanderer" }),
    "idle roam will not step onto haze")

  truthy(Grid.step(grid, player, 0, 1) or Grid.step(grid, player, 0, -1),
    "stand one cell off the opening")
  local away = math.abs(player.padU - pHome.u) + math.abs(player.padV - pHome.v)
  truthy(away >= 1, "they left home")
  truthy(Grid.idleWander(grid, player, "player", enemy),
    "with a lane down they walk home")
  truthy(math.abs(player.padU - pHome.u) + math.abs(player.padV - pHome.v) < away,
    "home is closer to the trainer pad")
  truthy(not Grid.isHaze(grid, player.padU, player.padV),
    "they did not step onto the cloud")

  truthy(Grid.setPad(grid, player, eHome.u, eHome.v + 1)
      or Grid.setPad(grid, player, eHome.u, eHome.v - 1),
    "stand next to the foe, off the cloud")
  truthy(Grid.withdrawFromFoe(grid, player, enemy, "player"),
    "withdraw with a lane down")
  eq(player.padU, pHome.u, "withdraw goes to the trainer pad, not the FIRE ring")
  eq(player.padV, pHome.v, "withdraw v is the opening home")
end

function tests.lane_hold_expires_and_tiles_loop()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = { id = "player", padU = pHome.u, padV = pHome.v }
  local enemy = { id = "enemy", padU = eHome.u, padV = eHome.v }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  Grid.seedHaze(grid, player, enemy, {
    side = "player", moveId = "EMBER", kind = "fire", density = 1, cells = 1,
    now = 10,
  })
  truthy(Grid.hasHaze(grid), "fire lane is down")
  eq(#Grid.tickHaze(grid, 99), 0, "a live lane does not burn out mid-turn")
  truthy(Grid.hasHaze(grid), "it loops until the turn ends")

  local battle = {}
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _deps = { Grid = Grid, Cues = Cues },
    _battle = battle,
  }
  Lifecycle._testBind(battle, session)
  Lifecycle.onTurnStarted(battle)
  truthy(not Grid.hasHaze(grid), "next turn clears the lane")
  Lifecycle._testUnbind(battle)

  Grid.seedHaze(grid, player, enemy, {
    side = "player", moveId = "SMOG", kind = "poison", density = 2, cells = 1,
  })
  eq(#Grid.tickHaze(grid, 99), 0, "untimed test haze does not expire")
  truthy(Grid.hasHaze(grid), "cut or faint still owns untimed cells")

  local painted = 0
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      setLineWidth = function() end,
      line = function() end,
      rectangle = function() painted = painted + 1 end,
      ellipse = function() painted = painted + 1 end,
      circle = function() painted = painted + 1 end,
      polygon = function() painted = painted + 1 end,
    },
    timer = { getTime = function() return 0.4 end },
  }
  local session = { live = true, grid = grid, _now = 0.4 }
  Projectiles.drawHazeLanes(session, 0, 0)
  truthy(painted > 0, "poison lane paints a looping puff")
  Grid.clearHaze(grid)
  Grid.seedHaze(grid, player, enemy, {
    side = "player", moveId = "EMBER", kind = "fire", density = 1, cells = 1,
  })
  painted = 0
  Projectiles.drawHazeLanes(session, 0, 0)
  truthy(painted > 0, "fire lane paints looping tongues")
  love = prevLove
end

function tests.foe_fire_hit_stops_your_charge()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v,
    play = function(self, kind) self.lastAnim = kind end,
    _pendingCloseStrike = { moveId = "TACKLE" },
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    play = function(self, kind) self.lastAnim = kind end,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local startU, startV = player.padU, player.padV
  local battle = { _arFireNow = true, _arFireNowCharger = "player" }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 40,
    _deps = { Projectiles = Projectiles },
    _battle = battle,
  }
  truthy(Cues.apply(session, "player", "hit", Grid, nil, battle, {
    category = "special", moveId = "PSYCHIC",
  }), "foe FIRE hit cue")
  truthy(not player._pendingCloseStrike, "connecting foe FIRE cancels your charge")
  truthy(player._heavyHit, "you are knocked back")
  eq(player.lastAnim, "tumble", "you take the bolt")
  truthy(player.padU ~= startU or player.padV ~= startV,
    "you leave the charge cell")
end

function tests.fire_now_miss_lets_the_charge_through()
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
    _pendingCloseStrike = { moveId = "TACKLE" },
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local battle = {
    _arFireNow = true,
    _arFireCarryThrough = true,
    kind = "wild",
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 41,
    _deps = { Projectiles = Projectiles },
    _battle = battle,
  }
  player.lastAnim = "idle"
  truthy(Cues.apply(session, "player", "miss", Grid, nil, battle, {
    category = "special", moveId = "WATER_GUN",
  }), "missed FIRE still plays")
  eq(player.lastAnim, "cast", "caster holds the shot pose")
  eq(enemy.lastAnim, nil, "charger does not hop aside")
  truthy(enemy._pendingCloseStrike, "the charge still carries through")

  session.projectiles = nil
  local normal = Projectiles.move(session, "player", {
    category = "special", moveId = "WATER_GUN",
  })
  session.projectiles = nil
  local slow = Projectiles.move(session, "player", {
    category = "special", moveId = "WATER_GUN", slowShot = true,
  })
  truthy(normal and slow, "both shots spawn")
  truthy(slow.duration > normal.duration, "missed FIRE flies slower")
end

function tests.fire_pick_defers_the_shot_off_the_hud()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = { id = "player", padU = pHome.u, padV = pHome.v }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    _pendingCloseStrike = { moveId = "PECK" },
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local battle = {}
  local fired = 0
  battle._arResumeReactPick = function()
    fired = fired + 1
  end
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _battle = battle,
    _now = 0,
  }
  Cues.tickReturns(session, Grid)
  eq(fired, 1, "FIRE shot runs on the present tick, not the HUD click")
  eq(battle._arResumeReactPick, nil, "resume is consumed")
  Cues.tickReturns(session, Grid)
  eq(fired, 1, "resume does not replay")
end

function tests.slower_side_holds_the_call_until_after_incoming()
  local React = assert(loadfile(root .. "/../battle/rules/react.lua"))()
  local slow = { curStats = { speed = 40 }, stats = { speed = 40 } }
  local fast = { curStats = { speed = 90 }, stats = { speed = 90 } }
  truthy(React.playerLikelyGoesSecond({ player = slow, enemy = fast }),
    "lower Speed waits on the incoming")
  truthy(not React.playerLikelyGoesSecond({ player = fast, enemy = slow }),
    "higher Speed still calls first")
  truthy(not React.playerLikelyGoesSecond({ player = fast, enemy = fast }),
    "speed tie still picks first")
  local wait = React.awaitIncomingAction()
  truthy(React.isAwaitIncoming(wait), "FIGHT going second is awaitIncoming")
  truthy(React.spendsQueuedAction("cover"), "COVER spends the slower call")
  truthy(React.spendsQueuedAction("entrench"), "ENTRENCH spends the slower call")
  truthy(React.spendsQueuedAction("fire", { fireNow = true }),
    "FIRE spends the slower call")
  truthy(React.spendsQueuedAction("charge", { chargeNow = true }),
    "CHARGE spends the slower call")
  truthy(not React.spendsQueuedAction("dodge"), "DODGE still gets the delayed call")
  truthy(not React.spendsQueuedAction("brace"), "BRACE still gets the delayed call")
  truthy(not React.spendsQueuedAction("commit"), "COMMIT still gets the delayed call")
  local goingSecond = { player = slow, enemy = fast }
  React.state(goingSecond)
  React.peek(goingSecond).queuedPlayerAction = wait
  truthy(React.counterDefersToLaterCall(goingSecond),
    "going-second proc waits for the later call")
  React.peek(goingSecond).playerActedThisTurn = true
  truthy(not React.counterDefersToLaterCall(goingSecond),
    "already-acted dodge still counters on the incoming")

  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = { id = "player", padU = pHome.u, padV = pHome.v }
  local enemy = { id = "enemy", padU = eHome.u, padV = eHome.v }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local battle = { _arAwaitCallout = true }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _battle = battle,
  }
  truthy(Cues.awaitingCallout(battle), "callout flag is live")
  truthy(Cues.shouldParkEngineQueue(session),
    "engine waits for the slower call")
  battle._arAwaitCallout = nil
  truthy(not Cues.shouldParkEngineQueue(session),
    "callout park clears after the pick")
end

function tests.counter_after_a_miss_always_connects()
  local React = assert(loadfile(root .. "/../battle/rules/react.lua"))()
  local player = { isPlayer = true }
  local enemy = { isPlayer = false }
  local battle = {}
  truthy(not React.isGuaranteedCounterHit(battle, player, enemy),
    "no latch is not a counter")
  React.state(battle)
  local st = React.peek(battle)
  st.mode = "counter"
  truthy(React.isGuaranteedCounterHit(battle, player, enemy),
    "post-miss opening always connects")
  truthy(not React.isGuaranteedCounterHit(battle, enemy, player),
    "foe swings are not guaranteed")
  st.mode = nil
  st.sameTurnCounterStrike = true
  truthy(React.isGuaranteedCounterHit(battle, player, enemy),
    "COUNTER! extra strike always connects")
  st.sameTurnCounterStrike = nil
  battle._arGuaranteedHit = true
  truthy(React.isGuaranteedCounterHit(battle, player, enemy),
    "REACT dodge-counter proc always connects")
  battle._arGuaranteedHit = nil
  battle._arCounterClash = true
  truthy(React.isGuaranteedCounterHit(battle, player, enemy),
    "clash counter always connects")
end

function tests.counter_proc_does_not_play_a_player_miss()
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
  player.lastAnim = "cast"
  local battle = { _arGuaranteedHit = true, _arAccuracyMissSide = "player" }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 80,
    _deps = { Projectiles = Projectiles, UI = UI },
    _battle = battle,
  }
  truthy(Cues.apply(session, "player", "miss", Grid, nil, battle),
    "leftover miss is consumed")
  eq(player.lastAnim, "cast", "counter pose is not replaced by a miss")
  eq(enemy.lastAnim, nil, "the foe does not sidestep the proc")
end

function tests.charge_does_not_proc_a_counter()
  local React = assert(loadfile(root .. "/../battle/rules/react.lua"))()
  local player = { isPlayer = true }
  local enemy = { isPlayer = false }
  local battle = { _arChargeNow = true }
  React.state(battle)
  local st = React.peek(battle)
  st.mode = "counter"
  truthy(not React.isGuaranteedCounterHit(battle, player, enemy),
    "CHARGE is not a counter hit")
  battle._arChargeNow = nil
  battle._arNoCounterThisTurn = true
  truthy(not React.isGuaranteedCounterHit(battle, player, enemy),
    "CHARGE spends the counter for the turn")
  battle._arNoCounterThisTurn = nil
  truthy(React.isGuaranteedCounterHit(battle, player, enemy),
    "without CHARGE an armed opening still counters")
end

function tests.finish_calls_drop_after_a_faint()
  local Dialogue = assert(loadfile(root .. "/../battle/rules/dialogue.lua"))()
  truthy(Dialogue.isFinishCallText("OK, PIKACHU!\nFinish it!"),
    "ok finish-it is a finish shout")
  truthy(Dialogue.isFaintText("Enemy RATTATA\nfainted!"), "faint line")
  local battle = {
    nextInsert = 2,
    current = { text = "PIKACHU! Finish it!" },
    queue = {
      { text = "Enemy RATTATA\nfainted!" },
      { text = "Finish it! PIKACHU! TACKLE!" },
    },
  }
  Dialogue.scrubFinishCalls(battle)
  eq(battle.current, nil, "live finish shout is dropped")
  eq(#battle.queue, 1, "queued finish shout is dropped")
  eq(battle.queue[1].text, "Enemy RATTATA\nfainted!", "faint line stays")
end

function tests.fire_locks_the_react_hud()
  local React = assert(loadfile(root .. "/../battle/rules/react.lua"))()
  React.bind({
    opt = function(key)
      return key == "momentum_counter"
    end,
    pickMode = function()
      return "ALWAYS"
    end,
    playerStatusLocked = function()
      return false
    end,
    foeMoveIsSpecial = function()
      return false
    end,
  })
  local tackle = { id = "TACKLE", power = 40, category = "physical", type = "NORMAL" }
  local battle = {
    player = { mon = { level = 20 } },
    enemy = { mon = { level = 20 } },
  }
  React.state(battle)
  truthy(React.shouldOffer(battle, tackle), "incoming still opens REACT")
  battle._arFireNow = true
  truthy(not React.shouldOffer(battle, tackle),
    "a FIRE shot does not open REACT")
  battle._arFireNow = nil
  React.lockHud(battle)
  truthy(React.isLocked(battle), "FIRE latches the HUD closed")
  truthy(not React.shouldOffer(battle, tackle),
    "after FIRE the HUD stays closed")
  React.reset(battle)
  truthy(not React.isLocked(battle), "the lock clears on the next turn")
  truthy(React.shouldOffer(battle, tackle), "next turn can REACT again")
end

function tests.empty_focus_skips_react_hud()
  local RD = assert(loadfile(root .. "/../battle/rules/reactive_defense.lua"))()
  local battle = {
    player = { stats = { speed = 80, defense = 50, special = 60 } },
    enemy = { stats = { speed = 55, defense = 90, special = 40 } },
  }
  RD.state(battle)
  local side = RD.sideState(battle, true)
  local tackle = { id = "TACKLE", power = 35, category = "physical", type = "NORMAL" }
  side.focus = 0
  local actions = RD.menuActions(battle, tackle)
  eq(#actions, 1, "drained Focus only lists COMMIT")
  eq(actions[1].id, "commit", "the leftover row is COMMIT")
  truthy(not RD.hasReactChoice(battle, tackle),
    "REACT HUD stays closed when only COMMIT remains")
  actions = RD.menuActions(battle, tackle, { canFireNow = true })
  eq(#actions, 1, "FIRE is not listed with empty Focus")
  truthy(not RD.hasReactChoice(battle, tackle, { canFireNow = true }),
    "an unaffordable FIRE window still skips the HUD")
  side.focus = RD.COST.brace
  truthy(RD.hasReactChoice(battle, tackle),
    "enough Focus for Brace opens REACT")
  side.focus = 0
  side.cover = true
  truthy(RD.hasReactChoice(battle, tackle),
    "holding cover is still a pick at 0 Focus")
end

function tests.fire_clashes_with_an_incoming_special()
  local RD = assert(loadfile(root .. "/../battle/rules/reactive_defense.lua"))()
  RD._testRng = function() return 1 end
  local ember = { id = "EMBER", power = 40, category = "special", type = "FIRE" }
  local water = { id = "WATER_GUN", power = 40, category = "special", type = "WATER" }
  truthy(RD.isSpecialClashIncoming(ember), "Ember is a clashable special")
  truthy(not RD.isSpecialClashIncoming({
    id = "TACKLE", power = 35, category = "physical", type = "NORMAL",
  }), "Tackle is not a beam clash")
  truthy(not RD.isSpecialClashIncoming({
    id = "THUNDER_WAVE", power = 0, category = "status", type = "ELECTRIC",
  }), "status shots do not clash")

  local battle = {
    player = { stats = { special = 120, speed = 50 } },
    enemy = { stats = { special = 40, speed = 80 } },
  }
  RD.state(battle)
  local verdict = RD.contestSpecialClash(battle, ember, water)
  eq(verdict, "win", "higher Special shoves the incoming beam")
  local result = RD.resolveIncoming(battle, "fire", nil, {
    user = battle.enemy,
    target = battle.player,
    move = ember,
    replyMove = water,
  })
  eq(result.fireClash, "win", "FIRE vs Ember is a clash win")
  eq(result.forceMiss, true, "incoming beam dies")
  eq(result.fireNowContinue, true, "your shot continues")
  eq(result.chip, "CLASH", "CLASH chip on a beam contest")

  battle = {
    player = { stats = { special = 80, speed = 50 } },
    enemy = { stats = { special = 80, speed = 80 } },
  }
  RD.state(battle)
  verdict = RD.contestSpecialClash(battle, ember, water)
  eq(verdict, "tie", "matched Special deadlocks")
  result = RD.resolveIncoming(battle, "fire", nil, {
    user = battle.enemy,
    target = battle.player,
    move = ember,
    replyMove = water,
  })
  eq(result.fireClash, "tie", "even clash cancels both")
  eq(result.forceMiss, true, "neither full hit lands")
  eq(result.fireNowContinue, false, "your shot dies in the middle")

  battle = {
    player = { stats = { special = 30, speed = 50 } },
    enemy = { stats = { special = 120, speed = 80 } },
  }
  RD.state(battle)
  result = RD.resolveIncoming(battle, "fire", nil, {
    user = battle.enemy,
    target = battle.player,
    move = ember,
    replyMove = water,
  })
  eq(result.fireClash, "lose", "weaker Special loses the push")
  eq(result.forceMiss, false, "theirs continues")
  truthy(result.damageMult < 1, "theirs continues weaker")
  eq(result.fireNowContinue, false, "your shot is spent")

  battle = {
    player = { stats = { special = 40, speed = 50 } },
    enemy = { stats = { special = 120, speed = 80 } },
  }
  RD.state(battle)
  verdict = RD.contestSpecialClash(battle, ember, water, { replySide = "enemy" })
  eq(verdict, "win", "foe FIRE with higher Special shoves your beam")
  verdict = RD.contestSpecialClash(battle, ember, water)
  eq(verdict, "lose", "default contest still treats reply as the player")

  local hydro = { id = "HYDRO_PUMP", power = 120, category = "special", type = "WATER" }
  local bolt = { id = "THUNDERBOLT", power = 95, category = "special", type = "ELECTRIC" }
  battle = {
    player = { stats = { special = 150, speed = 20 } },
    enemy = { stats = { special = 80, speed = 120 } },
  }
  RD.state(battle)
  verdict = RD.contestSpecialClash(battle, hydro, bolt)
  eq(verdict, "win", "slower high-Special Thunderbolt still cuts Hydro Pump")
  battle = {
    player = { stats = { special = 40, speed = 20 } },
    enemy = { stats = { special = 80, speed = 120 } },
  }
  RD.state(battle)
  verdict = RD.contestSpecialClash(battle, hydro, bolt, { replySide = "enemy" })
  eq(verdict, "win", "slower foe FIRE with higher Special still cuts")
  battle = {
    player = { stats = { special = 20, speed = 20 } },
    enemy = { stats = { special = 200, speed = 120 } },
  }
  RD.state(battle)
  verdict = RD.contestSpecialClash(battle, hydro, bolt)
  eq(verdict, "win", "Electric FIRE cuts Water even with lower Special")
  result = RD.resolveIncoming(battle, "fire", nil, {
    user = battle.enemy,
    target = battle.player,
    move = hydro,
    replyMove = bolt,
  })
  eq(result.fireClash, "win", "Electric FIRE clash-wins vs Hydro")
  eq(result.damageMult, RD.FIRE_CAST_MULT, "Electric FIRE keeps the 1.2x shot")
  eq(result.fireShotMult, RD.FIRE_CAST_MULT, "Electric FIRE shot is not clash-nerfed")
  eq(RD.COST.fire, 20, "FIRE spends more Focus")
  RD._testRng = function() return 0 end
  RD.state(battle)
  result = RD.resolveIncoming(battle, "fire", nil, {
    user = battle.enemy,
    target = battle.player,
    move = hydro,
    replyMove = bolt,
  })
  eq(result.fireWhiff, true, "FIRE can go wide")
  eq(result.fireNow, nil, "a whiffed FIRE does not interrupt")
  RD._testRng = function() return 1 end
  RD.clear(battle)

  local React = assert(loadfile(root .. "/../battle/rules/react.lua"))()
  React.bind({
    isFieldBattle = function() return true end,
    playerStatusLocked = function() return false end,
    listFireNowMoves = function()
      return { { moveId = "WATER_GUN", name = "WATER GUN",
        moveInst = { id = "WATER_GUN" } } }
    end,
    isRangedCounter = function(_, opts)
      return tostring(opts.category or ""):lower() == "special"
    end,
    isMeleeAttack = function() return false end,
    chargeWindowOpen = function() return false end,
  })
  local field = { player = { isPlayer = true }, enemy = {} }
  React.state(field)
  truthy(React.canFireNow(field, ember), "FIRE opens vs an incoming special")
  truthy(not React.canFireNow(field, {
    id = "THUNDER_WAVE", power = 0, category = "status", type = "ELECTRIC",
  }), "status shots do not open FIRE")
  React.bind({
    isFieldBattle = function() return true end,
    playerStatusLocked = function() return false end,
    listFireNowMoves = function()
      return { { moveId = "WATER_GUN", name = "WATER GUN",
        moveInst = { id = "WATER_GUN" } } }
    end,
    isRangedCounter = function(_, opts)
      return tostring(opts.category or ""):lower() == "special"
    end,
    isMeleeAttack = function() return false end,
    chargeWindowOpen = function() return false end,
    fireRangeOpen = function() return false end,
  })
  truthy(not React.canFireNow(field, ember),
    "FIRE stays off when they are not two tiles out")

  React.bind({
    isFieldBattle = function() return true end,
    playerStatusLocked = function() return false end,
    listFireNowMoves = function() return {} end,
    listCheckNowMoves = function()
      return { { moveId = "TACKLE", name = "TACKLE", checkNow = true,
        moveInst = { id = "TACKLE" } } }
    end,
    listCloudNowMoves = function() return {} end,
    isRangedCounter = function() return false end,
    isMeleeAttack = function() return true end,
    chargeWindowOpen = function() return true end,
    fireRangeOpen = function() return true end,
  })
  truthy(not React.canFireNow(field, {
    id = "QUICK_ATTACK", power = 40, category = "physical", type = "NORMAL",
  }), "FIRE stays off when the pool has no projectile special")

  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = { id = "player", padU = pHome.u, padV = pHome.v,
    play = function(self, kind) self.lastAnim = kind end }
  local enemy = { id = "enemy", padU = eHome.u, padV = eHome.v,
    play = function(self, kind) self.lastAnim = kind end }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _battle = { kind = "wild" },
    _deps = { Projectiles = Projectiles },
  }
  truthy(Cues.playBeamClash(session, Grid, { fireClash = "tie" }, {
    move = ember,
    replyMove = water,
  }), "beam clash paints")
  eq(player.lastAnim, "cast", "player casts into the clash")
  eq(enemy.lastAnim, "cast", "foe casts into the clash")
  truthy(session._clashPunch, "camera holds the midpoint")
  local styles = {}
  for i = 1, #(session.projectiles or {}) do
    styles[session.projectiles[i].style] = true
  end
  truthy(styles.clash_glow, "clash glow at mid")
  truthy(styles.clash_burst, "beam clash paints a smoke-screen boom")
  local burst
  for i = 1, #(session.projectiles or {}) do
    if session.projectiles[i].style == "clash_burst" then
      burst = session.projectiles[i]
    end
  end
  truthy(burst and (burst.age or 0) < 0, "boom waits until the shots meet")
  truthy(burst and burst.color2, "boom tints both specials")
end

function tests.charge_clashes_with_an_incoming_physical()
  local RD = assert(loadfile(root .. "/../battle/rules/reactive_defense.lua"))()
  local tackle = { id = "TACKLE", power = 35, category = "physical", type = "NORMAL" }
  local scratch = { id = "SCRATCH", power = 40, category = "physical", type = "NORMAL" }
  truthy(RD.isPhysicalClashIncoming(tackle), "Tackle is a physical crash")
  truthy(not RD.isPhysicalClashIncoming({
    id = "EMBER", power = 40, category = "special", type = "FIRE",
  }), "Ember is not a physical crash")
  truthy(not RD.isPhysicalClashIncoming({
    id = "SWIFT", power = 60, category = "physical", type = "NORMAL",
  }), "Swift still flies, so it is not a body crash")

  local battle = {
    player = { stats = { attack = 80, speed = 50 } },
    enemy = { stats = { attack = 80, speed = 80 } },
  }
  RD.state(battle)
  eq(RD.contestPhysicalClash(battle, tackle, scratch, { roll = 0.2 }), "win",
    "low roll is a charge win")
  eq(RD.contestPhysicalClash(battle, tackle, scratch, { roll = 0.8 }), "lose",
    "high roll is a charge lose")
  local result = RD.resolveIncoming(battle, "charge", nil, {
    user = battle.enemy,
    target = battle.player,
    move = tackle,
    replyMove = scratch,
    roll = 0.2,
  })
  eq(result.chargeNow, true, "CHARGE spends this turn's action")
  eq(result.chargeClash, "win", "CHARGE win boosts your crash")
  eq(result.forceMiss, false, "both physicals still land")
  eq(result.damageMult, 1, "incoming stays honest on a win")
  eq(result.chargeShotMult, RD.CHARGE_BOOST, "your crash is +15%")
  eq(result.chip, "CHARGE", "CHARGE chip on a body contest")

  battle = {
    player = { stats = { attack = 40, speed = 50 } },
    enemy = { stats = { attack = 120, speed = 80 } },
  }
  RD.state(battle)
  result = RD.resolveIncoming(battle, "charge", nil, {
    user = battle.enemy,
    target = battle.player,
    move = tackle,
    replyMove = scratch,
    roll = 0.8,
  })
  eq(result.chargeClash, "lose", "CHARGE lose boosts theirs")
  eq(result.damageMult, RD.CHARGE_BOOST, "incoming is +15% on a lose")
  eq(result.chargeShotMult, 1, "your crash stays honest")

  local actions = RD.menuActions(battle, tackle, {
    canChargeNow = true,
    chargeHint = "SCRATCH",
  })
  local ids = {}
  for i = 1, #actions do
    ids[actions[i].id] = actions[i]
  end
  truthy(ids.charge, "CHARGE is on the REACT menu during a physical")
  eq(ids.charge.hint, "SCRATCH", "CHARGE names the locked physical")
  truthy(not ids.entrench, "entrench yields the diamond slot to CHARGE")
  truthy(ids.fire == nil, "FIRE stays off unless the special window is open")

  actions = RD.menuActions(battle, tackle, {
    canFireNow = true,
    canChargeNow = true,
  })
  ids = {}
  for i = 1, #actions do
    ids[actions[i].id] = true
  end
  truthy(ids.fire and ids.charge, "FIRE and CHARGE can sit together")

  local React = assert(loadfile(root .. "/../battle/rules/react.lua"))()
  React.bind({
    isFieldBattle = function() return true end,
    playerStatusLocked = function() return false end,
    listFireNowMoves = function() return {} end,
    listCheckNowMoves = function()
      return { { moveId = "SCRATCH", name = "SCRATCH",
        moveInst = { id = "SCRATCH" } } }
    end,
    isRangedCounter = function(_, opts)
      return tostring(opts and opts.category or ""):lower() == "special"
    end,
    isMeleeAttack = function(_, opts)
      return tostring(opts and opts.category or ""):lower() == "physical"
    end,
    chargeWindowOpen = function() return true end,
    fireRangeOpen = function() return true end,
  })
  local field = { player = { isPlayer = true }, enemy = {} }
  React.state(field)
  truthy(React.canChargeNow(field, tackle), "CHARGE opens vs an incoming physical")
  truthy(not React.canChargeNow(field, {
    id = "EMBER", power = 40, category = "special", type = "FIRE",
  }), "CHARGE stays off vs a special")
  truthy(not React.canFireNow(field, tackle),
    "FIRE stays off when the pool has no projectile special")

  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = { id = "player", padU = pHome.u, padV = pHome.v,
    play = function(self, kind) self.lastAnim = kind end }
  local enemy = { id = "enemy", padU = eHome.u, padV = eHome.v,
    play = function(self, kind) self.lastAnim = kind end }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _battle = { kind = "wild" },
    _deps = { Projectiles = Projectiles },
  }
  truthy(Cues.playChargeClash(session, Grid, { chargeClash = "win" }, {
    move = tackle,
    replyMove = scratch,
  }), "body clash paints")
  eq(player.lastAnim, "attack", "player lunges into the crash")
  eq(enemy.lastAnim, "attack", "foe lunges into the crash")
  truthy(session._clashPunch, "camera holds the midpoint")
  local styles = {}
  for i = 1, #(session.projectiles or {}) do
    styles[session.projectiles[i].style] = true
  end
  truthy(styles.dash_smear, "both charges smear toward mid")
  truthy(styles.clash_burst, "body clash paints a crash boom")
  RD.clear(battle)
end

function tests.dodge_chance_rises_with_defender_health()
  local RD = assert(loadfile(root .. "/../battle/rules/reactive_defense.lua"))()
  local attacker = { stats = { speed = 50 } }
  local full = {
    stats = { speed = 50, hp = 40 },
    mon = { hp = 40, stats = { hp = 40, speed = 50 } },
  }
  local hurt = {
    stats = { speed = 50, hp = 40 },
    mon = { hp = 8, stats = { hp = 40, speed = 50 } },
  }
  local empty = {
    stats = { speed = 50, hp = 40 },
    mon = { hp = 0, stats = { hp = 40, speed = 50 } },
  }
  local unknown = { stats = { speed = 50 } }
  eq(RD.hpRatio(full), 1, "full bar is 1")
  eq(RD.hpRatio(hurt), 0.2, "8/40 is 0.2")
  eq(RD.hpRatio(empty), 0, "empty bar is 0")
  eq(RD.dodgeHealthBonus(full), RD.DODGE_HEALTH_BONUS, "full HP gets the whole bonus")
  eq(RD.dodgeHealthBonus(hurt), RD.DODGE_HEALTH_BONUS * 0.2, "hurt HP scales the bonus")
  eq(RD.dodgeHealthBonus(empty), 0, "empty HP adds nothing")
  eq(RD.dodgeHealthBonus(unknown), 0, "missing HP adds nothing")
  local fresh = RD.dodgeSuccessChance(full, attacker)
  local wounded = RD.dodgeSuccessChance(hurt, attacker)
  local down = RD.dodgeSuccessChance(empty, attacker)
  local base = RD.dodgeSuccessChance(unknown, attacker)
  truthy(fresh > wounded, "full HP dodges more often than 20%")
  truthy(wounded > down, "20% HP still dodges more than empty")
  eq(down, base, "empty HP matches a battler with no HP data")
  eq(fresh, base + RD.DODGE_HEALTH_BONUS,
    "full HP adds DODGE_HEALTH_BONUS on equal speed")
end

function tests.failed_npc_dodge_is_not_a_dodge_cue()
  local Fx = assert(loadfile(root .. "/../battle/fx.lua"))()
  local cue = Fx.foeCoverCue(nil, "BROCK:\nOnix, dodge!")
  eq(cue.kind, "hit", "failed order is not a dodge cue")
  eq(cue.side, "enemy", "fail still belongs to the foe")
  cue = Fx.foeCoverCue(
    { { who = "enemy", stat = "evasion", delta = 1 } },
    "BROCK:\nOnix, dodge!")
  eq(cue.kind, "dodge", "landed evasion is a dodge")
  cue = Fx.foeCoverCue(
    { { who = "enemy", stat = "defense", delta = 1 } },
    "BROCK:\nOnix, brace!")
  eq(cue.kind, "brace", "landed defense is a brace")
  cue = Fx.foeCoverCue(nil, "BROCK:\nAlakazam, now!", {
    kind = "fire", moveId = "PSYCHIC", moveType = "PSYCHIC",
  })
  eq(cue.kind, "cast", "foe FIRE is a cast cue")
  eq(cue.moveId, "PSYCHIC", "FIRE cue names the shot")
  Fx.bind({
    isDodgeFailNarrator = function(text)
      return type(text) == "string" and text:find("too slow", 1, true) ~= nil
    end,
  })
  cue = Fx.foeCoverCue(nil, "...but it was\ntoo slow!")
  eq(cue.kind, "hit", "too-slow narrator is a hit")
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

function tests.asleep_mons_do_not_wander()
  local grid, plan = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v, anim = "idle",
    facing = "up", _wanderCD = 0, wanderTx = 40, wanderTy = 40,
    _battleBattler = { mon = { status = "SLP" } },
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v, anim = "idle",
    facing = "up",
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local battle = {
    game = { overworld = { camera = { x = 0, y = 0 } } },
    animPlaying = false,
  }
  local session = {
    state = Lifecycle.STATE.Live,
    live = true,
    grid = grid,
    plan = plan,
    midX = plan.midX,
    midY = plan.midY,
    playerMon = player,
    enemyMon = enemy,
    _deps = {
      Grid = Grid,
      Cast = { tick = function() end },
      Cues = { pumpCurrent = function() end, tickReturns = function() end },
      Anims = { cache = function() end },
      Projectiles = { tick = function() end },
    },
  }
  Lifecycle._testBind(battle, session)
  Lifecycle.tick(battle, 0.20, session._deps)
  eq(player.facing, "up", "sleep does not snap them to face the foe")
  eq(player.padU, pHome.u, "asleep mon does not wander u")
  eq(player.padV, pHome.v, "asleep mon does not wander v")
  eq(player.wanderTx, nil, "sleep clears a queued wander")
  player._wanderCD = 0
  Lifecycle.tick(battle, 1 / 30, session._deps)
  eq(player.padU, pHome.u, "asleep mon still holds u after cooldown")
  eq(player.padV, pHome.v, "asleep mon still holds v after cooldown")

  player._battleBattler.mon.status = "FRZ"
  local frozenU, frozenV = player.padU, player.padV
  player._wanderCD = 0
  Lifecycle.tick(battle, 1 / 30, session._deps)
  eq(player.padU, frozenU, "frozen mon does not wander u")
  eq(player.padV, frozenV, "frozen mon does not wander v")
  Lifecycle._testUnbind(battle)
end

function tests.asleep_mons_do_not_dodge_a_miss()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local function mon(id, home, status)
    return {
      id = id,
      padU = home.u,
      padV = home.v,
      anim = "idle",
      lastAnim = nil,
      play = function(self, kind)
        self.lastAnim = kind
        self.anim = kind
      end,
      _battleBattler = { mon = { status = status } },
    }
  end
  local player = mon("player", pHome, nil)
  local enemy = mon("enemy", eHome, "SLP")
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 8,
    _deps = { Projectiles = { miss = function() end } },
  }
  local stayU, stayV = enemy.padU, enemy.padV
  truthy(Cues.apply(session, "player", "miss", Grid, nil, nil), "miss vs sleep")
  eq(player.lastAnim, "miss", "attacker still plays miss")
  eq(enemy.lastAnim, nil, "asleep defender does not play dodge")
  eq(enemy.anim, "idle", "asleep defender keeps the sleep stance")
  eq(enemy.padU, stayU, "asleep defender does not hop u")
  eq(enemy.padV, stayV, "asleep defender does not hop v")

  session._lastCueAt = nil
  session._now = 9
  player.lastAnim = nil
  enemy._battleBattler.mon.status = "FRZ"
  enemy.anim = "idle"
  truthy(Cues.apply(session, "player", "miss", Grid, nil, nil), "miss vs freeze")
  eq(enemy.lastAnim, nil, "frozen defender does not play dodge")
  eq(enemy.padU, stayU, "frozen defender does not hop u")
  eq(enemy.padV, stayV, "frozen defender does not hop v")

  session._lastCueAt = nil
  session._now = 10
  player.lastAnim = nil
  enemy.lastAnim = nil
  enemy._battleBattler.mon.status = nil
  enemy.anim = "idle"
  truthy(Cues.apply(session, "player", "miss", Grid, nil, nil), "miss vs awake")
  eq(enemy.lastAnim, "dodge", "awake defender still sidesteps a miss")
end

function tests.idle_mons_face_each_other_diagonally()
  local grid, plan = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v, anim = "idle",
    facing = "right", _kitSheet = true,
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v + 2, anim = "idle",
    facing = "left", _kitSheet = true,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local battle = {
    game = { overworld = { camera = { x = 0, y = 0 } } },
    animPlaying = false,
  }
  local session = {
    state = Lifecycle.STATE.Live,
    live = true,
    grid = grid,
    plan = plan,
    midX = plan.midX,
    midY = plan.midY,
    playerMon = player,
    enemyMon = enemy,
    _deps = {
      Grid = Grid,
      Sprites = Sprites,
      Cast = { tick = function() end },
      Cues = { pumpCurrent = function() end, tickReturns = function() end },
      Anims = { cache = function() end },
      Projectiles = { tick = function() end },
    },
  }
  Lifecycle._testBind(battle, session)
  Lifecycle.tick(battle, 0.20, session._deps)
  eq(player.facing, "down-right", "idle player looks diagonally at an offset foe")
  eq(enemy.facing, "up-left", "idle foe looks back along the same diagonal")
  Lifecycle._testUnbind(battle)
end

function tests.trainers_park_on_the_fight_sideline()
  local grid, plan = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local pT = grid.home.playerTrainer
  local eT = grid.home.enemyTrainer
  truthy(Grid.onFightLine(grid, pHome.u, pHome.v), "player mon sits on the line")
  truthy(Grid.onFightLine(grid, eHome.u, eHome.v), "foe mon sits on the line")
  local gapU = math.floor((pHome.u + eHome.u) / 2)
  local gapV = math.floor((pHome.v + eHome.v) / 2)
  truthy(Grid.onFightLine(grid, gapU, gapV), "the empty cell is the line")
  truthy(not Grid.onFightLine(grid, pT.u, pT.v), "trainer home is behind the line")

  local pu, pv = Grid.trainerWatchPad(grid, "player")
  local eu, ev = Grid.trainerWatchPad(grid, "enemy")
  truthy(pu ~= nil and pv ~= nil, "player trainer has a rim seat")
  truthy(eu ~= nil and ev ~= nil, "foe trainer has a rim seat")
  truthy(not Grid.onFightLine(grid, pu, pv), "player seat is off the corridor")
  truthy(not Grid.onFightLine(grid, eu, ev), "foe seat is off the corridor")
  truthy(not (pu == eu and pv == ev), "trainers do not share a seat")
  local midU = math.floor((pHome.u + eHome.u) / 2)
  local midV = math.floor((pHome.v + eHome.v) / 2)
  local pDist = math.max(math.abs(pu - midU), math.abs(pv - midV))
  local eDist = math.max(math.abs(eu - midU), math.abs(ev - midV))
  truthy(pDist >= (Grid.TRAINER_RIM or 2), "player trainer is on the outer rim")
  truthy(eDist >= (Grid.TRAINER_RIM or 2), "foe trainer is on the outer rim")
  truthy(pDist <= (Grid.TRAINER_RIM or 2) + 1, "player trainer stays in the ~4x4")
  truthy(eDist <= (Grid.TRAINER_RIM or 2) + 1, "foe trainer stays in the ~4x4")

  local function padEnt(home, occId)
    local px, py = Coords.padToPx(grid, home.u, home.v)
    return {
      padU = home.u, padV = home.v,
      px = px, py = py,
      cellX = select(1, Coords.padToWorld(grid, home.u, home.v)),
      cellY = select(2, Coords.padToWorld(grid, home.u, home.v)),
      _arFieldTrainerId = occId,
      facing = "up",
    }
  end
  local player = padEnt(pT, "ar_field_player_trainer")
  local foe = padEnt(eT, "ar_field_enemy_trainer")
  Grid.occupy(grid, player._arFieldTrainerId, player.padU, player.padV)
  Grid.occupy(grid, foe._arFieldTrainerId, foe.padU, foe.padV)
  Grid.occupy(grid, "player", pHome.u, pHome.v)
  Grid.occupy(grid, "enemy", eHome.u, eHome.v)
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
      padU = pHome.u, padV = pHome.v, anim = "idle",
      cellX = plan.pMonX, cellY = plan.pMonY,
    },
    enemyMon = {
      padU = eHome.u, padV = eHome.v, anim = "idle",
      cellX = plan.eMonX, cellY = plan.eMonY,
    },
    _deps = {
      Grid = Grid,
      Cast = { tick = function() end },
      Cues = { pumpCurrent = function() end, tickReturns = function() end },
      Anims = { cache = function() end },
      Projectiles = { tick = function() end },
    },
  }
  Lifecycle._testBind(battle, session)
  for _ = 1, 180 do
    Lifecycle.tick(battle, 1 / 30, session._deps)
  end
  eq(player.padU, pu, "player trainer walks to the rim")
  eq(player.padV, pv, "player trainer v matches the seat")
  eq(foe.padU, eu, "foe trainer walks to the rim")
  eq(foe.padV, ev, "foe trainer v matches the seat")
  truthy(not Grid.onFightLine(grid, player.padU, player.padV),
    "player trainer is not in the middle")
  truthy(not Grid.onFightLine(grid, foe.padU, foe.padV),
    "foe trainer is not in the middle")
  local stillU, stillV = player.padU, player.padV
  for _ = 1, 60 do
    Lifecycle.tick(battle, 1 / 30, session._deps)
  end
  eq(player.padU, stillU, "player trainer stays put after arriving")
  eq(player.padV, stillV, "player trainer does not pace the pad")
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
  eq(grid.sizeU, 5, "opening pad width")
  eq(grid.sizeV, 3, "compact pad height")
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  eq(math.abs(pHome.u - eHome.u), 2, "opening homes leave one empty cell")
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
  -- Opening homes already leave a free cell; the lunge steps into it.
  truthy(Grid.attackStep(grid, p, e), "attack step with room")
  eq(p.padU, homeU + 1, "attack advances on u axis")
  truthy(Grid.returnHome(grid, p), "return after attack")
  eq(p.padU, homeU, "returned u")
  eq(p.padV, homeV, "returned v")
  -- Already adjacent: lunge cannot occupy the foe tile.
  truthy(Grid.setPad(grid, p, eHome.u - 1, eHome.v), "stand next to the foe")
  local adjU, adjV = p.padU, p.padV
  truthy(not Grid.attackStep(grid, p, e), "adjacent attack does not step onto foe")
  eq(p.padU, adjU, "stays put when already adjacent")
  truthy(Grid.setPad(grid, p, homeU, homeV), "reset player to opening home")

  -- Close-the-gap: from farther than one tile, occupy a cell adjacent to the foe.
  truthy(Grid.padDistance(grid, p, e) > 1, "foe is more than a tile away")
  local originU, originV = p.padU, p.padV
  p.homePadU, p.homePadV = originU, originV
  truthy(Grid.closeGap(grid, p, e), "close gap toward the foe")
  eq(Grid.padDistance(grid, p, e), 1, "lands adjacent, not on the foe")
  eq(p._returnU, nil, "close-gap does not stash the opening cell")
  truthy(Grid.withdrawFromFoe(grid, p, e), "withdraw after close-gap")
  local after = Grid.padDistance(grid, p, e)
  truthy(after >= 2, "withdraw leaves the foe's face")
  truthy(after <= 3, "withdraw stops on the FIRE ring, not off the pad")
  eq(p._meleeAnchor, nil, "withdraw does not park idle roam on the foe")
  eq(p.homePadU, originU, "opening home stays the trainer lane")
  eq(p.homePadV, originV, "opening home v stays")
  truthy(p.padU ~= originU or p.padV ~= originV or after == 2,
    "does not snap back to the far opening cell in one jump")
  p._meleeAnchor = nil
  truthy(Grid.setPad(grid, p, eHome.u - 1, eHome.v), "stand next to the foe")
  truthy(Grid.setPad(grid, e, eHome.u, eHome.v), "foe on home")
  truthy(not Grid.closeGap(grid, p, e), "already-adjacent close-gap is a no-op")
  local closeU, closeV = p.padU, p.padV
  local hopped = Grid.openGap(grid, p, e)
  truthy(hopped and hopped >= 1, "adjacent caster hops away")
  truthy(Grid.padDistance(grid, p, e) > 1, "open-gap leaves melee")
  truthy(Grid.padDistance(grid, p, e) <= 3, "open-gap stays on the pad")
  truthy(p.padU ~= closeU or p.padV ~= closeV, "occupancy actually moved")
  eq(Grid.openGap(grid, p, e), false, "already spaced: open-gap is a no-op")

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
  eq(enemy.lastAnim, "tumble", "heavy hit animation")
  truthy(enemy._heavyHit, "heavy hit flag set for sprite knockback")
  eq(enemy.padU, startU + 1, "powerful hit pushes one tile before rock")
  eq(#(session.projectiles or {}), 3, "power hit + wall impact + ground kick")
  local styles = {}
  for i = 1, #(session.projectiles or {}) do
    styles[session.projectiles[i].style] = true
  end
  truthy(styles.power_hit, "typed burst on the mon")
  truthy(styles.power_impact, "impact burst at the obstacle")
  truthy(styles.ground_kick, "knockback kicks up the tile underfoot")

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
  truthy(weakStyles.ground_kick, "weak hit still kicks up the tile underfoot")
  truthy(not weakStyles.power_hit, "weak hit does not use the heavy burst")
  truthy((session._hitStopT or 0) > 0, "contact freezes a few frames")
  truthy((session._camShakeT or 0) > 0, "contact bumps the camera")
  truthy((session._clashSlowT or 0) > 0 and (session._clashSlowT or 0) < 0.45,
    "regular hit gets a short punch-in, not a clash hold")
  truthy(session.cameraNudgeX ~= nil and session.cameraNudgeY ~= nil,
    "regular hit punches the camera in")

  Projectiles.clear(session)
  enemy.padU = 4
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  enemy._heavyHit = nil
  enemy.lastAnim = nil
  session._clashSlowT = nil
  session._clashPunch = nil
  truthy(Cues.apply(session, "enemy", "hit", Grid, nil, nil, {
    moveId = "EMBER",
    movePower = 40,
    moveType = "FIRE",
    category = "special",
    push = false,
  }), "regular special hit cue")
  eq(enemy.lastAnim, "hit", "special still plays a flinch")
  local specialStyles = {}
  for i = 1, #(session.projectiles or {}) do
    specialStyles[session.projectiles[i].style] = true
  end
  truthy(specialStyles.light_hit, "special hit still sparks on the target")
  truthy(specialStyles.special_impact, "special hit paints a land burst")
  truthy(specialStyles.ground_kick, "special hit still kicks the tile")
  truthy(not specialStyles.power_hit, "regular special is not the heavy burst")
  truthy((session._clashSlowT or 0) >= 0.20 and (session._clashSlowT or 0) < 0.45,
    "special punch-in is longer than a physical, shorter than a clash")

  Projectiles.clear(session)
  enemy.padU = 4
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  enemy._heavyHit = nil
  enemy.lastAnim = nil
  session._clashSlowT = nil
  session._clashPunch = nil
  truthy(Cues.apply(session, "enemy", "hit", Grid, nil, nil, {
    moveId = "TACKLE",
    movePower = 35,
    moveType = "NORMAL",
    category = "physical",
    crit = true,
  }), "critical hit cue")
  eq(enemy.lastAnim, "tumble", "crit still flinches")
  truthy(enemy._heavyHit, "crit knocks like a heavy hit")
  local critStyles = {}
  for i = 1, #(session.projectiles or {}) do
    critStyles[session.projectiles[i].style] = true
  end
  truthy(critStyles.crit, "crit paints a comic starburst")
  truthy(critStyles.ground_kick, "crit kicks up the tile underfoot")
  truthy(not critStyles.light_hit, "crit replaces the light spark")
  truthy(not critStyles.power_hit, "crit uses the starburst, not the typed ring")
end

function tests.counter_clash_punches_in()
  local plan = Layout.plan(0, 0, 8, 0)
  local grid = Grid.build({
    pad = Coords.layoutPad({ minX = 0, maxX = 8, minY = -1, maxY = 1 }, 1, 0),
  }, plan)
  local player = {
    id = "player", padU = 2, padV = 0,
    play = function(self, kind) self.lastAnim = kind end,
  }
  local enemy = {
    id = "enemy", padU = 4, padV = 0,
    play = function(self, kind) self.lastAnim = kind end,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 40,
    _battle = { kind = "wild" },
    _deps = { Projectiles = Projectiles },
  }
  truthy(Cues.apply(session, "player", "counter", Grid, nil, nil, {
    category = "physical", moveId = "SCRATCH",
  }), "counter cue")
  eq(player.lastAnim, "counter", "attacker plays the rebound pose")
  truthy(session._clashPunch, "camera punch-in is armed")
  truthy((session._clashSlowT or 0) >= 0.7, "present clock holds a real slow-mo beat")
  truthy(session.cameraNudgeX ~= nil and session.cameraNudgeY ~= nil,
    "nudge sits on the clash midpoint")
  local styles = {}
  for i = 1, #(session.projectiles or {}) do
    styles[session.projectiles[i].style] = true
  end
  truthy(styles.power_hit, "clash paints the power_hit ring")
  truthy(styles.clash_glow, "clash rims the mons with glow")
  truthy(styles.clash_trail, "clash paints hair trails")

  truthy(Cues.apply(session, "enemy", "hit", Grid, nil, nil, {
    category = "physical", clash = true, push = true,
  }), "clash hit cue")
  eq(enemy.lastAnim, "tumble", "foe takes the clash")
  truthy(enemy._heavyHit, "clash knock is heavy")
end

function tests.finishing_blow_plays_the_clash()
  truthy(not Cues.isFinishingBlow(
    { isPlayer = true },
    { isPlayer = false, mon = { hp = 12 } }
  ), "a living foe is not a finisher")
  truthy(not Cues.isFinishingBlow(
    { isPlayer = true },
    { isPlayer = false, mon = { hp = 0 } }
  ), "a fainted foe does not play the finish clash")
  truthy(not Cues.isFinishingBlow(
    { isPlayer = false },
    { isPlayer = true, mon = { hp = 0 } }
  ), "the foe KOing you is not your finisher")
  truthy(not Cues.isFinishingBlow(
    { isPlayer = true },
    { isPlayer = false, mon = { hp = 0 }, _fainting = true }
  ), "an in-progress faint is not a finisher")
end

function tests.brace_counter_waits_for_the_incoming_hit()
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
  local battle = {
    _arPendingBraceCounter = {
      category = "physical", moveId = "TACKLE", moveType = "NORMAL",
    },
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 90,
    _deps = { Projectiles = Projectiles },
    _battle = battle,
  }
  Cues.tickBraceCounter(session, Grid)
  eq(player.lastAnim, nil, "brace-counter does not clash on the pick")
  truthy(Cues.shouldParkEngineQueue(session), "engine waits for the rebound")
  Cues.apply(session, "player", "hit", Grid, nil, battle, {
    category = "physical", moveId = "SCRATCH",
  })
  eq(player.lastAnim, "hit", "incoming hit still plays")
  Cues.tickBraceCounter(session, Grid)
  eq(player.lastAnim, "hit", "clash waits a beat after contact")
  session._now = 90.4
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, "counter", "rebound plays after the hit")
  eq(battle._arPendingBraceCounter, nil, "pending brace-counter clears")
  truthy(not Cues.shouldParkEngineQueue(session), "engine resumes after the clash")
end

function tests.clash_letterbox_spans_world_view()
  local w, h, edge, alpha = Lifecycle.clashLetterboxSize(320, 288)
  eq(w, 320, "vignette is as wide as the world canvas")
  eq(h, 288, "vignette uses the world canvas height")
  truthy(edge >= 32, "edge fade has real depth")
  truthy(alpha > 0.4 and alpha < 0.6, "fade is a soft veil, not a cinema crop")
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

function tests.idle_gait_slows_with_bulk()
  eq(Cast.idleStepSpeed({}), Cast.STEP_SPEED, "unknown mons keep the default walk")
  local pidgey = Cast.idleStepSpeed({
    _closeGapStats = { hp = 40, defense = 30, speed = 56 },
    _dexWeightLbs = 4,
  })
  local gengar = Cast.idleStepSpeed({
    _closeGapStats = { hp = 60, defense = 60, speed = 110 },
    _dexWeightLbs = 89,
  })
  local onix = Cast.idleStepSpeed({
    _closeGapStats = { hp = 35, defense = 160, speed = 70 },
    _dexWeightLbs = 463,
  })
  local snorlax = Cast.idleStepSpeed({
    _closeGapStats = { hp = 160, defense = 65, speed = 30 },
    _dexWeightLbs = 1014,
  })
  local fromDex = Cast.idleStepSpeed({
    _battleBattler = {
      def = {
        baseStats = { hp = 160, defense = 65, speed = 30 },
        dexEntry = { weight = 10141 },
      },
    },
  })
  truthy(pidgey > Cast.STEP_SPEED, "light mons wander faster")
  truthy(snorlax < Cast.STEP_SPEED, "snorlax lumbers home")
  truthy(snorlax < onix, "snorlax is heavier than onix")
  truthy(gengar > onix, "gengar is lighter than onix")
  truthy(snorlax >= 28, "tanks still reach home")
  truthy(math.abs(fromDex - snorlax) < 0.5, "dex tenths-of-a-pound maps to lbs")
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
  truthy(rocket <= 130, "dash speed is capped")
  truthy(snorlax >= 52, "even slow mons still close")

  local brawler = Cues.keepAwayBias({ _closeGapStats = { special = 40, defense = 110 } })
  local glass = Cues.keepAwayBias({ _closeGapStats = { special = 135, defense = 50 } })
  truthy(brawler < 0.15, "high def low spa stays in the foe's face")
  truthy(glass > 0.7, "high spa low def prefers space")
  local red = Cues.keepAwayBias({
    _closeGapStats = { special = 40, defense = 110 },
    _battleBattler = { mon = { hp = 12, stats = { hp = 80 } } },
  })
  truthy(red >= 0.85, "red HP wants space even on a brawler")
  local yellow = Cues.keepAwayBias({
    _closeGapStats = { special = 40, defense = 110 },
    _battleBattler = { mon = { hp = 40, stats = { hp = 80 } } },
  })
  truthy(yellow < 0.15, "yellow HP does not force keep-away")
  eq(Cues.hpRatio({ _hpRatio = 0.19 }), 0.19, "hurt ratio hook")
  truthy(Cues.keepAwayBias({ _hpRatio = 0.19 }) >= 0.85,
    "explicit red HP ratio wants space")
  local cruise = Cues.closeGapSpeed({ _closeGapStats = { speed = 80, attack = 90 } })
  local charger = { _closeGapStats = { speed = 80, attack = 90, special = 40, defense = 80 } }
  local foe = { basePx = 80, basePy = 0 }
  charger.basePx, charger.basePy = 0, 0
  local battle = {
    player = {
      curMoves = { { id = "WATER_GUN", pp = 25, power = 40, category = "special" } },
    },
    data = {
      moves = {
        WATER_GUN = { id = "WATER_GUN", power = 40, category = "special", type = "WATER" },
      },
    },
  }
  truthy(Cues.battlerHasFireSpecial(battle, battle.player, Projectiles),
    "water gun is a fireable special")
  charger._pendingCloseStrike = { moveId = "TACKLE" }
  local slow = Cues.armCloseGapGait(charger, battle, "enemy", foe, {
    Projectiles = Projectiles, rand = 0.4, now = 1,
  })
  truthy(slow < cruise * 0.55, "foe winds up slower when you can FIRE NOW")
  truthy(slow > cruise * 0.22, "FIRE NOW wind-up is not a crawl")
  charger.basePx = 70
  local later = Cues.tickCloseGapGait(charger, foe)
  truthy(later > slow, "close-gap speeds up as they draw in")
  truthy(later <= cruise + 0.01, "close-gap does not pass cruise speed")
  local noSpecial = { _closeGapStats = { speed = 80, attack = 90 } }
  noSpecial.basePx, noSpecial.basePy = 0, 0
  local emptyBattle = { player = { curMoves = { { id = "TACKLE", pp = 35, power = 35, category = "physical" } } } }
  local normal = Cues.armCloseGapGait(noSpecial, emptyBattle, "enemy", foe, {
    Projectiles = Projectiles, rand = 0.4, now = 1,
  })
  truthy(normal > slow, "no special means the charge does not crawl")
  eq(noSpecial._closeGapMinAt, nil, "no fire window does not hold the punch")

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
  truthy(after >= 2, "post-strike recover leaves the foe's face")
  truthy(after <= 3, "post-strike recover stays on the FIRE ring")
  eq(player.padU == 1, false, "does not snap back to the opening cell")
  eq(player._meleeAnchor, nil, "idle roam does not follow the foe after the strike")
  eq(player._withdrawAfterStrike, nil, "withdraw flag clears")

  Grid.setPad(grid, player, 6, 0)
  player.homePadU, player.homePadV = 1, 0
  local stuck = Grid.padDistance(grid, player, enemy)
  eq(stuck, 1, "healthy physical starts adjacent")
  truthy(Grid.idleWander(grid, player, "player", enemy),
    "idle roam steps when off the opening lane")
  truthy(Grid.padDistance(grid, player, enemy) > stuck,
    "healthy physical walks back toward the trainer lane, not the foe")

  Grid.setPad(grid, player, 6, 0)
  player.homePadU, player.homePadV = 1, 0
  player._keepAway = 0.85
  local near = Grid.padDistance(grid, player, enemy)
  eq(near, 1, "hurt test starts adjacent")
  truthy(Grid.idleWander(grid, player, "player", enemy),
    "red HP roam still steps")
  truthy(Grid.padDistance(grid, player, enemy) > near,
    "red HP steps out of the foe's face")
  Grid.setPad(grid, player, 1, 0)
  player.homePadU, player.homePadV = 1, 0
  player._keepAway = 0.85
  local hurtFar = Grid.padDistance(grid, player, enemy)
  Grid.idleWander(grid, player, "player", enemy)
  truthy(Grid.padDistance(grid, player, enemy) >= 2,
    "red HP does not close from the lane into melee")
  truthy(Grid.padDistance(grid, player, enemy) <= hurtFar,
    "red HP stays on the trainer's side of the pad")

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
  eq(player.lastAnim, nil, "adjacent cue does not punch on HUD confirm")
  truthy(player._pendingCloseStrike, "adjacent strike is still gated")
  truthy(not player._closeStrikeWait, "already in reach: skip the walk-first tick")
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
  eq(enemy.lastAnim, "tumble", "foe plays the hit")
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

function tests.adjacent_special_backsteps_then_fires()
  local grid = sampleGrid()
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = eHome.u - 1, padV = eHome.v,
    facing = "right",
    play = function(self, kind) self.lastAnim = kind end,
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    play = function(self, kind) self.lastAnim = kind end,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local startDist = Grid.padDistance(grid, player, enemy)
  eq(startDist, 1, "setup: caster is in the foe's face")
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 20,
    _battle = { kind = "wild" },
    _deps = { Projectiles = Projectiles },
  }
  Projectiles.clear(session)
  truthy(Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "special", moveId = "WATER_GUN", moveType = "WATER",
  }), "adjacent special cue")
  truthy(player._pendingRangedCast, "backstep is armed")
  truthy(Grid.padDistance(grid, player, enemy) > 1, "caster stepped away")
  eq(#(session.projectiles or {}), 0, "shot waits for the charge")
  truthy(Cues.shouldParkEngineQueue(session), "engine waits for the backstep")
  player.basePx, player.basePy = player.targetPx, player.targetPy
  Cues.tickReturns(session, Grid)
  truthy(player.lastAnim == "charge" or player.lastAnim == "cast",
    "caster turns and charges")
  eq(#(session.projectiles or {}), 0, "charge hold is not the shot")
  truthy(not Cues.shouldParkEngineQueue(session),
    "in-place charge leaves the queue free for REACT")
  session._now = 20 + (Cues.RANGED_CHARGE or 1.5)
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, "cast", "then the shot pose plays")
  truthy(#(session.projectiles or {}) >= 1, "water gun leaves after the charge")
  truthy(not player._pendingRangedCast, "pending backstep is cleared")
  truthy(not Cues.shouldParkEngineQueue(session), "engine resumes after the shot")
  truthy(Cues.rangedShotHoldActive(session), "HP waits for the water gun to land")
end

function tests.spaced_special_charges_before_the_shot()
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
  local startDist = Grid.padDistance(grid, player, enemy)
  truthy(startDist > 1, "setup: caster already has room")
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 40,
    _battle = { kind = "wild" },
    _deps = { Projectiles = Projectiles },
  }
  Projectiles.clear(session)
  local stayU, stayV = player.padU, player.padV
  truthy(Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "special", moveId = "THUNDERBOLT", moveType = "ELECTRIC",
  }), "spaced special cue")
  eq(player.padU, stayU, "already-spaced caster does not hop")
  eq(player.padV, stayV, "already-spaced caster keeps V")
  truthy(player._pendingRangedCast, "in-place wind-up is armed")
  truthy(player.lastAnim == "charge" or player.lastAnim == "cast",
    "charge pose starts immediately")
  eq(#(session.projectiles or {}), 0, "shot waits out the wind-up")
  truthy(not Cues.shouldParkEngineQueue(session),
    "REACT can open during the 0.7s charge")
  truthy(Cues.shouldHoldEngineHit(session, { user = { isPlayer = true } }),
    "the player's own HP tick still waits for the beam")
  truthy(not Cues.shouldHoldEngineHit(session, { user = { isPlayer = false } }),
    "an incoming special reaches runDamaging so REACT can open")
  truthy(Cues.shouldHoldApplyDamage(session, session._battle, { isPlayer = false }),
    "foe HP stays up during the charge")
  session._now = 40.35
  Cues.tickReturns(session, Grid)
  eq(#(session.projectiles or {}), 0, "mid-charge is still charging")
  session._now = 40 + (Cues.RANGED_CHARGE or 1.5)
  Cues.tickReturns(session, Grid)
  truthy(#(session.projectiles or {}) >= 1, "thunderbolt leaves after 0.7s")
  truthy(not player._pendingRangedCast, "wind-up clears after the shot")
  truthy(Cues.rangedShotHoldActive(session), "HP still waits while the bolt travels")
  truthy(Cues.shouldHoldApplyDamage(session, session._battle, { isPlayer = false }),
    "foe HP stays up until impact")
  session._battle._arCloseGapApply = { { "foe", 5 } }
  truthy(not Cues.flushHeldHit(session, session._battle),
    "a present tick does not apply HP mid-flight")
  truthy(session._battle._arCloseGapApply, "stashed HP stays put while the bolt is up")
  Projectiles.tick(session, 2)
  truthy(not Cues.rangedShotHoldActive(session), "impact releases the HP hold")
  eq(session._battle._arCloseGapApply, nil, "impact consumes the stashed HP")
end

function tests.special_hit_waits_until_the_bolt_lands()
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
    _now = 42,
    _battle = { kind = "wild" },
    _deps = { Projectiles = Projectiles, Grid = Grid },
  }
  Projectiles.clear(session)
  truthy(Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "special", moveId = "THUNDERBOLT", moveType = "ELECTRIC",
  }), "spaced special cue")
  truthy(Cues.shouldHoldHitCue(session, { user = { isPlayer = true } }),
    "knockback waits out the charge")
  truthy(Cues.holdCloseHit(session, "enemy", {
    category = "special", moveId = "THUNDERBOLT",
  }), "damage_dealt during the charge is stashed")
  eq(enemy.lastAnim, nil, "no contact beat during the wind-up")
  session._now = 42 + (Cues.RANGED_CHARGE or 0.7)
  Cues.tickReturns(session, Grid)
  eq(enemy.lastAnim, nil, "no contact beat when the bolt leaves")
  truthy(Cues.shouldHoldHitCue(session, { user = { isPlayer = true } }),
    "knockback still waits while the bolt travels")
  Projectiles.tick(session, 2)
  truthy(enemy.lastAnim == "hit" or enemy.lastAnim == "tumble",
    "contact beat plays when the bolt lands")
end

function tests.fire_now_does_not_backstep()
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
    _pendingCloseStrike = { moveId = "TACKLE" },
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  eq(Grid.padDistance(grid, player, enemy), 2, "FIRE window is two tiles")
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 30,
    _battle = { kind = "wild", _arFireNow = true },
    _deps = { Projectiles = Projectiles },
  }
  Projectiles.clear(session)
  local stayU, stayV = player.padU, player.padV
  truthy(Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "special", moveId = "THUNDERBOLT", moveType = "ELECTRIC",
    fireNow = true,
  }), "FIRE NOW cue")
  eq(player.padU, stayU, "FIRE NOW does not hop off the ring")
  eq(player.padV, stayV, "FIRE NOW keeps the same pad V")
  truthy(not player._pendingRangedCast, "FIRE NOW does not arm a backstep")
  truthy(#(session.projectiles or {}) >= 1, "the shot leaves immediately")
  truthy(Cues.rangedShotHoldActive(session), "FIRE NOW still holds HP until impact")

  -- Occupancy already adjacent because the charger jumped the close-gap cell.
  Grid.setPad(grid, enemy, pHome.u + 1, pHome.v)
  eq(Grid.padDistance(grid, player, enemy), 1, "charger occupancy is in the face")
  Projectiles.clear(session)
  stayU, stayV = player.padU, player.padV
  truthy(Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "special", moveId = "THUNDERBOLT", moveType = "ELECTRIC",
    fireNow = true,
  }), "FIRE NOW while occupancy is melee")
  eq(player.padU, stayU, "still no hop when the charger is on the next cell")
  eq(player.padV, stayV, "still no hop V")
  truthy(not player._pendingRangedCast, "charge occupancy does not force a backstep")
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

function tests.special_shot_paints_land_impact()
  local grid = sampleGrid()
  local player = {
    id = "player", padU = grid.home.player.u, padV = grid.home.player.v,
    px = 16, py = 32,
  }
  local enemy = {
    id = "enemy", padU = grid.home.enemy.u, padV = grid.home.enemy.v,
    px = 96, py = 40,
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _battle = { kind = "wild" },
  }
  Projectiles.clear(session)
  local bolt = Projectiles.move(session, "player", {
    category = "special", moveType = "ELECTRIC", moveId = "THUNDERBOLT",
  })
  truthy(bolt, "special shot spawned")
  Projectiles.tick(session, (bolt.duration or 0.3) + 0.02)
  local burst
  for i = 1, #(session.projectiles or {}) do
    local p = session.projectiles[i]
    if p.style == "special_impact" then
      burst = p
    end
  end
  truthy(burst, "landing a special paints an impact burst")
  eq(burst.sx, bolt.ex, "burst sits on the target")
  eq(burst.sy, bolt.ey, "burst uses the landing height")
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
  -- Opening homes already leave a free cell for the physical lunge.
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
  player.basePx, player.basePy = player.targetPx, player.targetPy
  player._pendingRangedCast = nil
  player._rangedChargeAt = nil
  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil, {
    category = "physical",
    moveType = "GHOST",
    moveId = "NIGHT_SHADE",
  }), "night shade attack cue")
  truthy(player.lastAnim == "charge" or player.lastAnim == "cast",
    "night shade charges in place")
  truthy(not player._attackStepped, "night shade does not lunge")
  eq(#(session.projectiles or {}), 0, "night shade waits out the wind-up")
  session._now = 12.5 + (Cues.RANGED_CHARGE or 1.5)
  Cues.tickReturns(session, Grid)
  eq(#(session.projectiles or {}), 1, "night shade spawns shadow projectile")
  eq(session.projectiles[1].style, "shadow", "night shade shadow style from cue")

  session._now = (session._lastCueAt or session._now) + 1.26
  truthy(not Cues.shouldSkipEvent(session, "player", "attack"), "dedupe expires")
  -- Same named special stays locked past the toast window (issue #3).
  session._now = 16
  session._lastCueAt = nil
  player.lastAnim = nil
  player._pendingRangedCast = nil
  player._rangedChargeAt = nil
  Projectiles.clear(session)
  Grid.setPad(grid, player, pHome.u, pHome.v)
  player.basePx, player.basePy = player.targetPx, player.targetPy
  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil, {
    category = "special",
    moveType = "PSYCHIC",
    moveId = "PSYCHIC",
  }), "psychic attack cue")
  eq(#(session.projectiles or {}), 0, "psychic waits out the wind-up")
  session._now = 16 + (Cues.RANGED_CHARGE or 1.5)
  Cues.tickReturns(session, Grid)
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

  session._now = 14.05
  session._lastCueAt = nil
  player.lastAnim = nil
  truthy(Cues.apply(session, "player", "miss", Grid, nil, nil), "miss cue")
  eq(player.lastAnim, "miss", "accuracy miss plays a slip-past")
  eq(enemy.lastAnim, "dodge", "the target sidesteps a miss")
  truthy(Cues.shouldSkipEvent(session, "player", "miss"), "dedupe miss")

  session._now = 14.2
  session._lastCueAt = nil
  enemy.lastAnim = nil
  player.lastAnim = nil
  truthy(Cues.apply(session, "enemy", "dodge", Grid, nil, nil), "foe dodge cue")
  eq(enemy.lastAnim, "dodge", "foe dodge animation")
  truthy(Cues.shouldSkipEvent(session, "enemy", "dodge"),
    "same-beat foe dodge does not replay")
  truthy(not Cues.shouldSkipEvent(session, "player", "dodge"),
    "player may still dodge after the foe does")

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

function tests.multi_hit_replays_each_strike()
  truthy(Cues.isMultiHitMove("PIN_MISSILE"), "pin missile is multi-hit")
  truthy(Cues.isMultiHitMove("DOUBLE_KICK"), "double kick is multi-hit")
  truthy(Cues.isMultiHitMove({ id = "FURY_ATTACK", multiHit = { 2, 2, 3, 3, 4, 5 } }),
    "engine multiHit list counts")
  truthy(Cues.isMultiHitMove({ id = "TWINEEDLE", multiHit = 2 }),
    "fixed two-hit record counts")
  truthy(not Cues.isMultiHitMove("TACKLE"), "tackle is a single strike")
  truthy(not Cues.isEngineMoveAnim("POOF_ANIM"), "send-out poof is not a move strike")
  truthy(Cues.isEngineMoveAnim("COMET_PUNCH"), "comet punch anim is a move strike")

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
    closeTheGap = true,
    _now = 30,
    _deps = { Projectiles = Projectiles },
    _battle = { queue = {} },
  }
  session._battle.queue = {}

  truthy(Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "physical", moveId = "PIN_MISSILE", moveType = "BUG",
  }), "first pin missile cue")
  truthy(session._arSkipEngineStrike, "first swing skips the engine hit-1 anim")
  truthy(Cues.shouldSkipEvent(session, "player", "attack", { moveId = "PIN_MISSILE" }),
    "duplicate announce still dedupes")
  truthy(not Cues.shouldSkipEvent(session, "player", "attack", {
    moveId = "PIN_MISSILE", followUp = true,
  }), "follow-up strikes are not deduped")

  Cues.tickReturns(session, Grid)
  player.basePx, player.basePy = player.targetPx, player.targetPy
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, "attack", "first strike punches")
  local punchU = player.padU
  player.lastAnim = nil
  enemy.lastAnim = nil
  Projectiles.clear(session)

  session._battle.queue = {
    { anim = "PIN_MISSILE", attackerIsPlayer = true },
  }
  eq(Cues.pumpFollowUpAnims(session, session._battle, Grid, nil), false,
    "engine hit-1 anim does not replay the first punch")
  eq(player.lastAnim, nil, "no extra attack on hit 1")
  eq(session._battle.queue[1]._arFieldFollowUpDone, true, "hit-1 row is consumed")

  session._battle.queue = {
    { anim = "PIN_MISSILE", attackerIsPlayer = true },
  }
  session._now = 30.5
  truthy(Cues.pumpFollowUpAnims(session, session._battle, Grid, nil),
    "engine hit-2 anim replays the strike")
  eq(player.lastAnim, "attack", "follow-up plays another attack")
  eq(enemy.lastAnim, "hit", "follow-up shows the foe getting hit")
  eq(player.padU, punchU, "follow-up does not close the gap again")
  eq(#(session.projectiles or {}) > 0, true, "follow-up spawns contact FX")

  session._battle.queue = {
    { anim = "PIN_MISSILE", attackerIsPlayer = true },
  }
  session._now = 30.9
  player._returnAt = session._now
  player._withdrawAfterStrike = true
  Cues.tickReturns(session, Grid)
  eq(player._withdrawAfterStrike, true, "withdraw waits until the combo ends")
  truthy(player._returnAt > session._now, "return is deferred for remaining hits")
end

function tests.flush_held_hit_skips_react_wrap()
  local calls = { react = 0, engine = 0 }
  local engine = function()
    calls.engine = calls.engine + 1
  end
  local react = function()
    calls.react = calls.react + 1
  end
  local prev = package.loaded["src.battle.EffectRegistry"]
  package.loaded["src.battle.EffectRegistry"] = {
    runDamaging = react,
    _arReactRunDamaging = react,
    _arVanillaRunDamaging = engine,
    _arEngineRunDamaging = engine,
  }
  local battle = {}
  battle._arCloseGapDamage = { ctx = { move = { id = "SCRATCH" } }, record = {} }
  local session = { live = true, playerMon = {}, enemyMon = {}, _battle = battle }
  Cues.flushHeldHit(session, battle)
  eq(calls.react, 0, "flush does not re-enter the React wrap")
  eq(calls.engine, 1, "flush resumes engine / vanilla damage")
  package.loaded["src.battle.EffectRegistry"] = prev
end

function tests.flush_held_hit_replays_multi_hit_list()
  local calls = { engine = 0 }
  local engine = function()
    calls.engine = calls.engine + 1
  end
  local prev = package.loaded["src.battle.EffectRegistry"]
  package.loaded["src.battle.EffectRegistry"] = {
    runDamaging = engine,
    _arReactRunDamaging = function() end,
    _arVanillaRunDamaging = engine,
    _arEngineRunDamaging = engine,
  }
  local battle = {}
  battle._arCloseGapDamage = {
    { ctx = { move = { id = "FURY_ATTACK" } }, record = { n = 1 } },
    { ctx = { move = { id = "FURY_ATTACK" } }, record = { n = 2 } },
    { ctx = { move = { id = "FURY_ATTACK" } }, record = { n = 3 } },
  }
  local session = { live = true, playerMon = {}, enemyMon = {}, _battle = battle }
  Cues.flushHeldHit(session, battle)
  eq(calls.engine, 3, "flush replays each held multi-hit runDamaging")
  eq(battle._arCloseGapDamage, nil, "held list is consumed")
  package.loaded["src.battle.EffectRegistry"] = prev
end

function tests.hit_does_not_replay_close_gap_attack()
  -- Punch → damage_dealt hit used to flip _lastCueSide, so the Scratch
  -- announce toast re-armed close-the-gap and crashed into Fury Attack.
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
    closeTheGap = true,
    _now = 40,
    _deps = { Projectiles = Projectiles },
    _battle = { queue = {} },
  }
  truthy(Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "physical", moveId = "SCRATCH", moveType = "NORMAL",
  }), "scratch walk starts")
  Cues.tickReturns(session, Grid)
  player.basePx, player.basePy = player.targetPx, player.targetPy
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, "attack", "scratch punches")
  eq(player._closeStruckMoveId, "SCRATCH", "punch latches the move")
  truthy(not player._pendingCloseStrike, "pending strike is cleared")

  Cues.apply(session, "enemy", "hit", Grid, nil, session._battle, {
    category = "physical", moveId = "SCRATCH", moveType = "NORMAL", push = false,
  })
  eq(session._lastCueSide, "enemy", "hit is the latest cue")
  truthy(Cues.shouldSkipEvent(session, "player", "attack", { moveId = "SCRATCH" }),
    "scratch stays presented after the foe hit")

  local padU = player.padU
  player.lastAnim = nil
  local battle = {
    current = {
      arFieldCue = {
        side = "player", kind = "attack", category = "physical",
        moveId = "SCRATCH", moveType = "NORMAL",
      },
      arOverlapReact = {
        { side = "enemy", kind = "brace" },
      },
    },
  }
  enemy.lastAnim = "hit"
  Cues.pumpCurrent(session, battle, Grid, nil)
  truthy(not player._pendingCloseStrike, "second close-gap walk is not armed")
  eq(player.lastAnim, nil, "no second scratch punch")
  eq(player.padU, padU, "occupancy stays put")
  eq(enemy.lastAnim, "hit", "leftover overlap brace does not replay after the punch")

  truthy(not Cues.shouldSkipEvent(session, "enemy", "attack", {
    moveId = "FURY_ATTACK", category = "physical",
  }), "foe fury attack is a new presentation")
end

function tests.close_gap_walk_still_overlaps_react()
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
    closeTheGap = true,
    _now = 41,
    _deps = { Projectiles = Projectiles, Callouts = Callouts },
    _battle = { queue = {} },
  }
  truthy(Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "physical", moveId = "SCRATCH", moveType = "NORMAL",
  }), "scratch walk starts")
  truthy(player._pendingCloseStrike, "walk is still pending")
  local battle = {
    current = {
      arFieldCue = {
        side = "player", kind = "attack", category = "physical",
        moveId = "SCRATCH", moveType = "NORMAL",
      },
      arOverlapReact = {
        { side = "enemy", kind = "dodge" },
      },
    },
  }
  Cues.pumpCurrent(session, battle, Grid, nil)
  eq(enemy.lastAnim, nil, "overlap dodge waits while the charger is still far")
  truthy(session._heldReact, "dodge is stashed until melee")
  truthy(player._pendingCloseStrike, "walk stays pending after overlap")
  player.basePx, player.basePy = 0, 0
  enemy.basePx, enemy.basePy = 8, 0
  Cues.tickHeldReact(session, Grid)
  eq(enemy.lastAnim, "dodge", "overlap dodge fires once the charger is in reach")
end

function tests.dodge_and_brace_wait_for_the_charge()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v,
    play = function(self, kind) self.lastAnim = kind end,
    basePx = 0, basePy = 0,
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    play = function(self, kind) self.lastAnim = kind end,
    basePx = 64, basePy = 0,
    _pendingCloseStrike = { moveId = "TACKLE" },
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 90,
    _battle = {},
  }
  truthy(Cues.apply(session, "player", "dodge", Grid, nil, session._battle),
    "dodge pick is accepted while they close")
  eq(player.lastAnim, nil, "dodge pose waits")
  truthy(Cues.apply(session, "player", "brace", Grid, nil, session._battle),
    "brace pick is accepted while they close")
  eq(player.lastAnim, nil, "brace pose waits")
  enemy.basePx = 8
  Cues.tickHeldReact(session, Grid)
  eq(player.lastAnim, "brace", "brace plays once they are in your face")
end

function tests.successful_dodge_plays_on_the_pick()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v,
    play = function(self, kind) self.lastAnim = kind end,
    basePx = 0, basePy = 0,
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    play = function(self, kind) self.lastAnim = kind end,
    basePx = 64, basePy = 0,
    _pendingCloseStrike = { moveId = "TACKLE" },
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 92,
    _battle = {},
  }
  truthy(Cues.apply(session, "player", "dodge", Grid, nil, session._battle, {
    forceMiss = true,
  }), "clean dodge is accepted while they close")
  eq(player.lastAnim, "dodge", "a clean dodge plays on the pick")
  truthy(not session._heldReact, "success is not stashed behind the hit")
end

function tests.dodge_counter_snaps_back_instead_of_dodging()
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
    _now = 93,
    _battle = {},
    _deps = { Projectiles = Projectiles },
  }
  truthy(Cues.apply(session, "player", "dodge", Grid, nil, session._battle, {
    forceMiss = true,
    counterPick = true,
  }), "counter-pick dodge is accepted")
  eq(player.lastAnim, "walk", "counter pick snaps back, not dodge pose")
  truthy(not session._clashPunch, "live COUNTER does not punch in")
  eq(session._clashSlowT, nil, "live COUNTER does not slow the clock")
end

function tests.live_counter_hud_times_out_to_hold()
  local Pick = assert(loadfile(root .. "/../battle/chrome/pick.lua"))()
  local battle = {}
  local picked
  local live = Pick.armLive(battle, {
    title = "COUNTER",
    choices = {
      { label = "THUNDERBOLT", moveInst = { id = "THUNDERBOLT" } },
      { label = "HOLD", hold = true },
    },
    window = 2.2,
    onPick = function(choice)
      picked = choice
    end,
  })
  truthy(live, "live overlay armed")
  eq(live.choices[1].dir, "up", "first move is U")
  eq(live.choices[2].dir, "a", "HOLD sits on A")
  eq(battle._arLiveCounter, live, "stored on the battle")
  Pick.tickLive(battle, 1.0)
  eq(picked, nil, "still open after one second")
  truthy(battle._arLiveCounter, "window still live")
  Pick.tickLive(battle, 1.3)
  truthy(picked and picked.hold, "timeout HOLDs")
  eq(battle._arLiveCounter, nil, "overlay clears")
end

function tests.live_counter_d_pad_confirms_the_move()
  local Pick = assert(loadfile(root .. "/../battle/chrome/pick.lua"))()
  local battle = {}
  local picked
  local live = Pick.armLive(battle, {
    title = "COUNTER",
    choices = {
      { label = "SCRATCH", moveInst = { id = "SCRATCH" } },
      { label = "CUT", moveInst = { id = "CUT" } },
      { label = "HOLD", hold = true },
    },
    onPick = function(choice)
      picked = choice
    end,
  })
  live._padArmed = true
  local presses = { up = true }
  local input = {
    wasPressed = function(_, key)
      return presses[key] == true
    end,
    isDown = function()
      return false
    end,
  }
  -- FIELD calls these as methods: live.input(live, input)
  truthy(live.input(live, input), "method-style U is accepted")
  eq(picked and picked.label, "SCRATCH", "U fires Scratch immediately")
  eq(battle._arLiveCounter, nil, "overlay closes after the pick")

  battle = {}
  picked = nil
  live = Pick.armLive(battle, {
    choices = {
      { label = "SCRATCH", moveInst = { id = "SCRATCH" } },
      { label = "HOLD", hold = true },
    },
    window = 2.2,
    onPick = function(choice)
      picked = choice
    end,
  })
  live.tick(live, 2.3)
  truthy(picked and picked.hold, "method-style tick still times out to HOLD")
end

function tests.live_counter_parks_the_engine_queue()
  local grid = sampleGrid()
  local session = {
    live = true,
    grid = grid,
    playerMon = { id = "player" },
    enemyMon = { id = "enemy" },
    _battle = { _arLiveCounter = { resolved = false } },
  }
  truthy(Cues.shouldParkEngineQueue(session),
    "engine waits out the live COUNTER window")
  session._battle._arLiveCounter.resolved = true
  truthy(not Cues.shouldParkEngineQueue(session),
    "engine resumes after the window")
  session._battle._arLiveCounter = nil
  truthy(not Cues.shouldParkEngineQueue(session),
    "no overlay does not park")
end

function tests.live_counter_hud_uses_slim_chips()
  local Pick = assert(loadfile(root .. "/../battle/chrome/pick.lua"))()
  local battle = {}
  local live = Pick.armLive(battle, {
    title = "COUNTER",
    subtitle = "KABUTO",
    choices = {
      { label = "SCRATCH", moveInst = { id = "SCRATCH" } },
      { label = "CUT", moveInst = { id = "CUT" } },
      { label = "HOLD", hold = true },
    },
  })
  truthy(live.slim, "live COUNTER uses the slim strip")
  local chips = Pick.liveChipTexts(live)
  eq(chips[1], "U SCRATCH", "U is Scratch")
  eq(chips[2], "L CUT", "L is Cut")
  eq(chips[3], "A HOLD", "A is Hold")
end

function tests.spent_miss_does_not_replay_after_the_counter_window()
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
  local leftover = {
    text = "The attack missed!",
    arFieldCue = { side = "player", kind = "miss" },
  }
  local battle = {
    queue = { leftover },
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 12,
    _deps = { Projectiles = Projectiles, UI = UI, Grid = Grid, Cues = Cues },
    _battle = battle,
  }
  truthy(Cues.apply(session, "player", "miss", Grid, nil, battle), "first miss plays")
  eq(player.lastAnim, "miss", "miss pose on the first cue")
  eq(leftover.arFieldCue, nil, "leftover miss tag is stripped")
  leftover.arFieldCue = { side = "player", kind = "miss" }
  battle.current = leftover
  leftover._arFieldCueDone = nil
  session._now = 15
  session._lastCueAt = 12
  player.lastAnim = "idle"
  enemy.lastAnim = "idle"
  truthy(Cues.shouldSkipEvent(session, "player", "miss"),
    "spent miss stays skipped after 2.2s")
  eq(Cues.pumpCurrent(session, battle, Grid, nil), false,
    "pump does not replay the leftover miss")
  eq(player.lastAnim, "idle", "miss pose does not replay")
  eq(enemy.lastAnim, "idle", "dodge hop does not replay")

  Lifecycle._testBind(battle, session)
  Lifecycle.onTurnStarted(battle)
  truthy(not Cues.shouldSkipEvent(session, "player", "miss"),
    "next turn can miss again")
  Lifecycle._testUnbind(battle)
end

function tests.failed_dodge_leads_the_hit()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v,
    play = function(self, kind) self.lastAnim = kind end,
    basePx = 0, basePy = 0,
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    play = function(self, kind) self.lastAnim = kind end,
    basePx = 64, basePy = 0,
    _pendingCloseStrike = { moveId = "TACKLE" },
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local battle = {}
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 93,
    _battle = battle,
  }
  truthy(Cues.apply(session, "player", "dodge", Grid, nil, battle),
    "failed dodge is accepted while they close")
  eq(player.lastAnim, nil, "failed dodge still waits for melee")
  local fired = 0
  battle._arResumeReactPick = function()
    fired = fired + 1
  end
  Cues.tickReturns(session, Grid)
  eq(fired, 0, "HP does not apply while they are still far")
  enemy.basePx = 8
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, "dodge", "sidestep plays once they are in reach")
  eq(fired, 0, "hit waits for the dodge to read")
  truthy(Cues.reactLeadPending(session), "lead is armed after the pose")
  session._now = 93.25
  Cues.tickReturns(session, Grid)
  eq(fired, 1, "hit lands after the dodge lead")
end

function tests.held_react_times_out_if_they_never_arrive()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u, padV = pHome.v,
    play = function(self, kind) self.lastAnim = kind end,
    basePx = 0, basePy = 0,
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    play = function(self, kind) self.lastAnim = kind end,
    basePx = 64, basePy = 0,
    _pendingCloseStrike = { moveId = "TACKLE" },
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 94,
    _battle = {},
  }
  truthy(Cues.apply(session, "player", "dodge", Grid, nil, session._battle),
    "dodge is stashed while they are far")
  truthy(session._heldReact, "hold is live")
  session._now = 94 + (Cues.REACT_HOLD_MAX or 0.95) + 0.01
  Cues.tickHeldReact(session, Grid)
  eq(player.lastAnim, "dodge", "timeout plays the pose so the queue cannot freeze")
  truthy(not session._heldReact, "hold is cleared")
end

function tests.react_pose_waits_for_the_special_shot()
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
    _pendingRangedCast = { category = "special", moveId = "THUNDERBOLT" },
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 91,
    _battle = {},
  }
  truthy(Cues.apply(session, "player", "dodge", Grid, nil, session._battle),
    "dodge pick is accepted while they charge")
  eq(player.lastAnim, nil, "dodge pose waits for the bolt")
  truthy(session._heldReact, "REACT pose is stashed until the shot")
  enemy._pendingRangedCast = nil
  Cues.tickHeldReact(session, Grid)
  eq(player.lastAnim, "dodge", "dodge plays once the special leaves")
end

function tests.react_hold_slows_then_speeds_up_on_shot()
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
  local battle = { _arAwaitingReact = true }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    closeTheGap = true,
    _now = 60,
    _deps = { Projectiles = Projectiles },
    _battle = battle,
  }
  truthy(Cues.apply(session, "enemy", "attack", Grid, nil, battle, {
    category = "physical", moveId = "TACKLE", moveType = "NORMAL",
  }), "foe charge starts")
  truthy(Cues.beginReactHold(session, battle), "REACT hold starts")
  truthy(session._reactHold, "present clock holds the charge")
  truthy(not session._clashPunch, "select hold is not a counter clash")
  truthy(session.cameraNudgeX ~= nil and session.cameraNudgeY ~= nil,
    "camera punches in on the charger")

  Cues.releaseReactHold(session, "dodge_shot")
  eq(session._reactHold, nil, "pick drops the hold")
  truthy((session._reactReleaseT or 0) > 0, "outcome speeds the present clock back up")
  truthy((session._camShakeT or 0) > 0, "outcome kicks the camera")
  eq(session._hitStopT, nil, "speed-up is not a freeze")

  Projectiles.clear(session)
  truthy(Cues.apply(session, "player", "dodge", Grid, nil, battle, {
    counterMoveId = "THUNDERBOLT",
    counterMoveType = "ELECTRIC",
    counterCategory = "special",
  }), "dodge with a special counter")
  eq(player.lastAnim, nil, "dodge waits while they are still closing")
  truthy(session._heldReact, "dodge is held until melee")
  player.basePx, player.basePy = 0, 0
  enemy.basePx, enemy.basePy = 8, 0
  Cues.tickHeldReact(session, Grid)
  eq(player.lastAnim, "dodge", "defender sidesteps once the charge is in reach")
  local shot
  for i = 1, #(session.projectiles or {}) do
    if session.projectiles[i].kind == "move"
        or session.projectiles[i].style == "beam" then
      shot = session.projectiles[i]
    end
  end
  truthy(shot, "special counter fires once they are in reach")
  eq(shot.style, "beam", "thunderbolt is a beam")
  truthy(shot.sx ~= nil, "beam originates on the defender")
  truthy(enemy._pendingCloseStrike, "charger is still committed")

  Cues.deferCancelCloseStrike(session, "enemy", 0.42)
  Cues.tickReturns(session, Grid)
  truthy(enemy._pendingCloseStrike, "whiff waits for the shot to read")
  session._now = 61
  Cues.tickReturns(session, Grid)
  truthy(not enemy._pendingCloseStrike, "walk cancels after the shot")
end

function tests.again_hold_slows_for_special_call()
  truthy(Cues.againOffersCall({
    category = "special", moveId = "PSYCHIC", moveType = "PSYCHIC",
  }, Projectiles), "psychic Again! is a second CALL")
  truthy(Cues.againOffersCall({
    category = "physical", moveId = "NIGHT_SHADE", moveType = "GHOST",
  }, Projectiles), "travel Again! is a second CALL")
  truthy(not Cues.againOffersCall({
    category = "physical", moveId = "TACKLE", moveType = "NORMAL",
  }, Projectiles), "melee Again! stays an extra swing")
  truthy(not Cues.againOffersCall({
    category = "special", moveId = "FIRE_PUNCH", moveType = "FIRE",
  }, Projectiles), "contact specials stay melee Again!")

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
  local battle = { _arAwaitAgain = true, _arAwaitAgainSide = "player" }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 80,
    _deps = { Projectiles = Projectiles },
    _battle = battle,
  }
  truthy(Cues.awaitingAgain(battle), "Again! call flag is live")
  truthy(Cues.beginAgainHold(session, battle), "Again! hold starts")
  truthy(session._reactHold, "present clock slows for the call")
  truthy(not session._clashPunch, "call hold is not a counter clash")
  truthy(session.cameraNudgeX ~= nil and session.cameraNudgeY ~= nil,
    "camera punches in on the special attacker")
  Cues.syncReactHold(session, battle)
  truthy(session._reactHold, "hold stays while the diamond is open")

  battle._arAwaitCallout = true
  truthy(Cues.shouldParkEngineQueue(session), "engine waits for the follow-up CALL")

  Cues.releaseAgainHold(session, "call")
  eq(session._reactHold, nil, "pick drops the hold")
  truthy((session._reactReleaseT or 0) > 0, "call speeds the present clock back up")
  battle._arAwaitAgain = nil
  battle._arAwaitCallout = nil
  Cues.syncReactHold(session, battle)
  eq(session._reactHold, nil, "sync does not re-arm after the pick")
end

function tests.ranged_counter_skips_contact_punches()
  truthy(Cues.isRangedCounter({
    moveId = "THUNDERBOLT", category = "special", moveType = "ELECTRIC",
  }, Projectiles), "thunderbolt is a ranged counter")
  truthy(Cues.isRangedCounter({
    moveId = "EMBER", category = "special", moveType = "FIRE",
  }, Projectiles), "ember is a ranged counter")
  truthy(not Cues.isRangedCounter({
    moveId = "FIRE_PUNCH", category = "special", moveType = "FIRE",
  }, Projectiles), "fire punch stays a melee poke")
  truthy(Projectiles.isFireNowShot({
    moveId = "EMBER", category = "special", moveType = "FIRE",
  }), "Ember is a FIRE projectile")
  truthy(Projectiles.isFireNowShot({
    moveId = "WATER_GUN", category = "special", moveType = "WATER",
  }), "Water Gun is a FIRE projectile")
  truthy(Projectiles.isFireNowShot({
    moveId = "SWIFT", category = "physical", moveType = "NORMAL",
  }), "Swift still flies as FIRE")
  truthy(not Projectiles.isFireNowShot({
    moveId = "FIRE_PUNCH", category = "special", moveType = "FIRE",
  }), "Fire Punch is not FIRE")
  truthy(not Projectiles.isFireNowShot({
    moveId = "TACKLE", category = "physical", moveType = "NORMAL",
  }), "Tackle is not FIRE")
  truthy(not Projectiles.isFireNowShot({
    moveId = "PSYCHIC", category = "special", moveType = "PSYCHIC",
  }), "Psychic is an aura, not a projectile")
  truthy(not Projectiles.isFireNowShot({
    moveId = "ABSORB", category = "special", moveType = "GRASS",
  }), "Absorb is a drain, not a projectile")
  truthy(not Projectiles.isFireNowShot({
    moveId = "SMOG", category = "special", moveType = "POISON",
  }), "Smog is a lane, not FIRE")
end

function tests.turn_start_clears_close_gap_drift()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = {
    id = "player", padU = pHome.u + 1, padV = pHome.v,
    homePadU = pHome.u + 1, homePadV = pHome.v,
    _meleeAnchor = true, _returnAt = 99, _withdrawAfterStrike = true,
    _struckMoves = { POISON_STING = true },
  }
  local enemy = {
    id = "enemy", padU = eHome.u, padV = eHome.v,
    homePadU = eHome.u, homePadV = eHome.v,
  }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local battle = {}
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _deps = { Grid = Grid, Cues = Cues },
    _battle = battle,
  }
  Lifecycle._testBind(battle, session)
  Lifecycle.onTurnStarted(battle)
  eq(player._returnAt, nil, "turn start drops withdraw clock")
  eq(player._withdrawAfterStrike, nil, "turn start drops withdraw flag")
  eq(player._meleeAnchor, nil, "turn start does not keep a foe-face roam")
  eq(player.homePadU, pHome.u + 1, "home pad is unchanged")
  eq(player._struckMoves, nil, "struck-move latch cleared")
  Lifecycle._testUnbind(battle)
end

function tests.coords_key_floors_pad_indices()
  eq(Coords.key(1.2, 2.8), "1,3", "occupancy keys round to nearest pad cell")
  eq(Coords.key(1, 2), "1,2", "integer pads keep their key")
end

function tests.awaiting_react_holds_close_strike()
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
  local battle = { _arAwaitingReact = true }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    closeTheGap = true,
    _now = 50,
    _deps = { Projectiles = Projectiles },
    _battle = battle,
  }
  truthy(Cues.apply(session, "enemy", "attack", Grid, nil, battle, {
    category = "physical", moveId = "FURY_ATTACK", moveType = "NORMAL",
  }), "foe fury walk starts")
  truthy(enemy._pendingCloseStrike, "strike waits for REACT")
  Cues.tickReturns(session, Grid)
  enemy.basePx, enemy.basePy = enemy.targetPx, enemy.targetPy
  Cues.tickReturns(session, Grid)
  eq(enemy.lastAnim, nil, "no punch while REACT is open")
  truthy(enemy._pendingCloseStrike, "pending walk stays parked")
  truthy(Cues.closeGapHoldActive(session), "HP still waits for the punch")
  eq(Cues.shouldParkEngineQueue(session), false,
    "REACT menu row is not starved by a parked queue")

  battle._arAwaitingReact = nil
  truthy(Cues.shouldParkEngineQueue(session),
    "after pick, park until punch or cancel")
  battle._arWhiffCloseStrike = "enemy"
  Cues.tickReturns(session, Grid)
  truthy(not enemy._pendingCloseStrike, "dodge miss cancels the punch")
  eq(enemy.lastAnim, nil, "whiff does not play attack")
end

function tests.accuracy_miss_plays_whiff_and_chip()
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
  local battle = { frame = 20, _arAccuracyMissSide = "player" }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    closeTheGap = true,
    _now = 70,
    _deps = { Projectiles = Projectiles, UI = UI },
    _battle = battle,
  }
  local tagged = {
    nextInsert = 1,
    queue = { { text = "The attack missed!" } },
    _arAccuracyMissSide = "enemy",
  }
  truthy(Cues.isMissText("The attack\nmissed!"), "vanilla miss line is a miss")
  truthy(Cues.tagMiss(tagged, tagged.queue[1].text), "tags the miss line")
  eq(tagged.queue[1].arFieldCue.kind, "miss", "miss cue kind")
  eq(tagged.queue[1].arFieldCue.side, "enemy", "miss cue is the attacker")

  truthy(Cues.apply(session, "player", "attack", Grid, nil, battle, {
    category = "physical", moveId = "TACKLE", moveType = "NORMAL",
  }), "walk starts before the miss")
  truthy(player._pendingCloseStrike, "close-gap is armed")
  battle._arAccuracyMissSide = "player"
  Cues.tickReturns(session, Grid)
  player.basePx, player.basePy = player.targetPx, player.targetPy
  Cues.tickReturns(session, Grid)
  eq(player.lastAnim, "miss", "melee arrival plays a miss, not a punch")
  eq(enemy.lastAnim, "dodge", "the foe hops aside on a miss")
  truthy(not player._pendingCloseStrike, "miss consumes the pending strike")
  eq(battle._arStatusChips.player.text, "MISS", "MISS chip sits on the attacker")
  eq(Projectiles.miss(session, "player").style, "puff",
    "miss paints a whoosh past the foe")
end

local function installMoveUsedListener(predict)
  local reacted = {}
  local fbv = {
    vanishKind = function() return nil end,
    shouldSkipEventReact = function() return false end,
    predictMoveHit = predict,
    react = function(_, side, kind, opts)
      reacted[#reacted + 1] = { side = side, kind = kind, opts = opts }
    end,
  }
  local listeners = {}
  local mod = {
    events = {
      on = function(_, name, fn)
        listeners[name] = fn
      end,
    },
  }
  Hooks.installEvents(fbv, mod, {
    isFieldBattle = function() return true end,
  })
  return listeners["battle.move_used"], reacted
end

function tests.predict_move_hit_reads_accuracy_stash()
  local user = { isPlayer = true }
  local move = { id = "TACKLE" }
  local battle = {
    _arAccuracyPred = { hit = false, user = user, moveId = "TACKLE" },
  }
  eq(FieldBattle.predictMoveHit(battle, user, nil, move), false,
    "stash miss is a miss")
  eq(FieldBattle.predictMoveHit(battle, user, nil, { id = "SCRATCH" }), nil,
    "other moves do not reuse the stash")
end

function tests.move_used_plays_miss_from_accuracy_stash()
  local user = { isPlayer = true }
  local target = { isPlayer = false }
  local emit, reacted = installMoveUsedListener(function(battle)
    return battle._arAccuracyPred and battle._arAccuracyPred.hit
  end)
  local battle = {
    player = user,
    enemy = target,
    _arAccuracyPred = { hit = false, user = user, target = target, moveId = "TACKLE" },
  }
  emit({
    battle = battle,
    user = user,
    target = target,
    move = { id = "TACKLE", type = "NORMAL", category = "physical", power = 40 },
  })
  eq(#reacted, 1, "reacted once")
  eq(reacted[1].kind, "miss", "early miss skips the attack lunge")
  eq(reacted[1].side, "player", "miss cue is the attacker")
  eq(battle._arAwaitAccuracyCue, nil, "stash path does not defer")
end

function tests.move_used_plays_attack_from_accuracy_stash()
  local user = { isPlayer = true }
  local target = { isPlayer = false }
  local emit, reacted = installMoveUsedListener(function()
    return true
  end)
  emit({
    battle = { player = user, enemy = target },
    user = user,
    target = target,
    move = { id = "TACKLE", type = "NORMAL", category = "physical", power = 40 },
  })
  eq(#reacted, 1, "reacted once")
  eq(reacted[1].kind, "attack", "early hit keeps the attack cue")
end

function tests.move_used_plays_attack_when_accuracy_unseen()
  local user = { isPlayer = true }
  local target = { isPlayer = false }
  local emit, reacted = installMoveUsedListener(function()
    return nil
  end)
  local battle = { player = user, enemy = target }
  emit({
    battle = battle,
    user = user,
    target = target,
    move = { id = "TACKLE", type = "NORMAL", category = "physical", power = 40 },
  })
  eq(#reacted, 1, "unseen roll still plays the swing")
  eq(reacted[1].kind, "attack", "defaults to attack until accuracy says miss")
  truthy(battle._arAwaitAccuracyCue, "accuracy wrap can still flip a later miss")
end

function tests.pump_does_not_lunge_while_accuracy_awaiting()
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
  local battle = {
    _arAwaitAccuracyCue = { side = "player", kind = "attack", opts = {} },
    current = {
      arFieldCue = {
        side = "player", kind = "attack",
        category = "physical", moveId = "KARATE_CHOP", moveType = "FIGHTING",
      },
      arOverlapReact = {
        { side = "enemy", kind = "dodge" },
      },
    },
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    closeTheGap = true,
    _now = 80,
    _deps = { Projectiles = Projectiles },
    _battle = battle,
  }
  truthy(Cues.pumpCurrent(session, battle, Grid, nil),
    "awaiting accuracy still plays the overlap dodge")
  eq(player.lastAnim, nil, "no punch before the roll")
  eq(player._pendingCloseStrike, nil, "close-gap is not armed")
  eq(enemy.lastAnim, "dodge", "foe dodges while the swing waits on accuracy")
  eq(battle.current._arFieldCueDone, true, "toast is consumed so it cannot double")
end

function tests.turn_start_clears_accuracy_preview()
  local battle = {
    _arAccuracyPred = { hit = false },
    _arAwaitAccuracyCue = { kind = "attack" },
  }
  Lifecycle.onTurnStarted(battle)
  eq(battle._arAccuracyPred, nil, "turn start drops the stash")
  eq(battle._arAwaitAccuracyCue, nil, "turn start drops a deferred cue")
end

function tests.counter_does_not_forget_prior_strike()
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
    closeTheGap = true,
    _now = 60,
    _deps = { Projectiles = Projectiles },
    _battle = {},
  }
  Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "physical", moveId = "FURY_ATTACK", moveType = "NORMAL",
  })
  Cues.tickReturns(session, Grid)
  player.basePx, player.basePy = player.targetPx, player.targetPy
  Cues.tickReturns(session, Grid)
  eq(player._closeStruckMoveId, "FURY_ATTACK", "fury punch latches")

  Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "physical", moveId = "TACKLE", moveType = "NORMAL",
    isCalled = true,
  })
  eq(player._closeStruckMoveId, "TACKLE", "called tackle stays in melee")
  truthy(not player._pendingCloseStrike, "second move does not start a new walk")
  eq(player.lastAnim, "attack", "called tackle plays contact in place")
  truthy(Cues.shouldSkipEvent(session, "player", "attack", { moveId = "FURY_ATTACK" }),
    "fury stays presented after a called tackle counter")
  player.lastAnim = nil
  local battle = {
    current = {
      arFieldCue = {
        side = "player", kind = "attack", category = "physical",
        moveId = "FURY_ATTACK", moveType = "NORMAL",
      },
    },
  }
  Cues.pumpCurrent(session, battle, Grid, nil)
  truthy(not player._pendingCloseStrike, "leftover fury toast does not re-arm")
  eq(player.lastAnim, nil, "no second fury punch after tackle")
end

function tests.orphan_close_gap_settles_before_next_turn()
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
  local flushed = false
  local battle = {
    _arCloseGapDamage = { { ctx = { move = { id = "SCRATCH" } }, record = {} } },
    applyDamage = function() end,
  }
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    closeTheGap = true,
    _now = 20,
    _deps = { Projectiles = Projectiles, Grid = Grid },
    _battle = battle,
  }
  truthy(Cues.apply(session, "player", "attack", Grid, nil, battle, {
    category = "physical", moveId = "SCRATCH", moveType = "NORMAL",
  }), "scratch walk starts")
  truthy(player._pendingCloseStrike, "walk is still pending")
  local origFlush = Cues.flushHeldHit
  Cues.flushHeldHit = function(sess, btl)
    flushed = true
    btl._arCloseGapDamage = nil
    return true
  end
  truthy(Cues.settleOrphanCloseGap(session, battle, Grid), "orphan walk settles")
  Cues.flushHeldHit = origFlush
  truthy(not player._pendingCloseStrike, "pending walk is cleared")
  truthy(flushed, "held HP is flushed after cancel")
end

function tests.field_snapshot_reports_pad_and_pixels()
  local grid = sampleGrid()
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local player = { id = "player", padU = pHome.u, padV = pHome.v }
  local enemy = { id = "enemy", padU = eHome.u, padV = eHome.v }
  Grid.setPad(grid, player, player.padU, player.padV)
  Grid.setPad(grid, enemy, enemy.padU, enemy.padV)
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _deps = { Grid = Grid },
  }
  local you, foe, dist = Cues.describeField(session)
  truthy(you:find("you u=", 1, true), "player pad is named")
  truthy(you:find("px=", 1, true), "player pixels are included")
  truthy(foe:find("foe u=", 1, true), "foe pad is named")
  truthy(dist:find("dist=", 1, true), "pad distance is included")
end

function tests.nameless_attack_does_not_close_gap()
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
    closeTheGap = true,
    _now = 70,
    _deps = { Projectiles = Projectiles },
    _battle = {},
  }
  Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "physical", moveId = "MEGA_PUNCH", moveType = "NORMAL",
  })
  Cues.tickReturns(session, Grid)
  player.basePx, player.basePy = player.targetPx, player.targetPy
  Cues.tickReturns(session, Grid)
  local padU = player.padU
  player.lastAnim = nil
  player._pendingCloseStrike = nil
  truthy(Cues.apply(session, "player", "attack", Grid, nil, session._battle, {
    category = "physical",
  }), "nameless again-shout still plays")
  truthy(not player._pendingCloseStrike, "nameless cue after a punch does not walk")
  eq(player.padU, padU, "nameless cue stays in melee")
  eq(player.lastAnim, "attack", "nameless cue is in-place contact")
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
  truthy(player.lastAnim == "cast" or player.lastAnim == "charge",
    "surf charges in place")
  eq(enemy.lastAnim, nil, "foe dodge waits for the surf")
  truthy(session._heldReact, "dodge is stashed until the bolt leaves")
  truthy(session._trainerCallouts and session._trainerCallouts.foe
      and session._trainerCallouts.foe[1], "Move! overlay is up")
  eq(session._trainerCallouts.foe[1].text, "BROCK:\nOnix, dodge!", "overlay text")
  player._pendingRangedCast = nil
  Cues.tickHeldReact(session, Grid)
  eq(enemy.lastAnim, "dodge", "foe dodges once the surf leaves")

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
  eq(enemy.lastAnim, nil, "queued dodge waits for the hydro pump")
  eq(queued._arOverlapShown, true, "queued toast is consumed")
  eq(queued._arFieldCueDone, true, "queued cue will not replay")
  player._pendingRangedCast = nil
  Cues.tickHeldReact(session, Grid)
  eq(enemy.lastAnim, "dodge", "queued dodge plays once the shot leaves")

  -- Late attach after the attack cue already fired (choose-lead / flush).
  session._now = 34
  enemy.lastAnim = nil
  player._pendingRangedCast = nil
  session._heldReact = nil
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

  -- Failed NPC dodge: trainer still shouted, but the cue is a hit, not a sidestep.
  session._now = 36.1
  enemy.lastAnim = nil
  session._trainerCallouts = nil
  battle.current._arFieldCueDone = true
  battle.current.arOverlapReact = {
    { side = "enemy", kind = "hit", text = "BROCK:\nOnix, dodge!", bubble = "foe" },
  }
  battle.queue = {}
  truthy(not Cues.pumpCurrent(session, battle, Grid, nil),
    "failed dodge order does not pump a react pose")
  eq(enemy.lastAnim, nil, "failed NPC dodge does not sidestep")

  -- Miss result toast after the overlap dodge: do not make the player flinch,
  -- and do not replay the foe's dodge before their next attack.
  session._now = 36.2
  player.lastAnim = nil
  enemy.lastAnim = nil
  battle.current = {
    text = "But SLOWPOKE\ndodged aside!",
    arFieldCue = { side = "enemy", kind = "dodge" },
    arDodgeWhiff = true,
  }
  battle.queue = {}
  eq(Cues.pumpCurrent(session, battle, Grid, nil), false,
    "dodge-whiff after overlap is not a second dodge")
  eq(player.lastAnim, nil, "player does not flinch into the foe's next move")
  eq(enemy.lastAnim, nil, "foe dodge does not replay on the miss line")
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
  eq(placeSlot, "above_box", "callouts stay above the dialogue row")
  eq(ySlot + 23 + 2, 119, "empty narrator still docks above the vanilla slot")

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
  eq(session._trainerCallouts.foe[1].text, "Onix! Move!",
    "callout stays up until a new shout replaces it")

  truthy(Callouts.push(session, "player", "PIKACHU!\nDodge it!", { kind = "react" }),
    "player react order uses the dialogue strip")
  eq(session._trainerCallouts.player[1].text, "PIKACHU!\nDodge it!",
    "player order is live")
  truthy(Callouts.ownsText(session, "PIKACHU!\nDodge it!"),
    "owns the player order")

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

function tests.react_menu_keeps_the_incoming_order()
  local session = {}
  truthy(Callouts.push(session, "foe", "BROCK:\nOnix, use Surf!", { kind = "order" }),
    "incoming order is live")
  local reactBattle = {
    phase = "messages",
    _arAwaitingReact = true,
    game = {
      stack = {
        top = function()
          return { isOpaque = false }
        end,
      },
    },
  }
  truthy(not Callouts.shouldHold(reactBattle),
    "REACT HUD does not dismiss the incoming order")
  Callouts.tick(session, 0.2, reactBattle)
  truthy(session._trainerCallouts and session._trainerCallouts.foe
      and session._trainerCallouts.foe[1],
    "Brock's order stays up while you pick")
end

function tests.move_call_rewrite_stays_put()
  local Dialogue = assert(loadfile(root .. "/../battle/rules/dialogue.lua"))()
  local S = { PLAYER_MOVE_CALLS = { "FIRST!\n%s %s" } }
  Dialogue.bind({
    opt = function(key)
      return key == "anime_move_calls"
    end,
    S = S,
  })
  local battle = {}
  local first = Dialogue.rewriteMoveCallText(battle, "SQUIRTLE\nused TACKLE!")
  S.PLAYER_MOVE_CALLS = { "SECOND!\n%s %s" }
  local again = Dialogue.rewriteMoveCallText(battle, "SQUIRTLE\nused TACKLE!")
  eq(first, again, "the same announce is not rewritten again")
  truthy(tostring(first):find("FIRST", 1, true), "cached line is the first roll")
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

  -- Hide turn fires vanish before the engine sets charging.
  playerMon._battleBattler.invulnerable = nil
  playerMon._battleBattler.charging = nil
  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil, {
    category = "physical", moveId = "DIG",
  }), "first Dig vanishes without a charge flag")
  eq(playerMon.anim, "vanish_dig", "hide-turn Dig plays vanish_dig")
  eq(session._lastCueKind, "vanish", "last cue is vanish")
  playerMon._fieldVanished = true
  playerMon.anim = "buried"
  Cues.syncSemiInvuln(session, Grid)
  eq(playerMon.anim, "buried", "sync does not pop out before invuln is armed")

  playerMon._fieldVanished = nil
  playerMon.anim = "idle"
  playerMon._battleBattler.invulnerable = true
  playerMon._battleBattler.charging = { id = "DIG" }
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
  eq(move._removed, true, "move projectile cleans itself up")
  eq(#session.projectiles, 1, "land leaves the impact burst")
  eq(session.projectiles[1].style, "special_impact", "burst is the special land FX")

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
  overworld.player = { px = 40, py = 56 }
  session.foe = { px = 90, py = 32 }
  session._battle = { kind = "trainer", game = { overworld = overworld } }
  player.px, player.py = 16, 32
  player.basePx, player.basePy = 16, 32
  enemy.px, enemy.py = 80, 32
  enemy.basePx, enemy.basePy = 80, 32
  local beam = Projectiles.recallBeam(session, "player")
  truthy(beam and beam.style == "recall", "player recall fires red laser")
  eq(beam.sx, 48, "recall origin is the live player trainer sprite")
  eq(beam.sy, 57, "recall origin uses trainer torso, not the home pad")
  eq(beam.ex, 24, "recall tip is the mon's map pose")
  eq(beam.ey, 36, "recall tip uses the faint/recall tile, not home")
  truthy(beam.pinTip and beam.pinFrozen, "recall bolt spans trainer → faint pose")
  eq(beam.followEnt, player, "recall laser remembers the recalled mon")
  player.px, player.py = 16, 8
  Projectiles.tick(session, 0.16)
  eq(beam.ex, 24, "tip does not chase the recall shrink offset")
  eq(beam.sx, 48, "origin stays on the trainer snapshot")
  local foeBeam = Projectiles.recallBeam(session, "enemy")
  eq(foeBeam.style, "recall", "trainer foe recall fires red laser")
  eq(foeBeam.sx, 98, "foe recall origin is the live trainer sprite")
  eq(foeBeam.ex, 88, "foe recall tip is the foe mon map pose")
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
  eq(ember.style, "ember", "ember uses a short fireball lob")
  eq(ember.glitz, "flame", "ember paints flame glitz")
  truthy(ember.sx < ember.ex, "ember travels toward the foe")
  truthy((ember.arc or 0) >= 8, "ember arcs like tossed fireballs")
  truthy(Projectiles.isTravelFx({
    moveType = "FIRE", moveId = "EMBER",
  }), "ember is a travel FX")
  local rockThrow = Projectiles.move(session, "player", {
    moveType = "ROCK", moveId = "ROCK_THROW",
  })
  eq(rockThrow.style, "rock", "rock throw lobs tumbling shards")
  eq(rockThrow.glitz, "rock", "rock throw paints rock glitz")
  truthy(rockThrow.sx < rockThrow.ex, "rock throw travels toward the foe")
  truthy((rockThrow.arc or 0) >= 18, "rock throw arcs like a thrown stone")
  truthy((rockThrow.duration or 0) >= 0.5, "rock throw holds the lob")
  truthy(Projectiles.isTravelFx({
    moveType = "ROCK", moveId = "ROCK_THROW",
  }), "rock throw is a travel FX")
  local rockSlide = Projectiles.move(session, "player", {
    moveType = "ROCK", moveId = "ROCK_SLIDE",
  })
  eq(rockSlide.style, "slide", "rock slide rains stones onto the foe")
  eq(rockSlide.glitz, "rock", "rock slide paints rock glitz")
  eq(rockSlide.sx, rockSlide.ex, "rock slide falls on the target")
  eq(rockSlide.sy, rockSlide.ey, "rock slide does not lob across the pad")
  truthy((rockSlide.duration or 0) >= 0.65, "rock slide holds the cascade")
  truthy(Projectiles.isTravelFx({
    moveType = "ROCK", moveId = "ROCK_SLIDE",
  }), "rock slide is a travel FX")
  truthy(not Cues.isMeleeAttack({
    category = "physical", moveId = "ROCK_SLIDE", moveType = "ROCK",
  }, Projectiles), "rock slide does not close the gap")
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
  local waterGun = Projectiles.move(session, "player", {
    moveType = "WATER", moveId = "WATER_GUN",
  })
  eq(waterGun.style, "stream", "water gun is a stream")
  eq(waterGun.glitz, "jet", "water gun paints a water jet")
  truthy((waterGun.duration or 0) >= 0.4, "water gun holds the stream")
  truthy(waterGun.sx < waterGun.ex, "water gun travels toward the foe")
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
  truthy((razor.duration or 0) >= 0.62, "razor leaf holds a longer volley")
  truthy(Projectiles.isTravelFx({
    moveType = "GRASS", moveId = "RAZOR_LEAF",
  }), "razor leaf is a travel FX")
  local hyperBeam = Projectiles.move(session, "player", {
    moveType = "NORMAL", moveId = "HYPER_BEAM",
  })
  eq(hyperBeam.style, "beam", "hyper beam is a beam")
  eq(hyperBeam.glitz, "hyper", "hyper beam uses a charged thick beam")
  truthy((hyperBeam.duration or 0) >= 0.65, "hyper beam holds the charge and fire")
  truthy(Projectiles.isTravelFx({
    moveType = "NORMAL", moveId = "HYPER_BEAM",
  }), "hyper beam is a travel FX")
  local psybeam = Projectiles.move(session, "player", {
    moveType = "PSYCHIC", moveId = "PSYBEAM",
  })
  eq(psybeam.style, "beam", "psybeam is a beam")
  eq(psybeam.glitz, "psy", "psybeam uses corkscrew psy glitz")
  truthy((psybeam.duration or 0) >= 0.48, "psybeam holds the helix")
  truthy(Projectiles.isTravelFx({
    moveType = "PSYCHIC", moveId = "PSYBEAM",
  }), "psybeam is a travel FX")
  local clones = Projectiles.status(session, "player", {
    moveType = "NORMAL", moveId = "DOUBLE_TEAM",
  })
  eq(clones.style, "clones", "double team fans afterimages around the user")
  eq(clones.glitz, "afterimage", "double team uses afterimage glitz")
  eq(clones.sx, clones.ex, "double team stays on the user")
  eq(clones.followSide, "player", "double team follows the caster")
  truthy((clones.duration or 0) >= 0.75, "double team holds the clone burst")
  truthy(Projectiles.isTravelFx({
    moveType = "NORMAL", moveId = "DOUBLE_TEAM",
  }), "double team is a travel FX")
  truthy(not Cues.isMeleeAttack({
    category = "status", moveId = "DOUBLE_TEAM", moveType = "NORMAL",
  }, Projectiles), "double team does not close the gap")
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
  truthy(Projectiles.isProjectileSpecial({
    moveType = "NORMAL", moveId = "SWIFT", category = "physical",
  }), "swift is a projectile special")
  truthy(not Cues.isMeleeAttack({
    category = "physical", moveId = "SWIFT", moveType = "NORMAL",
  }, Projectiles), "swift does not close the gap")
  truthy(Cues.isRangedCounter({
    category = "physical", moveId = "SWIFT", moveType = "NORMAL",
  }, Projectiles), "swift counters as a special")
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
  local sandAttack = Projectiles.status(session, "player", {
    moveType = "NORMAL", moveId = "SAND_ATTACK",
  })
  eq(sandAttack.style, "sand", "sand attack uses a grit spray")
  eq(sandAttack.glitz, "grit", "sand attack uses grit glitz")
  truthy(sandAttack.sx < sandAttack.ex, "sand attack travels toward the foe")
  truthy(sandAttack.pinTip, "sand attack locks onto the face")
  truthy(Projectiles.isTravelFx({
    moveType = "NORMAL", moveId = "SAND_ATTACK",
  }), "sand attack is a travel FX")
  local sandAlias = Projectiles.status(session, "player", {
    moveType = "GROUND", moveId = "SANDATTACK",
  })
  eq(sandAlias.style, "sand", "SANDATTACK aliases sand spray")
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
  local firePunch = Projectiles.contact(session, "player", {
    moveType = "FIRE", moveId = "FIRE_PUNCH",
  })
  eq(firePunch.glitz, "firepunch", "fire punch uses a flaming fist")
  truthy((firePunch.duration or 0) >= 0.38, "fire punch holds the flame burst")
  local icePunch = Projectiles.contact(session, "player", {
    moveType = "ICE", moveId = "ICE_PUNCH",
  })
  eq(icePunch.glitz, "icepunch", "ice punch uses a freezing fist")
  local thunderPunch = Projectiles.contact(session, "player", {
    moveType = "ELECTRIC", moveId = "THUNDERPUNCH",
  })
  eq(thunderPunch.glitz, "thunderpunch", "thunderpunch uses a shocking fist")
  local thunderPunchAlias = Projectiles.contact(session, "player", {
    moveType = "ELECTRIC", moveId = "THUNDER_PUNCH",
  })
  eq(thunderPunchAlias.glitz, "thunderpunch", "THUNDER_PUNCH aliases thunderpunch")
  local seismic = Projectiles.contact(session, "player", {
    moveType = "FIGHTING", moveId = "SEISMIC_TOSS",
  })
  eq(seismic.glitz, "toss", "seismic toss lifts both mons and slams them")
  truthy((seismic.duration or 0) >= 1.0, "seismic toss holds the throw")
  truthy(Projectiles.isContactFx({ moveId = "SEISMIC_TOSS" }), "seismic toss is contact FX")
  truthy(Cues.isMeleeAttack({
    category = "physical", moveId = "SEISMIC_TOSS", moveType = "FIGHTING",
  }, Projectiles), "seismic toss still closes the gap")
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
  local iceCrit = Projectiles.critBurst(session, "enemy", { moveType = "ICE" })
  eq(iceCrit.glitz, "ICE", "ice crit uses ice fill")
  local elecCrit = Projectiles.critBurst(session, "enemy", { moveType = "ELECTRIC" })
  eq(elecCrit.glitz, "ELECTRIC", "electric crit uses electric fill")
  local psyCrit = Projectiles.critBurst(session, "enemy", { moveType = "PSYCHIC" })
  eq(psyCrit.glitz, "PSYCHIC", "psychic crit uses psychic fill")
  local darkCrit = Projectiles.critBurst(session, "enemy", { moveType = "DARK" })
  eq(darkCrit.glitz, "DARK", "dark crit uses ink fill")
  local qa = Projectiles.contact(session, "player", {
    moveType = "NORMAL", moveId = "QUICK_ATTACK",
  })
  eq(qa.glitz, "dash", "quick attack uses dash contact")
  local qaSmear
  for i = 1, #(session.projectiles or {}) do
    if session.projectiles[i].style == "dash_smear" then
      qaSmear = session.projectiles[i]
    end
  end
  truthy(qaSmear, "quick attack smears the attacker")
  eq(qaSmear.glitz, "dash", "quick attack smear is a dash")
  truthy(qaSmear.sx < qaSmear.ex, "smear runs toward the foe")
  Projectiles.contact(session, "player", {
    moveType = "NORMAL", moveId = "EXTREMESPEED",
  })
  local esSmear
  for i = 1, #(session.projectiles or {}) do
    if session.projectiles[i].style == "dash_smear"
        and session.projectiles[i].glitz == "extreme" then
      esSmear = session.projectiles[i]
    end
  end
  truthy(esSmear, "extreme speed smears with a longer trail")
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

  calls.arc, calls.line, calls.circle, calls.ellipse = 0, 0, 0, 0
  local sand = Projectiles.status(session, "player", {
    moveType = "NORMAL", moveId = "SAND_ATTACK",
  })
  sand.age = 0.32
  sand:draw(0, 0)
  truthy(calls.circle > 0, "sand attack paints grit grains")
  truthy(calls.ellipse > 0, "sand attack paints a dust scuff")
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
  truthy(calls.circle > 0, "ember paints a hot fireball core")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local rockThrow = Projectiles.move(session, "player", {
    moveType = "ROCK", moveId = "ROCK_THROW",
  })
  rockThrow.age = 0.32
  rockThrow:draw(0, 0)
  truthy(calls.polygon > 0, "rock throw paints tumbling rock shards")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local rockSlide = Projectiles.move(session, "player", {
    moveType = "ROCK", moveId = "ROCK_SLIDE",
  })
  rockSlide.age = 0.36
  rockSlide:draw(0, 0)
  truthy(calls.polygon > 0, "rock slide paints falling rock shards")
  truthy(calls.ellipse > 0, "rock slide paints ground dust")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local flamethrower = Projectiles.move(session, "player", {
    moveType = "FIRE", moveId = "FLAMETHROWER",
  })
  flamethrower.age = 0.22
  flamethrower:draw(0, 0)
  truthy(calls.polygon > 0, "flamethrower paints a jet of flame tongues")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local waterGunPaint = Projectiles.move(session, "player", {
    moveType = "WATER", moveId = "WATER_GUN",
  })
  waterGunPaint.age = 0.28
  waterGunPaint:draw(0, 0)
  truthy(calls.polygon > 0, "water gun paints a water ribbon, not beads")
  truthy(calls.ellipse > 0, "water gun paints wet highlight sheets")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local blast = Projectiles.move(session, "player", {
    moveType = "FIRE", moveId = "FIRE_BLAST",
  })
  blast.age = 0.50
  blast:draw(0, 0)
  truthy(calls.polygon > 0, "fire blast paints a star of flame tongues")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local razorPaint = Projectiles.move(session, "player", {
    moveType = "GRASS", moveId = "RAZOR_LEAF",
  })
  razorPaint.age = 0.36
  razorPaint:draw(0, 0)
  truthy(calls.polygon > 0, "razor leaf paints a cyclone of leaf blades")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local hyperPaint = Projectiles.move(session, "player", {
    moveType = "NORMAL", moveId = "HYPER_BEAM",
  })
  hyperPaint.age = 0.28
  hyperPaint:draw(0, 0)
  truthy(calls.circle > 0, "hyper beam paints a charge orb")
  truthy(calls.line > 0, "hyper beam paints the fired beam")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local psyPaint = Projectiles.move(session, "player", {
    moveType = "PSYCHIC", moveId = "PSYBEAM",
  })
  psyPaint.age = 0.22
  psyPaint:draw(0, 0)
  truthy(calls.circle > 0, "psybeam paints corkscrew motes")
  truthy(calls.line > 0, "psybeam paints helix strands")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local icePunchPaint = Projectiles.contact(session, "player", {
    moveType = "ICE", moveId = "ICE_PUNCH",
  })
  icePunchPaint.age = 0.14
  icePunchPaint:draw(0, 0)
  truthy(calls.polygon > 0, "ice punch paints ice crystals")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local firePunchPaint = Projectiles.contact(session, "player", {
    moveType = "FIRE", moveId = "FIRE_PUNCH",
  })
  firePunchPaint.age = 0.14
  firePunchPaint:draw(0, 0)
  truthy(calls.polygon > 0, "fire punch paints flame tongues")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local thunderPunchPaint = Projectiles.contact(session, "player", {
    moveType = "ELECTRIC", moveId = "THUNDERPUNCH",
  })
  thunderPunchPaint.age = 0.14
  thunderPunchPaint:draw(0, 0)
  truthy(calls.line > 0, "thunderpunch paints lightning forks")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local tossPaint = Projectiles.contact(session, "player", {
    moveType = "FIGHTING", moveId = "SEISMIC_TOSS",
  })
  tossPaint.age = 0.40
  tossPaint:draw(0, 0)
  truthy(calls.ellipse > 0 or calls.circle > 0, "seismic toss paints ground shadows while they fly")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local clonePaint = Projectiles.status(session, "player", {
    moveType = "NORMAL", moveId = "DOUBLE_TEAM",
  })
  clonePaint.age = 0.28
  clonePaint:draw(0, 0)
  truthy(calls.ellipse > 0, "double team paints afterimage silhouettes")
  truthy(calls.circle > 0, "double team paints clone heads")

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

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local critPaint = Projectiles.critBurst(session, "enemy")
  critPaint.age = 0.10
  critPaint:draw(0, 0)
  truthy(calls.polygon > 0, "crit paints a comic starburst")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local icePaint = Projectiles.critBurst(session, "enemy", { moveType = "ICE" })
  icePaint.age = 0.10
  icePaint:draw(0, 0)
  truthy(calls.polygon > 0, "ice crit keeps the comic starburst")
  truthy(calls.polygon > 4, "ice crit fills with ice shards")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local boltPaint = Projectiles.critBurst(session, "enemy", { moveType = "ELECTRIC" })
  boltPaint.age = 0.10
  boltPaint:draw(0, 0)
  truthy(calls.polygon > 0, "electric crit keeps the comic starburst")
  truthy(calls.line > 0, "electric crit fills with lightning forks")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local psyPaint = Projectiles.critBurst(session, "enemy", { moveType = "PSYCHIC" })
  psyPaint.age = 0.10
  psyPaint:draw(0, 0)
  truthy(calls.polygon > 0, "psychic crit keeps the comic starburst")
  truthy(calls.ellipse > 0, "psychic crit fills with rings")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local inkPaint = Projectiles.critBurst(session, "enemy", { moveType = "DARK" })
  inkPaint.age = 0.10
  inkPaint:draw(0, 0)
  truthy(calls.polygon > 0, "dark crit keeps the comic starburst")
  truthy(calls.ellipse > 0, "dark crit fills with an ink blot")

  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  Projectiles.contact(session, "player", {
    moveType = "NORMAL", moveId = "QUICK_ATTACK",
  })
  local dashPaint
  for i = 1, #(session.projectiles or {}) do
    if session.projectiles[i].style == "dash_smear" then
      dashPaint = session.projectiles[i]
    end
  end
  truthy(dashPaint, "quick attack spawns a dash smear")
  dashPaint.age = 0.16
  dashPaint:draw(0, 0)
  truthy(calls.line > 0, "quick attack smear paints speed lines")

  session._battle.game.overworld.map = {
    isWaterCell = function() return false end,
    isGrassCell = function() return true end,
  }
  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local grassKick = Projectiles.groundKick(session, "enemy")
  eq(grassKick.glitz, "grass", "grass tile kicks leaf blades")
  grassKick.age = 0.16
  grassKick:draw(0, 0)
  truthy(calls.polygon > 0, "grass kick paints leaf blades")

  session._battle.game.overworld.map = {
    isWaterCell = function() return false end,
    isGrassCell = function() return false end,
    isIceCell = function() return true end,
  }
  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local snowKick = Projectiles.groundKick(session, "enemy")
  eq(snowKick.glitz, "snow", "ice tile kicks snow")
  snowKick.age = 0.16
  snowKick:draw(0, 0)
  truthy(calls.polygon > 0, "snow kick paints ice crystals")

  session._battle.game.overworld.map = nil
  grid.water = grid.water or {}
  grid.water[Coords.key(enemy.padU, enemy.padV)] = true
  calls.polygon, calls.arc, calls.circle, calls.ellipse, calls.line = 0, 0, 0, 0, 0
  local waterKick = Projectiles.groundKick(session, "enemy")
  eq(waterKick.glitz, "water", "water pad kicks spray")
  waterKick.age = 0.16
  waterKick:draw(0, 0)
  truthy(calls.circle > 0, "water kick paints droplets")
  love = prevLove
end

function tests.ice_beam_shard_polygons_are_xy_pairs()
  local odd = 0
  local polygons = 0
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      setLineWidth = function() end,
      line = function() end,
      arc = function() end,
      ellipse = function() end,
      circle = function() end,
      rectangle = function() end,
      polygon = function(_, ...)
        polygons = polygons + 1
        if (select("#", ...) % 2) ~= 0 then
          odd = odd + 1
        end
      end,
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
  local ice = Projectiles.move(session, "player", {
    moveType = "ICE", moveId = "ICE_BEAM",
  })
  ice.age = 0.12
  ice:draw(0, 0)
  truthy(polygons > 0, "ice beam paints ice-shard polygons")
  eq(odd, 0, "ice beam polygon verts are x,y pairs")
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

function tests.camera_look_span_scales_with_world_view()
  local sx, sy = Lifecycle.mouseLookSpan(160, 144)
  eq(sx, Lifecycle.CAMERA_LOOK_SPAN, "classic view keeps a 56px peek X")
  eq(sy, Lifecycle.CAMERA_LOOK_SPAN, "classic view keeps a 56px peek Y")
  local wideX = select(1, Lifecycle.mouseLookSpan(320, 144))
  eq(wideX, Lifecycle.CAMERA_LOOK_SPAN * 2, "double-wide view doubles peek X")

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
      renderer = { worldViewSize = function() return 320, 144 end },
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
  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  local restX = followed.x
  Lifecycle.noteMouseLook(session, 1, 0, 8)
  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  Lifecycle._testUnbind(battle)
  truthy(followed.x > restX + Lifecycle.CAMERA_LOOK_SPAN,
    "wide world view peeks farther than the classic 56px span")
end

function tests.camera_look_zone_skips_touch_chrome()
  local sw, sh = 160, 144
  truthy(Lifecycle.mouseLookInZone(80, 72, sw, sh), "center is in the look zone")
  truthy(not Lifecycle.mouseLookInZone(8, 136, sw, sh),
    "bottom-left d-pad corner is outside the look zone")
  truthy(not Lifecycle.mouseLookInZone(152, 136, sw, sh),
    "bottom-right A/B corner is outside the look zone")
  truthy(Lifecycle.mouseLookAllowed(8, 136, sw, sh),
    "desktop may look from a corner")
  truthy(not Lifecycle.mouseLookAllowed(8, 136, sw, sh, { touchConstrained = true }),
    "touch overlay blocks look from the d-pad corner")
  truthy(Lifecycle.mouseLookAllowed(80, 72, sw, sh, { touchConstrained = true }),
    "touch overlay still allows look in the center")
  truthy(not Lifecycle.mouseLookAllowed(80, 72, sw, sh, { touchHit = true }),
    "a virtual-pad hit blocks look even at center")

  local session = {}
  eq(Lifecycle.tryMouseLook(session, 8, 136, sw, sh, 20, 0, { touchConstrained = true }),
    false, "d-pad corner motion does not arm look")
  eq(session.mouseLookT, nil, "look timer stays idle after a d-pad tap")
  truthy(Lifecycle.tryMouseLook(session, 80, 72, sw, sh, 20, 0, { touchConstrained = true }),
    "center motion arms look while the pad is up")
  truthy((session.mouseLookT or 0) > 0, "look timer is held from the inner viewport")
end

function tests.camera_idle_tour_orbits_pad()
  local sx, sy = Lifecycle.idleTourSpan(160, 144)
  eq(sx, Lifecycle.CAMERA_TOUR_SPAN_X, "classic view keeps the 20px tour X")
  eq(sy, Lifecycle.CAMERA_TOUR_SPAN_Y, "classic view keeps the 12px tour Y")
  eq(select(1, Lifecycle.idleTourSpan(320, 144)), Lifecycle.CAMERA_TOUR_SPAN_X * 2,
    "double-wide view doubles tour X")

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

  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  local restX, restY = followed.x, followed.y

  battle.phase = "menu"
  for _ = 1, 120 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  local tour1x, tour1y = followed.x, followed.y
  truthy(math.abs(tour1x - restX) > 2 or math.abs(tour1y - restY) > 2,
    "command idle lifts the camera off the tight battler lock")

  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  truthy(math.abs(followed.x - tour1x) > 2 or math.abs(followed.y - tour1y) > 2,
    "idle tour keeps drifting over the pad")

  battle.phase = "messages"
  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  Lifecycle._testUnbind(battle)

  eq(followed.x, restX, "action framing returns camera X after the tour")
  eq(followed.y, restY, "action framing returns camera Y after the tour")
end

function tests.camera_idle_tour_yields_to_mouse_look()
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
    phase = "menu",
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

  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  local tourX = followed.x

  Lifecycle.noteMouseLook(session, 1, 0, 8)
  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  Lifecycle._testUnbind(battle)

  truthy(followed.x > tourX + 8, "mouse look takes the lens from the idle tour")
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

  player:play("dodge")
  truthy(player._dodgeStyle, "dodge picks a style")
  for _ = 1, 40 do
    Cast.tick(session, 1 / 60)
  end
  eq(player.anim, "idle", "dodge returns to idle")

  player:play("attack")
  for _ = 1, 30 do
    Cast.tick(session, 1 / 60)
  end
  eq(player.anim, "idle", "attack returns to idle")
  Cast.tick(session, 0.10)
  eq(player.px, player.basePx, "idle bob has no horizontal sway")
  eq(player.py, player.basePy, "idle pose stays planted (legacy wave off)")

  enemy:play("faint")
  for _ = 1, 55 do
    Cast.tick(session, 1 / 60)
  end
  truthy(enemy._faintDone, "faint animation completes")
  truthy(enemy.hidden, "fainted sprite hides after the collapse")
end

function tests.seismic_toss_lifts_both_mons()
  local grid, plan = sampleGrid()
  local overworld = { entities = {} }
  local battle = {
    game = { overworld = overworld },
    player = { mon = { species = "TEST_PLAYER" } },
    enemy = { mon = { species = "TEST_ENEMY" } },
  }
  local session = {
    live = true,
    plan = plan,
    grid = grid,
    _now = 40,
    _deps = { Projectiles = Projectiles, Grid = Grid, Cast = Cast },
    _battle = battle,
  }
  local enemy = Cast.stageEnemy(session, battle, nil, Sprites, Grid)
  local player = Cast.stagePlayer(session, battle, nil, Sprites, Grid)
  truthy(Cues.apply(session, "player", "attack", Grid, nil, battle, {
    category = "physical",
    moveId = "SEISMIC_TOSS",
    moveType = "FIGHTING",
    followUp = true,
  }), "seismic toss cue")
  eq(player.anim, "toss", "attacker grabs and leaps")
  eq(enemy.anim, "tossed", "defender is carried up")
  local p0 = player.basePy
  local e0 = enemy.basePy
  for _ = 1, 24 do
    Cast.tick(session, 1 / 60)
  end
  truthy(player.py < p0 - 18, "attacker is high in the air")
  truthy(enemy.py < e0 - 18, "defender is high in the air")
  Cues.apply(session, "enemy", "hit", Grid, nil, battle, {
    category = "physical", moveId = "SEISMIC_TOSS",
  })
  eq(enemy.anim, "tossed", "hit pose waits for the slam")
  for _ = 1, 50 do
    Cast.tick(session, 1 / 60)
  end
  eq(player.anim, "idle", "attacker lands")
  eq(enemy.anim, "idle", "defender lands")
  Cues.tickTossLand(session, Grid)
  eq(enemy.anim, "hit", "slam plays the hit")
  truthy(math.abs((player.py or 0) - (player.basePy or 0)) < 12,
    "attacker is back on the ground")
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

function tests.field_jit_does_not_force_on_after_battle()
  local prev = rawget(_G, "jit")
  local calls = {}
  _G.jit = {
    status = function() return false end,
    on = function() calls[#calls + 1] = "on" end,
    off = function() calls[#calls + 1] = "off" end,
    flush = function() calls[#calls + 1] = "flush" end,
  }
  local battle = { game = {} }
  Lifecycle._testBind(battle, {
    live = true,
    state = "Live",
    _arJitOff = true,
    _arJitWasOn = false,
  })
  local ok, err = pcall(Lifecycle.finish, battle, {})
  Lifecycle._testUnbind(battle)
  _G.jit = prev
  truthy(ok, err or "finish with JIT already off")
  local sawOn = false
  for i = 1, #calls do
    if calls[i] == "on" then
      sawOn = true
    end
  end
  eq(sawOn, false, "must not jit.on() after battle when Love had the compiler off")
end

function tests.field_jit_restores_when_it_was_on()
  local prev = rawget(_G, "jit")
  local calls = {}
  _G.jit = {
    status = function() return true end,
    on = function() calls[#calls + 1] = "on" end,
    off = function() calls[#calls + 1] = "off" end,
    flush = function() calls[#calls + 1] = "flush" end,
  }
  local battle = { game = {} }
  Lifecycle._testBind(battle, {
    live = true,
    state = "Live",
    _arJitOff = true,
    _arJitWasOn = true,
  })
  local ok, err = pcall(Lifecycle.finish, battle, {})
  Lifecycle._testUnbind(battle)
  _G.jit = prev
  truthy(ok, err or "finish with JIT previously on")
  local sawOn = false
  for i = 1, #calls do
    if calls[i] == "on" then
      sawOn = true
    end
  end
  truthy(sawOn, "desktop JIT comes back after the fight")
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

function tests.hit_ground_follows_tile()
  local ent = { padU = 1, padV = 1, cellX = 4, cellY = 5, px = 16, py = 32 }
  local session = { grid = { water = {}, sizeU = 6, sizeV = 4 }, coverScene = "route" }
  eq(Projectiles.hitGround(session, ent), "dust", "bare route dirt kicks dust")

  session.grid.water[Coords.key(1, 1)] = true
  eq(Projectiles.hitGround(session, ent), "water", "water pad kicks spray")
  session.grid.water[Coords.key(1, 1)] = nil

  local grassBattle = {
    game = {
      overworld = {
        map = {
          isWaterCell = function() return false end,
          isGrassCell = function(_, x, y) return x == 4 and y == 5 end,
        },
      },
    },
  }
  eq(Projectiles.hitGround(session, ent, grassBattle), "grass", "grass tile kicks blades")

  local snowBattle = {
    game = {
      overworld = {
        map = {
          isWaterCell = function() return false end,
          isGrassCell = function() return false end,
          isIceCell = function(_, x, y) return x == 4 and y == 5 end,
        },
      },
    },
  }
  eq(Projectiles.hitGround(session, ent, snowBattle), "snow", "ice tile kicks snow")

  eq(Projectiles.hitGround({ coverScene = "gym", grid = {} }, { padU = 0, padV = 0 }),
    "spark", "gym floor kicks sparks")
  eq(Projectiles.hitGround({ coverScene = "water", grid = {} }, { padU = 0, padV = 0 }),
    "sand", "beach kit kicks sand")
  eq(Projectiles.hitGround({ coverScene = "cave", grid = {} }, { padU = 0, padV = 0 }),
    "cave", "cave kit kicks pebbles")
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

function tests.kit_candidate_paths_prefer_dex_then_name()
  local mod = { path = "/mods/anime_realism" }
  local game = { data = { pokemon = { CHARMANDER = { dex = 4 } } } }
  local paths = Sprites.kitCandidatePaths(mod, game, "CHARMANDER")
  eq(paths[1], "/mods/anime_realism/assets/followers/follower_004.png",
    "dex kit")
  eq(paths[2], "/mods/anime_realism/assets/followers/follower_004_normal.png",
    "optional normal alias")
  eq(paths[3], "/mods/anime_realism/assets/followers/CHARMANDER.png",
    "species name kit")
  eq(paths[4], "/mods/anime_realism/assets/followers/CHARMANDER_normal.png",
    "species normal kit")
end

function tests.kit_block_uses_combat_rows()
  eq(Sprites.kitBlockForAnim("idle", 6), 0, "idle is walk on a 6-block kit")
  eq(Sprites.kitBlockForAnim("idle", 7), 6, "idle is the extra 7th block")
  eq(Sprites.kitBlockForAnim("idle", 8), 6, "idle stays 7th when faint is present")
  eq(Sprites.kitBlockForAnim("faint", 7), 0, "faint falls back without the 8th block")
  eq(Sprites.kitBlockForAnim("faint", 8), 7, "faint is the extra 8th block")
  eq(Sprites.kitBlockForAnim("walk", 7), 0, "walk stays the top block")
  eq(Sprites.kitBlockForAnim("dodge", 6), 1, "dodge block")
  eq(Sprites.kitBlockForAnim("brace", 6), 2, "brace block")
  eq(Sprites.kitBlockForAnim("attack", 6), 3, "physical block")
  eq(Sprites.kitBlockForAnim("jump", 6), 3, "jump uses physical on a short kit")
  eq(Sprites.kitBlockForAnim("counter", 6), 3, "counter uses physical on a short kit")
  eq(Sprites.kitBlockForAnim("miss", 6), 3, "miss uses physical on a short kit")
  eq(Sprites.kitBlockForAnim("cast", 6), 4, "special block")
  eq(Sprites.kitBlockForAnim("charge", 8), 4, "charge uses special until the extra row")
  eq(Sprites.kitBlockForAnim("hit", 6), 5, "hit block")
  eq(Sprites.kitBlockForAnim("selfhit", 6), 5, "recoil uses hit")
  eq(Sprites.kitBlockForAnim("dodge", 1), 0, "missing dodge stays on walk")
  eq(Sprites.kitBlockForAnim("cast", 3), 0, "missing special stays on walk")
  eq(Sprites.kitBlockForAnim("charge", 16), 8, "charge is the 9th block")
  eq(Sprites.kitBlockForAnim("jump", 16), 9, "jump is its own row")
  eq(Sprites.kitBlockForAnim("counter", 16), 10, "counter is its own row")
  eq(Sprites.kitBlockForAnim("miss", 16), 11, "miss is its own row")
  eq(Sprites.kitBlockForAnim("sleep", 8), 6, "sleep uses idle on an 8-block kit")
  eq(Sprites.kitBlockForAnim("sleep", 16), 12, "sleep is its own row")
  eq(Sprites.kitBlockForAnim("freeze", 16), 13, "freeze is its own row")
  eq(Sprites.kitBlockForAnim("confuse", 16), 14, "confuse is its own row")
  eq(Sprites.kitBlockForAnim("float", 16), 15, "float is its own row")
  eq(Sprites.kitBlockForAnim("tumble", 16), 5, "tumble uses hit until the extra row")
  eq(Sprites.kitBlockForAnim("tumble", 17), 16, "tumble is the 17th block")
  eq(Sprites.kitBlockForAnim("flap", 16), 0, "flap is walk without the extra row")
  eq(Sprites.kitBlockForAnim("flap", 17), 0, "flap is walk when only tumble is present")
  eq(Sprites.kitBlockForAnim("flap", 18), 17, "flap is the 18th block")
  eq(Sprites.kitBlockForAnim("dodge", 16, { _dodgeStyle = "lift" }), 15,
    "flying dodge uses float")
  eq(Sprites.kitBlockForAnim("dodge", 8, { _dodgeStyle = "lift" }), 1,
    "flying dodge stays dodge without float")
  eq(Sprites.kitBlockForAnim("dodge", 16, { _dodgeStyle = "phase" }), 1,
    "ghost dodge keeps the dodge row")
end

function tests.kit_idle_override_follows_status()
  eq(Sprites.kitIdleOverride({
    _battleBattler = { mon = { status = "SLP" } },
  }, false), "sleep", "asleep standing uses sleep")
  eq(Sprites.kitIdleOverride({
    _battleBattler = { mon = { status = "SLP" } },
  }, true), nil, "a shove while asleep still uses walk")
  eq(Sprites.kitIdleOverride({
    _battleBattler = { mon = { status = "FRZ" } },
  }, false), "freeze", "frozen standing uses freeze")
  eq(Sprites.kitIdleOverride({
    _battleBattler = { confusedTurns = 3, mon = {} },
  }, false), nil, "confused standing stays on Idle, not Rotate")
  eq(Sprites.kitIdleOverride({
    _battleBattler = { mon = { status = "PAR" } },
  }, false), nil, "para stays idle")
end

function tests.kit_move_override_flaps_when_flying()
  local pidgeot = {
    _kitSheet = true,
    _kitBlocks = 18,
    _flapWalk = true,
    _battleBattler = { curTypes = { "NORMAL", "FLYING" } },
  }
  eq(Sprites.kitMoveOverride(pidgeot, true), "flap",
    "Pidgeot flaps when the burst says so")
  pidgeot._flapWalk = false
  eq(Sprites.kitMoveOverride(pidgeot, true), nil,
    "same burst can stay on Walk")
  eq(Sprites.kitMoveOverride({
    _kitSheet = true,
    _kitBlocks = 18,
    _flapWalk = true,
    _battleBattler = { curTypes = { "FIRE" } },
  }, true), nil, "ground types do not flap")
  eq(Sprites.kitMoveOverride({
    _kitSheet = true,
    _kitBlocks = 16,
    _flapWalk = true,
    _battleBattler = { curTypes = { "FLYING" } },
  }, true), nil, "no FlapAround row stays on Walk")
  eq(Sprites.kitMoveOverride(pidgeot, false), nil, "standing clears the flap burst")
  eq(pidgeot._flapWalk, nil, "next walk can roll flap again")
end

function tests.physical_kit_prefers_specialized_strips()
  local meta = Sprites.parseKitMeta(table.concat({
    "kit 32 8",
    "walk 8 10 8 10",
    "physical 2 4 2 2",
    "idle 8 8",
    "faint 8 8",
    "flap 4 4 4 4",
    "kick 2 2 2 4",
    "punch 2 6 2",
    "multi 2 2 2 2 2",
  }, "\n"))
  local _, _, poseBlock = Sprites.kitMetaBlockTables(meta)
  eq(poseBlock.flap, 17, "flap stays on its fixed row")
  eq(poseBlock.kick, 18, "kick follows flap")
  eq(poseBlock.punch, 19, "punch follows kick")
  eq(poseBlock.multi, 20, "multi follows punch")
  local noFlap = Sprites.parseKitMeta(table.concat({
    "kit 32 8",
    "walk 8 10 8 10",
    "physical 2 4 2 2",
    "multi 2 2 2 2",
  }, "\n"))
  local _, _, noFlapBlocks = Sprites.kitMetaBlockTables(noFlap)
  eq(noFlapBlocks.multi, 17, "multi takes the flap slot when flap is missing")
  local ent = {
    _kitSheet = true,
    _kitBlocks = 21,
    _kitPoseBlock = poseBlock,
  }
  truthy(Sprites.kitHasPose(ent, "multi"), "sidecar lists multi")
  truthy(Sprites.usesKitPose(ent, "kick"), "kick row is a combat pose")
  eq(Cues.physicalKitAnim(ent, { moveId = "TACKLE" }, Sprites), "attack",
    "generic contact keeps Attack when both exist")
  eq(Cues.physicalKitAnim(ent, { moveId = "FURY_ATTACK" }, Sprites), "multi",
    "multi-hit uses MultiStrike / Double")
  eq(Cues.physicalKitAnim(ent, { moveId = "DOUBLE_KICK" }, Sprites), "multi",
    "Double Kick prefers multi over kick")
  eq(Cues.physicalKitAnim(ent, { moveId = "LOW_KICK" }, Sprites), "kick",
    "single kick uses Kick")
  eq(Cues.physicalKitAnim(ent, { moveId = "MEGA_PUNCH" }, Sprites), "punch",
    "punch move uses Punch")
  local kickOnly = {
    _kitSheet = true,
    _kitBlocks = 19,
    _kitPoseBlock = { physical = 3, kick = 18 },
  }
  eq(Cues.physicalKitAnim(kickOnly, { moveId = "DOUBLE_KICK" }, Sprites), "kick",
    "multi-hit falls back to Kick when Multi is missing")
  eq(Cues.physicalKitAnim({ _kitSheet = true }, { moveId = "FURY_ATTACK" }, Sprites),
    "attack", "no sidecar extras stay on Attack")
end

function tests.golem_attack_kit_is_special0()
  local path = root .. "/../assets/followers/follower_076.kit"
  local f = io.open(path, "r")
  truthy(f, "Golem kit sidecar is present")
  local body = f:read("*a") or ""
  f:close()
  local line = body:match("physical[^\n]+")
  eq(line, "physical 6 6 6 6 6 6", "Golem Attack is Special0, not the punch strip")
  truthy(not body:find("\nroll ", 1, true), "Golem has no extra roll row")
  eq(Sprites.kitMoveOverride({
    _kitSheet = true,
    _spriteSpecies = "GOLEM",
    _kitPoseBlock = { physical = 3, confuse = 14 },
  }, true), nil, "Golem still walks on Walk")
  eq(Cues.physicalKitAnim({
    _kitSheet = true,
    _spriteSpecies = "GOLEM",
    _kitPoseBlock = { physical = 3 },
  }, { moveId = "TACKLE" }, Sprites), "attack",
    "Golem's strike is the physical row")
end

function tests.pose_keeps_kit_on_the_plant()
  local grid, plan = sampleGrid()
  local overworld = { entities = {} }
  local battle = {
    game = { overworld = overworld },
    player = { mon = { species = "TEST_PLAYER" } },
    enemy = { mon = { species = "TEST_ENEMY" } },
  }
  local session = { plan = plan, grid = grid }
  Cast.stageEnemy(session, battle, nil, Sprites, Grid)
  local player = Cast.stagePlayer(session, battle, nil, Sprites, Grid)
  player._kitSheet = true
  player._kitCell = 32
  player._fieldBarLift = 24
  player.px, player.py = 16, 64
  local sprite, vx, vy = player:pose()
  truthy(sprite, "pose returns a sprite")
  eq(vx, 16, "vx stays on the plant x")
  eq(vy, 64, "vy stays on py so the body does not float off its shadow")
end

function tests.kit_pose_requires_combat_block()
  local kit = { _kitSheet = true, _kitBlocks = 6 }
  truthy(Sprites.usesKitPose(kit, "dodge"), "full kit plays dodge")
  truthy(Sprites.usesKitPose(kit, "attack"), "full kit plays physical")
  truthy(not Sprites.usesKitPose(kit, "idle"), "walk is not a combat pose")
  truthy(not Sprites.usesKitPose({ _kitSheet = true, _kitBlocks = 1 }, "dodge"),
    "walk-only kit keeps old hop")
  truthy(not Sprites.usesKitPose({ _kitBlocks = 6 }, "dodge"),
    "non-kit sheet keeps old hop")
  truthy(Sprites.usesKitPose({ _kitSheet = true, _kitBlocks = 6 }, "jump"),
    "short kit jump still uses physical")
  truthy(Sprites.usesKitPose({ _kitSheet = true, _kitBlocks = 16 }, "charge"),
    "tall kit plays charge")
  truthy(Sprites.usesKitPose({ _kitSheet = true, _kitBlocks = 17 }, "tumble"),
    "tumble row plays when present")
  truthy(Sprites.usesKitPose({ _kitSheet = true, _kitBlocks = 16 }, "sleep"),
    "tall kit plays sleep")
  truthy(Sprites.usesKitPose({ _kitSheet = true, _kitBlocks = 8 }, "faint"),
    "8-block kit plays faint")
  truthy(not Sprites.usesKitPose({ _kitSheet = true, _kitBlocks = 7 }, "faint"),
    "no faint block keeps the shrink")
end

function tests.kit_dodge_keeps_slide_without_squash()
  local grid, plan = sampleGrid()
  local overworld = { entities = {} }
  local battle = {
    game = { overworld = overworld },
    player = { mon = { species = "TEST_PLAYER" } },
    enemy = { mon = { species = "TEST_ENEMY" } },
  }
  local session = { plan = plan, grid = grid }
  Cast.stageEnemy(session, battle, nil, Sprites, Grid)
  local player = Cast.stagePlayer(session, battle, nil, Sprites, Grid)
  player._kitSheet = true
  player._kitBlocks = 6
  player:play("dodge")
  player._dodgeStyle = "duck"
  Cast.tick(session, 1 / 60)
  eq(player.drawScaleX, nil, "kit dodge does not squash x")
  eq(player.drawScaleY, nil, "kit dodge does not squash y")
  eq(player.drawAlpha, 1, "kit dodge stays opaque")
  eq(player.drawAngle, 0, "kit dodge does not lean")
  player:play("attack")
  Cast.tick(session, 0.16)
  eq(player.drawScale, 1, "kit punch does not scale up")
  player._kitBlocks = 16
  player:play("dodge")
  player._dodgeStyle = "phase"
  Cast.tick(session, 1 / 60)
  truthy(player.drawAlpha < 1, "ghost kit dodge goes paler")
  player:play("dodge")
  player._dodgeStyle = "hop"
  Cast.tick(session, 0.21)
  eq(player.drawScaleX, nil, "kit hop does not squash x")
  eq(player.drawScaleY, nil, "kit hop does not squash y")
  truthy(player.py < player.basePy - 4, "kit hop leaves the ground")
end

function tests.kit_col_walk_and_combat()
  eq(Sprites.kitColForAnim({ _walkT = 0 }, "idle", false), 0, "idle column")
  eq(Sprites.kitColForAnim({ _idleT = 0.48 }, "idle", false), 3,
    "standing walk plays the whole row, not rest 0/2")
  eq(Sprites.kitColForAnim({ _walkT = 0.2, _kitBlocks = 7 }, "idle", true), 1,
    "moving uses walk columns")
  eq(Sprites.kitColForAnim({ _idleT = 0.36, _kitBlocks = 7 }, "idle", false), 2,
    "dedicated idle loops all frames")
  eq(Sprites.kitColForAnim({ _walkT = 0.2 }, "idle", true), 1, "walk step column")
  eq(Sprites.kitColForAnim({ animT = 0 }, "attack", false), 0, "physical start")
  eq(Sprites.kitColForAnim({ animT = 0.18 }, "attack", false), 2, "physical recover")
  eq(Sprites.kitColForAnim({ animT = 0.4 }, "cast", false), 3, "special settle")
  eq(Sprites.kitColForAnim({ animT = 0.7, _kitBlocks = 8 }, "faint", false), 3,
    "faint settles on the last column")
  eq(Sprites.kitColForAnim({ animT = 0.30, _kitBlocks = 8 }, "faint", false), 2,
    "faint collapse uses mid frames before the hold")
  eq(Sprites.kitColForAnim({ animT = 0.25 }, "charge", false), 2,
    "charge loops while held")
  eq(Sprites.kitColForAnim({ _idleT = 0 }, "freeze", false), 0,
    "freeze holds the first frame")
  eq(Sprites.kitColForAnim({ _idleT = 0.56 }, "sleep", false), 2,
    "sleep loops the whole row")
end

function tests.kit_meta_plays_full_pmd_row()
  local meta = Sprites.parseKitMeta(table.concat({
    "# baked from 0005",
    "kit 32 14",
    "walk 8 10 8 10",
    "physical 2 2 2 2 4 1 1 2 2 2 2 2 2 2",
    "idle 40 2 3 3 3 2",
    "faint 2 2 2 8",
  }, "\n"))
  truthy(meta, "sidecar parses")
  eq(meta.cols, 14, "sheet width in cells")
  eq(meta.poses.physical.frames, 14, "attack keeps every PMD column")
  eq(meta.poses.idle.frames, 6, "idle is the breathe loop, not 4")
  local colsByBlock, ticksByBlock = Sprites.kitMetaBlockTables(meta)
  eq(colsByBlock[3], 14, "physical block is 14 wide")
  eq(colsByBlock[6], 6, "idle block is 6 wide")
  local ent = {
    _kitSheet = true,
    _kitBlocks = 8,
    _kitCols = 14,
    _kitColsByBlock = colsByBlock,
    _kitTicksByBlock = ticksByBlock,
  }
  eq(Sprites.kitFrameCount(ent, "attack"), 14, "physical uses the full row")
  eq(Sprites.kitFrameCount(ent, "idle"), 6, "idle uses its own length")
  eq(Sprites.kitColForAnim(ent, "attack", false), 0, "attack starts on col 0")
  local clip = Sprites.kitClipDuration(ent, "attack", 0.34)
  truthy(clip > 0.34, "full strip holds the clip open")
  ent.animT = clip * 0.55
  local mid = Sprites.kitColForAnim(ent, "attack", false)
  truthy(mid >= 6 and mid <= 13, "attack mid-clip is past the old 4-frame pick")
  ent.animT = clip
  eq(Sprites.kitColForAnim(ent, "attack", false), 13, "attack settles on last col")
  ent._idleT = 0
  eq(Sprites.kitColForAnim(ent, "idle", false), 0, "idle starts on col 0")
  local looped = Sprites.kitLoopTicks(meta.poses.idle.ticks, "idle")
  eq(looped[1], 16, "40-tick PMD rest is clamped, then idle is slowed")
  ent._idleT = looped[1] / 60 + 0.001
  eq(Sprites.kitColForAnim(ent, "idle", false), 1, "idle advances through the row")
  ent.animT = 1
  eq(Sprites.kitColForAnim(ent, "faint", false), 3, "faint still holds last crumple")
  eq(Sprites.kitColFromUnit(0.5, 14, meta.poses.physical.ticks) >= 4, true,
    "unit map reaches past four sampled frames")
  eq(Sprites.kitFrameCount({ _kitCols = 14 }, "idle"), 4,
    "sheet width is not a pose length")
end

function tests.kit_charge_hold_until_shoot()
  local grid, plan = sampleGrid()
  local overworld = { entities = {} }
  local battle = {
    game = { overworld = overworld },
    player = { mon = { species = "TEST_PLAYER" } },
    enemy = { mon = { species = "TEST_ENEMY" } },
  }
  local session = { plan = plan, grid = grid, live = true }
  Cast.stageEnemy(session, battle, nil, Sprites, Grid)
  local player = Cast.stagePlayer(session, battle, nil, Sprites, Grid)
  player._kitSheet = true
  player._kitBlocks = 16
  player:play("charge")
  Cast.tick(session, 0.50)
  eq(player.anim, "charge", "charge does not drop to idle")
  player:play("cast")
  eq(player.anim, "cast", "Shoot plays when the shot leaves")
end

function tests.cast_cue_holds_charge_on_kit()
  local grid, plan = sampleGrid()
  local overworld = { entities = {} }
  local battle = {
    game = { overworld = overworld },
    player = { mon = { species = "TEST_PLAYER" } },
    enemy = { mon = { species = "TEST_ENEMY" } },
  }
  local session = { plan = plan, grid = grid, live = true }
  Cast.stageEnemy(session, battle, nil, Sprites, Grid)
  local player = Cast.stagePlayer(session, battle, nil, Sprites, Grid)
  player._kitSheet = true
  player._kitBlocks = 16
  session._deps = { Sprites = Sprites }
  truthy(Cues.apply(session, "player", "cast", Grid, nil, battle, {}),
    "FIRE overlapping pose plays")
  eq(player.anim, "charge", "kit FIRE pose holds Charge")
end

function tests.kit_faint_then_recall_keeps_crumple()
  local grid, plan = sampleGrid()
  local pHome = grid.home.player
  grid.home.playerTrainer = { u = pHome.u - 1, v = pHome.v }
  local overworld = { entities = {} }
  local battle = {
    game = { overworld = overworld },
    player = { mon = { species = "TEST_PLAYER" } },
    enemy = { mon = { species = "TEST_ENEMY" } },
  }
  local session = { plan = plan, grid = grid, live = true, _battle = battle }
  Cast.stageEnemy(session, battle, nil, Sprites, Grid)
  local player = Cast.stagePlayer(session, battle, nil, Sprites, Grid)
  player._kitSheet = true
  player._kitBlocks = 16
  player.anim = "idle"
  player._sendoutStarted = nil
  player.px, player.py = 16, 32
  session._deps = { Sprites = Sprites, Projectiles = Projectiles }
  truthy(Cues.apply(session, "player", "faint", Grid, nil, battle, {}),
    "kit faint cue")
  eq(player.anim, "faint", "trainer faint plays the collapse first")
  truthy(player._recallAfterFaint, "laser waits for the crumple")
  Cast.tick(session, Sprites.KIT_FAINT_PLAY + Sprites.KIT_FAINT_HOLD + 0.02)
  eq(player.anim, "recall", "crumple hands off to the recall laser")
  eq(player._kitBlock, 7, "recall still shows the faint block")
  eq(player._kitCol, 3, "recall holds the last crumpled frame")
  truthy(not player.hidden, "sprite stays visible while the laser sucks them up")
end

function tests.kit_cell_origin_uses_block_facing_and_col()
  local u, v = Sprites.kitCellOrigin({
    _kitBlock = 3, _kitCol = 1, facing = "left",
  }, "left")
  eq(u, 32, "col 1 is 32px x")
  eq(v, 416, "physical left is row 13")
  u, v = Sprites.kitCellOrigin({ _kitBlock = 0, _kitCol = 0 }, "down")
  eq(u, 0, "walk front origin x")
  eq(v, 0, "walk front origin y")
  u, v = Sprites.kitCellOrigin({ _kitBlock = 0, _kitCol = 0 }, "right")
  eq(v, 64, "walk right is its own row, not a flipped left")
  u, v = Sprites.kitCellOrigin({
    _kitBlock = 0, _kitCol = 1, _kitCell = 38,
  }, "down")
  eq(u, 38, "large-mon kits use the sidecar cell size")
  eq(Sprites.kitCellSize({ _kitCell = 48 }), 48,
    "hop-overflow cells stay in range")
  local eight = { _kitBlock = 0, _kitCol = 0, _kitFaces = 8 }
  u, v = Sprites.kitCellOrigin(eight, "down-right")
  eq(u, 0, "diagonal origin x")
  eq(v, 128, "walk down-right is row 4 on an 8-face kit")
  u, v = Sprites.kitCellOrigin({
    _kitBlock = 3, _kitCol = 1, _kitFaces = 8, facing = "left",
  }, "left")
  eq(v, 800, "8-face physical left is row 25")
  eq(Sprites.kitFaceIndex({ _kitFaces = 4 }, "down-right"), 2,
    "4-face kits snap a diagonal to the side")
end

function tests.kit_idle_stays_on_idle_block_when_8face()
  local meta = Sprites.parseKitMeta(table.concat({
    "kit 45 16 8",
    "walk 8 10 8 10",
    "dodge 2 2",
    "brace 2 8",
    "physical 4 2",
    "special 2 8",
    "hit 2 8",
    "idle 40 2 2 2",
    "faint 30 35",
  }, "\n"))
  eq(meta.faces, 8, "sidecar stores 8 faces")
  eq(#meta.poses.idle.ticks, 4, "idle keeps every breathe column")
  local colsBy, ticksBy, poseBlock = Sprites.kitMetaBlockTables(meta)
  eq(poseBlock.idle, 6, "idle stays the 7th block")
  eq(poseBlock.faint, 7, "faint stays after idle")
  eq(colsBy[6], 4, "idle frame count is the sidecar row")
  eq(#ticksBy[7], 2, "faint ticks do not replace idle")
  local ent = {
    _kitBlock = 6, _kitCol = 0, _kitFaces = 8, _kitCell = 45,
    _kitBlocks = 18, _kitPoseBlock = poseBlock,
    _kitColsByBlock = colsBy, _kitTicksByBlock = ticksBy,
    _idleT = 0,
  }
  eq(Sprites.kitBlockForAnim("idle", 18, ent), 6, "standing uses idle")
  eq(Sprites.kitFrameCount(ent, "idle"), 4, "all idle columns play")
  local _, v = Sprites.kitCellOrigin(ent, "down")
  eq(v, 6 * 8 * 45, "idle down is block 6 × 8 rows")
  _, v = Sprites.kitCellOrigin(ent, "down-right")
  eq(v, (6 * 8 + 4) * 45, "idle diagonal stays inside idle")
  _, v = Sprites.kitCellOrigin({
    _kitBlock = 7, _kitCol = 0, _kitFaces = 8, _kitCell = 45,
  }, "down")
  eq(v, 7 * 8 * 45, "faint is the next 8-row block")
  eq(Sprites.kitFacesFromSheet(720, 6480, 45, meta), 8,
    "18 poses × 144 rows is 8-face even if tagged 4")
  local stale = Sprites.parseKitMeta("kit 45 16\nwalk 2\ndodge 2\nbrace 2\n"
    .. "physical 2\nspecial 2\nhit 2\nidle 2\nfaint 2\n")
  eq(stale.faces, 4, "old sidecar omits the 8")
  eq(Sprites.kitFacesFromSheet(720, 6480, 45, stale), 8,
    "image height beats a stale 4-face tag")
  eq(Sprites.kitBlockForAnim("idle", 18, { _kitPoseBlock = { walk = 0, faint = 6 } }),
    0, "missing Idle falls back to Walk, not Faint")
end

function tests.kit_face_from_delta_uses_diagonals()
  eq(Sprites.faceFromDelta(10, 0), "right", "east is right")
  eq(Sprites.faceFromDelta(0, 10), "down", "south is down")
  eq(Sprites.faceFromDelta(10, 10), "down-right", "southeast is diagonal")
  eq(Sprites.faceFromDelta(-8, -8), "up-left", "northwest is diagonal")
  eq(Sprites.faceFromDelta(10, 2), "right", "shallow angle stays cardinal")
  eq(Sprites.cardinalFacing("down-right"), "right", "voxel gets a cardinal")
  eq(Sprites.billboardFacing("down-right", true), "left",
    "kit diagonal does not GSC-flip")
  eq(Sprites.billboardFacing("up", true), "up", "kit up stays up")
end

function tests.dig_uses_baked_diglett_walk()
  eq(Sprites.kitBorrowSpec("vanish_dig"), nil, "Dig does not borrow a sheet")
  eq(Sprites.KIT_POSE_NAME.vanish_dig, "dig", "vanish plays the dig row")
  eq(Sprites.KIT_POSE_NAME.buried, "dig", "buried plays the dig row")
  eq(Sprites.KIT_POSE_NAME.emerge_dig, "dig", "emerge plays the dig row")
  local hasDig = false
  for i = 1, #(Sprites.KIT_TRAILING or {}) do
    if Sprites.KIT_TRAILING[i] == "dig" then
      hasDig = true
    end
  end
  truthy(hasDig, "dig is a trailing kit pose")
  local map = Sprites.kitPoseBlockMap({
    poses = {
      walk = { frames = 3, ticks = { 8, 8, 8 } },
      dig = { frames = 3, ticks = { 8, 8, 8 } },
    },
  })
  eq(map.dig, 17, "dig sits after the flap slot")
  local kitPath = root .. "/../assets/followers/follower_076.kit"
  local f = io.open(kitPath, "r")
  truthy(f, "Golem kit is on disk")
  local text = f:read("*a")
  f:close()
  local meta = Sprites.parseKitMeta(text)
  truthy(meta.poses.dig, "Golem kit includes the shared dig row")
  eq(meta.poses.dig.frames, 3, "dig is Diglett Walk's three frames")
end

function tests.kit_shadow_origin_stays_on_planted_column()
  local u, v = Sprites.kitShadowOrigin({
    _kitBlock = 1, _kitCol = 5, facing = "down",
  }, "down")
  eq(u, 0, "shadow uses column 0, not the hopped cell")
  eq(v, 128, "shadow stays on the dodge front row")
end

function tests.kit_billboard_does_not_mirror_right()
  eq(Sprites.billboardFacing("right", true), "left",
    "kit right is drawn, not GSC-flipped")
  eq(Sprites.billboardFacing("left", true), "left", "kit left stays left")
  eq(Sprites.billboardFacing("down", true), "down", "kit down stays down")
  eq(Sprites.billboardFacing("right", false), "right",
    "GSC sheets still flip right")
end

function tests.kit_billboards_stay_outermost_after_wilds_wrap()
  local lastVerts
  local SB = {
    mesh = function(def, frame)
      return { via = "orig", frame = frame }
    end,
  }
  local Voxel3D = {
    pushQuad = function() end,
    newMesh = function(verts)
      lastVerts = verts
      return { verts = verts, via = "kit" }
    end,
  }
  local mod = {
    find = function(_, id)
      if id == "DRAMATIC_SHAPE" then
        return {
          exports = {
            lib = {
              require = function(name)
                if name == "SpriteBillboards" then
                  return SB
                end
                if name == "Voxel3D" then
                  return Voxel3D
                end
              end,
            },
          },
        }
      end
    end,
  }
  truthy(Sprites.installKitBillboards(mod), "first wrap installs")
  eq(SB.mesh, SB._arKitWrapper, "wrapper is live mesh()")
  -- Wilds variable-geometry wrap steals mesh() for every 32px def.
  local inner = SB.mesh
  SB.mesh = function(def, frame)
    if type(def) == "table" and def.frameWidth == 32 then
      return { via = "wilds", frame = frame }
    end
    return inner(def, frame)
  end
  truthy(Sprites.installKitBillboards(mod), "rewrap after steal")
  eq(SB.mesh, SB._arKitWrapper, "kit wrap is outermost again")
  local fakeImg = {
    getDimensions = function()
      return 128, 768
    end,
  }
  local kitMesh = SB.mesh({
    kit = true,
    image = "kit.png",
    kitImage = fakeImg,
    kitU = 32,
    kitV = 64,
    frameWidth = 32,
    frameHeight = 32,
  }, 2)
  eq(kitMesh.via, "kit", "kit def does not use Wilds column-0 card")
  truthy(lastVerts and lastVerts[1], "kit card has verts")
  eq(lastVerts[1][2], 0, "body quad plants at y=0")
  eq(lastVerts[3][2], 32, "32px body top is the cell height")
  local u0 = lastVerts[1][4]
  local expect = (32 + 0.02) / 128
  assert(math.abs(u0 - expect) < 1e-6, "kit UVs sample column 1, not 0")
  local shadowMesh = SB.shadowQuad({
    kit = true,
    image = "kit.png",
    kitImage = fakeImg,
    kitU = 32,
    kitV = 64,
    kitShadowU = 0,
    kitShadowV = 64,
    frameWidth = 32,
    frameHeight = 32,
  }, 2)
  eq(shadowMesh.via, "kit", "kit shadow stays on the kit sheet")
  eq(lastVerts[1][2], 0, "shadow quad stays planted at y=0")
  local shadowU = lastVerts[1][4]
  local planted = (0 + 0.02) / 128
  assert(math.abs(shadowU - planted) < 1e-6, "ground blob samples planted column 0")
  local vanilla = SB.mesh({ image = "npc.png", frames = 6 }, 3)
  eq(vanilla.via, "orig", "vanilla GSC strip still uses original mesh")
end

function tests.kit_sheet_beats_wilds_when_present()
  local kit = root .. "/../assets/followers/follower_025.png"
  local f = io.open(kit, "rb")
  if not f then
    return
  end
  f:close()
  local mod = {
    path = root .. "/..",
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
                image = "/wilds/" .. tostring(opts.species) .. ".png",
                frames = 6,
                providerId = "pokemmo",
              }
            end,
          },
        }
      end
    end,
  }
  local game = { data = { pokemon = { PIKACHU = { dex = 25 } } } }
  local sheet = Sprites.resolveSheet(mod, game, "PIKACHU")
  truthy(sheet and sheet.kit, "baked kit wins over Wilds")
  truthy(sheet.image:find("follower_025%.png$"), "dex kit path")
  local meta = Sprites.kitMetaFromPath(kit)
  local cell = (meta and tonumber(meta.cell)) or Sprites.KIT_CELL
  -- Hop overflow / large mons write 40+ into the sidecar; do not assume 32.
  truthy(cell >= Sprites.KIT_CELL and cell <= Sprites.KIT_CELL_MAX,
    "sidecar cell stays in the bake range")
  eq(sheet.frameWidth, cell, "sheet uses sidecar cell size")
  eq(sheet.trueColor, true, "true-color kit")
  eq((meta and tonumber(meta.faces)) or 4, 8, "rebaked Pikachu kit is 8-face")
end

function tests.projectile_style_registry_is_public()
  eq(type(Projectiles.registerStyle), "function", "styles register by name")
end

function tests.hand_arena_layout_matches_authored_pad()
  local route = Themes.layout("route")
  truthy(route and route.id == "route", "arenas/route.lua registered")
  local kit = Themes.kit("route")
  truthy(kit.layout, "hand layout attached to kit")
  eq(kit.layout.sizeU, 10, "authored route width")
  local pad = Coords.layoutPad({ minX = 0, maxX = 9, minY = 0, maxY = 4 }, 1, 0)
  eq(pad.sizeU, 10, "matching pad width")
  eq(pad.sizeV, 5, "matching pad height")
  local plan = {
    pCellX = 0, pCellY = 2, eCellX = 9, eCellY = 2,
    pMonX = 3, pMonY = 2, eMonX = 6, eMonY = 2,
    sx = 1, sy = 0, midX = 4.5, midY = 2,
  }
  local battle = { currentMapId = function() return "ROUTE_1" end }
  local arena = Arena.generate(battle, plan, 1, {
    pad = pad,
    gridRect = { minX = 0, maxX = 9, minY = 0, maxY = 4 },
  })
  truthy(arena.handcrafted, "matching pad uses arenas/route.lua")
end

function tests.hooks_wrap_groups_attach()
  eq(type(Hooks.installDraw), "function", "draw wraps")
  eq(type(Hooks.installInput), "function", "input wraps")
  eq(type(Hooks.installEvents), "function", "event wraps")
end

do
  local fxFile = root:gsub("field$", "battle") .. "/fx.lua"
  local chunk, err = loadfile(fxFile)
  assert(chunk, err)
  local BattleFx = chunk()
  BattleFx.bind({
    isFireNowShot = function(_, opts)
      return Projectiles.isFireNowShot(opts)
    end,
  })

  function tests.counter_strike_uses_only_known_moves()
    local battle = {
      data = {
        moves = {
          EMBER = { id = "EMBER", power = 40, category = "special", type = "FIRE" },
          GROWL = { id = "GROWL", power = 0, category = "status", type = "NORMAL" },
          HEADBUTT = { id = "HEADBUTT", power = 70, category = "physical", type = "NORMAL" },
          MEGA_PUNCH = { id = "MEGA_PUNCH", power = 80, category = "physical", type = "NORMAL" },
          SCRATCH = { id = "SCRATCH", power = 40, category = "physical", type = "NORMAL" },
          FURY_ATTACK = { id = "FURY_ATTACK", power = 15, category = "physical", type = "NORMAL" },
        },
      },
      moveDef = function(self, inst)
        return inst and self.data.moves[inst.id]
      end,
      player = {
        curMoves = {
          { id = "SCRATCH", pp = 35 },
          { id = "GROWL", pp = 40 },
          { id = "EMBER", pp = 25 },
        },
      },
      enemy = {
        curMoves = {
          { id = "FURY_ATTACK", pp = 20 },
          { id = "GROWL", pp = 40 },
        },
      },
    }
    eq(BattleFx.pickCounterStrikeMove(battle, "brace", battle.player), "SCRATCH",
      "player brace uses a physical move they know")
    eq(BattleFx.pickCounterStrikeMove(battle, "brace", battle.enemy), "FURY_ATTACK",
      "foe brace uses a physical move they know")
    battle.player.curMoves = { { id = "EMBER", pp = 25 }, { id = "GROWL", pp = 40 } }
    eq(BattleFx.pickCounterStrikeMove(battle, "brace", battle.player), "EMBER",
      "special is used when that's the only damaging move known")
    eq(BattleFx.pickCounterStrikeMove(battle, "brace", { curMoves = {} }), nil,
      "empty set does not invent HEADBUTT from the dex")
    eq(BattleFx.pickCounterStrikeMove(battle, "brace", battle.player) ~= "HEADBUTT", true,
      "dex HEADBUTT stays unused")
    battle.player.curMoves = {
      { id = "SCRATCH", pp = 35 },
      { id = "EMBER", pp = 25 },
    }
    eq(BattleFx.pickCounterStrikeMove(battle, "dodge", battle.player, {
      category = "physical", type = "NORMAL", id = "TACKLE",
    }), "SCRATCH", "dodge vs a charge uses a physical rebound")
    eq(BattleFx.pickCounterStrikeMove(battle, "dodge", battle.player), "SCRATCH",
      "dodge without an incoming charge still uses the physical poke")
    battle.data.moves.SWIFT = {
      id = "SWIFT", power = 60, category = "physical", type = "NORMAL",
    }
    eq(BattleFx.pickCounterStrikeMove(battle, "dodge", battle.player, {
      category = "physical", type = "NORMAL", id = "SWIFT",
    }), "EMBER", "dodge vs a projectile uses a special, not a melee jab")
    battle.player.curMoves = { { id = "SCRATCH", pp = 35 } }
    eq(BattleFx.pickCounterStrikeMove(battle, "dodge", battle.player, {
      category = "physical", type = "NORMAL", id = "SWIFT",
    }), nil, "no melee counter on a far projectile")
  end

  function tests.fire_now_lists_known_specials_not_the_queued_move()
    local battle = {
      data = {
        moves = {
          SCRATCH = { id = "SCRATCH", power = 40, category = "physical", type = "NORMAL" },
          EMBER = { id = "EMBER", name = "EMBER", power = 40, category = "special", type = "FIRE" },
          FIRE_PUNCH = { id = "FIRE_PUNCH", power = 75, category = "special", type = "FIRE" },
          BUBBLEBEAM = { id = "BUBBLEBEAM", power = 65, category = "special", type = "WATER" },
          GROWL = { id = "GROWL", power = 0, category = "status", type = "NORMAL" },
        },
      },
      moveDef = function(self, inst)
        return inst and self.data.moves[inst.id]
      end,
      player = {
        curMoves = {
          { id = "SCRATCH", pp = 35 },
          { id = "GROWL", pp = 40 },
          { id = "EMBER", pp = 25 },
          { id = "FIRE_PUNCH", pp = 15 },
          { id = "BUBBLEBEAM", pp = 0 },
        },
      },
    }
    local shots = BattleFx.listFireNowMoves(battle, battle.player)
    eq(#shots, 1, "only a ranged special with PP is fireable")
    eq(shots[1].moveId, "EMBER", "queued Scratch can still switch to Ember")
    local checks = BattleFx.listCheckNowMoves(battle, battle.player)
    eq(#checks, 2, "Scratch and Fire Punch are CHECKs during a charge")
    local checkIds = {}
    for i = 1, #checks do
      checkIds[checks[i].moveId] = true
    end
    truthy(checkIds.SCRATCH, "Scratch is listed as a CHECK")
    truthy(checkIds.FIRE_PUNCH, "Fire Punch stays melee even as a Fire type")
    eq(checks[1].checkNow or checks[2].checkNow, true, "CHECK rows are tagged")

    battle.player.curMoves = {
      { id = "SMOG", pp = 20 },
      { id = "SMOKESCREEN", pp = 20 },
      { id = "EMBER", pp = 25 },
    }
    battle.data.moves.SMOG = {
      id = "SMOG", power = 20, category = "special", type = "POISON",
    }
    battle.data.moves.SMOKESCREEN = {
      id = "SMOKESCREEN", power = 0, category = "status", type = "NORMAL",
    }
    shots = BattleFx.listFireNowMoves(battle, battle.player)
    eq(#shots, 1, "SMOG is not a 2-tile FIRE special")
    eq(shots[1].moveId, "EMBER", "Ember stays on the FIRE list")
    local clouds = BattleFx.listCloudNowMoves(battle, battle.player)
    eq(#clouds, 2, "Smog and Smokescreen seed a lane")

    battle.player.curMoves = {
      { id = "SCRATCH", pp = 35 },
      { id = "WATER_GUN", pp = 25 },
    }
    battle.data.moves.WATER_GUN = {
      id = "WATER_GUN", name = "WATER GUN", power = 40,
      category = "special", type = "WATER",
    }
    shots = BattleFx.listFireNowMoves(battle, battle.player)
    eq(#shots, 1, "Water Gun is a fireable special")
    eq(shots[1].moveId, "WATER_GUN", "Nidorina can FIRE NOW with Water Gun")

    battle.player.curMoves = {
      { id = "PSYCHIC", pp = 10 },
      { id = "TACKLE", pp = 35 },
      { id = "THUNDERBOLT", pp = 15 },
    }
    battle.data.moves.PSYCHIC = {
      id = "PSYCHIC", power = 90, category = "special", type = "PSYCHIC",
    }
    battle.data.moves.TACKLE = {
      id = "TACKLE", power = 35, category = "physical", type = "NORMAL",
    }
    battle.data.moves.THUNDERBOLT = {
      id = "THUNDERBOLT", power = 95, category = "special", type = "ELECTRIC",
    }
    shots = BattleFx.listFireNowMoves(battle, battle.player)
    eq(#shots, 1, "FIRE lists only the projectile")
    eq(shots[1].moveId, "THUNDERBOLT", "Psychic and Tackle stay off FIRE")

    battle.player.curMoves = {
      { id = "PSYCHIC", pp = 10 },
      { id = "THUNDERBOLT", pp = 15 },
      { id = "GROWL", pp = 40 },
    }
    battle.data.moves.PSYCHIC = {
      id = "PSYCHIC", power = 90, category = "special", type = "PSYCHIC",
    }
    battle.data.moves.THUNDERBOLT = {
      id = "THUNDERBOLT", power = 95, category = "special", type = "ELECTRIC",
    }
    local follow = BattleFx.pickAgainCallMove(battle, battle.player, { id = "PSYCHIC" })
    eq(follow and follow.id, "THUNDERBOLT", "Again! call prefers a different known move")
    battle.player.curMoves = { { id = "PSYCHIC", pp = 10 } }
    follow = BattleFx.pickAgainCallMove(battle, battle.player, { id = "PSYCHIC" })
    eq(follow and follow.id, "PSYCHIC", "same move is used when the pool has no alt")
  end
end

local function loadEmotions()
  return assert(loadfile(root .. "/../battle/rules/emotions.lua"))()
end

local function loadPortraits()
  return assert(loadfile(root .. "/../battle/chrome/portraits.lua"))()
end

local function moodBattle(php, pmax, ehp, emax)
  return {
    player = {
      isPlayer = true,
      mon = { hp = php, stats = { hp = pmax }, name = "CHARMANDER", dex = 4 },
    },
    enemy = {
      mon = { hp = ehp, stats = { hp = emax }, name = "SQUIRTLE", dex = 7 },
    },
  }
end

function tests.emotions_low_hp_is_pain()
  local E = loadEmotions()
  local battle = moodBattle(10, 100, 80, 100)
  E.refresh(battle)
  eq(E.mood(battle, true), "pain", "player at 10% is tired")
  eq(E.mood(battle, false), "normal", "healthy foe stays normal")
  E.clear(battle)
end

function tests.emotions_two_misses_make_angry()
  local E = loadEmotions()
  local battle = moodBattle(80, 100, 80, 100)
  E.note(battle, { kind = "miss", side = "player" })
  eq(E.mood(battle, true), "sigh", "first miss flashes sigh")
  E.note(battle, { kind = "turn" })
  eq(E.mood(battle, true), "normal", "one miss is not angry yet")
  E.note(battle, { kind = "miss", side = "player" })
  E.note(battle, { kind = "turn" })
  eq(E.mood(battle, true), "angry", "two misses become angry")
  local mods = E.modifiers(battle, true)
  eq(type(mods), "table", "modifiers is a table")
  eq(mods.powerMul, 1.12, "angry hits harder")
  eq(mods.accuracy, -0.08, "angry swings wilder")
  eq(E.applyDamage(battle, battle.player, battle.enemy, 100), 112,
    "angry power applies to outgoing damage")
  E.clear(battle)
end

function tests.emotions_crit_stuns_then_angers()
  local E = loadEmotions()
  local battle = moodBattle(70, 100, 70, 100)
  E.note(battle, { kind = "crit", side = "player" })
  eq(E.mood(battle, true), "stunned", "received crit flashes stunned")
  E.note(battle, { kind = "turn" })
  eq(E.mood(battle, true), "angry", "after the flash the mon stays angry")
  E.clear(battle)
end

function tests.emotions_hp_lead_and_hit_is_determined()
  local E = loadEmotions()
  local battle = moodBattle(90, 100, 40, 100)
  E.note(battle, { kind = "hit", user = "player", target = "enemy", damage = 10, maxHp = 100 })
  eq(E.mood(battle, true), "determined", "HP lead plus a landed hit is determined")
  eq(E.mood(battle, false), "worried", "the trailing foe looks worried")
  E.clear(battle)
end

function tests.emotions_player_ko_flashes_happy()
  local E = loadEmotions()
  local battle = moodBattle(80, 100, 0, 100)
  E.note(battle, { kind = "faint", side = "enemy" })
  eq(E.mood(battle, true), "happy", "KO flashes happy on our mon")
  eq(E.fileName("happy"), "Happy", "happy uses the Happy portrait")
  eq(E.chip("happy").text, "HAPPY", "happy chip label")
  eq(E.portraitMood(battle, true), "happy", "KO face is happy")
  E.note(battle, { kind = "turn" })
  eq(E.mood(battle, true), "happy", "happy holds after the flash turn")
  E.note(battle, { kind = "turn" })
  E.note(battle, { kind = "turn" })
  eq(E.mood(battle, true), "happy", "happy is not a timed burst")
  E.note(battle, { kind = "miss", side = "player" })
  eq(E.mood(battle, true), "sigh", "the next mood event replaces happy")
  E.clear(battle)
end

function tests.emotions_player_faint_is_not_a_party()
  local E = loadEmotions()
  local battle = moodBattle(0, 100, 80, 100)
  E.note(battle, { kind = "faint", side = "player" })
  eq(E.mood(battle, true) ~= "happy", true, "our faint is not a celebration")
  eq(E.mood(battle, false) ~= "happy", true, "the foe does not celebrate")
  E.clear(battle)
end

function tests.emotions_switch_clears_mood()
  local E = loadEmotions()
  local battle = moodBattle(80, 100, 80, 100)
  E.note(battle, { kind = "miss", side = "player" })
  E.note(battle, { kind = "miss", side = "player" })
  E.note(battle, { kind = "turn" })
  eq(E.mood(battle, true), "angry", "setup: angry from misses")
  E.note(battle, { kind = "switch", side = "player" })
  eq(E.mood(battle, true), "normal", "switch resets the incoming mon")
  E.clear(battle)
end

function tests.portraits_resolve_gen1_root_path()
  local P = loadPortraits()
  eq(P.relPath(4, "angry"), "assets/portrait/0004/Angry.png", "dex 4 angry")
  eq(P.relPath(4, "happy"), "assets/portrait/0004/Happy.png", "dex 4 happy")
  eq(P.relPath(1, "normal"), "assets/portrait/0001/Normal.png", "dex 1 normal")
  eq(P.emotionFile("pain"), "Pain", "pain file")
  local battle = moodBattle(80, 100, 80, 100)
  eq(P.dexOf(battle, battle.player), 4, "reads mon.dex")
end

function tests.emotions_chip_colors_match_mood()
  local E = loadEmotions()
  local angry = E.chip("angry")
  eq(angry.text, "ANGRY", "angry chip label")
  truthy(angry.fill and angry.fill[1] > 0.6, "angry fill is red")
  eq(E.chip("pain").text, "TIRED", "low HP chip is TIRED")
  eq(E.chip("determined").text, "DTRMD", "determined chip is DTRMD")
  eq(E.chip("normal").text, "OK", "calm mood still has a chip")
end

function tests.status_chips_are_smaller_than_hud_type()
  eq(UI.CHIP_H, 13, "chip plate fits native HUD type")
  eq(UI.CHIP_SCALE, 1, "chip type is not scaled down")
  eq(UI.HP_LETTER_W, 11, "initial sits on a cream badge")
  eq(UI.HP_LETTER_SCALE, 1, "initial is native HUD type")
  truthy(UI.HP_BAR_H >= 5, "HP chip is thick enough to read")
end

function tests.react_chips_follow_the_mon()
  local hx, hy = UI.hpAboveFace(4, 40, 28)
  local mx, my = UI.moodChipAboveHp(hx, hy, 0)
  eq(mx, hx, "worry pill stays on the HUD stack midline")
  eq(my, hy - UI.CHIP_AIR - UI.CHIP_H, "worry pill sits above HP with air")
  local rx, ry = UI.reactChipAboveMon(48, 90)
  eq(rx, 48, "REACT pill is centered on the sprite")
  eq(ry, 90 - UI.CHIP_H - UI.REACT_CHIP_LIFT, "REACT pill sits over the mon")
  truthy(UI.CHIP_AIR >= 4, "emotion pill has a gap above the HP row")
  eq(UI.HP_FACE_GAP, 0, "HP row hugs the portrait")

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
  local player = {
    _arFieldBattler = true,
    _arFieldSide = "player",
    px = 40, py = 90, _fieldBarLift = 10, hidden = false,
  }
  local battle = {
    _arAnimeField = true,
    frame = 1,
    player = { shownHP = 20, mon = { name = "EKANS", stats = { hp = 20 } } },
    enemy = { shownHP = 20, mon = { name = "GEODUDE", stats = { hp = 20 } } },
    game = {
      overworld = { camera = { x = 0, y = 0 }, entities = { player } },
      renderer = {
        uiSize = function() return 160, 144 end,
        worldViewSize = function() return 160, 144 end,
        fitScale = function() return 1 end,
      },
    },
  }
  UI.armStatusChip(battle, "player", "DODGE")
  local spriteX = (player.px or 0) + 8
  local spriteY = (player.py or 0) - (player._fieldBarLift or 0)
  local chipX, chipY = UI.reactChipAboveMon(spriteX, spriteY)
  local function sawChip()
    for i = 1, #painted do
      if painted[i].y == chipY then
        return true
      end
    end
    return false
  end
  UI.drawWorldHP(battle, 0, 0, "ui")
  truthy(not sawChip(), "HUD pass does not paint REACT on the mon")
  painted = {}
  UI.drawReactChips(battle, 0, 0)
  love = prevLove
  truthy(sawChip(), "REACT pill paints over the battler on the overlay")
  local hit
  for i = 1, #painted do
    if painted[i].y == chipY then
      hit = painted[i]
      break
    end
  end
  truthy(hit and hit.x <= chipX and (hit.x + 40) >= chipX,
    "REACT pill is centered on the sprite X")
end

function tests.emotions_chip_ink_is_always_dark()
  local E = loadEmotions()
  for mood, spec in pairs(E.CHIP) do
    local ink = spec.ink
    truthy(ink, mood .. " has ink")
    local luma = (ink[1] or 0) * 0.3 + (ink[2] or 0) * 0.59 + (ink[3] or 0) * 0.11
    truthy(luma < 0.35, mood .. " ink stays dark so Font color cannot bleach the overlay")
  end
end

function tests.emotions_portrait_holds_until_normal()
  local E = loadEmotions()
  local battle = moodBattle(80, 100, 80, 100)
  E.note(battle, { kind = "miss", side = "player" })
  E.note(battle, { kind = "miss", side = "player" })
  E.note(battle, { kind = "turn" })
  eq(E.mood(battle, true), "angry", "setup angry")
  eq(E.consumeChange(battle, true), "angry", "first change arms a portrait")
  eq(E.consumeChange(battle, true), nil, "same mood does not re-fire")
  eq(E.portraitAlpha(battle, true), 1, "portrait stays while angry")
  local side = E.side(battle, true)
  side.portraitAt = (os.clock()) - 8
  eq(E.portraitAlpha(battle, true), 1, "elapsed time does not hide an active mood")
  eq(E.portraitMood(battle, true), "angry", "face matches the live mood")
  side.mood = "normal"
  side.flash = nil
  side.fadeAt = (os.clock()) - 2
  side.portraitMood = "angry"
  eq(E.portraitAlpha(battle, true), 1, "calm still keeps the portrait up")
  eq(E.portraitMood(battle, true), "normal", "face follows the live mood")
  E.clear(battle)
end

function tests.emotions_heat_follows_shown_mood()
  local E = loadEmotions()
  local battle = moodBattle(90, 100, 40, 100)
  E.note(battle, { kind = "hit", user = "player", target = "enemy", damage = 10, maxHp = 100 })
  eq(E.mood(battle, true), "determined", "setup determined")
  eq(E.mood(battle, false), "worried", "setup worried")
  local det = E.modifiers(battle, true)
  local wary = E.modifiers(battle, false)
  eq(det.accuracy, 0.08, "determined is more accurate")
  eq(wary.dodge, 0.08, "worried ducks better")
  eq(E.applyDamage(battle, battle.player, battle.enemy, 100), 106,
    "determined power, worried takes normal")
  E.note(battle, { kind = "crit", side = "player" })
  eq(E.mood(battle, true), "stunned", "crit flash overrides determined")
  eq(E.modifiers(battle, true).takenMul, 1.10, "stunned takes more this turn")
  E.clear(battle)
end

function tests.emotions_heat_off_when_faces_off()
  local E = loadEmotions()
  E.bind({
    facesOn = function()
      return false
    end,
  })
  local battle = moodBattle(80, 100, 80, 100)
  E.note(battle, { kind = "miss", side = "player" })
  E.note(battle, { kind = "miss", side = "player" })
  E.note(battle, { kind = "turn" })
  eq(E.mood(battle, true), "angry", "mood still derives with faces off")
  local mods = E.modifiers(battle, true)
  eq(mods.powerMul, 1, "heat is identity when faces are off")
  eq(mods.accuracy, 0, "no accuracy nudge when faces are off")
  eq(E.applyDamage(battle, battle.player, battle.enemy, 100), 100,
    "damage is unchanged when faces are off")
  E.clear(battle)
end

function tests.emotions_announce_is_not_dialogue()
  local E = loadEmotions()
  local pushed = 0
  E.bind({
    facesOn = function()
      return true
    end,
    pushNotice = function()
      pushed = pushed + 1
    end,
  })
  local battle = moodBattle(10, 100, 80, 100)
  E.announce(battle)
  eq(E.mood(battle, true), "pain", "low HP is pain")
  eq(pushed, 0, "mood does not push a notice line")
  E.clear(battle)
end

function tests.mood_aura_paints_when_angry()
  local rects = 0
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      setLineWidth = function() end,
      rectangle = function()
        rects = rects + 1
      end,
      circle = function() end,
      ellipse = function() end,
      line = function() end,
    },
    timer = { getTime = function() return 1.4 end },
  }
  Projectiles.moodOf = function(_, isPlayer)
    return isPlayer and "angry" or "normal"
  end
  local session = {
    live = true,
    playerMon = { px = 16, py = 32 },
    enemyMon = { px = 80, py = 32 },
  }
  Projectiles.drawMoodAuras(session, {}, 0, 0)
  truthy(rects > 0, "angry paints rising heat ticks")
  Projectiles.moodOf = function()
    return "normal"
  end
  rects = 0
  Projectiles.drawMoodAuras(session, {}, 0, 0)
  eq(rects, 0, "normal mood has no body aura")
  Projectiles.moodOf = nil
  love = prevLove
end

function tests.field_sfx_overlap_ducks_the_prior_voice()
  Audio.clearVoices()
  local function voice(playing)
    local vol = Audio.VOICE_VOL
    local on = playing ~= false
    return {
      isPlaying = function()
        return on
      end,
      setVolume = function(_, value)
        vol = value
      end,
      getVolume = function()
        return vol
      end,
      stop = function()
        on = false
      end,
    }
  end
  local first = voice()
  local second = voice()
  truthy(Audio.pushVoice(first, Audio.VOICE_VOL), "first voice lands")
  eq(Audio.voiceCount(), 1, "one live voice")
  truthy(Audio.pushVoice(second, Audio.VOICE_VOL), "second voice stacks")
  eq(Audio.voiceCount(), 2, "both voices stay up")
  truthy(first:getVolume() < Audio.VOICE_VOL, "the earlier sample is ducked")
  eq(second:getVolume(), Audio.VOICE_VOL, "the new sample stays full")
  first.stop()
  eq(Audio.voiceCount(), 1, "finished voices drop off")
  Audio.clearVoices()
  eq(Audio.voiceCount(), 0, "clear stops the stack")
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
