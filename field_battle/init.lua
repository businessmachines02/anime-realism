-- Field battle — standalone overworld combat (tile-grid movement tracker)
--
-- BATTLE STAGE = FIELD: fights stay on the map via transparent BattleState.
-- Cast occupies pad cells; pixels lerp toward padToPx. Present clock keeps
-- idle/attack/cast anims advancing while menus sit on top of BattleState.
--
-- Sibling packages:
--   immersion/     → HP/EXP hide + rewards
--   battle/        → traditional battle systems
--   field_battle/  → this package
--
-- Module map (loaded below):
--   intercept   push BattleState as a transparent stack host (no wipe)
--   lifecycle   Idle→Armed→Staging→Live→Finishing session owner
--   hooks       BattleState draw/input wraps + battle.* events
--   ui          compact command / diamond moves / dialogue chrome
--   survey      read-only walkable envelope around the encounter
--   grid        pad occupancy + step helpers (pad is truth)
--   cast        stage trainers + mons onto pad homes
--   cues        arFieldCue → step-in / cast-in-place choreography
--   sprites     OW follower sheets as battlers (+ bob / motion)
--   projectiles world-space FX entities (camera/voxel aligned)
--   anims       classic move FX affine → live pad centers
--   arena       themed overlay props on pad cells (session-only)
--   themes      map-id → kit (cover/grass/pond colors)
--   layout      tight adjacent-mon formation along the fight axis
--   coords      pad ↔ world ↔ pixel conversions
--   fx_catalog  TYPE_COLORS / MOVE_FX / TYPE_STYLE / TYPE_CONTACT
--   spectators  nearby trainers walk in, watch, rare shoutouts
--   wildlife    roaming OW mons scatter away from the duel
--   compat      suppress foreign staged battles while FIELD is on
--   debug       optional pad occupancy overlay
--
-- Public surface is the FBV table returned from this loader.

return function(env)
  local loadFile = env and env.load
  local mod = env and env.mod
  if type(loadFile) ~= "function" then
    error("field_battle/init.lua requires env.load", 2)
  end

  local Coords = loadFile("coords.lua")
  local Themes = loadFile("themes.lua")
  local FxCatalog = loadFile("fx_catalog.lua")
  do
    local loaded = package and package.loaded
    if type(loaded) == "table" then
      loaded["coords"] = Coords
      loaded["themes"] = Themes
      loaded["fx_catalog"] = FxCatalog
    end
  end
  local origRequire = require
  require = function(name)
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
    Layout = loadFile("layout.lua")
    Sprites = loadFile("sprites.lua")
    Arena = loadFile("arena.lua")
    Survey = loadFile("survey.lua")
    Grid = loadFile("grid.lua")
    Cast = loadFile("cast.lua")
    Cues = loadFile("cues.lua")
    Projectiles = loadFile("projectiles.lua")
    Audio = loadFile("audio.lua")
    Anims = loadFile("anims.lua")
    Lifecycle = loadFile("lifecycle.lua")
    Spectators = loadFile("spectators.lua")
    Wildlife = loadFile("wildlife.lua")
    Compat = loadFile("compat.lua")
    Hooks = loadFile("hooks.lua")
    Intercept = loadFile("intercept.lua")
    Debug = loadFile("debug.lua")
    UI = loadFile("ui.lua")
    Callouts = loadFile("callouts.lua")
  end)
  require = origRequire
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

  local FBV = {
    id = "field_battle",
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
    OPTION_KEYS = { "battle_stage", "field_sprites", "close_the_gap" },
  }

  function FBV.session(battle)
    return Lifecycle.get(battle)
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

  function FBV.nudgeCamera(battle, side, seconds)
    return Lifecycle.nudgeCamera(battle, side, seconds)
  end

  function FBV.monScreen(battle, side)
    return Lifecycle.monScreen(battle, side, Anims)
  end

  function FBV.begin(battle, mod)
    return Lifecycle.begin(battle, mod, deps)
  end

  function FBV.finish(battle)
    return Lifecycle.finish(battle, deps)
  end

  function FBV.syncMons(battle, mod, side)
    return Lifecycle.syncMons(battle, mod, deps, side)
  end

  function FBV.stagePlayerMon(battle, mod)
    return Lifecycle.stagePlayerMon(battle, mod, deps)
  end

  function FBV.tick(battle, dt)
    return Lifecycle.tick(battle, dt, deps)
  end

  function FBV.tickPresent(game, dt)
    return Lifecycle.tickPresent(game, dt, deps)
  end

  function FBV.tickActive(game, dt)
    return Lifecycle.tickPresent(game, dt, deps)
  end

  function FBV.drawDebug(battle)
    if not Debug then
      return
    end
    return Debug.draw(Lifecycle.get(battle), battle)
  end

  function FBV.drawUI(battle)
    if battle and FBV.shouldUse(mod, battle) then
      battle._arAnimeField = true
    end
    if UI and type(UI.draw) == "function" then
      UI.draw(battle)
    end
    -- Attack FX on the same overlay as HP (world→UI mapped).
    local session = Lifecycle and Lifecycle.get and Lifecycle.get(battle)
    if session and Projectiles and type(Projectiles.drawUi) == "function" then
      pcall(Projectiles.drawUi, session, battle)
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
    return Lifecycle.react(battle, side, kind, opts)
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

  -- Inject cross-package services (ReactiveDefense) into the FIELD deps bag.
  function FBV.bind(packages)
    local RD = packages and packages.battle and packages.battle.ReactiveDefense
    deps.ReactiveDefense = RD
    FBV.ReactiveDefense = RD
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
