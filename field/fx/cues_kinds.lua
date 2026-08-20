-- Field battle — what each beat looks like on the pad.
--
-- One function per kind. Cues.apply in cues.lua just looks up the name
-- and runs it. This is the file to open when an attack, dodge, hit, or
-- faint looks wrong.
--
--   dodge / cover / hide / brace   REACT! movement and pose
--   cast                           overlapping FIRE pose (shot is the attack cue)
--   attack                         physicals walk in; specials cast in place
--                                  (Dig/Fly charge turns vanish instead)
--   status                         in-place cast + orbit FX (Growl, Toxic, …)
--   hit / selfhit                  knockback or a stumble (confusion / recoil)
--   miss                           accuracy whiff: slip-past pose + MISS chip
--   vanish / emerge                Dig underground, Fly into the sky, then return
--   faint / recall                 HP hit zero: sink, or the red return laser
--
-- Adding a new beat: Cues.register("mykind", function(session, side, …) … end)
-- Keep the handler small. Shared helpers (which mon, play an anim, log) live
-- on Cues._H in cues.lua.

return function(Cues)
    local H = Cues._H

    local function playRangedCast(session, side, ent, foe, Grid, g, opts, category, battle)
        local Projectiles = session._deps and session._deps.Projectiles
        local Audio = session._deps and session._deps.Audio
        H.note(session, battle or session._battle, "cue path", side,
            opts.moveId or "-", "cast", H.padSnap(ent))
        if Audio and type(Audio.playMove) == "function" then
            pcall(Audio.playMove, battle or session._battle, opts.moveId,
                side == "player")
        end
        ent._returnAt = nil
        ent._attackStepped = nil
        if Projectiles and type(Projectiles.move) == "function" then
            local jump = type(Grid.pathObstructed) == "function"
                and Grid.pathObstructed(g, ent, foe)
            local slow = opts.slowShot == true or opts.fireCarry == true
            if slow then
                session._fireShotSlow = true
            end
            Projectiles.move(session, side, {
                category = category or "special",
                jump = jump,
                moveType = opts.moveType,
                moveId = opts.moveId,
                slowShot = slow,
            })
            session._fireShotSlow = nil
        end
        H.playAnim(ent, "cast")
    end

    local function armCloseGap(session, side, ent, foe, Grid, g, opts, thisId, jump, closed, stepped, battle)
        ent._savedStepSpeed = ent.stepSpeed
        local Projectiles = session._deps and session._deps.Projectiles
        Cues.armCloseGapGait(ent, battle or session._battle, side, foe, {
            Projectiles = Projectiles,
            now = H.now(session),
        })
        ent._pendingCloseStrike = {
            moveType = opts.moveType,
            moveId = thisId,
            movePower = opts.movePower,
            jump = jump,
        }
        -- Already next to the foe: punch on the next present tick, do not
        -- burn a "walk first" frame (that stall is most obvious on your mon).
        -- If the player could FIRE NOW, keep a wind-up so the charge reads.
        local fireWait = ent._closeGapMinAt ~= nil
        ent._closeStrikeWait = (not Cues.inMeleeReach(ent, foe)) or fireWait
        ent._closeStrikeArmedAt = H.now(session)
        ent._returnAt = nil
        ent._withdrawAfterStrike = true

        local dist = "-"
        if foe and type(Grid.padDistance) == "function" then
            dist = tostring(Grid.padDistance(g, ent, foe) or "-")
        end

        H.note(session, battle or session._battle, "cue path", side, thisId or "-",
            "walk", closed and "gap" or (stepped and "step" or "stay"),
            "dist=" .. dist, H.padSnap(ent), H.padSnap(foe))
    end

    local function playImmediateMelee(session, side, ent, opts, jump, stepped, battle)
        local Projectiles = session._deps and session._deps.Projectiles
        local Audio = session._deps and session._deps.Audio
        if Projectiles and type(Projectiles.contact) == "function" then
            Projectiles.contact(session, side, {
                moveType = opts.moveType,
                moveId = opts.moveId,
            })
        end
        if Audio and type(Audio.playMove) == "function" then
            pcall(Audio.playMove, battle or session._battle, opts.moveId,
                side == "player")
        end
        if stepped then
            ent._returnAt = H.now(session) + H.playMeleeStrike(session, side, ent, opts, jump)
        else
            H.playMeleeStrike(session, side, ent, opts, jump)
            ent._returnAt = Cues.isTossMove(opts) and (H.now(session) + Cues.TOSS_DUR) or nil
        end
    end

    local function playMeleeApproach(session, side, ent, foe, Grid, g, opts, battle)
        -- Extra swings (multi-hit, Again!, REACT counter after a punch, nameless
        -- toasts) stay in melee. One close-the-gap walk per side per turn.
        local thisId = H.cueMoveId(opts)
        local inPlace = opts.followUp or opts.again
            or H.hasStruckThisTurn(ent) or (ent._pendingCloseStrike and true)
        if inPlace then
            local why = opts.followUp and "follow"
                or opts.again and "again"
                or H.hasStruckThisTurn(ent) and "struck"
                or "pending"
            H.note(session, battle or session._battle, "cue path", side, thisId or "-",
                "inPlace", why, H.padSnap(ent))
            H.playMeleeContact(session, side, ent, opts, ent._attackJump)
            return
        end

        local delayStrike = Cues.closeTheGapEnabled(session, opts)
            and not opts.releaseStrike
        -- Physical: mon charges (optional close-the-gap, else one step / jump).
        -- Jump only when cover blocks the path — already-adjacent mons attack in place.
        local obstructed = type(Grid.pathObstructed) == "function"
            and Grid.pathObstructed(g, ent, foe)
        local jump = obstructed == true
        ent._attackJump = jump and true or nil
        local closed = false
        if Cues.closeTheGapEnabled(session, opts)
            and type(Grid.closeGap) == "function" then
            local okC, did = pcall(Grid.closeGap, g, ent, foe)
            if not okC then
                H.noteErr(session, battle, "cue.closeGap", did)
            else
                closed = did == true
            end
        end
        local stepped = closed
        if not stepped and type(Grid.attackStep) == "function" then
            local okS, didS = pcall(Grid.attackStep, g, ent, foe)
            if not okS then
                H.noteErr(session, battle, "cue.attackStep", didS)
            else
                stepped = didS == true
            end
        end
        ent._attackStepped = stepped

        -- "Close the gap" handles movement: the announce cue begins the approach;
        -- punch and engine damage wait until the sprite is in range.
        if delayStrike then
            armCloseGap(session, side, ent, foe, Grid, g, opts, thisId, jump, closed, stepped, battle)
        else
            playImmediateMelee(session, side, ent, opts, jump, stepped, battle)
        end
    end

    Cues.register("dodge", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        opts = opts or {}
        Grid.dodge(session.grid, ent, H.foeOf(session, side))
        -- Pose variety (type / speed / cycle) is picked inside play("dodge").
        H.playAnim(ent, "dodge")
        Cues.fireDodgeCounterShot(session, side, opts)
        return true
    end)

    local function cover(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        local foe = H.foeOf(session, side)
        local g = session.grid
        local tucked = false
        if type(Grid.seekCover) == "function" then
            tucked = Grid.seekCover(g, ent, foe) == true
        end
        if not tucked and type(Grid.seekWallCover) == "function" then
            tucked = Grid.seekWallCover(g, ent, foe) == true
        end
        if tucked then
            H.playAnim(ent, "cover")
        else
            Grid.dodge(g, ent, foe)
            print("H:", H)
            H.playAnim(ent, "dodge")
        end
        return true
    end
    Cues.register("cover", cover)
    Cues.register("hide", cover)

    Cues.register("brace", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        H.playAnim(ent, "brace")
        return true
    end)

    Cues.register("cast", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        H.playAnim(ent, "cast")
        return true
    end)

    Cues.register("status", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        opts = opts or {}
        local Projectiles = session._deps and session._deps.Projectiles
        local Audio = session._deps and session._deps.Audio
        if Audio and type(Audio.playMove) == "function" then
            pcall(Audio.playMove, battle or session._battle, opts.moveId,
                side == "player")
        end
        if Projectiles and type(Projectiles.status) == "function" then
            Projectiles.status(session, side, opts)
        end
        H.playAnim(ent, "cast")
        return true
    end)

    Cues.register("vanish", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        opts = opts or {}
        local flavor = opts.vanish or Cues.vanishKind(opts.moveId) or "dig"
        ent._vanishKind = flavor
        ent._fieldVanished = nil
        ent._emerging = nil
        ent._pendingReleaseAttack = nil
        ent._returnAt = nil
        ent._arFieldDetached = nil
        ent.hidden = false
        local Projectiles = session._deps and session._deps.Projectiles
        if Projectiles and type(Projectiles.vanish) == "function" then
            Projectiles.vanish(session, side, flavor)
        end
        H.playAnim(ent, flavor == "fly" and "vanish_fly" or "vanish_dig")
        return true
    end)

    Cues.register("emerge", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        opts = opts or {}
        local flavor = opts.vanish or ent._vanishKind
            or Cues.vanishKind(opts.moveId) or "dig"
        ent._vanishKind = flavor
        ent._emerging = true
        ent._arFieldDetached = nil
        ent.hidden = false
        ent.drawScale = ent.drawScale or 1
        local Projectiles = session._deps and session._deps.Projectiles
        if Projectiles and type(Projectiles.emerge) == "function" then
            Projectiles.emerge(session, side, flavor)
        end
        H.playAnim(ent, flavor == "fly" and "emerge_fly" or "emerge_dig")
        return true
    end)

    Cues.register("attack", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        opts = opts or {}
        local foe = H.foeOf(session, side)
        local g = session.grid
        local category = H.normCategory(opts.category)

        -- Dig / Fly charge turn: disappear instead of striking.
        if not opts.releaseStrike then
            local charging, flavor = H.isChargeTurn(ent, opts.moveId)
            if charging then
                return Cues.apply(session, side, "vanish", Grid, nudgeCamera, battle, {
                    vanish = flavor,
                    moveId = opts.moveId,
                    moveType = opts.moveType,
                })
            end
            -- Release strike while still hidden: emerge, then strike shortly after.
            if (ent._fieldVanished or ent.hidden) and Cues.vanishKind(opts.moveId) then
                ent._pendingReleaseAttack = {
                    category = category,
                    moveType = opts.moveType,
                    moveId = opts.moveId,
                }
                ent._releaseAt = H.now(session) + 0.28
                return Cues.apply(session, side, "emerge", Grid, nudgeCamera, battle, {
                    vanish = ent._vanishKind or Cues.vanishKind(opts.moveId),
                    moveId = opts.moveId,
                })
            end
        end
        if type(nudgeCamera) == "function" and battle then
            local foeSide = (side == "player") and "enemy" or "player"
            nudgeCamera(battle, foeSide, 0.45)
        end
        -- Physical: close distance on the pad, then return home.
        -- Special: hold cell; still play an in-place cast anim.
        -- Travel FX (beams, Night Shade, …) fly even when the Gen1 type split
        -- marks the move physical. Contact FX (Bite, Fire Punch) walk in even
        -- when that split marks them special.
        local Projectiles = session._deps and session._deps.Projectiles
        if not Cues.isMeleeAttack(opts, Projectiles) then
            playRangedCast(session, side, ent, foe, Grid, g, opts, category, battle)
        else
            playMeleeApproach(session, side, ent, foe, Grid, g, opts, battle)
        end
        if battle and battle._arCounterClash then
            battle._arCounterClash = nil
            H.clashFocus(session, side, opts)
        end
        return true
    end)

    Cues.register("counter", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        opts = opts or {}
        local shot = session._dodgeCounterShot
        local mid = H.cueMoveId(opts)
        local Projectiles = session._deps and session._deps.Projectiles
        local ranged = Cues.isRangedCounter({
            moveId = opts.moveId,
            moveType = opts.moveType,
            category = opts.category,
        }, Projectiles)
        if shot and shot.side == side and (not mid or shot.moveId == mid) then
            session._dodgeCounterShot = nil
            H.playAnim(ent, "cast")
            return true
        end
        if ranged then
            Cues.fireDodgeCounterShot(session, side, {
                counterMoveId = opts.moveId,
                counterMoveType = opts.moveType,
                counterCategory = opts.category or "special",
            })
            H.playAnim(ent, "cast")
            return true
        end
        H.clashFocus(session, side, opts)
        H.playAnim(ent, "counter")
        return true
    end)

    Cues.register("hit", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        opts = opts or {}
        if battle and battle._arPendingBraceCounter and side == "player"
            and not battle._arPendingBraceCounter.fireAt then
            battle._arPendingBraceCounter.fireAt = H.now(session) + 0.34
        end
        local finishing = opts.finishing == true
        print("[ar] finishing: ", finishing)
        if finishing then
            local atkSide = (side == "player") and "enemy" or "player"
            H.finishingFocus(session, atkSide, opts)
        end
        -- FIRE NOW that connected: knock the charger off the line.
        if battle and battle._arFireNow then
            local charger = battle._arFireNowCharger or "enemy"
            if side == charger then
                local foe = H.foeOf(session, side)
                Cues.cancelCloseStrike(session, side, Grid)
                if Grid and type(Grid.knockbackTiles) == "function" then
                    Grid.knockbackTiles(session.grid, ent, foe, 2)
                end
                ent._heavyHit = true
                local Projectiles = session._deps and session._deps.Projectiles
                if Projectiles and type(Projectiles.powerHit) == "function" then
                    Projectiles.powerHit(session, side, opts)
                end
                if Projectiles and type(Projectiles.groundKick) == "function" then
                    Projectiles.groundKick(session, side, opts)
                end
                H.impactKick(session, { powerful = true })
                H.playAnim(ent, "hit")
                return true
            end
        end
        local foe = H.foeOf(session, side)
        local g = session.grid
        local category = H.normCategory(opts.category)
        local clash = opts.clash == true or opts.finishing == true
            or session._clashPunch == true

        if opts.via ~= "toss-land" and not clash
            and (ent.anim == "tossed" or ent.anim == "toss"
                or (foe and (foe.anim == "toss" or foe.anim == "tossed"))) then
            session._pendingTossHit = { side = side, opts = opts }
            return true
        end

        if type(nudgeCamera) == "function" and battle and not clash then
            nudgeCamera(battle, side, 0.35)
        end
        local Audio = session._deps and session._deps.Audio
        if Audio and type(Audio.playHit) == "function" then
            pcall(Audio.playHit, battle or session._battle, opts.typeMult, {
                category = category or session._lastAttackCategory,
            })
        end
        local Projectiles = session._deps and session._deps.Projectiles
        local powerful = Projectiles and type(Projectiles.isPowerfulMove) == "function"
            and Projectiles.isPowerfulMove(opts)
        local crit = opts.crit == true
        H.impactKick(session, { powerful = powerful or crit, clash = clash })
        if clash or powerful or crit then
            local obstacle = Grid.obstacleBehind(g, ent, foe, clash and 1 or 2)
            if crit and Projectiles and type(Projectiles.critBurst) == "function" then
                Projectiles.critBurst(session, side, opts)
            elseif not session._clashHitFx and Projectiles and Projectiles.powerHit then
                Projectiles.powerHit(session, side, opts)
            end
            session._clashHitFx = nil
            Grid.knockbackTiles(g, ent, foe, clash and 1 or 2)
            if obstacle and Projectiles and Projectiles.wallImpact then
                Projectiles.wallImpact(session, obstacle, opts)
            end
            ent._heavyHit = true
            if Projectiles and type(Projectiles.groundKick) == "function" then
                Projectiles.groundKick(session, side, opts)
            end
            H.playAnim(ent, "hit")
            return true
        end
        if Projectiles and type(Projectiles.lightHit) == "function" then
            Projectiles.lightHit(session, side, opts)
        end
        if Projectiles and type(Projectiles.groundKick) == "function" then
            Projectiles.groundKick(session, side, opts)
        end
        local cat = category or session._lastAttackCategory or "physical"
        -- Both can shove; physical more often / more reliably.
        local pushChance = (cat == "special") and 0.45 or 0.78
        if opts.push == false then
            pushChance = 0
        elseif opts.push == true then
            pushChance = 1
        end
        if H.rr() <= pushChance then
            Grid.knockback(g, ent, foe)
        end
        H.playAnim(ent, "hit")
        return true
    end)

    Cues.register("selfhit", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        opts = opts or {}
        -- Confusion / recoil / crash: the user damages itself. Stumble in place
        -- with a bonk burst — never knock away from the foe.
        if type(nudgeCamera) == "function" and battle then
            nudgeCamera(battle, side, 0.22)
        end
        local Audio = session._deps and session._deps.Audio
        if Audio and type(Audio.playHit) == "function" then
            pcall(Audio.playHit, battle or session._battle, opts.typeMult)
        end
        local Projectiles = session._deps and session._deps.Projectiles
        if Projectiles and type(Projectiles.selfHit) == "function" then
            Projectiles.selfHit(session, side)
        end
        H.impactKick(session, { powerful = false })
        H.playAnim(ent, "selfhit")
        return true
    end)

    Cues.register("miss", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        if H.isExitPlaying(ent) then
            return true
        end
        -- Dodge-counter / COUNTER! after a miss always connects. A leftover
        -- "attack missed" tagged on the player must not slip-past that swing
        -- or hop the foe as if they dodged the proc.
        local shot = session._dodgeCounterShot
        if side == "player" and (
            (battle and (battle._arGuaranteedHit or battle._arCounterClash))
            or (shot and shot.side == "player")
        ) then
            return true
        end
        opts = opts or {}
        -- Missed FIRE NOW: keep the shot pose, do not hop the charger aside.
        if battle and (battle._arFireNow or battle._arFireCarryThrough) then
            local Projectiles = session._deps and session._deps.Projectiles
            session._fireShotSlow = true
            if Projectiles and type(Projectiles.move) == "function" and opts.moveId then
                Projectiles.move(session, side, {
                    category = opts.category or "special",
                    moveType = opts.moveType,
                    moveId = opts.moveId,
                    slowShot = true,
                })
            elseif Projectiles and type(Projectiles.miss) == "function" then
                Projectiles.miss(session, side)
            end
            session._fireShotSlow = nil
            H.playAnim(ent, "cast")
            return true
        end
        -- Accuracy miss: no punch, no HP. Convert a close-the-gap walk into
        -- a slip-past, then walk home.
        if ent._pendingCloseStrike then
            H.clearCloseStrike(ent)
            H.restoreStepSpeed(ent)
            ent._withdrawAfterStrike = true
        end
        if battle then
            battle._arAccuracyMissSide = nil
        end
        local UI = session._deps and session._deps.UI
        if UI and type(UI.armStatusChip) == "function" and battle then
            pcall(UI.armStatusChip, battle, side, "MISS")
        end
        local Projectiles = session._deps and session._deps.Projectiles
        if Projectiles and type(Projectiles.miss) == "function" then
            Projectiles.miss(session, side)
        end
        H.playAnim(ent, "miss")
        -- The target hops aside so a miss still reads as a dodge, not a
        -- quiet no-contact. Skip if they already sidestepped this beat.
        local foe = H.foeOf(session, side)
        if foe and foe.anim ~= "dodge" and not H.isExitPlaying(foe) then
            if Grid and type(Grid.dodge) == "function" then
                Grid.dodge(session.grid, foe, ent)
            end
            H.playAnim(foe, "dodge")
        end
        ent._returnAt = H.now(session) + 0.44
        return true
    end)

    Cues.register("faint", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        -- Owned by the HP bar hitting 0, not the "fainted!" dialogue.
        if H.isExitPlaying(ent) then
            return true
        end
        if type(nudgeCamera) == "function" and battle then
            nudgeCamera(battle, side, 0.28)
        end
        local Projectiles = session._deps and session._deps.Projectiles
        if Projectiles and type(Projectiles.faint) == "function" then
            Projectiles.faint(session, side)
        end
        -- Trainer-owned mons get the red recall laser; wild foes keep the sink.
        local beamed = false
        if ent.anim ~= "sendout"
            and Projectiles and type(Projectiles.recallBeam) == "function" then
            beamed = Projectiles.recallBeam(session, side, { target = ent }) ~= nil
        end
        ent._fainting = true
        if beamed then
            H.playAnim(ent, "recall")
        else
            H.playAnim(ent, "faint")
        end
        return true
    end)

    Cues.register("recall", function(session, side, kind, Grid, nudgeCamera, battle, opts)
        local ent = H.sideEnt(session, side)
        if not ent then
            return false
        end
        if H.isExitPlaying(ent) then
            return true
        end
        -- Don't shrink the live foe while the player is calling in.
        if side == "enemy" then
            local player = session.playerMon
            if (session.awaitPlayerMon or session._playerSendLockT
                    or (player and player.anim == "sendout")) then
                return true
            end
        end
        local Projectiles = session._deps and session._deps.Projectiles
        if Projectiles and type(Projectiles.recallBeam) == "function" then
            Projectiles.recallBeam(session, side, { target = ent })
        end
        H.playAnim(ent, "recall")
        return true
    end)
end
