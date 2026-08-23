-- Battle systems — per-side mood + heat (issue #74).
--
-- Derive a readable face from HP and fight events. chrome/portraits.lua
-- paints the PMD portrait. modifiers() feeds damage / accuracy / dodge.

local Emotions = {}

local byBattle = setmetatable({}, { __mode = "k" })

Emotions.LOW_HP = 0.20
Emotions.HEAVY_HIT = 0.25
Emotions.LEAD_MARGIN = 0.12
Emotions.FLASH_TURNS = 1
Emotions.ANGRY_CRIT_TURNS = 2

Emotions.FILE = {
    normal = "Normal",
    pain = "Pain",
    determined = "Determined",
    worried = "Worried",
    angry = "Angry",
    stunned = "Stunned",
    surprised = "Surprised",
    sigh = "Sigh",
}

-- Face stays up while the mood is not normal, then fades out.
Emotions.PORTRAIT_FADE = 0.45

-- Short chip labels + fills. Ink is dark on bright chips, light on deep ones.
Emotions.CHIP = {
    angry = { text = "ANGRY", fill = { 0.82, 0.22, 0.16 }, ink = { 1.00, 0.96, 0.94 } },
    pain = { text = "TIRED", fill = { 0.56, 0.34, 0.40 }, ink = { 1.00, 0.94, 0.94 } },
    determined = { text = "DTRMD", fill = { 0.90, 0.70, 0.16 }, ink = { 0.16, 0.10, 0.04 } },
    worried = { text = "WARY", fill = { 0.86, 0.78, 0.30 }, ink = { 0.18, 0.14, 0.04 } },
    stunned = { text = "STUN", fill = { 0.70, 0.66, 0.88 }, ink = { 0.12, 0.10, 0.22 } },
    sigh = { text = "SIGH", fill = { 0.60, 0.66, 0.72 }, ink = { 0.10, 0.12, 0.16 } },
    surprised = { text = "WOW", fill = { 0.96, 0.84, 0.22 }, ink = { 0.16, 0.12, 0.04 } },
}

local host = {}

function Emotions.bind(h)
    if type(h) == "table" then
        host = h
    end
    return Emotions
end

local function freshSide()
    return {
        mood = "normal",
        flash = nil,
        misses = 0,
        critsTaken = 0,
        angryTurns = 0,
        hitsLanded = 0,
        lastHeavy = false,
        announced = nil,
        lastShown = nil,
        portraitAt = nil,
        portraitMood = nil,
        fadeAt = nil,
        hp = nil,
        maxHp = nil,
    }
end

local function now()
    if love and love.timer and type(love.timer.getTime) == "function" then
        return love.timer.getTime()
    end
    return os.clock()
end

local function clamp01(n)
    n = tonumber(n)
    if not n then
        return nil
    end
    if n < 0 then
        return 0
    end
    if n > 1 then
        return 1
    end
    return n
end

local function hpOf(battler)
    local mon = battler and battler.mon
    local maxHP = tonumber(mon and mon.stats and mon.stats.hp)
    local hp = tonumber(mon and mon.hp)
    if hp == nil then
        hp = tonumber(battler and battler.shownHP)
    end
    return hp, maxHP
end

local function hpRatio(hp, maxHP)
    if not hp or not maxHP or maxHP <= 0 then
        return nil
    end
    return clamp01(hp / maxHP)
end

local function lowHpCut()
    local fn = host.lowHpRatio
    if type(fn) == "function" then
        local n = tonumber(fn())
        if n and n > 0 and n < 1 then
            return n
        end
    end
    return Emotions.LOW_HP
end

function Emotions.clear(battle)
    if battle then
        byBattle[battle] = nil
    end
end

function Emotions.state(battle)
    if type(battle) ~= "table" then
        return nil
    end
    local st = byBattle[battle]
    if not st then
        st = {
            player = freshSide(),
            enemy = freshSide(),
        }
        byBattle[battle] = st
    end
    if not st.player then
        st.player = freshSide()
    end
    if not st.enemy then
        st.enemy = freshSide()
    end
    return st
end

function Emotions.peek(battle)
    return battle and byBattle[battle] or nil
end

function Emotions.side(battle, isPlayer)
    local st = Emotions.state(battle)
    if not st then
        return nil
    end
    if isPlayer == true or isPlayer == "player" then
        return st.player
    end
    return st.enemy
end

function Emotions.resetSide(battle, isPlayer)
    local st = Emotions.state(battle)
    if not st then
        return
    end
    if isPlayer == true or isPlayer == "player" then
        st.player = freshSide()
    else
        st.enemy = freshSide()
    end
    Emotions.refresh(battle)
end

function Emotions.fileName(mood)
    return Emotions.FILE[tostring(mood or "")] or "Normal"
end

function Emotions.chip(mood)
    return Emotions.CHIP[tostring(mood or "")]
end

function Emotions.color(mood)
    local chip = Emotions.chip(mood)
    return chip and chip.fill or nil
end

-- Additive / small multiplicative heat. Caps keep this under the growth-layer
-- +15% ceiling in OVERVIEW.md.
Emotions.HEAT = {
    angry = { powerMul = 1.12, takenMul = 1.08, accuracy = -0.08, dodge = -0.05 },
    pain = { powerMul = 0.94, takenMul = 1.06, accuracy = -0.06, dodge = -0.08 },
    determined = { powerMul = 1.06, takenMul = 1.00, accuracy = 0.08, dodge = 0.04 },
    worried = { powerMul = 0.96, takenMul = 1.00, accuracy = 0.00, dodge = 0.08 },
    stunned = { powerMul = 0.92, takenMul = 1.10, accuracy = -0.10, dodge = -0.10 },
    sigh = { powerMul = 1.00, takenMul = 1.00, accuracy = -0.04, dodge = 0.00 },
    surprised = { powerMul = 1.00, takenMul = 1.06, accuracy = 0.00, dodge = -0.04 },
}

local function emptyMods()
    return { powerMul = 1, takenMul = 1, accuracy = 0, dodge = 0 }
end

local function heatOn()
    local fn = host.facesOn
    if type(fn) == "function" then
        return fn() ~= false
    end
    return true
end

function Emotions.modifiers(battle, isPlayer)
    if not heatOn() then
        return emptyMods()
    end
    local mood = Emotions.mood(battle, isPlayer)
    local spec = Emotions.HEAT[tostring(mood or "")]
    if not spec then
        return emptyMods()
    end
    return {
        powerMul = spec.powerMul or 1,
        takenMul = spec.takenMul or 1,
        accuracy = spec.accuracy or 0,
        dodge = spec.dodge or 0,
    }
end

function Emotions.applyDamage(battle, user, target, dmg)
    if type(dmg) ~= "number" or dmg <= 0 then
        return dmg
    end
    local out = 1
    local taken = 1
    if user then
        local m = Emotions.modifiers(battle, user.isPlayer == true)
        out = tonumber(m.powerMul) or 1
    end
    if target then
        local m = Emotions.modifiers(battle, target.isPlayer == true)
        taken = tonumber(m.takenMul) or 1
    end
    local mul = out * taken
    if mul > 1.25 then
        mul = 1.25
    elseif mul < 0.80 then
        mul = 0.80
    end
    if mul == 1 then
        return dmg
    end
    return math.max(1, math.floor(dmg * mul + 0.5))
end

function Emotions.nudgeHit(battle, user, hit)
    if not user then
        return hit
    end
    local m = Emotions.modifiers(battle, user.isPlayer == true)
    local acc = tonumber(m.accuracy) or 0
    if acc == 0 then
        return hit
    end
    local roll
    if love and love.math and type(love.math.random) == "function" then
        roll = love.math.random()
    else
        roll = math.random()
    end
    if hit and acc < 0 and roll < -acc then
        return false
    end
    if (not hit) and acc > 0 and roll < acc then
        return true
    end
    return hit
end

function Emotions.attachDefense(RD)
    if type(RD) ~= "table" then
        return Emotions
    end
    function RD.emotionDodgeBonus(defender, _attacker, battle)
        if not battle then
            return 0
        end
        local m = Emotions.modifiers(battle, defender and defender.isPlayer == true)
        return tonumber(m.dodge) or 0
    end
    return Emotions
end

local function derive(side, selfRatio, foeRatio)
    if selfRatio and selfRatio <= lowHpCut() then
        return "pain"
    end
    if (side.misses or 0) >= 2 or (side.angryTurns or 0) > 0 then
        return "angry"
    end
    if side.lastHeavy then
        return "worried"
    end
    if selfRatio and foeRatio and (foeRatio - selfRatio) >= Emotions.LEAD_MARGIN then
        return "worried"
    end
    if selfRatio and foeRatio
        and (selfRatio - foeRatio) >= Emotions.LEAD_MARGIN
        and (side.hitsLanded or 0) > 0 then
        return "determined"
    end
    return "normal"
end

function Emotions.refresh(battle)
    local st = Emotions.state(battle)
    if not st then
        return nil
    end
    local php, pmax = hpOf(battle.player)
    local ehp, emax = hpOf(battle.enemy)
    local pr, er = hpRatio(php, pmax), hpRatio(ehp, emax)
    st.player.hp, st.player.maxHp = php, pmax
    st.enemy.hp, st.enemy.maxHp = ehp, emax
    st.player.mood = derive(st.player, pr, er)
    st.enemy.mood = derive(st.enemy, er, pr)
    return st
end

function Emotions.mood(battle, isPlayer)
    local side = Emotions.side(battle, isPlayer)
    if not side then
        return "normal"
    end
    if side.flash and side.flash.mood then
        return side.flash.mood
    end
    return side.mood or "normal"
end

local function resolveWho(st, battle, who)
    if who == true or who == "player" then
        return st.player, true
    end
    if who == false or who == "enemy" then
        return st.enemy, false
    end
    if type(who) == "table" then
        if who.isPlayer or who == (battle and battle.player) then
            return st.player, true
        end
        return st.enemy, false
    end
    return nil, nil
end

local function tickSide(side)
    if not side then
        return
    end
    if side.flash then
        side.flash.turns = (tonumber(side.flash.turns) or 1) - 1
        if side.flash.turns <= 0 then
            side.flash = nil
        end
    end
    if (side.angryTurns or 0) > 0 then
        side.angryTurns = side.angryTurns - 1
    end
    if (side.hitsLanded or 0) > 0 then
        side.hitsLanded = side.hitsLanded - 1
    end
    side.lastHeavy = false
end

function Emotions.note(battle, ev)
    if type(battle) ~= "table" or type(ev) ~= "table" then
        return nil
    end
    local st = Emotions.state(battle)
    local kind = tostring(ev.kind or ev.type or "")

    if kind == "miss" then
        local side = resolveWho(st, battle, ev.side or ev.user)
        if side then
            side.misses = (side.misses or 0) + 1
            side.flash = { mood = "sigh", turns = Emotions.FLASH_TURNS }
        end
    elseif kind == "crit" then
        local victim = resolveWho(st, battle, ev.side or ev.target)
        if victim and not (victim.flash and victim.flash.mood == "stunned") then
            victim.critsTaken = (victim.critsTaken or 0) + 1
            victim.angryTurns = Emotions.ANGRY_CRIT_TURNS
            victim.flash = { mood = "stunned", turns = Emotions.FLASH_TURNS }
        end
        local attacker = resolveWho(st, battle, ev.user)
        if attacker and attacker ~= victim then
            attacker.hitsLanded = (attacker.hitsLanded or 0) + 1
        end
        if ev.foeSurprised then
            local other = victim == st.player and st.enemy or st.player
            if other then
                other.flash = { mood = "surprised", turns = Emotions.FLASH_TURNS }
            end
        end
    elseif kind == "hit" then
        local attacker = resolveWho(st, battle, ev.user or ev.side)
        local target = resolveWho(st, battle, ev.target)
        if attacker then
            attacker.hitsLanded = (attacker.hitsLanded or 0) + 1
        end
        local dmg = tonumber(ev.damage)
        local maxHP = tonumber(ev.maxHp or ev.maxHP)
        if not maxHP and target then
            maxHP = target.maxHp
        end
        if target and dmg and maxHP and maxHP > 0
            and (dmg / maxHP) >= Emotions.HEAVY_HIT then
            target.lastHeavy = true
        end
    elseif kind == "faint" or kind == "switch" then
        local _, isPlayer = resolveWho(st, battle, ev.side or ev.battler)
        if isPlayer == true then
            st.player = freshSide()
        elseif isPlayer == false then
            st.enemy = freshSide()
        end
    elseif kind == "turn" or kind == "turn_ended" or kind == "end_turn" then
        tickSide(st.player)
        tickSide(st.enemy)
    end

    Emotions.refresh(battle)
    return st
end

function Emotions.consumeChange(battle, isPlayer)
    local side = Emotions.side(battle, isPlayer)
    if not side then
        return nil
    end
    local shown = Emotions.mood(battle, isPlayer)
    if shown == side.lastShown then
        return nil
    end
    local prev = side.lastShown
    side.lastShown = shown
    if shown == "normal" then
        if prev and prev ~= "normal" and not side.fadeAt then
            side.fadeAt = now()
        end
        return nil
    end
    side.fadeAt = nil
    side.portraitAt = now()
    side.portraitMood = shown
    return shown
end

function Emotions.consumeAnnounce(battle, isPlayer)
    return Emotions.consumeChange(battle, isPlayer)
end

function Emotions.portraitAlpha(battle, isPlayer)
    local side = Emotions.side(battle, isPlayer)
    if not side then
        return 0
    end
    local shown = Emotions.mood(battle, isPlayer)
    if shown and shown ~= "normal" then
        side.fadeAt = nil
        side.portraitMood = shown
        return 1
    end
    if not side.fadeAt then
        if side.portraitMood then
            side.fadeAt = now()
        else
            return 0
        end
    end
    local fade = (now() - side.fadeAt) / (Emotions.PORTRAIT_FADE or 0.45)
    if fade >= 1 then
        side.fadeAt = nil
        side.portraitMood = nil
        return 0
    end
    if fade < 0 then
        return 1
    end
    return 1 - fade
end

function Emotions.portraitMood(battle, isPlayer)
    local shown = Emotions.mood(battle, isPlayer)
    if shown and shown ~= "normal" then
        return shown
    end
    local side = Emotions.side(battle, isPlayer)
    if not side then
        return nil
    end
    if Emotions.portraitAlpha(battle, isPlayer) <= 0 then
        return nil
    end
    return side.portraitMood
end

function Emotions.announce(battle)
    if type(battle) ~= "table" then
        return
    end
    local on = host.facesOn
    if type(on) == "function" and on() == false then
        return
    end
    Emotions.refresh(battle)
    for _, isPlayer in ipairs({ true, false }) do
        Emotions.consumeChange(battle, isPlayer)
    end
end

function Emotions.install(_mod)
    return true
end

return Emotions
