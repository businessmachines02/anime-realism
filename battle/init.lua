-- Battle systems — traditional battle layer
--
-- Reactive Defense (Focus) math + REACT pipeline (menus, momentum,
-- EffectRegistry wrap). Speech bubbles and trainer banter still live
-- in main.lua until the next extract. FIELD presentation is
-- field_battle/; this package is the fight systems on top of BattleState.
--
--   immersion/     → HP/EXP hide + rewards
--   battle/        → this package
--   field_battle/  → overworld viewer

return function(env)
    local loadFile = env and env.load
    local mod = env and env.mod

    local Battle = {
        id = "battle",
        title = "Battle systems",
    }

    Battle.OPTION_KEYS = {
        "momentum_counter",
        "callout_pick",
        "focus_bar",
        "dev_overlay",
    }

    local ReactiveDefense
    local React
    if type(loadFile) == "function" then
        local ok, value = pcall(loadFile, "reactive_defense.lua")
        if ok and type(value) == "table" then
            ReactiveDefense = value
        else
            print("[anime_realism] battle/reactive_defense: " .. tostring(value))
        end
        ok, value = pcall(loadFile, "react.lua")
        if ok and type(value) == "table" then
            React = value
        else
            print("[anime_realism] battle/react: " .. tostring(value))
        end
    end
    Battle.ReactiveDefense = ReactiveDefense
    Battle.React = React

    function Battle.ownsOption(key)
        for i = 1, #Battle.OPTION_KEYS do
            if Battle.OPTION_KEYS[i] == key then
                return true
            end
        end
        return false
    end

    -- Engine wraps (EffectRegistry) are installed from main after host
    -- presentation callbacks exist. See React.bind / React.install.
    function Battle.install(_mod)
        return true
    end

    return Battle
end
