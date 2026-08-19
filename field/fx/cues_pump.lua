-- Field battle — when to play the beat that is sitting on the queue.
--
-- The battle engine lines up messages ("PIKACHU used SURF!", "Foe dodged!").
-- Each line can carry a field cue. This file watches the live line and
-- plays that cue at the right time — it does not decide how the beat looks
-- (that is cues_kinds.lua).
--
-- Three jobs:
--   1. Play the current line's cue (attack, status, …). Faint/recall lines
--      are ignored here; those sprites fire when the HP bar hits zero.
--   2. Play the foe's dodge/brace on the SAME beat as the attack, even if
--      that "Move!" line is still waiting in the queue. Otherwise Surf
--      would finish before the dodge starts.
--   3. Multi-hit moves (Pin Missile, Fury Attack, …): the first swing is
--      the announce. Each extra engine animation row replays contact FX
--      in place, without walking in a second time.
--
-- Open this file when a dodge is late, a faint laser replays on the next
-- mon, or only the first hit of a multi-strike is visible.

return function(Cues)
    local H = Cues._H

    local function pushPinnedCallout(session, text, kind)
        local Callouts = session and session._deps and session._deps.Callouts
        if not (Callouts and type(Callouts.push) == "function" and text) then
            return
        end
        -- Pinned orders are already known NPC speech; do not re-filter.
        pcall(Callouts.push, session, "foe", text, {
            kind = kind or "order",
            urgent = true,
        })
    end

    function Cues.pumpOverlapReacts(session, battle, Grid, nudgeCamera)
        if not (session and session.live and battle) then
            return false
        end
        local cur = battle.current
        local attack = cur and cur.arFieldCue
        if not attack then
            return false
        end
        local attackKind = tostring(attack.kind or "")
        if attackKind ~= "attack" and attackKind ~= "status" then
            return false
        end

        local applied = false
        local function fire(react, row)
            if not react or react._arOverlapDone then
                return
            end
            if not Cues.isReactKind(react.kind) then
                return
            end
            react._arOverlapDone = true
            if row then
                row._arFieldCueDone = true
                row._arOverlapShown = true
            end
            Cues.apply(session, react.side, react.kind, Grid, nudgeCamera, battle, {
                category = react.category,
                moveType = react.moveType,
                moveId = react.moveId,
                via = "overlap",
            })
            local Callouts = session._deps and session._deps.Callouts
            if Callouts and type(Callouts.push) == "function" and react.text
                and react.side == "enemy" and react.bubble ~= "narrator"
                and (type(Callouts.isTrainerSpeech) ~= "function"
                    or Callouts.isTrainerSpeech(react.text)) then
                pcall(Callouts.push, session, "foe", react.text, {
                    kind = "react",
                    urgent = true,
                })
            end
            applied = true
        end

        local attached = cur.arOverlapReact
        if type(attached) == "table" then
            for i = 1, #attached do
                fire(attached[i], nil)
            end
        end

        local opposite = (attack.side == "player") and "enemy" or "player"
        local q = battle.queue
        if type(q) == "table" then
            for i = 1, math.min(6, #q) do
                local row = q[i]
                local cue = row and row.arFieldCue
                if cue and not row._arFieldCueDone and cue.side == opposite
                    and Cues.isReactKind(cue.kind) then
                    fire({
                        side = cue.side,
                        kind = cue.kind,
                        text = row.text,
                        bubble = row.bubble,
                    }, row)
                elseif cue and (cue.kind == "attack" or cue.kind == "status") then
                    break
                end
            end
        end
        return applied
    end

    --- Drain one-shot cue from battle.current when it becomes active.
    -- Faint / recall are HP-bar events (`shownHP` → 0), not dialogue. The
    -- "fainted!" line often becomes current after the sprite is gone — applying
    -- it then would replay the laser on the replacement mon.
    -- Dodge / brace / cover attached to this attack (or sitting in the next
    -- queue rows) fire on the same beat so they overlap the travel FX.
    function Cues.pumpCurrent(session, battle, Grid, nudgeCamera)
        local cur = battle and battle.current
        local cue = cur and cur.arFieldCue
        local applied = false
        local called = false
        local awaiting = battle and battle._arAwaitAccuracyCue
        local kind = cue and tostring(cue.kind or "") or ""
        -- move_used peeked nil, so the accuracy wrap still owns this swing.
        -- Pumping the announce toast here lunged (and punched) before the
        -- roll; a later miss then looked like a connected hit that failed.
        local holdForAccuracy = awaiting and cue
            and awaiting.side == cue.side
            and (kind == "attack" or kind == "status")
        -- Open the foe order first so the gray box is up a beat before the FX.
        if cur and cur.arNpcCallout and not cur._arNpcCalloutDone then
            cur._arNpcCalloutDone = true
            called = true
            pushPinnedCallout(session, cur.arNpcCallout, cur.arNpcCalloutKind or "order")
        end
        if cur and cue and not cur._arFieldCueDone then
            cur._arFieldCueDone = true
            if not holdForAccuracy then
                local pumpOpts = {
                    category = cue.category,
                    moveType = cue.moveType,
                    moveId = cue.moveId,
                    vanish = cue.vanish,
                    again = cue.again,
                    isCalled = cue.isCalled,
                    clash = cue.clash == true,
                    releaseStrike = cue.releaseStrike,
                    followUp = cue.followUp,
                    via = "pump",
                }
                if kind ~= "faint" and kind ~= "recall"
                    and not Cues.shouldSkipEvent(session, cue.side, kind, pumpOpts) then
                    applied = Cues.apply(session, cue.side, cue.kind, Grid, nudgeCamera, battle, pumpOpts)
                        and true or false
                end
            end
        end
        -- Overlap dodge/brace onto the live swing (including a close-gap walk, and
        -- late-attached reacts after the announce). After the punch, leftover
        -- queue reacts must not replay onto the foe's counter.
        local overlapped = false
        local attackEnt
        if cue and (cue.side == "player" or cue.side == "enemy") then
            attackEnt = H.sideEnt(session, cue.side)
        end
        local punched = H.hasStruckThisTurn(attackEnt)
            and not (attackEnt and attackEnt._pendingCloseStrike)
        if not punched and not holdForAccuracy then
            overlapped = Cues.pumpOverlapReacts(session, battle, Grid, nudgeCamera)
        end
        return applied or overlapped or called
    end

    local function followUpAnimRow(row, moveId, wantPlayer)
        if not row or not row.anim then
            return false
        end
        if tostring(row.anim):upper() ~= moveId then
            return false
        end
        if not Cues.isEngineMoveAnim(row.anim) then
            return false
        end
        return (row.attackerIsPlayer == true) == wantPlayer
    end

    --- True while extra multi-hit engine anims (or the live clip) still belong
    --- to this side — hold withdraw so the combo stays in melee.
    function Cues.pendingMultiHitFollowUp(session, battle, side)
        if not (session and battle and side) then
            return false
        end
        local moveId = session._multiHitMoveId
        if not moveId or session._multiHitSide ~= side then
            return false
        end
        if not Cues.isMultiHitMove(moveId) then
            return false
        end
        local wantPlayer = side == "player"
        if battle.animPlaying and Cues.isEngineMoveAnim(battle.animName)
            and tostring(battle.animName):upper() == moveId
            and (battle.animAttackerIsPlayer == true) == wantPlayer then
            return true
        end
        local q = battle.queue
        if type(q) ~= "table" then
            return false
        end
        for i = 1, #q do
            local row = q[i]
            if followUpAnimRow(row, moveId, wantPlayer) and not row._arFieldFollowUpDone then
                return true
            end
        end
        return false
    end

    --- Replay FIELD contact/cast on each extra engine anim row (issue #16).
    -- Hit 1 is the announce / close-the-gap punch; later `{ anim = move.id }`
    -- rows are the remaining strikes. Engine queue already waits on each
    -- anim + HP drain, so we only have to paint the world FX on those beats.
    function Cues.pumpFollowUpAnims(session, battle, Grid, nudgeCamera)
        if not (session and session.live and battle) then
            return false
        end
        local moveId, isPlayer, item
        local q1 = battle.queue and battle.queue[1]
        if q1 and not q1._arFieldFollowUpDone and Cues.isEngineMoveAnim(q1.anim) then
            moveId = tostring(q1.anim):upper()
            isPlayer = q1.attackerIsPlayer == true
            item = q1
        elseif battle.animPlaying and Cues.isEngineMoveAnim(battle.animName) then
            moveId = tostring(battle.animName):upper()
            isPlayer = battle.animAttackerIsPlayer == true
            local key = moveId .. ":" .. (isPlayer and "P" or "E")
            if session._arFollowUpAnimKey == key then
                return false
            end
        else
            if not battle.animPlaying then
                session._arFollowUpAnimKey = nil
            end
            return false
        end

        if not Cues.isMultiHitMove(moveId) then
            return false
        end
        if session._lastCueMoveId ~= moveId then
            return false
        end
        local side = isPlayer and "player" or "enemy"
        if session._lastCueSide ~= side then
            return false
        end

        if item then
            item._arFieldFollowUpDone = true
        end
        session._arFollowUpAnimKey = moveId .. ":" .. (isPlayer and "P" or "E")

        -- Engine hit-1 anim is the swing FIELD already presented.
        if session._arSkipEngineStrike then
            session._arSkipEngineStrike = nil
            return false
        end

        local opts = {
            category = session._lastAttackCategory,
            moveId = moveId,
            moveType = session._lastCueMoveType,
            followUp = true,
            via = "followUp",
        }
        Cues.apply(session, side, "attack", Grid, nudgeCamera, battle, opts)
        local foeSide = (side == "player") and "enemy" or "player"
        Cues.apply(session, foeSide, "hit", Grid, nudgeCamera, battle, {
            category = opts.category,
            moveId = moveId,
            moveType = opts.moveType,
            followUp = true,
            push = false,
        })
        return true
    end
end
