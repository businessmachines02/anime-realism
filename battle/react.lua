-- Battle systems — REACT pipeline (menus, momentum, EffectRegistry wrap)
--
-- Pure Focus math stays in reactive_defense.lua. This module owns the
-- interactive REACT / COUNTER menus and the damage-pipeline deferral.
-- Presentation helpers (bubbles, FX, queue inserts) are injected via
-- React.bind(host) from main.lua so FIELD and classic can share the same
-- rules without this file requiring field/.

local React = {}

local byBattle = setmetatable({}, { __mode = "k" })
local host = {}
local vanillaRunDamaging

function React.bind(h)
    if type(h) == "table" then
        host = h
        if type(h.runDamaging) == "function" then
            vanillaRunDamaging = h.runDamaging
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
    if failNarr then
        local failItem = {
            text = failNarr,
            auto = true,
            autoDelay = (S().CALLOUT_AUTO_DELAY or 55),
        }
        hostCall("tagFieldCue", failItem, "enemy", "hit")
        hostCall("insertBeforeAnim", battle, failItem)
    end
    if foeLine then
        local cue = hostCall("fieldCueForFoeCover", foeBuffs, foeLine)
        local bubble = hostCall("isDodgeFailNarrator", foeLine) and "narrator" or "foe"
        if not hostCall("enqueueReactWithAttack", battle, foeLine, (S().CALLOUT_AUTO_DELAY or 55),
            bubble, cue) then
            local item = {
                text = foeLine,
                auto = true,
                autoDelay = (S().CALLOUT_AUTO_DELAY or 55),
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

    -- Dodge / cover / brace FX before the foe's swing (or instead of it).
    if type(host.playFocusReactFx) == "function" then
        host.playFocusReactFx(battle, result.action or action, result)
    end

    for i = 1, #(result.lines or {}) do
        local line = result.lines[i]
        local item = { text = line, auto = true, autoDelay = (S().CALLOUT_AUTO_DELAY or 55) }
        hostCall("markBubbleWait", item, "player", true, battle)
        table.insert(battle.queue, 1, item)
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
                -- Clear hitMod so a later hit isn't zeroed.
                if RD() then
                    RD().state(battle).hitMod = nil
                end
            else
                -- REACT menu / cover FX can outlive BC's original arm — re-arm now so
                -- the foe's swing still gets the attack camera.
                hostCall("signalAttackPresentation", 
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
                battle.nextInsert = hostCall("resumeInsertIndex", battle)
                if type(battle.sayNext) == "function" then
                    battle:sayNext(string.format("%s countered!", hostCall("playerMonName", battle) or "Your Pokémon"))
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
end

local function mix01(a, b, t)
    return a + (b - a) * t
end

local function rgb01(c)
    if type(c) ~= "table" then
        return 1, 1, 1
    end
    local r = tonumber(c[1]) or 255
    local g = tonumber(c[2]) or 255
    local b = tonumber(c[3]) or 255
    if r > 1 or g > 1 or b > 1 then
        return r / 255, g / 255, b / 255
    end
    return r, g, b
end

-- COLORS (OG RED / SGB / CLASSIC / …) → a washed 4-shade chrome so the
-- REACT bar tints with the player's display pack without harsh fills.
local function reactChrome(game)
    local pal
    local data = game and game.data
    local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
    if ok and type(PaletteFX) == "table" then
        if type(PaletteFX.pal) == "function" then
            pal = PaletteFX.pal(data, "PALLET") or PaletteFX.pal(data, "GREENBAR")
        end
        pal = pal or PaletteFX.GRAYS
        if type(PaletteFX.effectiveColors) == "function" then
            pal = PaletteFX.effectiveColors(pal) or pal
        end
    end
    local pr, pg, pb = 0.97, 0.94, 0.90
    local sr, sg, sb = 0.86, 0.80, 0.78
    local ir, ig, ib = 0.16, 0.12, 0.11
    if pal and pal[1] then
        local r, g, b = rgb01(pal[1])
        pr, pg, pb = mix01(r, 1, 0.42), mix01(g, 1, 0.42), mix01(b, 1, 0.42)
    end
    if pal and pal[2] then
        local r, g, b = rgb01(pal[2])
        sr, sg, sb = mix01(r, pr, 0.58), mix01(g, pg, 0.58), mix01(b, pb, 0.58)
    elseif pal and pal[3] then
        local r, g, b = rgb01(pal[3])
        sr, sg, sb = mix01(r, pr, 0.62), mix01(g, pg, 0.62), mix01(b, pb, 0.62)
    end
    if pal and pal[4] then
        local r, g, b = rgb01(pal[4])
        ir, ig, ib = mix01(r, 0.22, 0.40), mix01(g, 0.16, 0.40), mix01(b, 0.14, 0.40)
    end
    return {
        paper = { pr, pg, pb },
        selected = { sr, sg, sb },
        ink = { ir, ig, ib },
        muted = {
            mix01(ir, pr, 0.52),
            mix01(ig, pg, 0.52),
            mix01(ib, pb, 0.52),
        },
        fill255 = { pr * 255, pg * 255, pb * 255 },
    }
end

local function reactHudStyle()
    local fn = host.reactHudStyle
    if type(fn) == "function" then
        local raw = tostring(fn() or "GRID"):upper()
        if raw == "TABS" then
            return "TABS"
        end
    end
    return "GRID"
end

local function shortReactLabel(choice)
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
    if name == "ENTRENCH" then
        return "ENTR"
    end
    return name
end

local DIR_LETTER = { up = "U", down = "D", left = "L", right = "R", a = "A" }

-- Soft pastels per react, mixed with the player's COLORS paper.
local TAB_TINTS = {
    dodge = { 0.70, 0.82, 0.94 },
    cover = { 0.76, 0.88, 0.72 },
    brace = { 0.94, 0.82, 0.68 },
    entrench = { 0.84, 0.76, 0.90 },
    commit = { 0.92, 0.88, 0.78 },
    entrench_hold = { 0.84, 0.76, 0.90 },
    entrench_break = { 0.94, 0.76, 0.76 },
    counter = { 0.94, 0.74, 0.70 },
    hold = { 0.80, 0.82, 0.86 },
}

local TAB_FALLBACK = {
    { 0.70, 0.82, 0.94 },
    { 0.76, 0.88, 0.72 },
    { 0.94, 0.82, 0.68 },
    { 0.84, 0.76, 0.90 },
    { 0.92, 0.88, 0.78 },
}

local function tabFill(choice, index, paper, selected)
    local tint = (choice and choice.id and TAB_TINTS[choice.id])
        or TAB_FALLBACK[((index - 1) % #TAB_FALLBACK) + 1]
    local wash = selected and 0.22 or 0.48
    return {
        mix01(tint[1], paper[1], wash),
        mix01(tint[2], paper[2], wash),
        mix01(tint[3], paper[3], wash),
    }
end

local function easeOutCubic(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local u = 1 - t
    return 1 - u * u * u
end

-- One-row tabs that slide up from the bottom of the 160×144 canvas.
local function drawReactTabs(g, Font, modal, chrome)
    local choices = modal.choices
    local n = #choices
    if n < 1 then
        return
    end
    local gap = 1
    local tabH = 18
    local inner = 160 - gap * (n + 1)
    local tabW = math.floor(inner / n)
    local extra = inner - tabW * n
    local age = modal._tabAge or 0
    local preferred = choices[modal.index]
    local x = gap
    for i = 1, n do
        local w = tabW
        if i <= extra then
            w = w + 1
        end
        local delay = (i - 1) * 0.04
        local t = easeOutCubic((age - delay) / 0.20)
        local y = 144 - tabH * t
        local choice = choices[i]
        local selected = preferred == choice
        if selected and t > 0.92 then
            y = y - 2
        end
        local fill = tabFill(choice, i, chrome.paper, selected)
        if choice and choice.disabled then
            fill = {
                mix01(fill[1], chrome.paper[1], 0.45),
                mix01(fill[2], chrome.paper[2], 0.45),
                mix01(fill[3], chrome.paper[3], 0.45),
            }
        end
        g.setColor(fill[1], fill[2], fill[3], 0.96)
        g.rectangle("fill", x, y, w, tabH + 4)
        g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 0.55)
        g.rectangle("line", x + 0.5, y + 0.5, w - 1, tabH + 3)
        if selected then
            g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 0.85)
            g.rectangle("fill", x + 2, y + 1, w - 4, 1)
        end
        local letter = DIR_LETTER[choice and choice.dir or ""] or tostring(i)
        local label = shortReactLabel(choice)
        if choice and choice.disabled then
            g.setColor(chrome.muted[1], chrome.muted[2], chrome.muted[3], 1)
        else
            g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
        end
        if Font and type(Font.draw) == "function" then
            g.push()
            g.translate(x + 2, y + 2)
            g.scale(0.70, 0.70)
            Font.draw(letter, 0, 0)
            g.pop()
            local scale = (#label > 5) and 0.62 or 0.70
            g.push()
            g.translate(x + 2, y + 9)
            g.scale(scale, scale)
            Font.draw(label, 0, 0)
            g.pop()
        end
        x = x + w + gap
    end
    g.setColor(1, 1, 1, 1)
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
        style = reactHudStyle(),
        cancelable = opts.cancelable == true,
        onPick = opts.onPick,
        onCancel = opts.onCancel,
        -- Instant D-pad picks must not fire on the same press that opened
        -- this modal (or a leftover held direction from the prior menu).
        _padArmed = not usePad,
        _tabAge = 0,
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

    function self:update(dt)
        if self.usePad and self.style == "TABS" then
            self._tabAge = (self._tabAge or 0) + (tonumber(dt) or 0)
        end
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
            if self.style == "TABS" then
                drawReactTabs(g, Font, self, reactChrome(self.game))
                return
            end
            -- Compact full-width 2×2 (GRID). U/R on top, L/D below;
            -- A (COMMIT) sits on the header row.
            local chrome = reactChrome(self.game)
            local preferred = self.choices[self.index]
            local x, y, w, h = 4, 100, 152, 40
            g.setColor(chrome.paper[1], chrome.paper[2], chrome.paper[3], 0.96)
            g.rectangle("fill", x, y, w, h)
            g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
            g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
            if w > 3 and h > 3 then
                g.rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3)
            end
            local title = self.title or "REACT!"
            g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
            Font.draw(title, x + 6, y + 3)
            local aChoice = choiceForDir("a")
            if self.subtitle and not aChoice then
                local sub = tostring(self.subtitle)
                if #sub > 8 then
                    sub = sub:sub(1, 7) .. "."
                end
                g.setColor(chrome.muted[1], chrome.muted[2], chrome.muted[3], 1)
                Font.draw(sub, x + 58, y + 3)
            end
            if aChoice then
                local aLabel = shortReactLabel(aChoice)
                local selectedA = preferred == aChoice
                if selectedA then
                    g.setColor(chrome.selected[1], chrome.selected[2],
                        chrome.selected[3], 1)
                    g.rectangle("fill", x + w - 58, y + 2, 52, 10)
                end
                if aChoice.disabled then
                    g.setColor(chrome.muted[1], chrome.muted[2], chrome.muted[3], 1)
                else
                    g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
                end
                Font.draw("A", x + w - 56, y + 3)
                g.push()
                g.translate(x + w - 46, y + 3)
                g.scale(0.75, 0.75)
                Font.draw(aLabel, 0, 0)
                g.pop()
            end
            local slots = {
                { dir = "up",    letter = "U", col = 0, row = 0 },
                { dir = "right", letter = "R", col = 1, row = 0 },
                { dir = "left",  letter = "L", col = 0, row = 1 },
                { dir = "down",  letter = "D", col = 1, row = 1 },
            }
            local colW = 74
            for s = 1, #slots do
                local slot = slots[s]
                local choice = choiceForDir(slot.dir)
                if choice then
                    local tx = x + 6 + slot.col * colW
                    local ty = y + 14 + slot.row * 12
                    local selected = preferred == choice
                    if selected then
                        g.setColor(chrome.selected[1], chrome.selected[2],
                            chrome.selected[3], 1)
                        g.rectangle("fill", tx - 2, ty - 1, colW - 4, 11)
                        if type(Font.drawCode) == "function" then
                            g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
                            Font.drawCode(0xED, tx, ty)
                        end
                    end
                    local label = shortReactLabel(choice)
                    if choice.disabled then
                        label = "(" .. label .. ")"
                        g.setColor(chrome.muted[1], chrome.muted[2], chrome.muted[3], 1)
                    else
                        g.setColor(chrome.ink[1], chrome.ink[2], chrome.ink[3], 1)
                    end
                    Font.draw(slot.letter, tx + 12, ty)
                    local scale = (#label > 6) and 0.72 or 0.85
                    g.push()
                    g.translate(tx + 22, ty)
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

        Font.drawBox(tx, ty, tw, th, reactChrome(self.game).fill255)
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
    if not RD() then
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
        local actions = RD().menuActions(battle, pendingMove)
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
        state.awaitingPick = "react"
        state.pendingDamage = { ctx = ctx, record = record }
        state.pickOfferedThisTurn = true
        battle._arPickOfferedThisTurn = true
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
