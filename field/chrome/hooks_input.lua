-- Field battle — BattleState update wrap (menu latch, pause, directional cast).
--
-- Loaded by field/init.lua and attached onto Hooks. `_arFbvUpdate` means
-- this wrap is already on BattleState.update for this process.

return function(Hooks)
function Hooks.installInput(FBV, mod, ctx)
    ctx = ctx or {}
    local isFieldBattle = ctx.isFieldBattle or function() return false end
    local focusEntrenched = ctx.focusEntrenched or function() return false end
    local playerLikelyGoesSecond = ctx.playerLikelyGoesSecond
        or function() return false end

    local function dumpAndThrow(battle, tag, err)
        if FBV.Log and type(FBV.Log.err) == "function" then
            pcall(FBV.Log.err, battle, tag, err)
        else
            pcall(print, "[ar] ERR " .. tostring(tag), tostring(err))
        end
        -- FIELD: rethrowing mid-voxel makes Love return 1 with no error screen.
        if not FBV.enabled(mod) then
            error(tostring(err), 0)
        end
    end

    local ok, BattleState = pcall(require, "src.battle.BattleState")
    if ok and type(BattleState) == "table" then
        -- Stick FIELD menu/pause/cast onto BattleState.update, once.
        if type(BattleState.update) == "function" and not BattleState._arFbvUpdate then
            local origUpdate = BattleState.update
            function BattleState:update(dt, ...)
                if isFieldBattle(self) then
                    self.showPlayerBack = false
                    self.showEnemyTrainer = false
                    self.letterboxWhite = false

                    local input = self.game and self.game.input

                    local swallowPause = false
                    local swallowB = false
                    local phaseBefore = self.phase
                    local pressedA = false
                    if input and type(input.wasPressed) == "function" then
                        pressedA = input:wasPressed("a") == true
                    end
                    local entrenched = focusEntrenched(self)
                    local mustSwitch = Hooks.playerMustSwitch(self)
                    local foeDown = Hooks.foeIsDown(self)
                    local awaitCallout = self._arAwaitCallout == true
                    local slowerWait = (not awaitCallout)
                        and playerLikelyGoesSecond(self) == true

                    -- Issue #6: fainted player cannot be stuck on the move diamond.
                    -- Delayed CLOSE THE GAP KOs must also drop the diamond so the
                    -- engine faint / send-out script can run.
                    if mustSwitch then
                        self._arFieldPreferMoves = nil
                        self._arFieldCommandHold = true
                        if self.phase == "moveSelect" or self.phase == "mimicSelect" then
                            self.phase = "menu"
                            self.menuIndex = self.menuIndex or 2
                            self.moveSwapIndex = nil
                        end
                    elseif foeDown then
                        if self._arAwaitAgain then
                            self._arAwaitCallout = nil
                            self._arAwaitAgain = nil
                            self._arAwaitAgainSide = nil
                        end
                        self._arFieldPreferMoves = nil
                        self._arFieldCommandHold = true
                        if self.phase == "moveSelect" or self.phase == "mimicSelect" then
                            self.phase = "messages"
                            self.moveSwapIndex = nil
                        end
                    end

                    -- `_arFieldPreferMoves`: sticky after FIGHT until PAUSE.
                    if self.phase == "messages" then
                        self._arFieldCommandHold = nil
                    end

                    -- PAUSE = B (edge), only on the move diamond / sticky command.
                    -- Delayed callout after going second cannot pause back to FIGHT.
                    local pauseEdge = (not awaitCallout)
                        and Hooks.fieldPausePressed(input, self)
                    if pauseEdge and Hooks.applyFieldPause(self) then
                        swallowPause = true
                    elseif awaitCallout and not mustSwitch and not foeDown
                        and not self.safari and not self.demo
                        and self.player and self.player.curMoves
                        and #(self.player.curMoves) > 0 then
                        self.phase = "moveSelect"
                        local n = #self.player.curMoves
                        self.moveIndex = math.min(self.moveIndex or 1, n)
                        self.moveSwapIndex = nil
                        self._arFieldPreferMoves = true
                        self._arFieldCommandHold = nil
                    elseif slowerWait and self.phase == "menu" then
                        -- Faster foe is about to move: stay on FIGHT/PKMN/BAG/RUN.
                        self._arFieldPreferMoves = nil
                        self._arFieldCommandHold = true
                    elseif self.phase == "menu" and self._arFieldPreferMoves
                        and not entrenched and not mustSwitch and not foeDown
                        and not slowerWait
                        and not self.safari and not self.demo
                        and self.player and self.player.curMoves
                        and #(self.player.curMoves) > 0 then
                        -- Reopen the diamond after FIGHT (skip while ENTRENCHED so
                        -- FIGHT can open the HOLD/BREAK menu in main.lua).
                        self.phase = "moveSelect"
                        local n = #self.player.curMoves
                        self.moveIndex = math.min(self.moveIndex or 1, n)
                        self.moveSwapIndex = nil
                        self._arFieldCommandHold = nil
                    elseif self.phase == "menu" and not self._arFieldPreferMoves then
                        -- Soft hold so nested older wraps don't auto-jump to moves.
                        self._arFieldCommandHold = true
                    end

                    if self.phase == "moveSelect" and self._arFieldPreferMoves then
                        swallowB = true
                    end

                    -- DIAMOND only: U/R/L/D picks that slot and confirms.
                    -- CLASSIC is a 2×2 cursor (move_grid_navigation) + A.
                    -- REACT! owns the same D-pad while it is on the stack;
                    -- do not also instant-confirm a move on that click.
                    local stackedMenu = false
                    do
                        local stack = self.game and self.game.stack
                        local top = stack and type(stack.top) == "function"
                            and stack:top()
                        stackedMenu = top ~= nil and top ~= self
                    end
                    if type(FBV.moveHudStyle) == "function"
                        and FBV.moveHudStyle(mod) == "DIAMOND"
                        and (self.phase == "moveSelect" or self.phase == "mimicSelect")
                        and not stackedMenu
                        and not self._arAwaitingReact then
                        if input and type(input.wasPressed) == "function" then
                            local moves = self.phase == "mimicSelect"
                                and (self.mimicMoves or {})
                                or (self.player and self.player.curMoves or {})
                            local instantIdx = nil
                            if input:wasPressed("up") and moves[1] then
                                instantIdx = 1
                            elseif input:wasPressed("right") and moves[2] then
                                instantIdx = 2
                            elseif input:wasPressed("left") and moves[3] then
                                instantIdx = 3
                            elseif input:wasPressed("down") and moves[4] then
                                instantIdx = 4
                            end
                            if instantIdx then
                                if self.phase == "mimicSelect" then
                                    self.mimicIndex = instantIdx
                                else
                                    self.moveIndex = instantIdx
                                end
                                self._arFieldInstantMove = true
                            end
                        end
                    end

                    if type(FBV.tickPresent) == "function" then
                        local okT, errT = pcall(FBV.tickPresent, self.game, dt)
                        if not okT then
                            dumpAndThrow(self, "tickPresent", errT)
                        end
                    elseif type(FBV.tickActive) == "function" then
                        local okT, errT = pcall(FBV.tickActive, self.game, dt)
                        if not okT then
                            dumpAndThrow(self, "tickActive", errT)
                        end
                    else
                        local okT, errT = pcall(FBV.tick, self, dt)
                        if not okT then
                            dumpAndThrow(self, "tick", errT)
                        end
                    end

                    -- Arm the close-the-gap walk before origUpdate so engine
                    -- applyDamage / runDamaging on this confirm frame are held.
                    if self._arFieldInstantMove and type(FBV.react) == "function" then
                        local moves = self.player and self.player.curMoves
                        local move = moves and moves[self.moveIndex]
                        local cat = move and tostring(move.category or ""):lower()
                        local special = cat == "special"
                        if not special and move and move.type then
                            local okD, Damage = pcall(require, "src.battle.Damage")
                            if okD and Damage and type(Damage.isSpecial) == "function" then
                                local okS, isSp = pcall(Damage.isSpecial, move.type)
                                special = okS and isSp and true or false
                            end
                        end
                        local damaging = move and ((move.power or 0) > 0
                            or move.fixedDamage)
                            and cat ~= "status"
                        local melee = damaging and not special
                        if damaging and type(FBV.isMeleeAttack) == "function" then
                            melee = FBV.isMeleeAttack({
                                category = special and "special" or "physical",
                                moveId = move.id,
                                moveType = move.type,
                            })
                        end
                        if damaging then
                            pcall(FBV.react, self, "player", "attack", {
                                category = special and "special" or "physical",
                                moveType = move.type,
                                moveId = move.id,
                                movePower = move.power,
                            })
                        end
                    end

                    local result
                    if (self._arFieldInstantMove or swallowPause or swallowB) and input then
                        local origWasPressed = input.wasPressed
                        local injectA = self._arFieldInstantMove and true or false
                        input.wasPressed = function(inp, key)
                            if injectA and key == "a" then
                                return true
                            end
                            if injectA and (key == "up" or key == "down"
                                    or key == "left" or key == "right") then
                                return false
                            end
                            if (swallowB or swallowPause) and key == "b" then
                                return false
                            end
                            return origWasPressed(inp, key)
                        end
                        local okU, a, b, c = pcall(origUpdate, self, dt, ...)
                        input.wasPressed = origWasPressed
                        self._arFieldInstantMove = nil
                        if not okU then
                            dumpAndThrow(self, "BattleState.update", a)
                        end
                        result = { a, b, c }
                    else
                        local okU, a, b, c = pcall(origUpdate, self, dt, ...)
                        if not okU then
                            dumpAndThrow(self, "BattleState.update", a)
                            return
                        end
                        result = { a, b, c }
                    end

                    -- FIGHT (menu → moveSelect via A) latches move mode.
                    if phaseBefore == "menu" and self.phase == "moveSelect" and pressedA
                        and not mustSwitch and not foeDown and not slowerWait then
                        self._arFieldPreferMoves = true
                        self._arFieldCommandHold = nil
                    end
                    -- Also latch when COVER!/ENTRENCH! STRIKE/EMERGE/BREAK called
                    -- goMoveSelect (phase becomes moveSelect without our A).
                    if self.phase == "moveSelect" and not entrenched
                        and not mustSwitch and not foeDown and not slowerWait
                        and (phaseBefore == "menu" or pressedA) then
                        self._arFieldPreferMoves = true
                        self._arFieldCommandHold = nil
                    end

                    return result[1], result[2], result[3]
                end
                return origUpdate(self, dt, ...)
            end

            BattleState._arFbvUpdate = true
        end
    end
end
end
