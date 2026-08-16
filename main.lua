-- Anime Realism
--
-- Three packages (see folders):
--   immersion/     — HP / EXP / numbers feel (hide HUD, underdog EXP, effort)
--   battle/        — traditional battle systems (Reactive Defense, callouts,
--                    speech bubbles, banter, chips)
--   field_battle/  — standalone overworld FIELD combat (BattleState on stack,
--                    transparent over the live map)
--
-- main.lua is the orchestrator + remaining shared hooks (moving into packages
-- over time). lib/modload.lua loads folder packages for zip + loose installs.
--
--




return function(mod)
    local Immersion
    local Battle
    local FieldBattleViewer
    local ReactiveDefense

    local ModLoad
    do
        local src
        if type(mod.read) == "function" then
            local ok, body = pcall(function()
                return mod:read("lib/modload.lua")
            end)
            if ok then
                src = body
            end
        end
        if type(src) == "string" and src ~= "" then
            local chunk, err = load(src, "@lib/modload.lua")
            if chunk then
                local ok, factory = pcall(chunk)
                if ok and type(factory) == "function" then
                    local okM, ml = pcall(factory, mod)
                    if okM then
                        ModLoad = ml
                    else
                        print("[anime_realism] modload init: " .. tostring(ml))
                    end
                else
                    print("[anime_realism] modload compile: " .. tostring(err or factory))
                end
            end
        else
            print("[anime_realism] lib/modload.lua missing")
        end
    end

    if ModLoad and type(ModLoad.loadPackage) == "function" then
        local value, err = ModLoad.loadPackage("immersion")
        if type(value) == "table" then
            Immersion = value
            pcall(Immersion.install, mod)
        else
            print("[anime_realism] immersion: " .. tostring(err))
        end

        if ModLoad and type(ModLoad.loadPackage) == "function" then
            local value, err = ModLoad.loadPackage("immersion")
            if type(value) == "table" then
                Immersion = value
                pcall(Immersion.install, mod)
            else
                print("[anime_realism] immersion: " .. tostring(err))
            end

            value, err = ModLoad.loadPackage("battle")
            if type(value) == "table" then
                Battle = value
                ReactiveDefense = Battle.ReactiveDefense
                pcall(Battle.install, mod)
            else
                print("[anime_realism] battle: " .. tostring(err))
            end

            value, err = ModLoad.loadPackage("field_battle")
            if type(value) == "table" then
                FieldBattleViewer = value
                pcall(FieldBattleViewer.install, mod)
            else
                print("[anime_realism] field_battle: " .. tostring(err))
            end
        end

        -- Expose packages for debug / future extractions.
        mod._arPackages = {
            immersion = Immersion,
            battle = Battle,
            field_battle = FieldBattleViewer,
        }

        mod.options:define({
            {
                key = "battle_stage",
                type = "choice",
                label = "BATTLE STAGE",
                default = "FIELD",
                choices = {
                    { "FIELD", "FIELD" },
                    { "AUTO",  "AUTO" },
                },
            },
            {
                key = "field_sprites",
                type = "choice",
                label = "FIELD SPRITES",
                default = "AUTO",
                choices = {
                    { "AUTO",    "AUTO" },
                    { "GSC",     "GSC" },
                    { "HGSS",    "HGSS" },
                    { "POKEDEX", "POKEDEX" },
                },
            },
            {
                key = "momentum_counter",
                type = "toggle",
                label = "REACTIVE DEF",
                default = true,
            },
            {
                key = "callout_pick",
                type = "choice",
                label = "REACT MENU",
                default = "ALWAYS",
                choices = {
                    { "ALWAYS", "ALWAYS" },
                    { "THREAT", "THREAT" },
                    { "OFF",    "OFF" },
                },
            },
            {
                key = "dev_overlay",
                type = "toggle",
                label = "DEV OVERLAY",
                default = false,
            },
        })

        local function opt(key)
            return mod.options:get(key) ~= false
        end

        -- AUTO = leave other battle presentation mods alone.
        -- FIELD = anime map fight: flat overworld stays under the battle UI, trainers
        --         stay visible, OW Pokémon sprites stand between them. potato_voxel
        --         free-roam VOXEL keeps drawing; OverworldBattle staging is gated.
        -- Legacy CLASSIC / STADIUM saves map to AUTO.
        local function battleStage()
            local raw = tostring(mod.options:get("battle_stage") or "AUTO"):upper()
            if raw == "FIELD" then
                return "FIELD"
            end
            return "AUTO"
        end

        -- Dev overlay + sequence log (one table — keeps LuaJIT's 200-local budget).
        -- Filled further after momentumState exists.
        local dev = {
            linesMax = 12,
            byBattle = setmetatable({}, { __mode = "k" }),
            peek = nil,
            draw = nil,
        }
        function dev.on()
            return mod.options:get("dev_overlay") == true
        end

        function dev.bag(battle)
            if not battle then
                return nil
            end
            local log = dev.byBattle[battle]
            if not log then
                log = { seq = 0, lines = {} }
                dev.byBattle[battle] = log
            end
            return log
        end

        function dev.log(battle, tag, detail)
            if not dev.on() or not battle then
                return
            end
            local log = dev.bag(battle)
            log.seq = (log.seq or 0) + 1
            local turn = tonumber(battle.turnCount) or 0
            local msg = string.format("#%d T%d %s", log.seq, turn, tostring(tag or "?"))
            if detail and detail ~= "" then
                msg = msg .. " | " .. tostring(detail)
            end
            local lines = log.lines
            lines[#lines + 1] = msg
            while #lines > dev.linesMax do
                table.remove(lines, 1)
            end
        end

        local function calloutPickMode()
            local raw = mod.options:get("callout_pick")
            -- Migrate legacy toggle values.
            if raw == false then
                return "OFF"
            end
            if raw == true or raw == nil then
                return "THREAT"
            end
            local s = tostring(raw):upper()
            if s == "ALWAYS" or s == "OFF" or s == "THREAT" then
                return s
            end
            return "THREAT"
        end

        local function calloutStyle()
            local s = tostring(mod.options:get("callout_style") or "AUTO"):upper()
            if s == "BOLD" or s == "TRICKY" or s == "SHOWY" then
                return s
            end
            return "AUTO"
        end

        local function hideAllHud()
            return opt("hide_battle_hud")
        end

        -- Levels and HP are always hidden everywhere.
        local function hideLevelsNow()
            return true
        end

        local function hideHpNow()
            return true
        end

        local function lowHpRatio()
            local choice = tostring(mod.options:get("low_hp_threshold") or "20")
            if choice == "40" then
                return 0.40
            end
            return 0.20
        end

        local S = {}
        S.PLAYER_LOW = {
            "Your POKéMON is\nlooking weak!",
            "Your POKéMON is\nlooking tired!",
            "Your POKéMON looks\nweak...",
            "Your POKéMON looks\ntired...",
        }
        S.ENEMY_LOW = {
            "The enemy POKéMON\nis looking weak!",
            "The enemy POKéMON\nis looking tired!",
            "The foe's POKéMON\nlooks weak!",
            "The foe's POKéMON\nlooks tired...",
        }

        -- Short party-list lines (fit the old HP row).
        S.PARTY_HINTS = {
            "WK-HEAL!",
            "TRD-HEAL!",
            "WK!",
            "TRD!",
            "HEAL!",
        }

        local function pickLine(lines)
            local n = #lines
            if n == 0 then
                return nil
            end
            local r = (love and love.math and love.math.random) or math.random
            return lines[r(n)]
        end

        -- Stable per-mon hint so the line does not flicker every frame.
        local partyHintFor = setmetatable({}, { __mode = "k" })

        local function partyRowHint(mon)
            if not mon or not mon.stats or not mon.stats.hp or mon.stats.hp <= 0 then
                return nil
            end
            local hp = mon.hp or 0
            if hp <= 0 then
                return "FAINTED-HEAL!"
            end
            local ratio = hp / mon.stats.hp
            local needs = (ratio <= lowHpRatio()) or mon.status or (ratio < 1)
            if not needs then
                partyHintFor[mon] = nil
                return nil
            end
            local hint = partyHintFor[mon]
            if not hint then
                hint = pickLine(S.PARTY_HINTS)
                partyHintFor[mon] = hint
            end
            return hint
        end

        -- Per-battle: warn once per side until healed above the threshold or switched.
        local lowWarned = setmetatable({}, { __mode = "k" })

        local function sideKey(battler)
            if not battler then
                return nil
            end
            if battler.isPlayer then
                return "player"
            end
            return "enemy"
        end

        local function checkLowHp(battle, battler)
            if not opt("low_hp_warn") or not battle or not battler or not battler.mon then
                return
            end
            local mon = battler.mon
            local max = mon.stats and mon.stats.hp
            local hp = mon.hp or 0
            local side = sideKey(battler)
            if not side or not max or max <= 0 then
                return
            end

            local state = lowWarned[battle]
            if not state then
                state = { player = false, enemy = false }
                lowWarned[battle] = state
            end

            if hp <= 0 or (hp / max) > lowHpRatio() then
                state[side] = false
                return
            end
            if state[side] then
                return
            end
            state[side] = true

            local text = pickLine(side == "player" and S.PLAYER_LOW or S.ENEMY_LOW)
            if not text then
                return
            end
            if type(battle.sayNext) == "function" then
                battle:sayNext(text)
            elseif type(battle.say) == "function" then
                battle:say(text)
            end
        end

        -- Official seam for the looping low-health siren (see Reference: Hooks).
        mod.hooks:wrap("battle.low_health_alarm", function(next, ctx)
            if opt("mute_low_hp_alarm") and ctx then
                ctx.on = false
            end
            return next(ctx)
        end)

        -- Momentum: foe → player.
        -- Physical hit → arms counter; on your reply you pick COUNTER or HOLD.
        -- Special → dodge callout (may fail); temp buffs clear when you attack.
        local Damage = require("src.battle.Damage")
        local momentumByBattle = setmetatable({}, { __mode = "k" })
        -- Forward decls: event handlers / pick menu close over these.
        local revealPlayerPic
        local enqueueDodgeHideAnim
        local enqueueBraceAnim
        local applyCalloutBuffs
        local clearCalloutPickState
        local resolvePendingDamage
        local announceCoverHit
        local rewriteDodgeMissText
        local tagFieldCue
        local tagLatestQueueFieldCue
        local fieldCueForFoeCover
        local maybeEnqueueIdleBanter
        local playerHoldingHide
        local playerCanStay
        local playerInDeepCover
        local rememberCoverSpot
        local ensurePlayerPicHidden
        local rollDeepCoverLock
        local pickDeepCoverLine
        local maybeQueueSameTurnCounter
        local clearAmbientStance
        local tickAmbientStance
        local publishChipState

        local function freshMomentum()
            return {
                mode = nil,
                boosted = false,
                enemyActedThisTurn = false,
                playerActedThisTurn = false,
                pickOfferedThisTurn = false,
                awaitingPick = nil,
                pendingDamage = nil,
                -- Committed STATUS CHIP lines (updated only after callouts settle).
                chipYou = nil,
                chipFoe = nil,
                chipPulseYou = 0,
                chipPulseFoe = 0,
                -- Temporary cover buffs from dodge/brace; cleared on your attack.
                -- entrenched: strong brace — near-max DEF while you wait to counter;
                -- foe can rarely "break through" and strip it before damage.
                -- entrenchTurns: STAY count while locked in (max S.ENTRENCH_MAX_TURNS).
                temp = {
                    evasion = 0,
                    defense = 0,
                    cover = false,
                    picHidden = false,
                    entrenched = false,
                    entrenchTurns = 0,
                    -- Hid/flew to a spot (not a plain sidestep) — STAY allowed.
                    hidAway = false,
                    -- ROCK / TREE / DIVE / FLY UP / … — flavors deep-cover locks.
                    coverSpot = nil,
                    -- This turn: stuck deep in cover (no STRIKE, no dodge/brace callout).
                    deepCover = false,
                    deepCoverRolled = false,
                    -- Set only on a successful dodge this swing (gates same-turn COUNTER!).
                    dodgedOk = false,
                },
                -- Trainer-foe mirror: temp buffs clear when the foe attacks.
                enemyTemp = { evasion = 0, defense = 0, cover = false },
                enemyMode = nil,
                enemyBoosted = false,
                enemyReactedThisTurn = false,
            }
        end

        local function momentumState(battle)
            local state = momentumByBattle[battle]
            if not state then
                state = freshMomentum()
                momentumByBattle[battle] = state
            end
            if not state.temp then
                state.temp = {
                    evasion = 0,
                    defense = 0,
                    cover = false,
                    picHidden = false,
                    entrenched = false,
                    entrenchTurns = 0,
                    hidAway = false,
                    coverSpot = nil,
                    deepCover = false,
                    deepCoverRolled = false,
                    dodgedOk = false,
                }
            end
            if state.temp.entrenchTurns == nil then
                state.temp.entrenchTurns = 0
            end
            if not state.enemyTemp then
                state.enemyTemp = { evasion = 0, defense = 0, cover = false }
            end
            return state
        end

        do
            local function fmtTemp(temp)
                if not temp then
                    return "-"
                end
                local bits = {}
                if (temp.evasion or 0) ~= 0 then
                    bits[#bits + 1] = "EV" .. tostring(temp.evasion)
                end
                if (temp.defense or 0) ~= 0 then
                    bits[#bits + 1] = "DF" .. tostring(temp.defense)
                end
                if temp.cover then
                    bits[#bits + 1] = "cover"
                end
                if temp.hidAway then
                    bits[#bits + 1] = "hide"
                end
                if temp.entrenched then
                    bits[#bits + 1] = "entrench"
                    if (temp.entrenchTurns or 0) > 0 then
                        bits[#bits + 1] = "t" .. tostring(temp.entrenchTurns)
                    end
                end
                if temp.picHidden then
                    bits[#bits + 1] = "picHide"
                end
                if temp.coverSpot and temp.coverSpot ~= "" then
                    bits[#bits + 1] = tostring(temp.coverSpot):sub(1, 6)
                end
                if temp.deepCover then
                    bits[#bits + 1] = "deep"
                end
                if #bits == 0 then
                    return "-"
                end
                return table.concat(bits, ",")
            end
            -- Expose for turn-start / cover-clear logs in the outer scope.
            dev.fmtTemp = fmtTemp

            dev.peek = function(battle)
                return battle and momentumByBattle[battle] or nil
            end

            function dev.stage(battler, stat)
                if not battler or not battler.stages then
                    return 0
                end
                return battler.stages[stat] or 0
            end

            function dev.snapshot(battle)
                local state = dev.peek(battle) or { temp = {}, enemyTemp = {} }
                local p, e = battle.player, battle.enemy
                local youArm = state.boosted and "used"
                    or (state.mode == "counter" and "rdy" or "-")
                local wait = tostring(state.awaitingPick or "-"):sub(1, 5)
                local youTmp = dev.fmtTemp(state.temp)
                local foeTmp = dev.fmtTemp(state.enemyTemp)
                return {
                    -- Compact chip lines (≤18 chars) for a corner panel.
                    string.format("YOU %s %s", youArm, wait),
                    string.format(" %s E%d D%d", youTmp, dev.stage(p, "evasion"),
                        dev.stage(p, "defense")),
                    string.format("FOE %s %s",
                        tostring(state.enemyMode or "-"):sub(1, 7),
                        state.enemyReactedThisTurn and "rx" or "-"),
                    string.format(" %s E%d D%d", foeTmp, dev.stage(e, "evasion"),
                        dev.stage(e, "defense")),
                }
            end

            -- Compact top-right chip; full sequence stays in anime_realism_dev.log.
            dev.draw = function(battle)
                if not dev.on() or type(battle) ~= "table" then
                    return
                end
                if not (love and love.graphics) then
                    return
                end
                local okFont, Font = pcall(require, "src.render.Font")
                if not okFont or type(Font) ~= "table" or type(Font.draw) ~= "function" then
                    return
                end
                local g = love.graphics
                local log = dev.bag(battle)
                local snap = dev.snapshot(battle)
                local events = log and log.lines or {}
                local last = events[#events]
                local lineH = 8
                local pad = 2
                local colW = 18 * 8
                local rows = 1 + #snap + (last and 1 or 0)
                local boxW = colW + pad * 2
                local boxH = rows * lineH + pad * 2
                local boxX = math.max(0, 160 - boxW)
                local boxY = 0
                local function clip(s, n)
                    s = tostring(s or "")
                    n = n or 18
                    if #s <= n then
                        return s
                    end
                    return s:sub(1, n - 1) .. "+"
                end
                g.push("all")
                -- Soft panel; thin edge so it reads as a chip, not a blackout.
                g.setColor(0.05, 0.08, 0.12, 0.72)
                g.rectangle("fill", boxX, boxY, boxW, boxH)
                g.setColor(0.55, 0.75, 0.95, 0.55)
                g.rectangle("line", boxX + 0.5, boxY + 0.5, boxW - 1, boxH - 1)
                local y = boxY + pad
                local x = boxX + pad
                local function put(text)
                    Font.draw(clip(text), x, y)
                    y = y + lineH
                end
                g.setColor(1, 1, 1, 1)
                put("AR DEV")
                for i = 1, #snap do
                    put(snap[i])
                end
                if last then
                    -- Strip the noisy "#N TN " prefix for the one-line tail.
                    local short = tostring(last):gsub("^#%d+%s+T%d+%s+", "")
                    put(short)
                end
                g.pop()
            end
        end

        local function resetMomentum(battle)
            if not battle then
                return
            end
            local prev = momentumByBattle[battle]
            local keepTemp = prev and prev.temp
            local keepEnemyTemp = prev and prev.enemyTemp
            -- Never carry deferred pick menus across turns — a leftover OPENING!
            -- COUNTER/HOLD would pop at the start of the next turn before anyone acts.
            if prev and prev.awaitingPick == "counter" then
                prev.mode = nil
                prev.boosted = false
                prev.foeWhiffDamage = nil
            end
            -- Keep unused counters armed across the turn boundary.
            local keepCounter = prev and prev.mode == "counter" and not prev.boosted
            local keepEnemyCounter = prev and prev.enemyMode == "counter" and not prev.enemyBoosted
            momentumByBattle[battle] = freshMomentum()
            if keepTemp then
                momentumByBattle[battle].temp = keepTemp
            end
            if keepEnemyTemp then
                momentumByBattle[battle].enemyTemp = keepEnemyTemp
            end
            if keepCounter then
                momentumByBattle[battle].mode = "counter"
                momentumByBattle[battle].boosted = false
            end
            if keepEnemyCounter then
                momentumByBattle[battle].enemyMode = "counter"
                momentumByBattle[battle].enemyBoosted = false
            end
            -- Battle-owned latches survive hot-reload weak-table resets.
            battle._arSuppressReactDefer = nil
            battle._arPickOfferedThisTurn = nil
        end

        local function clearBattleMomentum(battle)
            if battle then
                clearAmbientStance(battle)
                local st = momentumByBattle[battle]
                local cameo = st and st.banterCameo
                if cameo and cameo.forcedTrainer then
                    battle.showEnemyTrainer = cameo.prevShowEnemyTrainer and true or false
                end
            end
            if not battle then
                return
            end
            momentumByBattle[battle] = freshMomentum()
        end

        local function foeMoveIsSpecial(move)
            if not move then
                return false
            end
            if move.category == "special" then
                return true
            end
            if move.category == "physical" or move.category == "status" then
                return false
            end
            -- Gen 1: physical/special comes from the move's type.
            local ok, special = pcall(Damage.isSpecial, move.type)
            return ok and special or false
        end

        -- Sleep / freeze: fully inert — no trainer callouts, dodge/brace,
        -- COVER!/ENTRENCH!, or idle pulses. Paralysis still can act (stiffer react).
        local function battlerStatusLocked(battler)
            local st = battler and battler.mon and battler.mon.status
            return st == "SLP" or st == "FRZ"
        end

        local function playerStatusLocked(battle)
            return battlerStatusLocked(battle and battle.player)
        end

        local function enemyStatusLocked(battle)
            return battlerStatusLocked(battle and battle.enemy)
        end

        local function playerIsParalyzed(battle)
            local mon = battle and battle.player and battle.player.mon
            return mon and mon.status == "PAR"
        end

        local function playerHasCounter(battle)
            if not opt("momentum_counter") or not battle then
                return false
            end
            local state = momentumByBattle[battle]
            return state and state.mode == "counter" and not state.boosted
        end

        local function dodgeFailChance()
            local style = calloutStyle()
            if style == "TRICKY" then
                return 0.20
            end
            if style == "BOLD" then
                return 0.25
            end
            if style == "SHOWY" then
                return 0.35
            end
            return 0.30
        end

        -- Paralysis: still react, but stiffer (~+25% fail). Small per-turn chance
        -- to shake it off (vanilla Gen 1 never wears PAR on its own).
        S.PAR_REACT_FAIL_EXTRA = 0.25
        S.PAR_SHAKE_OFF = 0.10

        local function rollDodgeSuccess()
            local r = (love and love.math and love.math.random) or math.random
            return r() >= dodgeFailChance()
        end

        -- Player dodge/brace under fire. kind "brace" only fails while paralyzed.
        local function rollPlayerReactSuccess(battle, kind)
            local r = (love and love.math and love.math.random) or math.random
            local fail = 0
            if kind == "dodge" then
                fail = dodgeFailChance()
            end
            if playerIsParalyzed(battle) then
                fail = math.min(0.90, fail + (S.PAR_REACT_FAIL_EXTRA or 0.25))
            elseif kind ~= "dodge" then
                return true
            end
            return r() >= fail
        end

        local function tryShakeOffParalysis(battle)
            if not battle or not playerIsParalyzed(battle) then
                return false
            end
            local r = (love and love.math and love.math.random) or math.random
            if r() >= (S.PAR_SHAKE_OFF or 0.10) then
                return false
            end
            local battler = battle.player
            battler.mon.status = nil
            battler.shownStatus = nil
            return true
        end

        -- Rare physical connect that still arms COUNTER/HOLD (~20%).
        local function rollPhysicalCounterArm()
            local r = (love and love.math and love.math.random) or math.random
            return r() < 0.20
        end

        -- Light risk only — openings should feel rewarding, not coin-flippy.
        S.COUNTER_EXTRA_MISS = 0.05
        S.COUNTER_SNAPBACK_CHANCE = 0.40
        S.COUNTER_SNAPBACK_MULT = 0.50 -- of the foe's stashed whiff estimate
        local function rollCounterExtraMiss()
            local r = (love and love.math and love.math.random) or math.random
            return r() < S.COUNTER_EXTRA_MISS
        end
        local function rollCounterSnapBack()
            local r = (love and love.math and love.math.random) or math.random
            return r() < S.COUNTER_SNAPBACK_CHANCE
        end

        -- What the foe's whiff "would have" dealt (for their snap-back).
        local function estimateMoveDamage(battle, user, target, move)
            if not battle or not user or not target or not move then
                return 10
            end
            local dmg = nil
            local ok = pcall(function()
                dmg = select(1, Damage.compute(
                    battle.ruleset, user, target, move, { rng = battle.rng }))
            end)
            if ok and type(dmg) == "number" and dmg > 0 then
                return dmg
            end
            return math.max(1, math.floor((move.power or 40) * 0.45))
        end

        local function foeCounterBackDamage(state)
            local base = (state and state.foeWhiffDamage) or 10
            local mult = S.COUNTER_SNAPBACK_MULT or 0.50
            return math.max(1, math.floor(base * mult))
        end

        -- Entrenched: foe rarely punches through max DEF (~18%).
        local function rollEntrenchBreakthrough()
            local r = (love and love.math and love.math.random) or math.random
            return r() < 0.18
        end

        -- Per-battle effort tracking (Gen 1 stat exp consolation + underdog XP).
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

        local function clearEffort(battle)
            if battle then
                effortByBattle[battle] = { mons = {} }
            end
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

        S.EFFORT_LINES = {
            "%s grew\nfrom the effort!",
            "%s learned\nfrom that fight!",
            "Hard fight-\n%s grew a bit!",
            "%s's effort\nwasn't wasted!",
        }

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
            local line = pickLine(S.EFFORT_LINES) or "%s grew\nfrom the effort!"
            battle:sayNext(line:format(name))
            return true
        end

        -- Much-weaker KO → bonus EXP (exp.gain runs per receiving mon).
        mod.hooks:wrap("exp.gain", function(next, ctx)
            local exp = next(ctx)
            if not opt("underdog_exp") or type(exp) ~= "number" then
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
            if not opt("effort_faint") or not ctx or not ctx.battle then
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
                lowWarned[ev.battle] = { player = false, enemy = false }
                clearBattleMomentum(ev.battle)
                clearEffort(ev.battle)
                clearCalloutPickState(ev.battle)
                if ReactiveDefense then
                    ReactiveDefense.clear(ev.battle)
                    ReactiveDefense.state(ev.battle)
                end
                -- DS cover stamps only. FIELD arena snapshot/restore is owned by field_battle/.
                local fieldOn = FieldBattleViewer and type(FieldBattleViewer.enabled) == "function"
                    and FieldBattleViewer.enabled(mod)
                if not fieldOn then
                    ev.battle._arRestoreMap = function()
                        if type(dev.restoreBattleCoverProps) == "function" then
                            pcall(dev.restoreBattleCoverProps)
                        end
                    end
                    if type(dev.stampBattleCoverProps) == "function" then
                        pcall(dev.stampBattleCoverProps, ev.battle)
                    end
                end
            end
        end)

        mod.events:on("battle.ended", function(ev)
            if ev and ev.battle then
                resolvePendingDamage(ev.battle)
                clearCalloutPickState(ev.battle)
                clearAmbientStance(ev.battle)
                if type(dev.restoreBattleCoverProps) == "function" then
                    pcall(dev.restoreBattleCoverProps)
                end
                ev.battle._arRestoreMap = nil
                if type(dev.clearFocusCoverVisual) == "function" then
                    dev.clearFocusCoverVisual(ev.battle, false)
                else
                    revealPlayerPic(ev.battle, false)
                end
            end
        end)

        mod.events:on("battle.turn_started", function(ev)
            -- Keep cover buffs across the turn; only reset per-turn counter flags.
            resetMomentum(ev and ev.battle)
            local battle = ev and ev.battle
            if battle then
                local st = momentumByBattle[battle]
                -- Fresh roll each turn for deep-cover lock / same-turn dodge flag.
                if st and st.temp then
                    st.temp.deepCover = false
                    st.temp.deepCoverRolled = false
                    st.temp.dodgedOk = false
                end
                if st then
                    st.dodgeWhiffDone = nil
                    st.keepDodgeMissAnim = nil
                    st.dodgeMissName = nil
                end
                publishChipState(battle)
                dev.log(battle, "TURN start",
                    string.format("keepCounter=%s youTmp=%s foeTmp=%s",
                        (st and st.mode == "counter") and "Y" or "N",
                        dev.fmtTemp(st and st.temp),
                        dev.fmtTemp(st and st.enemyTemp)))
                -- Shake-off text is queued in the later turn hook (needs pickFormatted).
                if tryShakeOffParalysis(battle) then
                    -- Name/line inline — pickFormatted isn't in scope this early.
                    local p = battle.player
                    local me = (p and p.mon and type(p.mon.nickname) == "string"
                            and p.mon.nickname ~= "" and p.mon.nickname)
                        or (p and p.name)
                        or "POKéMON"
                    local line = me .. " shook off\nthe paralysis!"
                    local pool = S.PAR_SHAKE_CALLS
                    if type(pool) == "table" and #pool > 0 then
                        local rr = (love and love.math and love.math.random) or math.random
                        local tmpl = pool[rr(1, #pool)]
                        if type(tmpl) == "string" then
                            line = (tmpl:gsub("%%s", me, 1):gsub("%%s", me))
                        end
                    end
                    if type(battle.sayNext) == "function" then
                        battle:sayNext(line)
                    elseif type(battle.say) == "function" then
                        battle:say(line)
                    end
                    dev.log(battle, "PAR shake", "cured")
                end
            end
        end)

        mod.events:on("battle.battler_switched", function(ev)
            local battle = ev and ev.battle
            if not battle then
                return
            end
            local side = ev.side
            if side ~= "player" and side ~= "enemy" then
                side = sideKey(ev.battler)
            end
            local warn = lowWarned[battle]
            if warn and side then
                warn[side] = false
            end
            -- New mon: Focus back to default; clear cover / entrench / react CDs.
            if ReactiveDefense and side == "player" then
                ReactiveDefense.resetSide(battle, true)
                if type(dev.clearFocusCoverVisual) == "function" then
                    dev.clearFocusCoverVisual(battle, false)
                end
            elseif ReactiveDefense and side == "enemy" then
                ReactiveDefense.resetSide(battle, false)
            end
            -- Cover buffs belong to the mon that dodged; wipe on your switch.
            if side == "player" then
                resolvePendingDamage(battle)
                clearCalloutPickState(battle)
                revealPlayerPic(battle, false)
                local ms = momentumState(battle)
                ms.temp = {
                    evasion = 0,
                    defense = 0,
                    cover = false,
                    picHidden = false,
                    entrenched = false,
                    entrenchTurns = 0,
                    hidAway = false,
                    coverSpot = nil,
                    deepCover = false,
                    deepCoverRolled = false,
                    dodgedOk = false,
                }
                ms.focusCoverSpot = nil
                ms.mode = nil
                ms.boosted = false
                publishChipState(battle)
            elseif side == "enemy" then
                local ms = momentumState(battle)
                ms.enemyTemp = { evasion = 0, defense = 0, cover = false }
                ms.enemyMode = nil
                ms.enemyBoosted = false
                ms.enemyReactedThisTurn = false
                publishChipState(battle)
            end
            -- New battler may already be low.
            checkLowHp(battle, ev.battler)
        end)

        mod.events:on("battle.move_used", function(ev)
            if not ev or not ev.battle or not ev.user then
                return
            end
            if not ev.user.isPlayer then
                return
            end
            local mon = ev.user.mon
            local rec = effortRec(ev.battle, mon)
            if rec then
                rec.moves = (rec.moves or 0) + 1
            end
            -- Damaging attack this turn — used for same-round counter after a dodge.
            local move = ev.move
            if move and (move.power or 0) > 0 and move.category ~= "status" then
                momentumState(ev.battle).playerActedThisTurn = true
            end
        end)

        mod.events:on("battle.fainted", function(ev)
            if not ev or not ev.battle or not ev.battler then
                return
            end
            if ev.battler.isPlayer then
                local rec = effortRec(ev.battle, ev.battler.mon)
                if rec then
                    rec.fainted = true
                end
                -- Mid-pick faint should not leave a deferred hit hanging.
                resolvePendingDamage(ev.battle)
                clearCalloutPickState(ev.battle)
                revealPlayerPic(ev.battle, false)
            end
        end)

        mod.events:on("battle.damage_dealt", function(ev)
            checkLowHp(ev and ev.battle, ev and ev.target)
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
            if not opt("momentum_counter") then
                return
            end
            -- Physical connect: only an off-chance to arm counter (misses arm via
            -- battle.accuracy). Keeps COUNTER/HOLD from popping every trade.
            if target and target.isPlayer and user and not user.isPlayer
                and (ev.damage or 0) > 0 and not foeMoveIsSpecial(ev.move)
                and rollPhysicalCounterArm() then
                local state = momentumState(ev.battle)
                state.mode = "counter"
                state.boosted = false
                dev.log(ev.battle, "ARM counter", "physical-connect ~20%")
            end
            if user and user.isPlayer and target and not target.isPlayer
                and (ev.damage or 0) > 0 and not foeMoveIsSpecial(ev.move)
                and rollPhysicalCounterArm() then
                local state = momentumState(ev.battle)
                state.enemyMode = "counter"
                state.enemyBoosted = false
                dev.log(ev.battle, "ARM foeCounter", "physical-connect ~20%")
            end
            -- In cover / breakthrough messaging after a hit lands.
            if target and (ev.damage or 0) > 0 then
                announceCoverHit(ev.battle, target)
            elseif target and target.isPlayer then
                local st = momentumByBattle[ev.battle]
                if st and st.breakthroughPending then
                    announceCoverHit(ev.battle, target)
                end
            end
        end)

        -- Miss creates the opening: foe whiffs you → you can COUNTER next.
        -- Same for trainer foes when you miss them.
        -- Dodge cover miss: keep the move anim so the attack still plays.
        -- Counter swings have a light extra miss (~5%); a miss sometimes lets
        -- the foe snap back for half their stashed whiff damage.
        mod.hooks:wrap("battle.accuracy", function(next, ctx)
            if not opt("momentum_counter") or not ctx then
                return next(ctx)
            end
            local move = ctx.move
            if not move or (move.power or 0) <= 0 or move.category == "status" then
                return next(ctx)
            end
            local user, target, battle = ctx.user, ctx.target, ctx.battle
            if not battle or not user or not target then
                return next(ctx)
            end
            local state = momentumState(battle)
            local countering = user.isPlayer and not target.isPlayer
                and state.mode == "counter" and not state.boosted

            local hit = next(ctx)
            if hit and countering and rollCounterExtraMiss() then
                hit = false
            end

            if not hit then
                local function coverName(battler)
                    if battler and battler.mon and type(battler.mon.nickname) == "string"
                        and battler.mon.nickname ~= "" then
                        return battler.mon.nickname
                    end
                    return (battler and battler.name) or "POKéMON"
                end
                -- Keep miss anim only for dodge/hide cover — not brace DEF.
                local function isDodgeHide(temp)
                    return temp and temp.cover
                        and ((temp.evasion or 0) > 0 or temp.hidAway or temp.picHidden)
                end
                if target.isPlayer and isDodgeHide(state.temp) then
                    state.keepDodgeMissAnim = true
                    state.dodgeMissName = coverName(target)
                elseif (not target.isPlayer) and isDodgeHide(state.enemyTemp) then
                    state.keepDodgeMissAnim = true
                    state.dodgeMissName = coverName(target)
                end
                if countering then
                    -- Your counter whiffed — may snap-back (rolled in resolve).
                    state.counterWhiffed = true
                    state.mode = nil
                    state.boosted = false
                elseif target.isPlayer and not user.isPlayer then
                    state.mode = "counter"
                    state.boosted = false
                    state.foeWhiffDamage = estimateMoveDamage(battle, user, target, move)
                    -- Same-turn COUNTER! only after a successful dodge into a miss.
                    -- (Menu is queued later — after miss anim + dodge-whiff text.)
                    if state.temp and state.temp.cover and state.temp.dodgedOk then
                        state.offerSameTurnCounter = true
                        -- Going second: replace the move chosen at turn start.
                        if not state.playerActedThisTurn then
                            state.replaceQueuedPlayerAction = true
                        end
                        dev.log(battle, "ARM counter",
                            string.format("dodge-miss sameTurn=%s replace=%s",
                                "Y",
                                state.replaceQueuedPlayerAction and "Y" or "N"))
                    else
                        dev.log(battle, "ARM counter",
                            state.temp and state.temp.cover
                            and "foe-miss (cover, no dodgedOk)"
                            or "foe-miss (no cover)")
                    end
                elseif user.isPlayer and not target.isPlayer then
                    local kind = battle.kind
                    if kind == "trainer" or kind == "link" then
                        state.enemyMode = "counter"
                        state.enemyBoosted = false
                        dev.log(battle, "ARM foeCounter", "you-missed")
                    end
                end
                if countering then
                    dev.log(battle, "COUNTER whiff", "extra-miss/snapback")
                end
            end
            return hit
        end)

        mod.events:on("battle.turn_ended", function(ev)
            local battle = ev and ev.battle
            if not battle then
                return
            end
            -- Residual poison/burn and other non-damage_dealt drains.
            checkLowHp(battle, battle.player)
            checkLowHp(battle, battle.enemy)
            local state = momentumByBattle[battle]
            if state then
                state.breakthroughPending = nil
            end
            if ReactiveDefense and opt("momentum_counter") then
                ReactiveDefense.endTurn(battle)
            end
            -- Quiet beat: occasional trainer chatter when nothing's in cover.
            if maybeEnqueueIdleBanter then
                maybeEnqueueIdleBanter(battle)
            end
        end)


        -- Reactive Defense damage modifiers + legacy counter +25%.
        mod.hooks:wrap("battle.damage", function(next, ctx)
            local dmg, info = next(ctx)
            if not opt("momentum_counter") or not ctx then
                return dmg, info
            end
            local user, target, battle = ctx.user, ctx.target, ctx.battle
            if type(dmg) ~= "number" or dmg <= 0 then
                return dmg, info
            end

            if ReactiveDefense and target and target.isPlayer and user and not user.isPlayer then
                local rd = ReactiveDefense.state(battle)
                local side = ReactiveDefense.sideState(battle, true)
                local pending = rd and rd.hitMod
                -- Any hit while in Focus cover soaks durability (Commit still sheltered).
                if side and side.cover then
                    local durMult = 1
                    if pending and pending.coverDurMult then
                        durMult = pending.coverDurMult
                    elseif ctx.move and ReactiveDefense.isUnreactable(ctx.move) then
                        durMult = ReactiveDefense.COVER_UNREACT_DUR_MULT or 2.75
                    elseif ctx.move and ReactiveDefense.isCoverPierce(ctx.move) then
                        durMult = ReactiveDefense.COVER_PIERCE_MULT or 2
                    end
                    local overflow, broke = ReactiveDefense.applyCoverHit(
                        battle, true, dmg, durMult)
                    if broke then
                        if type(battle.sayNext) == "function" then
                            battle:sayNext("Cover shattered!")
                        end
                        if type(dev.clearFocusCoverVisual) == "function" then
                            dev.clearFocusCoverVisual(battle, true)
                        end
                    elseif overflow <= 0 then
                        if type(battle.sayNext) == "function" then
                            battle:sayNext("Cover held!")
                        end
                    end
                    dmg = overflow
                    if pending then
                        pending.coverSoak = false
                    end
                end
                if pending then
                    local mult = tonumber(pending.damageMult) or 1
                    if mult ~= 1 and dmg > 0 then
                        dmg = math.max(0, math.floor(dmg * mult + 0.5))
                    end
                    if pending.forceMiss then
                        dmg = 0
                    end
                    rd.hitMod = nil
                end
            end

            local state = battle and momentumByBattle[battle]
            if not state or dmg <= 0 then
                return dmg, info
            end
            if user and user.isPlayer and target and not target.isPlayer
                and state.mode == "counter" and not state.boosted then
                state.boosted = true
                dmg = math.max(1, math.floor(dmg * 5 / 4))
                dev.log(battle, "DMG +25%", "your counter")
                return dmg, info
            end
            if user and not user.isPlayer and target and target.isPlayer
                and state.enemyMode == "counter" and not state.enemyBoosted then
                state.enemyBoosted = true
                dmg = math.max(1, math.floor(dmg * 5 / 4))
                dev.log(battle, "DMG +25%", "foe counter")
                return dmg, info
            end
            return dmg, info
        end)

        -- Replace "X grew to level N!" with a generic line. StatBox + move
        -- learning still queue right after via uiNext / learnMove.
        S.LEVEL_UP_LINES = {
            "Your POKéMON has grown stronger!",
            "Your POKéMON looks more powerful!",
            "Your POKéMON's power has surged!",
            "Your POKéMON has become tougher!",
        }
   

        -- Anime-style trainer callouts for "NAME\nused MOVE!" (not item use).
        -- Wild battles keep the vanilla line. Trainer foes use the trainer's name.
        S.PLAYER_MOVE_CALLS = {
            "%s! Use %s!",
            "%s, use %s!",
            "Go! %s! %s!",
            "%s! %s!",
            "%s! Now! %s!",
            "%s! Quick, %s!",
            "OK, %s! %s!",
            "%s, go! Use %s!",
            "That's it! %s! %s!",
            "%s! Hit 'em! %s!",
            "Come on! %s! %s!",
            "%s! %s! Go!",
        }
        -- When the foe looks weak (same threshold as LOW HP AT).
        S.PLAYER_FINISH_CALLS = {
            "Finish it! %s! %s!",
            "%s! Finish it!",
            "%s! Finish it! %s!",
            "Now's our chance! %s! %s!",
            "%s! End it! %s!",
            "One more! %s! %s!",
            "%s! Take 'em down!",
            "Go for it! %s! %s!",
            "%s! This is it! %s!",
            "Finish them! %s! %s!",
        }
        -- After your move announce, when a physical counter is armed.
        -- Going second (foe already acted): announce becomes this line.
        S.AUTO_COUNTER_CALLS = {
            "%s! Counter with %s!",
            "Now, %s! Counter- %s!",
            "%s! Hit back! %s!",
            "Counter! %s, use %s!",
        }
        -- formatAutoCounterCall is defined after pickFormatted (Lua locals are
        -- not visible above their declaration — calling early binds a nil global).
        local formatAutoCounterCall
        S.PLAYER_COUNTER_CALLS = {
            AUTO = {
                "Now, %s! %s!",
                "%s! Hit back! %s!",
                "%s! Counter with %s!",
                "That's our opening! %s! %s!",
            },
            BOLD = {
                "%s! Strike back! %s!",
                "%s! Hit 'em hard!",
                "Now, %s! Smash back!",
                "%s! Return it! %s!",
            },
            TRICKY = {
                "%s! Turn it around!",
                "Now, %s! Catch 'em!",
                "%s! Use that opening!",
                "%s! Slip in- %s!",
            },
            SHOWY = {
                "Show 'em, %s! %s!",
                "%s! Make it flashy!",
                "That's it! %s! %s!",
                "%s! Hero time! %s!",
            },
        }
        -- Style-flavored dodge / brace bases (mon name = %s).
        S.DODGE_STYLE = {
            AUTO = {
                "%s! Dodge it!",
                "Dodge, %s!",
                "%s! Look out!",
                "Quick, %s! Dodge!",
            },
            BOLD = {
                "%s! Shrug it off!",
                "%s! Stand tall-dodge!",
                "No way, %s! Move!",
                "%s! Break clear!",
            },
            TRICKY = {
                "%s! Slip aside!",
                "Fake 'em out, %s!",
                "%s! Weave through!",
                "Easy, %s! Sidestep!",
            },
            SHOWY = {
                "%s! Dance aside!",
                "Show off, %s! Dodge!",
                "%s! Make it clean!",
                "Stylish, %s! Move!",
            },
        }
        S.BRACE_STYLE = {
            AUTO = {
                "%s! Get ready!",
                "%s! Brace yourself!",
                "Hold on, %s!",
                "%s! We can counter!",
            },
            BOLD = {
                "%s! Take it head-on!",
                "Stand firm, %s!",
                "%s! Don't flinch!",
                "%s! Eat that hit!",
            },
            TRICKY = {
                "%s! Roll with it!",
                "Wait for it, %s!",
                "%s! Let 'em commit!",
                "%s! Then we hit!",
            },
            SHOWY = {
                "%s! Make it look easy!",
                "Chin up, %s!",
                "%s! Pose-and brace!",
                "Cool under fire, %s!",
            },
        }
        -- Terrain lines: first %s = mon. Keep short for the text box.
        S.DODGE_SCENE = {
            cave = {
                "%s! Onto that rock!",
                "%s! Behind the rocks!",
                "Dodge-jump, %s! That ledge!",
            },
            forest = {
                "%s! Behind that tree!",
                "%s! Into the brush!",
                "Dodge-leaf, %s! Hide!",
            },
            city = {
                "%s! Behind that cart!",
                "%s! Use that alley!",
                "Dodge-corner, %s!",
            },
            route = {
                "%s! Into the grass!",
                "%s! Off the path!",
                "Wide berth, %s!",
            },
            mountain = {
                "%s! Up that cliff!",
                "%s! Use the ledge!",
                "Higher ground, %s!",
            },
            gym = {
                "%s! Use the pillars!",
                "%s! Around the court!",
                "Sidestep, %s! Pillar!",
            },
            water = {
                "%s! Along the shore!",
                "%s! Splash aside!",
                "Over the spray, %s!",
            },
            grave = {
                "%s! Behind a stone!",
                "%s! Into the dark!",
                "Fade back, %s!",
            },
            indoor = {
                "%s! Behind cover!",
                "%s! Use the wall!",
                "Clear the floor, %s!",
            },
        }
        S.BRACE_SCENE = {
            cave = {
                "%s! Brace on the rock!",
                "%s! Dig in here!",
            },
            forest = {
                "%s! Root in place!",
                "%s! Hold the line!",
            },
            city = {
                "%s! Hold the street!",
                "%s! Stand your ground!",
            },
            route = {
                "%s! Hold firm!",
                "%s! Hold the path!",
            },
            mountain = {
                "%s! Brace on stone!",
                "%s! Don't slip!",
            },
            gym = {
                "%s! Center court-hold!",
                "%s! Guard the mark!",
            },
            water = {
                "%s! Brace in the surf!",
                "%s! Hold the tide!",
            },
            grave = {
                "%s! Stand your ground!",
                "%s! Don't yield!",
            },
            indoor = {
                "%s! Hold the room!",
                "%s! Brace up!",
            },
        }
        -- Type spice (checked against player curTypes).
        S.DODGE_TYPE = {
            FLYING = {
                "%s! Fly up high!",
                "%s! Take the air!",
                "Wing it, %s! Up!",
            },
            WATER = {
                "%s! Dive aside!",
                "%s! Ride the splash!",
            },
            FIRE = {
                "%s! Burst aside!",
                "%s! Heat-dash clear!",
            },
            ELECTRIC = {
                "%s! Zip aside!",
                "%s! Spark-step!",
            },
            GRASS = {
                "%s! Into the leaves!",
                "%s! Bloom-step clear!",
            },
            PSYCHIC = {
                "%s! Sense-and move!",
                "%s! Bend aside!",
            },
            GHOST = {
                "%s! Fade through!",
                "%s! Phase aside!",
            },
            BUG = {
                "%s! Flutter clear!",
                "%s! Buzz aside!",
            },
            GROUND = {
                "%s! Dust-dash!",
                "%s! Low and aside!",
            },
            ROCK = {
                "%s! Stone-step clear!",
            },
            ICE = {
                "%s! Slide clear!",
            },
            DRAGON = {
                "%s! Soar clear!",
            },
            POISON = {
                "%s! Slip aside!",
            },
            FIGHTING = {
                "%s! Bob and weave!",
            },
        }
        S.BRACE_TYPE = {
            FIGHTING = {
                "%s! Guard up!",
                "%s! Tough it out!",
            },
            ROCK = {
                "%s! Be the boulder!",
                "%s! Rock-solid!",
            },
            GROUND = {
                "%s! Root down!",
            },
            STEEL = {
                "%s! Steel yourself!",
            },
            NORMAL = {
                "%s! Tough it out!",
            },
            WATER = {
                "%s! Roll with the wave!",
            },
            FLYING = {
                "%s! Hover-and hold!",
            },
        }
        -- Named characters only (gym leaders, E4, etc.). Class titles like
        -- YOUNGSTER / JR.TRAINER use foe mon callouts instead — no "TRAINER!".
        S.NAMED_TRAINERS = {
            BROCK = true,
            MISTY = true,
            ["LT.SURGE"] = true,
            ERIKA = true,
            KOGA = true,
            SABRINA = true,
            BLAINE = true,
            GIOVANNI = true,
            LORELEI = true,
            BRUNO = true,
            AGATHA = true,
            LANCE = true,
            ["PROF.OAK"] = true,
            CHIEF = true,
            ROCKET = true,
        }
        -- trainer, mon, move — softer "NAME:" lead-in, not "NAME!"
        S.TRAINER_MOVE_CALLS = {
            "%s:\n%s, use %s!",
            "%s:\n%s! %s!",
            "%s:\nGo, %s! %s!",
            "%s:\n%s, %s!",
            "%s:\n%s, now! %s!",
            "%s:\nDo it, %s! %s!",
        }
        -- Foe Pokémon callouts when the trainer label is a generic class.
        S.FOE_MOVE_CALLS = {
            "%s!\nUse %s!",
            "%s, use\n%s!",
            "Go, %s!\n%s!",
            "%s!\n%s!",
            "%s!\n%s, now!",
            "%s!\nQuick, %s!",
            "Come on,\n%s! %s!",
        }

        local function isGrewToLevelText(text)
            local s = tostring(text or ""):lower()
            return s:find("grew", 1, true) and s:find("level", 1, true)
        end

        -- Engine move announce is "NAME\nused MOVE!". Item use is "NAME used\nITEM!".
        local function parseUsedMoveText(text)
            local s = tostring(text or "")
            local mon, move = s:match("^([^\n]+)\nused ([^\n!]+)!$")
            if mon and move and mon ~= "" and move ~= "" then
                return mon, move
            end
            return nil
        end

        local function stripEnemyPrefix(mon)
            local bare = tostring(mon or ""):match("^[Ee]nemy%s+(.+)$")
            if bare and bare ~= "" then
                return bare, true
            end
            return mon, false
        end

        local function formatCall(template, a, b, c)
            local _, n = template:gsub("%%s", "")
            if n <= 0 then
                return template
            end
            if n >= 3 then
                return template:format(a, b, c)
            end
            if n >= 2 then
                return template:format(a, b)
            end
            return template:format(a)
        end

        local function pickFormatted(templates, a, b, c)
            local t = pickLine(templates)
            if not t then
                return nil
            end
            return formatCall(t, a, b, c)
        end

        formatAutoCounterCall = function(me, moveName)
            me = me or "POKéMON"
            moveName = moveName or "MOVE"
            return pickFormatted(S.AUTO_COUNTER_CALLS, me, moveName)
                or (me .. "!\nCounter with " .. moveName .. "!")
        end

        local function enemyLooksWeak(battle)
            local mon = battle and battle.enemy and battle.enemy.mon
            if not mon then
                return false
            end
            local max = mon.stats and mon.stats.hp
            local hp = mon.hp or 0
            if not max or max <= 0 or hp <= 0 then
                return false
            end
            return (hp / max) <= lowHpRatio()
        end

        -- Personal / boss names only. Class labels (JR.TRAINER, YOUNGSTER, …)
        -- and anything containing "TRAINER" are treated as generic.
        local function personalTrainerName(battle)
            local name = battle and battle.trainer and battle.trainer.name
            if type(name) ~= "string" or name == "" then
                return nil
            end
            local key = name:upper()
            if key:find("TRAINER", 1, true) then
                return nil
            end
            if key:match("^RIVAL%d*$") then
                return nil
            end
            if S.NAMED_TRAINERS[key] then
                return name
            end
            -- Rival overlay uses the save's rival name (e.g. BLUE) — keep it.
            local kind = battle.oppClass
            if kind == "OPP_RIVAL1" or kind == "OPP_RIVAL2" or kind == "OPP_RIVAL3" then
                return name
            end
            return nil
        end

        -- Battle text box is 18 glyphs wide (Theme.textBox.maxCols).
        S.BATTLE_TEXT_COLS = 18

        local function battleGlyphLen(s)
            local n = 0
            for _ in tostring(s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                n = n + 1
            end
            return n
        end

        local function fitsBattleLine(s)
            return battleGlyphLen(s) <= S.BATTLE_TEXT_COLS
        end

        -- Keep anime callouts inside the 2-line box; spill to a 3rd line or CONT.
        local function formatEnemyMoveCall(trainer, mon, move)
            mon = tostring(mon or "POKéMON")
            move = tostring(move or "MOVE")
            if trainer and trainer ~= "" then
                local head = tostring(trainer) .. ":"
                local one = mon .. ", use " .. move .. "!"
                if fitsBattleLine(head) and fitsBattleLine(one) then
                    return head .. "\n" .. one
                end
                local mid = mon .. ", use"
                local tail = move .. "!"
                if fitsBattleLine(head) and fitsBattleLine(mid) and fitsBattleLine(tail) then
                    return head .. "\n" .. mid .. "\n" .. tail
                end
                local short = mon .. "! " .. move .. "!"
                if fitsBattleLine(head) and fitsBattleLine(short) then
                    return head .. "\n" .. short
                end
                if fitsBattleLine(head) and fitsBattleLine(mon .. "!") and fitsBattleLine(tail) then
                    return head .. "\n" .. mon .. "!\n" .. tail
                end
                -- Last resort: CONT so the move name isn't clipped.
                return head .. "\n" .. mon .. "!\v" .. move .. "!"
            end
            local a = mon .. "!\nUse " .. move .. "!"
            if fitsBattleLine(mon .. "!") and fitsBattleLine("Use " .. move .. "!") then
                return a
            end
            if fitsBattleLine(mon .. ", use") and fitsBattleLine(move .. "!") then
                return mon .. ", use\n" .. move .. "!"
            end
            return mon .. "!\n" .. move .. "!"
        end

        local function rewriteMoveCallText(battle, text)
            local mon, move = parseUsedMoveText(text)
            if not mon then
                return text
            end
            local bare, isEnemy = stripEnemyPrefix(mon)
            -- Frozen / asleep: no trainer orders — leave the engine's status/move text.
            if isEnemy and enemyStatusLocked(battle) then
                return text
            end
            if (not isEnemy) and playerStatusLocked(battle) then
                return text
            end
            -- Armed counter: announce IS "Counter with X!" — no generic callout under it.
            if not isEnemy and playerHasCounter(battle) then
                return formatAutoCounterCall(bare, move)
            end
            if not opt("anime_move_calls") then
                return text
            end
            if isEnemy then
                local kind = battle and battle.kind
                -- Wild: leave "Enemy X used Y!" alone.
                if kind ~= "trainer" and kind ~= "link" then
                    return text
                end
                local trainer = personalTrainerName(battle)
                if trainer then
                    local fitted = formatEnemyMoveCall(trainer, bare, move)
                    if fitted then
                        return fitted
                    end
                    return pickFormatted(S.TRAINER_MOVE_CALLS, trainer, bare, move)
                        or (trainer .. ":\n" .. bare .. ", use " .. move .. "!")
                end
                return formatEnemyMoveCall(nil, bare, move)
                    or pickFormatted(S.FOE_MOVE_CALLS, bare, move)
                    or (bare .. "!\nUse " .. move .. "!")
            end
            return pickFormatted(S.PLAYER_MOVE_CALLS, bare, move)
                or (bare .. "!\nUse " .. move .. "!")
        end

        local function rewriteLevelUpText(text)
            if opt("generic_level_up") and isGrewToLevelText(text) then
                return pickLine(S.LEVEL_UP_LINES) or "Your POKéMON has\ngrown stronger!"
            end
            return text
        end

        -- Hide EXP share / EXP.ALL / boosted-EXP dialogue. Level-up lines stay.
        local function isExpGainDialogue(text)
            local s = tostring(text or "")
            if s == "" or isGrewToLevelText(s) then
                return false
            end
            local lower = s:lower()
            if lower:find("exp. points", 1, true) or lower:find("exp points", 1, true) then
                return true
            end
            if lower:find("experience", 1, true) then
                return true
            end
            if lower:find("exp.all", 1, true) or lower:find("exp all", 1, true) then
                return true
            end
            if lower:find("gained", 1, true)
                and (lower:find("exp", 1, true) or lower:find("boosted", 1, true)) then
                return true
            end
            -- Scrolled second page: "123 EXP. Points!"
            if lower:find("exp", 1, true) and lower:find("point", 1, true) then
                return true
            end
            return false
        end

        local function rewriteBattleText(battle, text)
            text = rewriteLevelUpText(text)
            return rewriteMoveCallText(battle, text)
        end

        local function playerMonName(battle)
            local p = battle and battle.player
            if not p then
                return "POKéMON"
            end
            if p.mon and type(p.mon.nickname) == "string" and p.mon.nickname ~= "" then
                return p.mon.nickname
            end
            return p.name or "POKéMON"
        end

        local function findMoveByName(battle, name)
            local moves = battle and battle.data and battle.data.moves
            if not moves or not name then
                return nil
            end
            local want = tostring(name):upper()
            local direct = moves[want]
            if type(direct) == "table" then
                return direct
            end
            for _, def in pairs(moves) do
                if type(def) == "table" and def.name and tostring(def.name):upper() == want then
                    return def
                end
            end
            return nil
        end

        local function battleScene(battle)
            local mapId = ""
            if battle and type(battle.currentMapId) == "function" then
                mapId = tostring(battle:currentMapId() or "")
            end
            local id = mapId:upper()
            local tileset = nil
            local maps = battle and battle.game and battle.game.data and battle.game.data.maps
            local def = maps and mapId ~= "" and maps[mapId]
            if type(def) == "table" then
                tileset = def.tileset
            end
            local ts = tostring(tileset or ""):upper()

            if ts == "CAVERN" or ts == "UNDERGROUND"
                or id:find("CAVE", 1, true) or id:find("TUNNEL", 1, true)
                or id:find("MT_MOON", 1, true) or id:find("ROCK_TUNNEL", 1, true) then
                return "cave"
            end
            if ts == "FOREST" or ts == "FOREST_GATE" or id:find("FOREST", 1, true) then
                return "forest"
            end
            if ts == "CEMETERY" or id:find("POKEMON_TOWER", 1, true)
                or id:find("LAVENDER", 1, true) then
                return "grave"
            end
            if ts == "GYM" or ts == "DOJO" or id:find("_GYM", 1, true) or id:find("GYM_", 1, true) then
                return "gym"
            end
            if ts == "PLATEAU" or id:find("VICTORY", 1, true)
                or id:find("MT_", 1, true) then
                return "mountain"
            end
            if ts == "SHIP" or ts == "SHIP_PORT" or id:find("SEAFOAM", 1, true)
                or id:find("SS_ANNE", 1, true) then
                return "water"
            end
            if id:find("CITY", 1, true) or id:find("TOWN", 1, true) then
                return "city"
            end
            if ts == "HOUSE" or ts == "MART" or ts == "POKECENTER" or ts == "INTERIOR"
                or ts == "LAB" or ts == "LOBBY" or ts == "FACILITY" or ts == "CLUB"
                or ts == "MUSEUM" or ts == "MANSION" or ts == "GATE"
                or ts == "REDS_HOUSE_1" or ts == "REDS_HOUSE_2" then
                return "indoor"
            end
            return "route"
        end

        local function playerTypeSet(battle)
            local set = {}
            local types = battle and battle.player and battle.player.curTypes
            if type(types) ~= "table" then
                return set
            end
            for _, ty in ipairs(types) do
                local key = tostring(ty or ""):upper()
                if key == "PSYCHIC_TYPE" then
                    key = "PSYCHIC"
                end
                if key ~= "" then
                    set[key] = true
                end
            end
            return set
        end

        local function buildCallPool(kind, battle)
            local style = calloutStyle()
            local scene = battleScene(battle)
            local types = playerTypeSet(battle)
            local pool = {}
            -- Each entry: { line = "...", boost = 1|2 } for dodge/brace tiers.

            local function add(list, boost)
                if type(list) ~= "table" then
                    return
                end
                for i = 1, #list do
                    pool[#pool + 1] = { line = list[i], boost = boost or 1 }
                end
            end

            if kind == "dodge" then
                add(S.DODGE_STYLE[style] or S.DODGE_STYLE.AUTO, style == "SHOWY" and 2 or 1)
                add(S.DODGE_SCENE[scene], 2)
                for ty, on in pairs(types) do
                    if on then
                        add(S.DODGE_TYPE[ty], 2)
                    end
                end
            elseif kind == "brace" then
                add(S.BRACE_STYLE[style] or S.BRACE_STYLE.AUTO, 1)
                add(S.BRACE_SCENE[scene], 1)
                for ty, on in pairs(types) do
                    if on then
                        add(S.BRACE_TYPE[ty], 2)
                    end
                end
            elseif kind == "counter" then
                local lines = S.PLAYER_COUNTER_CALLS[style] or S.PLAYER_COUNTER_CALLS.AUTO
                local defDrop = (style == "SHOWY" or style == "BOLD") and 2 or 1
                add(lines, defDrop)
            end

            return pool
        end

        local function pickCallEntry(kind, battle, monName, moveName)
            local pool = buildCallPool(kind, battle)
            if #pool == 0 then
                return nil, 1
            end
            local entry = pickLine(pool)
            if not entry then
                return nil, 1
            end
            local line = formatCall(entry.line, monName, moveName)
            return line, entry.boost or 1
        end

        S.DODGE_FAIL_CALLS = {
            "...but it was\ntoo slow!",
        }
        -- Narrator line for a failed dodge (bottom text box, not a speech bubble).
        S.DODGE_TOO_SLOW = "...but it was\ntoo slow!"
        S.PAR_REACT_FAIL = "...but it couldn't\nmove right!"
        S.PAR_SHAKE_CALLS = {
            "%s shook off\nthe paralysis!",
            "%s's body\nlimbered up!",
            "%s fought through\nthe paralysis!",
            "The paralysis\nleft %s!",
        }
        local function isDodgeFailNarrator(text)
            if type(text) ~= "string" then
                return false
            end
            if text == S.PAR_REACT_FAIL or text == S.DODGE_TOO_SLOW then
                return true
            end
            return text:find("but it was", 1, true) ~= nil
                and text:lower():find("too slow", 1, true) ~= nil
        end
        local function reactFailLine(battle, kind)
            if playerIsParalyzed(battle) then
                return S.PAR_REACT_FAIL
            end
            if kind == "dodge" then
                return S.DODGE_TOO_SLOW
            end
            return S.PAR_REACT_FAIL
        end
        -- Real hide pierced — never plain sidestep, never brace/entrench.
        S.COVER_HIT_CALLS = {
            "But it found\n%s!",
            "Still got hit,\n%s!",
            "%s!\nHit through cover!",
            "Cover wasn't\nenough!",
        }
        -- Miss while dodging — replaces vanilla "attack missed!".
        S.DODGE_WHIFF_CALLS = {
            "But %s\ndodged aside!",
            "%s slipped\naway!",
            "Too slow!\n%s dodged!",
            "The attack\nwhiffed past!",
            "%s!\nSafe in cover!",
        }
        -- Evasive hide (PATH / grass / fly / …): chance for extra EVADE.
        -- Light buff vs plain sidestep — brush/cover should feel worth picking.
        S.VANISH_CHANCE = 0.40
        S.VANISH_EVADE_BONUS = 1
        S.VANISH_CALLS = {
            "Vanished from\nthe foe's sight!",
            "%s vanished from\nsight!",
            "Out of the foe's\nsight!",
            "%s slipped from\nview!",
            "Gone from view!",
            "%s melted into\ncover!",
            "Can't be seen!",
            "%s winked out of\nsight!",
        }
        -- Weighted EVADE rolls so dodge strength isn't fixed by the menu pick.
        -- basic = plain DODGE sidestep; hide = PATH / grass / fly / dive / …
        -- Hide leans a touch higher so grass/cover reads as safer than a sidestep.
        S.DODGE_EVADE_ROLL = {
            basic = { 1, 1, 1, 1, 2, 2 },
            hide = { 1, 2, 2, 2, 2, 3, 3, 3, 3, 4 },
        }
        S.DODGE_EVADE_HIGH_CALLS = {
            "Sharp instincts!",
            "Perfect timing!",
            "%s moved like\na blur!",
            "What a read!",
        }
        -- Foe punches through your entrenched guard (DEF stripped for this hit).
        S.BREAKTHROUGH_CALLS = {
            "Broke through\nthe guard!",
            "The defense\nshattered!",
            "Pushed past\n%s!",
            "Guard broken!\n%s!",
        }
        S.LEAVE_COVER_CALLS = {
            "%s!\nLeft cover!",
            "Breaking cover,\n%s!",
            "%s!\nComing out!",
            "Leave cover,\n%s! Strike!",
            "%s!\nCome out!",
            "Out of hiding,\n%s!",
            "%s!\nSurface and\nstrike!",
        }
        -- Stay in a real hide — mon stays tucked away (pic hidden).
        S.HOLD_POSITION_CALLS = {
            "%s!\nHold on!",
            "Stay in cover,\n%s!",
            "%s!\nKeep hiding!",
            "Hold tight,\n%s!",
            "%s!\nDon't come out!",
            "Stay put,\n%s!",
            "%s!\nKeep cover!",
            "Stay ready\nin cover, %s!",
        }
        -- Random deep-cover lock: can't leave (tree / dive / boulder / …).
        S.DEEP_COVER_CHANCE = 0.30
        S.DEEP_COVER_CALLS = {
            TREE = {
                "%s is still\nup the tree!",
                "%s can't climb\ndown yet!",
                "Still perched-\n%s, hold!",
            },
            BRUSH = {
                "%s is deep in\nthe brush!",
                "Can't leave the\nthicket yet!",
            },
            GRASS = {
                "%s is buried\nin the grass!",
                "Still hidden in\nthe tall grass!",
            },
            ROCK = {
                "%s is pinned\nbehind a rock!",
                "Can't leave the\nboulder yet!",
            },
            STONE = {
                "%s ducks behind\nthe stone!",
                "Still behind the\nstone!",
            },
            CLIFF = {
                "%s is stuck up\nthe cliff!",
                "Can't descend\nyet!",
            },
            LEDGE = {
                "%s clings to\nthe ledge!",
                "Still on the\nledge!",
            },
            ["FLY UP"] = {
                "%s is still\nhigh above!",
                "%s can't land\nyet!",
                "Still airborne-\nhold!",
            },
            DIVE = {
                "%s is still\nunderwater!",
                "%s can't surface\nyet!",
                "Deep below-\nhold breath!",
            },
            SPLASH = {
                "%s is still\nin the water!",
                "Can't leave the\nwaves yet!",
            },
            SHORE = {
                "%s hugs the\nshoreline!",
                "Still along the\nshore!",
            },
            CART = {
                "%s is tucked\nbehind the cart!",
                "Still using the\ncart for cover!",
            },
            ALLEY = {
                "%s is deep in\nthe alley!",
                "Can't leave the\nalley yet!",
            },
            PILLAR = {
                "%s stays behind\nthe pillar!",
                "Still using the\npillar!",
            },
            SHADOW = {
                "%s is lost in\nthe dark!",
                "Still in the\nshadows!",
            },
            COVER = {
                "%s can't leave\ncover yet!",
                "Still dug in-\nhold!",
            },
            WALL = {
                "%s presses to\nthe wall!",
                "Still using the\nwall!",
            },
            _default = {
                "%s can't leave\ncover yet!",
                "%s is stuck in\nhiding!",
                "Too deep in\ncover-hold!",
                "%s needs a\nmoment more!",
            },
        }
        S.SCENE_COVER_SPOT = {
            forest = "TREE",
            cave = "ROCK",
            water = "DIVE",
            mountain = "CLIFF",
            grave = "STONE",
            route = "GRASS",
            city = "CART",
            gym = "PILLAR",
            indoor = "COVER",
        }
        -- STATUS CHIPS: cover label → short English (fits under mon name).
        S.CHIP_SPOT_PHRASE = {
            GRASS = "in brush",
            BRUSH = "in brush",
            TREE = "up a tree",
            ROCK = "behind rocks",
            BOULDER = "behind rocks",
            LEDGE = "on a ledge",
            CLIFF = "on a cliff",
            STONE = "by a stone",
            SHADOW = "in the dark",
            CART = "by a cart",
            ALLEY = "in an alley",
            PATH = "off the path",
            PILLAR = "by pillars",
            COURT = "on court",
            WALL = "by a wall",
            COVER = "in cover",
            ["FLY UP"] = "in the air",
            DIVE = "underwater",
            SPLASH = "in water",
            SHORE = "by water",
            ZIP = "zipping by",
            BURST = "in smoke",
            FADE = "faded out",
            SENSE = "out of mind",
        }
        S.CHIP_FALLBACK_SPOT = "in cover"
        -- Idle pulses while braced / hiding during the command menu.
        S.AMBIENT_DELAY = 2.2
        S.AMBIENT_DELAY_JITTER = 1.0
        S.AMBIENT_BRACE_MOVES = {
            "HARDEN", "WITHDRAW", "DEFENSE_CURL", "HARDEN", "MEDITATE",
        }
        S.AMBIENT_ENTRENCH_MOVES = {
            "HARDEN", "BARRIER", "WITHDRAW", "ACID_ARMOR", "HARDEN",
        }
        -- Spot-themed loops (grass → GROWTH, dig spots → DIG, water → SURF…).
        S.AMBIENT_HIDE_MOVES = {
            GRASS = { "GROWTH", "RAZOR_LEAF", "GROWTH", "VINE_WHIP" },
            BRUSH = { "GROWTH", "RAZOR_LEAF", "STUN_SPORE" },
            TREE = { "GROWTH", "RAZOR_LEAF", "LEECH_SEED" },
            DIVE = { "SURF", "WITHDRAW", "BUBBLE", "CLAMP" },
            SPLASH = { "SURF", "WATER_GUN", "BUBBLE" },
            SHORE = { "SURF", "WATER_GUN", "SAND_ATTACK" },
            ROCK = { "DIG", "ROCK_THROW", "HARDEN" },
            STONE = { "DIG", "ROCK_THROW", "HARDEN" },
            LEDGE = { "DIG", "QUICK_ATTACK" },
            CLIFF = { "DIG", "FLY", "ROCK_SLIDE" },
            ["FLY UP"] = { "FLY", "GUST", "WING_ATTACK" },
            PATH = { "DIG", "SAND_ATTACK", "DOUBLE_TEAM" },
            CART = { "DOUBLE_TEAM", "SMOKESCREEN", "DIG" },
            ALLEY = { "SMOKESCREEN", "DOUBLE_TEAM", "DIG" },
            SHADOW = { "NIGHT_SHADE", "TELEPORT", "LICK" },
            PILLAR = { "BARRIER", "HARDEN", "REFLECT" },
            WALL = { "BARRIER", "HARDEN", "REFLECT" },
            COURT = { "DOUBLE_TEAM", "QUICK_ATTACK" },
            COVER = { "DIG", "DOUBLE_TEAM", "MINIMIZE" },
            ZIP = { "FLASH", "THUNDER_WAVE", "DOUBLE_TEAM" },
            BURST = { "SMOKESCREEN", "EMBER", "FIRE_SPIN" },
            FADE = { "TELEPORT", "NIGHT_SHADE" },
            SENSE = { "CONFUSION", "TELEPORT", "DISABLE" },
        }
        -- Entrench hold: locked stance until a counter opening (or max turns).
        S.ENTRENCH_MAX_TURNS = 3
        S.STAY_ENTRENCHED_CALLS = {
            "Stay entrenched, %s!",
            "%s! Hold the trench!",
            "Keep digging in, %s!",
            "%s! Stay firm!",
            "Don't break, %s!",
            "%s! Weather it!",
        }
        S.BREAK_ENTRENCH_CALLS = {
            "%s! Break stance!",
            "Enough- %s, move!",
            "%s! Can't hold!",
        }
        S.TRAINER_FOE_DODGE_CALLS = {
            "%s: %s, dodge!",
            "%s: Dodge it, %s!",
            "%s: %s, get aside!",
            "%s: Move, %s!",
            "%s: %s, now-dodge!",
        }
        S.FOE_DODGE_CALLS = {
            "%s! Dodge it!",
            "%s, get aside!",
            "%s! Move!",
            "Quick, %s! Dodge!",
        }
        S.TRAINER_FOE_BRACE_CALLS = {
            "%s: %s, brace!",
            "%s: Dig in, %s!",
            "%s: %s, hold firm!",
            "%s: Stand firm, %s!",
        }
        S.FOE_BRACE_CALLS = {
            "%s! Brace!",
            "%s, dig in!",
            "%s! Hold firm!",
            "Stand firm, %s!",
        }
        S.TRAINER_FOE_COUNTER_CALLS = {
            "%s: %s, hit back!",
            "%s: Counter, %s!",
            "%s: Now, %s! Strike!",
        }
        S.FOE_COUNTER_CALLS = {
            "%s! Hit back!",
            "%s! Counter!",
            "Now, %s! Strike!",
        }
        S.TRAINER_FOE_COUNTER_BACK_CALLS = {
            "%s: Too slow! %s, counter!",
            "%s: %s! Punish that!",
            "%s: Got you! Counter, %s!",
        }
        S.FOE_COUNTER_BACK_CALLS = {
            "%s! Counters!",
            "Too slow! %s hits back!",
            "%s! Punished!",
        }
        S.TRAINER_FOE_AGAIN_CALLS = {
            "%s: Again, %s!",
            "%s: %s, once more!",
            "%s: Don't stop, %s!",
            "%s: They're open! %s, again!",
            "%s: Keep going, %s!",
            "%s: %s! One more!",
            "%s: Don't let up!",
            "%s: Hit 'em again, %s!",
        }
        S.FOE_AGAIN_CALLS = {
            "%s! Again!",
            "%s, once more!",
            "Don't stop, %s!",
            "They're open! %s, again!",
            "%s! One more!",
            "Don't let up! %s!",
        }
        S.TRAINER_FOE_LEAVE_COVER_CALLS = {
            "%s: %s, break cover!",
            "%s: Come out, %s!",
            "%s: %s, now-strike!",
        }
        S.FOE_LEAVE_COVER_CALLS = {
            "%s! Break cover!",
            "Come out, %s!",
            "%s, now-strike!",
        }
        S.AGAIN_CALLS = {
            "%s! One more!",
            "Don't stop, %s!",
            "%s! Keep going!",
            "There's an opening—hit again!",
            "They're reeling—one more time!",
            "Now's your chance, %s!",
            "Don't let up, %s!",
            "Press in! %s, again!",
            "You've got them! Again!",
            "They're open—strike again!",
            "%s! Finish it!",
            "Keep up the pressure!",
            "One more hit, %s!",
            "Go again, %s!",
            "Don't give them space!",
            "You have the opening—again!",
            "%s! Hit again!",
        }
   

        local function enemyMonName(battle)
            local e = battle and battle.enemy
            if not e then
                return "POKéMON"
            end
            if e.mon and type(e.mon.nickname) == "string" and e.mon.nickname ~= "" then
                return e.mon.nickname
            end
            return e.name or "POKéMON"
        end

        -- Prefer "BROCK: Onix, dodge!" when we know the trainer; else mon order.
        local function pickFoeTrainerLine(battle, trainerTemplates, monTemplates, monName)
            monName = monName or enemyMonName(battle)
            local trainer = personalTrainerName(battle)
            if trainer and trainerTemplates then
                return pickFormatted(trainerTemplates, trainer, monName)
                    or (trainer .. ":\n" .. monName .. "!")
            end
            return pickFormatted(monTemplates, monName)
                or (monName .. "!")
        end

        -- Personality buckets from oppClass / trainer name (Gen 1 classes).
        local function trainerPersona(battle)
            local cls = tostring(battle and battle.oppClass or ""):upper()
            local name = tostring(battle and battle.trainer and battle.trainer.name or ""):upper()
            local blob = cls .. " " .. name
            local function has(s)
                return blob:find(s, 1, true) ~= nil
            end
            if has("RIVAL") then
                return "rival"
            end
            if has("ROCKET") or has("BURGLAR") or has("GIOVANNI") then
                return "evil"
            end
            if has("BROCK") or has("MISTY") or has("SURGE") or has("ERIKA")
                or has("KOGA") or has("SABRINA") or has("BLAINE")
                or has("LORELEI") or has("BRUNO") or has("AGATHA") or has("LANCE") then
                return "gym"
            end
            if has("YOUNGSTER") or has("BUG_CATCHER") or has("BUG CATCHER")
                or has("LASS") or has("JR_TRAINER") or has("JR.TRAINER")
                or has("SCHOOL") then
                return "kid"
            end
            if has("COOLTRAINER") or has("ACE") or has("BLACKBELT")
                or has("BLACKBELT") or has("BIKER") or has("CUE_BALL")
                or has("BIRD_KEEPER") or has("TAMER") then
                return "cocky"
            end
            if has("CHANNELER") or has("GHOST") then
                return "spooky"
            end
            if has("SUPER_NERD") or has("SCIENTIST") or has("POKEMANIAC")
                or has("ENGINEER") or has("PSYCHIC") then
                return "nerd"
            end
            if has("GENTLEMAN") or has("BEAUTY") or has("SAILOR")
                or has("HIKER") or has("FISHER") or has("SWIMMER") then
                return "chill"
            end
            return "generic"
        end

        local function banterSpeaker(battle)
            return personalTrainerName(battle)
                or (battle.trainer and battle.trainer.name)
                or "TRAINER"
        end

        -- speaker (+ optional mon). Persona lines when you or they send out.
        -- player lines: (speaker, your mon). enemy lines: (speaker, their mon).
        S.BANTER = {
            kid = {
                player = {
                    "%s: A %s, huh?! Looks tough!",
                    "%s: Wow, a %s!",
                    "%s: %s looks so cool!",
                    "%s: Hi, %s! Let's play!",
                    "%s: Whoa! A real %s!",
                    "%s: %s?! I want one!",
                    "%s: Your %s is awesome!",
                    "%s: Neat! A %s!",
                    "%s: Is %s your favorite?",
                    "%s: A %s... I'm nervous!",
                },
                enemy = {
                    "%s: Go, %s!",
                    "%s: Do your best, %s!",
                    "%s: I believe in %s!",
                    "%s: You can do it, %s!",
                    "%s: Show them, %s!",
                    "%s: Ready, %s?!",
                    "%s: Please win, %s!",
                    "%s: Go go go, %s!",
                },
                idle = {
                    "%s: This is fun!",
                    "%s: You're good!",
                    "%s: Nice moves!",
                    "%s: Wow!",
                    "%s: My heart's racing!",
                    "%s: Best battle ever!",
                    "%s: Don't go easy!",
                    "%s: I'm learning so much!",
                    "%s: Again! Again!",
                    "%s: This rules!",
                },
                ahead = {
                    "%s: Am I winning?!",
                    "%s: Yes! Go me!",
                    "%s: I'm doing it!",
                    "%s: See? I'm good!",
                },
                behind = {
                    "%s: Uh-oh...",
                    "%s: Wait, no fair!",
                    "%s: I can still catch up!",
                    "%s: Don't cry... focus!",
                },
                player_weak = {
                    "%s: One more? Maybe?",
                    "%s: Your mon looks tired...",
                    "%s: Hang in there!",
                },
                self_weak = {
                    "%s: Ow ow ow!",
                    "%s: We're okay! ...Right?",
                    "%s: Don't give up!",
                },
                long = {
                    "%s: So long... but cool!",
                    "%s: My legs are tired!",
                    "%s: Still going?!",
                },
            },
            cocky = {
                player = {
                    "%s: A %s? That all?",
                    "%s: %s? Hah! Weak!",
                    "%s: Don't bore me with %s!",
                    "%s: %s... Easy prey!",
                    "%s: %s? Cute. Not enough!",
                    "%s: Bringing %s? Bold.",
                    "%s: I've beaten better than %s!",
                    "%s: %s won't last a minute!",
                    "%s: Stand aside, %s!",
                    "%s: Try harder than %s next time!",
                },
                enemy = {
                    "%s: Crush them, %s!",
                    "%s: Show off, %s!",
                    "%s: No contest!",
                    "%s: Flex on them, %s!",
                    "%s: End this, %s!",
                    "%s: Make it flashy, %s!",
                    "%s: Don't blink- %s!",
                    "%s: Own the field, %s!",
                },
                idle = {
                    "%s: Too easy!",
                    "%s: Wake me when it's over!",
                    "%s: Is that it?",
                    "%s: Yawn...",
                    "%s: Speed it up!",
                    "%s: I'm barely trying!",
                    "%s: Come on, impress me!",
                    "%s: Predictable!",
                    "%s: I've seen worse... barely!",
                    "%s: Step it up!",
                },
                ahead = {
                    "%s: Outmatched!",
                    "%s: As expected!",
                    "%s: Too slow!",
                    "%s: Know your league!",
                    "%s: This is why I'm top tier!",
                    "%s: Don't look so surprised!",
                },
                behind = {
                    "%s: Hmph-fine!",
                    "%s: Don't celebrate!",
                    "%s: A fluke. Nothing more!",
                    "%s: Tch... lucky!",
                    "%s: I'm just toying with you!",
                },
                player_weak = {
                    "%s: Finish it!",
                    "%s: They're done!",
                    "%s: Tap out already!",
                    "%s: One hit left. Maybe.",
                    "%s: Smell the defeat!",
                },
                self_weak = {
                    "%s: Whatever- still winning!",
                    "%s: I meant to take that!",
                    "%s: Cute hit. My turn!",
                },
                long = {
                    "%s: Dragging this? Rude!",
                    "%s: Wrap it up!",
                    "%s: I'm getting bored again!",
                },
           
            },
            evil = {
                player = {
                    "%s: A %s...? Hand it over to Team Rocket!",
                    "%s: %s? That's nothing special!",
                    "%s: That %s is blocking our plans!",
                    "%s: Hmm, a %s... Could be valuable!",
                    "%s: %s looks easy to take!",
                    "%s: We'll wipe out %s and take what we want!",
                    "%s: Another %s to capture!",
                    "%s: Keep %s out of Team Rocket's way!",
                    "%s: %s... won't save you now!",
                    "%s: We'll steal it later. Take down %s first!",
                },
                enemy = {
                    "%s: Go, %s! Show them Team Rocket's strength!",
                    "%s: Make them regret facing us!",
                    "%s: No mercy, %s!",
                    "%s: Crush them, %s!",
                    "%s: Show no pity, %s!",
                    "%s: Attack now, %s!",
                    "%s: Obey, %s! No holding back!",
                    "%s: Make them fear Team Rocket, %s!",
                },
           
                idle = {
                    "%s: This is Team Rocket's show!",
                    "%s: Nobody outsmarts Team Rocket!",
                    "%s: Heh heh heh...",
                    "%s: You can't run from us!",
                    "%s: Your journey ends here!",
                    "%s: Team Rocket always comes out on top!",
                    "%s: Squirm a bit more for us!",
                    "%s: Crime pays—watch and learn!",
                    "%s: You'll hand over your cash eventually!",
                },
                ahead = {
                    "%s: You can't win!",
                    "%s: Just as we planned!",
                    "%s: Too easy for Team Rocket!",
                    "%s: Music to our ears!",
                    "%s: You fell for Team Rocket's trap!",
                },
                behind = {
                    "%s: This can't be...!",
                    "%s: You'll pay for that!",
                    "%s: Just a minor setback!",
                    "%s: The boss will hear about this...",
                },
                player_weak = {
                    "%s: Give up already!",
                    "%s: It's finished!",
                    "%s: Down on your knees!",
                    "%s: End them! Show no mercy!",
                    "%s: That Pokémon is done for!",
                },
                self_weak = {
                    "%s: You'll regret that!",
                    "%s: You haven't won yet!",
                    "%s: I'll double down on you!",
                },
                long = {
                    "%s: We don't have all day—lose already!",
                    "%s: A %s...? Hand it over!",
                    "%s: %s? Pathetic!",
                    "%s: That %s is in our way!",
                    "%s: Hmm, a %s... Useful!",
                    "%s: %s looks ripe for taking!",
                    "%s: We'll crush %s and move on!",
                    "%s: Another %s to break!",
                    "%s: Keep %s out of Rocket business!",
                    "%s: %s... won't save you!",
                    "%s: Steal? Later. Beat %s first!",
                },
                enemy = {
                    "%s: Get them, %s!",
                    "%s: Make it hurt!",
                    "%s: No mercy!",
                    "%s: Ruin them, %s!",
                    "%s: Show no pity, %s!",
                    "%s: Tear in, %s!",
                    "%s: Obey me, %s!",
                    "%s: Make them scream, %s!",
                },
           
                idle = {
                    "%s: Prepare to suffer!",
                    "%s: Heh heh heh...",
                    "%s: No escape!",
                    "%s: Your hopes end here!",
                    "%s: We always win in the end!",
                    "%s: Squirm a little more!",
                    "%s: Crime pays- watch!",
                },
                ahead = {
                    "%s: Yes... suffer!",
                    "%s: All according to plan!",
                    "%s: Broken already?",
                    "%s: Fall for Team Rocket!",
                },
                behind = {
                    "%s: How are you ahead? Impossible...!",
                    "%s: You'll regret that!",
                    "%s: A setback- nothing more!",
                    "%s: Boss won't like this...",
                },
                player_weak = {
                    "%s: Beg for mercy!",
                    "%s: It's over!",
                    "%s: Kneel!",
                    "%s: Finish the worm!",
                    "%s: Your mon is done!",
                },
                self_weak = {
                    "%s: How dare you!",
                    "%s: This changes nothing!",
                    "%s: I'll make you pay double!",
                },
                long = {
                    "%s: Stop stalling and lose!",
                    "%s: Our time is money!",
                    "%s: Endurance? How quaint!",
                },
           
            },
            gym = {
                player = {
                    "%s: A %s, huh? Interesting!",
                    "%s: %s... Show me its skill!",
                    "%s: So you chose %s!",
                    "%s: That %s looks trained!",
                    "%s: %s carries your pride, yes?",
                    "%s: A worthy %s. Come then!",
                    "%s: I see the care in that %s!",
                    "%s: %s... let's test its spirit!",
                    "%s: Gym rules: hold nothing back!",
                    "%s: Your %s meets my standard!",
                },
                enemy = {
                    "%s: Go, %s!",
                    "%s: This is a real battle!",
                    "%s: Don't hold back!",
                    "%s: Show our gym's strength, %s!",
                    "%s: Stand tall, %s!",
                    "%s: Earn this win, %s!",
                    "%s: Press the advantage, %s!",
                    "%s: Battle with honor, %s!",
                },
                idle = {
                    "%s: Stay focused!",
                    "%s: Good-keep it up!",
                    "%s: Not bad!",
                    "%s: Prove yourself!",
                    "%s: Read the next exchange!",
                    "%s: Breathe. Then strike!",
                    "%s: That's the spirit!",
                    "%s: Pressure makes diamonds!",
                    "%s: A Leader expects your best!",
                    "%s: Don't freeze-adapt!",
                },
                ahead = {
                    "%s: Feel the gap in skill!",
                    "%s: Push harder!",
                    "%s: This is gym-level play!",
                    "%s: Can you climb back?",
                    "%s: Experience talks!",
                },
                behind = {
                    "%s: Well done-don't stop!",
                    "%s: You've grown!",
                    "%s: Impressive...again!",
                    "%s: I won't yield easily!",
                    "%s: Good! Make me work for it!",
                },
                player_weak = {
                    "%s: Finish with pride!",
                    "%s: One decisive blow!",
                    "%s: Your mon is on the ropes!",
                },
                self_weak = {
                    "%s: A Leader still stands!",
                    "%s: Pain sharpens focus!",
                    "%s: Now it gets serious!",
                },
                long = {
                    "%s: A true test of endurance!",
                    "%s: This is a fine battle!",
                    "%s: Long battles forge trainers!",
                    "%s: Neither backing down-good!",
                },
            },
            rival = {
                player = {
                    "%s: A %s, huh?! Looks tough! ...As if!",
                    "%s: %s?! Don't make me laugh!",
                    "%s: That %s? Pathetic!",
                    "%s: Oh, a %s... Smell ya later!",
                    "%s: %s? Still weak!",
                    "%s: Hah! A %s? What a joke!",
                    "%s: Bringing %s? Outclassed!",
                    "%s: %s won't save you!",
                    "%s: %s again? Predictable!",
                    "%s: Your precious %s? Please!",
                    "%s: Gramps would laugh at %s!",
                    "%s: I outgrew %s already!",
                },
                enemy = {
                    "%s: Go! %s!",
                    "%s: Watch this!",
                    "%s: I'm the best!",
                    "%s: Show them up, %s!",
                    "%s: Crush this chump!",
                    "%s: Easy win, %s!",
                    "%s: Make it hurt, %s!",
                    "%s: Don't hold back!",
                    "%s: My %s eats losers!",
                    "%s: Style points, %s!",
                    "%s: Wipe that look off- %s!",
                    "%s: Teach them, %s!",
                },
                idle = {
                    "%s: Bored yet?",
                    "%s: I'm just warming up!",
                    "%s: You call this a fight?",
                    "%s: Try harder!",
                    "%s: Still think you can win?",
                    "%s: Hahaha!",
                    "%s: My grandpa's stronger!",
                    "%s: Give it up!",
                    "%s: You're wasting my time!",
                    "%s: Come on, make it fun!",
                    "%s: I've got places to be!",
                    "%s: Smell ya-soon!",
                    "%s: That all the fire you've got?",
                    "%s: Keep up if you can!",
                },
                ahead = {
                    "%s: Told you I was better!",
                    "%s: This is too easy!",
                    "%s: You're finished!",
                    "%s: Hah! Know your place!",
                    "%s: Maybe forfeit?",
                    "%s: I'm in a whole other league!",
                    "%s: Should've stayed home!",
                    "%s: Who's the loser now?!",
                },
                behind = {
                    "%s: Lucky shot...",
                    "%s: Don't get cocky!",
                    "%s: That won't happen again!",
                    "%s: Tch-whatever!",
                    "%s: I'm not done yet!",
                    "%s: Beginner's luck!",
                    "%s: You just got lucky, twerp!",
                    "%s: I'll wipe that grin off!",
                },
                player_weak = {
                    "%s: Look at that HP!",
                    "%s: Almost done!",
                    "%s: One more hit!",
                    "%s: Going down!",
                    "%s: Savor it-you lose!",
                    "%s: Say goodbye!",
                    "%s: Any last words?",
                },
                self_weak = {
                    "%s: N-no big deal!",
                    "%s: I meant to do that!",
                    "%s: Shut up!",
                    "%s: This isn't over!",
                    "%s: You'll pay for that!",
                    "%s: Don't you dare laugh!",
                    "%s: I was going easy!",
                },
                long = {
                    "%s: Still dragging this out?",
                    "%s: Hurry up and lose!",
                    "%s: I'm getting impatient!",
                    "%s: End this already!",
                    "%s: What, writing a novel?!",
                    "%s: Finish strong or fold!",
                },
            },
            spooky = {
                player = {
                    "%s: A %s... Ooooh...",
                    "%s: %s... Spirits stir...",
                    "%s: That %s... How dreadful!",
                    "%s: %s walks with shadows...",
                    "%s: I feel a chill from %s...",
                    "%s: %s... will you scream for us?",
                    "%s: The veil thins near %s...",
                    "%s: Such a living %s... curious!",
                },
                enemy = {
                    "%s: Rise, %s!",
                    "%s: Haunt them!",
                    "%s: From beyond...",
                    "%s: Awaken, %s!",
                    "%s: Drain their hope, %s!",
                    "%s: Whisper ruin, %s!",
                    "%s: Possess the field, %s!",
                    "%s: Night falls- %s!",
                },
                idle = {
                    "%s: I sense fear...",
                    "%s: The spirits watch...",
                    "%s: Hee hee hee...",
                    "%s: Do you hear them too?",
                    "%s: This place remembers...",
                    "%s: Your pulse is loud...",
                    "%s: Don't look behind you...",
                    "%s: Cold air...good omen!",
                    "%s: The candles flicker for you!",
                    "%s: Join us...eventually!",
                },
                ahead = {
                    "%s: Yes... sink...",
                    "%s: Your light fades!",
                    "%s: The spirits approve!",
                    "%s: Terror suits you!",
                },
                behind = {
                    "%s: Impossible warmth...!",
                    "%s: The dead grow restless!",
                    "%s: A bright spark ...annoying!",
                },
                player_weak = {
                    "%s: One step from the grave!",
                    "%s: Say goodnight!",
                    "%s: Your soul wavers!",
                },
                self_weak = {
                    "%s: Pain is only a whisper!",
                    "%s: We do not stay down!",
                    "%s: From ash...again!",
                },
                long = {
                    "%s: An endless vigil...",
                    "%s: Time means nothing here!",
                    "%s: Still bound to this duel...",
                },
            },
            nerd = {
                player = {
                    "%s: A %s! Fascinating!",
                    "%s: %s... Statistically notable!",
                    "%s: Hmm, %s... Interesting data!",
                    "%s: %s matches my models... mostly!",
                    "%s: Recording %s for science!",
                    "%s: A %s specimen! Excellent!",
                    "%s: %s's typing...intriguing!",
                    "%s: I'll need notes on that %s!",
                    "%s: Probability favors... wait!",
                    "%s: %s appears well-trained!",
                },
                enemy = {
                    "%s: Deploy %s!",
                    "%s: Optimal pick: %s!",
                    "%s: As calculated!",
                    "%s: Initialize, %s!",
                    "%s: Run protocol %s!",
                    "%s: Variable %s-engage!",
                    "%s: Hypothesis: %s wins!",
                    "%s: Field test- %s!",
                },
                idle = {
                    "%s: As expected! Just as my models predicted for this matchup.",
                    "%s: Collecting data—your tactics are worth studying in battle.",
                    "%s: Hypothesis holds! Your Pokémon fits the scenario perfectly.",
                    "%s: Recalculating... Your move changed my equation.",
                    "%s: Variance accepted! These results still fit my battle data.",
                    "%s: Noted—your technique deserves further analysis.",
                    "%s: This exchange is a fascinating clash of skill and stats.",
                    "%s: My charts anticipated your last attack.",
                    "%s: Awaiting peer review—these conclusions need more tests.",
                    "%s: Science and skill are carrying me through this fight!",
                },
           
                ahead = {
                    "%s: Result matches forecast!",
                    "%s: Superior parameters!",
                    "%s: Your error margin grows!",
                    "%s: Q.E.D.!",
                },
                behind = {
                    "%s: Anomaly detected!",
                    "%s: Recalibrate! Quickly!",
                    "%s: Outliers...humbling!",
                    "%s: I must revise my thesis!",
                },
                player_weak = {
                    "%s: Critical HP threshold!",
                    "%s: One more data point to KO!",
                    "%s: Collapse is imminent!",
                },
                self_weak = {
                    "%s: Unexpected damage spike!",
                    "%s: Still within recovery!",
                    "%s: Pain is just feedback!",
                },
                long = {
                    "%s: Sample size: getting large!",
                    "%s: A lengthy trial... good!",
                    "%s: Endurance is a variable too!",
                },
            },
            chill = {
                player = {
                    "%s: A %s, huh? Looks tough!",
                    "%s: Fine %s you've got!",
                    "%s: %s, eh? Good luck!",
                    "%s: Nice pick- %s!",
                    "%s: Respect for that %s!",
                    "%s: %s seems well cared for!",
                    "%s: A solid %s. Let's enjoy!",
                    "%s: Hey there, %s!",
                    "%s: No hard feelings either way!",
                    "%s: %s... this'll be pleasant!",
                },
                enemy = {
                    "%s: Go on, %s!",
                    "%s: Steady now!",
                    "%s: Let's enjoy this!",
                    "%s: Easy does it, %s!",
                    "%s: You've got this, %s!",
                    "%s: Smooth and steady, %s!",
                    "%s: Take your time, %s!",
                    "%s: Have fun out there, %s!",
                },
                idle = {
                    "%s: Nice pace!",
                    "%s: Well fought!",
                    "%s: Carry on!",
                    "%s: Good clean fight!",
                    "%s: Love a fair battle!",
                    "%s: No rush-do your thing!",
                    "%s: You're sharp today!",
                    "%s: This is the good stuff!",
                    "%s: Breathe in...battle out!",
                    "%s: Respect either way!",
                },
                ahead = {
                    "%s: Looks like my edge for now!",
                    "%s: Hang in-you're doing fine!",
                    "%s: I've got a bit of room!",
                },
                behind = {
                    "%s: You've got me on the ropes!",
                    "%s: Nicely done-truly!",
                    "%s: I'm impressed! Really!",
                },
                player_weak = {
                    "%s: Your mon's fading...",
                    "%s: Tough spot-stay calm!",
                    "%s: One more good hit maybe!",
                },
                self_weak = {
                    "%s: Oof-that stung!",
                    "%s: We're alright! Still in it!",
                    "%s: Shaky... but smiling!",
                },
                long = {
                    "%s: A leisurely slugfest!",
                    "%s: No place I'd rather be!",
                    "%s: Long battles are the best!",
                },
            },
            generic = {
                player = {
                    "%s: A %s, huh?! Looks tough!",
                    "%s: Oh, a %s!",
                    "%s: %s, eh? Let's battle!",
                    "%s: That %s looks ready!",
                    "%s: So it's %s! Alright!",
                    "%s: A %s... Here we go!",
                    "%s: Facing %s? Okay!",
                    "%s: Your %s looks sharp!",
                    "%s: Bring it, %s!",
                    "%s: I've trained for %s!",
                },
                enemy = {
                    "%s: Go, %s!",
                    "%s: You're up!",
                    "%s: Do it!",
                    "%s: I choose you, %s!",
                    "%s: Let's win this, %s!",
                    "%s: Trust me, %s!",
                    "%s: Now, %s!",
                    "%s: Give it your all, %s!",
                },
                idle = {
                    "%s: Come on!",
                    "%s: Let's go!",
                    "%s: Keep it up!",
                    "%s: Focus!",
                    "%s: We can do this!",
                    "%s: Stay sharp!",
                    "%s: Nice exchange!",
                    "%s: Don't blink!",
                    "%s: Push forward!",
                    "%s: Battle on!",
                },
                ahead = {
                    "%s: We've got the lead!",
                    "%s: Keep pressing!",
                    "%s: Looking good!",
                },
                behind = {
                    "%s: We're not out yet!",
                    "%s: Turn it around!",
                    "%s: Dig deep!",
                },
                player_weak = {
                    "%s: They're nearly done!",
                    "%s: Finish strong!",
                    "%s: Almost there!",
                },
                self_weak = {
                    "%s: Hold on!",
                    "%s: We can still win!",
                    "%s: Not yet!",
                },
                long = {
                    "%s: What a drawn-out fight!",
                    "%s: Endurance wins battles!",
                    "%s: Still standing-good!",
                },
            },
       
        }

        local function rollTrainerBanter()
            local r = (love and love.math and love.math.random) or math.random
            return r() < 0.70
        end

        local function battlerHpRatio(battler)
            local mon = battler and battler.mon
            local max = mon and mon.stats and mon.stats.hp
            if not max or max <= 0 then
                return 1
            end
            return (mon.hp or 0) / max
        end

        -- Build a context-weighted idle pool (ahead/behind/low HP/long fight).

        local function pickContextualIdleLine(battle, persona, speaker)
            local pack = S.BANTER[persona] or S.BANTER.generic
            local pools = {}
            local function add(list, weight)
                if type(list) ~= "table" or #list == 0 then
                    return
                end
                weight = weight or 1
                for _ = 1, weight do
                    pools[#pools + 1] = list
                end
            end
            add(pack.idle or S.BANTER.generic.idle, 1)
            local pr = battlerHpRatio(battle.player)
            local er = battlerHpRatio(battle.enemy)
            local turn = tonumber(battle.turnCount) or 0
            if er > pr + 0.18 then
                add(pack.ahead, persona == "rival" and 3 or 2)
            elseif pr > er + 0.18 then
                add(pack.behind, persona == "rival" and 3 or 2)
            end
            if pr <= 0.35 then
                add(pack.player_weak, persona == "rival" and 3 or 2)
            end
            if er <= 0.35 then
                add(pack.self_weak, persona == "rival" and 3 or 2)
            end
            if turn >= 6 then
                add(pack.long, persona == "rival" and 2 or 1)
            end
            if #pools == 0 then
                return pickFormatted(S.BANTER.generic.idle, speaker)
            end
            local r = (love and love.math and love.math.random) or math.random
            local list = pools[r(1, #pools)]
            local ms = momentumState(battle)
            -- Prefer a line we didn't just use.
            for _ = 1, 6 do
                local line = pickFormatted(list, speaker)
                if line and line ~= ms.lastIdleBanterLine then
                    return line
                end
            end
            return pickFormatted(list, speaker)
        end

        -- True send-outs only. Anime move callouts like "Go! PIKACHU!\nTHUNDER!"
        -- must NOT arm send-in banter (they share the "Go! " prefix).
        local function isPlayerSendOutText(text)
            local s = tostring(text or "")
            if s:match("^Go! [^\n]+!$")
                or s:match("^Do it! [^\n]+!$")
                or s:match("^Get'm! [^\n]+!$") then
                return true
            end
            local low = s:lower()
            return low:find("enemy's weak", 1, true) ~= nil
                and low:find("get'm!", 1, true) ~= nil
        end

        local function isEnemySendOutText(text)
            return tostring(text or ""):find("sent\nout ", 1, true) ~= nil
        end

        local maybeEnqueueSendBanter

        -- Dodge/hide cover only (EVADE / hidAway) — brace DEF must not use these lines.
        -- Dodge/hide for miss-anim / whiff text (plain sidestep counts).
        local function isDodgeCoverTemp(temp)
            if not temp or not temp.cover then
                return false
            end
            return (temp.evasion or 0) > 0 or temp.hidAway == true or temp.picHidden == true
        end

        -- Only a real hide/fly spot earns "found in cover!" — not sidestep or brace.
        local function isPierceableHideTemp(temp)
            if not temp or temp.hidAway ~= true then
                return false
            end
            -- Bracing / entrenched is a guard, not a hide.
            if temp.entrenched or ((temp.defense or 0) > 0 and (temp.evasion or 0) <= 0) then
                return false
            end
            return true
        end

        announceCoverHit = function(battle, target)
            if not opt("momentum_counter") or not battle or not target then
                return
            end
            local state = momentumByBattle[battle]
            if not state then
                return
            end
            if state.breakthroughPending and target and target.isPlayer then
                state.breakthroughPending = false
                local name = playerMonName(battle)
                local line = pickFormatted(S.BREAKTHROUGH_CALLS, name)
                    or "Broke through\nthe guard!"
                if type(battle.sayNext) == "function" then
                    battle:sayNext(line)
                    tagLatestQueueFieldCue(battle, target.isPlayer and "player" or "enemy", "hit")
                end
                -- Entrench breakthrough already narrated — don't also say "found in cover!".
                return
            end
            local inHide = false
            local name = nil
            if target.isPlayer and isPierceableHideTemp(state.temp) then
                inHide = true
                name = playerMonName(battle)
            elseif (not target.isPlayer) and isPierceableHideTemp(state.enemyTemp) then
                inHide = true
                name = enemyMonName(battle)
            end
            if not inHide then
                return
            end
            local line = pickFormatted(S.COVER_HIT_CALLS, name)
                or ("But it found\n" .. (name or "POKéMON") .. "!")
            if type(battle.sayNext) == "function" then
                battle:sayNext(line)
                tagLatestQueueFieldCue(battle, target.isPlayer and "player" or "enemy", "hit")
            end
        end

        rewriteDodgeMissText = function(battle, text)
            if type(text) ~= "string" or not text:lower():find("attack missed", 1, true) then
                return text, false
            end
            local state = battle and momentumByBattle[battle]
            if not state or not state.keepDodgeMissAnim then
                return text, false
            end
            -- Counter already armed / firing — don't revive a stale dodge-whiff line.
            if state.sameTurnCounterQueued or state.sameTurnCounterStrike
                or state.dodgeWhiffDone then
                state.keepDodgeMissAnim = false
                state.dodgeMissName = nil
                return text, false
            end
            local name = state.dodgeMissName or "POKéMON"
            state.keepDodgeMissAnim = false
            state.dodgeMissName = nil
            state.dodgeWhiffDone = true
            local line = pickFormatted(S.DODGE_WHIFF_CALLS, name)
                or ("But " .. name .. "\ndodged aside!")
            -- Signal wrapBattleSay to park COUNTER! after this miss line + anim.
            return line, true
        end

        -- Drop orphaned dodge-miss lines that somehow landed after COUNTER!.
        local function scrubLateDodgeWhiff(battle)
            local state = battle and momentumByBattle[battle]
            if state then
                state.keepDodgeMissAnim = false
                state.dodgeMissName = nil
                state.dodgeWhiffDone = true
            end
            local q = battle and battle.queue
            if type(q) ~= "table" then
                return
            end
            for i = #q, 1, -1 do
                local row = q[i]
                if type(row) == "table" and type(row.text) == "string" then
                    local t = row.text:lower()
                    if row.arDodgeWhiff
                        or t:find("attack missed", 1, true)
                        or t:find("dodged aside", 1, true)
                        or t:find("slipped", 1, true) and t:find("away", 1, true)
                        or t:find("whiffed past", 1, true)
                        or t:find("safe in cover", 1, true) then
                        table.remove(q, i)
                        if battle.nextInsert and i <= battle.nextInsert then
                            battle.nextInsert = math.max(0, battle.nextInsert - 1)
                        end
                    end
                end
            end
        end

        local function trainerFoeReactionsOn(battle)
            if not opt("momentum_counter") or not battle then
                return false
            end
            local kind = battle.kind
            return kind == "trainer" or kind == "link"
        end

        -- Auto foe dodge/brace once per turn when you attack (trainer battles).
        -- Returns reactionText, buffList, trackTempBuffs, failNarrator.
        -- On a failed dodge: reactionText is still the trainer order (bubble), and
        -- failNarrator is the bottom-box "...but it was too slow!" (no bubble).
        local function tryFoeCoverReaction(battle, moveDef)
            if not trainerFoeReactionsOn(battle) or not moveDef then
                return nil
            end
            if (moveDef.power or 0) <= 0 or moveDef.category == "status" then
                return nil
            end
            -- Frozen / asleep foes can't take dodge/brace orders.
            if enemyStatusLocked(battle) then
                return nil
            end
            local state = momentumState(battle)
            if state.enemyReactedThisTurn then
                return nil
            end
            state.enemyReactedThisTurn = true
            local foe = enemyMonName(battle)
            if foeMoveIsSpecial(moveDef) then
                local line = pickFoeTrainerLine(
                    battle, S.TRAINER_FOE_DODGE_CALLS, S.FOE_DODGE_CALLS, foe)
                if not rollDodgeSuccess() then
                    dev.log(battle, "FOE dodge", "FAIL")
                    if line then
                        return line, nil, false, S.DODGE_TOO_SLOW
                    end
                    return S.DODGE_TOO_SLOW, nil, false, nil
                end
                state.enemyTemp.cover = true
                dev.log(battle, "FOE dodge", "OK EV+1")
                return line, {
                    { who = "enemy", stat = "evasion", delta = 1 },
                }, true, nil
            end
            -- Brace is a guard, not a hide — don't mark dodge cover.
            local line = pickFoeTrainerLine(
                battle, S.TRAINER_FOE_BRACE_CALLS, S.FOE_BRACE_CALLS, foe)
            dev.log(battle, "FOE brace", "OK DF+1")
            return line, {
                { who = "enemy", stat = "defense", delta = 1 },
            }, true, nil
        end

        local function rollEnemyCounter()
            local r = (love and love.math and love.math.random) or math.random
            return r() < 0.50
        end

        local function rollEnemyAgain()
            local r = (love and love.math and love.math.random) or math.random
            return r() < 0.40
        end

        -- Player-facing pick options per scene (label shown in menu).
        S.SCENE_PICK = {
            cave = {
                { label = "ROCK",  line = "%s!\nOnto that rock!", boost = 2 },
                { label = "LEDGE", line = "%s!\nUp that ledge!",  boost = 2 },
                { label = "DODGE", line = "%s!\nDodge it!",       boost = 1 },
            },
            forest = {
                { label = "TREE",  line = "%s!\nBehind that tree!", boost = 2 },
                { label = "BRUSH", line = "%s!\nInto the brush!",   boost = 2 },
                { label = "DODGE", line = "%s!\nDodge it!",         boost = 1 },
            },
            city = {
                { label = "CART",  line = "%s!\nBehind that cart!", boost = 2 },
                { label = "ALLEY", line = "%s!\nUse that alley!",   boost = 2 },
                { label = "DODGE", line = "%s!\nDodge it!",         boost = 1 },
            },
            route = {
                { label = "GRASS", line = "%s!\nInto the grass!", boost = 2 },
                { label = "PATH",  line = "%s!\nOff the path!",   boost = 1 },
                { label = "DODGE", line = "%s!\nDodge it!",       boost = 1 },
            },
            mountain = {
                { label = "CLIFF", line = "%s!\nUp that cliff!", boost = 2 },
                { label = "LEDGE", line = "%s!\nUse the ledge!", boost = 2 },
                { label = "DODGE", line = "%s!\nDodge it!",      boost = 1 },
            },
            gym = {
                { label = "PILLAR", line = "%s!\nUse the pillars!",  boost = 2 },
                { label = "COURT",  line = "%s!\nAround the court!", boost = 1 },
                { label = "DODGE",  line = "%s!\nDodge it!",         boost = 1 },
            },
            water = {
                { label = "SHORE",  line = "%s!\nAlong the shore!", boost = 2 },
                { label = "SPLASH", line = "%s!\nSplash aside!",    boost = 2 },
                { label = "DODGE",  line = "%s!\nDodge it!",        boost = 1 },
            },
            grave = {
                { label = "STONE",  line = "%s!\nBehind a stone!", boost = 2 },
                { label = "SHADOW", line = "%s!\nInto the dark!",  boost = 2 },
                { label = "DODGE",  line = "%s!\nDodge it!",       boost = 1 },
            },
            indoor = {
                { label = "WALL",  line = "%s!\nUse the wall!", boost = 2 },
                { label = "COVER", line = "%s!\nBehind cover!", boost = 2 },
                { label = "DODGE", line = "%s!\nDodge it!",     boost = 1 },
            },
        }
        S.SCENE_BRACE_PICK = {
            cave = {
                { label = "ROCK",   line = "%s!\nBrace on the rock!", boost = 2 },
                { label = "DIG IN", line = "%s!\nDig in here!",       boost = 2 },
                { label = "BRACE",  line = "%s!\nBrace yourself!",    boost = 1 },
            },
            forest = {
                { label = "ROOTS", line = "%s!\nRoot in place!",  boost = 2 },
                { label = "HOLD",  line = "%s!\nHold the line!",  boost = 1 },
                { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
            },
            city = {
                { label = "STREET", line = "%s!\nHold the street!",   boost = 2 },
                { label = "GROUND", line = "%s!\nStand your ground!", boost = 1 },
                { label = "BRACE",  line = "%s!\nBrace yourself!",    boost = 1 },
            },
            route = {
                { label = "PATH",   line = "%s!\nHold the path!",  boost = 1 },
                -- Strong brace: high DEF, but next attack is locked out (body-agnostic).
                { label = "DIG IN", line = "%s!\nEntrench!",       boost = 2, entrench = true },
                { label = "BRACE",  line = "%s!\nBrace yourself!", boost = 1 },
            },
            mountain = {
                { label = "STONE", line = "%s!\nBrace on stone!", boost = 2 },
                { label = "HOLD",  line = "%s!\nDon't slip!",     boost = 1 },
                { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
            },
            gym = {
                { label = "COURT", line = "%s!\nCenter court-hold!", boost = 2 },
                { label = "GUARD", line = "%s!\nGuard the mark!",    boost = 1 },
                { label = "BRACE", line = "%s!\nBrace yourself!",    boost = 1 },
            },
            water = {
                { label = "SURF",  line = "%s!\nBrace in the surf!", boost = 2 },
                { label = "TIDE",  line = "%s!\nHold the tide!",     boost = 1 },
                { label = "BRACE", line = "%s!\nBrace yourself!",    boost = 1 },
            },
            grave = {
                { label = "STAND", line = "%s!\nStand your ground!", boost = 1 },
                { label = "HOLD",  line = "%s!\nDon't yield!",       boost = 2 },
                { label = "BRACE", line = "%s!\nBrace yourself!",    boost = 1 },
            },
            indoor = {
                { label = "ROOM",  line = "%s!\nHold the room!", boost = 1 },
                { label = "BRACE", line = "%s!\nBrace up!",      boost = 1 },
                { label = "GUARD", line = "%s!\nGuard up!",      boost = 2 },
            },
        }
        S.TYPE_PICK_EXTRA = {
            FLYING = { label = "FLY UP", line = "%s!\nFly up high!", boost = 2 },
            WATER = { label = "DIVE", line = "%s!\nDive aside!", boost = 2 },
            ELECTRIC = { label = "ZIP", line = "%s!\nZip aside!", boost = 2 },
            FIRE = { label = "BURST", line = "%s!\nBurst aside!", boost = 2 },
            PSYCHIC = { label = "SENSE", line = "%s!\nSense-and move!", boost = 2 },
            GHOST = { label = "FADE", line = "%s!\nFade through!", boost = 2 },
            GRASS = { label = "BRUSH", line = "%s!\nInto the leaves!", boost = 2 },
        }

        local MoveEffects = require("src.battle.MoveEffects")
        local Menu = require("src.ui.Menu")
        -- Engine damage pipeline. Wrapped so Reactive Defense can defer a hit
        -- for the REACT menu / auto-counter. Not a Stadium package.
        local EffectRegistry = require("src.battle.EffectRegistry")
        -- Capture the engine function once. Hot-reload used to chain wraps so
        -- finishCalloutPick → origRunDamaging re-entered an OLD wrap that still
        -- queued REACT! (often with a stale HUD draw closure).
        local function ensureVanillaRunDamaging()
            local stored = EffectRegistry._arVanillaRunDamaging
            local liveWrap = EffectRegistry._arReactRunDamaging
            -- Ignore a stored value that is actually our previous wrap.
            if type(stored) == "function" and stored ~= liveWrap then
                return stored
            end
            local vanilla = EffectRegistry.runDamaging
            -- If runDamaging is already our wrap (hot reload), keep any prior vanilla.
            if vanilla == liveWrap and type(stored) == "function" then
                vanilla = stored
            end
            EffectRegistry._arVanillaRunDamaging = vanilla
            return vanilla
        end
        local origRunDamaging = ensureVanillaRunDamaging()

        -- Callout pages need a beat so they aren't instant.
        S.CALLOUT_AUTO_DELAY = 55
        -- Trainer slides on-screen while their banter line plays.
        S.BANTER_CAMEO_IN = 14
        S.BANTER_CAMEO_OUT = 12
        -- 3D-BTL: orbit toward side-on (0..1) while the trainer talks.
        S.BANTER_CAMEO_ORBIT = 0.38
        -- Speech bubbles: slower glyphs; after typing they wait for A/B (no auto).
        S.BUBBLE_AUTO_DELAY = 75 -- kept for non-bubble fallbacks / legacy callers
        -- Effective frames/glyph while a bubble is up (engine slow is 5).
        S.BUBBLE_CHAR_DELAY = 7
        -- FIELD: ~1.5s hold after each condensed toast finishes typing.
        S.FIELD_TOAST_DELAY = 90

        local function fieldFlowsText(battle)
            return type(battle) == "table"
                and (battle._arAnimeField or battle._arFieldCombat
                    or battle._arFieldStandalone)
        end

        local function liveFieldSession(battle)
            if not (FieldBattleViewer and type(FieldBattleViewer.session) == "function") then
                return nil
            end
            local session = FieldBattleViewer.session(battle)
            if session and session.live then
                return session
            end
            return nil
        end

        -- FIELD NPC shouts (banter, move orders) ride the reaction overlay.
        -- The engine text box keeps vanilla narrative only.
        local function isNpcTrainerSpeech(text)
            local Callouts = FieldBattleViewer and FieldBattleViewer.Callouts
            if Callouts and type(Callouts.isTrainerSpeech) == "function" then
                return Callouts.isTrainerSpeech(text)
            end
            return tostring(text or ""):match("^[%w%.%s']+:") ~= nil
        end

        local function pushNpcCallout(battle, text, force, opts)
            if not fieldFlowsText(battle) then
                return false
            end
            text = tostring(text or ""):match("^%s*(.-)%s*$") or ""
            if text == "" then
                return false
            end
            if not force and not isNpcTrainerSpeech(text) then
                return false
            end
            local Callouts = FieldBattleViewer and FieldBattleViewer.Callouts
            local session = liveFieldSession(battle)
            if not (Callouts and session and type(Callouts.push) == "function") then
                return false
            end
            return Callouts.push(session, "foe", text, opts) == true
        end

        -- original() may promote the announce to battle.current and leave
        -- nextInsert pointing at the next hole. Find the row we just submitted.
        local function stampNpcOrderOnAnnounce(battle, narrative, order)
            if type(battle) ~= "table" or not order then
                return false
            end
            local function stamp(item)
                if type(item) ~= "table" then
                    return false
                end
                item.arNpcCallout = order
                item.arNpcCalloutKind = "order"
                return true
            end
            local want = tostring(narrative or "")
            local function matches(item)
                return type(item) == "table" and tostring(item.text or "") == want
            end
            if matches(battle.queue and battle.queue[battle.nextInsert]) then
                return stamp(battle.queue[battle.nextInsert])
            end
            if matches(battle.current) then
                return stamp(battle.current)
            end
            local q = battle.queue
            if type(q) == "table" then
                for i = 1, #q do
                    if matches(q[i]) then
                        return stamp(q[i])
                    end
                end
            end
            return false
        end

        local function applyFieldToastAuto(item)
            if type(item) ~= "table" then
                return
            end
            item.auto = true
            item.autoDelay = S.FIELD_TOAST_DELAY
        end

        local function enqueuePromptAfter(battle, text)
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return
            end
            battle.nextInsert = (battle.nextInsert or 0) + 1
            table.insert(battle.queue, battle.nextInsert, { text = text })
        end

        -- Route battle dialogue into player / foe / narrator bubbles.
        local function inferBubbleSide(battle, text)
            if not opt("speech_bubbles") then
                return nil
            end
            local s = tostring(text or "")
            if s == "" then
                return nil
            end
            local mon = parseUsedMoveText(s)
            if mon then
                -- FIELD: "Enemy X used Y!" is narrator. Trainer orders go on
                -- the tinted foe strip so the same event is not painted twice.
                if fieldFlowsText(battle) then
                    return "narrator"
                end
                local _, isEnemy = stripEnemyPrefix(mon)
                if isEnemy then
                    return enemyStatusLocked(battle) and "narrator" or "foe"
                end
                return playerStatusLocked(battle) and "narrator" or "player"
            end
            local trainer = personalTrainerName(battle)
            if trainer and #trainer > 0 and s:sub(1, #trainer + 1) == (trainer .. ":") then
                return "foe"
            end
            local lower = s:lower()
            local narrHints = {
                "faint", "hurt by", "asleep", "frozen", "paralyz", "poison",
                "burn", "attack missed", "doesn't affect", "critical",
                "effective", "dodged", "whiffed", "came to", "woke up",
                "too slow", "couldn't dodge", "found ", "hit through",
                "about to use", "change pok",
            }
            for i = 1, #narrHints do
                if lower:find(narrHints[i], 1, true) then
                    return "narrator"
                end
            end
            local me = playerMonName(battle)
            if me ~= "" and (s:find(me .. "!", 1, true) == 1
                    or s:find(me .. "\n", 1, true) == 1
                    or s:find(me .. " ", 1, true) == 1) then
                return playerStatusLocked(battle) and "narrator" or "player"
            end
            local foe = enemyMonName(battle)
            if foe ~= "" and (s:find("Enemy " .. foe, 1, true)
                    or s:find(foe .. "!", 1, true) == 1
                    or s:find(foe .. "\n", 1, true) == 1) then
                return "foe"
            end
            if s:find("Enemy ", 1, true) == 1 then
                return "narrator"
            end
            return "narrator"
        end

        -- Tag a queue item as a bubble. forceWait (default true) clears auto so
        -- the player can finish reading before A/B — needed once the classic box
        -- is hidden. FIELD battles keep short auto toasts instead.
        local function markBubbleWait(item, bubble, forceWait, battle)
            if type(item) ~= "table" or not bubble or not opt("speech_bubbles") then
                return false
            end
            item.bubble = bubble
            if fieldFlowsText(battle) then
                applyFieldToastAuto(item)
                return true
            end
            if forceWait ~= false then
                item.auto = nil
                item.autoDelay = nil
            end
            return true
        end

        -- Field-battle sprite cue: lifecycle plays this when the row is current.
        -- kind: dodge | cover | brace | attack | hit | selfhit | faint
        -- category (optional): physical | special — drives pad step vs cast-in-place.
        tagFieldCue = function(item, side, kind, category, moveType, moveId)
            if type(item) ~= "table" or not side or not kind then
                return false
            end
            item.arFieldCue = { side = side, kind = kind }
            if category == "physical" or category == "special" then
                item.arFieldCue.category = category
            end
            item.arFieldCue.moveType = moveType
            item.arFieldCue.moveId = moveId
            -- Soft reddish dialogue fill while a foe damaging move is announced.
            if side == "enemy" and kind == "attack" then
                item.arThreatToast = true
            end
            return true
        end

        tagLatestQueueFieldCue = function(battle, side, kind, category, moveType, moveId)
            if not (battle and battle.queue and battle.nextInsert) then
                return false
            end
            return tagFieldCue(
                battle.queue[battle.nextInsert], side, kind, category, moveType, moveId)
        end

        fieldCueForFoeCover = function(foeBuffs, foeLine)
            if isDodgeFailNarrator(foeLine) then
                return { side = "enemy", kind = "hit" }
            end
            if type(foeBuffs) == "table" then
                for i = 1, #foeBuffs do
                    local b = foeBuffs[i]
                    if b and b.stat == "defense" then
                        return { side = "enemy", kind = "brace" }
                    end
                    if b and b.stat == "evasion" then
                        return { side = "enemy", kind = "dodge" }
                    end
                end
            end
            return { side = "enemy", kind = "dodge" }
        end

        local function enqueueAutoAfter(battle, text, delay, bubble, fieldCue)
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return
            end
            battle.nextInsert = (battle.nextInsert or 0) + 1
            local item = { text = text }
            -- With bubbles on, untagged lines become narrator (no classic text box).
            if bubble == nil and opt("speech_bubbles") then
                bubble = inferBubbleSide(battle, text) or "narrator"
            end
            if fieldFlowsText(battle) then
                applyFieldToastAuto(item)
                markBubbleWait(item, bubble, false, battle)
            elseif not markBubbleWait(item, bubble, true, battle) then
                item.auto = true
                item.autoDelay = delay or S.CALLOUT_AUTO_DELAY
            end
            if type(fieldCue) == "table" then
                tagFieldCue(item, fieldCue.side, fieldCue.kind, fieldCue.category)
            end
            table.insert(battle.queue, battle.nextInsert, item)
        end

        -- FIELD: pin a dodge/brace/cover onto the live attack toast so cues.lua
        -- can play it on the same beat (issue #10). Classic battles stay queued.
        local function attachOverlapReact(battle, react)
            if not fieldFlowsText(battle) or type(react) ~= "table" then
                return false
            end
            local function isAttackRow(row)
                local cue = row and row.arFieldCue
                if not cue then
                    return false
                end
                return cue.kind == "attack" or cue.kind == "status"
            end
            local row = battle.queue and battle.queue[battle.nextInsert]
            if not isAttackRow(row) then
                row = battle.current
            end
            if not isAttackRow(row) then
                local q = battle.queue
                if type(q) == "table" then
                    for i = 1, #q do
                        if isAttackRow(q[i]) then
                            row = q[i]
                            break
                        end
                    end
                end
            end
            if not isAttackRow(row) then
                return false
            end
            row.arOverlapReact = row.arOverlapReact or {}
            row.arOverlapReact[#row.arOverlapReact + 1] = react
            return true
        end

        local function enqueueReactWithAttack(battle, text, delay, bubble, fieldCue)
            local kind = fieldCue and fieldCue.kind
            local foeOrder = fieldCue and fieldCue.side == "enemy"
                and isNpcTrainerSpeech(text)
            if fieldFlowsText(battle) and fieldCue
                and (kind == "dodge" or kind == "cover" or kind == "hide"
                    or kind == "brace") then
                if foeOrder and attachOverlapReact(battle, {
                    side = fieldCue.side,
                    kind = kind,
                    text = text,
                    bubble = bubble,
                }) then
                    return true
                end
                if not foeOrder then
                    -- Player / narrator reacts stay in the vanilla box.
                    attachOverlapReact(battle, {
                        side = fieldCue.side,
                        kind = kind,
                    })
                    enqueueAutoAfter(battle, text, delay, "narrator")
                    return true
                end
            end
            enqueueAutoAfter(battle, text, delay, bubble, fieldCue)
            return false
        end

        local function enqueueNpcFlavor(battle, text, delay, fieldCue)
            if pushNpcCallout(battle, text, true, { kind = "react", urgent = true }) then
                return true
            end
            enqueueAutoAfter(battle, text, delay, "foe", fieldCue)
            return false
        end

        local function queueHasPoof(battle)
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return false
            end
            for i = 1, #battle.queue do
                local row = battle.queue[i]
                if row and row.anim == "POOF_ANIM" then
                    return true
                end
            end
            return false
        end

        local function queueHasBanter(battle)
            if type(battle) ~= "table" then
                return false
            end
            if battle.current and battle.current.arBanter then
                return true
            end
            local q = battle.queue
            if type(q) ~= "table" then
                return false
            end
            for i = 1, #q do
                if q[i] and q[i].arBanter then
                    return true
                end
            end
            return false
        end

        -- Battle box is 2 lines; extra \n scrolls like separate callouts.
        local function clampBanterText(line)
            local parts = {}
            for chunk in (tostring(line or "") .. "\n"):gmatch("(.-)\n") do
                chunk = chunk:match("^%s*(.-)%s*$") or chunk
                if chunk ~= "" then
                    parts[#parts + 1] = chunk
                end
            end
            if #parts <= 2 then
                return table.concat(parts, "\n")
            end
            local speaker = parts[1]
            local body = table.concat(parts, " ", 2)
            if fitsBattleLine(body) then
                return speaker .. "\n" .. body
            end
            return speaker .. "\n" .. parts[2]
        end

        maybeEnqueueSendBanter = function(battle, originalText)
            if not opt("trainer_banter") or not trainerFoeReactionsOn(battle) then
                return
            end
            if type(battle) ~= "table" then
                return
            end
            local aboutPlayer = isPlayerSendOutText(originalText)
            local aboutEnemy = isEnemySendOutText(originalText)
            if not aboutPlayer and not aboutEnemy then
                return
            end
            -- Pending / cooldown live on the battle object so they survive
            -- clearBattleMomentum (battle.started) and stay shared across any
            -- accidental double-wraps of say / updateQueue from hot reload.
            -- Prefer the player's Go! when both foe-send and Go! land in one wave.
            local replacing = battle._arPendingSendBanter
                and aboutPlayer
                and battle._arPendingSendBanter.side == "enemy"
            if battle._arPendingSendBanter and not replacing then
                return
            end
            if not replacing then
                if (battle._arSendBanterCooldown or 0) > 0 then
                    return
                end
                if queueHasBanter(battle) then
                    return
                end
                if not rollTrainerBanter() then
                    return
                end
            end
            -- Do not bake the mon name here. The engine's "Go!" names party[1]
            -- (often the overworld follower). choose_lead and other send-out
            -- mods rebind battle.player after that line is queued.
            battle._arPendingSendBanter = {
                side = aboutPlayer and "player" or "enemy",
                persona = trainerPersona(battle),
                speaker = banterSpeaker(battle),
            }
            battle._arSendBanterArmFrames = 8
            if aboutPlayer and battle.sendingOut then
                battle._arSendBanterSawOut = true
                battle._arSendBanterArmFrames = nil
            elseif aboutEnemy and battle.enemySendingOut then
                battle._arSendBanterSawOut = true
                battle._arSendBanterArmFrames = nil
            end
        end
        -- Banter cameo: slide the enemy trainer pic in from the right while their
        -- line is up. Flat battles draw in battle.overlay. Under 3D-BTL the fight
        -- is in the world — briefly show the intro trainer on the enemy billboard
        -- and ease the camera toward that side. Packed as one table for LuaJIT.
        local BanterCameo = {}
        BanterCameo.OW_MODS = { "DRAMATIC_SHAPE", "potato_voxel" }

        function BanterCameo.owLive(battle)
            if type(battle) ~= "table" or not mod.find then
                return false
            end
            for i = 1, #BanterCameo.OW_MODS do
                local handle = mod.find(BanterCameo.OW_MODS[i])
                local lib = handle and handle.exports and handle.exports.lib
                if lib and type(lib.require) == "function" then
                    local ok, OW = pcall(lib.require, "OverworldBattle")
                    if ok and type(OW) == "table" and type(OW.enabled) == "function"
                        and OW.enabled() then
                        -- Only when this fight is actually staged on the map.
                        local staged = true
                        if type(OW.shot) == "function" then
                            staged = OW.shot() and true or false
                        end
                        if staged and type(OW.battle) == "function" then
                            local live = OW.battle()
                            if live and live ~= battle then
                                staged = false
                            end
                        end
                        if staged then
                            return true, lib
                        end
                    end
                end
            end
            return false
        end

        function BanterCameo.armCam(lib, cameo)
            if not (lib and cameo and type(lib.require) == "function") then
                return false
            end
            local ok, Cam = pcall(lib.require, "BattleCam")
            if not (ok and type(Cam) == "table") then
                return false
            end
            -- BACK SPRITES pins half the composition; swinging breaks it.
            if Cam.steerable == false then
                return false
            end
            cameo.cam = Cam
            cameo.prevOrbitGoal = tonumber(Cam.orbitGoal) or 0
            cameo.prevPitchGoal = tonumber(Cam.pitchGoal) or 0
            -- Mild nudge — hard side-on swung the foe/trainer out of frame.
            local target = S.BANTER_CAMEO_ORBIT or 0.38
            if (cameo.prevOrbitGoal or 0) < target then
                Cam.orbitGoal = target
            end
            cameo.cameoOrbit = Cam.orbitGoal
            return true
        end

        function BanterCameo.releaseCam(cameo)
            local Cam = cameo and cameo.cam
            if not Cam then
                return
            end
            if cameo.prevOrbitGoal ~= nil then
                Cam.orbitGoal = cameo.prevOrbitGoal
            end
            if cameo.prevPitchGoal ~= nil then
                Cam.pitchGoal = cameo.prevPitchGoal
            end
            cameo.cam = nil
        end

        -- 3D-BTL: put the trainer on the enemy world billboard (same seam as the
        -- battle intro).
        function BanterCameo.showTrainer(battle, cameo)
            if not (battle and cameo and cameo.ow) or cameo.forcedTrainer then
                return
            end
            if not (battle.trainerPic or battle.enemyTrainerImage) then
                return
            end
            cameo.prevShowEnemyTrainer = battle.showEnemyTrainer and true or false
            battle.showEnemyTrainer = true
            cameo.forcedTrainer = true
        end

        function BanterCameo.hideTrainer(battle, cameo)
            if not (battle and cameo and cameo.forcedTrainer) then
                return
            end
            battle.showEnemyTrainer = cameo.prevShowEnemyTrainer and true or false
            cameo.forcedTrainer = false
        end

        function BanterCameo.image(battle)
            if type(battle) ~= "table" then
                return nil
            end
            local img = battle.enemyTrainerImage or battle.trainerPic
            if not img then
                return nil
            end
            if type(battle.picImage) == "function" and battle.trainerPic then
                local ok, painted = pcall(battle.picImage, battle, battle.trainerPic)
                if ok and painted then
                    return painted
                end
            end
            return img
        end

        function BanterCameo.stillShowing(battle, line)
            if type(battle) ~= "table" then
                return false
            end
            local session = liveFieldSession(battle)
            local overlays = session and session._trainerCallouts
            if overlays and overlays.foe and #overlays.foe > 0 then
                return true
            end
            local cur = battle.current
            if cur and cur.arBanter then
                return true
            end
            if line and cur and cur.text == line then
                return true
            end
            if line and battle._arLastBubbleText == line then
                return true
            end
            return false
        end

        function BanterCameo.progress(cameo)
            if not cameo then
                return 0
            end
            local t
            if cameo.mode == "in" then
                local dur = S.BANTER_CAMEO_IN or 14
                t = math.min(1, (cameo.frame or 0) / math.max(1, dur))
            elseif cameo.mode == "out" then
                local dur = S.BANTER_CAMEO_OUT or 12
                t = 1 - math.min(1, (cameo.frame or 0) / math.max(1, dur))
            else
                t = 1
            end
            return t * t * (3 - 2 * t)
        end

        function BanterCameo.start(battle, line)
            if not opt("trainer_banter") or not trainerFoeReactionsOn(battle) then
                return
            end
            if battle.showEnemyTrainer then
                return
            end
            local ow = BanterCameo.owLive(battle)
            if not ow and not BanterCameo.image(battle) then
                return
            end
            if ow and not (battle.trainerPic or battle.enemyTrainerImage) then
                return
            end
            local state = momentumState(battle)
            state.banterCameoWanted = line or true
        end

        function BanterCameo.tick(battle)
            if type(battle) ~= "table" then
                return
            end
            local state = momentumByBattle[battle]
            if not state then
                return
            end
            local cameo = state.banterCameo
            local wanted = state.banterCameoWanted
            local cur = battle.current

            local session = liveFieldSession(battle)
            local foeToasts = session and session._trainerCallouts
                and session._trainerCallouts.foe
            local overlayBanter = type(foeToasts) == "table" and #foeToasts > 0
            if not cameo and wanted and (overlayBanter or (cur and cur.arBanter)) then
                if not battle.showEnemyTrainer then
                    local ow, lib = BanterCameo.owLive(battle)
                    if ow or BanterCameo.image(battle) then
                        state.banterCameo = {
                            mode = "in",
                            frame = 0,
                            line = (wanted ~= true and wanted)
                                or (cur and cur.text) or nil,
                            ow = ow and true or false,
                        }
                        cameo = state.banterCameo
                        if ow then
                            BanterCameo.armCam(lib, cameo)
                            BanterCameo.showTrainer(battle, cameo)
                        end
                    end
                end
                state.banterCameoWanted = nil
            end

            if not cameo then
                return
            end

            -- Keep the banter orbit pinned while the line is up (player steer can
            -- fight it otherwise).
            if cameo.ow and cameo.cam and cameo.mode ~= "out" and cameo.cameoOrbit then
                cameo.cam.orbitGoal = cameo.cameoOrbit
            end

            if cameo.mode == "in" then
                cameo.frame = (cameo.frame or 0) + 1
                if cameo.frame >= (S.BANTER_CAMEO_IN or 14) then
                    cameo.mode = "hold"
                    cameo.frame = 0
                end
            elseif cameo.mode == "hold" then
                if not BanterCameo.stillShowing(battle, cameo.line) then
                    cameo.mode = "out"
                    cameo.frame = 0
                    BanterCameo.releaseCam(cameo)
                end
            elseif cameo.mode == "out" then
                cameo.frame = (cameo.frame or 0) + 1
                if cameo.frame >= (S.BANTER_CAMEO_OUT or 12) then
                    BanterCameo.hideTrainer(battle, cameo)
                    BanterCameo.releaseCam(cameo)
                    state.banterCameo = nil
                end
            end
        end

        function BanterCameo.draw(battle)
            if not opt("trainer_banter") then
                return
            end
            local state = battle and momentumByBattle[battle]
            local cameo = state and state.banterCameo
            if not cameo or not love or not love.graphics then
                return
            end
            -- 3D-BTL: trainer is on the world billboard via showEnemyTrainer.
            if cameo.ow then
                return
            end
            if battle.showEnemyTrainer then
                return
            end
            local img = BanterCameo.image(battle)
            if not img or type(img.getDimensions) ~= "function" then
                return
            end

            local t = BanterCameo.progress(cameo)
            if t <= 0 then
                return
            end

            local iw, ih = img:getDimensions()
            -- Same enemy-intro box Gen 2 / Gen3 switch overlay uses: tile (12,0), 7×7.
            local boxX, boxY, boxSize = 96, 0, 56
            local scale = 1
            if type(battle.picScale) == "function" then
                local path = battle.enemyTrainerPath
                    or (battle.trainer and (battle.trainer.picJessieJames or battle.trainer.pic))
                local ok, value = pcall(battle.picScale, battle, path, nil, false)
                if ok and tonumber(value) then
                    scale = tonumber(value)
                end
            end
            local px = boxX + (boxSize - iw * scale) / 2
            local py = boxY + (boxSize - ih * scale)
            px = px + (1 - t) * boxSize

            local g = love.graphics
            g.push("all")
            g.setColor(1, 1, 1, 1)
            local drew = false
            local okPal, Palettes = pcall(require, "src.world.gen2.Palettes")
            local okGbc, GbcPalette = pcall(require, "src.render.GbcPalette")
            local class = battle.enemyTrainerClass
                or (battle.trainer and (battle.trainer.class or battle.trainer.id))
            local colors = okPal and battle.palettes and type(Palettes.trainerColors) == "function"
                and Palettes.trainerColors(battle.palettes, class) or nil
            local function body()
                g.draw(img, px, py, 0, scale, scale)
            end
            if colors and okGbc and GbcPalette and type(GbcPalette.with) == "function"
                and (type(GbcPalette.available) ~= "function" or GbcPalette.available()) then
                drew = pcall(GbcPalette.with, colors, body)
            end
            if not drew then
                body()
            end
            g.pop()
        end

        local function flushPendingSendBanter(battle)
            if type(battle) ~= "table" then
                return
            end
            if (battle._arSendBanterCooldown or 0) > 0 then
                battle._arSendBanterCooldown = battle._arSendBanterCooldown - 1
            end
            local pending = battle._arPendingSendBanter
            if not pending then
                return
            end

            local function pickerOpen()
                local stack = battle.game and battle.game.stack
                if not (stack and type(stack.top) == "function") then
                    return false
                end
                local top = stack:top()
                if not top or top == battle then
                    return false
                end
                if top.battle ~= nil and top.battle ~= battle then
                    return false
                end
                if top.forceSwitch then
                    return true
                end
                local id = tostring(top.id or top.screenId or "")
                if id == "PartyMenu" or id == "Gen2PartyMenu" then
                    return top.forceSwitch == true or top.battle == battle
                end
                return false
            end

            local function queueStillHasSendOut()
                local function match(text)
                    if pending.side == "player" then
                        return isPlayerSendOutText(text)
                    end
                    return isEnemySendOutText(text)
                end
                if battle.current and match(battle.current.text) then
                    return true
                end
                local q = battle.queue
                if type(q) ~= "table" then
                    return false
                end
                for i = 1, #q do
                    if q[i] and match(q[i].text) then
                        return true
                    end
                end
                return false
            end

            local function composeLine()
                local persona = pending.persona or trainerPersona(battle)
                local pack = S.BANTER[persona] or S.BANTER.generic
                local speaker = pending.speaker or banterSpeaker(battle)
                local line
                if pending.side == "enemy" then
                    local mon = enemyMonName(battle)
                    line = pickFormatted(pack.enemy, speaker, mon)
                        or (speaker .. ":\nGo, " .. mon .. "!")
                else
                    local mon = playerMonName(battle)
                    line = pickFormatted(pack.player, speaker, mon)
                        or (speaker .. ":\nA " .. mon .. ", huh?!")
                end
                return clampBanterText(line)
            end

            -- choose_lead opens PartyMenu before the real send. Keep waiting so
            -- we name the mon that actually comes out, not party[1].
            if pickerOpen() then
                return
            end
            if queueStillHasSendOut() then
                return
            end
            local sending = (pending.side == "player" and battle.sendingOut)
                or (pending.side == "enemy" and battle.enemySendingOut)
            if sending then
                battle._arSendBanterSawOut = true
                battle._arSendBanterArmFrames = nil
                return
            end
            if queueHasPoof(battle) then
                battle._arSendBanterSawOut = true
                battle._arSendBanterArmFrames = nil
                return
            end
            if battle._arSendBanterArmFrames and battle._arSendBanterArmFrames > 0 then
                battle._arSendBanterArmFrames = battle._arSendBanterArmFrames - 1
                return
            end
            -- Ready: send-out finished and POOF is gone. Name the live battler.
            local line = composeLine()
            battle._arPendingSendBanter = nil
            battle._arSendBanterSawOut = nil
            battle._arSendBanterArmFrames = nil
            if type(battle.queue) ~= "table" then
                return
            end
            if queueHasBanter(battle) then
                -- Still consume the pending so a stuck wave can't retry forever.
                battle._arSendBanterCooldown = 120
                return
            end
            battle._arSendBanterDidIntro = true
            battle._arSendBanterCooldown = 120
            if pushNpcCallout(battle, line, true, { kind = "banter" }) then
                BanterCameo.start(battle, line)
                return
            end
            local item = { text = line, arBanter = true }
            if not markBubbleWait(item, "foe", true, battle) then
                item.auto = true
                item.autoDelay = S.CALLOUT_AUTO_DELAY
            end
            table.insert(battle.queue, 1, item)
            BanterCameo.start(battle, line)
        end

        maybeEnqueueIdleBanter = function(battle)
            if not opt("trainer_banter") or not trainerFoeReactionsOn(battle) then
                return
            end
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return
            end
            local ms = momentumState(battle)
            -- Skip while anything cinematic / cover-related is going on.
            if ms.awaitingPick or ms.pendingDamage or ms.againInProgress then
                return
            end
            if battle._arPendingSendBanter or (battle._arSendBanterCooldown or 0) > 0 then
                return
            end
            if queueHasBanter(battle) then
                return
            end
            local t = ms.temp or {}
            if t.picHidden or t.cover or t.entrenched then
                return
            end
            local et = ms.enemyTemp or {}
            if et.cover then
                return
            end
            local turn = tonumber(battle.turnCount) or 0
            if turn < 1 then
                return
            end
            local last = ms.lastIdleBanterTurn or 0
            local persona = trainerPersona(battle)
            local gap = (persona == "rival") and 1 or 2
            if turn - last < gap then
                return
            end
            local chance = (persona == "rival") and 0.48 or 0.20
            local r = (love and love.math and love.math.random) or math.random
            if r() >= chance then
                return
            end
            local speaker = banterSpeaker(battle)
            local line = pickContextualIdleLine(battle, persona, speaker)
                or (speaker .. ":\nCome on!")
            line = clampBanterText(line)
            ms.lastIdleBanterTurn = turn
            ms.lastIdleBanterLine = line
            if pushNpcCallout(battle, line, true, { kind = "banter" }) then
                BanterCameo.start(battle, line)
                return
            end
            local item = { text = line, arBanter = true }
            if not markBubbleWait(item, "foe", true, battle) then
                item.auto = true
                item.autoDelay = S.CALLOUT_AUTO_DELAY
            end
            table.insert(battle.queue, item)
            BanterCameo.start(battle, line)
        end

        -- Durable API so hot-reload can refresh logic without stacking wraps.
        -- Assigned onto BattleState after it is required (below).
        local sendBanterApi = {
            flush = flushPendingSendBanter,
            enqueue = maybeEnqueueSendBanter,
        }
        local function tagQueueBubble(battle, bubble, forceWait)
            if not opt("speech_bubbles") or not battle or not bubble then
                return
            end
            local item = battle.queue and battle.queue[battle.nextInsert]
            if item and item.text then
                if fieldFlowsText(battle) then
                    forceWait = false
                end
                markBubbleWait(item, bubble, forceWait, battle)
            end
        end

        -- After you whiff a counter (and snap-back rolls): half their whiff estimate.
        local function queueFoeCounterBack(battle)
            if not battle or type(battle.queue) ~= "table" then
                return
            end
            local state = momentumState(battle)
            local dmg = foeCounterBackDamage(state)
            state.foeWhiffDamage = nil
            state.counterWhiffed = nil
            local foe = enemyMonName(battle)
            local line = pickFoeTrainerLine(
                    battle, S.TRAINER_FOE_COUNTER_BACK_CALLS, S.FOE_COUNTER_BACK_CALLS, foe)
                or ("Too slow!\n" .. foe .. " counters!")
            if not enqueueNpcFlavor(battle, line, S.CALLOUT_AUTO_DELAY) then
                battle.nextInsert = (battle.nextInsert or 0) + 1
                do
                    local item = { text = line }
                    if not markBubbleWait(item, "foe", true, battle) then
                        item.auto = true
                        item.autoDelay = S.CALLOUT_AUTO_DELAY
                    end
                    table.insert(battle.queue, battle.nextInsert, item)
                end
            end
            battle.nextInsert = (battle.nextInsert or 0) + 1
            table.insert(battle.queue, battle.nextInsert, {
                arFx = true,
                fn = function()
                    local player = battle.player
                    if not player or not player.mon or (player.mon.hp or 0) <= 0 then
                        return
                    end
                    if battle.fx then
                        battle.fx.shake = math.max(battle.fx.shake or 0, 14)
                    end
                    if battle.picFxFor then
                        local pf = battle:picFxFor(player)
                        if pf then
                            pf.kind, pf.t = "blink", 0
                            pf.hidden = nil
                        end
                    end
                    local dealt = battle:applyDamage(player, dmg)
                    if type(battle.sayNextAuto) == "function" and (dealt or 0) > 0 then
                        -- Keep it short; HP bar drain already sells the hit.
                    end
                    if player.mon.hp <= 0 and type(battle.onFaint) == "function" then
                        battle:onFaint(player)
                    end
                    checkLowHp(battle, player)
                end,
            })
        end

        -- After a counter attempt resolves: sometimes snap-back on whiff.
        local function resolvePlayerCounterAttempt(battle, connected)
            local state = battle and momentumByBattle[battle]
            if not state then
                return false
            end
            if state.counterWhiffed then
                state.counterWhiffed = nil
                if rollCounterSnapBack() then
                    queueFoeCounterBack(battle)
                    dev.log(battle, "COUNTER snapback", "foe answers the whiff")
                    return true
                end
                -- Whiffed the opening, but no punish this time.
                state.foeWhiffDamage = nil
                dev.log(battle, "COUNTER whiff", "no snapback")
                return false
            end
            if connected then
                state.foeWhiffDamage = nil
            end
            return false
        end

        -- Re-arm Battle Cinematics attack cameras for swings we fire
        -- outside a normal resolveTurn (Again!, same-turn COUNTER!, menu waits…).
        -- Also clears banter orbit / trainer billboard so the attack cam can take over.
        local function resetBattleCamera(battle)
            clearAmbientStance(battle)
            local state = battle and momentumByBattle[battle]
            local cameo = state and state.banterCameo
            if cameo then
                BanterCameo.releaseCam(cameo)
                BanterCameo.hideTrainer(battle, cameo)
            end
            local bc = mod.find and mod.find("BATTLE_CINEMATICS")
            if bc and bc.exports and type(bc.exports.activity) == "function" then
                pcall(bc.exports.activity)
            end
        end

        local function emitMoveUsed(battle, user, target, move, opts)
            opts = opts or {}
            if not battle or not user or not move then
                return
            end
            local payload = {
                battle = battle,
                user = user,
                target = target,
                move = move,
                isCalled = opts.isCalled == true,
                presentationOnly = opts.presentationOnly == true,
            }
            -- Prefer the shared Runtime bus when present so Battle Cinematics hears us.
            local okRt, Runtime = pcall(require, "src.mods.Runtime")
            if okRt and Runtime and Runtime.events and type(Runtime.events.emit) == "function" then
                pcall(Runtime.events.emit, Runtime.events, "battle.move_used", payload)
                return
            end
            if mod.events and type(mod.events.emit) == "function" then
                pcall(mod.events.emit, mod.events, "battle.move_used", payload)
            end
        end

        local function signalAttackPresentation(battle, user, target, move, opts)
            resetBattleCamera(battle)
            emitMoveUsed(battle, user, target, move, opts)
        end

        -- True while our dodge/brace sparkles own AnimPlayer (must not steal attack cam).
        -- On `dev` to stay under LuaJIT's 200-local limit.
        dev.attackAnimIsSparkle = function(battle)
            if not battle then
                return false
            end
            if battle._arAmbientOwned then
                return true
            end
            local cur = battle.current
            if type(cur) == "table" and cur.arFx then
                return true
            end
            local row = battle.moveAnimRow
            if type(row) == "table" and row.arFx and battle.animName
                and tostring(row.anim or "") == tostring(battle.animName) then
                return true
            end
            return false
        end

        -- While a real attack anim plays, keep BC's attack camera armed on that side.
        dev.tickAttackCamera = function(battle)
            if not battle or not battle.animPlaying then
                battle._arCamKey = nil
                return
            end
            if dev.attackAnimIsSparkle(battle) then
                return
            end
            local isPlayer = battle.animAttackerIsPlayer
            if isPlayer == nil then
                return
            end
            local moveId = battle.animName
            if not moveId or moveId == "" then
                return
            end
            local key = tostring(moveId) .. ":" .. (isPlayer and "P" or "E")
            if battle._arCamKey == key then
                return
            end
            battle._arCamKey = key
            local user = isPlayer and battle.player or battle.enemy
            local target = isPlayer and battle.enemy or battle.player
            local move = { id = moveId }
            if type(battle.moveDef) == "function" then
                local ok, def = pcall(battle.moveDef, battle, { id = moveId })
                if ok and type(def) == "table" then
                    move = def
                end
            end
            signalAttackPresentation(battle, user, target, move, {
                presentationOnly = true,
            })
        end

        local function queueMoveAttackAnim(battle, move, attackerIsPlayer)
            if not battle or type(battle.queue) ~= "table" or not move then
                return nil
            end
            local moveId = move.id or move.index
            if not moveId then
                return nil
            end
            moveId = tostring(moveId):upper()
            local moves = battle.data and battle.data.moves
            if type(moves) == "table" and not moves[moveId] and move.name then
                local byName = findMoveByName(battle, move.name)
                if byName and byName.id then
                    moveId = tostring(byName.id):upper()
                end
            end
            battle.nextInsert = (battle.nextInsert or 0) + 1
            local row = {
                anim = moveId,
                attackerIsPlayer = attackerIsPlayer and true or false,
            }
            table.insert(battle.queue, battle.nextInsert, row)
            battle.moveAnimRow = row
            return row
        end

        -- True second strike after a counter (separate anim + damage roll).
        -- Stripped record: never miss, single hit, no recoil/secondary re-fire.
        local function tryAgainStrike(battle, ctx, monName, foeSide)
            if not opt("momentum_counter") or not battle or not ctx then
                return false
            end
            local state = momentumState(battle)
            if state.againInProgress then
                return false
            end
            local target = ctx.target
            local user = ctx.user
            local move = ctx.move
            if not target or not target.mon or (target.mon.hp or 0) <= 0 then
                return false
            end
            if not user or not user.mon or (user.mon.hp or 0) <= 0 then
                return false
            end
            if (ctx.totalDealt or 0) <= 0 then
                return false
            end
            if not move or (move.power or 0) <= 0 or move.category == "status" then
                return false
            end
            local mid = tostring(move.id or ""):upper()
            if mid == "COUNTER" or mid == "EXPLOSION" or mid == "SELFDESTRUCT"
                or mid == "STRUGGLE" then
                return false
            end

            state.againInProgress = true
            dev.log(battle, "AGAIN!", foeSide and "foe" or "you")
            local line
            if foeSide then
                line = pickFoeTrainerLine(
                    battle, S.TRAINER_FOE_AGAIN_CALLS, S.FOE_AGAIN_CALLS, monName or enemyMonName(battle))
            else
                line = pickFormatted(S.AGAIN_CALLS, monName or playerMonName(battle))
                    or ((monName or "POKéMON") .. "!\nAgain!")
            end
            enqueueAutoAfter(battle, line, S.CALLOUT_AUTO_DELAY, foeSide and "foe" or "player",
                { side = foeSide and "enemy" or "player", kind = "attack" })
            -- Arm the camera RIGHT BEFORE the second anim — doing it during the first
            -- hit's damage resolve races BC (it latches the still-playing first anim,
            -- then clears pending before Again! swings).
            battle.nextInsert = (battle.nextInsert or 0) + 1
            table.insert(battle.queue, battle.nextInsert, {
                arFx = true,
                fn = function()
                    signalAttackPresentation(battle, user, target, move, { isCalled = true })
                end,
            })
            battle.moveAnimRow = nil
            if queueMoveAttackAnim(battle, move, user.isPlayer == true) then
                battle.nextInsert = (battle.nextInsert or 0) + 1
            end
            local stripped = {
                neverMiss = true,
                hitCount = function()
                    return 1
                end,
            }
            local ok = pcall(origRunDamaging, battle, ctx, stripped)
            state.againInProgress = false
            return ok and true or false
        end

        local function buildPickChoices(kind, battle)
            local scene = battleScene(battle)
            local tableFor = kind == "brace" and S.SCENE_BRACE_PICK or S.SCENE_PICK
            local list = tableFor[scene] or tableFor.route or {}
            local choices = {}
            for i = 1, #list do
                choices[#choices + 1] = list[i]
            end
            if kind == "dodge" then
                local types = playerTypeSet(battle)
                for ty, on in pairs(types) do
                    if on and S.TYPE_PICK_EXTRA[ty] then
                        choices[#choices + 1] = S.TYPE_PICK_EXTRA[ty]
                    end
                end
            end
            if #choices == 0 then
                if kind == "brace" then
                    choices[1] = { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 }
                else
                    choices[1] = { label = "DODGE", line = "%s!\nDodge it!", boost = 1 }
                end
            end
            return choices
        end

        local function indexOfMoveAnim(battle)
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return nil
            end
            local want = battle.moveAnimRow
            if want then
                for i, row in ipairs(battle.queue) do
                    if row == want then
                        return i
                    end
                end
            end
            -- Engine-queued attack anim. Skip our dodge/brace sparkles (arFx) —
            -- those used to steal this slot and shove REACT!/damage past the swing,
            -- so hit text only showed after you picked at end of turn.
            for i, row in ipairs(battle.queue) do
                if type(row) == "table" and row.anim and not row.arFx then
                    return i
                end
            end
            return nil
        end

        -- resolveTurn queues executeAction / endOfTurn as plain { fn = ... } rows.
        -- Never resume deferred damage or counter UI after those — that delays
        -- OPENING!/COUNTER! until the next turn's attack.
        -- Our own picFx / helper rows are tagged arFx so we don't treat them as
        -- turn scripts.
        local function indexOfNextTurnScript(battle)
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return nil
            end
            for i, row in ipairs(battle.queue) do
                if type(row) == "table" and type(row.fn) == "function" and not row.arFx then
                    return i
                end
            end
            return nil
        end

        -- Cursor for battle:sayNext / waitNext when resuming a deferred hit.
        -- sayNext does `nextInsert = nextInsert + 1` before inserting, so return
        -- the index of the row we want messages to FOLLOW (the move anim). Using
        -- animIdx+1 here shoved "It doesn't affect…" / effectiveness text past
        -- endOfTurn.
        local function resumeInsertIndex(battle)
            local animIdx = indexOfMoveAnim(battle)
            if animIdx then
                return animIdx
            end
            local fnIdx = indexOfNextTurnScript(battle)
            if fnIdx then
                return math.max(0, fnIdx - 1)
            end
            return math.max(0, #(battle.queue or {}))
        end

        local function insertBeforeAnim(battle, item)
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return
            end
            -- Prefer the real moveAnimRow. Do NOT fall back to the first row.anim —
            -- dodge/brace sparkles (TELEPORT / HARDEN / …) would steal the slot and
            -- shove menus/damage past the second mover.
            local idx = indexOfMoveAnim(battle) or indexOfNextTurnScript(battle)
            if idx then
                table.insert(battle.queue, idx, item)
            else
                table.insert(battle.queue, 1, item)
            end
        end

        -- Same-turn COUNTER! must appear before the next executeAction / endOfTurn.
        local function insertBeforeTurnScript(battle, item)
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return
            end
            local idx = indexOfNextTurnScript(battle)
            if idx then
                table.insert(battle.queue, idx, item)
            else
                table.insert(battle.queue, 1, item)
            end
        end

        -- Park COUNTER! after the foe's miss anim + dodge-whiff text (not before).
        local function insertAfterMissAnim(battle, item)
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return
            end
            local q = battle.queue
            local animIdx = indexOfMoveAnim(battle)
            local fnIdx = indexOfNextTurnScript(battle) or (#q + 1)
            local start = animIdx and (animIdx + 1) or 1
            local insertAt = fnIdx
            for i = start, fnIdx - 1 do
                local row = q[i]
                if type(row) == "table" and (row.text or row.wait or row.anim or row.arFx) then
                    insertAt = i + 1
                end
            end
            -- Also never land before the move anim itself.
            if animIdx and insertAt <= animIdx then
                insertAt = animIdx + 1
            end
            table.insert(q, insertAt, item)
        end

        -- Pick a Gen1 move id that exists in this battle's data.
        local function pickHideMoveAnim(battle, candidates)
            local moves = battle and battle.data and battle.data.moves
            if type(moves) ~= "table" or type(candidates) ~= "table" then
                return nil
            end
            local ok = {}
            for i = 1, #candidates do
                local id = candidates[i]
                if type(id) == "string" and moves[id] then
                    ok[#ok + 1] = id
                end
            end
            if #ok == 0 then
                return nil
            end
            return pickLine(ok) or ok[1]
        end

        -- Dig/Fly/leaf/surf-style hides: picFx motion + thematic move anim.
        local function dodgeAnimSpec(choice, battle)
            local label = ""
            if type(choice) == "table" then
                label = tostring(choice.label or ""):upper()
            elseif type(choice) == "string" then
                label = choice:upper()
            end
            -- STAY re-hide / auto path: reuse the remembered cover spot.
            if label == "" and battle then
                local st = momentumByBattle[battle]
                if st and st.temp and st.temp.coverSpot then
                    label = tostring(st.temp.coverSpot):upper()
                end
            end
            local spec = {
                pic = "slideDownHide",
                wait = 20,
                moves = { "DIG", "SLIDE_DOWN_ANIM", "DOUBLE_TEAM" },
                emerge = { "DIG", "QUICK_ATTACK" },
            }
            local byLabel = {
                ["FLY UP"] = {
                    pic = "slideUp",
                    wait = 18,
                    moves = { "FLY", "WING_ATTACK", "GUST", "DRILL_PECK" },
                    emerge = { "FLY", "WING_ATTACK", "GUST" },
                },
                ["ZIP"] = {
                    pic = "slideOff",
                    wait = 20,
                    moves = { "THUNDERBOLT", "THUNDER_WAVE", "QUICK_ATTACK", "FLASH" },
                    emerge = { "THUNDERBOLT", "QUICK_ATTACK" },
                },
                ["BURST"] = {
                    pic = "bounce",
                    wait = 28,
                    moves = { "FLAMETHROWER", "FIRE_SPIN", "EMBER", "SMOKESCREEN" },
                    emerge = { "EMBER", "QUICK_ATTACK" },
                },
                ["FADE"] = {
                    pic = "blink",
                    wait = 26,
                    moves = { "TELEPORT", "NIGHT_SHADE", "CONFUSE_RAY", "LICK" },
                    emerge = { "TELEPORT", "NIGHT_SHADE" },
                },
                ["SENSE"] = {
                    pic = "blink",
                    wait = 22,
                    moves = { "PSYCHIC", "CONFUSION", "TELEPORT", "DISABLE" },
                    emerge = { "PSYCHIC", "TELEPORT" },
                },
                ["DIVE"] = {
                    pic = "slideDown",
                    wait = 22,
                    moves = { "SURF", "WATERFALL", "BUBBLEBEAM", "CLAMP", "WITHDRAW" },
                    emerge = { "SURF", "WATERFALL", "BUBBLEBEAM" },
                },
                ["SPLASH"] = {
                    pic = "slideDown",
                    wait = 20,
                    moves = { "SURF", "WATER_GUN", "BUBBLE", "BUBBLEBEAM" },
                    emerge = { "SURF", "WATER_GUN" },
                },
                ["SHORE"] = {
                    pic = "slideHalf",
                    wait = 18,
                    moves = { "SURF", "WATER_GUN", "SAND_ATTACK" },
                    emerge = { "WATER_GUN", "QUICK_ATTACK" },
                },
                ["GRASS"] = {
                    pic = "slideDownHide",
                    wait = 20,
                    moves = { "RAZOR_LEAF", "VINE_WHIP", "PETAL_DANCE", "LEECH_SEED", "SLEEP_POWDER" },
                    emerge = { "RAZOR_LEAF", "VINE_WHIP", "PETAL_DANCE" },
                },
                ["BRUSH"] = {
                    pic = "slideDownHide",
                    wait = 20,
                    moves = { "RAZOR_LEAF", "VINE_WHIP", "PETAL_DANCE", "STUN_SPORE" },
                    emerge = { "RAZOR_LEAF", "VINE_WHIP" },
                },
                ["TREE"] = {
                    pic = "slideHalf",
                    wait = 18,
                    moves = { "RAZOR_LEAF", "VINE_WHIP", "LEECH_SEED", "FLY" },
                    emerge = { "RAZOR_LEAF", "FLY" },
                },
                ["ROCK"] = {
                    pic = "slideHalf",
                    wait = 18,
                    moves = { "DIG", "ROCK_SLIDE", "ROCK_THROW", "STRENGTH" },
                    emerge = { "DIG", "ROCK_THROW" },
                },
                ["STONE"] = {
                    pic = "slideHalf",
                    wait = 18,
                    moves = { "DIG", "ROCK_THROW", "HARDEN" },
                    emerge = { "DIG", "ROCK_THROW" },
                },
                ["LEDGE"] = {
                    pic = "slideUp",
                    wait = 16,
                    moves = { "DIG", "QUICK_ATTACK", "STRENGTH" },
                    emerge = { "DIG", "QUICK_ATTACK" },
                },
                ["CLIFF"] = {
                    pic = "slideUp",
                    wait = 18,
                    moves = { "FLY", "DIG", "STRENGTH", "ROCK_SLIDE" },
                    emerge = { "FLY", "DIG" },
                },
                ["CART"] = {
                    pic = "slideOff",
                    wait = 20,
                    moves = { "QUICK_ATTACK", "DOUBLE_TEAM", "SMOKESCREEN" },
                    emerge = { "QUICK_ATTACK", "DOUBLE_TEAM" },
                },
                ["ALLEY"] = {
                    pic = "slideOff",
                    wait = 20,
                    moves = { "SMOKESCREEN", "DOUBLE_TEAM", "QUICK_ATTACK", "TOXIC" },
                    emerge = { "SMOKESCREEN", "QUICK_ATTACK" },
                },
                ["PATH"] = {
                    pic = "slideOff",
                    wait = 18,
                    moves = { "QUICK_ATTACK", "DOUBLE_TEAM", "AGILITY", "SAND_ATTACK" },
                    emerge = { "QUICK_ATTACK", "AGILITY" },
                },
                ["SHADOW"] = {
                    pic = "blink",
                    wait = 24,
                    moves = { "NIGHT_SHADE", "CONFUSE_RAY", "LICK", "TELEPORT" },
                    emerge = { "NIGHT_SHADE", "TELEPORT" },
                },
                ["PILLAR"] = {
                    pic = "slideHalf",
                    wait = 18,
                    moves = { "BARRIER", "LIGHT_SCREEN", "REFLECT", "HARDEN" },
                    emerge = { "BARRIER", "QUICK_ATTACK" },
                },
                ["COURT"] = {
                    pic = "slideOff",
                    wait = 16,
                    moves = { "QUICK_ATTACK", "DOUBLE_TEAM", "AGILITY" },
                    emerge = { "QUICK_ATTACK" },
                },
                ["WALL"] = {
                    pic = "slideHalf",
                    wait = 18,
                    moves = { "BARRIER", "REFLECT", "HARDEN" },
                    emerge = { "BARRIER", "QUICK_ATTACK" },
                },
                ["COVER"] = {
                    pic = "slideDownHide",
                    wait = 20,
                    moves = { "DOUBLE_TEAM", "MINIMIZE", "DIG", "HARDEN" },
                    emerge = { "DOUBLE_TEAM", "DIG" },
                },
                ["DODGE"] = {
                    pic = "slideOff",
                    wait = 14,
                    moves = { "QUICK_ATTACK", "DOUBLE_TEAM" },
                    emerge = { "QUICK_ATTACK" },
                },
            }
            if byLabel[label] then
                spec = byLabel[label]
            elseif label == "" and battle then
                local types = playerTypeSet(battle)
                if types.FLYING then
                    spec = byLabel["FLY UP"]
                elseif types.WATER then
                    spec = byLabel["DIVE"]
                elseif types.GRASS then
                    spec = byLabel["GRASS"]
                elseif types.GHOST or types.PSYCHIC then
                    spec = byLabel["FADE"]
                elseif types.FIRE then
                    spec = byLabel["BURST"]
                elseif types.ELECTRIC then
                    spec = byLabel["ZIP"]
                end
            end
            return spec, label
        end

        local function insertQueueAfter(battle, item)
            battle.nextInsert = (battle.nextInsert or 0) + 1
            table.insert(battle.queue, battle.nextInsert, item)
        end

        local function queueThematicMoveAnim(battle, moveId)
            if not moveId or not battle or type(battle.queue) ~= "table" then
                return
            end
            if not (battle.data and battle.data.moves and battle.data.moves[moveId]) then
                return
            end
            insertQueueAfter(battle, {
                anim = moveId,
                attackerIsPlayer = true,
                arFx = true,
            })
        end

        enqueueDodgeHideAnim = function(battle, choice)
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return
            end
            local beforeAnim = type(choice) == "table" and choice.beforeAnim == true
            local stayHidden = not (type(choice) == "table" and choice.stayHidden == false)
            local state = momentumState(battle)
            if stayHidden then
                state.temp.picHidden = true
            end
            -- FIELD combat: OW sprite tuck behind real props. Skip Dig/Fly/etc.
            -- thematic anims that stamp cover shapes onto the map stage.
            if battle._arAnimeField or battle._arFieldCombat or battle._arFieldStandalone then
                return
            end
            if battle.animationsOn and not battle:animationsOn() then
                local player = battle.player
                if stayHidden and player and battle.picFxFor then
                    local pf = battle:picFxFor(player)
                    if pf then
                        pf.kind, pf.hidden = nil, true
                    end
                end
                return
            end
            local spec, label = dodgeAnimSpec(choice, battle)
            local moveId = spec.move or pickHideMoveAnim(battle, spec.moves)
            local items = {}
            -- 1) Kick a picFx so the mon visibly ducks / flies / fades.
            items[#items + 1] = {
                arFx = true,
                fn = function()
                    if not battle.picFxFor or not battle.player then
                        return
                    end
                    local pf = battle:picFxFor(battle.player)
                    if not pf then
                        return
                    end
                    pf.kind, pf.t = spec.pic, 0
                    pf.hidden, pf.ox, pf.oy = nil, 0, 0
                    if battle.fx then
                        battle.fx.shake = math.max(battle.fx.shake or 0, 8)
                    end
                end,
            }
            -- 2) Let the picFx play out.
            items[#items + 1] = { wait = spec.wait or 18, arFx = true }
            -- 3) Thematic move anim (FLY / RAZOR_LEAF / DIG / SURF / …).
            if moveId and battle.data and battle.data.moves and battle.data.moves[moveId] then
                items[#items + 1] = {
                    anim = moveId,
                    attackerIsPlayer = true,
                    arFx = true,
                }
                dev.log(battle, "HIDE anim",
                    tostring(label or "?") .. "→" .. tostring(moveId))
            end
            -- 4) Stay hidden in cover afterward (or clear for a brief sidestep).
            items[#items + 1] = {
                arFx = true,
                fn = function()
                    if not battle.picFxFor or not battle.player then
                        return
                    end
                    local pf = battle:picFxFor(battle.player)
                    if not pf then
                        return
                    end
                    pf.kind, pf.t = nil, nil
                    pf.ox, pf.oy = 0, 0
                    if stayHidden then
                        pf.hidden = true
                    else
                        pf.hidden = nil
                        if state.temp then
                            state.temp.picHidden = false
                        end
                    end
                end,
            }

            if beforeAnim then
                for i = #items, 1, -1 do
                    insertBeforeAnim(battle, items[i])
                end
            else
                for i = 1, #items do
                    insertQueueAfter(battle, items[i])
                end
            end
        end

        enqueueBraceAnim = function(battle, opts)
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return
            end
            opts = opts or {}
            -- FIELD: brace is the OW sprite crouch — skip classic BARRIER/etc. FX.
            if battle._arAnimeField or battle._arFieldCombat or battle._arFieldStandalone then
                return
            end
            local foeSide = opts.foe == true
            local side = foeSide and battle.enemy or battle.player
            if not side then
                return
            end
            if battle.animationsOn and not battle:animationsOn() then
                return
            end

            local entrenched = opts.entrenched == true
            -- Classic status anims that read as "toughen up" / shell / barrier.
            -- Picked at random so brace/entrench don't always look identical.
            local movePool = entrenched and {
                "BARRIER", "ACID_ARMOR", "HARDEN", "WITHDRAW", "DEFENSE_CURL", "REFLECT",
            } or {
                "HARDEN", "WITHDRAW", "DEFENSE_CURL", "MEDITATE", "BIDE",
                "BARRIER", "ACID_ARMOR",
            }
            local picPool = {
                { pic = "blink",     wait = 10 },
                { pic = "bounce",    wait = 14 },
                { pic = "slideHalf", wait = 12 },
                { pic = "blink",     wait = 8, follow = "bounce", followWait = 12 },
            }
            local moveId = pickLine(movePool)
            local pic = pickLine(picPool) or picPool[1]
            local wait = pic.wait or 12
            if entrenched then
                wait = wait + 6
            end
            local shake = entrenched and 14 or 10

            local items = {}
            items[#items + 1] = {
                arFx = true,
                fn = function()
                    if not battle.picFxFor then
                        return
                    end
                    local battler = foeSide and battle.enemy or battle.player
                    if not battler then
                        return
                    end
                    local pf = battle:picFxFor(battler)
                    if pf then
                        pf.kind, pf.t = pic.pic, 0
                        pf.hidden = nil
                    end
                    if battle.fx then
                        battle.fx.shake = math.max(battle.fx.shake or 0, shake)
                    end
                end,
            }
            items[#items + 1] = { wait = wait, arFx = true }
            if pic.follow then
                items[#items + 1] = {
                    arFx = true,
                    fn = function()
                        if not battle.picFxFor then
                            return
                        end
                        local battler = foeSide and battle.enemy or battle.player
                        if not battler then
                            return
                        end
                        local pf = battle:picFxFor(battler)
                        if pf then
                            pf.kind, pf.t = pic.follow, 0
                        end
                    end,
                }
                items[#items + 1] = { wait = pic.followWait or 12, arFx = true }
            end
            if moveId and battle.data and battle.data.moves and battle.data.moves[moveId] then
                items[#items + 1] = {
                    anim = moveId,
                    attackerIsPlayer = not foeSide,
                    arFx = true,
                }
            end
            -- Clear leftover picFx so the real attack reads cleanly.
            items[#items + 1] = {
                arFx = true,
                fn = function()
                    if not battle.picFxFor then
                        return
                    end
                    local battler = foeSide and battle.enemy or battle.player
                    if not battler then
                        return
                    end
                    local pf = battle:picFxFor(battler)
                    if pf and (pf.kind == pic.pic or pf.kind == pic.follow) then
                        pf.kind, pf.t = nil, nil
                    end
                end,
            }

            if opts.beforeAnim then
                -- insertBeforeAnim prepends at the anim index; reverse so order stays.
                for i = #items, 1, -1 do
                    insertBeforeAnim(battle, items[i])
                end
            else
                for i = 1, #items do
                    insertQueueAfter(battle, items[i])
                end
            end
        end

        -- Focus cover spot from mon type / scene (feeds hide FX + overlay prop).
        -- On `dev` to stay under LuaJIT's 200-local limit.
        dev.pickFocusCoverLabel = function(battle)
            -- FIELD: prefer the prop flavor we actually stamped (TREE / ROCK / …).
            if FieldBattleViewer and type(FieldBattleViewer.session) == "function" then
                local sess = FieldBattleViewer.session(battle)
                if sess and type(sess.coverKind) == "string" and sess.coverKind ~= "" then
                    return sess.coverKind
                end
            end
            local types = playerTypeSet(battle)
            if types.FLYING then
                return "FLY UP"
            end
            if types.WATER then
                return "DIVE"
            end
            if types.GRASS then
                return "TREE"
            end
            if types.ROCK or types.GROUND then
                return "ROCK"
            end
            if types.GHOST or types.PSYCHIC then
                return "SHADOW"
            end
            if types.FIRE then
                return "BURST"
            end
            if types.ELECTRIC then
                return "ZIP"
            end
            local sceneSpot = S.SCENE_COVER_SPOT and S.SCENE_COVER_SPOT[battleScene(battle)]
            return sceneSpot or "ROCK"
        end

        -- Clear Focus cover hide + prop (shatter / emerge / battle end).
        dev.clearFocusCoverVisual = function(battle, withEmerge)
            if not battle then
                return
            end
            local state = momentumByBattle[battle]
            if state then
                state.focusCoverSpot = nil
                state.coverHideWorld = nil
                state.coverHidePicOx = nil
                state.coverHidePicOy = nil
                state.coverTucked = nil
            end
            if battle.picFxFor and battle.player then
                local pf = battle:picFxFor(battle.player)
                if pf then
                    pf.ox, pf.oy = 0, 0
                    if state and not (state.temp and state.temp.picHidden) then
                        pf.hidden = nil
                    end
                end
            end
            revealPlayerPic(battle, withEmerge == true)
        end

        -- Pick a stamped prop and tuck the mon on its far side from the foe.
        -- FIELD fights use field_battle arena slots; DS arena uses stamped voxels.
        dev.pickCoverHideSpot = function(battle)
            local state = momentumState(battle)
            local slots = state.coverPropSlots

            -- Prefer live FIELD cover slots (discovered tiles / session overlays).
            if (not slots or #slots == 0) and FieldBattleViewer
                and type(FieldBattleViewer.session) == "function" then
                local sess = FieldBattleViewer.session(battle)
                if sess and type(sess.coverSlots) == "table" and #sess.coverSlots > 0 then
                    slots = {}
                    for i = 1, #sess.coverSlots do
                        local s = sess.coverSlots[i]
                        if s then
                            slots[#slots + 1] = {
                                x = s.px,
                                z = s.py,
                                cx = s.cx,
                                cy = s.cy,
                                picOx = -14,
                                picOy = 6,
                                kind = s.kind,
                            }
                        end
                    end
                    state.coverPropSlots = slots
                    state.worldCoverProps = true
                end
            end

            if type(slots) ~= "table" or #slots == 0 then
                local edits = dev._coverPropEdits
                if type(edits) == "table" then
                    slots = {}
                    for i = 1, #edits do
                        local e = edits[i]
                        if e and e.wx and e.wz then
                            slots[#slots + 1] = {
                                x = e.wx, z = e.wz, cx = e.cx, cy = e.cy, picOx = e.picOx, picOy = e.picOy,
                            }
                        end
                    end
                end
            end
            if type(slots) ~= "table" or #slots == 0 then
                return false
            end
            local rr = (love and love.math and love.math.random) or math.random
            local pick = slots[rr(1, #slots)]
            local hx, hz = pick.x, pick.z
            -- Nudge further from the foe so the prop sits between mon and enemy.
            if FieldBattleViewer and type(FieldBattleViewer.session) == "function" then
                local sess = FieldBattleViewer.session(battle)
                local foe = sess and sess.enemyMon
                if foe then
                    local ex = foe.basePx or foe.px or hx
                    local ez = foe.basePy or foe.py or hz
                    local dx, dz = hx - ex, hz - ez
                    local len = math.sqrt(dx * dx + dz * dz)
                    if len > 0.001 then
                        hx = hx + (dx / len) * 10
                        hz = hz + (dz / len) * 10
                    end
                end
            end
            state.coverHideWorld = { x = hx, z = hz }
            state.coverHidePicOx = pick.picOx or ((pick.x or 0) > 0 and -14 or 14)
            state.coverHidePicOy = pick.picOy or 6
            state.coverTucked = true
            return true
        end

        -- Apply tuck: flat pic gets an ox/oy nudge behind cover.
        dev.applyCoverTuckVisual = function(battle)
            if not battle then
                return
            end
            local state = momentumByBattle[battle]
            if not (state and state.coverTucked) then
                return
            end
            if battle.picFxFor and battle.player then
                local pf = battle:picFxFor(battle.player)
                if pf then
                    pf.hidden = nil
                    pf.ox = state.coverHidePicOx or -12
                    pf.oy = state.coverHidePicOy or 4
                end
            end
            if state.temp then
                state.temp.picHidden = false
            end
        end

        -- Dramatic Shape OverworldBattle (cover stamps on staged 3D fights).
        dev.findDsLib = function()
            if not mod.find then
                return nil
            end
            local ids = { "DRAMATIC_SHAPE", "potato_voxel" }
            for i = 1, #ids do
                local handle = mod.find(ids[i])
                local lib = handle and handle.exports and handle.exports.lib
                if lib and type(lib.require) == "function" then
                    return lib
                end
            end
            return nil
        end

        -- BATTLE STAGE preference (AUTO / FIELD).
        dev.battleStage = function()
            return battleStage()
        end

        -- FIELD presentation lives in field_battle/ (lifecycle + tile grid).
        dev.wantsAnimeField = function()
            return FieldBattleViewer and type(FieldBattleViewer.enabled) == "function"
                and FieldBattleViewer.enabled(mod)
        end

        dev.installFieldFightSpriteHook = function()
            if FieldBattleViewer and type(FieldBattleViewer.install) == "function" then
                pcall(FieldBattleViewer.install, mod)
            end
        end

        dev.owSpritePath = function()
            return nil
        end

        -- Play dodge / cover / brace / entrench FX for Focus reacts.
        dev.playFocusReactFx = function(battle, action, result)
            if not battle or not opt("momentum_counter") then
                return
            end
            -- FIELD: OW sprites + projectiles own the react beat.
            if battle._arAnimeField or battle._arFieldCombat or battle._arFieldStandalone then
                if FieldBattleViewer and type(FieldBattleViewer.react) == "function" then
                    local kind = tostring(action or "")
                    if kind == "dodge" or kind == "cover" or kind == "brace"
                        or kind == "entrench" or kind == "entrench_hold" then
                        pcall(FieldBattleViewer.react, battle, "player",
                            (kind == "entrench_hold" and "brace") or kind)
                    end
                end
                return
            end
            action = tostring(action or "")
            result = result or {}
            local state = momentumState(battle)

            if action == "dodge" then
                if result.forceMiss then
                    enqueueDodgeHideAnim(battle, {
                        label = "DODGE",
                        beforeAnim = true,
                        stayHidden = false,
                    })
                else
                    insertBeforeAnim(battle, { wait = 10, arFx = true })
                    insertBeforeAnim(battle, {
                        arFx = true,
                        fn = function()
                            if battle.picFxFor and battle.player then
                                local pf = battle:picFxFor(battle.player)
                                if pf then
                                    pf.kind, pf.t = "blink", 0
                                end
                            end
                            if battle.fx then
                                battle.fx.shake = math.max(battle.fx.shake or 0, 10)
                            end
                        end,
                    })
                end
                return
            end

            if action == "cover" then
                -- Already holding: keep prop / tuck; no full re-enter flash.
                if state.focusCoverSpot and ReactiveDefense then
                    local rdSide = ReactiveDefense.sideState(battle, true)
                    if rdSide and rdSide.cover then
                        return
                    end
                end
                local spot = dev.pickFocusCoverLabel(battle)
                state.focusCoverSpot = spot
                rememberCoverSpot(battle, spot)
                local tucked = false
                if type(dev.pickCoverHideSpot) == "function" then
                    tucked = dev.pickCoverHideSpot(battle) and true or false
                end
                -- Dive anim, then stay visible tucked behind the world prop (or hidden
                -- if we have no stamp to stand behind).
                enqueueDodgeHideAnim(battle, {
                    label = spot,
                    beforeAnim = true,
                    stayHidden = not tucked,
                })
                insertBeforeAnim(battle, {
                    arFx = true,
                    fn = function()
                        if tucked and type(dev.applyCoverTuckVisual) == "function" then
                            dev.applyCoverTuckVisual(battle)
                        end
                        if FieldBattleViewer and type(FieldBattleViewer.react) == "function" then
                            pcall(FieldBattleViewer.react, battle, "player", "cover")
                        end
                    end,
                })
                return
            end

            if action == "brace" then
                enqueueBraceAnim(battle, { beforeAnim = true })
                return
            end

            if action == "entrench" or action == "entrench_hold" then
                if action == "entrench" then
                    enqueueBraceAnim(battle, { beforeAnim = true, entrenched = true })
                end
                return
            end
        end

        -- Chunky 2.5D voxel cube (Dramatic Shape aesthetic) for cover props.
        dev.drawVoxelCube = function(g, cx, cy, s, r, gg, b, a)
            local d = math.max(2, math.floor(s * 0.42 + 0.5))
            local h = s
            local x0 = cx - s * 0.5
            local y0 = cy - h * 0.5
            g.setColor(r * 0.72, gg * 0.72, b * 0.72, a)
            g.rectangle("fill", x0, y0, s, h)
            g.setColor(r, gg, b, a)
            g.polygon("fill",
                x0, y0,
                x0 + d, y0 - d,
                x0 + s + d, y0 - d,
                x0 + s, y0)
            g.setColor(r * 0.48, gg * 0.48, b * 0.48, a)
            g.polygon("fill",
                x0 + s, y0,
                x0 + s + d, y0 - d,
                x0 + s + d, y0 + h - d,
                x0 + s, y0 + h)
        end

        -- Voxel-style cover prop (tree / rock / splash / …) while Focus-covered.
        -- Prefer real map stamps when 3D arena props were placed; HUD is fallback.
        dev.drawCoverProp = function(battle)
            if not ReactiveDefense or not battle or not (love and love.graphics) then
                return
            end
            -- FIELD: never paint HUD cover cubes — tuck uses real map props only.
            if battle._arAnimeField or battle._arFieldCombat or battle._arFieldStandalone
                or (FieldBattleViewer and FieldBattleViewer.enabled
                    and FieldBattleViewer.enabled(mod)) then
                return
            end
            local side = ReactiveDefense.sideState(battle, true)
            if not side or not side.cover then
                return
            end
            local state = momentumByBattle[battle]
            if state and state.worldCoverProps then
                -- World trees/rocks are in the shot; keep the mon visible but tucked.
                if type(dev.applyCoverTuckVisual) == "function" then
                    pcall(dev.applyCoverTuckVisual, battle)
                end
                return
            end
            -- Flat fallback: nudge pic behind the HUD prop instead of vanishing.
            if battle.picFxFor and battle.player then
                local pf = battle:picFxFor(battle.player)
                if pf and not pf.kind then
                    pf.hidden = nil
                    pf.ox = (state and state.coverHidePicOx) or -12
                    pf.oy = (state and state.coverHidePicOy) or 4
                end
            end
            local spot = tostring((state and state.focusCoverSpot)
                or (state and state.temp and state.temp.coverSpot)
                or "ROCK"):upper()
            local g = love.graphics
            -- Classic player backsprite box sits lower-left; prop sits in front.
            local ox, oy = 36, 78
            local kind = "boulder"
            if spot == "TREE" or spot == "GRASS" or spot == "BRUSH" then
                kind = "tree"
            elseif spot == "DIVE" or spot == "SPLASH" or spot == "SHORE" then
                kind = "water"
            elseif spot == "FLY UP" then
                kind = "cloud"
            elseif spot == "SHADOW" or spot == "FADE" then
                kind = "shadow"
            elseif spot == "BURST" then
                kind = "ember"
            elseif spot == "ZIP" then
                kind = "spark"
            end

            g.push("all")
            local pulse = ((battle.frame or 0) % 40) < 20 and 1 or 0.92
            local a = 0.96 * pulse
            local cube = dev.drawVoxelCube
            if kind == "boulder" then
                cube(g, ox + 8, oy + 6, 10, 0.42, 0.38, 0.34, a)
                cube(g, ox + 18, oy + 4, 12, 0.52, 0.48, 0.42, a)
                cube(g, ox + 12, oy - 2, 9, 0.58, 0.54, 0.48, a)
                cube(g, ox + 22, oy + 8, 7, 0.36, 0.33, 0.30, a)
            elseif kind == "tree" then
                cube(g, ox + 14, oy + 10, 5, 0.42, 0.28, 0.14, a)
                cube(g, ox + 14, oy + 5, 5, 0.48, 0.32, 0.16, a)
                cube(g, ox + 10, oy - 2, 9, 0.22, 0.48, 0.24, a)
                cube(g, ox + 18, oy - 4, 10, 0.28, 0.55, 0.28, a)
                cube(g, ox + 14, oy - 10, 8, 0.34, 0.62, 0.32, a)
                cube(g, ox + 6, oy + 2, 7, 0.20, 0.42, 0.22, a)
            elseif kind == "water" then
                cube(g, ox + 6, oy + 8, 8, 0.28, 0.48, 0.78, a * 0.75)
                cube(g, ox + 16, oy + 6, 10, 0.35, 0.58, 0.88, a * 0.8)
                cube(g, ox + 12, oy + 2, 7, 0.55, 0.78, 0.98, a * 0.7)
            elseif kind == "cloud" then
                cube(g, ox + 6, oy + 2, 8, 0.90, 0.92, 0.96, a)
                cube(g, ox + 16, oy - 2, 10, 0.94, 0.96, 0.99, a)
                cube(g, ox + 24, oy + 2, 7, 0.88, 0.90, 0.95, a)
            elseif kind == "shadow" then
                cube(g, ox + 10, oy + 4, 12, 0.18, 0.12, 0.28, a * 0.7)
                cube(g, ox + 18, oy, 8, 0.32, 0.18, 0.42, a * 0.65)
            elseif kind == "ember" then
                cube(g, ox + 8, oy + 6, 7, 0.55, 0.22, 0.10, a)
                cube(g, ox + 16, oy + 2, 6, 0.90, 0.45, 0.12, a)
                cube(g, ox + 12, oy - 4, 5, 0.98, 0.75, 0.20, a)
            else -- spark / crate
                cube(g, ox + 10, oy + 2, 10, 0.58, 0.42, 0.20, a)
                cube(g, ox + 18, oy - 2, 8, 0.68, 0.52, 0.26, a)
            end
            g.setColor(1, 1, 1, 1)
            g.pop()
        end

        -- Restore map blocks stamped for battle cover props.
        dev.restoreBattleCoverProps = function()
            local edits = dev._coverPropEdits
            if type(edits) ~= "table" then
                return
            end
            for i = #edits, 1, -1 do
                local e = edits[i]
                if e and e.map and type(e.map.setBlock) == "function" then
                    pcall(function()
                        if mod.world and type(mod.world.replaceBlock) == "function" then
                            mod.world:replaceBlock(e.bx, e.by, e.prev)
                        else
                            e.map:setBlock(e.bx, e.by, e.prev)
                        end
                    end)
                end
                edits[i] = nil
            end
            dev._coverPropEdits = nil
            if type(dev._coverPropBattle) == "table" then
                local st = momentumByBattle[dev._coverPropBattle]
                if st then
                    st.worldCoverProps = nil
                    st.coverPropSlots = nil
                    st.coverHideWorld = nil
                    st.coverTucked = nil
                end
                dev._coverPropBattle = nil
            end
        end

        -- Pick a Cut-tree / rock block id from the live tileset.
        dev.pickCoverBlockId = function(map, battle, wantTree)
            if not (map and map.tileset and type(map.tileset.blocks) == "table") then
                return nil
            end
            local blocks = map.tileset.blocks
            local data = battle and battle.game and battle.game.data
            if wantTree then
                local swaps = data and data.field and data.field.cutTreeSwaps
                if type(swaps) == "table" then
                    for i = 1, #swaps do
                        local sw = swaps[i]
                        local before = sw and tonumber(sw.before)
                        if before and type(blocks[before + 1]) == "table" then
                            return before
                        end
                    end
                end
                -- Lone canopy / cuttable sapling tile patterns (OVERWORLD / GYM / …).
                local treeTiles = {
                    [42] = true,
                    [43] = true,
                    [58] = true,
                    [59] = true,
                    [45] = true,
                    [46] = true,
                    [61] = true,
                    [62] = true,
                    [4] = true,
                    [5] = true,
                    [6] = true,
                    [7] = true,
                }
                local best, bestN = nil, 0
                for id = 0, #blocks - 1 do
                    local b = blocks[id + 1]
                    if type(b) == "table" then
                        local n = 0
                        for t = 1, 16 do
                            if treeTiles[b[t]] then
                                n = n + 1
                            end
                        end
                        if n > bestN then
                            best, bestN = id, n
                        end
                    end
                end
                if bestN >= 2 then
                    return best
                end
            end
            -- Rock / boulder tiles across cavern / gym / plateau atlases.
            local rockTiles = {
                [7] = true,
                [8] = true,
                [23] = true,
                [24] = true,
                [12] = true,
                [13] = true,
                [28] = true,
                [29] = true,
                [44] = true,
                [45] = true,
                [46] = true,
                [47] = true,
            }
            local best, bestN = nil, 0
            for id = 0, #blocks - 1 do
                local b = blocks[id + 1]
                if type(b) == "table" then
                    local n = 0
                    for t = 1, 16 do
                        if rockTiles[b[t]] then
                            n = n + 1
                        end
                    end
                    if n > bestN then
                        best, bestN = id, n
                    end
                end
            end
            if bestN >= 2 then
                return best
            end
            return nil
        end

        -- Stamp real voxel trees/rocks beside the player arena cell for Cover.
        -- Uses Map:setBlock so Dramatic Shape remeshes; restored on battle end.
        dev.stampBattleCoverProps = function(battle)
            if not battle or not opt("momentum_counter") then
                return
            end
            -- FIELD fights must not stamp trees/rocks into the live map.
            if battle._arAnimeField or battle._arFieldCombat or battle._arFieldStandalone
                or (FieldBattleViewer and FieldBattleViewer.enabled
                    and FieldBattleViewer.enabled(mod)) then
                return
            end
            -- Avoid double-stamp if begin-hook and battle.started both fire.
            if type(dev._coverPropEdits) == "table" and #dev._coverPropEdits > 0 then
                local st = momentumState(battle)
                st.worldCoverProps = true
                return
            end
            local scene = battleScene(battle)
            if scene == "indoor" or scene == "gym" then
                return
            end
            local arena, map
            local lib = dev.findDsLib()
            if lib then
                local ok, OB = pcall(lib.require, "OverworldBattle")
                if ok and type(OB) == "table" and type(OB.arena) == "function" then
                    arena = OB.arena()
                end
            end
            if not (arena and arena.playerCell and arena.enemyCell) then
                return
            end
            map = arena.map
            if not (map and type(map.setBlock) == "function" and type(map.blockAt) == "function") then
                local ow = battle.game and battle.game.overworld
                map = ow and ow.map
            end
            if not (map and type(map.setBlock) == "function" and type(map.blockAt) == "function") then
                return
            end
            local wantTree = (scene == "forest" or scene == "route" or scene == "city")
            local blockId = dev.pickCoverBlockId(map, battle, wantTree)
            if not blockId and wantTree then
                blockId = dev.pickCoverBlockId(map, battle, false)
            end
            if not blockId then
                return
            end

            local px, py = arena.playerCell[1], arena.playerCell[2]
            local ex, ey = arena.enemyCell[1], arena.enemyCell[2]
            local pbx, pby = math.floor(px / 2), math.floor(py / 2)
            local ebx, eby = math.floor(ex / 2), math.floor(ey / 2)
            -- Fight-lane unit (player → enemy); prefer props off that axis.
            local ldx, ldy = (ex or px) - px, (ey or py) - py
            local llen = math.sqrt(ldx * ldx + ldy * ldy)
            if llen > 0.001 then
                ldx, ldy = ldx / llen, ldy / llen
            else
                ldx, ldy = 0, -1
            end

            local candidates = {}
            for ox = -4, 4 do
                for oy = -4, 4 do
                    if not (ox == 0 and oy == 0) then
                        local dist = math.sqrt(ox * ox + oy * oy)
                        if dist >= 1.2 and dist <= 4.2 then
                            local cx, cy = px + ox, py + oy
                            if not (map.inBounds and not map:inBounds(cx, cy)) then
                                local bx, by = math.floor(cx / 2), math.floor(cy / 2)
                                if not (bx == pbx and by == pby) and not (bx == ebx and by == eby) then
                                    local okCell = true
                                    if map.warpAtCell and map:warpAtCell(cx, cy) then
                                        okCell = false
                                    end
                                    if okCell and map.isWarpTileCell and map:isWarpTileCell(cx, cy) then
                                        okCell = false
                                    end
                                    if okCell then
                                        local walk = map.isWalkableCell and map:isWalkableCell(cx, cy)
                                        local grass = map.isGrassCell and map:isGrassCell(cx, cy)
                                        if not (walk or grass) then
                                            okCell = false
                                        end
                                    end
                                    if okCell then
                                        -- Score: prefer flanks over the fight lane; light jitter later.
                                        local along = ox * ldx + oy * ldy
                                        local side = math.abs(ox * (-ldy) + oy * ldx)
                                        local score = side * 3 - math.abs(along) + dist
                                        -- Slight bias toward camera side (away from enemy).
                                        if along < 0 then
                                            score = score + 1.5
                                        end
                                        candidates[#candidates + 1] = {
                                            cx = cx,
                                            cy = cy,
                                            bx = bx,
                                            by = by,
                                            score = score,
                                            ox = ox,
                                            oy = oy,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if #candidates == 0 then
                return
            end
            table.sort(candidates, function(a, b)
                return (a.score or 0) > (b.score or 0)
            end)
            -- Take a random pick from the top-scoring half so placement varies.
            local poolN = math.max(1, math.min(#candidates, math.ceil(#candidates * 0.55)))
            local rr = (love and love.math and love.math.random) or math.random
            local wantCount = rr(1, 2)
            local edits = {}
            local slots = {}
            local seen = {}
            for _ = 1, wantCount do
                if poolN < 1 then
                    break
                end
                local pickIdx = rr(1, poolN)
                local cand = candidates[pickIdx]
                -- Swap-remove from pool so we don't stamp the same block twice.
                candidates[pickIdx], candidates[poolN] = candidates[poolN], candidates[pickIdx]
                poolN = poolN - 1
                if not cand then
                    break
                end
                local key = cand.bx .. "," .. cand.by
                if not seen[key] then
                    seen[key] = true
                    local prev = map:blockAt(cand.bx, cand.by)
                    local wx = cand.cx * 16 + 8
                    local wz = cand.cy * 16 + 8
                    local picOx = (cand.ox >= 0) and -14 or 14
                    local picOy = (cand.oy >= 0) and 6 or 2
                    local wrote = false
                    if prev ~= nil and prev ~= blockId then
                        if mod.world and type(mod.world.replaceBlock) == "function" then
                            wrote = mod.world:replaceBlock(cand.bx, cand.by, blockId) and true or false
                        end
                        if not wrote then
                            pcall(map.setBlock, map, cand.bx, cand.by, blockId)
                            wrote = map:blockAt(cand.bx, cand.by) == blockId
                        end
                        if wrote then
                            edits[#edits + 1] = {
                                map = map,
                                bx = cand.bx,
                                by = cand.by,
                                prev = prev,
                                wx = wx,
                                wz = wz,
                                cx = cand.cx,
                                cy = cand.cy,
                                picOx = picOx,
                                picOy = picOy,
                            }
                        end
                    elseif prev == blockId then
                        wrote = true
                    end
                    if wrote then
                        slots[#slots + 1] = {
                            x = wx,
                            z = wz,
                            cx = cand.cx,
                            cy = cand.cy,
                            picOx = picOx,
                            picOy = picOy,
                        }
                    end
                end
            end

            if #slots == 0 then
                return
            end
            dev._coverPropEdits = edits
            dev._coverPropBattle = battle
            local st = momentumState(battle)
            st.worldCoverProps = true
            st.coverPropSlots = slots
            if type(dev.log) == "function" then
                dev.log(battle, "COVER props",
                    string.format("stamped=%d slots=%d block=%s scene=%s",
                        #edits, #slots, tostring(blockId), tostring(scene)))
            end
        end

        -- Hook OverworldBattle.begin: cover stamps.
        dev.installCoverPropStampHooks = function()
            local lib = dev.findDsLib()
            if not lib then
                return
            end
            local ok, OB = pcall(lib.require, "OverworldBattle")
            if not (ok and type(OB) == "table" and type(OB.begin) == "function") then
                return
            end

            if not OB._arCoverPropBegin then
                local inner = OB.begin
                OB.begin = function(state, battle)
                    local result = inner(state, battle)
                    if result and type(dev.stampBattleCoverProps) == "function" and battle then
                        pcall(dev.stampBattleCoverProps, battle)
                    end
                    return result
                end
                OB._arCoverPropBegin = true
            end

            if type(OB.finish) == "function" and not OB._arCoverPropFinish then
                local innerFinish = OB.finish
                OB.finish = function(...)
                    if type(dev.restoreBattleCoverProps) == "function" then
                        pcall(dev.restoreBattleCoverProps)
                    end
                    return innerFinish(...)
                end
                OB._arCoverPropFinish = true
            end
            dev._coverPropStampHooks = true
        end

        -- Idle HARDEN / GROWTH / DIG pulses while braced or hiding in the menu.
        -- Drives animPlayer + picFx without stealing the FIGHT / STRIKE menus.
        clearAmbientStance = function(battle)
            local state = battle and momentumByBattle[battle]
            local owned = battle and battle._arAmbientOwned
            if battle then
                battle._arAmbientOwned = nil
            end
            -- Stop leftover HARDEN/BARRIER pulses so the real attack anim can start
            -- cleanly (entrench STRIKE was inheriting a busy animPlayer).
            if owned and battle and battle.animPlayer then
                local ap = battle.animPlayer
                if type(ap.stop) == "function" then
                    pcall(ap.stop, ap)
                elseif type(ap.start) == "function" then
                    -- No stop API: poke a finished state via isDone by clearing custom.
                    pcall(function()
                        ap.custom = false
                        ap.spec = nil
                        if ap.inner and type(ap.inner.stop) == "function" then
                            ap.inner:stop()
                        end
                    end)
                end
            end
            if not state or not state.ambient then
                return
            end
            local amb = state.ambient
            state.ambient = nil
            if amb.wasHidden and battle.picFxFor and battle.player
                and state.temp and state.temp.picHidden then
                local pf = battle:picFxFor(battle.player)
                if pf then
                    pf.hidden = true
                end
            end
        end

        local function ambientMovePool(temp)
            if not temp then
                return nil
            end
            if temp.entrenched then
                return S.AMBIENT_ENTRENCH_MOVES or S.AMBIENT_BRACE_MOVES
            end
            if (temp.defense or 0) > 0 and not temp.hidAway then
                return S.AMBIENT_BRACE_MOVES
            end
            if temp.hidAway or temp.picHidden then
                local spot = tostring(temp.coverSpot or ""):upper()
                local bySpot = S.AMBIENT_HIDE_MOVES or {}
                if spot ~= "" and bySpot[spot] then
                    return bySpot[spot]
                end
                local spec = dodgeAnimSpec({ label = spot }, nil)
                return (spec and spec.moves) or { "DIG", "DOUBLE_TEAM" }
            end
            return nil
        end

        local function pickAmbientMove(battle, pool)
            if type(pool) ~= "table" or #pool == 0 then
                return nil
            end
            local moves = battle and battle.data and battle.data.moves
            local ok = {}
            for i = 1, #pool do
                local id = pool[i]
                if type(id) == "string" and moves and moves[id] then
                    ok[#ok + 1] = id
                end
            end
            if #ok == 0 then
                return nil
            end
            return pickLine(ok) or ok[1]
        end

        local function kickAmbientPicFx(battle, bracing)
            if not battle or not battle.picFxFor or not battle.player then
                return
            end
            local pf = battle:picFxFor(battle.player)
            if not pf then
                return
            end
            pf.kind, pf.t = bracing and "blink" or "bounce", 0
            if battle.fx then
                battle.fx.shake = math.max(battle.fx.shake or 0, bracing and 6 or 4)
            end
        end

        tickAmbientStance = function(battle, dt)
            if not opt("momentum_counter") or type(battle) ~= "table" then
                return
            end
            local state = momentumByBattle[battle]
            local phase = battle.phase
            if phase ~= "menu" and phase ~= "moveSelect" then
                clearAmbientStance(battle)
                return
            end
            -- Frozen / asleep: no idle HARDEN/GROWTH pulses.
            if playerStatusLocked(battle) then
                clearAmbientStance(battle)
                return
            end
            -- Don't fight real queue traffic / callout picks / an engine-owned anim.
            if battle.current or (battle.queue and #battle.queue > 0)
                or (battle.animPlaying and not battle._arAmbientOwned) then
                clearAmbientStance(battle)
                return
            end
            if not state or not state.temp then
                return
            end
            if state.awaitingPick then
                clearAmbientStance(battle)
                return
            end

            dt = tonumber(dt) or (1 / 60)
            if state.ambient then
                local ap = battle.animPlayer
                if ap and type(ap.update) == "function" then
                    pcall(ap.update, ap)
                end
                local done = true
                if ap and type(ap.isDone) == "function" then
                    local ok, d = pcall(ap.isDone, ap)
                    if ok then
                        done = d ~= false
                    end
                else
                    state.ambient.frames = (state.ambient.frames or 0) + 1
                    done = state.ambient.frames >= 40
                end
                if done then
                    clearAmbientStance(battle)
                    local r = (love and love.math and love.math.random) or math.random
                    local base = S.AMBIENT_DELAY or 2.2
                    local jit = S.AMBIENT_DELAY_JITTER or 1.0
                    state.ambientCd = base + r() * jit
                end
                return
            end

            local pool = ambientMovePool(state.temp)
            if not pool then
                state.ambientCd = nil
                return
            end
            state.ambientCd = (state.ambientCd or 0.35) - dt
            if state.ambientCd > 0 then
                return
            end

            local moveId = pickAmbientMove(battle, pool)
            local bracing = state.temp.entrenched
                or ((state.temp.defense or 0) > 0 and not state.temp.hidAway)
            local wasHidden = state.temp.picHidden == true
            -- Briefly reveal for leaf/growth pulses so the anim reads on-screen.
            if wasHidden and battle.picFxFor and battle.player then
                local pf = battle:picFxFor(battle.player)
                if pf then
                    pf.hidden = nil
                end
            end
            kickAmbientPicFx(battle, bracing)

            local started = false
            local ap = battle.animPlayer
            if moveId and ap and type(ap.start) == "function" then
                -- Start without flipping battle.animPlaying — keeps FIGHT menus alive.
                local ok = pcall(ap.start, ap, moveId, true)
                if ok then
                    battle._arAmbientOwned = true
                    started = true
                    dev.log(battle, "AMBIENT", tostring(moveId)
                        .. (bracing and " brace" or " hide"))
                end
            end
            state.ambient = {
                moveId = moveId,
                wasHidden = wasHidden,
                bracing = bracing,
                frames = 0,
            }
            if not started then
                -- picFx-only fallback — short pulse, then wait the delay again.
                state.ambient.frames = 28
            end
            state.ambientCd = 0
        end

        revealPlayerPic = function(battle, withEmerge)
            clearAmbientStance(battle)
            local state = battle and momentumByBattle[battle]
            local wasHidden = state and state.temp and state.temp.picHidden
            local coverSpot = state and state.temp and state.temp.coverSpot
            if state and state.temp then
                state.temp.picHidden = false
            end
            local player = battle and battle.player
            if not player or not wasHidden then
                return
            end
            local function showNow()
                if not battle.picFxFor then
                    return
                end
                local pf = battle:picFxFor(player)
                if not pf then
                    return
                end
                if withEmerge then
                    pf.kind, pf.t = "slideUp", 0
                    pf.hidden, pf.ox, pf.oy = nil, 0, 0
                else
                    pf.kind, pf.t, pf.hidden, pf.ox, pf.oy = nil, nil, nil, 0, 0
                end
            end
            if withEmerge and type(battle.queue) == "table" then
                -- Thematic "coming out" sparkle (same family as the hide).
                local spec = dodgeAnimSpec({ label = coverSpot }, battle)
                local emergeId = pickHideMoveAnim(battle, spec and spec.emerge or spec and spec.moves)
                battle.nextInsert = (battle.nextInsert or 0) + 1
                table.insert(battle.queue, battle.nextInsert, { fn = showNow, arFx = true })
                if emergeId and battle.data and battle.data.moves and battle.data.moves[emergeId] then
                    battle.nextInsert = (battle.nextInsert or 0) + 1
                    table.insert(battle.queue, battle.nextInsert, {
                        anim = emergeId,
                        attackerIsPlayer = true,
                        arFx = true,
                    })
                    dev.log(battle, "EMERGE anim",
                        tostring(coverSpot or "?") .. "→" .. tostring(emergeId))
                end
            else
                showNow()
            end
        end

        clearCalloutPickState = function(battle)
            if not battle then
                return
            end
            local state = momentumByBattle[battle]
            if state then
                state.awaitingPick = nil
                state.pendingDamage = nil
                state.pendingFoeReaction = nil
                state.suppressReactDefer = nil
            end
            battle._arSuppressReactDefer = nil
            -- Keep _arPickOfferedThisTurn until turn_started (resetMomentum).
        end

        local function scrubReactPickRows(battle)
            if type(battle) ~= "table" or type(battle.queue) ~= "table" then
                return
            end
            for i = #battle.queue, 1, -1 do
                local row = battle.queue[i]
                -- Strip every queued UI row when resolving a react — older hot-reload
                -- wraps sometimes inserted untagged { ui = ... } REACT menus.
                if type(row) == "table" and row.ui then
                    table.remove(battle.queue, i)
                end
            end
        end

        -- Foe dodge/brace stashed while COUNTER/HOLD is pending (so that menu
        -- isn't shown after "couldn't dodge!" as if they were related).
        local function flushPendingFoeReaction(battle)
            if not battle then
                return
            end
            local state = momentumByBattle[battle]
            local pending = state and state.pendingFoeReaction
            if state then
                state.pendingFoeReaction = nil
            end
            if not pending or not pending.moveDef then
                return
            end
            local foeLine, foeBuffs, foeTrack, failNarr =
                tryFoeCoverReaction(battle, pending.moveDef)
            if not foeLine and not failNarr then
                return
            end
            applyCalloutBuffs(battle, foeBuffs, foeTrack)
            -- If the real move anim is already gone from the queue, shouting / sparkles
            -- would land after damage/faint — keep the silent buffs only.
            if not indexOfMoveAnim(battle) then
                return
            end
            -- Insert fail first, then order: each insertBeforeAnim lands before anim,
            -- so later inserts sit earlier in the queue (order → fail → anim).
            if failNarr then
                local failItem = {
                    text = failNarr,
                    auto = true,
                    autoDelay = S.CALLOUT_AUTO_DELAY,
                }
                tagFieldCue(failItem, "enemy", "hit")
                insertBeforeAnim(battle, failItem)
            end
            if foeLine then
                local cue = fieldCueForFoeCover(foeBuffs, foeLine)
                local bubble = isDodgeFailNarrator(foeLine) and "narrator" or "foe"
                if not enqueueReactWithAttack(battle, foeLine, S.CALLOUT_AUTO_DELAY,
                    bubble, cue) then
                    local item = {
                        text = foeLine,
                        auto = true,
                        autoDelay = S.CALLOUT_AUTO_DELAY,
                    }
                    markBubbleWait(item, bubble, true, battle)
                    tagFieldCue(item, cue.side, cue.kind)
                    insertBeforeAnim(battle, item)
                end
            end
            -- Physical brace: Harden-style sparkle on the foe before your hit.
            if foeTrack and foeBuffs then
                local braced = false
                for i = 1, #foeBuffs do
                    if foeBuffs[i].stat == "defense" then
                        braced = true
                        break
                    end
                end
                if braced then
                    enqueueBraceAnim(battle, { foe = true, beforeAnim = true })
                end
            end
        end

        resolvePendingDamage = function(battle)
            if not battle then
                return
            end
            local state = momentumByBattle[battle]
            if not state or not state.pendingDamage then
                return
            end
            local pending = state.pendingDamage
            local wasCounter = state.awaitingPick == "counter"
            state.awaitingPick = nil
            state.pendingDamage = nil
            if wasCounter then
                -- Abandoned menu counts as HOLD.
                state.mode = nil
                state.boosted = false
            end
            if not pending.ctx then
                state.pendingFoeReaction = nil
                return
            end
            -- Strip any leftover pick UI rows so the hit can finish.
            if type(battle.queue) == "table" then
                for i = #battle.queue, 1, -1 do
                    local row = battle.queue[i]
                    if type(row) == "table" and row.ui then
                        table.remove(battle.queue, i)
                    end
                end
            end
            flushPendingFoeReaction(battle)
            if type(battle.queue) == "table" then
                battle.nextInsert = resumeInsertIndex(battle)
            end
            origRunDamaging(battle, pending.ctx, pending.record)
        end

        local function threatWantsPick(battle, move)
            if calloutPickMode() == "ALWAYS" then
                return true
            end
            if calloutPickMode() ~= "THREAT" then
                return false
            end
            local player = battle and battle.player
            local mon = player and player.mon
            if mon and mon.stats and mon.stats.hp and mon.stats.hp > 0 then
                if (mon.hp or 0) / mon.stats.hp <= lowHpRatio() then
                    return true
                end
            end
            local power = move and (move.power or 0) or 0
            if power >= 80 then
                return true
            end
            if power >= 40 and foeMoveIsSpecial(move) then
                return true
            end
            local foeLv = battle and battle.enemy and battle.enemy.mon and battle.enemy.mon.level
            local myLv = mon and mon.level
            if foeLv and myLv and (foeLv - myLv) >= 5 then
                return true
            end
            -- First meaningful foe hit this turn still opens the menu once.
            local state = momentumState(battle)
            if not state.pickOfferedThisTurn then
                return power >= 40
            end
            return false
        end

        local function shouldOfferCalloutPick(battle, move)
            if calloutPickMode() == "OFF" or not opt("momentum_counter") then
                return false
            end
            if not battle or not move then
                return false
            end
            if (move.power or 0) <= 0 or move.category == "status" then
                return false
            end
            -- Frozen / asleep: can't dodge, brace, or take orders.
            if playerStatusLocked(battle) then
                return false
            end
            -- Battle-owned latches: survive hot-reload weak momentum tables and
            -- older chained runDamaging wraps that still call shouldOffer.
            if battle._arPickOfferedThisTurn or battle._arSuppressReactDefer then
                return false
            end
            local state = momentumState(battle)
            -- One REACT! per turn. finishCalloutPick → origRunDamaging used to
            -- re-offer under ALWAYS (especially after TAKE COVER soaks the hit).
            if state.pickOfferedThisTurn or state.suppressReactDefer then
                return false
            end
            -- Focus trench: auto-hold in runDamaging (no REACT menu).
            if ReactiveDefense then
                local side = ReactiveDefense.sideState(battle, true)
                if side and side.entrenched and (side.entrenchTurns or 0) > 0 then
                    return false
                end
                return threatWantsPick(battle, move)
            end
            -- Legacy path (no Focus module).
            if playerInDeepCover(battle) then
                return false
            end
            if playerHoldingHide(battle) then
                return false
            end
            local st = momentumByBattle[battle]
            if st and st.temp and st.temp.entrenched then
                return false
            end
            return threatWantsPick(battle, move)
        end

        -- Random EVADE stages for a successful dodge (menu or auto).
        local function rollPlayerDodgeEvasion(isHide)
            local pools = S.DODGE_EVADE_ROLL or {}
            local pool = isHide and pools.hide or pools.basic
            if type(pool) ~= "table" or #pool == 0 then
                return isHide and 2 or 1
            end
            local n = pickLine(pool)
            n = tonumber(n) or (isHide and 2 or 1)
            return math.max(1, math.min(4, math.floor(n)))
        end

        -- Evasive hide (PATH / tree / dive / …): chance for +1 EVADE + flavor.
        local function tryVanishEvasion(battle, me)
            if not opt("momentum_counter") or not battle then
                return 0
            end
            local state = momentumState(battle)
            if not state.temp or not state.temp.hidAway then
                return 0
            end
            local r = (love and love.math and love.math.random) or math.random
            if r() >= (S.VANISH_CHANCE or 0.30) then
                return 0
            end
            local bonus = S.VANISH_EVADE_BONUS or 1
            applyCalloutBuffs(battle, {
                { who = "player", stat = "evasion", delta = bonus },
            }, true)
            local line = pickFormatted(S.VANISH_CALLS, me)
                or "Vanished from\nthe foe's sight!"
            enqueueAutoAfter(battle, line, S.CALLOUT_AUTO_DELAY, nil)
            dev.log(battle, "VANISH", "EV+" .. tostring(bonus))
            return bonus
        end

        local function maybeQueueHighEvadeLine(battle, me, evadeBoost)
            if (evadeBoost or 0) < 3 then
                return
            end
            local line = pickFormatted(S.DODGE_EVADE_HIGH_CALLS, me)
                or "Sharp instincts!"
            enqueueAutoAfter(battle, line, S.CALLOUT_AUTO_DELAY, nil)
        end

        local function finishCalloutPick(battle, me, moveName, action, braceCall)
            local state = momentumState(battle)
            -- Latch BEFORE resolving so a nested runDamaging / sticky pad press
            -- cannot queue another REACT! for this same hit.
            state.pickOfferedThisTurn = true
            state.suppressReactDefer = true
            -- Also on the battle object so hot-reload / chained wraps see it.
            battle._arPickOfferedThisTurn = true
            battle._arSuppressReactDefer = true
            state.awaitingPick = nil
            -- Invalidate any leftover REACT ui rows still sitting in the queue.
            state.reactEpoch = (state.reactEpoch or 0) + 1
            local pending = state.pendingDamage
            state.pendingDamage = nil
            state.enemyActedThisTurn = true

            -- Drop any leftover REACT! ui rows so the menu can't pop twice.
            scrubReactPickRows(battle)

            if action == "entrench_break" and ReactiveDefense then
                local ok = ReactiveDefense.earlyExitEntrench(battle, true)
                if ok then
                    enqueueAutoAfter(battle, "Broke entrench!", S.CALLOUT_AUTO_DELAY, "player")
                end
                action = "commit"
            end

            local result = { lines = {}, damageMult = 1, forceMiss = false }
            if ReactiveDefense and pending and pending.ctx then
                result = ReactiveDefense.resolveIncoming(battle, action, braceCall, pending.ctx)
                    or result
                ReactiveDefense.state(battle).hitMod = {
                    damageMult = result.damageMult or 1,
                    forceMiss = result.forceMiss == true,
                    coverSoak = result.coverSoak == true,
                    coverDurMult = result.coverDurMult or 1,
                }
            end

            -- Dodge / cover / brace FX before the foe's swing (or instead of it).
            if type(dev.playFocusReactFx) == "function" then
                dev.playFocusReactFx(battle, result.action or action, result)
            end

            for i = 1, #(result.lines or {}) do
                local line = result.lines[i]
                local item = { text = line, auto = true, autoDelay = S.CALLOUT_AUTO_DELAY }
                markBubbleWait(item, "player", true, battle)
                table.insert(battle.queue, 1, item)
            end

            dev.log(battle, "REACT " .. tostring(action),
                string.format("mult=%.2f miss=%s focus=%s",
                    tonumber(result.damageMult) or 1,
                    result.forceMiss and "Y" or "N",
                    ReactiveDefense and ReactiveDefense.focusLabel(battle, true) or "-"))

            if pending and pending.ctx then
                battle.nextInsert = resumeInsertIndex(battle)
                local okDmg, errDmg = pcall(function()
                    if result.forceMiss then
                        if type(battle.cancelMoveAnim) == "function" then
                            pcall(battle.cancelMoveAnim, battle)
                        end
                        if type(battle.waitNext) == "function" then
                            pcall(battle.waitNext, battle, 20)
                        end
                        -- Clear hitMod so a later hit isn't zeroed.
                        if ReactiveDefense then
                            ReactiveDefense.state(battle).hitMod = nil
                        end
                    else
                        -- REACT menu / cover FX can outlive BC's original arm — re-arm now so
                        -- the foe's swing still gets the attack camera.
                        signalAttackPresentation(
                            battle, pending.ctx.user, pending.ctx.target, pending.ctx.move,
                            { presentationOnly = true })
                        origRunDamaging(battle, pending.ctx, pending.record)
                    end
                    -- Lightweight reactive counters (Focus Dodge/Brace).
                    if result.counter and pending.ctx.user and battle.player then
                        local frac = result.counter.powerFrac or 0.35
                        if result.counter.absorbScale and result.counter.reduction then
                            frac = 0.25 + (result.counter.reduction or 0) * 0.5
                        end
                        local dealt = math.max(1, math.floor(
                            ((pending.ctx.move and pending.ctx.move.power) or 40) * frac * 0.4))
                        battle.nextInsert = resumeInsertIndex(battle)
                        if type(battle.sayNext) == "function" then
                            battle:sayNext(string.format("%s countered!", playerMonName(battle) or "Your Pokémon"))
                        end
                        if type(battle.applyDamage) == "function" then
                            local foe = battle.enemy
                            if foe and foe.mon and (foe.mon.hp or 0) > 0 then
                                battle:applyDamage(foe, dealt)
                                if foe.mon.hp <= 0 and type(battle.onFaint) == "function" then
                                    battle:onFaint(foe)
                                end
                            end
                        end
                    end
                end)
                if not okDmg then
                    -- Keep suppressReactDefer latched for the rest of the turn;
                    -- turn_started / clearCalloutPickState clear it.
                    error(errDmg, 0)
                end
            end
            -- Keep suppressReactDefer true until turn_started so sticky D-pad /
            -- multi-hit follow-ups cannot re-open REACT! this turn.
            state.pickOfferedThisTurn = true
            publishChipState(battle)
        end

        local function newCalloutPickModal(game, opts)
            local Font = require("src.render.Font")
            local Sound = require("src.core.Sound")
            local choices = opts.choices or {}
            local start = tonumber(opts.index) or 1
            if start < 1 then
                start = 1
            end
            if #choices > 0 and start > #choices then
                start = #choices
            end
            -- D-pad picks instantly when there are few options (REACT / BRACE / STAY).
            -- Long lists (COUNTER move pick) keep cursor + A.
            local usePad = opts.pad
            if usePad == nil then
                usePad = #choices > 0 and #choices <= 5
            end

            local function ensurePadDirs()
                if not usePad then
                    return
                end
                for i = 1, #choices do
                    if choices[i].dir then
                        return
                    end
                end
                local byId = {}
                for i = 1, #choices do
                    local id = choices[i].id
                    if id then
                        byId[id] = choices[i]
                    end
                end
                if byId.dodge or byId.commit or byId.entrench then
                    if byId.dodge then
                        byId.dodge.dir = "up"
                    end
                    if byId.cover then
                        byId.cover.dir = "left"
                    end
                    if byId.brace then
                        byId.brace.dir = "right"
                    end
                    if byId.entrench then
                        byId.entrench.dir = "down"
                    end
                    if byId.commit then
                        byId.commit.dir = "a"
                    end
                    if byId.entrench_hold then
                        byId.entrench_hold.dir = "down"
                    end
                    if byId.entrench_break then
                        byId.entrench_break.dir = "up"
                    end
                    return
                end
                local n = #choices
                if n == 1 then
                    choices[1].dir = "a"
                elseif n == 2 then
                    choices[1].dir = "up"
                    choices[2].dir = "down"
                elseif n == 3 then
                    choices[1].dir = "up"
                    choices[2].dir = "left"
                    choices[3].dir = "right"
                elseif n == 4 then
                    choices[1].dir = "up"
                    choices[2].dir = "left"
                    choices[3].dir = "right"
                    choices[4].dir = "down"
                else
                    choices[1].dir = "up"
                    choices[2].dir = "left"
                    choices[3].dir = "right"
                    choices[4].dir = "down"
                    choices[5].dir = "a"
                end
            end
            ensurePadDirs()

            local self = {
                game = game,
                title = tostring(opts.title or "DODGE!"),
                subtitle = opts.subtitle and tostring(opts.subtitle) or nil,
                choices = choices,
                index = start,
                usePad = usePad,
                cancelable = opts.cancelable == true,
                onPick = opts.onPick,
                onCancel = opts.onCancel,
                -- Instant D-pad picks must not fire on the same press that opened
                -- this modal (or a leftover held direction from the prior menu).
                _padArmed = not usePad,
                _resolved = false,
            }

            local function hintFor(choice)
                if not choice then
                    return ""
                end
                if choice.hint then
                    return tostring(choice.hint)
                end
                local line = tostring(choice.line or "")
                line = line:gsub("%%s", ""):gsub("!", ""):gsub("\n", " ")
                line = line:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
                if #line > 16 then
                    line = line:sub(1, 15) .. "."
                end
                return line
            end

            local function choiceForDir(dir)
                for i = 1, #self.choices do
                    if self.choices[i].dir == dir then
                        return self.choices[i]
                    end
                end
                return nil
            end

            local function anyPadDown(input)
                local down = input.isDown or input.down
                if type(down) ~= "function" then
                    return false
                end
                return down(input, "up") or down(input, "down")
                    or down(input, "left") or down(input, "right")
                    or down(input, "a")
            end

            local function confirm(choice)
                if self._resolved or not choice then
                    return
                end
                self._resolved = true
                Sound.play(self.game.data, "Press_AB")
                self.game.stack:pop()
                if self.onPick then
                    self.onPick(choice)
                end
            end

            -- Filled triangle arrows so D-pad mapping reads at a glance.
            local function drawPadArrow(dir, cx, cy, enabled)
                local g = love.graphics
                local s = 3.5
                if enabled == false then
                    g.setColor(0.45, 0.45, 0.45, 1)
                else
                    g.setColor(0, 0, 0, 1)
                end
                if dir == "up" then
                    g.polygon("fill", cx, cy - s, cx - s, cy + s * 0.55, cx + s, cy + s * 0.55)
                elseif dir == "down" then
                    g.polygon("fill", cx, cy + s, cx - s, cy - s * 0.55, cx + s, cy - s * 0.55)
                elseif dir == "left" then
                    g.polygon("fill", cx - s, cy, cx + s * 0.55, cy - s, cx + s * 0.55, cy + s)
                elseif dir == "right" then
                    g.polygon("fill", cx + s, cy, cx - s * 0.55, cy - s, cx - s * 0.55, cy + s)
                end
            end

            local function drawAKey(cx, cy, enabled)
                local g = love.graphics
                if enabled == false then
                    g.setColor(0.45, 0.45, 0.45, 1)
                else
                    g.setColor(0, 0, 0, 1)
                end
                -- Compact R/B/Y-style key hint (no filled disc).
                g.rectangle("line", cx - 5, cy - 5, 10, 10)
                g.setColor(0, 0, 0, 1)
                Font.draw("A", cx - 3, cy - 4)
            end

            function self:update(dt)
                local input = self.game.input
                local n = #self.choices
                if n < 1 or self._resolved then
                    return
                end
                if self.cancelable
                    and (input:wasPressed("b") or input:wasPressed("start")) then
                    self._resolved = true
                    Sound.play(self.game.data, "Press_AB")
                    self.game.stack:pop()
                    if self.onCancel then
                        self.onCancel()
                    end
                    return
                end
                if self.usePad then
                    -- Wait until every direction/A is released once so a held
                    -- press from opening / the previous modal cannot auto-pick.
                    if not self._padArmed then
                        if not anyPadDown(input) then
                            self._padArmed = true
                        end
                        return
                    end
                    local dir = nil
                    if input:wasPressed("up") then
                        dir = "up"
                    elseif input:wasPressed("down") then
                        dir = "down"
                    elseif input:wasPressed("left") then
                        dir = "left"
                    elseif input:wasPressed("right") then
                        dir = "right"
                    elseif input:wasPressed("a") then
                        dir = "a"
                    end
                    if dir then
                        confirm(choiceForDir(dir))
                    end
                    return
                end
                if input:wasPressed("up") then
                    self.index = self.index > 1 and self.index - 1 or n
                elseif input:wasPressed("down") then
                    self.index = self.index < n and self.index + 1 or 1
                elseif input:wasPressed("a") then
                    confirm(self.choices[self.index])
                end
            end

            function self:draw()
                local n = #self.choices
                if n < 1 then
                    return
                end
                local g = love.graphics

                if self.usePad then
                    -- Spatial D-pad compass (same language as the FIELD move diamond).
                    -- Compact bottom panel keeps mons / HP / weather readable above.
                    local function shortLabel(choice)
                        local name = tostring(choice and choice.label or "")
                        if name == "TAKE COVER" then
                            return "COVER"
                        end
                        if name == "STAY COVER" then
                            return "STAY"
                        end
                        if name == "PHYSICAL" then
                            return "PHYS"
                        end
                        if name == "SPECIAL" then
                            return "SPEC"
                        end
                        return name
                    end
                    local function textW(label)
                        if type(Font.width) == "function" then
                            return Font.width(label)
                        end
                        return #Font.split(label) * 8
                    end
                    local preferred = self.choices[self.index]
                    local slots = {
                        up = { x = 56, y = 92, w = 48, h = 12 },
                        left = { x = 8, y = 108, w = 52, h = 12 },
                        right = { x = 100, y = 108, w = 52, h = 12 },
                        down = { x = 56, y = 124, w = 48, h = 12 },
                        a = { x = 56, y = 136, w = 48, h = 11 },
                    }
                    -- Cream panel across the lower third only.
                    g.setColor(0.96, 0.92, 0.82, 0.96)
                    g.rectangle("fill", 0, 78, 160, 66)
                    g.setColor(0.10, 0.07, 0.06, 1)
                    g.rectangle("line", 0.5, 78.5, 159, 65)
                    g.rectangle("line", 1.5, 79.5, 157, 63)
                    -- Title + tiny subtitle on one header row.
                    local title = self.title or "REACT!"
                    g.setColor(0.08, 0.06, 0.05, 1)
                    Font.draw(title, 6, 80)
                    if self.subtitle then
                        local sub = tostring(self.subtitle)
                        if #sub > 10 then
                            sub = sub:sub(1, 9) .. "."
                        end
                        g.setColor(0.40, 0.34, 0.28, 1)
                        local subX = 160 - 6 - math.floor(textW(sub) * 0.75)
                        g.push()
                        g.translate(math.max(70, subX), 81)
                        g.scale(0.75, 0.75)
                        Font.draw(sub, 0, 0)
                        g.pop()
                    end
                    for _, dir in ipairs({ "up", "left", "right", "down", "a" }) do
                        local choice = choiceForDir(dir)
                        local slot = slots[dir]
                        if choice and slot then
                            local selected = preferred == choice
                            local label = shortLabel(choice)
                            if choice.disabled then
                                label = "(" .. label .. ")"
                            end
                            if selected then
                                g.setColor(0.16, 0.30, 0.55, 1)
                            else
                                g.setColor(0.99, 0.96, 0.88, 1)
                            end
                            g.rectangle("fill", slot.x, slot.y, slot.w, slot.h)
                            g.setColor(0.10, 0.08, 0.06, 1)
                            g.rectangle("line", slot.x + 0.5, slot.y + 0.5,
                                slot.w - 1, slot.h - 1)
                            local glyphX = slot.x + 7
                            local glyphY = slot.y + 6
                            if dir == "a" then
                                drawAKey(glyphX, glyphY, not choice.disabled)
                            else
                                drawPadArrow(dir, glyphX, glyphY, not choice.disabled)
                            end
                            local scale = (#label > 6) and 0.72 or 0.85
                            if selected then
                                g.setColor(1, 1, 1, 1)
                            else
                                g.setColor(0.08, 0.06, 0.05, 1)
                            end
                            g.push()
                            g.translate(slot.x + 14, slot.y + 2)
                            g.scale(scale, scale)
                            Font.draw(label, 0, 0)
                            g.pop()
                        end
                    end
                    g.setColor(1, 1, 1, 1)
                    return
                end

                local widest = #Font.split(self.title)
                if self.subtitle then
                    widest = math.max(widest, #Font.split(self.subtitle))
                end
                for i = 1, n do
                    local label = tostring(self.choices[i].label or "")
                    widest = math.max(widest, #Font.split(label) + 2)
                end
                local tw = math.min(16, math.max(10, widest + 2))
                local head = self.subtitle and 2 or 1
                local th = head + n + 2
                local tx = 1
                local ty = math.max(1, 13 - th)
                if ty + th > 13 then
                    th = 13 - ty
                end

                Font.drawBox(tx, ty, tw, th)
                love.graphics.setColor(0, 0, 0, 1)
                Font.draw(self.title, (tx + 1) * 8, (ty + 1) * 8)
                local row = ty + 2
                if self.subtitle then
                    Font.draw(self.subtitle, (tx + 1) * 8, row * 8)
                    row = row + 1
                end
                for i = 1, n do
                    local choice = self.choices[i]
                    local y = row * 8
                    if i == self.index then
                        Font.drawCode(0xED, tx * 8 + 2, y)
                    end
                    Font.draw(tostring(choice.label or ""), (tx + 2) * 8, y)
                    row = row + 1
                    if row >= ty + th - 1 then
                        break
                    end
                end
                love.graphics.setColor(1, 1, 1, 1)
            end

            return self
        end

        -- Serious hits: Focus menu — Dodge / Cover / Brace / Entrench / Commit.
        local function queueCalloutPickMenu(battle, me, moveName, preferredKind)
            if not ReactiveDefense then
                -- Fallback: commit through immediately.
                finishCalloutPick(battle, me, moveName, "commit", nil)
                return
            end
            local function openReactMenu()
                local pendingMove = nil
                do
                    local st = momentumState(battle)
                    pendingMove = st.pendingDamage and st.pendingDamage.ctx
                        and st.pendingDamage.ctx.move
                end
                local actions = ReactiveDefense.menuActions(battle, pendingMove)
                local choices = {}
                local index = 1
                for i = 1, #actions do
                    local a = actions[i]
                    -- menuActions already omits unaffordable reacts.
                    choices[#choices + 1] = {
                        label = a.label,
                        hint = a.hint,
                        id = a.id,
                        afford = true,
                    }
                    if preferredKind and a.id == preferredKind then
                        index = #choices
                    end
                end
                if #choices == 0 then
                    choices[1] = { label = "COMMIT", hint = "Take the hit", id = "commit" }
                end
                return newCalloutPickModal(battle.game, {
                    title = "REACT!",
                    subtitle = me,
                    index = index,
                    pad = true,
                    choices = choices,
                    cancelable = false,
                    onPick = function(choice)
                        local id = choice and choice.id or "commit"
                        -- Brace used to open a second D-pad (PHYS/SPEC/STAT) that
                        -- felt like REACT! repeating — auto-match the incoming hit.
                        if id == "brace" then
                            local call = foeMoveIsSpecial(pendingMove) and "special"
                                or "physical"
                            if pendingMove and pendingMove.category == "status" then
                                call = "status"
                            end
                            finishCalloutPick(battle, me, moveName, "brace", call)
                            return
                        end
                        finishCalloutPick(battle, me, moveName, id, nil)
                    end,
                })
            end
            scrubReactPickRows(battle)
            local reactEpoch = (momentumState(battle).reactEpoch or 0) + 1
            momentumState(battle).reactEpoch = reactEpoch
            insertBeforeAnim(battle, {
                arReactPick = true,
                arReactEpoch = reactEpoch,
                ui = function()
                    local st = momentumState(battle)
                    -- Stale / duplicate rows after a pick already resolved.
                    if not st.pendingDamage or st.suppressReactDefer
                        or (st.reactEpoch or 0) ~= reactEpoch then
                        return {
                            game = battle.game,
                            update = function(self)
                                if self.game and self.game.stack then
                                    self.game.stack:pop()
                                end
                            end,
                            draw = function() end,
                        }
                    end
                    return openReactMenu()
                end,
            })
        end

        local function finishSameTurnCounter(battle, choice)
            local state = momentumState(battle)
            state.sameTurnCounterQueued = nil
            local replacing = state.replaceQueuedPlayerAction
            -- Miss text belongs before COUNTER!; never replay it after the strike.
            scrubLateDodgeWhiff(battle)
            if not choice or choice.hold or tostring(choice.label or "") == "HOLD" then
                state.mode = nil
                state.boosted = false
                state.foeWhiffDamage = nil
                state.replaceQueuedPlayerAction = nil
                dev.log(battle, "COUNTER! pick",
                    replacing and "HOLD keep-plan" or "HOLD skip")
                publishChipState(battle)
                -- Going second + HOLD: keep the move you picked at turn start.
                return
            end
            local moveInst = choice.moveInst
            if not moveInst or not battle.player or not battle.enemy then
                state.mode = nil
                state.boosted = false
                state.replaceQueuedPlayerAction = nil
                publishChipState(battle)
                return
            end
            if (battle.player.mon and battle.player.mon.hp or 0) <= 0
                or (battle.enemy.mon and battle.enemy.mon.hp or 0) <= 0 then
                state.mode = nil
                state.boosted = false
                state.replaceQueuedPlayerAction = nil
                publishChipState(battle)
                return
            end
            -- Keep opening armed; announce becomes "Counter with X!" + boosted damage.
            state.mode = "counter"
            state.boosted = false
            state.sameTurnCounterStrike = true
            local moveName = tostring(choice.label or moveInst.id or "MOVE")
            if replacing then
                -- Swap the queued turn action for the move you just picked.
                state.overridePlayerAction = moveInst
                state.replaceQueuedPlayerAction = nil
                dev.log(battle, "COUNTER! pick", "replace→" .. moveName)
                publishChipState(battle)
                return
            end
            -- You already attacked this turn: fire an extra counter strike now.
            dev.log(battle, "COUNTER! pick", "extra→" .. moveName)
            table.insert(battle.queue, 1, {
                arFx = true,
                fn = function()
                    if not battle.player or not battle.enemy then
                        return
                    end
                    if (battle.player.mon.hp or 0) <= 0 or (battle.enemy.mon.hp or 0) <= 0 then
                        state.mode = nil
                        publishChipState(battle)
                        return
                    end
                    -- Idle BC camera often takes over during the COUNTER! menu — snap it
                    -- back; performMove wrap + engine move_used re-arm the attack cam.
                    resetBattleCamera(battle)
                    battle:performMove(battle.player, battle.enemy, moveInst)
                end,
            })
            publishChipState(battle)
        end

        maybeQueueSameTurnCounter = function(battle)
            if not opt("momentum_counter") or not battle then
                return
            end
            local state = momentumByBattle[battle]
            if not state or not state.offerSameTurnCounter then
                return
            end
            state.offerSameTurnCounter = nil
            if playerStatusLocked(battle) then
                dev.log(battle, "COUNTER! skip", "status-locked")
                return
            end
            if state.sameTurnCounterQueued or not playerHasCounter(battle) then
                dev.log(battle, "COUNTER! skip",
                    state.sameTurnCounterQueued and "already-queued"
                    or "not-armed")
                return
            end
            if (battle.player and battle.player.mon and battle.player.mon.hp or 0) <= 0 then
                state.mode = nil
                return
            end
            if (battle.enemy and battle.enemy.mon and battle.enemy.mon.hp or 0) <= 0 then
                state.mode = nil
                return
            end
            state.sameTurnCounterQueued = true
            local me = playerMonName(battle)
            local replacing = state.replaceQueuedPlayerAction
            local moves = battle.player and battle.player.curMoves or {}
            local choices = {}
            for i = 1, #moves do
                local mv = moves[i]
                if mv and not mv.struggle and (mv.pp or 0) > 0 then
                    local def = nil
                    if type(battle.moveDef) == "function" then
                        def = battle:moveDef(mv)
                    end
                    if not def then
                        def = findMoveByName(battle, mv.id or mv.name)
                    end
                    if def and (def.power or 0) > 0 and def.category ~= "status" then
                        choices[#choices + 1] = {
                            label = tostring(def.name or mv.id or "MOVE"),
                            hint = "PP " .. tostring(mv.pp),
                            moveInst = mv,
                            moveDef = def,
                        }
                    end
                end
            end
            choices[#choices + 1] = {
                label = "HOLD",
                hint = replacing and "Keep plan" or "Skip counter",
                hold = true,
            }
            -- After miss anim + dodge-whiff text — never before the foe's swing.
            dev.log(battle, "COUNTER! menu",
                replacing and "re-pick after miss anim" or "extra strike after miss anim")
            insertAfterMissAnim(battle, {
                ui = function()
                    return newCalloutPickModal(battle.game, {
                        title = "COUNTER!",
                        subtitle = replacing and "Pick a move" or me,
                        choices = choices,
                        pad = false,
                        cancelable = false,
                        onPick = function(choice)
                            finishSameTurnCounter(battle, choice)
                        end,
                    })
                end,
            })
            -- Opening is live after "dodged aside!" — chip can show ready-to-counter.
            publishChipState(battle)
        end

        local function finishCounterPick(battle, me, moveName, doCounter)
            local state = momentumState(battle)
            state.awaitingPick = nil
            local pending = state.pendingDamage
            state.pendingDamage = nil

            if doCounter then
                -- Leave mode=counter so battle.damage still applies +25%.
                state.mode = "counter"
                state.boosted = false
                local line, drop = pickCallEntry("counter", battle, me, moveName)
                line = line or ("Now, " .. me .. "!\nHit back!")
                drop = drop or 1
                do
                    local item = {
                        text = line,
                        auto = true,
                        autoDelay = S.CALLOUT_AUTO_DELAY,
                    }
                    markBubbleWait(item, "player", true, battle)
                    tagFieldCue(item, "player", "attack", "physical")
                    table.insert(battle.queue, 1, item)
                end
                battle.nextInsert = 1
                applyCalloutBuffs(battle, {
                    { who = "enemy", stat = "defense", delta = -drop, fromEnemy = true },
                }, false)
                dev.log(battle, "OPENING! pick",
                    "COUNTER " .. tostring(moveName) .. " foeDF-" .. tostring(drop))
            else
                state.mode = nil
                state.boosted = false
                state.foeWhiffDamage = nil
                dev.log(battle, "OPENING! pick", "HOLD (clear arm)")
            end

            if pending and pending.ctx then
                -- Foe dodge/brace after your COUNTER/HOLD choice, before the hit.
                flushPendingFoeReaction(battle)
                battle.nextInsert = resumeInsertIndex(battle)
                origRunDamaging(battle, pending.ctx, pending.record)
                if doCounter then
                    local connected = state.boosted
                    -- Damage hook should have consumed the boost; clear arming either way.
                    state.mode = nil
                    if resolvePlayerCounterAttempt(battle, connected) then
                        -- Foe snap-back queued; skip Again!
                    elseif connected then
                        -- Anime follow-through: true second hit if the foe is still up.
                        tryAgainStrike(battle, pending.ctx, me, false)
                    end
                end
            elseif doCounter then
                state.mode = nil
                state.pendingFoeReaction = nil
                state.foeWhiffDamage = nil
            end
        end

        local function queueCounterPickMenu(battle, me, moveName)
            insertBeforeAnim(battle, {
                ui = function()
                    return newCalloutPickModal(battle.game, {
                        title = "OPENING!",
                        subtitle = me,
                        choices = {
                            {
                                label = "COUNTER",
                                hint = "Hit back harder",
                                line = "",
                            },
                            {
                                label = "HOLD",
                                hint = "Save the opening",
                                line = "",
                            },
                        },
                        cancelable = false,
                        onPick = function(choice)
                            local doCounter = choice and tostring(choice.label) == "COUNTER"
                            finishCounterPick(battle, me, moveName, doCounter)
                        end,
                    })
                end,
            })
        end

        local function shouldDeferForCalloutPick(battle, ctx)
            if not battle or not ctx then
                return false
            end
            local user, target, move = ctx.user, ctx.target, ctx.move
            if not user or user.isPlayer or not target or not target.isPlayer then
                return false
            end
            if battle._arSuppressReactDefer or battle._arPickOfferedThisTurn then
                return false
            end
            if not shouldOfferCalloutPick(battle, move) then
                return false
            end
            local state = momentumState(battle)
            -- Already resolved this hit (finishCalloutPick → origRunDamaging), or
            -- a pick is already open / pending.
            if state.suppressReactDefer or state.awaitingPick or state.pendingDamage then
                return false
            end
            return true
        end

        -- Any armed opening + your damaging attack: auto "Counter with X!" (+25%).
        -- No OPENING! COUNTER/HOLD menu — that used to pop at turn-start before
        -- anyone acted whenever a prior-turn opening was still armed.
        local function shouldAutoCounter(battle, ctx)
            if not opt("momentum_counter") or not battle or not ctx then
                return false
            end
            local user, target, move = ctx.user, ctx.target, ctx.move
            if not user or not user.isPlayer or not target or target.isPlayer then
                return false
            end
            if not move or (move.power or 0) <= 0 or move.category == "status" then
                return false
            end
            -- Frozen / asleep: can't take a counter order.
            if playerStatusLocked(battle) then
                return false
            end
            if not playerHasCounter(battle) then
                return false
            end
            local state = momentumState(battle)
            if state.awaitingPick or state.pendingDamage then
                return false
            end
            return true
        end

        function EffectRegistry.runDamaging(battle, ctx, record)
            -- Focus trench: soak the hit with entrench mitigation (no REACT menu).
            if ReactiveDefense and opt("momentum_counter") and battle and ctx
                and ctx.user and not ctx.user.isPlayer
                and ctx.target and ctx.target.isPlayer then
                local side = ReactiveDefense.sideState(battle, true)
                local state = momentumState(battle)
                if side and side.entrenched and (side.entrenchTurns or 0) > 0
                    and not state.awaitingPick and not state.pendingDamage then
                    local move = ctx.move
                    local me = playerMonName(battle)
                    local moveName = tostring((move and (move.name or move.id)) or "MOVE")
                    state.awaitingPick = "react"
                    state.pendingDamage = { ctx = ctx, record = record }
                    do
                        local animIdx = indexOfMoveAnim(battle)
                        local row = animIdx and battle.queue[animIdx]
                        if row and row.anim then
                            battle.moveAnimRow = row
                        end
                    end
                    dev.log(battle, "AUTO entrench_hold", tostring(moveName))
                    finishCalloutPick(battle, me, moveName, "entrench_hold", nil)
                    return
                end
            end
            if shouldDeferForCalloutPick(battle, ctx) then
                local state = momentumState(battle)
                local move = ctx.move
                -- Cursor default only — menu always offers Focus options.
                local preferred = foeMoveIsSpecial(move) and "dodge" or "brace"
                state.awaitingPick = "react"
                state.pendingDamage = { ctx = ctx, record = record }
                state.pickOfferedThisTurn = true
                battle._arPickOfferedThisTurn = true
                -- Pin the engine's attack anim so finishCalloutPick resumes after it
                -- (not before endOfTurn). Without this, REACT! landed after the swing.
                do
                    local animIdx = indexOfMoveAnim(battle)
                    local row = animIdx and battle.queue[animIdx]
                    if row and row.anim then
                        battle.moveAnimRow = row
                    end
                end
                local me = playerMonName(battle)
                local moveName = tostring(move.name or move.id or "MOVE")
                dev.log(battle, "MENU react",
                    tostring(moveName) .. " prefer=" .. preferred .. " (defer hit)")
                queueCalloutPickMenu(battle, me, moveName, preferred)
                return
            end
            -- Armed opening: auto counter (no OPENING! menu — same-turn COUNTER!
            -- after a dodge miss is the interactive pick).
            if shouldAutoCounter(battle, ctx) then
                local state = momentumState(battle)
                local me = playerMonName(battle)
                local move = ctx.move
                local moveName = tostring(move.name or move.id or "MOVE")
                state.mode = "counter"
                state.boosted = false
                local drop = 1
                local style = calloutStyle()
                if style == "SHOWY" or style == "BOLD" then
                    drop = 2
                end
                dev.log(battle, "AUTO counter",
                    tostring(moveName) .. " foeDF-" .. tostring(drop)
                    .. (state.enemyActedThisTurn and " (2nd)" or " (1st)"))
                applyCalloutBuffs(battle, {
                    { who = "enemy", stat = "defense", delta = -drop, fromEnemy = true },
                }, false)
                flushPendingFoeReaction(battle)
                local result = origRunDamaging(battle, ctx, record)
                local connected = state.boosted
                state.mode = nil
                publishChipState(battle)
                if resolvePlayerCounterAttempt(battle, connected) then
                    return result
                end
                if connected then
                    tryAgainStrike(battle, ctx, me, false)
                end
                return result
            end
            local state = battle and momentumState(battle)
            local enemyCounterArmed = state
                and ctx and ctx.user and not ctx.user.isPlayer
                and state.enemyMode == "counter" and not state.enemyBoosted
            -- If COUNTER/HOLD wasn't needed, still play any stashed foe reaction.
            flushPendingFoeReaction(battle)
            local result = origRunDamaging(battle, ctx, record)
            -- Trainer foe mirror: after their counter lands, sometimes Again!
            if enemyCounterArmed and state.enemyBoosted and trainerFoeReactionsOn(battle)
                and rollEnemyAgain() then
                tryAgainStrike(battle, ctx, enemyMonName(battle), true)
            end
            if enemyCounterArmed then
                state.enemyMode = nil
                publishChipState(battle)
            end
            -- Same-turn COUNTER! waits for dodge-whiff text in wrapBattleSay.
            return result
        end

        EffectRegistry._arReactRunDamaging = EffectRegistry.runDamaging

        local function silentStageDelta(who, stat, delta)
            if not who or not who.stages or not stat or not delta or delta == 0 then
                return
            end
            local cur = who.stages[stat] or 0
            who.stages[stat] = math.max(-6, math.min(6, cur + delta))
            who.hazeStatReset = nil
        end

        applyCalloutBuffs = function(battle, buffs, trackTemp)
            if not opt("callout_buffs") or not buffs or not battle then
                return
            end
            local state = momentumState(battle)
            for i = 1, #buffs do
                local b = buffs[i]
                local who = b.who
                local whoTag = tostring(who or "?")
                if who == "player" then
                    who = battle.player
                elseif who == "enemy" then
                    who = battle.enemy
                end
                if who and who.stages and b.stat and b.delta and b.delta ~= 0 then
                    local before = who.stages[b.stat] or 0
                    -- Callout already said what to do — apply stages with no rose/fell dialogue.
                    MoveEffects.changeStage(
                        battle, who, b.stat, b.delta, b.fromEnemy and true or false)
                    local after = who.stages[b.stat] or 0
                    local applied = after - before
                    if trackTemp and applied ~= 0 then
                        if who == battle.player then
                            if b.stat == "evasion" then
                                state.temp.evasion = (state.temp.evasion or 0) + applied
                            elseif b.stat == "defense" then
                                state.temp.defense = (state.temp.defense or 0) + applied
                            end
                        elseif who == battle.enemy then
                            if not state.enemyTemp then
                                state.enemyTemp = { evasion = 0, defense = 0, cover = false }
                            end
                            if b.stat == "evasion" then
                                state.enemyTemp.evasion = (state.enemyTemp.evasion or 0) + applied
                            elseif b.stat == "defense" then
                                state.enemyTemp.defense = (state.enemyTemp.defense or 0) + applied
                            end
                        end
                    end
                    if applied ~= 0 then
                        dev.log(battle, "BUFF",
                            string.format("%s %s %+d→%d%s",
                                whoTag, tostring(b.stat), applied, after,
                                trackTemp and " (temp)" or ""))
                    end
                end
            end
        end

        -- STAY is only for a real hide/fly spot — not a plain sidestep or brace.
        playerCanStay = function(battle)
            if not opt("momentum_counter") or not battle then
                return false
            end
            local state = momentumState(battle)
            local t = state.temp
            return t and t.hidAway and (t.cover or t.picHidden)
        end

        -- Already holding a hide spot — don't ask grass/path again.
        playerHoldingHide = function(battle)
            if not battle then
                return false
            end
            local state = momentumByBattle[battle]
            local t = state and state.temp
            return t and t.hidAway and (t.cover or t.picHidden)
        end

        playerInDeepCover = function(battle)
            local state = battle and momentumByBattle[battle]
            return state and state.temp and state.temp.deepCover == true
        end

        rememberCoverSpot = function(battle, label)
            local state = momentumState(battle)
            local spot = tostring(label or ""):upper()
            if spot == "" or spot == "DODGE" then
                spot = (S.SCENE_COVER_SPOT and S.SCENE_COVER_SPOT[battleScene(battle)])
                    or "COVER"
            end
            state.temp.coverSpot = spot
            return spot
        end

        pickDeepCoverLine = function(battle)
            local me = playerMonName(battle)
            local state = momentumState(battle)
            local spot = tostring((state.temp and state.temp.coverSpot) or ""):upper()
            local pack = S.DEEP_COVER_CALLS or {}
            local list = pack[spot] or pack._default
            return pickFormatted(list, me)
                or (me .. " can't leave\ncover yet!")
        end

        -- Keep the Dig/Fly-style hide while STAY-ing in cover.
        ensurePlayerPicHidden = function(battle, withAnim)
            local state = momentumState(battle)
            local t = state.temp
            if not t or not t.hidAway then
                return
            end
            if t.picHidden and not withAnim then
                local player = battle.player
                if player and battle.picFxFor then
                    local pf = battle:picFxFor(player)
                    if pf then
                        pf.hidden = true
                    end
                end
                return
            end
            enqueueDodgeHideAnim(battle, { label = t.coverSpot or "COVER" })
        end

        -- ~30% while in a real hide: this turn you're stuck deep (no action/callout).
        rollDeepCoverLock = function(battle)
            if not playerCanStay(battle) then
                return false
            end
            local state = momentumState(battle)
            local t = state.temp
            if t.deepCoverRolled then
                return t.deepCover == true
            end
            t.deepCoverRolled = true
            local r = (love and love.math and love.math.random) or math.random
            if r() < (S.DEEP_COVER_CHANCE or 0.30) then
                t.deepCover = true
                if not t.coverSpot or t.coverSpot == "" then
                    rememberCoverSpot(battle, nil)
                end
                dev.log(battle, "DEEP cover",
                    "lock spot=" .. tostring(t.coverSpot or "?"))
                publishChipState(battle)
                return true
            end
            return false
        end

        local function resolveCoverOnPlayerAttack(battle, monName)
            clearAmbientStance(battle)
            local state = momentumState(battle)
            local temp = state.temp or { evasion = 0, defense = 0, cover = false, picHidden = false }
            local player = battle.player
            if player and player.stages then
                if (temp.evasion or 0) ~= 0 then
                    silentStageDelta(player, "evasion", -(temp.evasion or 0))
                end
                if (temp.defense or 0) ~= 0 then
                    silentStageDelta(player, "defense", -(temp.defense or 0))
                end
            end
            local hadCover = temp.cover
            -- Real hide/fly spot only — plain DODGE sidesteps must not shout "Coming out!".
            local hadHide = temp.hidAway == true
            local goingFirst = not state.enemyActedThisTurn
            if hadCover or hadHide or (temp.evasion or 0) ~= 0 or (temp.defense or 0) ~= 0 then
                dev.log(battle, "CLEAR youCover",
                    string.format("hadCover=%s hide=%s first=%s was=%s",
                        hadCover and "Y" or "N",
                        hadHide and "Y" or "N",
                        goingFirst and "Y" or "N",
                        dev.fmtTemp(temp)))
            end
            -- Pop back onto the field when leaving a real hide (not a sidestep).
            revealPlayerPic(battle, hadHide)
            state.temp = {
                evasion = 0,
                defense = 0,
                cover = false,
                picHidden = false,
                entrenched = false,
                entrenchTurns = 0,
                hidAway = false,
                coverSpot = nil,
                deepCover = false,
                deepCoverRolled = false,
                dodgedOk = false,
            }

            -- Leaving a real hide to attack → "Coming out!" (any speed order).
            -- Frozen / asleep: no trainer shout.
            if not opt("callout_buffs") or not hadHide or not player
                or playerStatusLocked(battle) then
                publishChipState(battle)
                return nil
            end
            -- Leaving cover to strike first is riskier.
            if goingFirst then
                silentStageDelta(player, "defense", -1)
            end
            -- If COUNTER/HOLD is about to open, skip the leave-cover shout so the
            -- two don't stack into one confusing beat.
            if playerHasCounter(battle) then
                publishChipState(battle)
                return true
            end
            local line = pickFormatted(S.LEAVE_COVER_CALLS, monName)
                or (monName .. "!\nComing out!")
            enqueueAutoAfter(battle, line, nil, "player")
            publishChipState(battle)
            return true
        end

        -- Foe leaves cover to attack: strip their temp EVADE/DEF.
        local function resolveCoverOnEnemyAttack(battle, monName)
            local state = momentumState(battle)
            local temp = state.enemyTemp or { evasion = 0, defense = 0, cover = false }
            local enemy = battle.enemy
            if enemy and enemy.stages then
                if (temp.evasion or 0) ~= 0 then
                    silentStageDelta(enemy, "evasion", -(temp.evasion or 0))
                end
                if (temp.defense or 0) ~= 0 then
                    silentStageDelta(enemy, "defense", -(temp.defense or 0))
                end
            end
            local hadCover = temp.cover
            state.enemyTemp = { evasion = 0, defense = 0, cover = false }
            if not opt("callout_buffs") or not hadCover or not enemy
                or enemyStatusLocked(battle) then
                publishChipState(battle)
                return nil
            end
            local line = pickFoeTrainerLine(
                battle,
                S.TRAINER_FOE_LEAVE_COVER_CALLS,
                S.FOE_LEAVE_COVER_CALLS,
                monName or enemyMonName(battle))
            enqueueNpcFlavor(battle, line, S.CALLOUT_AUTO_DELAY)
            publishChipState(battle)
            return true
        end

        -- Follow-up line after a "NAME\nused MOVE!" announce (before the anim).
        -- Returns reactionText, buffList, trackTempBuffs, fieldCue.
        local function reactionAfterMoveAnnounce(battle, originalText)
            local mon, moveName = parseUsedMoveText(originalText)
            if not mon or not moveName then
                return nil
            end
            local bare, isEnemy = stripEnemyPrefix(mon)
            local moveDef = findMoveByName(battle, moveName)
            if moveDef and ((moveDef.power or 0) <= 0 or moveDef.category == "status") then
                return nil
            end

            local me = playerMonName(battle)
            local state = momentumState(battle)
            local foeAttackCue = { side = "enemy", kind = "attack" }

            if isEnemy then
                if not opt("momentum_counter") then
                    return nil
                end
                if not moveDef then
                    return nil
                end
                -- Foe leaves cover as they commit to the attack.
                resolveCoverOnEnemyAttack(battle, bare)
                state.enemyActedThisTurn = true
                -- Armed foe counter: 50% they take it (auto), else HOLD.
                local enemyCounterLine = nil
                if trainerFoeReactionsOn(battle)
                    and state.enemyMode == "counter" and not state.enemyBoosted then
                    if rollEnemyCounter() then
                        enemyCounterLine = pickFoeTrainerLine(
                            battle, S.TRAINER_FOE_COUNTER_CALLS, S.FOE_COUNTER_CALLS, bare)
                        -- Leave enemyMode armed so battle.damage still boosts.
                    else
                        state.enemyMode = nil
                        state.enemyBoosted = false
                    end
                end
                -- Interactive pick defers player Focus reacts to EffectRegistry.runDamaging.
                if shouldOfferCalloutPick(battle, moveDef) then
                    if enemyCounterLine then
                        return enemyCounterLine, nil, false, foeAttackCue
                    end
                    return nil
                end
                -- Focus Reactive Defense owns player reactions — no legacy EVADE/DEF auto path.
                if ReactiveDefense then
                    local side = ReactiveDefense.sideState(battle, true)
                    if side and side.entrenched and (side.entrenchTurns or 0) > 0 then
                        if enemyCounterLine then
                            return enemyCounterLine, nil, false, foeAttackCue
                        end
                        return nil
                    end
                    if enemyCounterLine then
                        return enemyCounterLine, nil, false, foeAttackCue
                    end
                    return nil
                end
                -- Frozen / asleep: take the hit — no dodge/brace under fire.
                if playerStatusLocked(battle) then
                    if state.temp then
                        state.temp.dodgedOk = false
                    end
                    if enemyCounterLine then
                        return enemyCounterLine, nil, false, foeAttackCue
                    end
                    return nil
                end
                -- Deep cover this turn: take the hit silent (no dodge/brace callout).
                if playerInDeepCover(battle) then
                    if enemyCounterLine then
                        return enemyCounterLine, nil, false, foeAttackCue
                    end
                    return nil
                end
                -- Still in a hide/fly spot from STAY — keep it, no new dodge/brace line.
                if playerHoldingHide(battle) then
                    if enemyCounterLine then
                        return enemyCounterLine, nil, false, foeAttackCue
                    end
                    return nil
                end
                -- Entrenched: hold the trench; no new dodge/brace callouts.
                if state.temp and state.temp.entrenched then
                    if enemyCounterLine then
                        return enemyCounterLine, nil, false, foeAttackCue
                    end
                    return nil
                end
                if foeMoveIsSpecial(moveDef) then
                    if not rollPlayerReactSuccess(battle, "dodge") then
                        state.temp.dodgedOk = false
                        if enemyCounterLine then
                            enqueueNpcFlavor(battle, enemyCounterLine, S.CALLOUT_AUTO_DELAY,
                                foeAttackCue)
                        end
                        return reactFailLine(battle, "dodge"), nil, false,
                            { side = "player", kind = "hit" }
                    end
                    local line, tierBoost = pickCallEntry("dodge", battle, me, moveName)
                    line = line or (me .. "!\nDodge it!")
                    tierBoost = tierBoost or 1
                    state.temp.cover = true
                    state.temp.dodgedOk = true
                    state.temp.hidAway = (tierBoost or 1) >= 2
                    if state.temp.hidAway then
                        rememberCoverSpot(battle, nil)
                    end
                    -- Same random EVADE roll as the menu path (tier from the flavor pick).
                    local evadeBoost = rollPlayerDodgeEvasion(state.temp.hidAway)
                    if enemyCounterLine then
                        line = enemyCounterLine .. "\v" .. line
                    end
                    if evadeBoost >= 3 then
                        local high = pickFormatted(S.DODGE_EVADE_HIGH_CALLS, me)
                            or "Sharp instincts!"
                        line = line .. "\v" .. high
                    end
                    local dodgeKind = state.temp.hidAway and "cover" or "dodge"
                    return line, {
                        { who = "player", stat = "evasion", delta = evadeBoost },
                    }, true, { side = "player", kind = dodgeKind }
                end
                if not rollPlayerReactSuccess(battle, "brace") then
                    state.temp.dodgedOk = false
                    if enemyCounterLine then
                        enqueueNpcFlavor(battle, enemyCounterLine, S.CALLOUT_AUTO_DELAY,
                            foeAttackCue)
                    end
                    return reactFailLine(battle, "brace"), nil, false,
                        { side = "player", kind = "hit" }
                end
                state.temp.dodgedOk = false
                local line, boost = pickCallEntry("brace", battle, me, moveName)
                line = line or (me .. "!\nGet ready!")
                boost = boost or 1
                if boost >= 2 then
                    local cur = (battle.player and battle.player.stages
                        and battle.player.stages.defense) or 0
                    boost = math.max(1, 6 - cur)
                    state.temp.entrenched = true
                    state.temp.entrenchTurns = 0
                end
                if enemyCounterLine then
                    line = enemyCounterLine .. "\v" .. line
                end
                return line, {
                    { who = "player", stat = "defense", delta = boost },
                }, true, { side = "player", kind = "brace" }
            end

            -- Counter announce is handled in rewriteMoveCallText (single page).
            if playerHasCounter(battle) then
                return nil
            end
            if opt("anime_move_calls") and enemyLooksWeak(battle) then
                return pickFormatted(S.PLAYER_FINISH_CALLS, bare, moveName)
                    or ("Finish it!\n" .. bare .. "!"), nil, false,
                    { side = "player", kind = "attack" }
            end
            return nil
        end

        local Font = require("src.render.Font")
        local HudTiles = require("src.render.HudTiles")
        local BattleState = require("src.battle.BattleState")
        local WideBattle = require("src.battle.WideBattle")
        local PartyMenu = require("src.ui.PartyMenu")
        local SummaryMenu = require("src.ui.SummaryMenu")
        -- Publish send-banter flush/enqueue after BattleState exists (hot-reload safe).
        BattleState._arSendBanterApi = sendBanterApi

        -- Install/HUD helpers on one table (LuaJIT 200-local budget).
        local hud = {
            hidingHud = false,
            patched = setmetatable({}, { __mode = "k" }),
            suppressingBattleHpText = false,
        }
        hud.fieldCompactActive = function(battle)
            if not FieldBattleViewer or not battle then
                return false
            end
            if type(FieldBattleViewer.compactUIActive) == "function"
                and FieldBattleViewer.compactUIActive(battle) then
                return true
            end
            return type(FieldBattleViewer.shouldUse) == "function"
                and FieldBattleViewer.shouldUse(mod, battle)
        end
        hud.fieldBattleInGame = function(game)
            local states = game and game.stack and game.stack.states
            if type(states) ~= "table" then
                return nil
            end
            for i = #states, 1, -1 do
                local state = states[i]
                if hud.fieldCompactActive(state) then
                    return state
                end
            end
            return nil
        end
        -- SPEECH BUBBLE mode: all battle dialogue rides in bubbles; classic box hidden.
        hud.bubbleSideActive = function(battle)
            if not opt("speech_bubbles") or type(battle) ~= "table" then
                return nil
            end
            if battle.phase ~= "messages" then
                battle._arLastBubble = nil
                battle._arLastBubbleText = nil
                battle._arLastBubbleThreat = nil
                return nil
            end
            local cur = battle.current
            if cur and cur.text and cur.text ~= "" then
                local side = cur.bubble
                if not side then
                    side = inferBubbleSide(battle, cur.text) or "narrator"
                    cur.bubble = side
                end
                battle._arLastBubble = side
                battle._arLastBubbleText = cur.text
                -- Incoming foe move announce → reddish toast (QoL threat cue).
                local cue = cur.arFieldCue
                local threat = cur.arThreatToast == true
                if not threat and cue and cue.side == "enemy" and cue.kind == "attack" then
                    threat = true
                end
                if not threat then
                    local mon, move = parseUsedMoveText(cur.text)
                    if mon and move then
                        local _, isEnemy = stripEnemyPrefix(mon)
                        threat = isEnemy and true or false
                    end
                end
                battle._arLastBubbleThreat = threat and true or nil
                return side
            end
            -- Keep the last bubble up through move anim / CONT waits (pokered keeps
            -- the announce text visible while the anim plays).
            if battle._arLastBubbleText and (battle.animPlaying or battle.msgHold
                    or battle.msgWaiting or battle.msgPrompt
                    or (battle.shown and #battle.shown > 0)) then
                return battle._arLastBubble
            end
            battle._arLastBubble = nil
            battle._arLastBubbleText = nil
            battle._arLastBubbleThreat = nil
            return nil
        end

        hud.wrapBubbleText = function(text, maxPx)
            local lines = {}
            local raw = tostring(text or ""):gsub("\v", "\n")
            local function flushWord(word)
                while word ~= "" do
                    if Font.width(word) <= maxPx then
                        return word
                    end
                    local cut = 1
                    while cut < #word and Font.width(word:sub(1, cut + 1)) <= maxPx do
                        cut = cut + 1
                    end
                    if cut < 1 then
                        cut = 1
                    end
                    lines[#lines + 1] = word:sub(1, cut)
                    word = word:sub(cut + 1)
                end
                return ""
            end
            for chunk in (raw .. "\n"):gmatch("(.-)\n") do
                chunk = chunk:match("^%s*(.-)%s*$") or chunk
                if chunk ~= "" then
                    local line = ""
                    for word in chunk:gmatch("%S+") do
                        local trial = (line == "") and word or (line .. " " .. word)
                        if Font.width(trial) <= maxPx then
                            line = trial
                        else
                            if line ~= "" then
                                lines[#lines + 1] = line
                            end
                            line = flushWord(word)
                        end
                    end
                    if line ~= "" then
                        lines[#lines + 1] = line
                    end
                end
            end
            return lines
        end

        hud.fieldPopupText = function(text)
            local s = tostring(text or ""):gsub("\v", "\n")
                :match("^%s*(.-)%s*$") or ""
            -- Keep short status callouts, but leave ordinary dialogue readable.
            local flat = s:gsub("\n", " "):gsub("%s+", " ")
            local upper = flat:upper()
            local stat = upper:match("^.-'S%s+(.+)%s+GREATLY FELL!?$")
                or upper:match("^.-'S%s+(.+)%s+FELL!?$")
            if stat then return stat .. " DOWN!" end
            stat = upper:match("^.-'S%s+(.+)%s+ROSE SHARPLY!?$")
                or upper:match("^.-'S%s+(.+)%s+GREATLY ROSE!?$")
                or upper:match("^.-'S%s+(.+)%s+ROSE!?$")
            if stat then return stat .. " UP!" end
            local move = upper:match("^.- USED%s+(.+)!$")
            if move then return move .. "!" end
            if upper:find("SUPER EFFECTIVE", 1, true) then return "SUPER EFFECTIVE!" end
            if upper:find("NOT VERY EFFECTIVE", 1, true) then return "NOT VERY EFFECTIVE!" end
            if upper:find("CRITICAL HIT", 1, true) then return "CRITICAL HIT!" end
            if upper:find("BUT IT MISSED", 1, true)
                or upper:find("ATTACK MISSED", 1, true) then
                return "MISSED THE TARGET!"
            end
            if upper:find("NO EFFECT", 1, true) then return "NO EFFECT!" end
            if upper:find("REGAINED HEALTH", 1, true) then return "HEALED!" end
            return s
        end

        hud.bubbleVisibleText = function(battle)
            local cur = battle and battle.current
            local text
            if cur and cur.text and cur.text ~= "" then
                text = cur.text
            else
                text = (battle and battle._arLastBubbleText) or ""
            end
            if hud.fieldCompactActive(battle) then
                return hud.fieldPopupText(text)
            end
            return text
        end

        hud.drawSpeechBubble = function(battle, side)
            if not side or not love or not love.graphics then
                return
            end
            local text = hud.bubbleVisibleText(battle)
            if text == "" then
                return
            end
            -- FIELD: trainer speech belongs on the tinted foe strip, not here.
            if hud.fieldCompactActive(battle) then
                local Callouts = FieldBattleViewer and FieldBattleViewer.Callouts
                local session = liveFieldSession(battle)
                local raw = (battle.current and battle.current.text)
                    or battle._arLastBubbleText or text
                if Callouts and type(Callouts.isTrainerSpeech) == "function"
                    and Callouts.isTrainerSpeech(raw) then
                    -- Already shown (or about to show) on the attack/react beat.
                    return
                end
                if session and type(Callouts) == "table"
                    and type(Callouts.ownsText) == "function"
                    and (Callouts.ownsText(session, raw)
                        or Callouts.ownsText(session, text)) then
                    return
                end
                if side == "foe" then
                    side = "narrator"
                end
            end
            local g = love.graphics
            local narrator = (side == "narrator")
            local fieldToast = hud.fieldCompactActive(battle)
            -- FIELD keeps a wide, readable bottom bubble (not a tiny tip).
            local maxInner = fieldToast and 144 or (narrator and 128 or 112)
            local padX, padY = fieldToast and 6 or 4, fieldToast and 4 or 3
            local lineH = 8
            local lines = hud.wrapBubbleText(text, maxInner)
            if #lines == 0 then
                lines[1] = ""
            end
            local maxLines = fieldToast and 4 or (narrator and 4 or 5)
            if #lines > maxLines then
                local trimmed = {}
                for i = 1, maxLines - 1 do
                    trimmed[i] = lines[i]
                end
                trimmed[maxLines] = "..."
                lines = trimmed
            end
            local contentW = 0
            for i = 1, #lines do
                contentW = math.max(contentW, Font.width(lines[i]))
            end
            contentW = math.max(fieldToast and 120 or 32, math.min(maxInner, contentW))
            local bw = contentW + padX * 2
            local bh = padY * 2 + #lines * lineH
            local floorY = 142
            local x, y
            local anchorX, anchorY
            -- FIELD: pin to the bottom so multi-line toasts stay readable.
            if fieldToast then
                x = math.floor((160 - bw) / 2)
                y = floorY - bh
                if y < 1 then y = 1 end
                battle._arNarratorTop = y
            elseif hud.fieldCompactActive(battle) and not narrator then
                local wanted = (side == "foe") and "enemy" or "player"
                local ow = battle.game and battle.game.overworld
                for i = 1, #(ow and ow.entities or {}) do
                    local ent = ow.entities[i]
                    if ent and ent._arFieldBattler and ent._arFieldSide == wanted
                        and ent._fieldScreenX and ent._fieldScreenY then
                        anchorX, anchorY = ent._fieldScreenX, ent._fieldScreenY
                        break
                    end
                end
            end
            if fieldToast then
                -- already placed
            elseif anchorX then
                x = math.floor(anchorX - bw / 2)
                y = math.floor(anchorY - bh - 9)
                x = math.max(1, math.min(159 - bw, x))
            elseif narrator then
                x = math.floor((160 - bw) / 2)
                y = floorY - bh
            elseif side == "foe" then
                x = 160 - bw - 1
                y = floorY - bh
            else
                x = 1
                y = floorY - bh
            end
            if y < 1 then
                y = 1
            end

            local totalGlyphs = 0
            local encoded = {}
            for i = 1, #lines do
                encoded[i] = Font.encode(lines[i])
                totalGlyphs = totalGlyphs + #encoded[i]
            end
            local shownBudget = totalGlyphs
            if battle.total and battle.total > 0 and battle.charIndex then
                shownBudget = math.floor(totalGlyphs * (battle.charIndex / battle.total) + 0.5)
            end

            -- Classic text-box look: white fill, double black border.
            -- FIELD: the tinted foe strip owns threat red. This slab stays white
            -- so "Enemy used X!" / switch prompts are not a second red order.
            local threat = not fieldToast and (
                battle._arLastBubbleThreat == true
                or (battle.current and battle.current.arThreatToast == true)
            )
            local fillR, fillG, fillB = 1, 1, 1
            if threat then
                fillR, fillG, fillB = 1.00, 0.78, 0.74
            end
            g.push("all")
            g.setColor(fillR, fillG, fillB, 1)
            g.rectangle("fill", x, y, bw, bh)
            g.setColor(0, 0, 0, 1)
            g.rectangle("line", x + 0.5, y + 0.5, bw - 1, bh - 1)
            g.rectangle("line", x + 1.5, y + 1.5, bw - 3, bh - 3)
            if anchorX then
                local tailX = math.max(x + 5, math.min(x + bw - 5, anchorX))
                g.setColor(fillR, fillG, fillB, 1)
                g.polygon("fill", tailX - 4, y + bh - 1,
                    tailX + 4, y + bh - 1, anchorX, math.min(anchorY - 2, y + bh + 6))
                g.setColor(0, 0, 0, 1)
                g.line(tailX - 4, y + bh - 1,
                    anchorX, math.min(anchorY - 2, y + bh + 6))
                g.line(anchorX, math.min(anchorY - 2, y + bh + 6),
                    tailX + 4, y + bh - 1)
            elseif not narrator then
                if side == "foe" then
                    g.setColor(fillR, fillG, fillB, 1)
                    g.polygon("fill", x + bw - 12, y + 1, x + bw - 4, y - 5, x + bw - 20, y + 1)
                    g.setColor(0, 0, 0, 1)
                    g.line(x + bw - 12, y + 1, x + bw - 4, y - 5)
                    g.line(x + bw - 4, y - 5, x + bw - 20, y + 1)
                else
                    g.setColor(fillR, fillG, fillB, 1)
                    g.polygon("fill", x + 12, y + 1, x + 4, y - 5, x + 20, y + 1)
                    g.setColor(0, 0, 0, 1)
                    g.line(x + 12, y + 1, x + 4, y - 5)
                    g.line(x + 4, y - 5, x + 20, y + 1)
                end
            end

            local textX = x + padX
            g.setColor(0, 0, 0, 1)
            local left = shownBudget
            local ty = y + padY
            for i = 1, #lines do
                local codes = encoded[i]
                local tx = textX
                for j = 1, #codes do
                    if left <= 0 then
                        break
                    end
                    Font.drawCode(codes[j], tx, ty)
                    tx = tx + (Font.advanceOf(codes[j]) or 8)
                    left = left - 1
                end
                ty = ty + lineH
                if left <= 0 then
                    break
                end
            end
            if (battle.msgWaiting or battle.msgPrompt) and (battle.frame or 0) % 60 < 30
                and (not hud.fieldCompactActive(battle) or battle._arFieldToastPaused) then
                Font.drawCode(0xED, x + bw - 10, y + bh - 9)
            end
            if hud.fieldCompactActive(battle) and battle._arFieldToastPaused
                and Font and type(Font.draw) == "function" then
                g.setColor(0, 0, 0, 1)
                Font.draw("II", x + 2, y + 1)
            end
            g.setColor(1, 1, 1, 1)
            g.pop()
        end

        -- True while chat bubbles own battle dialogue (hide classic / Gen3 text box).
        hud.bubblesOwnDialogue = function(battle)
            if not opt("speech_bubbles") or type(battle) ~= "table" then
                return false
            end
            if battle.phase ~= "messages" then
                return false
            end
            if hud.bubbleSideActive(battle) then
                return true
            end
            return battle.current ~= nil
                or battle.animPlaying
                or battle.msgHold
                or battle.msgWaiting
                or battle.msgPrompt
                or (battle.shown and #battle.shown > 0)
        end

        -- Keep drawTextArea lifecycle (scroll / typewriter) but paint nothing.
        hud.runDrawInvisible = function(fn, self, ...)
            if not (love and love.graphics and type(fn) == "function") then
                if type(fn) == "function" then
                    return fn(self, ...)
                end
                return
            end
            local g = love.graphics
            g.push("all")
            g.setScissor(0, 0, 0, 0)
            local ok, a, b, c = pcall(fn, self, ...)
            g.pop()
            if not ok then
                error(a, 0)
            end
            return a, b, c
        end

        mod.hooks:wrap("battle.bottom_ui_visible", function(next, who)
            if hud.fieldCompactActive(who) then
                -- Keep the classic dialogue slab hidden on FIELD, but allow
                -- stacked learn-move / YES-NO TextBoxes to paint (UIVisibility
                -- asks the enclosing battle before drawing those overlays).
                local Compat = FieldBattleViewer and FieldBattleViewer.Compat
                if Compat and type(Compat.fieldAllowsStackedBottomUI) == "function"
                    and Compat.fieldAllowsStackedBottomUI(who) then
                    return true
                end
                return false
            end
            -- Hide the classic text box for all battle dialogue; bubbles carry it.
            -- Keep the box for FIGHT / move menus (non-messages phases).
            if hud.bubblesOwnDialogue(who) then
                return false
            end
            return next(who)
        end)

        -- Short mon name so chips stay readable on 160×144.
        hud.chipMonName = function(name)
            name = tostring(name or "POKéMON")
            if #name <= 9 then
                return name
            end
            return name:sub(1, 8) .. "+"
        end

        hud.chipSpotPhrase = function(spot)
            spot = tostring(spot or ""):upper()
            if spot == "" then
                return S.CHIP_FALLBACK_SPOT or "in cover"
            end
            local map = S.CHIP_SPOT_PHRASE or {}
            return map[spot] or (S.CHIP_FALLBACK_SPOT or "in cover")
        end

        hud.chipLinesKey = function(lines)
            if type(lines) ~= "table" then
                return ""
            end
            return tostring(lines[1] or "") .. "\n" .. tostring(lines[2] or "")
        end

        -- Build narrative chip lines from live momentum (no numbers, no menu prompts).
        hud.buildChipNarrative = function(battle, foeSide)
            local state = battle and momentumByBattle[battle]
            if not state then
                return nil
            end
            local name = hud.chipMonName(
                foeSide and enemyMonName(battle) or playerMonName(battle))
            local temp = foeSide and (state.enemyTemp or {}) or (state.temp or {})
            local counterArmed = (foeSide
                    and state.enemyMode == "counter" and not state.enemyBoosted)
                or ((not foeSide) and state.mode == "counter" and not state.boosted)

            -- Frozen / asleep: chips reflect helplessness (player side only for FRZ/SLP).
            if not foeSide then
                local mon = battle.player and battle.player.mon
                local st = mon and mon.status
                if st == "FRZ" then
                    return { name .. " is", "frozen solid!" }
                end
                if st == "SLP" then
                    return { name .. " is", "fast asleep!" }
                end
            end

            if counterArmed then
                return { name .. " is", "ready to counter!" }
            end

            -- Focus Reactive Defense chips (player for now).
            if ReactiveDefense and not foeSide then
                local side = ReactiveDefense.sideState(battle, true)
                if side then
                    if side.entrenched then
                        local t = side.entrenchTurns or 0
                        if t > 0 then
                            return { name .. " is", "entrenched (" .. t .. ")!" }
                        end
                        return { name .. " is", "holding the trench!" }
                    end
                    if side.cover then
                        return { name .. " is", "in cover!" }
                    end
                    local focus = math.floor(side.focus or 0)
                    local cap = ReactiveDefense.focusCap(battle.player)
                    if focus <= 20 then
                        return { name .. " is", "low on Focus!" }
                    end
                    if focus >= (cap or 100) - 5 then
                        return { name .. " is", "fully focused!" }
                    end
                end
            end

            if not foeSide and temp.deepCover then
                local spot = hud.chipSpotPhrase(temp.coverSpot)
                if spot and spot ~= "in cover" and #spot <= 12 then
                    return { name .. " is", "stuck " .. spot }
                end
                return { name .. " is", "stuck deep!" }
            end

            if not foeSide and temp.entrenched then
                return { name .. " is", "holding the trench!" }
            end

            if temp.hidAway then
                return { name .. " is", "hiding " .. hud.chipSpotPhrase(temp.coverSpot) }
            end

            if (temp.evasion or 0) >= 3 then
                return { name .. " is", "hard to pin down!" }
            end
            if (temp.evasion or 0) > 0 or temp.cover then
                return { name .. " is", "on guard!" }
            end
            if (temp.defense or 0) > 0 then
                return { name .. " is", "bracing hard!" }
            end
            return nil
        end

        -- Commit chip text after callouts/state settle (never from awaitingPick).
        publishChipState = function(battle)
            if not battle or not opt("momentum_chips") or not opt("momentum_counter") then
                return
            end
            local state = momentumState(battle)
            local you = hud.buildChipNarrative(battle, false)
            local foe = hud.buildChipNarrative(battle, true)
            if hud.chipLinesKey(you) ~= hud.chipLinesKey(state.chipYou) then
                state.chipPulseYou = 18
            end
            if hud.chipLinesKey(foe) ~= hud.chipLinesKey(state.chipFoe) then
                state.chipPulseFoe = 18
            end
            state.chipYou = you
            state.chipFoe = foe
        end

        hud.drawMomentumChip = function(battle, foeSide)
            if not opt("momentum_chips") or not opt("momentum_counter") then
                return
            end
            if not (love and love.graphics) then
                return
            end
            -- Skip while a big speech bubble owns that corner.
            local bubble = hud.bubbleSideActive(battle)
            if bubble == (foeSide and "foe" or "player") then
                return
            end
            local state = battle and momentumByBattle[battle]
            -- Don't use `foe and chipFoe or chipYou` — nil chipFoe would fall through
            -- to the player chip and draw a second SEADRA in foe colors.
            local raw = state and (foeSide and state.chipFoe or (not foeSide and state.chipYou))
            if not raw then
                return
            end
            local g = love.graphics
            local lineH = 8
            local padX, padY = 2, 1
            local maxBox = 72
            local maxPx = maxBox - padX * 2 - 2
            local function fitChipLine(s)
                s = tostring(s or "")
                if s == "" or Font.width(s) <= maxPx then
                    return s
                end
                local cut = #s
                while cut > 1 and Font.width(s:sub(1, cut) .. "+") > maxPx do
                    cut = cut - 1
                end
                return s:sub(1, cut) .. "+"
            end
            local lines = {}
            if #raw >= 2 then
                lines[1] = fitChipLine(raw[1])
                lines[2] = fitChipLine(raw[2])
            else
                local wrapped = hud.wrapBubbleText(raw[1], maxPx)
                for j = 1, math.min(2, #wrapped) do
                    lines[j] = wrapped[j]
                end
            end
            if #lines == 0 then
                return
            end
            local widest = 0
            for i = 1, #lines do
                widest = math.max(widest, Font.width(lines[i]))
            end
            local bw = math.min(maxBox, widest + padX * 2 + 2)
            local bh = padY * 2 + #lines * lineH
            local x = foeSide and (160 - bw - 1) or 1
            local y = 1
            -- Leave room for the slim Focus bar under the top-left corner.
            if not foeSide and opt("focus_chip") and ReactiveDefense then
                y = 1 + 9
            end
            local pulse = foeSide and (state.chipPulseFoe or 0) or (state.chipPulseYou or 0)
            if pulse > 0 then
                if foeSide then
                    state.chipPulseFoe = pulse - 1
                else
                    state.chipPulseYou = pulse - 1
                end
            end
            -- Classic R/B/Y: white box, black border, no tinted accents.
            g.push("all")
            g.setColor(1, 1, 1, 1)
            g.rectangle("fill", x, y, bw, bh)
            g.setColor(0, 0, 0, 1)
            g.rectangle("line", x + 0.5, y + 0.5, bw - 1, bh - 1)
            g.rectangle("line", x + 1.5, y + 1.5, bw - 3, bh - 3)
            local textX = x + padX + 1
            local ty = y + padY
            for i = 1, #lines do
                Font.draw(lines[i], textX, ty)
                ty = ty + lineH
            end
            g.setColor(1, 1, 1, 1)
            g.pop()
        end

        -- Slim Focus meter — top-left, optional.
        -- Stored on `dev` to stay under LuaJIT's 200-local limit.
        dev.drawFocusChip = function(battle)
            if not opt("focus_chip") or not opt("momentum_counter") then
                return
            end
            if not ReactiveDefense or not battle then
                return
            end
            if not (love and love.graphics) then
                return
            end
            -- Player speech bubble owns the top-left corner.
            if hud.bubbleSideActive(battle) == "player" then
                return
            end
            local side = ReactiveDefense.sideState(battle, true)
            if not side then
                return
            end
            local cap = math.max(1, ReactiveDefense.focusCap(battle.player) or 100)
            local focus = math.max(0, math.min(cap, math.floor(side.focus or 0)))
            local state = momentumState(battle)
            if state.focusChipLast ~= focus then
                state.focusChipLast = focus
                state.focusChipPulse = 18
            end
            local pulse = state.focusChipPulse or 0
            if pulse > 0 then
                state.focusChipPulse = pulse - 1
            end

            local g = love.graphics
            -- Tiny R/B/Y strip: "F" + black fill on white track.
            local barW, barH = 28, 3
            local bw, bh = 7 + barW + 3, 8
            local x, y = 1, 1
            local fill = 0
            if focus <= 20 then
                fill = 0.35 -- lighter when low so the empty track reads clearly
            end

            g.push("all")
            g.setColor(1, 1, 1, 1)
            g.rectangle("fill", x, y, bw, bh)
            g.setColor(0, 0, 0, 1)
            g.rectangle("line", x + 0.5, y + 0.5, bw - 1, bh - 1)
            Font.draw("F", x + 1, y)
            local barX, barY = x + 8, y + 2
            g.setColor(0.85, 0.85, 0.85, 1)
            g.rectangle("fill", barX, barY, barW, barH)
            local filled = math.floor(barW * (focus / cap) + 0.5)
            if filled > 0 then
                g.setColor(fill, fill, fill, 1)
                g.rectangle("fill", barX, barY, filled, barH)
            end
            g.setColor(0, 0, 0, 1)
            g.rectangle("line", barX + 0.5, barY + 0.5, barW - 1, barH - 1)
            g.setColor(1, 1, 1, 1)
            g.pop()
        end

        mod.hooks:wrap("battle.overlay", function(next, battle)
            next(battle)
            if hud.fieldCompactActive(battle) then
                local side = hud.bubbleSideActive(battle)
                battle._arFieldBubbleDialogue = side and true or nil
                battle._arNarratorTop = nil
                if FieldBattleViewer and type(FieldBattleViewer.drawUI) == "function" then
                    FieldBattleViewer.drawUI(battle)
                end
                battle._arFieldBubbleDialogue = nil
                if side then
                    hud.drawSpeechBubble(battle, side)
                end
                if FieldBattleViewer and type(FieldBattleViewer.drawCallouts) == "function" then
                    FieldBattleViewer.drawCallouts(battle)
                end
                return
            end
            BanterCameo.draw(battle)
            -- FIELD: no HUD cover cubes (field_battle uses map props / grid cover).
            if type(dev.drawCoverProp) == "function"
                and not (FieldBattleViewer and FieldBattleViewer.enabled
                    and FieldBattleViewer.enabled(mod)) then
                dev.drawCoverProp(battle)
            end
            hud.drawMomentumChip(battle, false)
            hud.drawMomentumChip(battle, true)
            if type(dev.drawFocusChip) == "function" then
                dev.drawFocusChip(battle)
            end
            local side = hud.bubbleSideActive(battle)
            if side then
                hud.drawSpeechBubble(battle, side)
            end
        end)

        -- Slow speech-bubble typing a bit past the engine's "Slow" text speed.
        -- Guard: hot reload must not stack flushPendingSendBanter wrappers.
        do
            if not BattleState._arAnimeUQ then
                BattleState._arAnimeUQ = true
                local origUpdateQueue = BattleState.updateQueue
                if type(origUpdateQueue) == "function" then
                    function BattleState.updateQueue(self)
                        local api = BattleState._arSendBanterApi
                        if api and type(api.flush) == "function" then
                            api.flush(self)
                        end
                        local curItem = self and self.current
                        local shownLine = self and self.shown and self.shown[#self.shown]
                        -- FIELD toasts auto-cycle (~1.5s). B pauses; A or B resumes.
                        if fieldFlowsText(self) then
                            self._arBubbleAcc = 0
                            if self.phase ~= "messages" then
                                self._arFieldToastPaused = nil
                            else
                                local input = self.game and self.game.input
                                if input and type(input.wasPressed) == "function" then
                                    if input:wasPressed("b") then
                                        self._arFieldToastPaused = not self._arFieldToastPaused
                                    elseif self._arFieldToastPaused and input:wasPressed("a") then
                                        self._arFieldToastPaused = false
                                    end
                                end
                                if curItem and curItem._arOverlapShown then
                                    -- Already played as an overlay during the attack.
                                    curItem.auto = true
                                    curItem.autoDelay = 0
                                elseif self._arFieldToastPaused and curItem then
                                    curItem.auto = nil
                                    curItem.autoDelay = nil
                                elseif curItem and curItem.text and curItem.auto ~= false then
                                    applyFieldToastAuto(curItem)
                                end
                            end
                            return origUpdateQueue(self)
                        end
                        local bubbleTyping = opt("speech_bubbles") and curItem and curItem.bubble
                            and self.phase == "messages"
                            and shownLine and self.codes
                            and #shownLine < #self.codes
                        if not bubbleTyping then
                            self._arBubbleAcc = 0
                            return origUpdateQueue(self)
                        end

                        local opts = self.game and self.game.save and self.game.save.options
                        local prevSpeed = opts and opts.textSpeed
                        if opts then
                            opts.textSpeed = 5
                        end

                        self._arBubbleAcc = (self._arBubbleAcc or 0) + 1
                        local beforeLen = #shownLine
                        local beforeIndex = self.charIndex or 0
                        if self._arBubbleAcc < S.BUBBLE_CHAR_DELAY then
                            -- Hold: run queue logic but don't emit a glyph this frame.
                            self.charTimer = 0
                            local result = origUpdateQueue(self)
                            if opts then
                                opts.textSpeed = prevSpeed
                            end
                            return result
                        end

                        -- Emit at most one glyph every S.BUBBLE_CHAR_DELAY frames.
                        self._arBubbleAcc = 0
                        self.charTimer = 4
                        local result = origUpdateQueue(self)
                        while #shownLine > beforeLen + 1 do
                            table.remove(shownLine)
                            self.charIndex = math.max(0, (self.charIndex or 0) - 1)
                        end
                        if #shownLine == beforeLen and (self.charIndex or 0) > beforeIndex then
                            self.charIndex = beforeIndex
                        end
                        if opts then
                            opts.textSpeed = prevSpeed
                        end
                        return result
                    end
                end
            end
        end

        -- FIGHT while hidden / entrenched: STAY, or STRIKE when an opening allows.
        do
            local function goMoveSelect(battle)
                battle.phase = "moveSelect"
                local moves = battle.player and battle.player.curMoves
                local n = moves and #moves or 1
                battle.moveIndex = math.min(battle.moveIndex or 1, n)
                battle.moveSwapIndex = nil
                -- FIELD latch: after STRIKE/EMERGE/BREAK, keep the diamond open.
                battle._arFieldPreferMoves = true
                battle._arFieldCommandHold = nil
            end

            local function clearPlayerEntrench(battle)
                local state = momentumState(battle)
                local temp = state.temp or {}
                local player = battle.player
                local def = temp.defense or 0
                if player and player.stages and def ~= 0 then
                    silentStageDelta(player, "defense", -def)
                end
                temp.defense = 0
                temp.entrenched = false
                temp.entrenchTurns = 0
                state.temp = temp
                publishChipState(battle)
            end

            local function openStrikeOrStayMenu(battle)
                if not battle or not battle.game or not battle.game.stack then
                    goMoveSelect(battle)
                    return
                end
                -- Random deep-cover turn: can't leave (tree / dive / boulder / …).
                if rollDeepCoverLock(battle) then
                    ensurePlayerPicHidden(battle, false)
                    battle:resolveTurn({ special = "holdPosition" })
                    return
                end
                battle.phase = "menu"
                battle.game.stack:push(newCalloutPickModal(battle.game, {
                    title = "COVER!",
                    subtitle = playerMonName(battle),
                    choices = {
                        { label = "STRIKE", hint = "Come out & attack", line = "" },
                        { label = "STAY",   hint = "Hold cover / hide", line = "" },
                    },
                    cancelable = true,
                    onPick = function(choice)
                        local label = choice and tostring(choice.label) or ""
                        if label == "STAY" then
                            battle:resolveTurn({ special = "holdPosition" })
                        else
                            clearAmbientStance(battle)
                            goMoveSelect(battle)
                        end
                    end,
                    onCancel = function()
                        battle.phase = "menu"
                    end,
                }))
            end

            local function openEntrenchMenu(battle)
                if not battle or not battle.game or not battle.game.stack then
                    battle.phase = "menu"
                    return
                end
                local state = momentumState(battle)
                local turns = (state.temp and state.temp.entrenchTurns) or 0
                local maxed = turns >= (S.ENTRENCH_MAX_TURNS or 3)
                local opening = playerHasCounter(battle)
                local choices
                if maxed then
                    choices = {
                        { label = "BREAK", hint = "Stance worn out", line = "" },
                    }
                elseif opening then
                    choices = {
                        { label = "STRIKE", hint = "Use the opening", line = "" },
                        { label = "STAY",   hint = "Stay entrenched", line = "" },
                    }
                else
                    choices = {
                        { label = "STAY", hint = "Stay entrenched", line = "" },
                    }
                end
                battle.phase = "menu"
                battle.game.stack:push(newCalloutPickModal(battle.game, {
                    title = "ENTRENCH!",
                    subtitle = playerMonName(battle),
                    choices = choices,
                    cancelable = true,
                    onPick = function(choice)
                        local label = choice and tostring(choice.label) or ""
                        if label == "STAY" then
                            battle:resolveTurn({ special = "holdPosition" })
                        elseif label == "BREAK" then
                            clearAmbientStance(battle)
                            clearPlayerEntrench(battle)
                            local me = playerMonName(battle)
                            local line = pickFormatted(S.BREAK_ENTRENCH_CALLS, me)
                                or (me .. "!\nBreak stance!")
                            if type(battle.sayNext) == "function" then
                                battle:sayNext(line)
                            end
                            tagQueueBubble(battle, "player")
                            goMoveSelect(battle)
                            dev.log(battle, "ENTRENCH break", "max turns / stance worn")
                        else
                            -- Leaving the trench to attack: kill idle BARRIER pulses now so
                            -- they can't delay the real move anim.
                            clearAmbientStance(battle)
                            goMoveSelect(battle)
                        end
                    end,
                    onCancel = function()
                        battle.phase = "menu"
                    end,
                }))
            end

            local function openFocusCoverMenu(battle)
                if not battle or not battle.game or not battle.game.stack or not ReactiveDefense then
                    goMoveSelect(battle)
                    return
                end
                local side = ReactiveDefense.sideState(battle, true)
                local emergeCost = (ReactiveDefense.COST and ReactiveDefense.COST.cover_exit) or 10
                local canEmerge = side and (side.focus or 0) >= emergeCost
                local choices = {
                    { label = "STAY", hint = "Hold cover", line = "", dir = "down" },
                }
                if canEmerge then
                    table.insert(choices, 1, {
                        label = "EMERGE",
                        hint = "Leave cover",
                        dir = "up",
                    })
                end
                battle.phase = "menu"
                battle.game.stack:push(newCalloutPickModal(battle.game, {
                    title = "COVER!",
                    subtitle = playerMonName(battle),
                    pad = true,
                    choices = choices,
                    cancelable = true,
                    onPick = function(choice)
                        local label = choice and tostring(choice.label) or ""
                        if label == "STAY" then
                            battle:resolveTurn({ special = "holdPosition" })
                        elseif label == "EMERGE" then
                            if ReactiveDefense.exitCover(battle, true, true) then
                                if type(battle.sayNext) == "function" then
                                    battle:sayNext("Coming out\nof cover!")
                                end
                                tagQueueBubble(battle, "player")
                                if type(dev.clearFocusCoverVisual) == "function" then
                                    dev.clearFocusCoverVisual(battle, true)
                                end
                            end
                            clearAmbientStance(battle)
                            goMoveSelect(battle)
                            publishChipState(battle)
                        else
                            clearAmbientStance(battle)
                            goMoveSelect(battle)
                        end
                    end,
                    onCancel = function()
                        battle.phase = "menu"
                    end,
                }))
            end

            local function openFocusEntrenchMenu(battle)
                if not battle or not battle.game or not battle.game.stack or not ReactiveDefense then
                    battle.phase = "menu"
                    return
                end
                local side = ReactiveDefense.sideState(battle, true)
                local turns = (side and side.entrenchTurns) or 0
                battle.phase = "menu"
                battle.game.stack:push(newCalloutPickModal(battle.game, {
                    title = "ENTRENCH!",
                    subtitle = playerMonName(battle),
                    pad = true,
                    choices = {
                        { label = "HOLD",  hint = "Stay locked", line = "", dir = "down" },
                        { label = "BREAK", hint = "Leave early", line = "", dir = "up" },
                    },
                    cancelable = true,
                    onPick = function(choice)
                        local label = choice and tostring(choice.label) or ""
                        if label == "HOLD" then
                            battle:resolveTurn({ special = "holdPosition" })
                        else
                            local ok, refund = ReactiveDefense.earlyExitEntrench(battle, true)
                            clearAmbientStance(battle)
                            if type(battle.sayNext) == "function" then
                                battle:sayNext("Broke entrench!")
                            end
                            tagQueueBubble(battle, "player")
                            goMoveSelect(battle)
                            publishChipState(battle)
                            dev.log(battle, "FOCUS entrench break", "refund=" .. tostring(refund))
                        end
                    end,
                    onCancel = function()
                        battle.phase = "menu"
                    end,
                }))
            end

            local function playerIsEntrenched(battle)
                if not opt("momentum_counter") or not battle then
                    return false
                end
                if ReactiveDefense then
                    local side = ReactiveDefense.sideState(battle, true)
                    return side and side.entrenched == true and (side.entrenchTurns or 0) > 0
                end
                local state = momentumByBattle[battle]
                return state and state.temp and state.temp.entrenched == true
            end

            local function playerInFocusCover(battle)
                if not ReactiveDefense or not opt("momentum_counter") or not battle then
                    return false
                end
                local side = ReactiveDefense.sideState(battle, true)
                return side and side.cover == true
            end

            local origUpdate = BattleState.update
            if type(origUpdate) == "function" then
                function BattleState.update(self, dt)
                    local phaseBefore = self.phase
                    local result = origUpdate(self, dt)
                    if phaseBefore == "menu" and self.phase == "moveSelect" then
                        -- Sleep / freeze: skip COVER!/ENTRENCH! (can't follow orders).
                        -- Paralysis still gets those menus — react rolls are just stiffer.
                        if not playerStatusLocked(self) then
                            if playerIsEntrenched(self) then
                                if ReactiveDefense then
                                    openFocusEntrenchMenu(self)
                                else
                                    openEntrenchMenu(self)
                                end
                            elseif playerInFocusCover(self) then
                                openFocusCoverMenu(self)
                            elseif playerCanStay(self) then
                                openStrikeOrStayMenu(self)
                            end
                        end
                    end
                    -- Brace / hide idle sparkles (HARDEN, GROWTH, DIG…) between commands.
                    tickAmbientStance(self, dt)
                    BanterCameo.tick(self)
                    if type(dev.tickAttackCamera) == "function" then
                        dev.tickAttackCamera(self)
                    end
                    return result
                end
            end

            local origExecuteAction = BattleState.executeAction
            if type(origExecuteAction) == "function" then
                function BattleState.executeAction(self, user, target, action)
                    -- Locked in a trench with no opening: can't swing — convert to STAY.
                    -- Exception: a real move pick is an intentional BREAK + attack
                    -- (FIELD PreferMoves used to skip ENTRENCH! and get eaten here).
                    if user and user.isPlayer and action and action.special ~= "holdPosition" then
                        local state = momentumByBattle[self]
                        local isRealMove = action.id ~= nil or action.struggle == true
                        if state and state.temp and state.temp.deepCover then
                            action = { special = "holdPosition" }
                            dev.log(self, "DEEP cover", "force STAY (can't leave)")
                        elseif ReactiveDefense then
                            local side = ReactiveDefense.sideState(self, true)
                            if side and side.entrenched and (side.entrenchTurns or 0) > 0 then
                                if isRealMove then
                                    clearAmbientStance(self)
                                    ReactiveDefense.earlyExitEntrench(self, true)
                                    publishChipState(self)
                                    dev.log(self, "FOCUS entrench break", "attack leaves trench")
                                else
                                    action = { special = "holdPosition" }
                                    dev.log(self, "FOCUS entrench lock", "force STAY")
                                end
                            end
                        elseif state and state.temp and state.temp.entrenched
                            and not playerHasCounter(self) then
                            local turns = state.temp.entrenchTurns or 0
                            if turns < (S.ENTRENCH_MAX_TURNS or 3) then
                                if isRealMove then
                                    clearAmbientStance(self)
                                    clearPlayerEntrench(self)
                                    dev.log(self, "ENTRENCH break", "attack leaves trench")
                                else
                                    action = { special = "holdPosition" }
                                    dev.log(self, "ENTRENCH lock", "force STAY (no opening)")
                                end
                            end
                        end
                    end
                    if action and action.special == "holdPosition"
                        and user and user.isPlayer then
                        if self.result then
                            return
                        end
                        if not user.mon or user.mon.hp <= 0 then
                            return
                        end
                        local me = playerMonName(self)
                        local state = momentumState(self)
                        local rdSide = ReactiveDefense and ReactiveDefense.sideState(self, true)
                        local entrenched = (rdSide and rdSide.entrenched)
                            or (state.temp and state.temp.entrenched)
                        local deep = state.temp and state.temp.deepCover
                        local focusCover = rdSide and rdSide.cover
                        local line
                        if deep then
                            -- Stuck up a tree / underwater / behind a boulder this turn.
                            ensurePlayerPicHidden(self, not (state.temp and state.temp.picHidden))
                            line = pickDeepCoverLine(self)
                            dev.log(self, "STAY deep",
                                "spot=" .. tostring(state.temp.coverSpot or "?"))
                        elseif rdSide and rdSide.entrenched then
                            -- Focus trench: turn countdown is owned by ReactiveDefense.endTurn.
                            line = pickFormatted(S.STAY_ENTRENCHED_CALLS, me)
                                or ("Stay entrenched,\n" .. me .. "!")
                            rdSide.reactedThisTurn = true
                            dev.log(self, "STAY focus entrench",
                                "left=" .. tostring(rdSide.entrenchTurns or 0))
                        elseif focusCover then
                            line = pickFormatted(S.HOLD_POSITION_CALLS, me)
                                or (me .. "!\nHold cover!")
                            rdSide.reactedThisTurn = true
                            dev.log(self, "STAY focus cover",
                                "dur=" .. tostring(math.floor(rdSide.coverDurability or 0)))
                        elseif entrenched then
                            state.temp.entrenchTurns = (state.temp.entrenchTurns or 0) + 1
                            line = pickFormatted(S.STAY_ENTRENCHED_CALLS, me)
                                or ("Stay entrenched,\n" .. me .. "!")
                            dev.log(self, "STAY entrench",
                                "turn " .. tostring(state.temp.entrenchTurns)
                                .. "/" .. tostring(S.ENTRENCH_MAX_TURNS or 3))
                            if state.temp.entrenchTurns >= (S.ENTRENCH_MAX_TURNS or 3) then
                                -- Stance worn out after this hold — clear at end of the order.
                                clearPlayerEntrench(self)
                                dev.log(self, "ENTRENCH end", "max stays reached")
                            end
                        else
                            -- Hold cover: keep the Dig/Fly-style hide on the field.
                            ensurePlayerPicHidden(self, not (state.temp and state.temp.picHidden))
                            line = pickFormatted(S.HOLD_POSITION_CALLS, me)
                                or (me .. "!\nHold on!")
                            dev.log(self, "STAY", "hold hide/cover spot="
                                .. tostring(state.temp and state.temp.coverSpot or "-"))
                        end
                        -- Frozen / asleep: keep stance silently — no trainer STAY shout.
                        if not playerStatusLocked(self) and line then
                            if type(self.sayNextAuto) == "function" then
                                self:sayNextAuto(line, S.BUBBLE_AUTO_DELAY or S.CALLOUT_AUTO_DELAY)
                            elseif type(self.sayNext) == "function" then
                                self:sayNext(line)
                            end
                            tagQueueBubble(self, "player")
                            -- STAY / hold cover / entrench → tuck toward cover on the map.
                            local stayKind = (deep or focusCover or playerHoldingHide(self))
                                and "cover" or "brace"
                            tagLatestQueueFieldCue(self, "player", stayKind)
                        end
                        publishChipState(self)
                        -- Cover / brace / entrench buffs stay (unless max just cleared).
                        return
                    end
                    -- After a dodge opening going second: use the counter move you picked.
                    if user and user.isPlayer then
                        local state = momentumByBattle[self]
                        if state and state.overridePlayerAction then
                            action = state.overridePlayerAction
                            state.overridePlayerAction = nil
                            dev.log(self, "OVERRIDE move",
                                tostring(action and (action.id or action.name) or "?"))
                        end
                    end
                    return origExecuteAction(self, user, target, action)
                end
            end
        end

        -- BC returns the camera on resolveTurn; our mid-turn swings (COUNTER!,
        -- Again!, deferred hits) skip that. Re-arm attack cam on every performMove.
        do
            local origPerformMove = BattleState.performMove
            if type(origPerformMove) == "function" then
                function BattleState.performMove(self, user, target, moveInst, isCalled)
                    local move = moveInst
                    if type(self.moveDef) == "function" and moveInst then
                        local ok, def = pcall(self.moveDef, self, moveInst)
                        if ok and type(def) == "table" then
                            move = def
                        end
                    end
                    signalAttackPresentation(self, user, target, move or moveInst, {
                        isCalled = isCalled == true,
                    })
                    return origPerformMove(self, user, target, moveInst, isCalled)
                end
            end
        end

        -- Keep Dig/Fly-style dodge hides through the foe's attack anim.
        do
            local origResetPicFx = BattleState.resetPicFx
            if type(origResetPicFx) == "function" then
                function BattleState.resetPicFx(self)
                    origResetPicFx(self)
                    local state = self and momentumByBattle[self]
                    if not (state and state.temp and state.temp.picHidden) then
                        return
                    end
                    local player = self.player
                    if not player then
                        return
                    end
                    local pf = self:picFxFor(player)
                    if pf then
                        pf.hidden = true
                    end
                end
            end
        end

        -- Dodge miss: leave the move anim queued so the attack still plays past cover
        -- (vanilla cancelMoveAnim removes it on accuracy miss).
        do
            local origCancelMoveAnim = BattleState.cancelMoveAnim
            if type(origCancelMoveAnim) == "function" then
                function BattleState.cancelMoveAnim(self)
                    local state = self and momentumByBattle[self]
                    if state and state.keepDodgeMissAnim then
                        return
                    end
                    return origCancelMoveAnim(self)
                end
            end
        end

        -- True only while a battle HUD paint is in progress.
        -- Functions are not tables, so track wraps in a weak set.

        -- Classic white dialogue slab: run for state, paint nothing while bubbles speak.
        do
            local origTextArea = BattleState.drawTextArea
            if type(origTextArea) == "function" and not hud.patched[origTextArea] then
                local function wrappedTextArea(self, ...)
                    if hud.fieldCompactActive(self) or hud.bubblesOwnDialogue(self) then
                        return hud.runDrawInvisible(origTextArea, self, ...)
                    end
                    return origTextArea(self, ...)
                end
                hud.patched[origTextArea] = true
                hud.patched[wrappedTextArea] = true
                BattleState.drawTextArea = wrappedTextArea
            end
        end

        -- Must be after local BattleState / patched (Lua locals aren't visible above).
        hud.willShowCalloutPick = function(battle, originalText)
            local mon, moveName = parseUsedMoveText(originalText)
            if not mon or not moveName then
                return false
            end
            local _, isEnemy = stripEnemyPrefix(mon)
            if not isEnemy then
                return false
            end
            local moveDef = findMoveByName(battle, moveName)
            return shouldOfferCalloutPick(battle, moveDef)
        end

        -- OPENING! COUNTER/HOLD menu removed — openings auto-fire on your attack.
        hud.willShowCounterPick = function(_battle, _originalText)
            return false
        end

        hud.wrapBattleSay = function(methodName)
            -- Durable per-method guard (hud.patched is recreated on hot reload).
            BattleState._arAnimeSayPatched = BattleState._arAnimeSayPatched or {}
            if BattleState._arAnimeSayPatched[methodName] then
                return
            end
            local original = BattleState[methodName]
            if type(original) ~= "function" or hud.patched[original] then
                return
            end
            local wrapped = function(self, text, ...)
                -- Suppress EXP share / EXP.ALL / boosted-EXP pages; keep level-ups.
                if isExpGainDialogue(text) then
                    return
                end
                -- Parse the engine's original announce before anime rewrite.
                local mon, moveName = parseUsedMoveText(text)
                local bare, isEnemy = nil, false
                if mon then
                    bare, isEnemy = stripEnemyPrefix(mon)
                end
                local reaction, buffs, trackTemp, fieldCue = reactionAfterMoveAnnounce(self, text)
                -- Dodge cover miss: keep anim + replace vanilla "attack missed!".
                local dodgeWhiff
                text, dodgeWhiff = rewriteDodgeMissText(self, text)
                local displayText = rewriteBattleText(self, text)
                -- FIELD: NPC move orders ride the attack cue so they open on
                -- the same beat as the FX (issue #10). The box keeps narrative.
                local pendingNpcOrder
                if fieldFlowsText(self) and mon and isEnemy then
                    local narrative = rewriteLevelUpText(text)
                    if displayText ~= narrative then
                        pendingNpcOrder = displayText
                        displayText = narrative
                    end
                end
                local result = original(self, displayText, ...)
                -- Move announce → physical step-in or special cast-in-place on FIELD.
                if mon and moveName then
                    local moveDef = findMoveByName(self, moveName)
                    if moveDef then
                        local damaging = (moveDef.power or 0) > 0
                            and moveDef.category ~= "status"
                        local cat = foeMoveIsSpecial(moveDef) and "special" or "physical"
                        local kind = damaging and "attack" or "status"
                        local moveId = moveDef.id
                            or tostring(moveName):upper():gsub("[^A-Z0-9]+", "_")
                        tagLatestQueueFieldCue(self, isEnemy and "enemy" or "player",
                            kind, damaging and cat or nil, moveDef.type, moveId)
                    end
                end
                if pendingNpcOrder then
                    if not stampNpcOrderOnAnnounce(self, displayText, pendingNpcOrder) then
                        -- Announce row was not findable; still show the order
                        -- so it is not dropped. Cue pump will refresh it.
                        pushNpcCallout(self, pendingNpcOrder, true, {
                            kind = "order",
                            urgent = true,
                        })
                    end
                end
                if dodgeWhiff then
                    local item = self.queue and self.queue[self.nextInsert]
                    if type(item) == "table" and item.text then
                        item.arDodgeWhiff = true
                        -- Whiff narration lands as the dodge succeeding on-screen.
                        tagFieldCue(item, "player", "dodge")
                    end
                end
                -- After the foe's miss anim + "dodged aside!" text: offer COUNTER!.
                if dodgeWhiff and maybeQueueSameTurnCounter then
                    maybeQueueSameTurnCounter(self)
                elseif type(text) == "string"
                    and text:lower():find("attack missed", 1, true) then
                    -- Foe whiff without dodge cover still arms next-turn openings.
                    publishChipState(self)
                end
                -- Route every battle line into a bubble so the classic box can stay hidden.
                -- Frozen / asleep: narrator bubble (no trainer voice), not the bottom box.
                if opt("speech_bubbles") then
                    if mon then
                        local locked = isEnemy and enemyStatusLocked(self)
                            or ((not isEnemy) and playerStatusLocked(self))
                        if locked or (fieldFlowsText(self) and isEnemy) then
                            -- FIELD: engine "Enemy used X!" stays narrative.
                            tagQueueBubble(self, "narrator")
                        else
                            tagQueueBubble(self, isEnemy and "foe" or "player")
                        end
                    else
                        -- Keep engine auto-advance when present; still draw as a bubble.
                        local side = inferBubbleSide(self, text) or "narrator"
                        local item = self.queue and self.queue[self.nextInsert]
                        local keepAuto = item and item.auto == true
                        tagQueueBubble(self, side, not keepAuto)
                    end
                end
                -- FIELD: keep every line as a short auto toast so fights flow into the
                -- directional move grid without A/B between announcements.
                if fieldFlowsText(self) then
                    local item = self.queue and self.queue[self.nextInsert]
                    if item and item.text then
                        applyFieldToastAuto(item)
                    end
                end
                -- Opposing trainer shouts on send-outs (personality-flavored).
                do
                    local api = BattleState._arSendBanterApi
                    if api and type(api.enqueue) == "function" then
                        api.enqueue(self, text)
                    else
                        maybeEnqueueSendBanter(self, text)
                    end
                end
                -- Let callouts finish (A/B) before dodge/brace or counter menus.
                if (methodName == "sayNextAuto" or methodName == "sayAuto")
                    and (hud.willShowCalloutPick(self, text) or hud.willShowCounterPick(self, text))
                    and not fieldFlowsText(self) then
                    local item = self.queue and self.queue[self.nextInsert]
                    if item and item.text then
                        item.auto = nil
                        item.autoDelay = nil
                    end
                end
                -- After your announce is queued: drop temp dodge/brace stages.
                if mon and not isEnemy then
                    resolveCoverOnPlayerAttack(self, bare or playerMonName(self))
                    local st = momentumState(self)
                    -- Same-round bonus counter: don't stack another foe dodge on top.
                    if st.sameTurnCounterStrike then
                        st.sameTurnCounterStrike = nil
                    else
                        -- Trainer foe may auto-dodge/brace before your hit resolves.
                        -- Only stash while the same-turn COUNTER! menu is still pending —
                        -- auto-counter from an entrench STRIKE / prior opening must react
                        -- here (before the anim), or brace sparkles land after damage/faint.
                        local moveDef = moveName and findMoveByName(self, moveName)
                        local damaging = moveDef and (moveDef.power or 0) > 0
                            and moveDef.category ~= "status"
                        if damaging and (st.sameTurnCounterQueued or st.offerSameTurnCounter) then
                            st.pendingFoeReaction = { moveDef = moveDef }
                        elseif damaging then
                            local foeLine, foeBuffs, foeTrack, failNarr =
                                tryFoeCoverReaction(self, moveDef)
                            if foeLine then
                                local foeBubble = isDodgeFailNarrator(foeLine) and "narrator" or "foe"
                                local foeCue = fieldCueForFoeCover(foeBuffs, foeLine)
                                enqueueReactWithAttack(self, foeLine, S.CALLOUT_AUTO_DELAY,
                                    foeBubble, foeCue)
                                applyCalloutBuffs(self, foeBuffs, foeTrack)
                                if foeTrack and foeBuffs then
                                    local braced = false
                                    for i = 1, #foeBuffs do
                                        if foeBuffs[i].stat == "defense" then
                                            braced = true
                                            break
                                        end
                                    end
                                    if braced then
                                        enqueueBraceAnim(self, { foe = true })
                                    end
                                end
                                publishChipState(self)
                            end
                            if failNarr then
                                -- Narrator only — never a trainer speech bubble.
                                enqueueAutoAfter(self, failNarr, S.CALLOUT_AUTO_DELAY, "narrator",
                                    { side = "enemy", kind = "hit" })
                            end
                        end
                    end
                end
                if reaction then
                    -- Failed dodges use the narrator bubble, not a trainer bubble.
                    local bubbleSide = "narrator"
                    if not isDodgeFailNarrator(reaction) then
                        bubbleSide = isEnemy and "foe" or "player"
                    end
                    enqueueReactWithAttack(self, reaction, S.CALLOUT_AUTO_DELAY, bubbleSide, fieldCue)
                    applyCalloutBuffs(self, buffs, trackTemp)
                    local st = momentumByBattle[self]
                    if isEnemy and st and st.temp and trackTemp then
                        if st.temp.cover then
                            if st.temp.hidAway then
                                tryVanishEvasion(self, playerMonName(self))
                            end
                            enqueueDodgeHideAnim(self, nil)
                        else
                            enqueueBraceAnim(self, {
                                entrenched = st.temp.entrenched == true,
                            })
                        end
                    end
                    publishChipState(self)
                end
                return result
            end
            hud.patched[original] = true
            hud.patched[wrapped] = true
            BattleState._arAnimeSayPatched[methodName] = true
            BattleState[methodName] = wrapped
        end

        hud.wrapBattleSay("sayNext")
        hud.wrapBattleSay("say")
        hud.wrapBattleSay("sayNextAuto")
        hud.wrapBattleSay("sayAuto")

        hud.isDigits = function(text)
            return type(text) == "string" and text:match("^%d+$") ~= nil
        end

        hud.isHpFraction = function(text)
            return type(text) == "string" and text:match("^%s*%d+%s*/%s*%d+%s*$") ~= nil
        end

        -- Gen 3 UI / modern overlays print "Lv.12" instead of the native <LV> tile.
        hud.isLevelTag = function(text)
            local s = tostring(text or "")
            return s:match("^[Ll][Vv]%.") ~= nil
        end

        hud.isHpLabel = function(text)
            local s = tostring(text or ""):upper()
            return s == "HP" or s == "EXP"
        end

        hud.wrapHudPaint = function(fn, ...)
            local prev = hud.hidingHud
            hud.hidingHud = true
            local ok, a, b, c = pcall(fn, ...)
            hud.hidingHud = prev
            if not ok then
                error(a, 0)
            end
            return a, b, c
        end

        -- Live Font.draw lookup: native digits + "Lv." tags from UI overhaul mods.
        hud.origFontDraw = Font.draw
        function Font.draw(text, x, y, ...)
            if hud.isLevelTag(text) or hud.isHpFraction(text) then
                return
            end
            if hud.hidingHud and not hideAllHud() then
                if hud.isDigits(text) and (y == 8 or y == 64) then
                    return
                end
            end
            return hud.origFontDraw(text, x, y, ...)
        end

        -- True while a patched Gen3 (etc.) battle status HUD is painting.

        -- Catch TrueType love.graphics.print/printf "Lv." tags from UI overhauls.
        -- HP numbers are filtered only while a battle status HUD paint is active,
        -- so party/summary HP text stays visible when only HIDE BATTLE HP is on.
        hud.installLoveTextFilters = function()
            if not (love and love.graphics) or hud.patched.__love_text then
                return
            end
            hud.patched.__love_text = true
            local g = love.graphics
            local origPrint, origPrintf = g.print, g.printf
            function g.print(text, ...)
                if hud.isLevelTag(text) or hud.isHpFraction(text) or hud.isHpLabel(text) then
                    return
                end
                return origPrint(text, ...)
            end

            function g.printf(text, ...)
                if hud.isLevelTag(text) or hud.isHpFraction(text) or hud.isHpLabel(text) then
                    return
                end
                return origPrintf(text, ...)
            end
        end

        -- Table-path draws (WideBattle, party, etc.).
        hud.origHPBar = HudTiles.drawHPBar
        function HudTiles.drawHPBar(data, tx, ty, mon, barType, ...)
            -- Never draw HP bars (battle, party, summary).
            return
        end

        hud.origTile = HudTiles.tile
        function HudTiles.tile(code, x, y, ...)
            if code == 0x6E then
                return
            end
            return hud.origTile(code, x, y, ...)
        end

        hud.origStatusTile = HudTiles.statusTile
        if hud.origStatusTile then
            function HudTiles.statusTile(code, x, y, ...)
                if code == 0x6E then
                    return
                end
                return hud.origStatusTile(code, x, y, ...)
            end
        end

        hud.wrapHudDraw = function(inner)
            return function(...)
                if hideAllHud() then
                    return
                end
                return hud.wrapHudPaint(inner, ...)
            end
        end

        -- Classic BattleState caches drawHPBar/hudTile as locals. Dramatic Shape
        -- also keeps an innerHUDs upvalue that bypasses later BattleState.drawHUDs
        -- wraps. Patch those upvalues after every mod has installed.
        hud.patchDrawLocals = function(fn, seen)
            if type(fn) ~= "function" then
                return
            end
            if not (debug and type(debug.getupvalue) == "function"
                and type(debug.setupvalue) == "function") then
                return
            end
            seen = seen or {}
            if seen[fn] then
                return
            end
            seen[fn] = true

            local i = 1
            while true do
                local name, val = debug.getupvalue(fn, i)
                if not name then
                    break
                end

                if name == "drawHPBar" and type(val) == "function" and not hud.patched[val] then
                    local wrapped = function()
                        return
                    end
                    hud.patched[val] = true
                    hud.patched[wrapped] = true
                    debug.setupvalue(fn, i, wrapped)
                elseif name == "hudTile" and type(val) == "function" and not hud.patched[val] then
                    local wrapped = function(code, x, y, tint)
                        if code == 0x6E then
                            return
                        end
                        return val(code, x, y, tint)
                    end
                    hud.patched[val] = true
                    hud.patched[wrapped] = true
                    debug.setupvalue(fn, i, wrapped)
                elseif (name == "innerHUDs" or name == "drawHUDs") and type(val) == "function" then
                    if not hud.patched[val] then
                        local wrapped = hud.wrapHudDraw(val)
                        hud.patched[val] = true
                        hud.patched[wrapped] = true
                        debug.setupvalue(fn, i, wrapped)
                        hud.patchDrawLocals(val, seen)
                    else
                        hud.patchDrawLocals(val, seen)
                    end
                end
                i = i + 1
            end
        end

        hud.installBattleDrawWrap = function()
            local current = BattleState.drawHUDs
            if hud.patched[current] then
                hud.patchDrawLocals(current)
                return
            end
            local wrapped = hud.wrapHudDraw(current)
            hud.patched[current] = true
            hud.patched[wrapped] = true
            BattleState.drawHUDs = wrapped
            hud.patchDrawLocals(current)
            hud.patchDrawLocals(wrapped)
        end

        hud.installWideWrap = function()
            -- Only patch WideBattle's local drawHUDs — do not wrap the whole wide
            -- draw (that would also filter the dialogue box).
            hud.patchDrawLocals(WideBattle.draw)
        end

        -- Dramatic Shape snaps HUD bands + frosted panels outside drawHUDs.
        hud.installDramaticShapeHide = function()
            if type(dev.installCoverPropStampHooks) == "function" then
                pcall(dev.installCoverPropStampHooks)
            end
            if type(dev.installFieldFightSpriteHook) == "function" then
                pcall(dev.installFieldFightSpriteHook)
            end
            if FieldBattleViewer and type(FieldBattleViewer.install) == "function" then
                pcall(FieldBattleViewer.install, mod)
            end
            local handle = mod.find and mod.find("DRAMATIC_SHAPE")
            local lib = handle and handle.exports and handle.exports.lib
            if not (lib and type(lib.require) == "function") then
                return
            end
            local ok, OverworldBattle = pcall(lib.require, "OverworldBattle")
            if not ok or type(OverworldBattle) ~= "table" then
                return
            end

            -- Frosted name/HP panels follow hudLive; returning false skips those
            -- boxes while leaving the dialogue panel alone.
            if type(OverworldBattle.hudLive) == "function" and not hud.patched[OverworldBattle.hudLive] then
                local origLive = OverworldBattle.hudLive
                OverworldBattle.hudLive = function(battle, slide)
                    if hideAllHud() then
                        return false, false
                    end
                    return origLive(battle, slide)
                end
                hud.patched[origLive] = true
                hud.patched[OverworldBattle.hudLive] = true
            end

            -- Drop the frosted glass slab under the battle text box while bubbles speak.
            if type(OverworldBattle.textRects) == "function"
                and not hud.patched[OverworldBattle.textRects] then
                local origRects = OverworldBattle.textRects
                OverworldBattle.textRects = function(battle)
                    local out = origRects(battle)
                    if hud.bubblesOwnDialogue(battle) and type(out) == "table" then
                        out.box = nil
                    end
                    return out
                end
                hud.patched[origRects] = true
                hud.patched[OverworldBattle.textRects] = true
            end
        end

        -- Gen 3 Inspired UI (and similar) keep their own printText / HUD drawers as
        -- upvalues on render.hud / battle.overlay wraps. Patch those after load so
        -- "Lv." tags and status panels honor this mod's options.
        hud.patchCompatUiFn = function(fn, seen)
            if type(fn) ~= "function" or seen[fn] then
                return
            end
            if not (debug and type(debug.getupvalue) == "function"
                and type(debug.setupvalue) == "function") then
                return
            end
            seen[fn] = true
            local i = 1
            while true do
                local name, val = debug.getupvalue(fn, i)
                if not name then
                    break
                end
                if type(val) == "function" and not hud.patched[val] then
                    if name == "renderHudHook" then
                        -- Gen 3's battle UI is reached through a table of renderer methods,
                        -- so its individual drawers are not all visible as callback upvalues.
                        -- Bypass the top-level foreground pass for FIELD instead.
                        local inner = val
                        local wrapped = function(ownerMod, next, game, ...)
                            if hud.fieldBattleInGame(game) then
                                return next(game, ...)
                            end
                            return inner(ownerMod, next, game, ...)
                        end
                        hud.patched[val] = true
                        hud.patched[wrapped] = true
                        debug.setupvalue(fn, i, wrapped)
                    elseif name == "printText" or name == "partyText" or name == "finalText" then
                        local inner = val
                        local wrapped = function(text, ...)
                            local s = tostring(text or "")
                            if hud.isLevelTag(s) or hud.isHpLabel(s) or hud.isHpFraction(s) then
                                return
                            end
                            if hud.suppressingBattleHpText and hud.isHpFraction(s) then
                                return
                            end
                            return inner(text, ...)
                        end
                        hud.patched[val] = true
                        hud.patched[wrapped] = true
                        debug.setupvalue(fn, i, wrapped)
                    elseif name == "drawDialogue"
                        or name == "drawCommandMenu" or name == "drawMoveSelect" then
                        -- Gen 3 Inspired UI paints its own cream dialogue panel; skip it
                        -- while SPEECH BUBBLE owns the message beat.
                        local inner = val
                        local wrapped = function(battle, ...)
                            if hud.fieldCompactActive(battle) or hud.bubblesOwnDialogue(battle) then
                                return
                            end
                            return inner(battle, ...)
                        end
                        hud.patched[val] = true
                        hud.patched[wrapped] = true
                        debug.setupvalue(fn, i, wrapped)
                    elseif name == "drawEnemyHUD" or name == "drawPlayerHUD" then
                        local inner = val
                        local wrapped = function(...)
                            local battle = select(1, ...)
                            if hud.fieldCompactActive(battle) or hideAllHud() then
                                return
                            end
                            local prev = hud.suppressingBattleHpText
                            hud.suppressingBattleHpText = true
                            local ok, a, b, c = pcall(inner, ...)
                            hud.suppressingBattleHpText = prev
                            if not ok then
                                error(a, 0)
                            end
                            return a, b, c
                        end
                        hud.patched[val] = true
                        hud.patched[wrapped] = true
                        debug.setupvalue(fn, i, wrapped)
                    elseif name == "drawStyledHP" or name == "drawPartyExpBar" then
                        local wrapped = function()
                            return
                        end
                        hud.patched[val] = true
                        hud.patched[wrapped] = true
                        debug.setupvalue(fn, i, wrapped)
                    elseif name == "partyHPBarFinal" then
                        local inner = val
                        local partyTextFn = nil
                        for j = 1, 48 do
                            local n, v = debug.getupvalue(fn, j)
                            if n == "partyText" and type(v) == "function" then
                                partyTextFn = v
                                break
                            end
                        end
                        local wrapped = function(x, y, w, mon, ...)
                            local hint = partyRowHint(mon)
                            if hint and partyTextFn then
                                partyTextFn(hint, x, y - 2, 3, { 0.46, 0.14, 0.12, 1 })
                                return
                            end
                            -- Still never draw the real HP bar.
                            return
                        end
                        hud.patched[val] = true
                        hud.patched[wrapped] = true
                        debug.setupvalue(fn, i, wrapped)
                    elseif name == "drawEXPRow" then
                        local inner = val
                        local wrapped = function(...)
                            if opt("hide_xp_bar") or hideAllHud() then
                                return
                            end
                            return inner(...)
                        end
                        hud.patched[val] = true
                        hud.patched[wrapped] = true
                        debug.setupvalue(fn, i, wrapped)
                    else
                        hud.patchCompatUiFn(val, seen)
                    end
                end
                i = i + 1
            end
        end

        hud.installCompatUiOverrides = function()
            hud.installLoveTextFilters()
            local Runtime = require("src.mods.Runtime")
            local chains = Runtime.hooks and Runtime.hooks.chains
            if type(chains) ~= "table" then
                return
            end
            local seen = {}
            for _, hookName in ipairs({ "render.hud", "battle.overlay" }) do
                local chain = chains[hookName]
                if type(chain) == "table" then
                    for _, entry in ipairs(chain) do
                        if entry and type(entry.callback) == "function" then
                            -- Prefer known UI overhaul owners; still walk unknown wraps that
                            -- close over printText/drawEnemyHUD.
                            if entry.owner == "gen3_battle_ui"
                                or entry.owner == nil
                                or type(entry.owner) == "string" then
                                hud.patchCompatUiFn(entry.callback, seen)
                            end
                            -- Gen 3 UI has multiple late foreground passes. Skipping its whole
                            -- hook during FIELD is more reliable than patching individual
                            -- captured drawers, and leaves BattleState/input ownership intact.
                            local skipFieldUi = entry.owner == "gen3_battle_ui"
                                or entry.owner == "move_inspector"
                                or entry.owner == "typed_move_colors"
                            if skipFieldUi and not entry._arFieldUiSkip then
                                local inner = entry.callback
                                if hookName == "render.hud" then
                                    entry.callback = function(next, game, ...)
                                        if hud.fieldBattleInGame(game) then
                                            return next(game, ...)
                                        end
                                        return inner(next, game, ...)
                                    end
                                else
                                    entry.callback = function(next, battle, ...)
                                        if hud.fieldCompactActive(battle) then
                                            return next(battle, ...)
                                        end
                                        return inner(next, battle, ...)
                                    end
                                end
                                entry._arFieldUiSkip = true
                            end
                        end
                    end
                end
            end
        end

        mod.events:on("mods.loaded", function()
            hud.installBattleDrawWrap()
            hud.installWideWrap()
            hud.installDramaticShapeHide()
            hud.installCompatUiOverrides()
            if FieldBattleViewer and type(FieldBattleViewer.install) == "function" then
                pcall(FieldBattleViewer.install, mod)
            end
        end)
        mod.events:on("game.ready", function()
            hud.installLoveTextFilters()
            hud.installCompatUiOverrides()
            if FieldBattleViewer and type(FieldBattleViewer.install) == "function" then
                pcall(FieldBattleViewer.install, mod)
            end
        end)
        -- Hot reload / late installers.
        hud.installBattleDrawWrap()
        hud.installWideWrap()
        hud.installDramaticShapeHide()
        hud.installCompatUiOverrides()

        -- Suppress the QoL thin XP rectangle (classic, wide, and Dramatic Shape).
        mod.events:on("battle.started", function(ev)
            local battle = ev and ev.battle
            if not battle or type(battle.draw) ~= "function" or battle.__lhh_draw then
                return
            end
            local baseDraw = battle.draw
            battle.draw = function(self, ...)
                if not (opt("hide_xp_bar") or hideAllHud()) then
                    return baseDraw(self, ...)
                end
                local g = love.graphics
                local origRect = g.rectangle
                g.rectangle = function(mode, x, y, w, h, ...)
                    if mode == "fill" and type(h) == "number" and type(w) == "number"
                        and h > 0 and h <= 16 and w >= 2 then
                        local shot = rawget(self, "dramaticShapeShot")
                        if type(shot) == "table" and type(shot.ly) == "number"
                            and type(shot.scale) == "number" and shot.scale > 0 then
                            local expY = shot.ly + 89 * shot.scale
                            if math.abs((y or 0) - expY) <= shot.scale then
                                return
                            end
                        end
                        -- Classic / wide QoL XP strip sits on rows 88-91.
                        if (y or 0) >= 88 and (y or 0) <= 94 and h <= 4 then
                            return
                        end
                    end
                    return origRect(mode, x, y, w, h, ...)
                end
                local ok, a, b, c = pcall(baseDraw, self, ...)
                g.rectangle = origRect
                if not ok then
                    error(a, 0)
                end
                return a, b, c
            end
            battle.__lhh_draw = true
        end)

        -- Party menu: never show level/HP; print a heal hint on the old HP row.
        hud.origPartyDraw = PartyMenu.draw
        function PartyMenu.draw(self)
            local prevDraw, prevTile = Font.draw, HudTiles.tile
            local prevHPBar = HudTiles.drawHPBar

            Font.draw = function(text, x, y, ...)
                if hud.isLevelTag(text) or hud.isHpFraction(text) then
                    return
                end
                if hud.isDigits(text) and (x == 104 or x == 112) and (y % 16 == 0) then
                    return
                end
                return prevDraw(text, x, y, ...)
            end
            HudTiles.tile = function(code, x, y, ...)
                if code == 0x6E then
                    return
                end
                return prevTile(code, x, y, ...)
            end
            HudTiles.drawHPBar = function()
                return
            end

            local ok, err = pcall(hud.origPartyDraw, self)
            Font.draw = prevDraw
            HudTiles.tile = prevTile
            HudTiles.drawHPBar = prevHPBar
            if not ok then
                error(err, 0)
            end

            if self.tmhm then
                return
            end
            local party = self.party or (self.game.save and self.game.save.party) or {}
            love.graphics.setColor(0, 0, 0, 1)
            for i, mon in ipairs(party) do
                local hint = partyRowHint(mon)
                if hint then
                    local y = PartyMenu.entryY(i)
                    prevDraw(hint, 40, y + 8)
                end
            end
            love.graphics.setColor(1, 1, 1, 1)
        end

        -- Summary (STATS): hide level + HP bar/numbers.
        hud.origSummaryDraw = SummaryMenu.draw
        function SummaryMenu.draw(self)
            local prevDraw = Font.draw
            local prevStatus = HudTiles.statusTile
            local prevTile = HudTiles.tile
            local prevHPBar = HudTiles.drawHPBar

            Font.draw = function(text, x, y, ...)
                if hud.isLevelTag(text) or hud.isHpFraction(text) then
                    return
                end
                if hud.isDigits(text) then
                    if (y == 16 and (x == 112 or x == 120))
                        or (y == 48 and (x == 128 or x == 136)) then
                        return
                    end
                end
                return prevDraw(text, x, y, ...)
            end
            local function hideLv(code, x, y)
                return code == 0x6E
                    and ((x == 112 and y == 16) or (x == 128 and y == 48))
            end
            if prevStatus then
                HudTiles.statusTile = function(code, x, y, tint)
                    if hideLv(code, x, y) then
                        return
                    end
                    return prevStatus(code, x, y, tint)
                end
            end
            HudTiles.tile = function(code, x, y, tint)
                if hideLv(code, x, y) then
                    return
                end
                return prevTile(code, x, y, tint)
            end
            HudTiles.drawHPBar = function()
                return
            end

            local ok, err = pcall(hud.origSummaryDraw, self)
            Font.draw = prevDraw
            HudTiles.statusTile = prevStatus
            HudTiles.tile = prevTile
            HudTiles.drawHPBar = prevHPBar
            if not ok then
                error(err, 0)
            end
        end

        -- Dev overlay paints after the battle frame (classic + wide).
        do
            local origDraw = BattleState.draw
            if type(origDraw) == "function" then
                function BattleState.draw(self)
                    local result = origDraw(self)
                    -- Ambient menu pulses: ensure Gen1 anim sprites paint even
                    -- if the engine skipped them outside a queued attack.
                    if self and self._arAmbientOwned and self.animPlayer then
                        local ap = self.animPlayer
                        if type(ap.drawSprites) == "function" then
                            pcall(ap.drawSprites, ap)
                        end
                        if type(ap.draw) == "function" then
                            pcall(ap.draw, ap)
                        end
                    end
                    dev.draw(self)
                    return result
                end
            end
        end

        mod.log:info("levels/HP hidden; party list shows heal hints only")
    end
end
