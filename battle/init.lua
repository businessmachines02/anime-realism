-- Battle systems — traditional battle layer
--
-- Reactive Defense (Focus), anime move callouts, speech bubbles, trainer
-- banter, status/focus chips. Works on CLASSIC battles and under FIELD for
-- menus/logic. Presentation of FIELD itself is field_battle/; this package
-- is the fight systems on top of BattleState.
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
        "dev_overlay",
    }

    local ReactiveDefense
    if type(loadFile) == "function" then
        local ok, value = pcall(loadFile, "reactive_defense.lua")
        if ok and type(value) == "table" then
            ReactiveDefense = value
        else
            print("[anime_realism] battle/reactive_defense: " .. tostring(value))
        end
    end
    Battle.ReactiveDefense = ReactiveDefense

    function Battle.ownsOption(key)
        for i = 1, #Battle.OPTION_KEYS do
            if Battle.OPTION_KEYS[i] == key then
                return true
            end
        end
        return false
    end

    function Battle.install(_mod)
        return true
    end

    return Battle
end
