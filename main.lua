-- Anime Realism
--
-- Three packages (see folders):
--   hud/     — hide numbers + underdog EXP / effort
--   battle/  — rules, REACT menus, FX policy, banter/bubble paint,
--              callout rewrite, say wraps, picFx enqueue
--   field/   — overworld FIELD combat (BattleState on the live map)
--
-- main.lua is the orchestrator + remaining shared hooks (moving into packages
-- over time). lib/modload.lua loads folder packages for zip + loose installs.
--
-- Flip to false for release builds. When true, lib/log.lua prints battle
-- traces to the Love / stdout console (independent of DEV OVERLAY).
local DEV = false

return function(mod)
    local Hud
    local Battle
    local FieldBattleViewer
    local ReactiveDefense
    local React
    local Fx

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
        local value, err = ModLoad.loadPackage("hud")
        if type(value) == "table" then
            Hud = value
        else
            print("[anime_realism] hud: " .. tostring(err))
        end

        value, err = ModLoad.loadPackage("battle")
        if type(value) == "table" then
            Battle = value
            ReactiveDefense = Battle.ReactiveDefense
            React = Battle.React
            Fx = Battle.Fx
        else
            print("[anime_realism] battle: " .. tostring(err))
        end

        value, err = ModLoad.loadPackage("field")
        if type(value) == "table" then
            FieldBattleViewer = value
        else
            print("[anime_realism] field: " .. tostring(err))
        end
    end

    do
        local factory = ModLoad and type(ModLoad.loadFile) == "function"
            and select(1, ModLoad.loadFile("lib/log.lua"))
        if type(factory) == "function" then
            local okL, log = pcall(factory, {
                enabled = function()
                    return DEV
                end,
            })
            if okL and type(log) == "table" then
                mod._arLog = log
                if DEV and type(log.note) == "function" then
                    pcall(log.note, nil, "boot", "DEV console log ON")
                end
            elseif DEV then
                print("[ar] log init: " .. tostring(log))
            end
        elseif DEV then
            print("[ar] lib/log.lua missing")
        end
    end

    -- Crash dump: do not assign love.errorhandler (sandbox refuses it so
    -- the player still gets the engine crash screen). Event listeners are
    -- pcall'd by the host, so wrap mod.events so a throw still prints the
    -- [ar] trail instead of vanishing as a one-line Logger.error.
    do
        local function dumpCrash(where, err)
            pcall(print, "[ar] CRASH " .. tostring(where) .. " " .. tostring(err))
            local Log = mod._arLog
            if Log and type(Log.err) == "function" then
                pcall(Log.err, nil, where, err)
            elseif Log and type(Log.dump) == "function" then
                pcall(Log.dump)
            end
        end

        local function wrapListener(name, callback)
            if type(callback) ~= "function" then
                return callback
            end
            return function(payload)
                local ok, err = xpcall(function()
                    return callback(payload)
                end, tostring)
                if not ok then
                    dumpCrash("event." .. tostring(name), err)
                    error(err)
                end
            end
        end

        if type(mod.events) == "table" and type(mod.events.on) == "function"
            and not mod.events._arDump then
            local origOn = mod.events.on
            mod.events.on = function(self, name, callback, priority)
                return origOn(self, name, wrapListener(name, callback), priority)
            end
            if type(mod.events.once) == "function" then
                local origOnce = mod.events.once
                mod.events.once = function(self, name, callback, priority)
                    return origOnce(self, name, wrapListener(name, callback), priority)
                end
            end
            mod.events._arDump = true
            if DEV then
                pcall(print, "[ar] crash dump on mod.events")
            end
        end
    end

    if ModLoad and type(ModLoad.loadPackage) == "function" then
        -- Expose packages before install so FBV.bind can inject ReactiveDefense.
        mod._arPackages = {
            hud = Hud,
            battle = Battle,
            field = FieldBattleViewer,
            log = mod._arLog,
        }

        if Hud then
            pcall(Hud.install, mod)
        end
        if Battle then
            pcall(Battle.install, mod)
        end
        if FieldBattleViewer then
            pcall(FieldBattleViewer.bind, mod._arPackages)
            pcall(FieldBattleViewer.install, mod)
        end

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
                key = "move_hud",
                type = "choice",
                label = "MOVE HUD",
                default = "CLASSIC",
                choices = {
                    { "CLASSIC", "CLASSIC" },
                    { "DIAMOND", "DIAMOND" },
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
                key = "react_hud",
                type = "choice",
                label = "REACT HUD",
                default = "GRID",
                choices = {
                    { "GRID",    "GRID" },
                    { "TABS",    "TABS" },
                    { "DIAMOND", "DIAMOND" },
                },
            },
            {
                key = "focus_bar",
                type = "choice",
                label = "FOCUS BAR",
                default = "OFF",
                choices = {
                    { "OFF",   "OFF" },
                    { "FLUSH", "FLUSH" },
                    { "1PX",   "1PX" },
                },
            },
            {
                key = "close_the_gap",
                type = "toggle",
                label = "CLOSE THE GAP",
                default = true,
            },
            {
                key = "status_chips",
                type = "toggle",
                label = "STATUS CHIPS",
                default = true,
            },
            {
                key = "battle_faces",
                type = "toggle",
                label = "BATTLE FACES",
                default = true,
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
        -- FIELD = anime map fight. Legacy STADIUM saves keep FIELD (stadium
        -- presentation is gone). CLASSIC maps to AUTO.
        local function battleStage()
            if FieldBattleViewer and type(FieldBattleViewer.stage) == "function" then
                return FieldBattleViewer.stage(mod)
            end
            local raw = tostring(mod.options:get("battle_stage") or "FIELD"):upper()
            if raw == "FIELD" or raw == "STADIUM" then
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

        function dev.focusBarMode()
            local raw = mod.options:get("focus_bar")
            if raw == nil then
                if mod.options:get("focus_bar_visible") == true then
                    return "FLUSH"
                end
                return "OFF"
            end
            if raw == true then
                return "FLUSH"
            end
            local s = tostring(raw):upper()
            if s == "FLUSH" or s == "1PX" then
                return s
            end
            if s == "1" or s == "1PXL" or s == "1 PIXEL" then
                return "1PX"
            end
            return "OFF"
        end

        function dev.focusBarVisible()
            local mode = dev.focusBarMode()
            return mode == "FLUSH" or mode == "1PX"
        end

        do
            local UI = FieldBattleViewer and FieldBattleViewer.UI
            if UI then
                UI.focusBarVisible = function()
                    return dev.focusBarVisible() and opt("momentum_counter")
                end
                UI.focusBarGap = function()
                    if dev.focusBarMode() == "1PX" then
                        return 1
                    end
                    return 0
                end
                UI.focusRatio = function(battle, isPlayer)
                    if not ReactiveDefense or not battle then
                        return nil
                    end
                    local battler = isPlayer and battle.player or battle.enemy
                    local side = ReactiveDefense.sideState(battle, isPlayer)
                    local cap = ReactiveDefense.focusCap(battler)
                    if not side or not cap or cap <= 0 then
                        return nil
                    end
                    return math.max(0, math.min(1, (tonumber(side.focus) or 0) / cap))
                end
                UI.faceEnabled = function()
                    return mod.options:get("battle_faces") ~= false
                end
                UI.faceFlash = function(battle, isPlayer)
                    local Portraits = Battle and Battle.Portraits
                    if Portraits and type(Portraits.flash) == "function" then
                        return Portraits.flash(battle, isPlayer)
                    end
                end
                UI.moodOf = function(battle, isPlayer)
                    local E = Battle and Battle.Emotions
                    if E and type(E.mood) == "function" then
                        return E.mood(battle, isPlayer)
                    end
                end
                UI.moodChip = function(mood)
                    local E = Battle and Battle.Emotions
                    if E and type(E.chip) == "function" then
                        return E.chip(mood)
                    end
                end
            end
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
            local Log = mod._arLog
            if Log and type(Log.note) == "function" then
                pcall(Log.note, battle, tag, detail)
            end
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

        function dev.noteMood(battle, ev)
            local E = Battle and Battle.Emotions
            if not E or type(battle) ~= "table" then
                return
            end
            if ev then
                E.note(battle, ev)
            elseif type(E.refresh) == "function" then
                E.refresh(battle)
            end
            if type(E.announce) == "function" then
                E.announce(battle)
            end
        end

        local function reactHudStyle()
            local raw = tostring(mod.options:get("react_hud") or "GRID"):upper()
            if raw == "TABS" or raw == "DIAMOND" then
                return raw
            end
            return "GRID"
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

        local function lowHpRatio()
            local choice = tostring(mod.options:get("low_hp_threshold") or "20")
            if choice == "40" then
                return 0.40
            end
            return 0.20
        end

        local S = (Battle and Battle.Strings) or {}

        local function pickLine(lines)
            local n = #lines
            if n == 0 then
                return nil
            end
            local r = (love and love.math and love.math.random) or math.random
            return lines[r(n)]
        end

        -- Party HP row: current HP / max HP (mon.stats.hp is fully-healed total).
        -- Same bands as field health chips (red ≤20%, yellow ≤50%).
        local TIRED_HP_RATIO = 0.5

        local function partyMonHealth(mon)
            if type(mon) ~= "table" then
                return nil
            end
            local current = tonumber(mon.hp)
            local maxHp = mon.stats and tonumber(mon.stats.hp)
            if not current or not maxHp or maxHp <= 0 then
                return nil
            end
            return current, maxHp, current / maxHp
        end

        local function partyHasStatus(mon)
            local st = mon and mon.status
            return type(st) == "string" and st ~= ""
        end

        local function partyRowHint(mon)
            local current, maxHp, ratio = partyMonHealth(mon)
            if not maxHp then
                return nil
            end
            if current <= 0 then
                return "FAINTED-HEAL!"
            end
            local hasStatus = partyHasStatus(mon)
            local band
            if ratio <= 0.20 then
                band = "WK"
            elseif ratio <= TIRED_HP_RATIO then
                band = "TRD"
            end
            if band and hasStatus then
                return band .. "-HEAL!"
            end
            if band then
                return band .. "!"
            end
            if hasStatus then
                return "HEAL!"
            end
            return nil
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
        -- Momentum table lives in battle/rules/react.lua (React.state / peek).
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
        local maybeEnqueueSendBanter
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

        local function momentumState(battle)
            if React then
                return React.state(battle)
            end
            return { temp = {}, enemyTemp = {} }
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
                return React and React.peek(battle) or nil
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
            if React then
                React.reset(battle)
            end
        end

        local function clearBattleMomentum(battle)
            if battle then
                clearAmbientStance(battle)
            end
            if not battle then
                return
            end
            if React then
                React.clear(battle)
            end
        end

        local function foeMoveIsSpecial(move)
            if not move then
                return false
            end
            if ReactiveDefense and type(ReactiveDefense.isSpecialClashIncoming) == "function"
                and ReactiveDefense.isSpecialClashIncoming(move) then
                return true
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
            if not opt("momentum_counter") or not battle or not React then
                return false
            end
            local state = React.peek(battle)
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
            print("[ar] estimateMoveDamage: " .. tostring(dmg) .. " " .. tostring(ok) .. " " .. tostring(move.power))
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

        mod.events:on("battle.started", function(ev)
            if ev and ev.battle then
                lowWarned[ev.battle] = { player = false, enemy = false }
                clearBattleMomentum(ev.battle)
                clearCalloutPickState(ev.battle)
                if ReactiveDefense then
                    ReactiveDefense.clear(ev.battle)
                    ReactiveDefense.state(ev.battle)
                end
                if Battle and Battle.Emotions then
                    Battle.Emotions.clear(ev.battle)
                    Battle.Emotions.state(ev.battle)
                    Battle.Emotions.refresh(ev.battle)
                end
                dev.log(ev.battle, "BATTLE start", battleStage())
            end
        end)

        mod.events:on("battle.ended", function(ev)
            if ev and ev.battle then
                dev.log(ev.battle, "BATTLE end")
                resolvePendingDamage(ev.battle)
                clearCalloutPickState(ev.battle)
                clearAmbientStance(ev.battle)
                if Battle and Battle.Notices and type(Battle.Notices.clear) == "function" then
                    Battle.Notices.clear(ev.battle)
                end
                if Battle and Battle.Emotions then
                    Battle.Emotions.clear(ev.battle)
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
                battle._arAccuracyPred = nil
                battle._arAwaitAccuracyCue = nil
                local st = React.peek(battle)
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
                    st.dodgeMissSide = nil
                    st.queuedPlayerAction = ev.playerAction or battle._arQueuedPlayerAction
                    st.queuedEnemyAction = ev.enemyAction
                    st.skipQueuedPlayerAction = nil
                    st.skipQueuedEnemyAction = nil
                    st.fireNowMove = nil
                end
                battle._arAwaitCallout = nil
                battle._arAwaitAgain = nil
                battle._arAwaitAgainSide = nil
                battle._arFireNowHit = nil
                battle._arFireCarryThrough = nil
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
            elseif side == "enemy" then
                local ms = momentumState(battle)
                ms.enemyTemp = { evasion = 0, defense = 0, cover = false }
                ms.enemyMode = nil
                ms.enemyBoosted = false
                ms.enemyReactedThisTurn = false
            end
            -- New battler may already be low.
            checkLowHp(battle, ev.battler)
            dev.noteMood(battle, { kind = "switch", side = side })
        end)

        mod.events:on("battle.move_used", function(ev)
            if not ev or not ev.battle or not ev.user then
                return
            end
            if not ev.user.isPlayer then
                return
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
                -- Mid-pick faint should not leave a deferred hit hanging.
                resolvePendingDamage(ev.battle)
                clearCalloutPickState(ev.battle)
                revealPlayerPic(ev.battle, false)
            end
            dev.noteMood(ev.battle, { kind = "faint", side = ev.battler })
        end)

        mod.events:on("battle.damage_dealt", function(ev)
            checkLowHp(ev and ev.battle, ev and ev.target)
            if ev and ev.battle and ev.target and (ev.damage or 0) > 0 then
                ev.battle._arLastHitSide = ev.target.isPlayer and "player" or "enemy"
                local maxHP = ev.target.mon and ev.target.mon.stats and ev.target.mon.stats.hp
                local crit = ev.critical or ev.crit or ev.isCrit or ev.wasCrit
                if crit then
                    dev.noteMood(ev.battle, {
                        kind = "crit",
                        side = ev.target,
                        user = ev.user,
                    })
                else
                    dev.noteMood(ev.battle, {
                        kind = "hit",
                        user = ev.user,
                        target = ev.target,
                        damage = ev.damage,
                        maxHp = maxHP,
                    })
                end
            end
            if not ev or not ev.battle then
                return
            end
            local user, target = ev.user, ev.target
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
                local st = React.peek(ev.battle)
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
        --
        -- FIELD peeks this hook on move_used, stashes the boolean, and the
        -- engine's later call returns that stash so RNG is spent once.
        local engineAccuracy = nil

        local function accuracyMoveId(ctx)
            return ctx and ctx.move and ctx.move.id
        end

        local function accuracyPredMatches(pred, ctx)
            if not (pred and ctx and ctx.user and ctx.move) then
                return false
            end
            if pred.user ~= ctx.user then
                return false
            end
            if ctx.target and pred.target and pred.target ~= ctx.target then
                return false
            end
            return pred.moveId == accuracyMoveId(ctx)
        end

        local function bookkeepAccuracyMiss(ctx, hit)
            if hit or not ctx then
                return
            end
            local user, target, battle = ctx.user, ctx.target, ctx.battle
            if not (battle and user) then
                return
            end
            battle._arAccuracyMissSide = user.isPlayer and "player" or "enemy"
            dev.noteMood(battle, {
                kind = "miss",
                side = battle._arAccuracyMissSide,
            })
            if not opt("momentum_counter") then
                return
            end
            local state = momentumState(battle)
            local function coverName(battler)
                if battler and battler.mon and type(battler.mon.nickname) == "string"
                    and battler.mon.nickname ~= "" then
                    return battler.mon.nickname
                end
                return (battler and battler.name) or "POKéMON"
            end
            local function isDodgeHide(temp)
                return temp and temp.cover
                    and ((temp.evasion or 0) > 0 or temp.hidAway or temp.picHidden)
            end
            if target and target.isPlayer and isDodgeHide(state.temp) then
                state.keepDodgeMissAnim = true
                state.dodgeMissName = coverName(target)
                state.dodgeMissSide = "player"
            elseif target and (not target.isPlayer) and isDodgeHide(state.enemyTemp) then
                state.keepDodgeMissAnim = true
                state.dodgeMissName = coverName(target)
                state.dodgeMissSide = "enemy"
            end
            local countering = user.isPlayer and target and not target.isPlayer
                and state.mode == "counter" and not state.boosted
                and not battle._arNoCounterThisTurn
                and not battle._arChargeNow
            if countering then
                state.counterWhiffed = true
                state.mode = nil
                state.boosted = false
            elseif target and target.isPlayer and not user.isPlayer then
                state.mode = "counter"
                state.boosted = false
                state.foeWhiffDamage = estimateMoveDamage(battle, user, target, ctx.move)
                if state.temp and state.temp.cover and state.temp.dodgedOk then
                    state.offerSameTurnCounter = true
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
            elseif user.isPlayer and target and not target.isPlayer then
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

        local function rollAccuracy(next, ctx)
            local hit = next(ctx)
            if not ctx then
                return hit
            end
            local user, target, battle = ctx.user, ctx.target, ctx.battle
            -- Counter after a miss (REACT dodge proc included) always lands.
            local guaranteed = React and type(React.isGuaranteedCounterHit) == "function"
                and React.isGuaranteedCounterHit(battle, user, target)
            if guaranteed then
                hit = true
            elseif hit and FieldBattleViewer
                and type(FieldBattleViewer.applyFarShotAccuracy) == "function" then
                -- Ranged specials from 5+ tiles pick up a light extra miss.
                hit = FieldBattleViewer.applyFarShotAccuracy(battle, ctx, hit)
            end
            if not guaranteed
                and Battle and Battle.Emotions
                and type(Battle.Emotions.nudgeHit) == "function" then
                hit = Battle.Emotions.nudgeHit(battle, user, hit)
            end
            if battle and battle._arFireNow then
                battle._arFireNowHit = hit and true or false
                if not hit then
                    if battle._arCheckNow then
                        battle._arAccuracyMissSide = nil
                    else
                        -- Missed FIRE is a slow shot the charger runs through,
                        -- not a slip-past / dodge hop.
                        battle._arFireCarryThrough = true
                        battle._arAccuracyMissSide = nil
                    end
                end
            end
            if not (battle and battle._arFireCarryThrough) then
                bookkeepAccuracyMiss(ctx, hit)
            end
            return hit
        end

        local function playPendingMoveCue(battle, hit)
            local pending = battle and battle._arAwaitAccuracyCue
            if not pending then
                return
            end
            battle._arAwaitAccuracyCue = nil
            if not (FieldBattleViewer and type(FieldBattleViewer.react) == "function") then
                return
            end
            local kind = hit and pending.kind or "miss"
            local opts = pending.opts or {}
            if battle._arFireNow then
                opts.fireNow = true
            end
            if battle._arFireNow and not hit then
                kind = pending.kind or "attack"
                if battle._arCheckNow then
                    opts.closeTheGap = false
                    opts.followUp = true
                else
                    opts.slowShot = true
                    opts.fireCarry = true
                    battle._arFireCarryThrough = true
                end
            end
            pcall(FieldBattleViewer.react, battle, pending.side, kind, opts)
        end

        local function predictMoveHit(battle, user, target, move)
            if not (battle and user and move) then
                return nil
            end
            local ctx = {
                battle = battle,
                user = user,
                target = target,
                move = move,
            }
            local pred = battle._arAccuracyPred
            if accuracyPredMatches(pred, ctx) then
                return pred.hit
            end
            if type(engineAccuracy) ~= "function" then
                return nil
            end
            -- Roll vanilla + our extras once. Do not go through hooks:call —
            -- that re-enters this wrap and was returning nil (move_used await)
            -- so the toast lunged before the engine's roll.
            battle._arAccuracyPeeking = true
            local ok, hit = pcall(rollAccuracy, engineAccuracy, ctx)
            battle._arAccuracyPeeking = nil
            if not ok then
                return nil
            end
            battle._arAccuracyPred = {
                hit = hit and true or false,
                user = user,
                target = target,
                moveId = move.id,
            }
            return battle._arAccuracyPred.hit
        end

        if FieldBattleViewer then
            FieldBattleViewer.predictMoveHit = predictMoveHit
        end

        mod.hooks:wrap("battle.accuracy", function(next, ctx)
            if not ctx then
                return next(ctx)
            end
            local battle = ctx.battle
            local peeking = battle and battle._arAccuracyPeeking == true
            if not peeking and type(next) == "function" then
                engineAccuracy = next
            end
            if battle and not peeking
                and accuracyPredMatches(battle._arAccuracyPred, ctx) then
                local hit = battle._arAccuracyPred.hit
                battle._arAccuracyPred = nil
                return hit
            end
            local hit = rollAccuracy(next, ctx)
            if peeking and battle and ctx.user and ctx.move then
                battle._arAccuracyPred = {
                    hit = hit and true or false,
                    user = ctx.user,
                    target = ctx.target,
                    moveId = accuracyMoveId(ctx),
                }
            elseif battle and not peeking then
                playPendingMoveCue(battle, hit)
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
            local state = React.peek(battle)
            if state then
                state.breakthroughPending = nil
            end
            if ReactiveDefense and opt("momentum_counter") then
                ReactiveDefense.endTurn(battle)
            end
            dev.noteMood(battle, { kind = "turn" })
            -- Quiet beat: occasional trainer chatter when nothing's in cover.
            if maybeEnqueueIdleBanter then
                maybeEnqueueIdleBanter(battle)
            end
        end)


        -- Reactive Defense damage modifiers + legacy counter +25%.
        mod.hooks:wrap("battle.damage", function(next, ctx)
            local dmg, info = next(ctx)
            if ctx and Battle and Battle.Emotions
                and type(Battle.Emotions.applyDamage) == "function" then
                dmg = Battle.Emotions.applyDamage(ctx.battle, ctx.user, ctx.target, dmg)
            end
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
                if pending and pending.side ~= "enemy" then
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

            if ReactiveDefense and user and user.isPlayer and target and not target.isPlayer then
                local rd = ReactiveDefense.state(battle)
                local pending = rd and rd.hitMod
                if pending and pending.side == "enemy" then
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

            local shotMult = battle and tonumber(battle._arFireShotMult)
            if shotMult and shotMult > 0 and shotMult ~= 1 and type(dmg) == "number" and dmg > 0 then
                battle._arFireShotMult = nil
                battle._arReactSpecialMult = nil
                dmg = math.max(1, math.floor(dmg * shotMult + 0.5))
            end
            local reactMult = battle and tonumber(battle._arReactSpecialMult)
            if reactMult and reactMult > 0 and reactMult ~= 1
                and type(dmg) == "number" and dmg > 0 then
                battle._arReactSpecialMult = nil
                dmg = math.max(1, math.floor(dmg * reactMult + 0.5))
            end
            local chargeMult = battle and tonumber(battle._arChargeShotMult)
            if chargeMult and chargeMult > 0 and chargeMult ~= 1
                and type(dmg) == "number" and dmg > 0 then
                battle._arChargeShotMult = nil
                dmg = math.max(1, math.floor(dmg * chargeMult + 0.5))
            end
            if battle and battle._arCheckNow and type(dmg) == "number" and dmg > 0 then
                dmg = math.max(1, math.floor(dmg * 0.35 + 0.5))
            end

            local state = battle and React.peek(battle)
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


        -- Anime-style trainer callouts for "NAME\nused MOVE!" (not item use).
        -- Wild battles keep the vanilla line. Trainer foes use the trainer's name.
        -- When the foe looks weak (same threshold as LOW HP AT).
        -- After your move announce, when a physical counter is armed.
        -- Going second (foe already acted): announce becomes this line.
        -- formatAutoCounterCall is defined after pickFormatted (Lua locals are
        -- not visible above their declaration — calling early binds a nil global).
        local formatAutoCounterCall
        -- Style-flavored dodge / brace bases (mon name = %s).
        -- Terrain lines: first %s = mon. Keep short for the text box.
        -- Type spice (checked against player curTypes).
        -- Named characters only (gym leaders, E4, etc.). Class titles like
        -- YOUNGSTER / JR.TRAINER use foe mon callouts instead — no "TRAINER!".
        -- trainer, mon, move — softer "NAME:" lead-in, not "NAME!"
        -- Foe Pokémon callouts when the trainer label is a generic class.

        local function isGrewToLevelText(text)
            return Battle.Dialogue.isGrewToLevelText(text)
        end

        -- Engine move announce is "NAME\nused MOVE!". Item use is "NAME used\nITEM!".
        local function parseUsedMoveText(text)
            return Battle.Dialogue.parseUsedMoveText(text)
        end

        local function stripEnemyPrefix(mon)
            return Battle.Dialogue.stripEnemyPrefix(mon)
        end

        local function formatCall(template, a, b, c)
            return Battle.Dialogue.formatCall(template, a, b, c)
        end

        local function pickFormatted(templates, a, b, c)
            return Battle.Dialogue.pickFormatted(templates, a, b, c)
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
            return Battle.Dialogue.formatEnemyMoveCall(trainer, mon, move)
        end

        local function rewriteMoveCallText(battle, text)
            return Battle.Dialogue.rewriteMoveCallText(battle, text)
        end

        local function rewriteLevelUpText(text)
            return Battle.Dialogue.rewriteLevelUpText(text)
        end

        local function isExpGainDialogue(text)
            return Battle.Dialogue.isExpGainDialogue(text)
        end

        local function rewriteBattleText(battle, text)
            return Battle.Dialogue.rewriteBattleText(battle, text)
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

        local function pickCallEntry(kind, battle, monName, moveName)
            return Battle.Dialogue.pickCallEntry(kind, battle, monName, moveName)
        end

        -- Narrator line for a failed dodge (bottom text box, not a speech bubble).
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
        -- Miss while dodging — replaces vanilla "attack missed!".
        -- Evasive hide (PATH / grass / fly / …): chance for extra EVADE.
        -- Light buff vs plain sidestep — brush/cover should feel worth picking.
        -- Weighted EVADE rolls so dodge strength isn't fixed by the menu pick.
        -- basic = plain DODGE sidestep; hide = PATH / grass / fly / dive / …
        -- Hide leans a touch higher so grass/cover reads as safer than a sidestep.
        -- Foe punches through your entrenched guard (DEF stripped for this hit).
        -- Stay in a real hide — mon stays tucked away (pic hidden).
        -- Random deep-cover lock: can't leave (tree / dive / boulder / …).
        -- Idle pulses while braced / hiding during the command menu.
        -- Spot-themed loops (grass → GROWTH, dig spots → DIG, water → SURF…).
        -- Entrench hold: locked stance until a counter opening (or max turns).


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
            local state = React.peek(battle)
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
            local state = battle and React.peek(battle)
            if not state or not state.keepDodgeMissAnim then
                return text, false
            end
            -- Counter already armed / firing — don't revive a stale dodge-whiff line.
            if state.sameTurnCounterQueued or state.sameTurnCounterStrike
                or state.dodgeWhiffDone then
                state.keepDodgeMissAnim = false
                state.dodgeMissName = nil
                state.dodgeMissSide = nil
                return text, false
            end
            local name = state.dodgeMissName or "POKéMON"
            local side = state.dodgeMissSide == "enemy" and "enemy" or "player"
            state.keepDodgeMissAnim = false
            state.dodgeMissName = nil
            state.dodgeMissSide = nil
            state.dodgeWhiffDone = true
            battle._arAccuracyMissSide = nil
            local line = pickFormatted(S.DODGE_WHIFF_CALLS, name)
                or ("But " .. name .. "\ndodged aside!")
            -- Signal wrapBattleSay to park COUNTER! after this miss line + anim.
            -- Side is who dodged (the miss target), not who attacked.
            return line, true, side
        end

        -- Drop orphaned dodge-miss lines that somehow landed after COUNTER!.
        local function scrubLateDodgeWhiff(battle)
            local state = battle and React.peek(battle)
            if state then
                state.keepDodgeMissAnim = false
                state.dodgeMissName = nil
                state.dodgeMissSide = nil
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

        -- Auto foe REACT once per turn when you attack (trainer battles).
        -- Same Focus costs as the player; pick is weighted (commit / dodge /
        -- brace / FIRE). Returns reactionText, buffList, trackTempBuffs,
        -- failNarrator, fieldCue. Failed dodge still spends Focus: trainer
        -- order bubble + "...but it was too slow!". FIRE spends their later call.
        local function foeFireWindow(battle, moveDef)
            local FoeAi = Battle and Battle.FoeAi
            if not (FoeAi and type(FoeAi.canFireNow) == "function") then
                return false, {}
            end
            local shots = {}
            if Fx and type(Fx.listFireNowMoves) == "function" then
                shots = Fx.listFireNowMoves(battle, battle.enemy) or {}
            end
            local field = FieldBattleViewer
                and type(FieldBattleViewer.isFieldBattle) == "function"
                and FieldBattleViewer.isFieldBattle(battle)
            local fireRange
            if field and type(FieldBattleViewer.fireRangeOpen) == "function" then
                fireRange = FieldBattleViewer.fireRangeOpen(battle)
            end
            local playerCharge = false
            if field and type(FieldBattleViewer.playerChargeWindowOpen) == "function" then
                playerCharge = FieldBattleViewer.playerChargeWindowOpen(battle) == true
            end
            local state = momentumState(battle)
            local incomingMelee = true
            if ReactiveDefense and type(ReactiveDefense.isSpecialClashIncoming) == "function" then
                incomingMelee = not ReactiveDefense.isSpecialClashIncoming(moveDef)
            end
            local can = FoeAi.canFireNow(battle, moveDef, {
                fieldBattle = field and true or false,
                fireRangeOpen = fireRange,
                playerChargeOpen = playerCharge,
                shotCount = #shots,
                alreadyActed = state.enemyActedThisTurn == true
                    or state.skipQueuedEnemyAction == true,
                statusLocked = enemyStatusLocked(battle),
                incomingMelee = incomingMelee,
            })
            return can, shots
        end

        local function foeChargeWindow(battle, moveDef)
            local FoeAi = Battle and Battle.FoeAi
            if not (FoeAi and type(FoeAi.canChargeNow) == "function") then
                return false, {}
            end
            local charges = {}
            if Fx and type(Fx.listCheckNowMoves) == "function" then
                charges = Fx.listCheckNowMoves(battle, battle.enemy) or {}
            end
            local field = FieldBattleViewer
                and type(FieldBattleViewer.isFieldBattle) == "function"
                and FieldBattleViewer.isFieldBattle(battle)
            local playerCharge = false
            if field and type(FieldBattleViewer.playerChargeWindowOpen) == "function" then
                playerCharge = FieldBattleViewer.playerChargeWindowOpen(battle) == true
            end
            local state = momentumState(battle)
            local incomingMelee = true
            if ReactiveDefense and type(ReactiveDefense.isPhysicalClashIncoming) == "function" then
                incomingMelee = ReactiveDefense.isPhysicalClashIncoming(moveDef)
            elseif ReactiveDefense and type(ReactiveDefense.isSpecialClashIncoming) == "function" then
                incomingMelee = not ReactiveDefense.isSpecialClashIncoming(moveDef)
            end
            local can = FoeAi.canChargeNow(battle, moveDef, {
                fieldBattle = field and true or false,
                playerChargeOpen = playerCharge,
                chargeCount = #charges,
                alreadyActed = state.enemyActedThisTurn == true
                    or state.skipQueuedEnemyAction == true,
                statusLocked = enemyStatusLocked(battle),
                incomingMelee = incomingMelee,
            })
            return can, charges
        end

        local function executeFoeFire(battle, moveDef, shots, foe, focusNow)
            local FoeAi = Battle and Battle.FoeAi
            local shot = FoeAi and type(FoeAi.pickFireShot) == "function"
                and FoeAi.pickFireShot(shots)
                or (shots and shots[1])
            if not shot then
                return nil
            end
            local ok = ReactiveDefense and ReactiveDefense.spend(battle, false, "fire")
            if not ok then
                return nil
            end
            local foeSide = ReactiveDefense and ReactiveDefense.sideState(battle, false)
            if foeSide then
                foeSide.reactedThisTurn = true
            end
            local state = momentumState(battle)
            state.skipQueuedEnemyAction = true
            state.enemyActedThisTurn = true
            local inst = shot.moveInst
            if inst and type(inst.pp) == "number" and inst.pp > 0 then
                inst.pp = inst.pp - 1
            end
            local reply = {
                id = shot.moveId,
                type = shot.moveType,
                power = (shot.moveDef and shot.moveDef.power) or shot.power,
                category = shot.checkNow and "physical"
                    or shot.hazeNow and (shot.category or "status")
                    or "special",
                moveId = shot.moveId,
                moveType = shot.moveType,
            }
            local cue = {
                side = "enemy",
                kind = (shot.checkNow and "attack") or "cast",
                category = reply.category,
                moveType = shot.moveType,
                moveId = shot.moveId,
            }
            local line = pickFoeTrainerLine(
                battle, S.TRAINER_FOE_FIRE_CALLS, S.FOE_FIRE_CALLS, foe)
            local clashIncoming = ReactiveDefense
                and type(ReactiveDefense.isSpecialClashIncoming) == "function"
                and ReactiveDefense.isSpecialClashIncoming(moveDef)
                and not shot.checkNow and not shot.hazeNow
            if clashIncoming then
                local verdict = ReactiveDefense.contestSpecialClash(
                    battle, moveDef, reply, { replySide = "enemy" })
                local rd = ReactiveDefense.state(battle)
                if verdict == "win" then
                    rd.hitMod = { side = "enemy", forceMiss = true }
                    battle._arFireShotMult = ReactiveDefense.CLASH_WIN_SHOT_MULT
                elseif verdict == "tie" then
                    rd.hitMod = { side = "enemy", forceMiss = true }
                else
                    rd.hitMod = {
                        side = "enemy",
                        damageMult = ReactiveDefense.CLASH_LOSE_MULT,
                    }
                end
                if FieldBattleViewer
                    and type(FieldBattleViewer.playBeamClash) == "function" then
                    FieldBattleViewer.playBeamClash(battle, { fireClash = verdict }, {
                        move = moveDef,
                        replyMove = reply,
                        replySide = "enemy",
                    })
                end
                if verdict == "win" and type(dev.fireQueuedSpecial) == "function" then
                    dev.fireQueuedSpecial(battle, inst, "enemy")
                end
                dev.log(battle, "FOE fire",
                    string.format("clash=%s focus=%d", tostring(verdict), focusNow))
                return line, nil, false, nil, cue
            end
            if shot.checkNow and type(dev.fireQueuedCheck) == "function" then
                if battle then
                    battle._arCheckNow = true
                end
                dev.fireQueuedCheck(battle, inst, "enemy")
            elseif type(dev.fireQueuedSpecial) == "function" then
                if shot.hazeNow then
                    battle._arHazeNow = true
                end
                dev.fireQueuedSpecial(battle, inst, "enemy")
            end
            if battle._arFireNowHit then
                if shot.hazeNow then
                    -- Lane stall; no 2-tile knockback.
                elseif FieldBattleViewer
                    and type(FieldBattleViewer.interruptCharge) == "function" then
                    FieldBattleViewer.interruptCharge(battle, "player",
                        shot.checkNow and 1 or 2)
                end
            elseif ReactiveDefense then
                ReactiveDefense.state(battle).hitMod = {
                    side = "enemy",
                    damageMult = ReactiveDefense.FIRE_CAST_MULT,
                }
            end
            dev.log(battle, "FOE fire",
                string.format("shot=%s hit=%s focus=%d",
                    tostring(shot.moveId or "?"),
                    battle._arFireNowHit and "Y" or "N",
                    focusNow))
            return line, nil, false, nil, cue
        end

        local function executeFoeCharge(battle, moveDef, charges, foe, focusNow)
            local FoeAi = Battle and Battle.FoeAi
            local shot = FoeAi and type(FoeAi.pickFireShot) == "function"
                and FoeAi.pickFireShot(charges)
                or (charges and charges[1])
            if not shot then
                return nil
            end
            local ok = ReactiveDefense and ReactiveDefense.spend(battle, false, "charge")
            if not ok then
                return nil
            end
            local foeSide = ReactiveDefense and ReactiveDefense.sideState(battle, false)
            if foeSide then
                foeSide.reactedThisTurn = true
            end
            local state = momentumState(battle)
            state.skipQueuedEnemyAction = true
            state.enemyActedThisTurn = true
            local inst = shot.moveInst
            if inst and type(inst.pp) == "number" and inst.pp > 0 then
                inst.pp = inst.pp - 1
            end
            local reply = {
                id = shot.moveId,
                type = shot.moveType,
                power = (shot.moveDef and shot.moveDef.power) or shot.power,
                category = "physical",
                moveId = shot.moveId,
                moveType = shot.moveType,
            }
            local verdict = "lose"
            if ReactiveDefense and type(ReactiveDefense.contestPhysicalClash) == "function" then
                verdict = ReactiveDefense.contestPhysicalClash(
                    battle, moveDef, reply, { replySide = "enemy" })
            end
            local boost = (ReactiveDefense and ReactiveDefense.CHARGE_BOOST) or 1.15
            if verdict == "win" then
                battle._arChargeShotMult = boost
            elseif ReactiveDefense then
                ReactiveDefense.state(battle).hitMod = {
                    side = "enemy",
                    damageMult = boost,
                }
            end
            if FieldBattleViewer
                and type(FieldBattleViewer.playChargeClash) == "function" then
                FieldBattleViewer.playChargeClash(battle, { chargeClash = verdict }, {
                    move = moveDef,
                    replyMove = reply,
                    replySide = "enemy",
                })
            end
            if type(dev.fireQueuedCharge) == "function" then
                dev.fireQueuedCharge(battle, inst, "enemy")
            end
            local cue = {
                side = "enemy",
                kind = "attack",
                category = "physical",
                moveType = shot.moveType,
                moveId = shot.moveId,
            }
            local line = pickFoeTrainerLine(
                battle, S.TRAINER_FOE_CHARGE_CALLS, S.FOE_CHARGE_CALLS, foe)
            dev.log(battle, "FOE charge",
                string.format("clash=%s focus=%d", tostring(verdict), focusNow))
            return line, nil, false, nil, cue
        end

        local function tryFoeCoverReaction(battle, moveDef)
            if React and type(React.isGuaranteedCounterHit) == "function"
                and React.isGuaranteedCounterHit(battle,
                    battle and battle.player, battle and battle.enemy) then
                return nil
            end
            if not trainerFoeReactionsOn(battle) or not moveDef then
                return nil
            end
            if (moveDef.power or 0) <= 0 or moveDef.category == "status" then
                return nil
            end
            if ReactiveDefense
                and (ReactiveDefense.isVanishHideTurn(battle.player, moveDef)
                    or ReactiveDefense.isVanished(battle.enemy)) then
                if FieldBattleViewer
                    and type(FieldBattleViewer.armStatusChip) == "function" then
                    pcall(FieldBattleViewer.armStatusChip, battle, "enemy", "PASS")
                end
                return nil
            end
            -- Frozen / asleep foes can't take dodge/brace/FIRE orders.
            if enemyStatusLocked(battle) then
                return nil
            end
            local state = momentumState(battle)
            if state.enemyReactedThisTurn then
                return nil
            end
            state.enemyReactedThisTurn = true
            local special = foeMoveIsSpecial(moveDef)
            local canFire, shots = foeFireWindow(battle, moveDef)
            local canCharge, charges = foeChargeWindow(battle, moveDef)
            local action = "commit"
            if ReactiveDefense and type(ReactiveDefense.pickFoeReact) == "function" then
                action = ReactiveDefense.pickFoeReact(
                    battle, moveDef, special, {
                        canFireNow = canFire,
                        canChargeNow = canCharge,
                    }) or "commit"
            end
            local foeSide = ReactiveDefense and ReactiveDefense.sideState(battle, false)
            local focusNow = foeSide and tonumber(foeSide.focus) or 0
            if action == "fire" then
                return executeFoeFire(battle, moveDef, shots, enemyMonName(battle), focusNow)
            end
            if action == "charge" then
                return executeFoeCharge(battle, moveDef, charges, enemyMonName(battle), focusNow)
            end
            if action ~= "dodge" and action ~= "brace" then
                dev.log(battle, "FOE react",
                    string.format("commit focus=%d", focusNow))
                return nil
            end
            if ReactiveDefense then
                local ok = ReactiveDefense.spend(battle, false, action)
                if not ok then
                    dev.log(battle, "FOE react",
                        string.format("broke %s focus=%d", action, focusNow))
                    return nil
                end
                if foeSide then
                    foeSide.reactedThisTurn = true
                end
                focusNow = tonumber(foeSide and foeSide.focus) or focusNow
            end
            local foe = enemyMonName(battle)
            if action == "dodge" then
                local line = pickFoeTrainerLine(
                    battle, S.TRAINER_FOE_DODGE_CALLS, S.FOE_DODGE_CALLS, foe)
                local chance = 0.65
                if ReactiveDefense and type(ReactiveDefense.dodgeSuccessChance) == "function" then
                    chance = ReactiveDefense.dodgeSuccessChance(
                        battle.enemy, battle.player, battle)
                end
                local r = (love and love.math and love.math.random) or math.random
                if r() > chance then
                    dev.log(battle, "FOE dodge",
                        string.format("FAIL p=%.2f focus=%d", chance, focusNow))
                    if line then
                        return line, nil, false, S.DODGE_TOO_SLOW
                    end
                    return S.DODGE_TOO_SLOW, nil, false, nil
                end
                state.enemyTemp.cover = true
                dev.log(battle, "FOE dodge",
                    string.format("OK EV+1 p=%.2f focus=%d", chance, focusNow))
                return line, {
                    { who = "enemy", stat = "evasion", delta = 1 },
                }, true, nil
            end
            -- Brace is a guard, not a hide — don't mark dodge cover.
            local line = pickFoeTrainerLine(
                battle, S.TRAINER_FOE_BRACE_CALLS, S.FOE_BRACE_CALLS, foe)
            dev.log(battle, "FOE brace",
                string.format("OK DF+1 focus=%d", focusNow))
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
        -- Trainer slides on-screen while their banter line plays.
        -- Speech bubbles: slower glyphs; after typing they wait for A/B (no auto).
        -- Effective frames/glyph while a bubble is up (engine slow is 5).
        -- FIELD: short hold after each condensed toast, skipped by A.

        local function fieldFlowsText(battle)
            return type(battle) == "table"
                and FieldBattleViewer
                and type(FieldBattleViewer.isFieldBattle) == "function"
                and FieldBattleViewer.isFieldBattle(battle)
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

        local function pushPlayerCallout(battle, text, opts)
            if not fieldFlowsText(battle) then
                return false
            end
            text = tostring(text or ""):match("^%s*(.-)%s*$") or ""
            if text == "" then
                return false
            end
            local Callouts = FieldBattleViewer and FieldBattleViewer.Callouts
            local session = liveFieldSession(battle)
            if not (Callouts and session and type(Callouts.push) == "function") then
                return false
            end
            -- One strip at a time. A REACT shout on top of the live foe
            -- order is the rewrite flicker (Brock's line → "Dodge it!").
            -- Pretend success so the shout is not also queued as engine text.
            opts = type(opts) == "table" and opts or {}
            if opts.kind == "react" then
                local foeQ = session._trainerCallouts and session._trainerCallouts.foe
                if foeQ and foeQ[1] then
                    return true
                end
            end
            return Callouts.push(session, "player", text, opts) == true
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
        tagFieldCue = function(item, side, kind, category, moveType, moveId)
            if Fx then
                return Fx.tag(item, side, kind, category, moveType, moveId)
            end
            return false
        end

        tagLatestQueueFieldCue = function(battle, side, kind, category, moveType, moveId)
            if Fx then
                return Fx.tagLatest(battle, side, kind, category, moveType, moveId)
            end
            return false
        end

        fieldCueForFoeCover = function(foeBuffs, foeLine, extra)
            if Fx then
                return Fx.foeCoverCue(foeBuffs, foeLine, extra)
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
                tagFieldCue(item, fieldCue.side, fieldCue.kind, fieldCue.category,
                    fieldCue.moveType, fieldCue.moveId)
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
                    or kind == "brace" or kind == "cast") then
                if foeOrder and attachOverlapReact(battle, {
                        side = fieldCue.side,
                        kind = kind,
                        text = text,
                        bubble = bubble,
                        category = fieldCue.category,
                        moveType = fieldCue.moveType,
                        moveId = fieldCue.moveId,
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

        maybeEnqueueSendBanter = function(battle, originalText)
            return Battle.Dialogue.maybeEnqueueSendBanter(battle, originalText)
        end

        local BanterCameo = (Battle and Battle.Dialogue and Battle.Dialogue.Banter) or {
            start = function() end,
            tick = function() end,
            draw = function() end,
        }

        local function flushPendingSendBanter(battle)
            return Battle.Dialogue.flushPendingSendBanter(battle)
        end

        maybeEnqueueIdleBanter = function(battle)
            return Battle.Dialogue.maybeEnqueueIdleBanter(battle)
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
            local state = battle and React.peek(battle)
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
        local function resetBattleCamera(battle)
            clearAmbientStance(battle)
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
            -- Send-out / hide-pic use *_ANIM ids. Emitting those as
            -- battle.move_used (stub { id = "POOF_ANIM" }) crashes other
            -- mods that index move.effect (stronger_trainers smart_ai).
            do
                local id = tostring(moveId):upper()
                if id:find("_ANIM$", 1) then
                    return
                end
                local moves = battle.data and battle.data.moves
                if type(moves) == "table" and not moves[id] and not moves[moveId] then
                    return
                end
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
        -- Melee: extra swing of the same move. Special: a new CALL from the pool.
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

            local offerCall = fieldFlowsText(battle)
            if offerCall then
                if FieldBattleViewer and type(FieldBattleViewer.againOffersCall) == "function" then
                    offerCall = FieldBattleViewer.againOffersCall({
                        category = move.category,
                        moveId = move.id or move.moveId,
                        moveType = move.type or move.moveType,
                    }) == true
                else
                    offerCall = tostring(move.category or ""):lower() == "special"
                end
            end
            local hasPool = false
            do
                local moves = user.curMoves
                if type(moves) == "table" then
                    for i = 1, #moves do
                        local mv = moves[i]
                        if mv and not mv.struggle and (mv.pp == nil or mv.pp > 0) then
                            hasPool = true
                            break
                        end
                    end
                end
            end

            state.againInProgress = true
            if offerCall and not foeSide and hasPool then
                dev.log(battle, "AGAIN!", "you call")
                battle._arAwaitAgain = true
                battle._arAwaitAgainSide = "player"
                if FieldBattleViewer and type(FieldBattleViewer.beginAgainHold) == "function" then
                    FieldBattleViewer.beginAgainHold(battle)
                end
                local callLine = pickFormatted(S.AGAIN_CALLS, monName or playerMonName(battle))
                    or ((monName or "POKéMON") .. "!\nAgain!")
                enqueueAutoAfter(battle, callLine, S.CALLOUT_AUTO_DELAY, "player")
                battle.nextInsert = (battle.nextInsert or 0) + 1
                table.insert(battle.queue, battle.nextInsert, {
                    arFx = true,
                    fn = function()
                        if not battle._arAwaitAgain then
                            return
                        end
                        battle._arAwaitCallout = true
                        battle.phase = "moveSelect"
                        battle._arFieldPreferMoves = true
                        battle._arFieldCommandHold = nil
                        local moves = battle.player and battle.player.curMoves
                        local n = moves and #moves or 1
                        battle.moveIndex = math.min(battle.moveIndex or 1, n)
                        battle.moveSwapIndex = nil
                        dev.log(battle, "AGAIN call", "special attacker picks the follow-up")
                    end,
                })
                return true
            end

            local followInst = nil
            if offerCall and foeSide and Fx and type(Fx.pickAgainCallMove) == "function" then
                followInst = Fx.pickAgainCallMove(battle, user, move)
            end
            if followInst and type(followInst) == "table"
                and tostring(followInst.id or ""):upper() ~= mid
                and type(battle.performMove) == "function" then
                dev.log(battle, "AGAIN!", "foe call")
                local line = pickFoeTrainerLine(
                    battle, S.TRAINER_FOE_AGAIN_CALLS, S.FOE_AGAIN_CALLS, monName or enemyMonName(battle))
                enqueueAutoAfter(battle, line, S.CALLOUT_AUTO_DELAY, "foe")
                battle._arAgainCalled = true
                local ok = pcall(battle.performMove, battle, user, target, followInst, true)
                battle._arAgainCalled = nil
                state.againInProgress = false
                return ok and true or false
            end

            dev.log(battle, "AGAIN!", foeSide and "foe" or "you")
            local line
            if foeSide then
                line = pickFoeTrainerLine(
                    battle, S.TRAINER_FOE_AGAIN_CALLS, S.FOE_AGAIN_CALLS, monName or enemyMonName(battle))
            else
                line = pickFormatted(S.AGAIN_CALLS, monName or playerMonName(battle))
                    or ((monName or "POKéMON") .. "!\nAgain!")
            end
            enqueueAutoAfter(battle, line, S.CALLOUT_AUTO_DELAY, foeSide and "foe" or "player")
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

        local function pickHideMoveAnim(battle, candidates)
            return Fx.pickHideMoveAnim(battle, candidates)
        end

        local function dodgeAnimSpec(choice, battle)
            return Fx.dodgeAnimSpec(choice, battle)
        end

        enqueueDodgeHideAnim = function(battle, choice)
            return Fx.enqueueDodgeHideAnim(battle, choice)
        end

        enqueueBraceAnim = function(battle, opts)
            return Fx.enqueueBraceAnim(battle, opts)
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
            local state = React.peek(battle)
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
        -- FIELD fights use field arena slots; DS arena uses stamped voxels.
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
            local state = React.peek(battle)
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

        -- BATTLE STAGE preference (AUTO / FIELD).
        dev.battleStage = function()
            return battleStage()
        end

        dev.installFieldFightSpriteHook = function()
            if FieldBattleViewer and type(FieldBattleViewer.install) == "function" then
                pcall(FieldBattleViewer.install, mod)
            end
        end

        -- Play dodge / cover / brace / entrench FX for Focus reacts.
        dev.playFocusReactFx = function(battle, action, result)
            if Fx then
                return Fx.play(battle, action, result)
            end
        end

        -- Fire a special during a close-gap charge (FIRE NOW).
        -- Uses the picked special. Never the awaitIncoming placeholder.
        -- `side` is "player" (default) or "enemy".
        dev.fireQueuedSpecial = function(battle, moveInst, side)
            if not (battle and battle.player and battle.enemy) then
                return false
            end
            side = side or "player"
            local isPlayer = side ~= "enemy"
            local user = isPlayer and battle.player or battle.enemy
            local target = isPlayer and battle.enemy or battle.player
            local state = React.peek(battle)
            local action = moveInst or (state and state.fireNowMove)
            if state then
                state.fireNowMove = nil
                if isPlayer then
                    state.skipQueuedPlayerAction = true
                    state.playerActedThisTurn = true
                else
                    state.skipQueuedEnemyAction = true
                    state.enemyActedThisTurn = true
                end
            end
            if isPlayer then
                battle._arAwaitCallout = nil
            end
            if type(action) == "table" and action.special then
                action = nil
            end
            if type(action) ~= "table" or not (action.id or action.name) then
                return false
            end
            if type(battle.performMove) ~= "function" then
                return false
            end
            -- The shot is the react. Do not open REACT on this performMove
            -- (foe FIRE used to land as a new incoming and reopen the HUD).
            if React and type(React.lockHud) == "function" then
                React.lockHud(battle)
            else
                battle._arReactLocked = true
            end
            battle._arFireNow = true
            battle._arFireNowHit = nil
            battle._arFireCarryThrough = nil
            battle._arFireNowCharger = isPlayer and "enemy" or "player"
            if not battle._arCheckNow and not battle._arFireShotMult
                and ReactiveDefense then
                local mult = tonumber(ReactiveDefense.REACT_SPECIAL_MULT)
                if mult and mult > 0 and mult ~= 1 then
                    battle._arReactSpecialMult = mult
                end
            end
            local ok, err = pcall(battle.performMove, battle, user, target, action)
            battle._arFireNow = nil
            battle._arCheckNow = nil
            battle._arHazeNow = nil
            if not ok then
                dev.log(battle, "ERR FIRE now", tostring(err))
                return false
            end
            return true
        end

        -- Contact CHECK during a close-gap: in-place melee, 1-tile interrupt.
        dev.fireQueuedCheck = function(battle, moveInst, side)
            if battle then
                battle._arCheckNow = true
            end
            return dev.fireQueuedSpecial(battle, moveInst, side)
        end

        -- Physical CHARGE: close the gap and crash. Not a CHECK interrupt.
        dev.fireQueuedCharge = function(battle, moveInst, side)
            if not (battle and battle.player and battle.enemy) then
                return false
            end
            side = side or "player"
            local isPlayer = side ~= "enemy"
            local user = isPlayer and battle.player or battle.enemy
            local target = isPlayer and battle.enemy or battle.player
            local state = React.peek(battle)
            local action = moveInst or (state and state.chargeNowMove)
            if state then
                state.chargeNowMove = nil
                if isPlayer then
                    state.skipQueuedPlayerAction = true
                    state.playerActedThisTurn = true
                else
                    state.skipQueuedEnemyAction = true
                    state.enemyActedThisTurn = true
                end
            end
            if isPlayer then
                battle._arAwaitCallout = nil
            end
            if type(action) == "table" and action.special then
                action = nil
            end
            if type(action) ~= "table" or not (action.id or action.name) then
                return false
            end
            if type(battle.performMove) ~= "function" then
                return false
            end
            if React and type(React.lockHud) == "function" then
                React.lockHud(battle)
            else
                battle._arReactLocked = true
            end
            battle._arNoCounterThisTurn = true
            battle._arChargeNow = true
            local ok, err = pcall(battle.performMove, battle, user, target, action)
            battle._arChargeNow = nil
            if not ok then
                dev.log(battle, "ERR CHARGE now", tostring(err))
                return false
            end
            return true
        end

        -- Idle HARDEN / GROWTH / DIG pulses while braced or hiding in the menu.
        -- Drives animPlayer + picFx without stealing the FIGHT / STRIKE menus.
        clearAmbientStance = function(battle)
            local state = battle and React.peek(battle)
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
            local state = React.peek(battle)
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
            local state = battle and React.peek(battle)
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

        -- REACT pick / damage deferral lives in battle/rules/react.lua.
        clearCalloutPickState = function(battle)
            if React then
                React.clearPick(battle)
            end
        end

        resolvePendingDamage = function(battle)
            if React then
                React.resolvePending(battle)
            end
        end

        maybeQueueSameTurnCounter = function(battle)
            if React then
                React.maybeQueueSameTurnCounter(battle)
            end
        end

        local function newCalloutPickModal(game, opts)
            if React then
                return React.newPickModal(game, opts)
            end
        end

        local function shouldOfferCalloutPick(battle, move)
            return React and React.shouldOffer(battle, move)
        end

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
            local state = React.peek(battle)
            local t = state and state.temp
            return t and t.hidAway and (t.cover or t.picHidden)
        end

        playerInDeepCover = function(battle)
            local state = battle and React.peek(battle)
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
                return nil
            end
            -- Leaving cover to strike first is riskier.
            if goingFirst then
                silentStageDelta(player, "defense", -1)
            end
            -- If COUNTER/HOLD is about to open, skip the leave-cover shout so the
            -- two don't stack into one confusing beat.
            if playerHasCounter(battle) then
                return true
            end
            local line = pickFormatted(S.LEAVE_COVER_CALLS, monName)
                or (monName .. "!\nComing out!")
            enqueueAutoAfter(battle, line, nil, "player")
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
                return nil
            end
            local line = pickFoeTrainerLine(
                battle,
                S.TRAINER_FOE_LEAVE_COVER_CALLS,
                S.FOE_LEAVE_COVER_CALLS,
                monName or enemyMonName(battle))
            enqueueNpcFlavor(battle, line, S.CALLOUT_AUTO_DELAY)
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
                -- Faint owns the exit. Do not queue "Finish it!" behind it.
                local foe = battle.enemy and battle.enemy.mon
                if foe and (foe.hp or 0) > 0 then
                    return pickFormatted(S.PLAYER_FINISH_CALLS, bare, moveName)
                        or ("Finish it!\n" .. bare .. "!"), nil, false,
                        { side = "player", kind = "attack" }
                end
            end
            return nil
        end

        local BattleState = require("src.battle.BattleState")
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
        -- Speech-bubble paint lives in battle/chrome/bubbles.lua (Dialogue.Bubbles).
        hud.wrapBubbleText = function() return {} end
        hud.fieldPopupText = function(text) return tostring(text or "") end
        hud.bubbleVisibleText = function() return "" end
        hud.drawSpeechBubble = function() end
        hud.bubbleSideActive = function() return nil end
        hud.bubblesOwnDialogue = function() return false end
        hud.stackedPromptActive = function() return false end
        hud.runDrawInvisible = function(fn, self, ...)
            if type(fn) == "function" then
                return fn(self, ...)
            end
        end
        if Battle and Battle.Dialogue then
            Battle.Dialogue.bind({
                opt = opt,
                S = S,
                React = React,
                FieldBattleViewer = FieldBattleViewer,
                momentumState = momentumState,
                trainerFoeReactionsOn = trainerFoeReactionsOn,
                liveFieldSession = liveFieldSession,
                inferBubbleSide = inferBubbleSide,
                parseUsedMoveText = parseUsedMoveText,
                stripEnemyPrefix = stripEnemyPrefix,
                fieldCompactActive = hud.fieldCompactActive,
                enemyStatusLocked = enemyStatusLocked,
                playerStatusLocked = playerStatusLocked,
                playerHasCounter = playerHasCounter,
                formatAutoCounterCall = formatAutoCounterCall,
                personalTrainerName = personalTrainerName,
                calloutStyle = calloutStyle,
                battleScene = battleScene,
                playerTypeSet = playerTypeSet,
                playerMonName = playerMonName,
                enemyMonName = enemyMonName,
                pushNpcCallout = pushNpcCallout,
                markBubbleWait = markBubbleWait,
                queueHasPoof = queueHasPoof,
            })
            if Battle.Dialogue.Bubbles then
                hud.wrapBubbleText = Battle.Dialogue.Bubbles.wrapText
                hud.fieldPopupText = Battle.Dialogue.Bubbles.fieldPopupText
                hud.bubbleVisibleText = Battle.Dialogue.Bubbles.visibleText
                hud.drawSpeechBubble = Battle.Dialogue.Bubbles.draw
                hud.bubbleSideActive = Battle.Dialogue.Bubbles.sideActive
                hud.bubblesOwnDialogue = Battle.Dialogue.Bubbles.ownDialogue
                hud.stackedPromptActive = Battle.Dialogue.Bubbles.stackedPromptActive
                hud.runDrawInvisible = Battle.Dialogue.Bubbles.runDrawInvisible
            end
        end

        mod.hooks:wrap("battle.bottom_ui_visible", function(next, who)
            -- Keep the classic dialogue slab hidden on FIELD / bubble mode, but
            -- allow stacked learn-move / YES-NO TextBoxes to paint (UIVisibility
            -- asks the enclosing battle before drawing those overlays). AUTO
            -- used to miss this exception, so the prompt text was invisible.
            if hud.stackedPromptActive(who) then
                return true
            end
            if hud.fieldCompactActive(who) then
                return false
            end
            -- Hide the classic text box for all battle dialogue; bubbles carry it.
            -- Keep the box for FIGHT / move menus (non-messages phases).
            if hud.bubblesOwnDialogue(who) then
                return false
            end
            return next(who)
        end)


        -- Bind presentation callbacks and wrap EffectRegistry once helpers exist.
        if Fx then
            Fx.bind({
                opt = opt,
                RD = ReactiveDefense,
                isFieldBattle = function(battle)
                    return FieldBattleViewer
                        and type(FieldBattleViewer.isFieldBattle) == "function"
                        and FieldBattleViewer.isFieldBattle(battle)
                end,
                fieldReact = function(battle, side, kind, opts)
                    if FieldBattleViewer and type(FieldBattleViewer.react) == "function" then
                        return FieldBattleViewer.react(battle, side, kind, opts)
                    end
                end,
                momentumState = momentumState,
                insertBeforeAnim = insertBeforeAnim,
                playerTypeSet = playerTypeSet,
                log = function(battle, ...)
                    return dev.log(battle, ...)
                end,
                rememberCoverSpot = rememberCoverSpot,
                pickFocusCoverLabel = function(battle)
                    if type(dev.pickFocusCoverLabel) == "function" then
                        return dev.pickFocusCoverLabel(battle)
                    end
                end,
                pickCoverHideSpot = function(battle)
                    if type(dev.pickCoverHideSpot) == "function" then
                        return dev.pickCoverHideSpot(battle)
                    end
                end,
                applyCoverTuckVisual = function(battle)
                    if type(dev.applyCoverTuckVisual) == "function" then
                        return dev.applyCoverTuckVisual(battle)
                    end
                end,
                isDodgeFailNarrator = isDodgeFailNarrator,
                isRangedCounter = function(battle, opts)
                    if FieldBattleViewer and type(FieldBattleViewer.isRangedCounter) == "function" then
                        return FieldBattleViewer.isRangedCounter(opts)
                    end
                end,
                isFireNowShot = function(battle, opts)
                    if FieldBattleViewer and type(FieldBattleViewer.isFireNowShot) == "function" then
                        return FieldBattleViewer.isFireNowShot(opts)
                    end
                end,
            })
        end
        if React then
            React.bind({
                RD = ReactiveDefense,
                opt = opt,
                S = S,
                runDamaging = origRunDamaging,
                log = function(battle, ...)
                    return dev.log(battle, ...)
                end,
                playFocusReactFx = function(battle, action, result)
                    if type(dev.playFocusReactFx) == "function" then
                        return dev.playFocusReactFx(battle, action, result)
                    end
                end,
                pickMode = calloutPickMode,
                reactHudStyle = reactHudStyle,
                calloutStyle = calloutStyle,
                lowHpRatio = lowHpRatio,
                foeMoveIsSpecial = foeMoveIsSpecial,
                playerStatusLocked = playerStatusLocked,
                playerHasCounter = playerHasCounter,
                playerInDeepCover = playerInDeepCover,
                playerHoldingHide = playerHoldingHide,
                playerMonName = playerMonName,
                enemyMonName = enemyMonName,
                trainerFoeReactionsOn = trainerFoeReactionsOn,
                rollEnemyAgain = rollEnemyAgain,
                pickCallEntry = pickCallEntry,
                findMoveByName = findMoveByName,
                insertBeforeAnim = insertBeforeAnim,
                insertAfterMissAnim = insertAfterMissAnim,
                indexOfMoveAnim = indexOfMoveAnim,
                resumeInsertIndex = resumeInsertIndex,
                enqueueAutoAfter = enqueueAutoAfter,
                markBubbleWait = markBubbleWait,
                pushPlayerCallout = pushPlayerCallout,
                pushNotice = function(battle, text, opts)
                    local Notices = Battle and Battle.Notices
                    if Notices and type(Notices.push) == "function" then
                        return Notices.push(battle, text, opts)
                    end
                end,
                armFieldChip = function(battle, side, text)
                    if FieldBattleViewer
                        and type(FieldBattleViewer.armStatusChip) == "function" then
                        return FieldBattleViewer.armStatusChip(battle, side, text)
                    end
                end,
                isFieldBattle = function(battle)
                    return FieldBattleViewer
                        and type(FieldBattleViewer.isFieldBattle) == "function"
                        and FieldBattleViewer.isFieldBattle(battle)
                end,
                fieldReact = function(battle, side, kind, opts)
                    if FieldBattleViewer and type(FieldBattleViewer.react) == "function" then
                        return FieldBattleViewer.react(battle, side, kind, opts)
                    end
                end,
                tagFieldCue = tagFieldCue,
                pickCounterStrikeMove = function(battle, kind, battler, incoming)
                    if Fx and type(Fx.pickCounterStrikeMove) == "function" then
                        return Fx.pickCounterStrikeMove(battle, kind, battler, incoming)
                    end
                end,
                listFireNowMoves = function(battle, battler)
                    if Fx and type(Fx.listFireNowMoves) == "function" then
                        return Fx.listFireNowMoves(battle, battler)
                    end
                end,
                listCheckNowMoves = function(battle, battler)
                    if Fx and type(Fx.listCheckNowMoves) == "function" then
                        return Fx.listCheckNowMoves(battle, battler)
                    end
                end,
                listCloudNowMoves = function(battle, battler)
                    if Fx and type(Fx.listCloudNowMoves) == "function" then
                        return Fx.listCloudNowMoves(battle, battler)
                    end
                end,
                queueMoveAttackAnim = queueMoveAttackAnim,
                applyCalloutBuffs = applyCalloutBuffs,
                enqueueBraceAnim = enqueueBraceAnim,
                signalAttackPresentation = signalAttackPresentation,
                beginReactHold = function(battle)
                    if FieldBattleViewer and type(FieldBattleViewer.beginReactHold) == "function" then
                        return FieldBattleViewer.beginReactHold(battle)
                    end
                end,
                releaseReactHold = function(battle, outcome)
                    if FieldBattleViewer and type(FieldBattleViewer.releaseReactHold) == "function" then
                        return FieldBattleViewer.releaseReactHold(battle, outcome)
                    end
                end,
                isRangedCounter = function(battle, opts)
                    if FieldBattleViewer and type(FieldBattleViewer.isRangedCounter) == "function" then
                        return FieldBattleViewer.isRangedCounter(opts)
                    end
                end,
                isFireNowShot = function(battle, opts)
                    if FieldBattleViewer and type(FieldBattleViewer.isFireNowShot) == "function" then
                        return FieldBattleViewer.isFireNowShot(opts)
                    end
                end,
                isMeleeAttack = function(battle, opts)
                    if FieldBattleViewer and type(FieldBattleViewer.isMeleeAttack) == "function" then
                        return FieldBattleViewer.isMeleeAttack(opts)
                    end
                end,
                closeGapPending = function(battle, side)
                    if FieldBattleViewer and type(FieldBattleViewer.closeGapPending) == "function" then
                        return FieldBattleViewer.closeGapPending(battle, side)
                    end
                end,
                chargeWindowOpen = function(battle)
                    if FieldBattleViewer and type(FieldBattleViewer.chargeWindowOpen) == "function" then
                        return FieldBattleViewer.chargeWindowOpen(battle)
                    end
                end,
                fireRangeOpen = function(battle)
                    if FieldBattleViewer and type(FieldBattleViewer.fireRangeOpen) == "function" then
                        return FieldBattleViewer.fireRangeOpen(battle)
                    end
                end,
                fireQueuedSpecial = function(battle, moveInst, side)
                    if type(dev.fireQueuedSpecial) == "function" then
                        return dev.fireQueuedSpecial(battle, moveInst, side)
                    end
                end,
                fireQueuedCheck = function(battle, moveInst, side)
                    if type(dev.fireQueuedCheck) == "function" then
                        return dev.fireQueuedCheck(battle, moveInst, side)
                    end
                end,
                playBeamClash = function(battle, result, ctx)
                    if FieldBattleViewer and type(FieldBattleViewer.playBeamClash) == "function" then
                        return FieldBattleViewer.playBeamClash(battle, result, ctx)
                    end
                end,
                playChargeClash = function(battle, result, ctx)
                    if FieldBattleViewer and type(FieldBattleViewer.playChargeClash) == "function" then
                        return FieldBattleViewer.playChargeClash(battle, result, ctx)
                    end
                end,
                fireQueuedCharge = function(battle, moveInst, side)
                    if type(dev.fireQueuedCharge) == "function" then
                        return dev.fireQueuedCharge(battle, moveInst, side)
                    end
                end,
                cancelCloseStrike = function(battle, side)
                    if FieldBattleViewer and type(FieldBattleViewer.cancelCloseStrike) == "function" then
                        return FieldBattleViewer.cancelCloseStrike(battle, side)
                    end
                end,
                interruptCharge = function(battle, side, tiles)
                    if FieldBattleViewer and type(FieldBattleViewer.interruptCharge) == "function" then
                        return FieldBattleViewer.interruptCharge(battle, side, tiles)
                    end
                end,
                deferCancelCloseStrike = function(battle, side, delay)
                    if FieldBattleViewer and type(FieldBattleViewer.deferCancelCloseStrike) == "function" then
                        return FieldBattleViewer.deferCancelCloseStrike(battle, side, delay)
                    end
                end,
                tryAgainStrike = tryAgainStrike,
                resolvePlayerCounterAttempt = resolvePlayerCounterAttempt,
                tryFoeCoverReaction = tryFoeCoverReaction,
                enqueueReactWithAttack = enqueueReactWithAttack,
                enqueueNpcFlavor = enqueueNpcFlavor,
                fieldCueForFoeCover = fieldCueForFoeCover,
                isDodgeFailNarrator = isDodgeFailNarrator,
                resetBattleCamera = resetBattleCamera,
                scrubLateDodgeWhiff = scrubLateDodgeWhiff,
            })
            pcall(React.install, mod)
        end
        if Battle and Battle.Emotions and type(Battle.Emotions.bind) == "function" then
            Battle.Emotions.bind({
                lowHpRatio = lowHpRatio,
                facesOn = function()
                    return mod.options:get("battle_faces") ~= false
                end,
            })
            pcall(Battle.Emotions.install, mod)
        end
        if Battle and Battle.Portraits and type(Battle.Portraits.bind) == "function" then
            Battle.Portraits.bind({
                Emotions = Battle.Emotions,
                mod = mod,
                facesOn = function()
                    return mod.options:get("battle_faces") ~= false
                end,
            })
        end

        mod.hooks:wrap("battle.overlay", function(next, battle)
            if hud.fieldCompactActive(battle) then
                -- FIELD chrome is FBV.drawFrame (hooks_draw). Do not paint
                -- classic / gen3 / bubbles on top of it.
                return
            end
            next(battle)
            local stackedPrompt = hud.stackedPromptActive(battle)
            BanterCameo.draw(battle)
            local side = (not stackedPrompt) and hud.bubbleSideActive(battle) or nil
            if side then
                hud.drawSpeechBubble(battle, side)
            end
            if Battle and Battle.Notices and type(Battle.Notices.draw) == "function" then
                Battle.Notices.draw(battle)
            end
            if Battle and Battle.Portraits and type(Battle.Portraits.draw) == "function" then
                Battle.Portraits.draw(battle)
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
                        -- FIELD toasts auto-cycle. A skips the hold; B pauses.
                        if fieldFlowsText(self) then
                            self._arBubbleAcc = 0
                            if self.phase ~= "messages" then
                                self._arFieldToastPaused = nil
                            else
                                local input = self.game and self.game.input
                                local pressedA = false
                                if input and type(input.wasPressed) == "function" then
                                    pressedA = input:wasPressed("a") == true
                                    if input:wasPressed("b") then
                                        self._arFieldToastPaused = not self._arFieldToastPaused
                                    elseif self._arFieldToastPaused and pressedA then
                                        self._arFieldToastPaused = false
                                    end
                                end
                                if curItem and curItem._arOverlapShown then
                                    -- Already played as an overlay during the attack.
                                    curItem.auto = true
                                    curItem.autoDelay = 0
                                elseif pressedA and curItem and not self._arFieldToastPaused then
                                    -- Do not restamp the 1s hold; let origUpdateQueue
                                    -- dismiss this line on the same click.
                                    curItem.auto = true
                                    curItem.autoDelay = 0
                                elseif self._arFieldToastPaused and curItem then
                                    curItem.auto = nil
                                    curItem.autoDelay = nil
                                elseif curItem and curItem.text and curItem.auto ~= false
                                    and curItem.autoDelay == nil then
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
                local state = React.peek(battle)
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

            local function isFieldFight(battle)
                return FieldBattleViewer
                    and type(FieldBattleViewer.isFieldBattle) == "function"
                    and FieldBattleViewer.isFieldBattle(battle)
            end

            local origChooseMenu = BattleState.chooseMenu
            if type(origChooseMenu) == "function" then
                function BattleState.chooseMenu(self, choice)
                    -- Going second: FIGHT means stand in. Call the move after REACT.
                    if choice == "fight" and isFieldFight(self)
                        and not self.safari and not self.demo and not self.ghost
                        and React and type(React.playerLikelyGoesSecond) == "function"
                        and React.playerLikelyGoesSecond(self)
                        and not playerStatusLocked(self)
                        and not playerIsEntrenched(self)
                        and not playerInFocusCover(self)
                        and not playerCanStay(self)
                        and type(self.fightLockedAction) == "function"
                        and not self:fightLockedAction(self.player)
                        and type(self.playerHasPP) == "function"
                        and self:playerHasPP() then
                        local wait = React.awaitIncomingAction
                            and React.awaitIncomingAction()
                            or { special = "awaitIncoming" }
                        self._arQueuedPlayerAction = wait
                        local state = React.peek(self)
                        if state then
                            state.queuedPlayerAction = wait
                        end
                        dev.log(self, "AWAIT incoming", "slower side holds the call")
                        self:resolveTurn(wait)
                        return true
                    end
                    return origChooseMenu(self, choice)
                end
            end

            local origChooseMove = BattleState.chooseMove
            if type(origChooseMove) == "function" then
                function BattleState.chooseMove(self, index)
                    if self._arAwaitCallout then
                        if self.phase ~= "moveSelect" then
                            return nil, "move menu is not active"
                        end
                        local moves = self.player and self.player.curMoves
                        local move = moves and moves[index]
                        if not move then
                            return nil, "invalid move slot"
                        end
                        self.moveIndex = index
                        if self.player.disabledSlot == index then
                            if type(self.say) == "function" then
                                self:say(self:romText("_MoveDisabledText",
                                    "The move is\ndisabled!"))
                            end
                            self.phase = "moveSelect"
                            return true
                        end
                        if (move.pp or 0) <= 0 then
                            if type(self.say) == "function" then
                                self:say(self:romText("_MoveNoPPText",
                                    "No PP left for\nthis move!"))
                            end
                            self.phase = "moveSelect"
                            return true
                        end
                        local again = self._arAwaitAgain == true
                        self._arAwaitCallout = nil
                        self._arAwaitAgain = nil
                        self._arAwaitAgainSide = nil
                        if again then
                            self._arAgainCalled = true
                            local state = React.peek(self)
                            if state then
                                state.againInProgress = false
                            end
                            if FieldBattleViewer
                                and type(FieldBattleViewer.releaseAgainHold) == "function" then
                                FieldBattleViewer.releaseAgainHold(self, "call")
                            end
                            dev.log(self, "AGAIN pick",
                                tostring(move.id or move.name or index))
                        end
                        self.playerMoveListIndex = index
                        self.phase = "messages"
                        self.nextInsert = 0
                        self:executeAction(self.player, self.enemy, move)
                        return true
                    end
                    return origChooseMove(self, index)
                end
            end

            local origResolveTurn = BattleState.resolveTurn
            if type(origResolveTurn) == "function" then
                function BattleState.resolveTurn(self, action)
                    -- turn_started does not carry the locked move; stash it here
                    -- so FIRE NOW can switch off Tackle / onto Water Gun.
                    self._arQueuedPlayerAction = action
                    local state = React.peek(self)
                    if state then
                        state.queuedPlayerAction = action
                    end
                    return origResolveTurn(self, action)
                end
            end

            local origExecuteAction = BattleState.executeAction
            if type(origExecuteAction) == "function" then
                function BattleState.executeAction(self, user, target, action)
                    -- Locked in a trench with no opening: can't swing — convert to STAY.
                    -- Exception: a real move pick is an intentional BREAK + attack
                    -- (FIELD PreferMoves used to skip ENTRENCH! and get eaten here).
                    if user and user.isPlayer and action
                        and action.special ~= "holdPosition"
                        and action.special ~= "awaitIncoming" then
                        local state = React.peek(self)
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
                        -- Cover / brace / entrench buffs stay (unless max just cleared).
                        return
                    end
                    -- FIRE / COVER spent the later call: skip the queued swing.
                    if user and not user.isPlayer then
                        local state = React.peek(self)
                        if state and state.skipQueuedEnemyAction then
                            state.skipQueuedEnemyAction = nil
                            dev.log(self, "FOE REACT spent", "skip later executeAction")
                            return
                        end
                    end
                    -- After a dodge opening going second: use the counter move you picked.
                    if user and user.isPlayer then
                        local state = React.peek(self)
                        if state and state.skipQueuedPlayerAction then
                            state.skipQueuedPlayerAction = nil
                            self._arAwaitCallout = nil
                            dev.log(self, "REACT spent", "skip later executeAction")
                            return
                        end
                        if action and action.special == "awaitIncoming" then
                            if self.result then
                                return
                            end
                            if not user.mon or user.mon.hp <= 0 then
                                return
                            end
                            self.nextInsert = 0
                            self._arAwaitCallout = true
                            self.phase = "moveSelect"
                            self._arFieldPreferMoves = true
                            self._arFieldCommandHold = nil
                            local moves = self.player and self.player.curMoves
                            local n = moves and #moves or 1
                            self.moveIndex = math.min(self.moveIndex or 1, n)
                            self.moveSwapIndex = nil
                            dev.log(self, "CALLOUT now", "slower side picks after the incoming")
                            return
                        end
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
                    local called = isCalled == true or self._arAgainCalled == true
                    signalAttackPresentation(self, user, target, move or moveInst, {
                        isCalled = called,
                    })
                    self._arAgainCalled = nil
                    return origPerformMove(self, user, target, moveInst, called)
                end
            end
        end

        -- Keep Dig/Fly-style dodge hides through the foe's attack anim.
        do
            local origResetPicFx = BattleState.resetPicFx
            if type(origResetPicFx) == "function" then
                function BattleState.resetPicFx(self)
                    origResetPicFx(self)
                    local state = self and React.peek(self)
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
                    local state = self and React.peek(self)
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
                    -- FIELD owns the bottom chrome. Calling the classic slab
                    -- even with a zero scissor still paints the white move box
                    -- + continue caret onto the UI canvas under our HUD.
                    if hud.fieldCompactActive(self) then
                        return
                    end
                    -- Stacked learn-move / YES-NO states draw themselves.
                    -- Keep BattleState's slab invisible so leftover bubbles
                    -- do not paint under the prompt.
                    if hud.bubblesOwnDialogue(self) or hud.stackedPromptActive(self) then
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

        if Battle and Battle.Dialogue then
            Battle.Dialogue.bind({
                BattleState = BattleState,
                patched = hud.patched,
                reactionAfterMoveAnnounce = reactionAfterMoveAnnounce,
                rewriteDodgeMissText = rewriteDodgeMissText,
                fieldFlowsText = fieldFlowsText,
                findMoveByName = findMoveByName,
                foeMoveIsSpecial = foeMoveIsSpecial,
                tagLatestQueueFieldCue = tagLatestQueueFieldCue,
                stampNpcOrderOnAnnounce = stampNpcOrderOnAnnounce,
                pushNpcCallout = pushNpcCallout,
                tagFieldCue = tagFieldCue,
                maybeQueueSameTurnCounter = maybeQueueSameTurnCounter,
                tagQueueBubble = tagQueueBubble,
                applyFieldToastAuto = applyFieldToastAuto,
                maybeEnqueueSendBanter = maybeEnqueueSendBanter,
                willShowCalloutPick = hud.willShowCalloutPick,
                willShowCounterPick = hud.willShowCounterPick,
                resolveCoverOnPlayerAttack = resolveCoverOnPlayerAttack,
                tryFoeCoverReaction = tryFoeCoverReaction,
                isGuaranteedCounterHit = function(battle, user, target)
                    if React and type(React.isGuaranteedCounterHit) == "function" then
                        return React.isGuaranteedCounterHit(battle, user, target)
                    end
                end,
                fieldCueForFoeCover = fieldCueForFoeCover,
                enqueueReactWithAttack = enqueueReactWithAttack,
                enqueueNpcFlavor = enqueueNpcFlavor,
                applyCalloutBuffs = applyCalloutBuffs,
                enqueueBraceAnim = enqueueBraceAnim,
                isDodgeFailNarrator = isDodgeFailNarrator,
                enqueueAutoAfter = enqueueAutoAfter,
                playerMonName = playerMonName,
                noteBattleLine = function(battle, text)
                    if type(text) ~= "string" or not battle then
                        return
                    end
                    local lower = text:lower()
                    if not lower:find("critical", 1, true) then
                        return
                    end
                    local side = battle._arLastHitSide
                    if side ~= "player" and side ~= "enemy" then
                        side = "enemy"
                    end
                    dev.noteMood(battle, { kind = "crit", side = side })
                end,
                tryVanishEvasion = tryVanishEvasion,
                enqueueDodgeHideAnim = enqueueDodgeHideAnim,
            })
            hud.wrapBattleSay = Battle.Dialogue.wrapBattleSay
        else
            hud.wrapBattleSay = function() end
        end
        hud.wrapBattleSay("sayNext")
        hud.wrapBattleSay("say")
        hud.wrapBattleSay("sayNextAuto")
        hud.wrapBattleSay("sayAuto")

        if Hud and Hud.Hide then
            Hud.Hide.bind({
                opt = opt,
                hideAllHud = hideAllHud,
                partyRowHint = partyRowHint,
                fieldCompactActive = hud.fieldCompactActive,
                fieldBattleInGame = hud.fieldBattleInGame,
                bubblesOwnDialogue = hud.bubblesOwnDialogue,
                onFieldInstall = function()
                    if type(dev.installFieldFightSpriteHook) == "function" then
                        pcall(dev.installFieldFightSpriteHook)
                    end
                    if FieldBattleViewer and type(FieldBattleViewer.install) == "function" then
                        pcall(FieldBattleViewer.install, mod)
                    end
                end,
            })
            pcall(Hud.Hide.install, mod)
        end

        -- FIELD intercept needs OverworldState, which may load after boot.
        -- Keep this independent of HUD hide so a Hide.install miss cannot
        -- leave pics suppressed with no map cast.
        if FieldBattleViewer and type(FieldBattleViewer.install) == "function" then
            mod.events:on("mods.loaded", function()
                pcall(FieldBattleViewer.install, mod)
            end)
            mod.events:on("game.ready", function()
                pcall(FieldBattleViewer.install, mod)
            end)
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
