-- Field battle — move / hit SFX synced to our world FX.
--
-- The engine always plays PlayApplyingAttackSound ("Damage" / SE / NVE) from
-- BattleState.applyHitFx after the move anim. FIELD already owns that beat
-- from Cues, so applyHitFx.sfx is stripped while a session is live. Intentional
-- FIELD samples start their own overlapping voices — they must not drop the
-- suppress flag or the engine thud can leak on the same tick.
--
-- Sound.playMove is one SFX bus (stop or drop the previous row). FIELD clones
-- each sample and ducks whatever is still playing so rapid moves stack.

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
  if Audio._Log and type(Audio._Log.note) == "function" then
    pcall(Audio._Log.note, nil, "audio.enterField", Audio._suppressEngine)
  end
  local Sound = tryRequire("src.core.Sound")
  if Sound then
    Sound._arFieldSuppress = (Sound._arFieldSuppress or 0) + 1
  end
end

function Audio.leaveField()
  Audio._suppressEngine = math.max(0, (Audio._suppressEngine or 0) - 1)
  if Audio._Log and type(Audio._Log.note) == "function" then
    pcall(Audio._Log.note, nil, "audio.leaveField", Audio._suppressEngine)
  end
  local Sound = tryRequire("src.core.Sound")
  if Sound then
    Sound._arFieldSuppress = math.max(0, (Sound._arFieldSuppress or 0) - 1)
  end
  Audio.clearVoices()
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

-- Engine Sound.playMove is one Game Boy SFX bus: a new row either drops or
-- stops the last source. FIELD stacks voices and ducks whatever is still up.
Audio.DUCK = 0.55
Audio.MAX_VOICES = 8
Audio.VOICE_VOL = 0.80

local live = {}
local protoCache = {}

local function isPlaying(src)
  if not src then
    return false
  end
  local ok, playing = pcall(src.isPlaying, src)
  return ok and playing == true
end

function Audio.pruneVoices()
  local kept = {}
  for i = 1, #live do
    local v = live[i]
    if v and isPlaying(v.src) then
      kept[#kept + 1] = v
    end
  end
  live = kept
  return #live
end

function Audio.voiceCount()
  return Audio.pruneVoices()
end

function Audio.clearVoices()
  for i = 1, #live do
    local src = live[i] and live[i].src
    if src and type(src.stop) == "function" then
      pcall(src.stop, src)
    end
  end
  live = {}
end

function Audio.duckVoices(factor)
  factor = tonumber(factor) or Audio.DUCK
  if factor > 1 then
    factor = 1
  elseif factor < 0 then
    factor = 0
  end
  Audio.pruneVoices()
  for i = 1, #live do
    local v = live[i]
    v.vol = (tonumber(v.vol) or Audio.VOICE_VOL) * factor
    if v.src and type(v.src.setVolume) == "function" then
      pcall(v.src.setVolume, v.src, v.vol)
    end
  end
  return #live
end

function Audio.pushVoice(src, vol)
  if not src then
    return false
  end
  Audio.duckVoices(Audio.DUCK)
  live[#live + 1] = { src = src, vol = tonumber(vol) or Audio.VOICE_VOL }
  while #live > Audio.MAX_VOICES do
    local old = table.remove(live, 1)
    if old and old.src and type(old.src.stop) == "function" then
      pcall(old.src.stop, old.src)
    end
  end
  return true
end

local function cloneVoice(src)
  if not src then
    return nil
  end
  if type(src.clone) == "function" then
    local ok, voice = pcall(src.clone, src)
    if ok and voice then
      if type(src.stop) == "function" then
        pcall(src.stop, src)
      end
      if type(voice.setVolume) == "function" then
        pcall(voice.setVolume, voice, Audio.VOICE_VOL)
      end
      if type(voice.play) == "function" then
        pcall(voice.play, voice)
      end
      return voice
    end
  end
  return src
end

local function startChipVoice(data, name, pitch, tempo, def)
  local ChipAudio = tryRequire("src.core.ChipAudio")
  if not (ChipAudio and type(ChipAudio.newSfx) == "function") then
    return nil
  end
  if type(def) ~= "table" or not (def.chip or def.address) then
    return nil
  end
  local key = ("%s@%02x%02x"):format(name, pitch or 0, tempo or 0x80)
  local proto = protoCache[key]
  if proto == false then
    return nil
  end
  if not proto then
    local ok, src = pcall(ChipAudio.newSfx, data, name, pitch, tempo, def)
    if not (ok and src) then
      protoCache[key] = false
      return nil
    end
    protoCache[key] = src
    proto = src
  end
  if type(proto.clone) == "function" then
    local ok, voice = pcall(proto.clone, proto)
    if ok and voice then
      if type(voice.setVolume) == "function" then
        pcall(voice.setVolume, voice, Audio.VOICE_VOL)
      end
      if type(voice.play) == "function" then
        pcall(voice.play, voice)
      end
      return voice
    end
  end
  if type(proto.play) == "function" then
    pcall(proto.play, proto)
  end
  return proto
end

local function startStereoVoice(data, anim)
  local Sound = tryRequire("src.core.Sound")
  local playStereo = Sound and Sound.playStereo
  if type(playStereo) ~= "function" or not (anim and anim.sound) then
    return nil
  end
  local name = anim.sound
  local pitch = anim.pitch or 0
  local tempo = anim.tempo or 0x80
  local sfx = data and data.audio and data.audio.sfx
  local variant = ("%s@%02x%02x"):format(name, pitch, tempo)
  local key = (sfx and sfx[variant]) and variant or name
  local src = playStereo(data, key)
  return cloneVoice(src)
end

local function startVoice(data, anim)
  if not (anim and anim.sound) then
    return nil
  end
  local name = anim.sound
  local pitch = anim.pitch or 0
  local tempo = anim.tempo or 0x80
  local sfx = data and data.audio and data.audio.sfx
  local def = sfx and sfx[name]
  local src = startChipVoice(data, name, pitch, tempo, def)
  if src then
    return src
  end
  src = startStereoVoice(data, anim)
  if src then
    return src
  end
  local Sound = tryRequire("src.core.Sound")
  local fn = Audio._origPlayMove
      or (Sound and Sound._arFieldOrigPlayMove)
      or (Sound and Sound.playMove)
  if type(fn) == "function" then
    pcall(fn, data, anim)
  end
  return nil
end

local function fieldPlayMove(data, anim)
  local src = startVoice(data, anim)
  if src then
    return Audio.pushVoice(src, Audio.VOICE_VOL)
  end
  -- Headless / missing assets: still report the attempt so cues keep going.
  return false
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

  -- Hits also arm shakeProg / waitFrames / blink. Those drive drawClassic's
  -- SGB canvas + PaletteFX shader over the live voxel world and abort Love.
  local okBS, BattleState = pcall(require, "src.battle.BattleState")
  if okBS and BattleState and type(BattleState.applyHitFx) == "function"
      and not BattleState._arFieldMuteHitFx then
    local origHitFx = BattleState.applyHitFx
    function BattleState.applyHitFx(self, hit)
      if self and (self._arAnimeField or self._arFieldCombat) then
        return
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
  if Audio._Log and type(Audio._Log.note) == "function" then
    pcall(Audio._Log.note, battle, "audio.playMove", moveId,
      attackerIsPlayer and "you" or "foe")
  end
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
      local ok, src = pcall(Sound.playMoveCry, battle.data, species, tempo)
      if ok then
        src = cloneVoice(src) or src
        if src then
          Audio.pushVoice(src, Audio.VOICE_VOL)
        end
        Audio._lastMovePlayed = true
        return true
      end
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
  if Audio._Log and type(Audio._Log.note) == "function" then
    pcall(Audio._Log.note, battle, "audio.playHit", typeMult,
      opts and opts.category)
  end
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
