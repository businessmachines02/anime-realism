-- Immersion — HP / EXP / numbers feel
--
-- Hides levels and HP, XP bar, generic level-up / EXP lines, low-HP warnings,
-- underdog EXP, and faint effort consolations so fights play by feel.
--
-- HUD hide still lives in main.lua (shared `hud` table with speech bubbles).
-- Rewards (underdog EXP + effort faint) install from this package.
--   immersion/     → numbers feel (this package)
--   battle/        → traditional battle systems (Reactive Defense, callouts…)
--   field_battle/  → overworld battle viewer

return function(env)
  local loadFile = env and env.load

  local Immersion = {
    id = "immersion",
    title = "Immersion (HP / EXP)",
  }

  -- Immersion is always on (no menu toggles). Keys below are the baked-in feel.
  Immersion.OPTION_KEYS = {}

  local Rewards
  if type(loadFile) == "function" then
    local ok, value = pcall(loadFile, "rewards.lua")
    if ok and type(value) == "table" then
      Rewards = value
    else
      print("[anime_realism] immersion/rewards: " .. tostring(value))
    end
  end
  Immersion.Rewards = Rewards

  function Immersion.ownsOption(key)
    for i = 1, #Immersion.OPTION_KEYS do
      if Immersion.OPTION_KEYS[i] == key then
        return true
      end
    end
    return false
  end

  function Immersion.install(mod)
    if Rewards and type(Rewards.install) == "function" then
      Rewards.install(mod)
    end
    return true
  end

  return Immersion
end
