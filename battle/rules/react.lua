-- Battle systems — REACT pipeline (momentum, EffectRegistry wrap)
--
-- Pure Focus math stays in rules/reactive_defense.lua. Pick HUD paint
-- lives in chrome/pick.lua. This module owns when to offer REACT /
-- COUNTER and how a pick mutates the damage pipeline.
-- Presentation helpers (bubbles, FX, queue inserts) are injected via
-- React.bind(host) from main.lua so FIELD and classic can share the same
-- rules without this file requiring field/.

local React = {}

local byBattle = setmetatable({}, { __mode = "k" })
local host = {}
local vanillaRunDamaging
local Hud

function React.attachHud(mod)
    if type(mod) == "table" then
        Hud = mod
        if type(host) == "table" and type(Hud.bind) == "function" then
            Hud.bind(host)
        end
    end
    return React
end

function React.bind(h)
    if type(h) == "table" then
        host = h
        if type(h.runDamaging) == "function" then
            vanillaRunDamaging = h.runDamaging
        end
        if Hud and type(Hud.bind) == "function" then
            Hud.bind(h)
        end
    end
    return React
end

local function opt(key)
    local fn = host.opt
    if type(fn) == "function" then
        return fn(key)
    end
    return false
end

local function log(battle, ...)
    local fn = host.log
    if type(fn) == "function" then
        return fn(battle, ...)
    end
end

local function hostCall(name, ...)
    local fn = host[name]
    if type(fn) == "function" then
        return fn(...)
    end
end

local function S()
    return host.S or {}
end

local function RD()
    return host.RD
end

local function origRunDamaging(...)
    local fn = vanillaRunDamaging or host.runDamaging
    if type(fn) == "function" then
        return fn(...)
    end
end

local function freshMomentum()
    return {
        mode = nil,
        boosted = false,
        enemyActedThisTurn = false,
        playerActedThisTurn = false,
        skipQueuedPlayerAction = false,
        queuedPlayerAction = nil,
        fireNowMove = nil,
        pickOfferedThisTurn = false,
        awaitingPick = nil,
        pendingDamage = nil,
        -- Temporary cover buffs from dodge/brace; cleared on your attack.
        -- entrenched: strong brace — near-max DEF while you wait to counter;
        -- foe can rarely "break through" and strip it before damage.
        -- entrenchTurns: STAY count while locked in (max S().ENTRENCH_MAX_TURNS).
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
    local state = byBattle[battle]
    if not state then
        state = freshMomentum()
        byBattle[battle] = state
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
local function resetMomentum(battle)
    if not battle then
        return
    end
    local prev = byBattle[battle]
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
    byBattle[battle] = freshMomentum()
    if keepTemp then
        byBattle[battle].temp = keepTemp
    end
    if keepEnemyTemp then
        byBattle[battle].enemyTemp = keepEnemyTemp
    end
    if keepCounter then
        byBattle[battle].mode = "counter"
        byBattle[battle].boosted = false
    end
    if keepEnemyCounter then
        byBattle[battle].enemyMode = "counter"
        byBattle[battle].enemyBoosted = false
    end
    -- Battle-owned latches survive hot-reload weak-table resets.
    battle._arSuppressReactDefer = nil
    battle._arPickOfferedThisTurn = nil
    battle._arAwaitingReact = nil
    battle._arWhiffCloseStrike = nil
end
clearCalloutPickState = function(battle)
    if not battle then
        return
    end
    local state = byBattle[battle]
    if state then
        state.awaitingPick = nil
        state.pendingDamage = nil
        state.pendingFoeReaction = nil
        state.suppressReactDefer = nil
    end
    battle._arSuppressReactDefer = nil
    -- Issue #6: drop the sticky FIELD diamond so PKMN is reachable.
    battle._arFieldPreferMoves = nil
    battle._arFieldCommandHold = true
    if battle.phase == "moveSelect" or battle.phase == "mimicSelect" then
        battle.phase = "menu"
    end
    if type(battle.queue) == "table" then
        for i = #battle.queue, 1, -1 do
            local row = battle.queue[i]
            if type(row) == "table" and row.ui then
                table.remove(battle.queue, i)
            end
        end
    end
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
    local state = byBattle[battle]
    local pending = state and state.pendingFoeReaction
    if state then
        state.pendingFoeReaction = nil
    end
    if not pending or not pending.moveDef then
        return
    end
    local foeLine, foeBuffs, foeTrack, failNarr =
        hostCall("tryFoeCoverReaction", battle, pending.moveDef)
    if not foeLine and not failNarr then
        return
    end
    hostCall("applyCalloutBuffs", battle, foeBuffs, foeTrack)
    -- If the real move anim is already gone from the queue, shouting / sparkles
    -- would land after damage/faint — keep the silent buffs only.
    if not hostCall("indexOfMoveAnim", battle) then
        return
    end
    -- Insert fail first, then order: each insertBeforeAnim lands before anim,
    -- so later inserts sit earlier in the queue (order → fail → anim).
    local delay = (S().CALLOUT_AUTO_DELAY or 55)
    if failNarr then
        local failItem = {
            text = failNarr,
            auto = true,
            autoDelay = delay,
        }
        hostCall("tagFieldCue", failItem, "enemy", "hit")
        hostCall("insertBeforeAnim", battle, failItem)
        -- Order shout without a dodge pose — they were told to dodge and missed it.
        if foeLine and not hostCall("enqueueNpcFlavor", battle, foeLine, delay) then
            local item = {
                text = foeLine,
                auto = true,
                autoDelay = delay,
            }
            hostCall("markBubbleWait", item, "foe", true, battle)
            hostCall("insertBeforeAnim", battle, item)
        end
    elseif foeLine then
        local cue = hostCall("fieldCueForFoeCover", foeBuffs, foeLine)
        local bubble = hostCall("isDodgeFailNarrator", foeLine) and "narrator" or "foe"
        if not hostCall("enqueueReactWithAttack", battle, foeLine, delay, bubble, cue) then
            local item = {
                text = foeLine,
                auto = true,
                autoDelay = delay,
            }
            hostCall("markBubbleWait", item, bubble, true, battle)
            hostCall("tagFieldCue", item, cue.side, cue.kind)
            hostCall("insertBeforeAnim", battle, item)
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
            hostCall("enqueueBraceAnim", battle, { foe = true, beforeAnim = true })
        end
    end
end

resolvePendingDamage = function(battle)
    if not battle then
        return
    end
    local state = byBattle[battle]
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
        battle.nextInsert = hostCall("resumeInsertIndex", battle)
    end
    origRunDamaging(battle, pending.ctx, pending.record)
end

local function threatWantsPick(battle, move)
    if hostCall( "pickMode" ) == "ALWAYS" then
        return true
    end
    if hostCall( "pickMode" ) ~= "THREAT" then
        return false
    end
    local player = battle and battle.player
    local mon = player and player.mon
    if mon and mon.stats and mon.stats.hp and mon.stats.hp > 0 then
        if (mon.hp or 0) / mon.stats.hp <= hostCall( "lowHpRatio" ) then
            return true
        end
    end
    local power = move and (move.power or 0) or 0
    if power >= 80 then
        return true
    end
    if power >= 40 and hostCall("foeMoveIsSpecial", move) then
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
    if hostCall( "pickMode" ) == "OFF" or not opt("momentum_counter") then
        return false
    end
    if not battle or not move then
        return false
    end
    if (move.power or 0) <= 0 or move.category == "status" then
        return false
    end
    -- Frozen / asleep: can't dodge, brace, or take orders.
    if hostCall("playerStatusLocked", battle) then
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
    if RD() then
        local side = RD().sideState(battle, true)
        if side and side.entrenched and (side.entrenchTurns or 0) > 0 then
            return false
        end
        return threatWantsPick(battle, move)
    end
    -- Legacy path (no Focus module).
    if hostCall("playerInDeepCover", battle) then
        return false
    end
    if hostCall("playerHoldingHide", battle) then
        return false
    end
    local st = byBattle[battle]
    if st and st.temp and st.temp.entrenched then
        return false
    end
    return threatWantsPick(battle, move)
end

local function enqueueTrainerReactCall(battle, me, moveName, action)
    local kind = action
    if action == "entrench_hold" then
        kind = "entrench"
    end
    local line = hostCall("pickCallEntry", kind, battle, me, moveName)
    if type(line) ~= "string" or line == "" then
        local name = tostring(me or "POKéMON")
        if action == "dodge" then
            line = name .. "!\nDodge it!"
        elseif action == "cover" then
            line = name .. "!\nTake cover!"
        elseif action == "brace" then
            line = name .. "!\nBrace yourself!"
        elseif action == "commit" then
            line = name .. "!\nTake it!"
        elseif action == "fire" then
            line = name .. "!\nNow!"
        elseif action == "entrench" or action == "entrench_hold" then
            line = name .. "!\nHold the line!"
        elseif action == "entrench_break" then
            line = name .. "!\nBreak stance!"
        else
            line = name .. "!"
        end
    end
    if hostCall("pushPlayerCallout", battle, line, { kind = "react" }) then
        return
    end
    if type(battle) ~= "table" or type(battle.queue) ~= "table" then
        return
    end
    local item = {
        text = line,
        auto = true,
        autoDelay = (S().CALLOUT_AUTO_DELAY or 55),
    }
    hostCall("markBubbleWait", item, "player", true, battle)
    table.insert(battle.queue, 1, item)
end

-- After the incoming swing: counter toast + physical jab + HP drain.
-- Dodge/brace flavor stays on the first beat (result.lines).
local function queueReactCounterStrike(battle, result, ctx)
    if not (battle and result and result.counter and ctx) then
        return
    end
    if type(battle.queue) ~= "table" then
        return
    end
    local player = battle.player
    local foe = battle.enemy
    if not (player and player.mon and (player.mon.hp or 0) > 0) then
        return
    end
    if not (foe and foe.mon and (foe.mon.hp or 0) > 0) then
        return
    end

    -- Sit after the incoming hit's text/anim, before endOfTurn / executeAction.
    local q = battle.queue
    local fnIdx = nil
    for i = 1, #q do
        local row = q[i]
        if type(row) == "table" and type(row.fn) == "function" and not row.arFx then
            fnIdx = i
            break
        end
    end
    if fnIdx then
        battle.nextInsert = fnIdx - 1
    else
        battle.nextInsert = #q
    end

    local frac = result.counter.powerFrac or 0.35
    if result.counter.absorbScale and result.counter.reduction then
        frac = 0.25 + (result.counter.reduction or 0) * 0.5
    end
    local dealt = math.max(1, math.floor(
        ((ctx.move and ctx.move.power) or 40) * frac * 0.4))

    local kind = result.counter.kind
    local user = battle.player
    local moveId = result.counter.moveId
        or hostCall("pickCounterStrikeMove", battle, kind, user, ctx and ctx.move)
    local moves = battle.data and battle.data.moves
    local move = (moveId and type(moves) == "table" and type(moves[moveId]) == "table")
        and moves[moveId]
        or (moveId and { id = moveId, category = "physical", power = 40, type = "NORMAL" })
        or nil
    local category = tostring((result.counter.category or (move and move.category) or "physical")):lower()
    if category ~= "special" then
        category = "physical"
    end
    local ranged = result.counter.ranged == true
        or hostCall("isRangedCounter", battle, {
            moveId = moveId,
            moveType = move and move.type,
            category = category,
        }) == true

    local me = hostCall("playerMonName", battle) or "POKéMON"
    local line = result.counter.line or (me .. " countered!")

    battle.nextInsert = (battle.nextInsert or 0) + 1
    table.insert(battle.queue, battle.nextInsert, {
        arFx = true,
        fn = function()
            if not battle.player or not battle.enemy then
                return
            end
            hostCall("pushNotice", battle, line, { kind = "counter" })
            hostCall("armFieldChip", battle, "player", "COUNTER")
            if hostCall("isFieldBattle", battle) then
                hostCall("fieldReact", battle, "player", "counter", {
                    category = category,
                    moveId = moveId,
                    moveType = move and move.type,
                })
            elseif move then
                hostCall("signalAttackPresentation", battle, battle.player, battle.enemy, move, {
                    isCalled = true,
                })
            end
        end,
    })
    if move and not hostCall("isFieldBattle", battle) then
        hostCall("queueMoveAttackAnim", battle, move, true)
    end
    -- Never restore the incoming foe clip. That made leftover FURY_ATTACK
    -- rows run as the player after a named counter they don't know.

    battle.nextInsert = (battle.nextInsert or 0) + 1
    table.insert(battle.queue, battle.nextInsert, {
            arFx = true,
            arFieldCue = {
                side = "enemy",
                kind = "hit",
                category = category,
                clash = not ranged,
            },
        fn = function()
            local target = battle.enemy
            if not target or not target.mon or (target.mon.hp or 0) <= 0 then
                return
            end
            if type(battle.applyDamage) ~= "function" then
                return
            end
            battle:applyDamage(target, dealt)
            if target.mon.hp <= 0 and type(battle.onFaint) == "function" then
                battle:onFaint(target)
            end
        end,
    })
    log(battle, "REACT counter", tostring(kind or "?") .. "→" .. tostring(moveId or "-"))
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
    battle._arAwaitingReact = nil
    -- Invalidate any leftover REACT ui rows still sitting in the queue.
    state.reactEpoch = (state.reactEpoch or 0) + 1
    local pending = state.pendingDamage
    state.pendingDamage = nil
    state.enemyActedThisTurn = true

    -- Drop any leftover REACT! ui rows so the menu can't pop twice.
    scrubReactPickRows(battle)

    enqueueTrainerReactCall(battle, me, moveName, action)

    if action == "entrench_break" and RD() then
        local ok = RD().earlyExitEntrench(battle, true)
        if ok then
            hostCall("enqueueAutoAfter", battle, "Broke entrench!", (S().CALLOUT_AUTO_DELAY or 55), "player")
        end
        action = "commit"
    end

    local result = { lines = {}, damageMult = 1, forceMiss = false }
    if RD() and pending and pending.ctx then
        result = RD().resolveIncoming(battle, action, braceCall, pending.ctx)
            or result
        RD().state(battle).hitMod = {
            damageMult = result.damageMult or 1,
            forceMiss = result.forceMiss == true,
            coverSoak = result.coverSoak == true,
            coverDurMult = result.coverDurMult or 1,
        }
    end

    if result.counter then
        local moveId = hostCall("pickCounterStrikeMove", battle, result.counter.kind,
            battle.player, pending and pending.ctx and pending.ctx.move)
        local moves = battle.data and battle.data.moves
        local move = (moveId and type(moves) == "table" and type(moves[moveId]) == "table")
            and moves[moveId]
            or (moveId and { id = moveId, category = "physical", type = "NORMAL" })
            or nil
        local category = tostring((move and move.category) or "physical"):lower()
        if category ~= "special" then
            category = "physical"
        end
        result.counter.moveId = moveId
        result.counter.moveType = move and move.type
        result.counter.category = category
        result.counter.ranged = hostCall("isRangedCounter", battle, {
            moveId = moveId,
            moveType = result.counter.moveType,
            category = category,
        }) == true
    end

    local outcome = result.action or action
    if result.fireNow then
        outcome = "fire"
    elseif result.counter and result.counter.ranged then
        outcome = "dodge_shot"
    elseif result.forceMiss then
        outcome = "dodge"
    elseif tostring(action) == "dodge" then
        outcome = "dodge_fail"
    end
    hostCall("releaseReactHold", battle, outcome)

    -- Dodge / cover / brace FX before the foe's swing (or instead of it).
    -- FIRE NOW lets performMove paint the special; don't also sidestep.
    if not result.fireNow and type(host.playFocusReactFx) == "function" then
        host.playFocusReactFx(battle, result.action or action, result)
    end

    -- FIELD HP chips: only a successful player REACT! pick, never the
    -- order toast, a failed react, or an engine miss / auto foe dodge.
    if result.chip then
        hostCall("armFieldChip", battle, "player", result.chip)
    end

    -- Beat flavor rides the top-right notice stack so it cannot bury the swing.
    for i = 1, #(result.lines or {}) do
        hostCall("pushNotice", battle, result.lines[i], { kind = "react" })
    end

    log(battle, "REACT " .. tostring(action),
        string.format("mult=%.2f miss=%s focus=%s",
            tonumber(result.damageMult) or 1,
            result.forceMiss and "Y" or "N",
            RD() and RD().focusLabel(battle, true) or "-"))

    if pending and pending.ctx then
        battle.nextInsert = hostCall("resumeInsertIndex", battle)
        local okDmg, errDmg = pcall(function()
            if result.forceMiss then
                if type(battle.cancelMoveAnim) == "function" then
                    pcall(battle.cancelMoveAnim, battle)
                end
                if type(battle.waitNext) == "function" then
                    pcall(battle.waitNext, battle, 20)
                end
                -- Incoming close-the-gap walk must not punch after a dodge.
                local user = pending.ctx.user
                battle._arWhiffCloseStrike = (user and user.isPlayer) and "player" or "enemy"
                local holdCharge = hostCall("isFieldBattle", battle)
                    and result.counter and result.counter.ranged
                    and hostCall("closeGapPending", battle, battle._arWhiffCloseStrike)
                if holdCharge then
                    hostCall("deferCancelCloseStrike", battle, battle._arWhiffCloseStrike, 0.42)
                else
                    hostCall("cancelCloseStrike", battle, battle._arWhiffCloseStrike)
                end
                -- Clear hitMod so a later hit isn't zeroed.
                if RD() then
                    RD().state(battle).hitMod = nil
                end
            else
                if result.fireNow then
                    hostCall("fireQueuedSpecial", battle, state.fireNowMove)
                    state.fireNowMove = nil
                end
                local foe = battle.enemy
                local foeDown = foe and foe.mon and (foe.mon.hp or 0) <= 0
                if result.fireNow and foeDown then
                    hostCall("cancelCloseStrike", battle, "enemy")
                else
                    -- REACT menu / cover FX can outlive BC's original arm — re-arm now so
                    -- the foe's swing still gets the attack camera.
                    hostCall("signalAttackPresentation",
                        battle, pending.ctx.user, pending.ctx.target, pending.ctx.move,
                        { presentationOnly = true })
                    origRunDamaging(battle, pending.ctx, pending.record)
                end
            end
            if not result.fireNow then
                queueReactCounterStrike(battle, result, pending.ctx)
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
end

local function newCalloutPickModal(game, opts)
    if Hud and type(Hud.newModal) == "function" then
        return Hud.newModal(game, opts)
    end
    return {
        game = game,
        update = function(self)
            if self.game and self.game.stack then
                self.game.stack:pop()
            end
        end,
        draw = function() end,
    }
end

local function listFireNowMoves(battle)
    local list = hostCall("listFireNowMoves", battle, battle and battle.player)
    if type(list) == "table" then
        return list
    end
    return {}
end

local function preferredFireNowMove(battle)
    local shots = listFireNowMoves(battle)
    if #shots == 0 then
        return nil, shots, 1
    end
    local queued = battle and momentumState(battle).queuedPlayerAction
    local qid = queued and tostring(queued.id or queued.name or ""):upper():gsub("%s+", "_")
    if qid and qid ~= "" then
        for i = 1, #shots do
            if shots[i].moveId == qid then
                return shots[i], shots, i
            end
        end
    end
    return shots[1], shots, 1
end

local function incomingIsRanged(battle, incoming)
    if not incoming then
        return false
    end
    return hostCall("isRangedCounter", battle, {
        moveId = incoming.id or incoming.moveId,
        moveType = incoming.type or incoming.moveType,
        category = incoming.category,
    }) == true
end

local function incomingIsMelee(battle, incoming)
    if not incoming then
        return false
    end
    local opts = {
        moveId = incoming.id or incoming.moveId,
        moveType = incoming.type or incoming.moveType,
        category = incoming.category,
    }
    if hostCall("isMeleeAttack", battle, opts) == true then
        return true
    end
    if incomingIsRanged(battle, incoming) then
        return false
    end
    return tostring(incoming.category or ""):lower() == "physical"
end

local function canFireNow(battle, incoming)
    if not hostCall("isFieldBattle", battle) then
        return false
    end
    if hostCall("playerStatusLocked", battle) then
        return false
    end
    if incomingIsRanged(battle, incoming) then
        return false
    end
    local state = momentumState(battle)
    if state.playerActedThisTurn or state.skipQueuedPlayerAction then
        return false
    end
    local action = state.queuedPlayerAction
    -- Going second after locking a move — item / switch / run stay as-is.
    if type(action) == "table" and (action.struggle or action.item
        or action.switch or action.run or action.special == "holdPosition") then
        return false
    end
    -- Compact pad + Quick Attack dash: still a fire window even when the
    -- walk has not armed, or the mons already share adjacent home cells.
    if not incomingIsMelee(battle, incoming)
        and not hostCall("chargeWindowOpen", battle) then
        return false
    end
    return #listFireNowMoves(battle) > 0
end

local function fireHintForMenu(battle)
    local preferred, shots = preferredFireNowMove(battle)
    if type(shots) == "table" and #shots > 1 then
        return "Pick a special"
    end
    if preferred then
        return tostring(preferred.name or preferred.moveId or "Special now")
    end
    return "Special now"
end

-- Serious hits: Focus menu — Dodge / Fire / Cover / Brace / Entrench / Commit.
local function queueFireNowMoveMenu(battle, me, moveName, shots, prefIdx)
    local choices = {}
    for i = 1, #shots do
        local shot = shots[i]
        choices[#choices + 1] = {
            label = shot.label or shot.name or shot.moveId,
            hint = shot.hint or "Special now",
            id = "fire",
            moveInst = shot.moveInst,
        }
    end
    hostCall("insertBeforeAnim", battle, {
        arReactPick = true,
        arReactEpoch = momentumState(battle).reactEpoch,
        ui = function()
            local st = momentumState(battle)
            if not st.pendingDamage or st.suppressReactDefer then
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
            return newCalloutPickModal(battle.game, {
                title = "FIRE!",
                subtitle = me,
                index = prefIdx or 1,
                pad = #choices > 0 and #choices <= 4,
                choices = choices,
                cancelable = false,
                onPick = function(choice)
                    local st = momentumState(battle)
                    st.fireNowMove = choice and choice.moveInst or shots[1] and shots[1].moveInst
                    finishCalloutPick(battle, me, moveName, "fire", nil)
                end,
            })
        end,
    })
end

local function queueCalloutPickMenu(battle, me, moveName, preferredKind)
    if not RD() then
        -- Fallback: commit through immediately.
        finishCalloutPick(battle, me, moveName, "commit", nil)
        return
    end
    local function beginFireNow(shots, prefIdx)
        shots = shots or {}
        if #shots == 0 then
            finishCalloutPick(battle, me, moveName, "commit", nil)
            return
        end
        if #shots == 1 then
            momentumState(battle).fireNowMove = shots[1].moveInst
            finishCalloutPick(battle, me, moveName, "fire", nil)
            return
        end
        queueFireNowMoveMenu(battle, me, moveName, shots, prefIdx)
    end
    local function openReactMenu()
        local pendingMove = nil
        do
            local st = momentumState(battle)
            pendingMove = st.pendingDamage and st.pendingDamage.ctx
                and st.pendingDamage.ctx.move
        end
        local fireNow = canFireNow(battle, pendingMove)
        local actions = RD().menuActions(battle, pendingMove, {
            canFireNow = fireNow,
            fireHint = fireHintForMenu(battle),
        })
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
                    local braceCall = hostCall("foeMoveIsSpecial", pendingMove) and "special"
                        or "physical"
                    if pendingMove and pendingMove.category == "status" then
                        braceCall = "status"
                    end
                    finishCalloutPick(battle, me, moveName, "brace", braceCall)
                    return
                end
                if id == "fire" then
                    local _, shots, prefIdx = preferredFireNowMove(battle)
                    beginFireNow(shots, prefIdx)
                    return
                end
                finishCalloutPick(battle, me, moveName, id, nil)
            end,
        })
    end
    scrubReactPickRows(battle)
    local reactEpoch = (momentumState(battle).reactEpoch or 0) + 1
    momentumState(battle).reactEpoch = reactEpoch
    hostCall("insertBeforeAnim", battle, {
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
    hostCall("scrubLateDodgeWhiff", battle)
    if not choice or choice.hold or tostring(choice.label or "") == "HOLD" then
        state.mode = nil
        state.boosted = false
        state.foeWhiffDamage = nil
        state.replaceQueuedPlayerAction = nil
        log(battle, "COUNTER! pick",
            replacing and "HOLD keep-plan" or "HOLD skip")
        -- Going second + HOLD: keep the move you picked at turn start.
        return
    end
    local moveInst = choice.moveInst
    if not moveInst or not battle.player or not battle.enemy then
        state.mode = nil
        state.boosted = false
        state.replaceQueuedPlayerAction = nil
        return
    end
    if (battle.player.mon and battle.player.mon.hp or 0) <= 0
        or (battle.enemy.mon and battle.enemy.mon.hp or 0) <= 0 then
        state.mode = nil
        state.boosted = false
        state.replaceQueuedPlayerAction = nil
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
        log(battle, "COUNTER! pick", "replace→" .. moveName)
        return
    end
    -- You already attacked this turn: fire an extra counter strike now.
    log(battle, "COUNTER! pick", "extra→" .. moveName)
    table.insert(battle.queue, 1, {
        arFx = true,
        fn = function()
            if not battle.player or not battle.enemy then
                return
            end
            if (battle.player.mon.hp or 0) <= 0 or (battle.enemy.mon.hp or 0) <= 0 then
                state.mode = nil
                return
            end
            -- Idle BC camera often takes over during the COUNTER! menu — snap it
            -- back; performMove wrap + engine move_used re-arm the attack cam.
            hostCall("resetBattleCamera", battle)
            hostCall("armFieldChip", battle, "player", "COUNTER")
            battle._arCounterClash = true
            battle:performMove(battle.player, battle.enemy, moveInst)
        end,
    })
end

maybeQueueSameTurnCounter = function(battle)
    if not opt("momentum_counter") or not battle then
        return
    end
    local state = byBattle[battle]
    if not state or not state.offerSameTurnCounter then
        return
    end
    state.offerSameTurnCounter = nil
    if hostCall("playerStatusLocked", battle) then
        log(battle, "COUNTER! skip", "status-locked")
        return
    end
    if state.sameTurnCounterQueued or not hostCall("playerHasCounter", battle) then
        log(battle, "COUNTER! skip",
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
    local me = hostCall("playerMonName", battle)
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
                def = hostCall("findMoveByName", battle, mv.id or mv.name)
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
    log(battle, "COUNTER! menu",
        replacing and "re-pick after miss anim" or "extra strike after miss anim")
    hostCall("insertAfterMissAnim", battle, {
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
    -- Opening is live after "dodged aside!".
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
        local line, drop = hostCall("pickCallEntry", "counter", battle, me, moveName)
        line = line or ("Now, " .. me .. "!\nHit back!")
        drop = drop or 1
        do
            local item = {
                text = line,
                auto = true,
                autoDelay = (S().CALLOUT_AUTO_DELAY or 55),
            }
            hostCall("markBubbleWait", item, "player", true, battle)
            hostCall("tagFieldCue", item, "player", "attack", "physical")
            table.insert(battle.queue, 1, item)
        end
        battle.nextInsert = 1
        hostCall("applyCalloutBuffs", battle, {
            { who = "enemy", stat = "defense", delta = -drop, fromEnemy = true },
        }, false)
        log(battle, "OPENING! pick",
            "COUNTER " .. tostring(moveName) .. " foeDF-" .. tostring(drop))
    else
        state.mode = nil
        state.boosted = false
        state.foeWhiffDamage = nil
        log(battle, "OPENING! pick", "HOLD (clear arm)")
    end

    if pending and pending.ctx then
        -- Foe dodge/brace after your COUNTER/HOLD choice, before the hit.
        flushPendingFoeReaction(battle)
        battle.nextInsert = hostCall("resumeInsertIndex", battle)
        origRunDamaging(battle, pending.ctx, pending.record)
        if doCounter then
            local connected = state.boosted
            -- Damage hook should have consumed the boost; clear arming either way.
            state.mode = nil
            if hostCall("resolvePlayerCounterAttempt", battle, connected) then
                -- Foe snap-back queued; skip Again!
            elseif connected then
                -- Anime follow-through: true second hit if the foe is still up.
                hostCall("tryAgainStrike", battle, pending.ctx, me, false)
            end
        end
    elseif doCounter then
        state.mode = nil
        state.pendingFoeReaction = nil
        state.foeWhiffDamage = nil
    end
end

local function queueCounterPickMenu(battle, me, moveName)
    hostCall("insertBeforeAnim", battle, {
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
    if hostCall("playerStatusLocked", battle) then
        return false
    end
    if not hostCall("playerHasCounter", battle) then
        return false
    end
    local state = momentumState(battle)
    if state.awaitingPick or state.pendingDamage then
        return false
    end
    return true
end


function React.state(battle)
    return momentumState(battle)
end

function React.peek(battle)
    return battle and byBattle[battle] or nil
end

function React.reset(battle)
    return resetMomentum(battle)
end

function React.clear(battle)
    if battle then
        byBattle[battle] = freshMomentum()
    end
end

function React.clearPick(battle)
    return clearCalloutPickState(battle)
end

function React.resolvePending(battle)
    return resolvePendingDamage(battle)
end

function React.maybeQueueSameTurnCounter(battle)
    return maybeQueueSameTurnCounter(battle)
end

function React.fresh()
    return freshMomentum()
end

function React.newPickModal(game, opts)
    return newCalloutPickModal(game, opts)
end

function React.shouldOffer(battle, move)
    return shouldOfferCalloutPick(battle, move)
end


function React.install(mod)
    local EffectRegistry = require("src.battle.EffectRegistry")
    local stored = EffectRegistry._arVanillaRunDamaging
    local liveWrap = EffectRegistry._arReactRunDamaging
    local vanilla = vanillaRunDamaging
    if type(vanilla) ~= "function" then
        vanilla = host.runDamaging
    end
    if type(stored) == "function" and stored ~= liveWrap then
        vanilla = stored
    elseif type(vanilla) ~= "function" then
        vanilla = EffectRegistry.runDamaging
        if vanilla == liveWrap and type(stored) == "function" then
            vanilla = stored
        end
    elseif vanilla == liveWrap and type(stored) == "function" then
        vanilla = stored
    end
    EffectRegistry._arVanillaRunDamaging = vanilla
    vanillaRunDamaging = vanilla

function EffectRegistry.runDamaging(battle, ctx, record)
    do
        local move = ctx and ctx.move
        local who = (ctx and ctx.user and ctx.user.isPlayer) and "you" or "foe"
        log(battle, "runDamaging",
            tostring(move and (move.id or move.name) or "-") .. " by=" .. who)
    end
    -- Focus trench: soak the hit with entrench mitigation (no REACT menu).
    if RD() and opt("momentum_counter") and battle and ctx
        and ctx.user and not ctx.user.isPlayer
        and ctx.target and ctx.target.isPlayer then
        local side = RD().sideState(battle, true)
        local state = momentumState(battle)
        if side and side.entrenched and (side.entrenchTurns or 0) > 0
            and not state.awaitingPick and not state.pendingDamage then
            local move = ctx.move
            local me = hostCall("playerMonName", battle)
            local moveName = tostring((move and (move.name or move.id)) or "MOVE")
            state.awaitingPick = "react"
            state.pendingDamage = { ctx = ctx, record = record }
            do
                local animIdx = hostCall("indexOfMoveAnim", battle)
                local row = animIdx and battle.queue[animIdx]
                if row and row.anim then
                    battle.moveAnimRow = row
                end
            end
            log(battle, "AUTO entrench_hold", tostring(moveName))
            finishCalloutPick(battle, me, moveName, "entrench_hold", nil)
            return
        end
    end
    if shouldDeferForCalloutPick(battle, ctx) then
        local state = momentumState(battle)
        local move = ctx.move
        -- Cursor default only — menu always offers Focus options.
        local preferred = hostCall("foeMoveIsSpecial", move) and "dodge" or "brace"
        if canFireNow(battle, move) then
            preferred = "fire"
        end
        state.awaitingPick = "react"
        state.pendingDamage = { ctx = ctx, record = record }
        state.pickOfferedThisTurn = true
        battle._arPickOfferedThisTurn = true
        battle._arAwaitingReact = true
        hostCall("beginReactHold", battle)
        -- Pin the engine's attack anim so finishCalloutPick resumes after it
        -- (not before endOfTurn). Without this, REACT! landed after the swing.
        do
            local animIdx = hostCall("indexOfMoveAnim", battle)
            local row = animIdx and battle.queue[animIdx]
            if row and row.anim then
                battle.moveAnimRow = row
            end
        end
        local me = hostCall("playerMonName", battle)
        local moveName = tostring(move.name or move.id or "MOVE")
        log(battle, "MENU react",
            tostring(moveName) .. " prefer=" .. preferred .. " (defer hit)")
        queueCalloutPickMenu(battle, me, moveName, preferred)
        return
    end
    -- Armed opening: auto counter (no OPENING! menu — same-turn COUNTER!
    -- after a dodge miss is the interactive pick).
    if shouldAutoCounter(battle, ctx) then
        local state = momentumState(battle)
        local me = hostCall("playerMonName", battle)
        local move = ctx.move
        local moveName = tostring(move.name or move.id or "MOVE")
        state.mode = "counter"
        state.boosted = false
        local drop = 1
        local style = hostCall( "calloutStyle" )
        if style == "SHOWY" or style == "BOLD" then
            drop = 2
        end
        log(battle, "AUTO counter",
            tostring(moveName) .. " foeDF-" .. tostring(drop)
            .. (state.enemyActedThisTurn and " (2nd)" or " (1st)"))
        hostCall("applyCalloutBuffs", battle, {
            { who = "enemy", stat = "defense", delta = -drop, fromEnemy = true },
        }, false)
        flushPendingFoeReaction(battle)
        local result = origRunDamaging(battle, ctx, record)
        local connected = state.boosted
        state.mode = nil
        if hostCall("resolvePlayerCounterAttempt", battle, connected) then
            return result
        end
        if connected then
            hostCall("tryAgainStrike", battle, ctx, me, false)
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
    if enemyCounterArmed and state.enemyBoosted and hostCall("trainerFoeReactionsOn", battle)
        and hostCall("rollEnemyAgain") then
        hostCall("tryAgainStrike", battle, ctx, hostCall("enemyMonName", battle), true)
    end
    if enemyCounterArmed then
        state.enemyMode = nil
    end
    -- Same-turn COUNTER! waits for dodge-whiff text in wrapBattleSay.
    return result
end


    EffectRegistry._arReactRunDamaging = EffectRegistry.runDamaging
    return true
end

return React
