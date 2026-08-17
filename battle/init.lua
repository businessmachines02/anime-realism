-- Battle systems — traditional battle layer
--
-- Reactive Defense (Focus) math + REACT pipeline + animation policy +
-- dialogue (strings, callout rewrite, say wraps, banter cameo, bubbles).
--   hud/     → hide numbers + rewards
--   battle/  → this package
--   field/   → overworld viewer (pad cues, projectiles, compact HUD)

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
    local Fx
    local Dialogue
    local Strings
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
        ok, value = pcall(loadFile, "fx.lua")
        if ok and type(value) == "table" then
            Fx = value
        else
            print("[anime_realism] battle/fx: " .. tostring(value))
        end
        ok, value = pcall(loadFile, "strings.lua")
        if ok and type(value) == "table" then
            Strings = value
        else
            print("[anime_realism] battle/strings: " .. tostring(value))
        end
        ok, value = pcall(loadFile, "dialogue.lua")
        if ok and type(value) == "table" then
            Dialogue = value
        else
            print("[anime_realism] battle/dialogue: " .. tostring(value))
        end
    end
    Battle.ReactiveDefense = ReactiveDefense
    Battle.React = React
    Battle.Fx = Fx
    Battle.Dialogue = Dialogue
    Battle.Strings = Strings

    function Battle.ownsOption(key)
        for i = 1, #Battle.OPTION_KEYS do
            if Battle.OPTION_KEYS[i] == key then
                return true
            end
        end
        return false
    end

    -- React.bind / Fx.bind / Dialogue.bind + React.install run from main
    -- after host presentation callbacks exist.
    function Battle.install(_mod)
        return true
    end

    return Battle
end
