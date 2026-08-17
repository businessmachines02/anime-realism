-- Field battle — move / hit SFX synced to our world FX.
--
-- The engine always plays PlayApplyingAttackSound ("Damage" / SE / NVE) from
-- BattleState.applyHitFx after the move anim. FIELD already owns that beat
-- from Cues, so applyHitFx.sfx is stripped while a session is live. Intentional
-- FIELD samples call the stashed Sound.playMove — they must not drop the
-- suppress flag or the engine thud can leak on the same tick.

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
  local Sound = tryRequire("src.core.Sound")
  if Sound then
    Sound._arFieldSuppress = (Sound._arFieldSuppress or 0) + 1
  end
end

function Audio.leaveField()
  Audio._suppressEngine = math.max(0, (Audio._suppressEngine or 0) - 1)
  local Sound = tryRequire("src.core.Sound")
  if Sound then
    Sound._arFieldSuppress = math.max(0, (Sound._arFieldSuppress or 0) - 1)
  end
end

function Audio.suppressingEngine()
  if (Audio._suppressEngine or 0) > 0 then
    return true
  end
  local Sound = tryRequire("src.core.Sound")
  return Sound and (Sound._arFieldSuppress or 0) > 0
end

local HIT_SFX = {
  Damage = true,
  Super_Effective = true,
  Not_Very_Effective = true,
}

local function fieldPlayMove(data, anim)
  local Sound = tryRequire("src.core.Sound")
  local fn = Audio._origPlayMove
      or (Sound and Sound._arFieldOrigPlayMove)
  if type(fn) ~= "function" then
    fn = Sound and Sound.playMove
  end
  if type(fn) == "function" then
    return fn(data, anim)
  end
  local play = Audio._origPlay
  if type(play) ~= "function" then
    local Sound = tryRequire("src.core.Sound")
    play = Sound and Sound.play
  end
  if type(play) == "function" and anim and anim.sound then
    return play(data, anim.sound)
  end
end

--- Install once: mute engine move / applying-attack SFX while FIELD owns presentation.
function Audio.installEngineMute()
  local Sound = tryRequire("src.core.Sound")
  if Sound and not Sound._arFieldMute then
    if type(Sound.playMove) == "function" then
      local origMove = Sound.playMove
      Audio._origPlayMove = origMove
      Sound._arFieldOrigPlayMove = origMove
      function Sound.playMove(data, anim)
        if (Sound._arFieldSuppress or 0) > 0 then
          return
        end
        return origMove(data, anim)
      end
    end
    if type(Sound.play) == "function" then
      local origPlay = Sound.play
      Audio._origPlay = origPlay
      function Sound.play(data, name)
        if (Sound._arFieldSuppress or 0) > 0 and HIT_SFX[tostring(name or "")] then
          return
        end
        return origPlay(data, name)
      end
    end
    Sound._arFieldMute = true
  end

  -- The generic thud on every connecting hit is applyHitFx, not AnimPlayer.
  local okBS, BattleState = pcall(require, "src.battle.BattleState")
  if okBS and BattleState and type(BattleState.applyHitFx) == "function"
      and not BattleState._arFieldMuteHitFx then
    local origHitFx = BattleState.applyHitFx
    function BattleState.applyHitFx(self, hit)
      -- FIELD battles stamp _arAnimeField. Drop the applying-attack sample
      -- (Damage / SE / NVE) so it cannot fire after the hidden engine anim.
      if self and self._arAnimeField and type(hit) == "table" and hit.sfx then
        hit = {
          animType = hit.animType,
          blink = hit.blink,
        }
      end
      return origHitFx(self, hit)
    end
    BattleState._arFieldMuteHitFx = true
  end
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
  for mid, mdef in pairs(battle.data.moves) do
    if type(mdef) == "table" and tostring(mdef.name or ""):upper() == id then
      return mdef, mid
    end
  end
  return nil, id
end

--- Play the move's MoveSoundTable entry (pitch/tempo aware).
function Audio.playMove(battle, moveId, attackerIsPlayer)
  Audio._lastMovePlayed = false
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
      Audio._lastMovePlayed = true
      return true
    end
  end
  local anim = def.anim
  if not (anim and anim.sound) then
    return false
  end
  local ok = pcall(fieldPlayMove, battle.data, anim)
  Audio._lastMovePlayed = ok and true or false
  return ok and true or false
end

--- Impact thud matching PlayApplyingAttackSound (#826 pitch path).
-- Neutral physicals skip when the move sample just played — Tackle / Scratch
-- already sound like Damage, and stacking them is the "double generic hit".
function Audio.playHit(battle, typeMult, opts)
  if not battle then
    return false
  end
  typeMult = tonumber(typeMult) or 10
  local category = opts and opts.category
  if category == "physical" and typeMult == 10 and Audio._lastMovePlayed then
    Audio._lastMovePlayed = false
    return false
  end
  Audio._lastMovePlayed = false

  local sfx = {}
  if typeMult > 10 then
    sfx.sound = "Super_Effective"
    sfx.pitch = math.floor(0x80 + math.min(24, (typeMult - 10) * 1.5))
  elseif typeMult < 10 then
    sfx.sound = "Not_Very_Effective"
    sfx.pitch = math.floor(0x40 - math.min(32, (10 - typeMult) * 2.5))
    if sfx.pitch < 0x10 then sfx.pitch = 0x10 end
  else
    sfx.sound = "Damage"
    sfx.pitch = 0x60
  end

  local ok = pcall(fieldPlayMove, battle.data, sfx)
  return ok and true or false
end

return Audio
