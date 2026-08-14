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
  Projectiles.clear(session)

  local flamethrower = Projectiles.move(session, "player", {
    moveType = "FIRE", moveId = "FLAMETHROWER",
  })
  eq(flamethrower.style, "stream", "named fire move uses stream glitz")
  eq(flamethrower.glitz, "flame", "flamethrower paints flame trail")
  local psychic = Projectiles.move(session, "player", {
    moveType = "PSYCHIC", moveId = "PSYCHIC",
  })
  eq(psychic.style, "spiral", "psychic uses spiral ring")
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

function tests.status_auras_follow_field_mons()
  local calls = { sparks = 0, ice = 0, bubbles = 0, zs = 0, swirl = 0 }
  local prevLove = love
  love = {
    graphics = {
      setColor = function() end,
      setLineWidth = function() end,
      line = function() calls.sparks = calls.sparks + 1 end,
      rectangle = function() calls.zs = calls.zs + 1 end,
      arc = function() calls.swirl = calls.swirl + 1 end,
      circle = function(mode)
        if mode == "fill" then
          calls.ice = calls.ice + 1
        else
          calls.bubbles = calls.bubbles + 1
        end
      end,
      polygon = function() calls.ice = calls.ice + 1 end,
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

  battle.player.mon.status = nil
  battle.enemy.confusedTurns = nil
  calls.sparks, calls.ice, calls.bubbles, calls.zs, calls.swirl = 0, 0, 0, 0, 0
  Projectiles.drawStatusAuras(session, battle, 0, 0)
  eq(calls.sparks + calls.ice + calls.bubbles + calls.zs + calls.swirl, 0,
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
