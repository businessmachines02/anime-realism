-- HUD rewards — underdog EXP and effort-faint consolations.
-- Installed from Hud.install. Always-on (legacy option keys still honor
-- an explicit false if a save still has them).

local Rewards = {}

local EFFORT_LINES = {
    "%s grew\nfrom the effort!",
    "%s learned\nfrom that fight!",
    "Hard fight-\n%s grew a bit!",
    "%s's effort\nwasn't wasted!",
}

local function pickLine(lines)
    if type(lines) ~= "table" or #lines == 0 then
        return nil
    end
    local r = (love and love.math and love.math.random) or math.random
    return lines[r(#lines)]
end

local function on(mod, key)
    if not (mod and mod.options and type(mod.options.get) == "function") then
        return true
    end
    return mod.options:get(key) ~= false
end

local function performedWell(rec, enemy)
    if not rec or (rec.damage or 0) <= 0 then
        return false
    end
    local maxHp = enemy and enemy.mon and enemy.mon.stats and enemy.mon.stats.hp
    maxHp = tonumber(maxHp) or 0
    if maxHp > 0 and rec.damage >= math.max(1, math.floor(maxHp * 0.25)) then
        return true
    end
    return (rec.moves or 0) >= 2 and rec.damage >= 5
end

function Rewards.install(mod)
    if not mod or mod._arImmersionRewards then
        return true
    end
    mod._arImmersionRewards = true

    local effortByBattle = setmetatable({}, { __mode = "k" })
    local Stats = require("src.pokemon.Stats")

    local function effortState(battle)
        local state = effortByBattle[battle]
        if not state then
            state = { mons = {} }
            effortByBattle[battle] = state
        end
        return state
    end

    local function effortRec(battle, mon)
        if not battle or not mon then
            return nil
        end
        local state = effortState(battle)
        local rec = state.mons[mon]
        if not rec then
            rec = { damage = 0, moves = 0, fainted = false, effortPaid = false }
            state.mons[mon] = rec
        end
        return rec
    end

    local function awardEffortConsolation(battle, mon, foeDef)
        if not mon or not foeDef or type(foeDef.baseStats) ~= "table" then
            return false
        end
        if type(mon.statExp) ~= "table" then
            mon.statExp = {}
        end
        local order = Stats.ORDER or { "hp", "attack", "defense", "speed", "special" }
        local any = false
        for i = 1, #order do
            local key = order[i]
            local base = tonumber(foeDef.baseStats[key]) or 0
            -- About 1/5 of a normal undivided base-stat yield (capped effort).
            local gain = math.max(1, math.floor(base / 5))
            local before = mon.statExp[key] or 0
            mon.statExp[key] = math.min(65535, before + gain)
            if mon.statExp[key] > before then
                any = true
            end
        end
        -- Tiny EXP crumb so the fight still "counts" without a full share.
        if any then
            local crumb = math.max(1, math.min(8, math.floor((foeDef.baseExp or 16) / 8)))
            mon.exp = (mon.exp or 0) + crumb
        end
        if not any or not battle or type(battle.sayNext) ~= "function" then
            return any
        end
        local name = mon.nickname
        if not name or name == "" then
            local def = battle.data and battle.data.pokemon and battle.data.pokemon[mon.species]
            name = def and def.name or "POKéMON"
        end
        local line = pickLine(EFFORT_LINES) or "%s grew\nfrom the effort!"
        battle:sayNext(line:format(name))
        return true
    end

    -- Much-weaker KO → bonus EXP (exp.gain runs per receiving mon).
    mod.hooks:wrap("exp.gain", function(next, ctx)
        local exp = next(ctx)
        if not on(mod, "underdog_exp") or type(exp) ~= "number" then
            return exp
        end
        local mon = ctx and ctx.mon
        local foeLv = ctx and ctx.level
        if not mon or not foeLv or (mon.hp or 0) <= 0 then
            return exp
        end
        local gap = (tonumber(foeLv) or 0) - (tonumber(mon.level) or 0)
        local mult = 1
        if gap >= 8 then
            mult = 1.5
        elseif gap >= 4 then
            mult = 1.25
        else
            return exp
        end
        local boosted = math.max(1, math.floor(exp * mult))
        -- Cap: never more than +50% or +80 raw over the vanilla share.
        return math.min(boosted, math.floor(exp * 1.5), exp + 80)
    end)

    -- Fainted mons who fought well still get Gen 1 stat exp (effort).
    mod.hooks:wrap("battle.exp_award", function(next, ctx)
        next(ctx)
        if not on(mod, "effort_faint") or not ctx or not ctx.battle then
            return
        end
        local battle = ctx.battle
        local state = effortByBattle[battle]
        if not state or not state.mons then
            return
        end
        local foeDef = battle.enemy and battle.enemy.def
        if not foeDef then
            return
        end
        for mon, rec in pairs(state.mons) do
            if rec and rec.fainted and not rec.effortPaid
                and performedWell(rec, battle.enemy) then
                if awardEffortConsolation(battle, mon, foeDef) then
                    rec.effortPaid = true
                end
            end
        end
    end)

    mod.events:on("battle.started", function(ev)
        if ev and ev.battle then
            effortByBattle[ev.battle] = { mons = {} }
        end
    end)

    mod.events:on("battle.move_used", function(ev)
        if not ev or not ev.battle or not ev.user or not ev.user.isPlayer then
            return
        end
        local rec = effortRec(ev.battle, ev.user.mon)
        if rec then
            rec.moves = (rec.moves or 0) + 1
        end
    end)

    mod.events:on("battle.fainted", function(ev)
        if not ev or not ev.battle or not ev.battler or not ev.battler.isPlayer then
            return
        end
        local rec = effortRec(ev.battle, ev.battler.mon)
        if rec then
            rec.fainted = true
        end
    end)

    mod.events:on("battle.damage_dealt", function(ev)
        if not ev or not ev.battle then
            return
        end
        local user, target = ev.user, ev.target
        if user and user.isPlayer and target and not target.isPlayer
            and (ev.damage or 0) > 0 then
            local rec = effortRec(ev.battle, user.mon)
            if rec then
                rec.damage = (rec.damage or 0) + (ev.damage or 0)
            end
        end
    end)

    return true
end

return Rewards
