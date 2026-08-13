-- Field battle — session owner (Idle → Armed → Staging → Live → Finishing).
--
-- One weak-keyed session per BattleState. Lifecycle owns:
--   begin/finish   survey envelope, stage cast, camera, voxel snapshot/restore
--   tick/tickPresent  bob, steps, projectiles, trainer dodge-aside
--   syncMons / stagePlayerMon / capture / despawn
--   onTurnStarted / onTurnEnded / react (cue fan-out)
--
-- States:
--   Idle       no active FIELD session
--   Armed      battle flagged; waiting to stage onto the map
--   Staging    cast entities / grid / arena props being placed
--   Live       combat presentation running on the overworld
--   Finishing  teardown; restore camera / voxel / entity snapshots
--
-- Present clock (tickPresent) advances anims even while BattleState menus
-- own input, so idle bob does not freeze under the move diamond.

local Coords = require("coords")

local Lifecycle = {}
Lifecycle.CAMERA_UI_BIAS_Y = 18

-- Weak keys: sessions die with their BattleState without explicit cleanup races.
local byBattle = setmetatable({}, { __mode = "k" })

Lifecycle.STATE = {
  Idle = "Idle",
  Armed = "Armed",
  Staging = "Staging",
  Live = "Live",
  Finishing = "Finishing",
}

local function now()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return 0
end

local function rr(...)
  local random = (love and love.math and love.math.random) or math.random
  return random(...)
end

local function applyZoom(session, battle)
  local ok, Zoom = pcall(require, "src.render.Zoom")
  if not (ok and type(Zoom) == "table") then
    return
  end
  session.zoomSaved = Zoom.offset or 0
  local S = 3
  local game = battle.game
  if game and game.renderer and type(game.renderer.fitScale) == "function" then
    local okS, s = pcall(game.renderer.fitScale, game.renderer)
    if okS and type(s) == "number" and s > 0 then
      S = s
    end
  end
  local want = session.zoomSaved - 1
  if type(Zoom.clampOffset) == "function" then
    Zoom.offset = Zoom.clampOffset(want, S)
  else
    Zoom.offset = want
  end
end

local function restoreZoom(session)
  if session.zoomSaved == nil then
    return
  end
  local ok, Zoom = pcall(require, "src.render.Zoom")
  if ok and type(Zoom) == "table" then
    Zoom.offset = session.zoomSaved
  end
  session.zoomSaved = nil
end

local function snapshotVoxel(session)
  local ok, Pipelines = pcall(require, "src.render.Pipelines")
  if not (ok and Pipelines and type(Pipelines.level) == "function") then
    return
  end
  local okL, level = pcall(Pipelines.level, "voxel")
  if okL and type(level) == "number" then
    session.voxelSaved = level
  end
end

local function restoreVoxel(session)
  if session.voxelSaved == nil then
    return
  end
  local saved = session.voxelSaved
  session.voxelSaved = nil
  local ok, Pipelines = pcall(require, "src.render.Pipelines")
  if not (ok and Pipelines and type(Pipelines.setLevel) == "function") then
    return
  end
  local current = nil
  if type(Pipelines.level) == "function" then
    local okL, level = pcall(Pipelines.level, "voxel")
    if okL and type(level) == "number" then
      current = level
    end
  end
  -- Re-assert the pre-battle voxel level. If the pipeline already reports the
  -- same level but the overlay got stuck flat after FIELD camera/entity
  -- cleanup, bounce through OFF so potato_voxel re-tweens onto the live map.
  if current == saved and saved > 0 then
    pcall(Pipelines.setLevel, "voxel", 0)
  end
  pcall(Pipelines.setLevel, "voxel", saved)
end

function Lifecycle.get(battle)
  return battle and byBattle[battle] or nil
end

function Lifecycle.active(battle)
  local s = Lifecycle.get(battle)
  return s ~= nil and s.live == true and s.state == Lifecycle.STATE.Live
end

function Lifecycle.focusCamera(battle)
  local session = Lifecycle.get(battle)
  if not (session and session.live) then
    return
  end
  local game = battle and battle.game
  local ow = game and game.overworld
  local cam = ow and ow.camera
  if not cam then
    return
  end

  local fx, fy
  local p, e = session.playerMon, session.enemyMon
  local grid = session.grid
  local function focusOf(ent)
    if not ent then
      return nil, nil
    end
    if grid and ent.padU ~= nil then
      return Coords.padCenterPx(grid, ent.padU, ent.padV)
    end
    return (ent.basePx or ent.px or 0) + 8, (ent.basePy or ent.py or 0) + 8
  end
  local rect = session.envelope and session.envelope.gridRect
  if rect then
    fx = ((rect.minX + rect.maxX) / 2) * Coords.CELL + Coords.CELL / 2
    fy = ((rect.minY + rect.maxY) / 2) * Coords.CELL + Coords.CELL / 2
  elseif p and e then
    local px, py = focusOf(p)
    local ex, ey = focusOf(e)
    fx = (px + ex) / 2
    fy = (py + ey) / 2
  elseif p then
    fx, fy = focusOf(p)
  elseif e then
    fx, fy = focusOf(e)
  else
    fx = (session.midX or 0) * 16 + 8
    fy = (session.midY or 0) * 16 + 8
  end

  local nudgeT = session.camNudgeT or 0
  if nudgeT > 0 and session.camNudgeX and session.camNudgeY then
    local w = math.min(1, nudgeT / 0.35) * 0.55
    fx = fx * (1 - w) + session.camNudgeX * w
    fy = fy * (1 - w) + session.camNudgeY * w
  end

  local lfx, lfy = session.focusX, session.focusY
  if lfx and lfy and nudgeT <= 0 then
    local ddx, ddy = fx - lfx, fy - lfy
    if (ddx * ddx + ddy * ddy) < 2.25 then
      return
    end
  end

  local vw = session._vw
  local vh = session._vh
  if not vw then
    vw, vh = 160, 144
    if game.renderer and type(game.renderer.worldViewSize) == "function" then
      local ok, a, b = pcall(game.renderer.worldViewSize, game.renderer)
      if ok and type(a) == "number" then
        vw, vh = a, b or vh
      end
    end
    session._vw, session._vh = vw, vh
  end

  -- Battle menus occupy the lower screen. Aim the camera below the action so
  -- the compact pad appears in the unobstructed upper viewport.
  local cameraY = fy + (session.cameraUiBiasY or Lifecycle.CAMERA_UI_BIAS_Y)
  if type(cam.follow) == "function" then
    cam:follow(fx, cameraY, vw, vh)
  else
    cam.x = fx - vw / 2
    cam.y = cameraY - vh / 2
  end
  session.focusX, session.focusY = fx, fy
end

function Lifecycle.nudgeCamera(battle, side, seconds)
  local session = Lifecycle.get(battle)
  if not session then
    return
  end
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent then
    return
  end
  local grid = session.grid
  if grid and ent.padU ~= nil then
    session.camNudgeX, session.camNudgeY = Coords.padCenterPx(grid, ent.padU, ent.padV)
  else
    session.camNudgeX = (ent.basePx or ent.px or session.focusX or 0) + 8
    session.camNudgeY = (ent.basePy or ent.py or session.focusY or 0) + 8
  end
  session.camNudgeT = seconds or 0.4
end

function Lifecycle.monScreen(battle, side, Anims)
  local session = Lifecycle.get(battle)
  if Anims then
    return Anims.monScreen(session, battle, side)
  end
  return nil, nil
end

function Lifecycle.animTransform(battle, Anims)
  return Anims.transform(Lifecycle.get(battle), battle)
end

function Lifecycle.animShift(battle, Anims)
  return Anims.shift(Lifecycle.get(battle), battle)
end

function Lifecycle.cacheAnimTransform(battle, Anims)
  Anims.cache(Lifecycle.get(battle), battle)
end

function Lifecycle.animTransformCached(battle, Anims)
  return Anims.cached(Lifecycle.get(battle), battle)
end

local function leadPickerOpen(battle)
  local stack = battle and battle.game and battle.game.stack
  if not (stack and type(stack.top) == "function") then
    return false
  end
  local top = stack:top()
  if not top or top == battle then
    return false
  end
  if top.battle ~= nil and top.battle ~= battle then
    return false
  end
  if top.forceSwitch then
    return true
  end
  local id = tostring(top.id or top.screenId or "")
  if id == "PartyMenu" or id == "Gen2PartyMenu" then
    return top.forceSwitch == true or top.battle == battle
  end
  return false
end

local function combatReadyForPlayerReveal(battle)
  if not battle then
    return false
  end
  if battle.sendingOut or battle._arFieldRevealPlayer then
    return true
  end
  if battle.turn and battle.turn > 0 then
    return true
  end
  return false
end

function Lifecycle.begin(battle, mod, deps)
  -- Stage a FIELD session onto the live overworld: survey walkable cells,
  -- build grid/cast/arena props, snapshot voxel so free-roam restores cleanly.
  if not battle then
    return false
  end
  if Lifecycle.active(battle) then
    return true
  end
  local Layout = deps.Layout
  local Sprites = deps.Sprites
  local Arena = deps.Arena
  local Survey = deps.Survey
  local Grid = deps.Grid
  local Cast = deps.Cast

  Lifecycle.finish(battle, deps)

  local game = battle.game
  local ow = game and game.overworld
  local player = ow and ow.player
  if not player then
    return false
  end

  local RD = nil
  if mod and mod._arPackages and mod._arPackages.battle then
    RD = mod._arPackages.battle.ReactiveDefense
  end

  local foe = Layout.findFoeTrainer(ow, battle)
  local fx, fy
  if foe then
    fx, fy = foe.cellX or 0, foe.cellY or 0
  else
    fx, fy = Layout.wildAnchor(player)
  end

  local px, py = player.cellX or 0, player.cellY or 0
  local plan = Layout.plan(px, py, fx, fy)
  plan.hasFoeTrainer = foe ~= nil

  local envelope = nil
  if Survey and type(Survey.build) == "function" then
    local okSurvey, result = pcall(Survey.build, ow.map, plan, {
      entityPools = { ow.entities or {}, ow.npcs or {}, ow.npcPool or {} },
      player = player,
      foe = foe,
    })
    if okSurvey then
      envelope = result
    end
  end

  local layout = nil
  if Arena and type(Arena.generate) == "function" then
    local okGen, result = pcall(Arena.generate, battle, plan, nil, envelope)
    if okGen then
      layout = result
    end
  end

  local coverSlots = layout and layout.coverSlots or nil
  local grid = Grid.build(layout, plan)

  local session = {
    state = Lifecycle.STATE.Staging,
    live = true,
    started = now(),
    playerPose = Layout.copyPose(player),
    foe = foe,
    foePose = Layout.copyPose(foe),
    savedEntities = {},
    playerMon = nil,
    enemyMon = nil,
    awaitPlayerMon = true,
    sawLeadPicker = false,
    plan = plan,
    grid = grid,
    _mod = mod,
    _deps = deps,
    _battle = battle,
    midX = plan.midX,
    midY = plan.midY,
    arenaEdits = layout,
    arena = layout,
    envelope = envelope,
    coverSlots = coverSlots,
    coverKind = layout and layout.coverKind or nil,
    coverScene = layout and layout.coverScene or nil,
    ReactiveDefense = RD,
  }
  if RD then
    battle._arReactiveDefense = RD
  end
  for i = 1, #(ow.entities or {}) do
    session.savedEntities[i] = ow.entities[i]
  end

  player.frozen = true
  player.inputLocked = true
  player.wanders = false
  player.moving = false
  local function parkTrainer(ent, homeKey, face, occId)
    if not ent then
      return
    end
    ent.frozen = true
    ent.wanders = false
    ent.moving = false
    ent._arFieldTrainerId = occId
    local h = grid.home and grid.home[homeKey]
    if h then
      local wx, wy = Coords.padToWorld(grid, h.u, h.v)
      local px, py = Coords.padToPx(grid, h.u, h.v)
      ent.cellX, ent.cellY = wx, wy
      ent.px, ent.py = px, py
      ent.padU, ent.padV = h.u, h.v
      Grid.occupy(grid, occId, h.u, h.v)
    end
    if face then
      ent.facing = face
    end
  end
  parkTrainer(player, "playerTrainer", plan.playerFace, "ar_field_player_trainer")
  ow.engaging = true
  ow._arFieldEngaging = true

  if foe then
    parkTrainer(foe, "enemyTrainer", plan.foeFace, "ar_field_enemy_trainer")
  end

  Cast.stageEnemy(session, battle, mod, Sprites, Grid)

  local cast = {}
  local floor = layout and Arena.floorEntity(layout)
  if floor then
    cast[#cast + 1] = floor
  end
  cast[#cast + 1] = player
  if foe then
    cast[#cast + 1] = foe
  end
  if session.enemyMon then
    cast[#cast + 1] = session.enemyMon
  end
  if layout and type(layout.overlay) == "table" then
    for i = 1, #layout.overlay do
      local slot = layout.overlay[i]
      local prop = Arena.overlayEntity(slot)
      if prop then
        cast[#cast + 1] = prop
      end
    end
  end
  ow.entities = cast

  snapshotVoxel(session)
  applyZoom(session, battle)
  session.state = Lifecycle.STATE.Live
  byBattle[battle] = session
  Lifecycle.focusCamera(battle)

  battle._arAnimeField = true
  battle.isOpaque = false
  battle.BG_WORLD_DIM = 0
  battle.showPlayerBack = false
  -- TODO: Remove this once we have a proper enemy trainer
  battle.showEnemyTrainer = true
  if battle.introSlide and battle.introSlide > 0 then
    battle.introSlide = 0
  end

  return true
end

function Lifecycle.stagePlayerMon(battle, mod, deps)
  local session = Lifecycle.get(battle)
  if not (session and session.live) then
    return nil
  end
  if session.playerMon and not session.playerMon._removed then
    session.awaitPlayerMon = false
    return session.playerMon
  end
  deps = deps or session._deps
  mod = mod or session._mod
  return deps.Cast.stagePlayer(session, battle, mod, deps.Sprites, deps.Grid)
end

function Lifecycle.tryRevealPlayerMon(battle)
  local session = Lifecycle.get(battle)
  if not (session and session.live and session.awaitPlayerMon) then
    return
  end
  if not (battle.player and battle.player.mon) then
    return
  end
  if leadPickerOpen(battle) then
    session.sawLeadPicker = true
    return
  end
  if session.sawLeadPicker then
    Lifecycle.stagePlayerMon(battle)
    return
  end
  if combatReadyForPlayerReveal(battle) then
    Lifecycle.stagePlayerMon(battle)
  end
end

function Lifecycle.syncMons(battle, mod, deps)
  local session = Lifecycle.get(battle)
  if not (session and session.live) then
    return
  end
  deps = deps or session._deps
  mod = mod or session._mod
  local Cast = deps.Cast
  local Grid = deps.Grid
  local Sprites = deps.Sprites

  local function refresh(side, battler)
    if side == "player" and session.awaitPlayerMon then
      if leadPickerOpen(battle) then
        session.sawLeadPicker = true
        return
      end
      if session.sawLeadPicker or combatReadyForPlayerReveal(battle)
          or battle._arFieldRevealPlayer then
        Lifecycle.stagePlayerMon(battle, mod, deps)
      end
      return
    end
    local current = (side == "player") and session.playerMon or session.enemyMon
    local wanted = battler and battler.mon and battler.mon.species
    if not current then
      local ent = Cast.replace(session, battle, mod, Sprites, Grid, side, battler)
      if ent and type(ent.play) == "function" then
        ent:play("sendout")
      end
      return
    end
    if tostring(current.species or ""):upper() == tostring(wanted or ""):upper() then
      return
    end
    session.pendingSwitch = session.pendingSwitch or {}
    local pending = session.pendingSwitch[side]
    if pending and pending.species == wanted then
      return
    end
    session.pendingSwitch[side] = {
      battler = battler,
      species = wanted,
      delay = 0.34,
    }
    if type(current.play) == "function" then
      current:play("recall")
    end
  end

  refresh("player", battle.player)
  refresh("enemy", battle.enemy)
end

local function tickSwitches(session, battle, deps, dt)
  local pending = session and session.pendingSwitch
  if type(pending) ~= "table" then
    return
  end
  for _, side in ipairs({ "player", "enemy" }) do
    local item = pending[side]
    if item then
      item.delay = (item.delay or 0) - dt
      if item.delay <= 0 then
        pending[side] = nil
        local ent = deps.Cast.replace(session, battle, session._mod,
          deps.Sprites, deps.Grid, side, item.battler)
        if ent and type(ent.play) == "function" then
          ent:play("sendout")
        end
      end
    end
  end
end

function Lifecycle.capture(battle, ev)
  local session = Lifecycle.get(battle)
  if not (session and session.live and session.enemyMon) then
    return false
  end
  local Projectiles = session._deps and session._deps.Projectiles
  local function resolve()
    local enemy = session.enemyMon
    if not (enemy and type(enemy.play) == "function") then
      return
    end
    if ev and ev.caught then
      enemy:play("capture")
    else
      enemy:play("hit")
    end
  end
  if Projectiles and type(Projectiles.ball) == "function" then
    session.captureInFlight = true
    Projectiles.ball(session, {
      shakes = ev and ev.shakes,
      onDone = function()
        session.captureInFlight = nil
        resolve()
      end,
    })
  else
    resolve()
  end
  return true
end

function Lifecycle.despawnMon(battle, side)
  local session = Lifecycle.get(battle)
  if not session then
    return
  end
  local deps = session._deps
  deps.Cast.despawn(session, battle, deps.Grid, side)
end

local function tickIdleWander(session, Grid, ent, side, dt)
  if not ent or ent._removed or ent.hidden or ent._fainting then
    return
  end
  local busy = ent.anim and ent.anim ~= "idle"
  if busy or ent._returnAt then
    return
  end
  -- Still lerping to a cell target.
  local tpx, tpy = ent.targetPx, ent.targetPy
  if tpx and tpy then
    local dx = tpx - (ent.basePx or 0)
    local dy = tpy - (ent.basePy or 0)
    if (dx * dx + dy * dy) > 4 then
      return
    end
  end
  ent._wanderCD = (ent._wanderCD or (2.5 + rr() * 1.5)) - dt
  if ent._wanderCD > 0 then
    return
  end
  -- Often just hold the lane; only sometimes take a step.
  if rr() > 0.35 then
    ent._wanderCD = 2.8 + rr() * 2.4
    return
  end
  if Grid.idleWander(session.grid, ent, side) then
    ent._wanderCD = 3.2 + rr() * 2.8
  else
    ent._wanderCD = 2.0 + rr() * 1.5
  end


end



-- Trainer walk-step speed in world px/sec (comparable to the battler mons'
-- default steerBase speed of ~40-56).
local TRAINER_STEP_SPEED = 48

--- Reserve a pad cell and kick off a soft walk toward it. Player/NPC don't
--- consume targetPx/targetPy themselves, so we drive px/py ourselves via
--- stepTrainerClear below rather than routing through Player:update()/
--- NPC:update() (built for input-driven, collision-checked taps).
local function beginTrainerStep(session, Grid, trainer, nu, nv, du, dv)
  local occId = trainer._arFieldTrainerId
  if not occId then
    return false
  end
  Grid.occupy(session.grid, occId, nu, nv)
  trainer.padU, trainer.padV = nu, nv
  local tx, ty = Coords.padToPx(session.grid, nu, nv)
  trainer._stepTX, trainer._stepTY = tx, ty
  local wx, wy = Coords.padDeltaToWorld(session.grid, du, dv)
  if math.abs(wx) >= math.abs(wy) then
    trainer.facing = wx >= 0 and "right" or "left"
  else
    trainer.facing = wy >= 0 and "down" or "up"
  end
  trainer.moving = true
  return true
end

--- Per-frame lerp toward a pending trainer step. Call every tick for any
--- trainer that might have a step in flight (ow.player, session.foe).
local function stepTrainerClear(session, trainer, dt)
  if not (trainer and trainer._stepTX and trainer._stepTY) then
    return
  end
  local px, py = trainer.px or 0, trainer.py or 0
  local dx = trainer._stepTX - px
  local dy = trainer._stepTY - py
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 1.5 then
    trainer.px, trainer.py = trainer._stepTX, trainer._stepTY
    if session.grid and trainer.padU ~= nil then
      trainer.cellX, trainer.cellY =
        Coords.padToWorld(session.grid, trainer.padU, trainer.padV)
    end
    trainer._stepTX, trainer._stepTY = nil, nil
    trainer.moving = false
    return
  end
  local step = math.min(dist, TRAINER_STEP_SPEED * (dt or 1 / 60))
  trainer.px = px + dx / dist * step
  trainer.py = py + dy / dist * step
end

-- When a battler shares / brushes a trainer cell, walk the trainer aside.
local function keepTrainerClear(session, Grid, trainer, mon)
  if not (session and session.grid and Grid and trainer and mon) then
    return
  end
  if mon._removed or mon.hidden or trainer._removed then
    return
  end
  if trainer._stepTX then
    return
  end
  local tu, tv = trainer.padU, trainer.padV
  local mu, mv = mon.padU, mon.padV
  if tu == nil or mu == nil then
    return
  end
  local dist = math.abs(tu - mu) + math.abs(tv - mv)
  if dist > 1 then
    return
  end
  if not trainer._arFieldTrainerId then
    return
  end
  local awayU, awayV = tu - mu, tv - mv
  local dirs = {
    { awayU, awayV },
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
  }
  for i = 1, #dirs do
    local du, dv = dirs[i][1], dirs[i][2]
    if not (du == 0 and dv == 0) then
      if math.abs(du) > 1 then du = du > 0 and 1 or -1 end
      if math.abs(dv) > 1 then dv = dv > 0 and 1 or -1 end
      local nu, nv = tu + du, tv + dv
      if Grid.isFree(session.grid, nu, nv, trainer._arFieldTrainerId) then
        return beginTrainerStep(session, Grid, trainer, nu, nv, du, dv)
      end
    end
  end
  return false
end





-- When a battler shares / brushes a trainer cell, step the trainer aside.
-- local function keepTrainerClear(session, Grid, trainer, mon)
--   if not (session and session.grid and Grid and trainer and mon) then
--     return
--   end
--   if mon._removed or mon.hidden or trainer._removed then
--     return
--   end
--   local tu, tv = trainer.padU, trainer.padV
--   local mu, mv = mon.padU, mon.padV
--   if tu == nil or mu == nil then
--     return
--   end
--   local dist = math.abs(tu - mu) + math.abs(tv - mv)
--   if dist > 1 then
--     return
--   end
--   local occId = trainer._arFieldTrainerId
--   if not occId then
--     return
--   end
--   local awayU, awayV = tu - mu, tv - mv
--   local dirs = {
--     { awayU, awayV },
--     { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
--     { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
--   }
--   for i = 1, #dirs do
--     local du, dv = dirs[i][1], dirs[i][2]
--     if not (du == 0 and dv == 0) then
--       if math.abs(du) > 1 then du = du > 0 and 1 or -1 end
--       if math.abs(dv) > 1 then dv = dv > 0 and 1 or -1 end
--       local nu, nv = tu + du, tv + dv
--       if Grid.isFree(session.grid, nu, nv, occId) then
--         Grid.occupy(session.grid, occId, nu, nv)
--         trainer.padU, trainer.padV = nu, nv
--         local wx, wy = Coords.padToWorld(session.grid, nu, nv)
--         local px, py = Coords.padToPx(session.grid, nu, nv)
--         trainer.cellX, trainer.cellY = wx, wy
--         trainer.px, trainer.py = px, py
--         if math.abs(du) >= math.abs(dv) then
--           trainer.facing = du >= 0 and "right" or "left"
--         else
--           trainer.facing = dv >= 0 and "down" or "up"
--         end
--         return true
--       end
--     end
--   end
--   return false
-- end

function Lifecycle.onTurnEnded(battle)
  local session = Lifecycle.get(battle)
  if not (session and session.live and session.grid) then
    return
  end
  local Grid = session._deps.Grid
  local function maybeTrainer(ent, side)
    if not ent or ent._removed or ent._fainting then
      return
    end
    -- Occasional trainer check-in; keep rare so the pad doesn't thrash.
    if rr() <= 0.22 then
      local h = session.grid.home
          and ((side == "player") and session.grid.home.playerTrainer
            or session.grid.home.enemyTrainer)
      if h and h.u ~= nil and Grid.setPad(session.grid, ent, h.u, h.v) then
        ent._returnAt = now() + 0.55
        ent._returnU = ent.homePadU
        ent._returnV = ent.homePadV
        ent._wanderCD = 3.5
      end
    end
  end
  maybeTrainer(session.playerMon, "player")
  maybeTrainer(session.enemyMon, "enemy")
end

function Lifecycle.onTurnStarted(battle)
  local session = Lifecycle.get(battle)
  if not (session and session.live and session.grid) then
    return
  end
  local Grid = session._deps.Grid
  local function repairInvalidCell(ent)
    if not ent or ent._removed or ent._fainting then
      return
    end
    -- Free-tile positions persist across turns. Only repair a cell that fell
    -- outside the surveyed envelope (for example after a compatibility swap).
    if ent.padU ~= nil and not Grid.inEnvelope(session.grid, ent.padU, ent.padV)
        and ent.homePadU ~= nil then
      Grid.setPad(session.grid, ent, ent.homePadU, ent.homePadV)
      ent._wanderCD = 2.5
    end
  end
  repairInvalidCell(session.playerMon)
  repairInvalidCell(session.enemyMon)
end

function Lifecycle.react(battle, side, kind, opts)
  local session = Lifecycle.get(battle)
  if not (session and session.live) then
    return
  end
  local deps = session._deps
  deps.Cues.apply(session, side, kind, deps.Grid, Lifecycle.nudgeCamera, battle, opts)
end

function Lifecycle.shouldSkipEventReact(battle, side, kind)
  local session = Lifecycle.get(battle)
  local deps = session and session._deps
  if not (session and deps) then
    return false
  end
  return deps.Cues.shouldSkipEvent(session, side, kind)
end

local function wallNow(session)
  if session and session._now ~= nil then
    return session._now
  end
  if Lifecycle._now ~= nil then
    return Lifecycle._now
  end
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return nil
end

--- Find the live FIELD session + battle for this game (menus may sit on top).
function Lifecycle.liveBattle(game)
  local battle = nil
  for b, s in pairs(byBattle) do
    if s and s.live then
      battle = b
      break
    end
  end
  if not battle then
    return nil, nil
  end
  local stack = game and game.stack
  local states = stack and stack.states
  if type(states) == "table" then
    for i = #states, 1, -1 do
      local st = states[i]
      local s = st and byBattle[st]
      if s and s.live then
        battle = st
        break
      end
    end
  end
  return battle, byBattle[battle]
end

--- Test hook: bind a live session without going through begin().
function Lifecycle._testBind(battle, session)
  if battle then
    byBattle[battle] = session
  end
end

function Lifecycle._testUnbind(battle)
  if battle then
    byBattle[battle] = nil
  end
end

--- Present-clock tick. Safe to call from input.step, BattleState:update,
--- render.letterbox, and battle.overlay — deduped so bob never freezes
--- under menus. Must NOT early-out on waitingUI / stack top / auto==false.
function Lifecycle.tickPresent(game, dt, deps)
  local battle, session = Lifecycle.liveBattle(game)
  if not (battle and session and session.live) then
    return false
  end
  deps = deps or session._deps

  local t = wallNow(session)
  -- Already advanced this display frame (another driver got here first).
  if t and session._lastPresentAt and (t - session._lastPresentAt) < 0.008 then
    return false
  end

  local useDt = dt
  if t and session._lastPresentAt then
    useDt = t - session._lastPresentAt
  end
  if type(useDt) ~= "number" or useDt <= 0 then
    useDt = 1 / 60
  end
  if useDt > 1 / 15 then
    useDt = 1 / 15
  end
  if t then
    session._lastPresentAt = t
  else
    session._lastPresentAt = (session._lastPresentAt or 0) + useDt
  end

  Lifecycle.tick(battle, useDt, deps)
  return true
end

function Lifecycle.tickActive(game, dt, deps)
  return Lifecycle.tickPresent(game, dt, deps)
end

function Lifecycle.tick(battle, dt, deps)
  -- Per-battle Live tick: idle wander, trainer clear, switches, cast lerp,
  -- projectile step, and anim-transform cache. Prefer tickPresent from
  -- drivers that need menu-safe bob advancement.
  local session = Lifecycle.get(battle)
  if not (session and session.live) then
    return
  end
  -- Present clock: never gate on waitingUI, stack top, or current.auto.
  deps = deps or session._deps
  dt = dt or (1 / 60)

  if session.awaitPlayerMon then
    Lifecycle.tryRevealPlayerMon(battle)
  end

  tickSwitches(session, battle, deps, dt)
  if deps.Projectiles and type(deps.Projectiles.tick) == "function" then
    deps.Projectiles.tick(session, dt)
  end
  deps.Cues.pumpCurrent(session, battle, deps.Grid, Lifecycle.nudgeCamera)
  deps.Cues.tickReturns(session, deps.Grid)

  if session.camNudgeT and session.camNudgeT > 0 then
    session.camNudgeT = math.max(0, session.camNudgeT - dt)
  end

  local p, e = session.playerMon, session.enemyMon
  if p and p._faintDone then
    Lifecycle.despawnMon(battle, "player")
    p = nil
  end
  if e and e._faintDone then
    Lifecycle.despawnMon(battle, "enemy")
    e = nil
  end

  tickIdleWander(session, deps.Grid, p, "player", dt)
  tickIdleWander(session, deps.Grid, e, "enemy", dt)

  local ow = battle.game and battle.game.overworld
  if ow then
    keepTrainerClear(session, deps.Grid, ow.player, p)
    keepTrainerClear(session, deps.Grid, ow.player, e)
    keepTrainerClear(session, deps.Grid, session.foe, e)
    keepTrainerClear(session, deps.Grid, session.foe, p)
    stepTrainerClear(session, ow.player, dt)
    stepTrainerClear(session, session.foe, dt)
  end

  local moving = (p and p.targetPx and (
        math.abs((p.basePx or 0) - p.targetPx) > 1
        or math.abs((p.basePy or 0) - (p.targetPy or 0)) > 1))
      or (e and e.targetPx and (
        math.abs((e.basePx or 0) - e.targetPx) > 1
        or math.abs((e.basePy or 0) - (e.targetPy or 0)) > 1))
      or (p and p.anim and p.anim ~= "idle")
      or (e and e.anim and e.anim ~= "idle")

  session._camAcc = (session._camAcc or 0) + dt
  local camHz = ((session.camNudgeT or 0) > 0 or moving) and 0.05 or 0.12
  if session._camAcc >= camHz then
    session._camAcc = 0
    Lifecycle.focusCamera(battle)
  end

  session._faceAcc = (session._faceAcc or 0) + dt
  if session._faceAcc >= 0.15 then
    session._faceAcc = 0
    local grid = session.grid
    local function faceToward(ent, other)
      if not (ent and other) then
        return
      end
      local dx, dy
      if grid and ent.padU ~= nil and other.padU ~= nil then
        dx, dy = Coords.padDeltaToWorld(grid,
          other.padU - ent.padU, other.padV - ent.padV)
      else
        dx = (other.cellX or 0) - (ent.cellX or 0)
        dy = (other.cellY or 0) - (ent.cellY or 0)
      end
      if math.abs(dx) >= math.abs(dy) then
        ent.facing = dx >= 0 and "right" or "left"
      else
        ent.facing = dy >= 0 and "down" or "up"
      end
    end
    if p and e and (not p.anim or p.anim == "idle") then
      faceToward(p, e)
    end
    if e and p and (not e.anim or e.anim == "idle") then
      faceToward(e, p)
    end
  end

  if battle.animPlaying then
    local row = battle.moveAnimRow
    local atkPlayer = row and row.attackerIsPlayer
    if atkPlayer == nil and battle.current and battle.current.attackerIsPlayer ~= nil then
      atkPlayer = battle.current.attackerIsPlayer
    end
    if atkPlayer == true and p and type(p.play) == "function"
        and (not p.anim or p.anim == "idle") then
      p:play("attack")
    elseif atkPlayer == false and e and type(e.play) == "function"
        and (not e.anim or e.anim == "idle") then
      e:play("attack")
    end
  end

  deps.Cast.tick(session, dt)

  session._xformAcc = (session._xformAcc or 0) + dt
  if battle.animPlaying or moving or session._xformAcc >= 0.12 then
    session._xformAcc = 0
    deps.Anims.cache(session, battle)
  end
end

function Lifecycle.finish(battle, deps)
  -- Tear down Live cast, restore entity/camera/voxel snapshots, clear session.
  local session = battle and byBattle[battle]
  if not session then
    return
  end
  session.state = Lifecycle.STATE.Finishing
  session.live = false
  deps = deps or session._deps
  local Layout = deps and deps.Layout
  local Grid = deps and deps.Grid

  if Grid and session.grid then
    Grid.clear(session.grid)
  end
  if deps and deps.Projectiles and type(deps.Projectiles.clear) == "function" then
    deps.Projectiles.clear(session)
  end

  local game = battle.game
  local ow = game and game.overworld
  if ow then
    if session.playerPose and ow.player and Layout then
      Layout.applyPose(ow.player, session.playerPose)
      ow.player.moving = false
    end
    if session.foe and session.foePose and Layout then
      Layout.applyPose(session.foe, session.foePose)
      session.foe.moving = false
    end
    ow.engaging = nil
    ow._arFieldEngaging = nil
    if ow.player then
      ow.player.inputLocked = false
    end
    if type(session.savedEntities) == "table" and #session.savedEntities > 0 then
      local restored = {}
      for i = 1, #session.savedEntities do
        local e = session.savedEntities[i]
        if e and not e._fbv and not e._arFieldBattler and not e._arFieldCover then
          restored[#restored + 1] = e
        end
      end
      ow.entities = restored
    else
      local keep = {}
      for i = 1, #(ow.entities or {}) do
        local e = ow.entities[i]
        if e and not e._fbv and not e._arFieldBattler and not e._arFieldCover then
          keep[#keep + 1] = e
        end
      end
      ow.entities = keep
    end
  end

  -- FIELD never writes map tiles; no snapshot rewind.
  session.arenaEdits = nil
  session.mapSnap = nil

  restoreZoom(session)
  restoreVoxel(session)
  if battle then
    battle._arAnimeField = nil
  end
  byBattle[battle] = nil
end

return Lifecycle
