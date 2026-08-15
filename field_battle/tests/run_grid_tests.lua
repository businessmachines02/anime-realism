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
  eq(player.lastAnim, "jump", "attacker jumps when path is blocked")
  local fx = session.projectiles and session.projectiles[1]
  truthy(fx and fx.style == "contact", "physical keeps contact-only FX")
  eq(fx.sx, fx.ex, "no traveling physical projectile")
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
  eq(player.lastAnim, "attack", "physical attack animation")
  truthy(player._attackStepped, "physical attack owns one grid step")
  eq(player._returnAt, 10.48, "return waits for attack presentation")
  truthy(Cues.shouldSkipEvent(session, "player", "attack"), "dedupe same cue")

  -- Night Shade is Gen1 physical (Ghost) + 0 BP, but must cast a travel shadow.
  session._now = 12.5
  session._lastCueAt = nil
  player._attackStepped = nil
  player._returnAt = nil
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
  local calls = { sparks = 0, ice = 0, bubbles = 0, zs = 0, swirl = 0, seed = 0, flame = 0 }
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

  battle.player.mon.status = nil
  battle.enemy.confusedTurns = nil
  battle.enemy.leechSeeded = nil
  calls.sparks, calls.ice, calls.bubbles, calls.zs, calls.swirl, calls.seed, calls.flame =
      0, 0, 0, 0, 0, 0, 0
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  eq(calls.sparks + calls.ice + calls.bubbles + calls.zs + calls.swirl
      + calls.seed + calls.flame, 0,
    "healthy mons have no status aura")
  love = prevLove
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
