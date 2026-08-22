-- Field battle — walking up to the foe before the punch.
--
-- Physical attacks do not land from across the pad. The attacker walks
-- (or jumps cover) until they are next to the target, then they swing.
-- This file owns that walk: start it, cancel it, punch when they arrive,
-- and hold the HP bar / knockback until the fist actually connects.
--
-- The battle engine often reports "you hit" while the sprite is still
-- crossing the grass. If we applied damage then, Body Slam would shove
-- someone who has not been punched yet. So we stash that hit here and
-- flush it at the punch.
--
-- Open this file when close-the-gap is punching too early, walking
-- forever, or leaking into the next turn. The walk itself is armed from
-- the attack handler in cues_kinds.lua; the per-frame "have they arrived?"
-- check is in cues_tick.lua.

return function(Cues)
    local H = Cues._H

    --- damage_dealt often fires while CLOSE THE GAP is still walking (applyDamage
    --- reports the hit so the engine can continue). Hold the FIELD shove until
    --- the punch, or Body Slam etc. never push.
    function Cues.holdCloseHit(session, side, opts)
        if not (session and side) then
            return false
        end
        session._pendingCloseHit = { side = side, opts = type(opts) == "table" and opts or {} }
        return true
    end

    function Cues.flushCloseHit(session, Grid)
        local hit = session and session._pendingCloseHit
        if not hit then
            return false
        end
        session._pendingCloseHit = nil
        Grid = Grid or (session._deps and session._deps.Grid)
        if not (hit.side and Grid) then
            return false
        end
        return Cues.apply(session, hit.side, "hit", Grid, nil, session._battle, hit.opts or {})
            and true or false
    end

    function H.clearCloseStrike(ent)
        if not ent then
            return
        end
        ent._pendingCloseStrike = nil
        ent._closeStrikeDeadline = nil
        ent._closeStrikeWait = nil
        ent._closeStrikeArmedAt = nil
        ent._closeGapMinAt = nil
        ent._closeGapCruise = nil
        ent._closeGapStart = nil
        ent._closeGapSpan = nil
        ent._cuttingHaze = nil
        ent._hazeSlow = nil
        ent._hazeStuckAt = nil
        ent._hazeChipped = nil
    end

    function H.fireCloseStrike(session, side, ent, Grid)
        if not ent then
            return
        end
        local pending = ent._pendingCloseStrike
        local mid = pending and pending.moveId and tostring(pending.moveId):upper() or nil
        if mid == "" then
            mid = nil
        end
        local foe = H.foeOf(session, side)
        local dist = "-"
        local G = Grid or (session and session._deps and session._deps.Grid)
        if foe and G and type(G.padDistance) == "function" then
            dist = tostring(G.padDistance(session.grid, ent, foe) or "-")
        end
        H.note(session, session and session._battle, "closeStrike", side, mid,
            "dist=" .. dist, H.describeEnt(session, ent, side))
        local battle = session and session._battle
        if battle and battle._arAccuracyMissSide == side then
            battle._arAccuracyMissSide = nil
            Cues.apply(session, side, "miss", Grid, nil, battle, {
                via = "close-miss",
                moveId = mid,
            })
            return
        end
        if mid then
            H.markStruck(ent, mid)
        end
        H.clearCloseStrike(ent)
        local deps = session and session._deps
        local Projectiles = deps and deps.Projectiles
        local Audio = deps and deps.Audio
        if pending and Audio and type(Audio.playMove) == "function" then
            pcall(Audio.playMove, battle, pending.moveId, side == "player")
        end
        if pending then
            Cues.cutLaneHaze(session, side, Grid, pending)
        end
        if pending and Projectiles and type(Projectiles.contact) == "function" then
            Projectiles.contact(session, side, pending)
        end
        local jump = (pending and pending.jump) or ent._attackJump
        local held = session._pendingCloseHit
        local finishing = held and held.opts and held.opts.finishing == true
        if Cues.isTossMove(pending) then
            H.playTossPair(session, side)
            if finishing and side == "player" then
                H.finishingFocus(session, side, held.opts)
            end
            ent._returnAt = H.now(session) + Cues.TOSS_DUR
        elseif finishing and side == "player" then
            H.finishingFocus(session, side, held.opts)
            ent._returnAt = H.now(session) + (jump and 0.56 or 0.48)
        else
            H.playAnim(ent, jump and "jump" or "attack")
            ent._returnAt = H.now(session) + (jump and 0.56 or 0.48)
        end
        -- Shove now that occupancy is adjacent. damage_dealt during the walk
        -- was stashed; a replay after this is skipped by shouldSkipEvent.
        Cues.flushCloseHit(session, Grid)
        Cues.flushHeldHit(session, battle)
    end

    --- True while CLOSE THE GAP still owns the physical beat.
    function Cues.closeGapHoldActive(session)
        if not (session and session.live) then
            return false
        end
        local battle = session._battle
        if Cues.awaitingReact(battle) then
            return true
        end
        if not Cues.closeTheGapEnabled(session) then
            return false
        end
        local p, e = session.playerMon, session.enemyMon
        return (p and p._pendingCloseStrike) or (e and e._pendingCloseStrike) or false
    end

    --- Park updateQueue during the walk so Harden cannot start — except while
    --- REACT is waiting. That menu is a queue `ui` row; parking it deadlocks
    --- (punch waits for the menu, menu waits for the queue).
    function Cues.shouldParkEngineQueue(session)
        if not (session and session.live) then
            return false
        end
        local battle = session._battle
        if battle and battle._arCloseGapResuming then
            return false
        end
        if Cues.awaitingReact(battle) then
            return false
        end
        if Cues.awaitingCallout(battle) then
            return true
        end
        if battle and battle._arPendingBraceCounter then
            return true
        end
        if Cues.tossAirPending(session) then
            return true
        end
        local p, e = session.playerMon, session.enemyMon
        return (p and p._pendingCloseStrike) or (e and e._pendingCloseStrike) or false
    end

    --- Drop a close-the-gap walk without punching (REACT dodge miss / cancelled hit).
    function Cues.cancelCloseStrike(session, side, Grid)
        local ent = H.sideEnt(session, side)
        if not ent or not ent._pendingCloseStrike then
            return false
        end
        H.clearCloseStrike(ent)
        H.restoreStepSpeed(ent)
        ent._withdrawAfterStrike = true
        ent._returnAt = H.now(session)
        return true
    end

    --- FIRE NOW connected: stop the charge and shove the charger back.
    --- CHECK uses 1 tile; a connecting special uses 2.
    function Cues.interruptCharge(session, side, Grid, tiles)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        local wasCharging = ent._pendingCloseStrike ~= nil
        Cues.cancelCloseStrike(session, side, Grid)
        if not wasCharging then
            return false
        end
        Grid = Grid or (session._deps and session._deps.Grid)
        local foe = H.foeOf(session, side)
        tiles = tonumber(tiles) or 2
        if tiles < 1 then
            tiles = 1
        end
        if Grid and type(Grid.knockbackTiles) == "function" then
            Grid.knockbackTiles(session.grid, ent, foe, tiles)
        end
        ent._heavyHit = true
        H.playHitAnim(ent)
        return true
    end

    --- A close-gap walk that leaked into the next turn (foe Harden while
    --- Scratch was still walking). Punch if already adjacent, else cancel
    --- and flush the held HP so the next swing starts clean.
    function Cues.settleOrphanCloseGap(session, battle, Grid)
        if not (session and session.live) then
            return false
        end
        Grid = Grid or (session._deps and session._deps.Grid)
        local settled = false
        for _, side in ipairs({ "player", "enemy" }) do
            local ent = H.sideEnt(session, side)
            if ent and ent._pendingCloseStrike then
                local mid = ent._pendingCloseStrike.moveId
                local foe = H.foeOf(session, side)
                local punch = Cues.inMeleeReach(ent, foe)
                H.note(session, battle, "settleGap", side, mid or "-",
                    punch and "punch" or "cancel", H.padSnap(ent))
                if punch then
                    H.fireCloseStrike(session, side, ent, Grid)
                else
                    Cues.cancelCloseStrike(session, side, Grid)
                end
                settled = true
            end
        end
        if settled then
            Cues.flushHeldHit(session, battle)
        end
        return settled
    end

    --- Drop leftover close-gap punch clocks at turn start. Opening home
    --- stays the idle roam so the next CALL decides whether they close.
    function Cues.resetTurnSide(session, side, keep, _)
        local ent = H.sideEnt(session, side)
        if not ent or keep then
            return false
        end
        H.clearCloseStrike(ent)
        ent._closeStruckMoveId = nil
        ent._struckMoves = nil
        H.restoreStepSpeed(ent)
        ent._returnAt = nil
        ent._withdrawAfterStrike = nil
        ent._meleeAnchor = nil
        return true
    end

    --- True while a physical closer is still walking; engine damage must wait.
    function Cues.shouldHoldEngineHit(session, ctx)
        if not Cues.closeGapHoldActive(session) then
            return false
        end
        local user = ctx and ctx.user
        if not user then
            return true
        end
        local side = user.isPlayer and "player" or "enemy"
        local ent = H.sideEnt(session, side)
        return ent and ent._pendingCloseStrike and true or false
    end

    --- Hold the charger's punch HP. A FIRE NOW bolt into the charger lands now.
    function Cues.shouldHoldApplyDamage(session, battle, target)
        if not (session and battle) then
            return false
        end
        if battle._arFireNow or battle._arCloseGapResuming then
            return false
        end
        if not Cues.closeGapHoldActive(session) then
            return false
        end
        local playerCharging = session.playerMon and session.playerMon._pendingCloseStrike
        local enemyCharging = session.enemyMon and session.enemyMon._pendingCloseStrike
        if enemyCharging and not playerCharging then
            return target == battle.player
        end
        if playerCharging and not enemyCharging then
            return target == battle.enemy
        end
        return true
    end

    --- Normalize one held `{ ctx, record }` or a list of them.
    local function heldRunList(held)
        if type(held) ~= "table" then
            return nil
        end
        if held.ctx then
            return { held }
        end
        if #held > 0 then
            return held
        end
        return nil
    end

    local function battlerHpDown(b)
        if not b then
            return false
        end
        local hp = (b.mon and b.mon.hp) or b.hp
        return type(hp) == "number" and hp <= 0
    end

    local function battlerShownDown(b)
        if not b then
            return false
        end
        local hp = (b.mon and b.mon.hp) or b.hp
        local shown = b.shownHP
        return (type(hp) == "number" and hp <= 0)
            or (type(shown) == "number" and shown <= 0)
    end

    --- Resume engine HP / hit that waited for the close-the-gap punch.
    function Cues.flushHeldHit(session, battle)
        if not battle then
            return false
        end
        local p, e = session and session.playerMon, session and session.enemyMon
        if (p and p._pendingCloseStrike) or (e and e._pendingCloseStrike) then
            return false
        end
        local runs = heldRunList(battle._arCloseGapDamage)
        local stashed = battle._arCloseGapApply
        if not runs and (type(stashed) ~= "table" or #stashed == 0) then
            return false
        end
        battle._arCloseGapDamage = nil
        battle._arCloseGapApply = nil
        -- Punch already applied this when Grid was available. If not, shove
        -- before HP replay so a second damage_dealt cannot double-push.
        Cues.flushCloseHit(session, session._deps and session._deps.Grid)
        battle._arCloseGapResuming = true
        local replayedRun = runs and true or false
        H.note(session, battle, "flushHeldHit", replayedRun and "runDamaging" or "applyDamage")
        if replayedRun then
            -- Resume the engine (or close-gap's orig), never the live React wrap.
            -- Calling EffectRegistry.runDamaging here re-entered AUTO counter / Again!
            -- after FURY_ATTACK and armed a second closeStrike.
            local okE, registry = pcall(require, "src.battle.EffectRegistry")
            local react = okE and registry and registry._arReactRunDamaging
            local function usable(fn)
                return type(fn) == "function" and fn ~= react
            end
            local run = okE and registry and (
                (usable(registry._arEngineRunDamaging) and registry._arEngineRunDamaging)
                or (usable(registry._arVanillaRunDamaging) and registry._arVanillaRunDamaging)
            )
            if type(run) == "function" then
                for i = 1, #runs do
                    local held = runs[i]
                    if type(held) == "table" and held.ctx then
                        local okR, errR = pcall(run, battle, held.ctx, held.record)
                        if not okR then
                            H.noteErr(session, battle, "flushHeldHit.runDamaging", errR)
                        end
                    end
                end
            end
        elseif type(stashed) == "table" and type(battle.applyDamage) == "function" then
            for i = 1, #stashed do
                local args = stashed[i]
                if type(args) == "table" then
                    local okA, errA = pcall(battle.applyDamage, battle, unpack(args))
                    if not okA then
                        H.noteErr(session, battle, "flushHeldHit.applyDamage", errA)
                    end
                end
            end
            -- applyDamage alone does not run the engine faint script.
            if type(battle.onFaint) == "function" then
                if battlerHpDown(battle.player) then
                    pcall(battle.onFaint, battle, battle.player)
                end
                if battlerHpDown(battle.enemy) then
                    pcall(battle.onFaint, battle, battle.enemy)
                end
            end
        end
        battle._arCloseGapResuming = nil
        -- Sticky FIELD diamond must not cover faint / send-out.
        if battlerShownDown(battle.player) or battlerShownDown(battle.enemy) then
            battle._arFieldPreferMoves = nil
            battle._arFieldCommandHold = true
            if battle.phase == "moveSelect" or battle.phase == "mimicSelect" then
                battle.phase = battlerShownDown(battle.player) and "menu" or "messages"
            end
        end
        return true
    end
end
