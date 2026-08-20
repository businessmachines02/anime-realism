-- Field battle — battle.* event fan-out, close-the-gap holds, self-hit cues.
--
-- Loaded by field/init.lua and attached onto Hooks. Guard `_arFbvEvents`
-- keeps install idempotent across mods.loaded / game.ready.

return function(Hooks)
    function Hooks.installEvents(FBV, mod, ctx)
        ctx = ctx or {}
        local isFieldBattle = ctx.isFieldBattle or function() return false end

        local ok, BattleState = pcall(require, "src.battle.BattleState")
        if ok and type(BattleState) == "table" then
            -- Confusion / recoil / crash lines → self-hit field cue.
            local function wrapSelfHitSay(methodName)
                local guard = "_arFbvSelfHit_" .. methodName
                if type(BattleState[methodName]) ~= "function" or BattleState[guard] then
                    return
                end
                local orig = BattleState[methodName]
                BattleState[methodName] = function(self, text, ...)
                    local a, b, c = orig(self, text, ...)
                    if isFieldBattle(self) then
                        if type(FBV.tagSelfDamage) == "function" then
                            pcall(FBV.tagSelfDamage, self, text)
                        end
                        if type(FBV.tagChargeVanish) == "function" then
                            pcall(FBV.tagChargeVanish, self, text)
                        end
                    end
                    return a, b, c
                end
                BattleState[guard] = true
            end
            wrapSelfHitSay("sayNext")
            wrapSelfHitSay("sayNextAuto")

            if type(BattleState.statusInterrupt) == "function"
                and not BattleState._arFbvSelfHitInterrupt then
                local origInterrupt = BattleState.statusInterrupt
                function BattleState:statusInterrupt(user, ...)
                    local interrupted = origInterrupt(self, user, ...)
                    if interrupted and isFieldBattle(self) then
                        self._arAccuracyPred = nil
                        self._arAwaitAccuracyCue = nil
                        if user and type(FBV.tagSelfDamage) == "function" then
                            pcall(FBV.tagSelfDamage, self, "hurt itself",
                                user.isPlayer and "player" or "enemy")
                        end
                    end
                    return interrupted
                end

                BattleState._arFbvSelfHitInterrupt = true
            end
        end

        -- ---- Battle events → Lifecycle / Cues / Projectiles ----
        if mod.events and type(mod.events.on) == "function" and not mod._arFbvEvents then
            mod._arFbvEvents = true

            mod.events:on("battle.started", function(ev)
                local battle = ev and ev.battle
                if not (battle and type(FBV.shouldUse) == "function"
                        and FBV.shouldUse(mod, battle)) then
                    return
                end
                if battle._arFieldBeginDone or (FBV.active and FBV.active(battle)) then
                    return
                end
                battle._arFieldBeginDone = true
                battle._arFieldPreferMoves = nil
                battle._arFieldCommandHold = nil
                if FBV.Log and type(FBV.Log.note) == "function" then
                    pcall(FBV.Log.note, battle, "event.started", "field.begin")
                end
                pcall(FBV.begin, battle, mod)
            end)

            mod.events:on("battle.ended", function(ev)
                local battle = ev and ev.battle
                if battle then
                    battle._arFieldPreferMoves = nil
                    battle._arFieldCommandHold = nil
                    pcall(FBV.finish, battle)
                end
            end)

            mod.events:on("battle.battler_switched", function(ev)
                local battle = ev and ev.battle
                if battle and isFieldBattle(battle) then
                    local side = ev.side
                    if type(side) == "string" then
                        side = side:lower()
                        if side == "ally" then
                            side = "player"
                        elseif side == "foe" or side == "opponent" then
                            side = "enemy"
                        end
                    end
                    if side ~= "player" and side ~= "enemy" then
                        if ev.battler and ev.battler.isPlayer == true then
                            side = "player"
                        elseif ev.battler and ev.battler.isPlayer == false then
                            side = "enemy"
                        else
                            side = nil
                        end
                    end
                    if side == "player" or (ev.battler and ev.battler.isPlayer) then
                        battle._arFieldRevealPlayer = true
                    end
                    pcall(FBV.syncMons, battle, mod, side)
                end
            end)

            local function moveCategory(move)
                if not move then
                    return "physical"
                end
                if move.category == "special" then
                    return "special"
                end
                if move.category == "physical" or move.category == "status" then
                    return "physical"
                end
                local okD, Damage = pcall(require, "src.battle.Damage")
                if okD and Damage and type(Damage.isSpecial) == "function" then
                    local ok, special = pcall(Damage.isSpecial, move.type)
                    if ok and special then
                        return "special"
                    end
                end
                return "physical"
            end

            -- Zero BP is not always a status move: Night Shade / Seismic Toss /
            -- Dragon Rage / etc. deal fixed damage via SPECIAL_DAMAGE_EFFECT.
            local function isStatusMove(move)
                if not move then
                    return true
                end
                if move.category == "status" then
                    return true
                end
                if (move.power or 0) > 0 then
                    return false
                end
                if move.fixedDamage then
                    return false
                end
                local effect = tostring(move.effect or ""):upper()
                if effect == "SPECIAL_DAMAGE_EFFECT"
                    or effect == "SUPER_FANG_EFFECT"
                    or effect == "OHKO_EFFECT" then
                    return false
                end
                return true
            end

            -- Hold engine HP / hit text until CLOSE THE GAP lands. Otherwise the
            -- logic clock resolves the swing while the sprite is still walking.
            do
                local okE, EffectRegistry = pcall(require, "src.battle.EffectRegistry")
                if okE and type(EffectRegistry) == "table"
                    and type(EffectRegistry.runDamaging) == "function"
                    and not EffectRegistry._arFbvCloseGap then
                    local origRun = EffectRegistry.runDamaging

                    -- Prefer vanilla / the function under this wrap. Punch resume
                    -- must not call the live React wrap (AUTO counter / Again!).
                    local react = EffectRegistry._arReactRunDamaging
                    local vanilla = EffectRegistry._arVanillaRunDamaging
                    local stored = EffectRegistry._arEngineRunDamaging

                    if type(stored) ~= "function" or stored == react then
                        if type(vanilla) == "function" and vanilla ~= react then
                            EffectRegistry._arEngineRunDamaging = vanilla
                        elseif origRun ~= react then
                            EffectRegistry._arEngineRunDamaging = origRun
                        end
                    end

                    function EffectRegistry.runDamaging(battle, ctx, record)
                        if battle and battle._arCloseGapResuming then
                            return origRun(battle, ctx, record)
                        end

                        local session = FBV and type(FBV.session) == "function"
                            and FBV.session(battle)

                        if session and type(FBV.shouldHoldEngineHit) == "function"
                            and FBV.shouldHoldEngineHit(session, ctx) then
                            local held = battle._arCloseGapDamage
                            local row = { ctx = ctx, record = record }
                            if type(held) ~= "table" then
                                battle._arCloseGapDamage = { row }
                            elseif held.ctx then
                                battle._arCloseGapDamage = { held, row }
                            else
                                held[#held + 1] = row
                            end
                            -- Engine multi-hit loops add the return; nil crashed
                            -- Fury Attack after the close-gap walk started.
                            return 0
                        end
                        return origRun(battle, ctx, record)
                    end

                    EffectRegistry._arFbvCloseGap = true
                end
            end

            if ok and type(BattleState) == "table" and type(BattleState.applyDamage) == "function" and not BattleState._arFbvApplyDmg
            then
                local origApply = BattleState.applyDamage
                function BattleState:applyDamage(...)
                    if self and self._arCloseGapResuming then
                        return origApply(self, ...)
                    end
                    local session = FBV and type(FBV.session) == "function"
                        and FBV.session(self)
                    if session and type(FBV.closeGapHoldActive) == "function"
                        and FBV.closeGapHoldActive(session) then
                        local args = { ... }
                        self._arCloseGapApply = self._arCloseGapApply or {}
                        self._arCloseGapApply[#self._arCloseGapApply + 1] = args
                        -- Report the hit without changing HP yet.
                        return tonumber(args[2]) or 0
                    end
                    return origApply(self, ...)
                end

                BattleState._arFbvApplyDmg = true
            end


            mod.events:on("battle.move_used", function(ev)
                local battle = ev and ev.battle
                if not (battle and isFieldBattle(battle) and ev.user) then
                    return
                end
                local side = ev.user.isPlayer and "player" or "enemy"
                local move = ev.move
                if not move then
                    return
                end
                -- Dig/Fly emit move_used before the charge flag is set, so an
                -- immediate react would wrongly lunge on the hide turn. Queue
                -- arFieldCue (and charge-text tags) drive vanish / emerge instead.
                if type(FBV.vanishKind) == "function" and FBV.vanishKind(move.id) then
                    return
                end
                local status = isStatusMove(move)
                local kind = status and "status" or "attack"
                local opts = {
                    category = status and "status" or moveCategory(move),
                    moveType = move.type,
                    moveId = move.id,
                    isCalled = ev.isCalled == true,
                    presentationOnly = ev.presentationOnly == true,
                    via = ev.presentationOnly and "cam" or "move_used",
                }
                local skip = opts.presentationOnly
                local hit
                if not skip and type(FBV.predictMoveHit) == "function" then
                    local target = ev.target
                    if not target then
                        target = ev.user.isPlayer and battle.enemy or battle.player
                    end
                    local okH, peeked = pcall(FBV.predictMoveHit, battle,
                        ev.user, target, move)
                    if okH and type(peeked) == "boolean" then
                        hit = peeked
                    end
                end
                if hit == false then
                    kind = "miss"
                end
                if not skip and type(FBV.shouldSkipEventReact) == "function" then
                    local okS, s = pcall(FBV.shouldSkipEventReact, battle, side, kind, opts)
                    skip = okS and s
                end
                if skip then
                    if FBV.Log and type(FBV.Log.note) == "function" then
                        pcall(FBV.Log.note, battle, "move_used skip", side, move.id, kind)
                    end
                else
                    if hit == nil then
                        battle._arAwaitAccuracyCue = {
                            side = side,
                            kind = kind,
                            opts = opts,
                        }
                    end
                    if FBV.Log and type(FBV.Log.note) == "function" then
                        pcall(FBV.Log.note, battle, "move_used", side, move.id, kind)
                    end
                    pcall(FBV.react, battle, side, kind, opts)
                end
            end)

            mod.events:on("battle.damage_dealt", function(ev)
                local battle = ev and ev.battle
                if not (battle and isFieldBattle(battle)
                        and ev.target and (ev.damage or 0) > 0) then
                    return
                end

                local session = FBV and type(FBV.session) == "function"
                    and FBV.session(battle)

                local side = ev.target.isPlayer and "player" or "enemy"

                local cat = moveCategory(ev.move)

                local hitOpts = {
                    category = cat,
                    typeMult = ev.typeMult,
                    moveId = ev.move and ev.move.id,
                    moveType = ev.move and ev.move.type,
                    movePower = ev.move and ev.move.power,
                    crit = ev.crit == true,
                    via = "dmg",
                }

                -- if the mon is still walking in
                -- we want to hold out on actually calling the engine to deal damage.
                if session and type(FBV.shouldHoldEngineHit) == "function" and FBV.shouldHoldEngineHit(session, { user = ev.user })
                then
                    if FBV.Log and type(FBV.Log.note) == "function" then
                        pcall(FBV.Log.note, battle, "dmg hold", side, ev.damage,
                            hitOpts.moveId)
                    end
                    if type(FBV.holdCloseHit) == "function" then
                        FBV.holdCloseHit(session, side, hitOpts)
                    end
                    return
                end

                local skip = false

                if type(FBV.shouldSkipEventReact) == "function" then
                    local okS, s = pcall(FBV.shouldSkipEventReact, battle, side, "hit")
                    skip = okS and s
                end
                if not skip then
                    if FBV.Log and type(FBV.Log.note) == "function" then
                        pcall(FBV.Log.note, battle, "dmg", side, ev.damage,
                            hitOpts.moveId)
                    end
                    pcall(FBV.react, battle, side, "hit", hitOpts)
                end
            end)

            mod.events:on("battle.fainted", function(ev)
                local battle = ev and ev.battle
                if not (battle and isFieldBattle(battle) and ev.battler) then
                    return
                end
                local side = ev.battler.isPlayer and "player" or "enemy"
                -- Dialogue-timed event: only a fallback if the bar is already empty
                -- and watchHpFaint has not played the exit yet.
                if type(FBV.onFainted) == "function" then
                    if FBV.Log and type(FBV.Log.note) == "function" then
                        pcall(FBV.Log.note, battle, "faint", side)
                    end
                    pcall(FBV.onFainted, battle, side)
                else
                    local skip = false
                    if type(FBV.shouldSkipEventReact) == "function" then
                        local okS, s = pcall(FBV.shouldSkipEventReact, battle, side, "faint")
                        skip = okS and s
                    end
                    if not skip then
                        pcall(FBV.react, battle, side, "faint")
                    end
                end
            end)

            mod.events:on("battle.ball_thrown", function(ev)
                local battle = ev and ev.battle
                if battle and isFieldBattle(battle) and type(FBV.capture) == "function" then
                    pcall(FBV.capture, battle, ev)
                end
            end)

            mod.events:on("battle.turn_ended", function(ev)
                local battle = ev and ev.battle
                if battle and isFieldBattle(battle) and FBV.onTurnEnded then
                    pcall(FBV.onTurnEnded, battle)
                end
            end)

            mod.events:on("battle.turn_started", function(ev)
                local battle = ev and ev.battle
                if battle and isFieldBattle(battle) and FBV.onTurnStarted then
                    pcall(FBV.onTurnStarted, battle)
                end
            end)

            mod.events:on("mods.loaded", function()
                pcall(FBV.install, mod)
            end)

            mod.events:on("game.ready", function()
                pcall(FBV.install, mod)
            end)
        end
    end
end
