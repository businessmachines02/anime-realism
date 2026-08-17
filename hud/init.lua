-- HUD — HP / EXP / numbers feel
--
-- Hides levels and HP, XP bar, generic level-up / EXP lines, low-HP warnings,
-- underdog EXP, and faint effort consolations so fights play by feel.
--
-- HUD hide (levels/HP/XP) lives in hide.lua; speech-bubble paint lives in
-- battle/dialogue.lua. Rewards (underdog EXP + effort faint) install here.
--   hud/     → numbers feel (this package)
--   battle/  → REACT rules, menus, FX policy, dialogue paint
--   field/   → overworld FIELD viewer

return function(env)
  local loadFile = env and env.load

  local Hud = {
    id = "hud",
    title = "HUD (HP / EXP hide + rewards)",
  }

  -- HUD feel is always on (no menu toggles). Keys below are the baked-in feel.
  Hud.OPTION_KEYS = {}

  local Rewards
  local Hide
  if type(loadFile) == "function" then
    local ok, value = pcall(loadFile, "rewards.lua")
    if ok and type(value) == "table" then
      Rewards = value
    else
      print("[anime_realism] hud/rewards: " .. tostring(value))
    end
    ok, value = pcall(loadFile, "hide.lua")
    if ok and type(value) == "table" then
      Hide = value
    else
      print("[anime_realism] hud/hide: " .. tostring(value))
    end
  end
  Hud.Rewards = Rewards
  Hud.Hide = Hide

  function Hud.ownsOption(key)
    for i = 1, #Hud.OPTION_KEYS do
      if Hud.OPTION_KEYS[i] == key then
        return true
      end
    end
    return false
  end

  function Hud.install(mod)
    if Rewards and type(Rewards.install) == "function" then
      Rewards.install(mod)
    end
    return true
  end

  return Hud
end
