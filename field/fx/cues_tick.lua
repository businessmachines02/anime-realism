-- Field battle — the every-frame clock for walks, punches, and Dig/Fly.
--
-- Cues.apply starts a beat. This file finishes it over time. Each frame
-- it checks both mons:
--
--   Close-the-gap: if they are still walking, keep closing. When they
--   are in punching range (or they have been walking too long), swing.
--   After the swing, wait a beat and walk home — unless a multi-hit is
--   still going, in which case stay in melee.
--
--   Dig / Fly: if they vanished, strike once they pop back out. While
--   the engine says they are invulnerable, keep the buried / in-the-sky
--   pose. If invulnerability ends with no release (a miss, a cancel),
--   emerge anyway so they are not stuck underground.
--
-- Open this file when someone never punches, never comes home, or stays
-- buried after Dig misses. The walk is armed in cues_kinds.lua; the punch
-- itself is cues_close.lua.

return function(Cues)
    local H = Cues._H

    local function tryCloseGap(session, Grid, ent, foe, battle)
        if not (foe and Grid.padDistance and Grid.padDistance(session.grid, ent, foe) > 1) then
            return
        end
        if type(Grid.closeGap) ~= "function" then
            return
        end
        local okG, errG = pcall(Grid.closeGap, session.grid, ent, foe)
        if not okG then
            H.noteErr(session, battle, "tickReturns.closeGap", errG)
        end
    end

    local function tryPunch(session, side, ent, Grid, battle, tag)
        local okF, errF = pcall(H.fireCloseStrike, session, side, ent, Grid)
        if not okF then
            H.noteErr(session, battle, tag, errF)
        end
    end

    --- Finish delayed attack returns to home cell + Dig/Fly release strikes.
    function Cues.tickReturns(session, Grid)
        if not (session and session.grid) then
            return
        end
        local battle = session._battle
        local t = H.now(session)
        if Grid and type(Grid.tickHaze) == "function" then
            Grid.tickHaze(session.grid, t)
        end
        Cues.tickHeldReact(session, Grid)
        Cues.tickTossLand(session, Grid)
        if session._reactLeadUntil and t >= session._reactLeadUntil then
            session._reactLeadUntil = nil
        end
        local waiting = Cues.reactOutcomePending(session)
        -- FIRE / clash shot was latched on the HUD click; run it here so
        -- performMove cannot mutate sprites after this frame's pose.
        -- Failed dodge/brace waits until they are in your face, then a
        -- short lead so the pose is not the same frame as the hit.
        do
            local resume = battle and battle._arResumeReactPick
            if type(resume) == "function" then
                battle._arResumeArmedAt = battle._arResumeArmedAt or t
                local stuck = (t - battle._arResumeArmedAt)
                    >= (Cues.REACT_RESUME_MAX or 1.25)
                if not waiting or stuck then
                    battle._arResumeReactPick = nil
                    battle._arResumeArmedAt = nil
                    if stuck then
                        session._heldReact = nil
                        session._reactLeadUntil = nil
                        waiting = false
                    end
                    local okR, errR = pcall(resume)
                    if not okR then
                        H.noteErr(session, battle, "resumeReactPick", errR)
                    end
                end
            end
        end
        Cues.tickBraceCounter(session, Grid)
        local whiff = battle and battle._arWhiffCloseStrike
        if whiff then
            local after = battle._arWhiffCloseAfter
            if not (after and t < after) then
                battle._arWhiffCloseStrike = nil
                battle._arWhiffCloseAfter = nil
                Cues.cancelCloseStrike(session, whiff, Grid)
            end
        end
        for _, side in ipairs({ "player", "enemy" }) do
            local ent = H.sideEnt(session, side)
            if ent and ent._pendingCloseStrike then
                local foe = H.foeOf(session, side)
                local onHaze = Grid and type(Grid.isHaze) == "function"
                    and Grid.isHaze(session.grid, ent.padU, ent.padV)
                local hazeAhead = Grid and type(Grid.firstHazeOnPath) == "function"
                    and Grid.firstHazeOnPath(session.grid, ent, foe)
                ent._hazeSlow = (onHaze or hazeAhead) and true or nil
                if onHaze then
                    if not ent._hazeChipped then
                        ent._hazeChipped = true
                        local target = battle and ((side == "player")
                            and battle.player or battle.enemy)
                        if battle and type(battle.applyDamage) == "function"
                            and target then
                            pcall(battle.applyDamage, battle, target, Cues.HAZE_CHIP or 4)
                        elseif type(ent.hp) == "number" then
                            ent.hp = math.max(0, ent.hp - (Cues.HAZE_CHIP or 4))
                        end
                    end
                    local stuck = Grid.hazeAt and Grid.hazeAt(session.grid, ent.padU, ent.padV)
                    if stuck and (tonumber(stuck.density) or 1) >= 2 then
                        ent._hazeStuckAt = ent._hazeStuckAt or t
                    else
                        ent._hazeStuckAt = nil
                    end
                else
                    ent._hazeStuckAt = nil
                end
                Cues.tickCloseGapGait(ent, foe)
                tryCloseGap(session, Grid, ent, foe, battle)
                if ent._closeStrikeWait then
                    -- Cue just armed this tick (HUD confirm / announce). Walk first.
                    ent._closeStrikeWait = nil
                elseif H.fieldMenuOpen(session._battle) then
                    -- REACT! / other menus: keep the walk parked.
                elseif ent._closeGapMinAt and t < ent._closeGapMinAt then
                    -- Slow wind-up so FIRE NOW has a beat to read.
                elseif waiting then
                    -- Dodge/brace is waiting for this arrival; do not punch first.
                elseif battle and battle._arWhiffCloseStrike == side then
                    -- Successful dodge: let the cancel land, do not swing.
                elseif Cues.inMeleeReach(ent, foe) then
                    tryPunch(session, side, ent, Grid, battle, "tickReturns.punch")
                elseif ent._hazeStuckAt then
                    -- Thick smog: do not timeout-punch through the cloud.
                elseif ent._closeStrikeArmedAt
                    and (t - ent._closeStrikeArmedAt) > Cues.closeGapPunchTimeout(ent)
                    and not H.fieldMenuOpen(session._battle) then
                    tryPunch(session, side, ent, Grid, battle, "tickReturns.timeout")
                end
            end
            if ent and ent._pendingCloseStrike then
                -- Still closing; do not walk home yet.
            elseif ent and ent._returnAt and t >= ent._returnAt then
                if ent.anim == "toss" or ent.anim == "tossed" then
                    ent._returnAt = t + 0.08
                elseif Cues.pendingMultiHitFollowUp(session, session._battle, side) then
                    ent._returnAt = t + 0.12
                else
                    ent._returnAt = nil
                    local foe = H.foeOf(session, side)
                    if ent._withdrawAfterStrike then
                        ent._withdrawAfterStrike = nil
                        if foe and type(Grid.withdrawFromFoe) == "function" then
                            Grid.withdrawFromFoe(session.grid, ent, foe, side)
                        end
                    else
                        Grid.returnHome(session.grid, ent)
                    end
                    H.restoreStepSpeed(ent)
                end
            end
            if ent and ent._pendingRangedCast then
                if Cues.stillWalkingToPad(ent) then
                    -- Backing up; charge starts once the feet land.
                    elseif not ent._rangedChargeAt then
                    ent._rangedChargeAt = t + (Cues.RANGED_CHARGE or 0.7)
                    local foe = H.foeOf(session, side)
                    H.faceToward(ent, foe)
                    H.playChargeHold(session, ent)
                elseif t >= ent._rangedChargeAt then
                    local shot = ent._pendingRangedCast
                    H.clearRangedCast(ent)
                    Cues.apply(session, side, "attack", Grid, nil, battle or session._battle, {
                        category = shot.category,
                        moveType = shot.moveType,
                        moveId = shot.moveId,
                        slowShot = shot.slowShot,
                        fireCarry = shot.fireCarry,
                        rangedReady = true,
                        via = "rangedBackstep",
                    })
                end
            end
            if ent and ent._releaseAt and t >= ent._releaseAt then
                ent._releaseAt = nil
                local pending = ent._pendingReleaseAttack
                ent._pendingReleaseAttack = nil
                ent._fieldVanished = nil
                ent._emerging = nil
                ent._arFieldDetached = nil
                ent.hidden = false
                if pending then
                    Cues.apply(session, side, "attack", Grid, nil, session._battle, {
                        category = pending.category,
                        moveType = pending.moveType,
                        moveId = pending.moveId,
                        releaseStrike = true,
                        via = "release",
                    })
                end
            end
        end
        local holdUntil = session._rangedHoldUntil
        if holdUntil and t >= holdUntil
            and not Cues.rangedCastHoldActive(session)
            and not Cues.rangedHoldHasProjectile(session) then
            session._rangedHoldUntil = nil
            Cues.releaseRangedShotHold(session, battle)
        end
    end

    --- Keep Dig/Fly users in buried/aloft holds while semi-invulnerable; emerge
    --- if the invuln flag cleared without a release cue (miss / cancel / faint).
    function Cues.syncSemiInvuln(session, Grid)
        if not (session and session.live) then
            return
        end
        for _, side in ipairs({ "player", "enemy" }) do
            local ent = H.sideEnt(session, side)
            if not ent or ent._removed or ent._fainting then
                -- fall through
            else
                local battler = ent._battleBattler
                local flavor = H.battlerChargingVanish(battler)
                if flavor then
                    ent._sawVanishInvuln = true
                    ent._vanishKind = flavor
                    local anim = ent.anim or ""
                    if not ent._fieldVanished
                        and anim ~= "vanish_dig" and anim ~= "vanish_fly"
                        and anim ~= "buried" and anim ~= "aloft" then
                        Cues.apply(session, side, "vanish", Grid, nil, session._battle, {
                            vanish = flavor,
                        })
                    elseif ent._fieldVanished then
                        -- Stay on the cast with a hold pose (dirt hole / sky circle).
                        ent.hidden = false
                        ent._arFieldDetached = nil
                        local hold = (flavor == "fly") and "aloft" or "buried"
                        if anim ~= hold and anim ~= "vanish_dig" and anim ~= "vanish_fly"
                            and anim ~= "emerge_dig" and anim ~= "emerge_fly" then
                            if type(ent.play) == "function" then
                                ent:play(hold)
                            else
                                ent.anim = hold
                            end
                        end
                    end
                elseif ent._fieldVanished and ent._sawVanishInvuln
                    and not ent._emerging
                    and not ent._pendingReleaseAttack and not ent._releaseAt then
                    -- Invulnerability ended without a queued release strike (miss/cancel).
                    ent._sawVanishInvuln = nil
                    Cues.apply(session, side, "emerge", Grid, nil, session._battle, {
                        vanish = ent._vanishKind or "dig",
                    })
                end
            end
        end
    end
end
