-- Field battle — move / hit SFX synced to our world FX.
--
-- Classic battles play sounds from AnimPlayer rows (BattleState.playAnimSound).
-- FIELD suppresses that paint and fires projectiles from Cues on move_used, so
-- engine SFX land later (or not at all if the anim is cancelled). This module
-- owns the audible beat while a FIELD session is live: play on cue, mute the
-- engine's Sound.playMove so nothing doubles.

local Audio = {}

Audio._suppressEngine = 0

local function tryRequire(path)
  local ok, mod = pcall(require, path)
  if ok then
    return mod
  end
  return nil
end

function Audio.enterField()
  Audio._suppressEngine = (Audio._suppressEngine or 0) + 1
end

function Audio.leaveField()
  Audio._suppressEngine = math.max(0, (Audio._suppressEngine or 0) - 1)
end

function Audio.suppressingEngine()
  return (Audio._suppressEngine or 0) > 0
end

--- Install once: mute engine move SFX while FIELD owns presentation.
function Audio.installEngineMute()
  local Sound = tryRequire("src.core.Sound")
  if not (Sound and type(Sound.playMove) == "function") or Sound._arFieldMute then
    return
  end
  local orig = Sound.playMove
  function Sound.playMove(data, anim)
    if Audio.suppressingEngine() then
      return
    end
    return orig(data, anim)
  end
  Sound._arFieldMute = true
end

local function moveDef(battle, moveId)
  if not (battle and battle.data and battle.data.moves and moveId) then
    return nil
  end
  local id = tostring(moveId):upper():gsub("%s+", "_")
  local def = battle.data.moves[id]
  if def then
    return def, id
  end
  -- Some rows pass the name; scan once.
  for mid, mdef in pairs(battle.data.moves) do
    if type(mdef) == "table" and tostring(mdef.name or ""):upper() == id then
      return mdef, mid
    end
  end
  return nil, id
end

--- Play the move's MoveSoundTable entry (pitch/tempo aware).
function Audio.playMove(battle, moveId, attackerIsPlayer)
  if not battle then
    return false
  end
  local Sound = tryRequire("src.core.Sound")
  if not Sound then
    return false
  end
  local def, id = moveDef(battle, moveId)
  if not def then
    return false
  end
  -- GROWL / ROAR use the attacker's cry (IsCryMove).
  if id == "GROWL" or id == "ROAR" then
    local side = attackerIsPlayer and battle.player or battle.enemy
    local species = side and side.mon and side.mon.species
    if species and type(Sound.playMoveCry) == "function" then
      local tempo = def.anim and def.anim.tempo
      pcall(Sound.playMoveCry, battle.data, species, tempo)
      return true
    end
  end
  local anim = def.anim
  if not (anim and anim.sound) then
    return false
  end
  -- Bypass our mute wrapper for the intentional FIELD play.
  local was = Audio._suppressEngine
  Audio._suppressEngine = 0
  local ok = false
  if type(Sound.playMove) == "function" then
    -- Call through a direct require of the original if we stashed it…
    -- The wrapper checks suppressingEngine(); with 0 it reaches the real play.
    ok = pcall(Sound.playMove, battle.data, anim)
  elseif type(Sound.play) == "function" then
    ok = pcall(Sound.play, battle.data, anim.sound)
  end
  Audio._suppressEngine = was
  return ok and true or false
end

--- Impact thud matching PlayApplyingAttackSound (#826 pitch path).
function Audio.playHit(battle, typeMult)
  if not battle then
    return false
  end
  local Sound = tryRequire("src.core.Sound")
  if not Sound then
    return false
  end
  typeMult = tonumber(typeMult) or 10

  -- Use a different pitch calculation path
  local sfx = {}
  if typeMult > 10 then
    sfx.sound = "Super_Effective"
    -- Pitch raises with multiplier (max 24 semitones up at x4)
    sfx.pitch = math.floor(0x80 + math.min(24, (typeMult - 10) * 1.5))
  elseif typeMult < 10 then
    sfx.sound = "Not_Very_Effective"
    -- Pitch lowers with smaller multiplier (down to 0 at x0.25)
    sfx.pitch = math.floor(0x40 - math.min(32, (10 - typeMult) * 2.5))
    if sfx.pitch < 0x10 then sfx.pitch = 0x10 end
  else
    sfx.sound = "Damage"
    sfx.pitch = 0x60
  end

  local was = Audio._suppressEngine
  Audio._suppressEngine = 0
  local ok = false
  if type(Sound.playMove) == "function" then
    ok = pcall(Sound.playMove, battle.data, sfx)
  elseif type(Sound.play) == "function" then
    ok = pcall(Sound.play, battle.data, sfx.sound)
  end
  Audio._suppressEngine = was
  return ok and true or false
end

return Audio
