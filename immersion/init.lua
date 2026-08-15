-- Immersion — HP / EXP / numbers feel
--
-- Hides levels and HP, XP bar, generic level-up / EXP lines, low-HP warnings,
-- underdog EXP, and faint effort consolations so fights play by feel.
--
-- Runtime hooks still live in main.lua for now (LuaJIT local budget + shared
-- HUD patch table). This package owns the option keys and public labels so the
-- three pillars stay clear:
--   immersion/     → numbers feel (this package)
--   battle/        → traditional battle systems (Reactive Defense, callouts…)
--   field_battle/  → overworld battle viewer

return function(env)
  local Immersion = {
    id = "immersion",
    title = "Immersion (HP / EXP)",
  }

  -- Immersion is always on (no menu toggles). Keys below are the baked-in feel.
  Immersion.OPTION_KEYS = {}

  function Immersion.ownsOption(key)
    for i = 1, #Immersion.OPTION_KEYS do
      if Immersion.OPTION_KEYS[i] == key then
        return true
      end
    end
    return false
  end

  -- Reserved for extracted install hooks as immersion code moves out of main.
  function Immersion.install(_mod)
    return true
  end

  return Immersion
end
