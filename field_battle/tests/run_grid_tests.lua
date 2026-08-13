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
local FieldFactory = load("init.lua")
local FieldBattle = FieldFactory({ load = function() return {} end })

local tests = {}

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
  eq(envelope.pad.sizeU, 9, "free-tile envelope width")
  eq(envelope.pad.sizeV, 7, "free-tile envelope height")
  truthy(envelope.readOnly, "survey is explicitly read-only")
  truthy(calls.walk > 0 and calls.water > 0, "survey queries map traversal")

  for _, world in ipairs({ { 13, 12 }, { 12, 9 }, { 11, 8 }, { 15, 11 } }) do
    local u, v = Coords.worldToPad(envelope.pad, world[1], world[2])
    truthy(not envelope.walkable[Coords.key(u, v)],
      "blocked terrain/entity excluded from envelope")
  end

  local arena = Arena.generate(nil, plan, 123, envelope)
  local grid = Grid.build(arena, plan)
  eq(grid.sizeU, 9, "grid adopts surveyed width")
  eq(grid.sizeV, 7, "grid adopts surveyed height")
  local wu, wv = Coords.worldToPad(envelope.pad, 13, 12)
  truthy(not Grid.isFree(grid, wu, wv), "movement rejects surveyed water")
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

function tests.compact_arena_keeps_cast_lanes_clear()
  local player = { cellX = 10, cellY = 10, facing = "right" }
  local fx, fy = Layout.wildAnchor(player)
  local plan = Layout.plan(player.cellX, player.cellY, fx, fy)
  eq(plan.pCellX, player.cellX, "wild pad starts at player")
  local arena = Arena.generate(nil, plan, 12345)
  eq(arena.pad.sizeU, 5, "arena width")
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
  eq(math.abs(plan.pCellY - plan.eCellY), 4, "trainer edges span compact pad")
  eq(math.abs(plan.pMonY - plan.eMonY), 2, "mons stand inside trainers")
end

local function sampleGrid()
  local plan = Layout.plan(10, 10, 18, 10)
  return Grid.build(nil, plan), plan
end

function tests.occupancy_and_movement()
  local grid = sampleGrid()
  eq(grid.sizeU, 5, "compact pad width")
  eq(grid.sizeV, 3, "compact pad height")
  local pHome = grid.home.player
  local eHome = grid.home.enemy
  local p = { id = "player", padU = pHome.u, padV = pHome.v }
  local e = { id = "enemy", padU = eHome.u, padV = eHome.v }
  truthy(Grid.setPad(grid, p, p.padU, p.padV), "place player")
  truthy(Grid.setPad(grid, e, e.padU, e.padV), "place enemy")
  truthy(not Grid.setPad(grid, { id = "other" }, p.padU, p.padV),
    "reject occupied cell")

  local homeU, homeV = p.padU, p.padV
  truthy(Grid.attackStep(grid, p, e), "attack step")
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
  local session = {
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    _now = 10,
  }

  truthy(Cues.apply(session, "player", "attack", Grid, nil, nil,
    { category = "physical" }), "physical attack cue")
  eq(player.lastAnim, "attack", "physical attack animation")
  truthy(player._attackStepped, "physical attack owns one grid step")
  eq(player._returnAt, 10.48, "return waits for attack presentation")
  truthy(Cues.shouldSkipEvent(session, "player", "attack"), "dedupe same cue")

  session._now = 12
  truthy(not Cues.shouldSkipEvent(session, "player", "attack"), "dedupe expires")
  truthy(Cues.apply(session, "enemy", "hit", Grid, nil, nil,
    { category = "special", push = false }), "hit cue")
  eq(enemy.lastAnim, "hit", "hit animation")
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
  local player = { padU = grid.home.player.u, padV = 0 }
  local enemy = { padU = grid.home.enemy.u, padV = 0 }
  Lifecycle._testBind(battle, {
    state = Lifecycle.STATE.Live,
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    envelope = { gridRect = grid.worldRect },
  })
  -- No prior camera pose → settle on the envelope immediately.
  Lifecycle.focusCamera(battle)
  Lifecycle._testUnbind(battle)

  truthy(followed, "camera follows field cast")
  local rect = grid.worldRect
  local actionY = ((rect.minY + rect.maxY) / 2) * Coords.CELL + Coords.CELL / 2
  eq(followed.y, actionY + Lifecycle.CAMERA_UI_BIAS_Y,
    "camera stably frames envelope above menu")
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
  local player = { padU = grid.home.player.u, padV = 0 }
  local enemy = { padU = grid.home.enemy.u, padV = 0 }
  Lifecycle._testBind(battle, {
    state = Lifecycle.STATE.Live,
    live = true,
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    envelope = { gridRect = grid.worldRect },
  })

  local rect = grid.worldRect
  local targetX = ((rect.minX + rect.maxX) / 2) * Coords.CELL + Coords.CELL / 2
  local targetY = ((rect.minY + rect.maxY) / 2) * Coords.CELL + Coords.CELL / 2
    + Lifecycle.CAMERA_UI_BIAS_Y

  Lifecycle.focusCamera(battle, 1 / 60)
  truthy(followed, "camera begins soft pan")
  local mid1 = followed
  truthy(math.abs(mid1.x - targetX) > 1 or math.abs(mid1.y - targetY) > 1,
    "first frame has not snapped to envelope")

  for _ = 1, 180 do
    Lifecycle.focusCamera(battle, 1 / 60)
  end
  Lifecycle._testUnbind(battle)

  eq(followed.x, targetX, "pan settles on envelope X")
  eq(followed.y, targetY, "pan settles on envelope Y above menu")
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
  for _ = 1, 40 do
    Cast.tick(session, 1 / 60)
  end
  truthy(enemy._faintDone, "faint animation completes")
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
  Lifecycle.tick(battle, 0.40, deps)
  eq(session.playerMon.species, "SECOND_MON", "replacement species staged")
  truthy(session.playerMon._sendoutStarted, "replacement uses send-out animation")

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
  Lifecycle.restoreOverworldFollowers(session, overworld)
  eq(overworld.entities[2], follower, "follower returns at its original index")
  eq(follower.hidden, false, "restored follower is visible")
  eq(follower._arFieldParked, nil, "park marker is cleared")
end

function tests.field_overlay_draws_projectiles()
  local drawn = 0
  local projectile = {
    _removed = false,
    draw = function()
      drawn = drawn + 1
    end,
  }
  local battle = {
    game = {
      overworld = { camera = { x = 0, y = 0 } },
    },
  }
  local session = {
    state = Lifecycle.STATE.Live,
    live = true,
    projectiles = { projectile },
    _deps = {
      Projectiles = {
        draw = function(s, camX, camY)
          eq(camX, 0, "overlay uses camera x")
          eq(camY, 0, "overlay uses camera y")
          for i = 1, #s.projectiles do
            s.projectiles[i]:draw(camX, camY)
          end
        end,
      },
    },
  }
  Lifecycle._testBind(battle, session)
  Lifecycle.drawWorldOverlay(battle)
  Lifecycle.drawWorldOverlay(battle)
  eq(drawn, 2, "overlay paints projectiles every drawUI call")
  Lifecycle._testUnbind(battle)
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
