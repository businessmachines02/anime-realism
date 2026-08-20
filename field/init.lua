-- Field battle — standalone overworld combat (tile-grid movement tracker)
--
-- BATTLE STAGE = FIELD: fights stay on the map via transparent BattleState.
-- Cast occupies pad cells; pixels lerp toward padToPx. Present clock keeps
-- idle/attack/cast anims advancing while menus sit on top of BattleState.
--
-- Sibling packages:
--   hud/     → HP/EXP hide + rewards
--   battle/  → REACT rules, menus, FX policy, dialogue paint
--   field/   → this package
--
-- Folders (env.load paths are relative to field/):
--   pad/      coords, grid, layout, survey, cast
--   session/  lifecycle, intercept, compat, spectators, wildlife
--   fx/       catalog, projectiles, cues (+ cues_*), anims, audio, sprites
--   stage/    arena, themes, arenas/*.lua kits
--   chrome/   ui, callouts, debug, hooks*
--
-- Public surface is the FBV table returned from this loader.

return function(env)
  local loadFile = env and env.load
  local mod = env and env.mod
  if type(loadFile) ~= "function" then
    error("field/init.lua requires env.load", 2)
  end

  local Coords = loadFile("pad/coords.lua")
  local Themes = loadFile("stage/themes.lua")
  do
    local ids = {
      "cave", "city", "forest", "grave", "gym", "indoor", "mountain", "route", "water",
    }
    for i = 1, #ids do
      local ok, layout = pcall(loadFile, "stage/arenas/" .. ids[i] .. ".lua")
      if ok and type(layout) == "table" and type(Themes.registerLayout) == "function" then
        Themes.registerLayout(layout.id or ids[i], layout)
      end
    end
  end
  local FxCatalog = loadFile("fx/fx_catalog.lua")
  do
    local loaded = package and package.loaded
    if type(loaded) == "table" then
      loaded["coords"] = Coords
      loaded["themes"] = Themes
      loaded["fx_catalog"] = FxCatalog
    end
  end
  -- Sibling shims only while this package loads. Always restore _G.require;
  -- a leaked wrapper can hand Dramatic Shape our pad coords module.
  local origRequire = _G.require
  _G.require = function(name)
    if name == "coords" then
      return Coords
    end
    if name == "themes" then
      return Themes
    end
    if name == "fx_catalog" then
      return FxCatalog
    end
    return origRequire(name)
  end
  local Layout, Sprites, Arena, Survey, Grid, Cast, Cues, Projectiles
  local Audio, Anims, Lifecycle, Spectators, Wildlife, Compat
  local Hooks, Intercept, Debug, UI, Callouts
  local loadOk, loadErr = pcall(function()
    Layout = loadFile("pad/layout.lua")
    Sprites = loadFile("fx/sprites.lua")
    Arena = loadFile("stage/arena.lua")
    Survey = loadFile("pad/survey.lua")
    Grid = loadFile("pad/grid.lua")
    Cast = loadFile("pad/cast.lua")
    Cues = loadFile("fx/cues.lua")
    if Cues and type(Cues.attach) == "function" then
      Cues.attach(loadFile)
    end
    Projectiles = loadFile("fx/projectiles.lua")
    Audio = loadFile("fx/audio.lua")
    Anims = loadFile("fx/anims.lua")
    Lifecycle = loadFile("session/lifecycle.lua")
    Spectators = loadFile("session/spectators.lua")
    Wildlife = loadFile("session/wildlife.lua")
    Compat = loadFile("session/compat.lua")
    Hooks = loadFile("chrome/hooks.lua")
    do
      local attach = {
        "chrome/hooks_draw.lua",
        "chrome/hooks_input.lua",
        "chrome/hooks_events.lua",
      }
      for i = 1, #attach do
        local chunk = loadFile(attach[i])
        if type(chunk) == "function" then
          chunk(Hooks)
        end
      end
    end
    Intercept = loadFile("session/intercept.lua")
    Debug = loadFile("chrome/debug.lua")
    UI = loadFile("chrome/ui.lua")
    Callouts = loadFile("chrome/callouts.lua")
  end)
  _G.require = origRequire
  if not loadOk then
    error(loadErr)
  end

  local deps = {
    Layout = Layout,
    Sprites = Sprites,
    Arena = Arena,
    Survey = Survey,
    Coords = Coords,
    Themes = Themes,
    Grid = Grid,
    Cast = Cast,
    Cues = Cues,
    Projectiles = Projectiles,
    Audio = Audio,
    Anims = Anims,
    Lifecycle = Lifecycle,
    Spectators = Spectators,
    Wildlife = Wildlife,
    Compat = Compat,
    Debug = Debug,
    UI = UI,
    Callouts = Callouts,
  }

  local function loggedCall(battle, tag, noisy, fn, ...)
    local Log = deps.Log
    if noisy and Log and type(Log.note) == "function" then
      pcall(Log.note, battle, tag)
    end
    local n = select("#", ...)
    local args = { ... }
    local tracer = (type(debug) == "table" and debug.traceback) or tostring
    local ok, a, b, c, d, e = xpcall(function()
      return fn(unpack(args, 1, n))
    end, tracer)
    if not ok then
      if Log and type(Log.err) == "function" then
        pcall(Log.err, battle, tag, a)
      end
      error(a)
    end
    return a, b, c, d, e
  end

  local FBV = {
    id = "field",
    title = "Field battle (standalone OW combat)",
    Layout = Layout,
    Sprites = Sprites,
    Arena = Arena,
    Survey = Survey,
    Coords = Coords,
    Themes = Themes,
    Grid = Grid,
    Cast = Cast,
    Cues = Cues,
    Projectiles = Projectiles,
    Audio = Audio,
    Anims = Anims,
    Lifecycle = Lifecycle,
    Spectators = Spectators,
    Wildlife = Wildlife,
    Compat = Compat,
    Debug = Debug,
    UI = UI,
    Callouts = Callouts,
    Intercept = Intercept,
    OPTION_KEYS = { "battle_stage", "field_sprites", "move_hud", "close_the_gap", "status_chips" },
  }

  function FBV.session(battle)
    return Lifecycle.get(battle)
  end

  -- Hooks / main talk to these instead of Lifecycle / Cues guts.
  function FBV.tryMouseLook(game, x, y, dx, dy)
    if not (Lifecycle and type(Lifecycle.liveBattle) == "function") then
      return
    end
    local session = select(2, Lifecycle.liveBattle(game))
    if session and session.live and type(Lifecycle.tryMouseLook) == "function" then
      return Lifecycle.tryMouseLook(session, x, y, nil, nil, dx, dy)
    end
  end

  function FBV.vanishKind(moveId)
    if Cues and type(Cues.vanishKind) == "function" then
      return Cues.vanishKind(moveId)
    end
  end

  function FBV.shouldHoldEngineHit(session, opts)
    return Cues and type(Cues.shouldHoldEngineHit) == "function"
      and Cues.shouldHoldEngineHit(session, opts)
  end

  function FBV.holdCloseHit(session, side, opts)
    if Cues and type(Cues.holdCloseHit) == "function" then
      return Cues.holdCloseHit(session, side, opts)
    end
  end

  function FBV.isMeleeAttack(opts)
    if Cues and type(Cues.isMeleeAttack) == "function" then
      return Cues.isMeleeAttack(opts, Projectiles)
    end
  end

  function FBV.closeGapHoldActive(session)
    return Cues and type(Cues.closeGapHoldActive) == "function"
      and Cues.closeGapHoldActive(session)
  end

  function FBV.shouldParkEngineQueue(session)
    return Cues and type(Cues.shouldParkEngineQueue) == "function"
      and Cues.shouldParkEngineQueue(session)
  end

  function FBV.tagSelfDamage(battle, text, side)
    if Cues and type(Cues.tagSelfDamage) == "function" then
      return Cues.tagSelfDamage(battle, text, side)
    end
  end

  function FBV.tagMiss(battle, text, side)
    if Cues and type(Cues.tagMiss) == "function" then
      return Cues.tagMiss(battle, text, side)
    end
  end

  function FBV.tagChargeVanish(battle, text)
    if Cues and type(Cues.tagChargeVanish) == "function" then
      return Cues.tagChargeVanish(battle, text)
    end
  end

  function FBV.liveBattle(game)
    if Lifecycle and type(Lifecycle.liveBattle) == "function" then
      return Lifecycle.liveBattle(game)
    end
  end

  function FBV.drawWorldOverlay(battle)
    if Lifecycle and type(Lifecycle.drawWorldOverlay) == "function" then
      return Lifecycle.drawWorldOverlay(battle)
    end
  end

  function FBV.unwedgeVoxelPass(mod)
    if Compat and type(Compat.unwedgeVoxelPass) == "function" then
      return Compat.unwedgeVoxelPass(mod)
    end
  end

  function FBV.fieldAllowsStackedBottomUI(battle)
    return Compat and type(Compat.fieldAllowsStackedBottomUI) == "function"
      and Compat.fieldAllowsStackedBottomUI(battle)
  end

  function FBV.active(battle)
    return Lifecycle.active(battle)
  end

  function FBV.focusCamera(battle)
    return Lifecycle.focusCamera(battle)
  end

  function FBV.tickReturnCamera(ow, dt)
    return Lifecycle.tickReturnCamera(ow, dt)
  end

  function FBV.animShift(battle)
    return Lifecycle.animShift(battle, Anims)
  end

  function FBV.animTransform(battle)
    return Lifecycle.animTransform(battle, Anims)
  end

  function FBV.animTransformCached(battle)
    return Lifecycle.animTransformCached(battle, Anims)
  end

  function FBV.cacheAnimTransform(battle)
    return Lifecycle.cacheAnimTransform(battle, Anims)
  end

  function FBV.cancelCloseStrike(battle, side)
    local session = Lifecycle.get(battle)
    if session and Cues and type(Cues.cancelCloseStrike) == "function" then
      return Cues.cancelCloseStrike(session, side, Grid)
    end
  end

  function FBV.deferCancelCloseStrike(battle, side, delay)
    local session = Lifecycle.get(battle)
    if session and Cues and type(Cues.deferCancelCloseStrike) == "function" then
      return Cues.deferCancelCloseStrike(session, side, delay)
    end
  end

  function FBV.beginReactHold(battle)
    local session = Lifecycle.get(battle)
    if session and Cues and type(Cues.beginReactHold) == "function" then
      return Cues.beginReactHold(session, battle)
    end
  end

  function FBV.releaseReactHold(battle, outcome)
    local session = Lifecycle.get(battle)
    if session and Cues and type(Cues.releaseReactHold) == "function" then
      return Cues.releaseReactHold(session, outcome)
    end
  end

  function FBV.isRangedCounter(opts)
    if Cues and type(Cues.isRangedCounter) == "function" then
      return Cues.isRangedCounter(opts, Projectiles)
    end
  end

  function FBV.closeGapPending(battle, side)
    local session = Lifecycle.get(battle)
    if not session then
      return false
    end
    local ent = (side == "player") and session.playerMon or session.enemyMon
    return ent and ent._pendingCloseStrike and true or false
  end

  function FBV.nudgeCamera(battle, side, seconds)
    return Lifecycle.nudgeCamera(battle, side, seconds)
  end

  function FBV.monScreen(battle, side)
    return Lifecycle.monScreen(battle, side, Anims)
  end

  function FBV.begin(battle, mod)
    return loggedCall(battle, "field.begin", true, Lifecycle.begin, battle, mod, deps)
  end

  function FBV.finish(battle)
    return loggedCall(battle, "field.finish", true, Lifecycle.finish, battle, deps)
  end

  function FBV.syncMons(battle, mod, side)
    return loggedCall(battle, "field.syncMons", true, Lifecycle.syncMons, battle, mod, deps, side)
  end

  function FBV.stagePlayerMon(battle, mod)
    return Lifecycle.stagePlayerMon(battle, mod, deps)
  end

  function FBV.tick(battle, dt)
    return loggedCall(battle, "tick", false, Lifecycle.tick, battle, dt, deps)
  end

  function FBV.tickPresent(game, dt)
    return loggedCall(nil, "tickPresent", false, Lifecycle.tickPresent, game, dt, deps)
  end

  function FBV.tickActive(game, dt)
    return FBV.tickPresent(game, dt)
  end

  function FBV.drawDebug(battle)
    if not Debug then
      return
    end
    return Debug.draw(Lifecycle.get(battle), battle)
  end

  function FBV.statusChipsEnabled(modRef)
    modRef = modRef or mod
    if not (modRef and modRef.options and type(modRef.options.get) == "function") then
      return true
    end
    return modRef.options:get("status_chips") ~= false
  end

  function FBV.armStatusChip(battle, side, text)
    if not FBV.statusChipsEnabled(mod) then
      return false
    end
    if UI and type(UI.armStatusChip) == "function" then
      return UI.armStatusChip(battle, side, text)
    end
    return false
  end

  function FBV.drawUI(battle)
    if battle and FBV.shouldUse(mod, battle) then
      battle._arAnimeField = true
    end
    if UI and type(UI.syncStatusChips) == "function" then
      if FBV.statusChipsEnabled(mod) then
        UI.syncStatusChips(battle)
      elseif battle then
        battle._arFieldChipDialogue = nil
      end
    end
    if UI and type(UI.draw) == "function" then
      UI.draw(battle, FBV.moveHudStyle(mod))
    end
    -- Attack FX on the same overlay as HP (world→UI mapped).
    local session = Lifecycle and Lifecycle.get and Lifecycle.get(battle)
    if session and Projectiles and type(Projectiles.drawUi) == "function" then
      local okUi, errUi = pcall(Projectiles.drawUi, session, battle)
      if not okUi then
        local Log = deps.Log
        if Log and type(Log.err) == "function" then
          pcall(Log.err, battle, "drawUi", errUi)
        end
      end
    end
  end

  -- One FIELD overlay pass: game box + REACT chips + banter strip. Callers
  -- must not also run battle.overlay next() (classic / gen3 / bubbles).
  function FBV.drawFrame(battle)
    FBV.drawUI(battle)
    local stacked = type(FBV.fieldAllowsStackedBottomUI) == "function"
      and FBV.fieldAllowsStackedBottomUI(battle)
    if not stacked then
      FBV.drawCallouts(battle)
    end
  end

  -- After the white narrator toast so the foe strip can sit above it.
  function FBV.drawCallouts(battle)
    local session = Lifecycle and Lifecycle.get and Lifecycle.get(battle)
    if session and Callouts and type(Callouts.draw) == "function" then
      pcall(Callouts.draw, session, battle)
    end
  end

  function FBV.compactUIActive(battle)
    return (UI and type(UI.active) == "function" and UI.active(battle))
      or FBV.shouldUse(mod, battle)
  end

  function FBV.react(battle, side, kind, opts)
    return loggedCall(battle, "react", false, Lifecycle.react, battle, side, kind, opts)
  end

  -- Read a stashed battle.accuracy result. main.lua overwrites this with a
  -- peek that front-runs the real hook; tests use this reader.
  function FBV.predictMoveHit(battle, user, target, move)
    local pred = battle and battle._arAccuracyPred
    if not (pred and user and move) then
      return nil
    end
    if pred.user ~= user or pred.moveId ~= move.id then
      return nil
    end
    if target and pred.target and pred.target ~= target then
      return nil
    end
    return pred.hit
  end

  function FBV.shouldSkipEventReact(battle, side, kind, opts)
    return Lifecycle.shouldSkipEventReact(battle, side, kind, opts)
  end

  function FBV.onFainted(battle, side)
    return Lifecycle.onFainted(battle, side)
  end

  function FBV.onTurnEnded(battle)
    return Lifecycle.onTurnEnded(battle)
  end

  function FBV.onTurnStarted(battle)
    return Lifecycle.onTurnStarted(battle)
  end

  function FBV.capture(battle, ev)
    return Lifecycle.capture(battle, ev)
  end

  -- BATTLE STAGE: FIELD keeps fights on the live map. AUTO leaves other
  -- presentation mods alone. Legacy CLASSIC → AUTO; STADIUM → FIELD (the
  -- 3D stadium presentation is gone, so those saves keep map fights).
  function FBV.stage(mod)
    if not (mod and mod.options and type(mod.options.get) == "function") then
      return "AUTO"
    end
    local raw = tostring(mod.options:get("battle_stage") or "FIELD"):upper()
    if raw == "FIELD" or raw == "STADIUM" then
      return "FIELD"
    end
    return "AUTO"
  end

  function FBV.enabled(mod)
    return FBV.stage(mod) == "FIELD"
  end

  -- MOVE HUD: CLASSIC is the compact 2×2 (D-pad moves, A confirms).
  -- DIAMOND is the U/R/L/D compass with instant-cast. Unset → CLASSIC.
  function FBV.moveHudStyle(modRef)
    modRef = modRef or mod
    if not (modRef and modRef.options and type(modRef.options.get) == "function") then
      return "CLASSIC"
    end
    local raw = tostring(modRef.options:get("move_hud") or "CLASSIC"):upper()
    if raw == "DIAMOND" then
      return "DIAMOND"
    end
    return "CLASSIC"
  end

  -- FIELD owns ordinary single wild and trainer encounters. Link, demo,
  -- double, and other special battle hosts retain their normal presentation.
  function FBV.supportsBattle(battle)
    if not battle or battle.link or battle.demo
        or battle.double or battle.isDouble or battle.doubleBattle then
      return false
    end
    local kind = tostring(battle.kind or ""):lower()
    return kind == "wild" or kind == "trainer"
  end

  function FBV.shouldUse(mod, battle)
    return FBV.enabled(mod) and FBV.supportsBattle(battle)
  end

  -- Runtime FIELD predicate: intercept flags (cache) or shouldUse (policy).
  function FBV.isFieldBattle(battle)
    if Compat and type(Compat.isFieldBattle) == "function" then
      return Compat.isFieldBattle(battle, FBV, mod)
    end
    if not battle then
      return false
    end
    if battle._arAnimeField or battle._arFieldCombat or battle._arFieldStandalone then
      return true
    end
    return FBV.shouldUse(mod, battle)
  end

  -- Inject cross-package services (ReactiveDefense, DEV logger) into deps.
  function FBV.setLog(log)
    deps.Log = log
    FBV.Log = log
    if Audio then
      Audio._Log = log
    end
    if Cues then
      Cues._Log = log
    end
    return true
  end

  function FBV.notePos(battle, tag)
    local session = Lifecycle.get(battle)
    if Cues and type(Cues.notePos) == "function" then
      return Cues.notePos(session, battle, tag)
    end
  end

  function FBV.bind(packages)
    local RD = packages and packages.battle and packages.battle.ReactiveDefense
    deps.ReactiveDefense = RD
    FBV.ReactiveDefense = RD
    if packages and packages.log then
      FBV.setLog(packages.log)
    end
    return true
  end

  function FBV.install(mod)
    if mod and mod._arPackages then
      pcall(FBV.bind, mod._arPackages)
    end
    pcall(Intercept.install, FBV, mod)
    return Hooks.install(FBV, mod)
  end

  return FBV
end
