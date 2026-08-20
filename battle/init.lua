-- Battle systems — traditional battle layer
--
--   rules/   → Focus math, REACT pipeline, foe AI, dialogue rewrite
--   chrome/  → pick HUD, speech bubbles, trainer cameo, notice stack
--   fx.lua   → classic vs FIELD animation policy
--   strings.lua → callout / banter copy
--
-- Sibling files load via env.load (zip-safe). Public surface stays
-- Battle.ReactiveDefense / FoeAi / React / Fx / Dialogue / Strings.

return function(env)
    local loadFile = env and env.load

    local Battle = {
        id = "battle",
        title = "Battle systems",
    }

    Battle.OPTION_KEYS = {
        "momentum_counter",
        "callout_pick",
        "react_hud",
        "focus_bar",
        "dev_overlay",
    }

    local function loadMod(name)
        if type(loadFile) ~= "function" then
            return nil
        end
        local ok, value = pcall(loadFile, name)
        if ok and type(value) == "table" then
            return value
        end
        print("[anime_realism] battle/" .. name .. ": " .. tostring(value))
        return nil
    end

    local ReactiveDefense = loadMod("rules/reactive_defense.lua")
    local FoeAi = loadMod("rules/foe_ai.lua")
    if FoeAi and ReactiveDefense and type(FoeAi.attach) == "function" then
        FoeAi.attach(ReactiveDefense)
    end
    local Pick = loadMod("chrome/pick.lua")
    local BubblesChrome = loadMod("chrome/bubbles.lua")
    local Notices = loadMod("chrome/notices.lua")
    local React = loadMod("rules/react.lua")
    local Fx = loadMod("fx.lua")
    local Strings = loadMod("strings.lua")
    local Dialogue = loadMod("rules/dialogue.lua")

    if React and type(React.attachHud) == "function" then
        React.attachHud(Pick)
    end
    if Dialogue and type(Dialogue.attachChrome) == "function" then
        Dialogue.attachChrome(BubblesChrome)
    end

    Battle.ReactiveDefense = ReactiveDefense
    Battle.FoeAi = FoeAi
    Battle.React = React
    Battle.Fx = Fx
    Battle.Dialogue = Dialogue
    Battle.Strings = Strings
    Battle.Notices = Notices

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
