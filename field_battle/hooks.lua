-- Field battle — BattleState presentation hooks + events + standalone intercept.
--
-- Responsibilities:
--   • Suppress classic/Stadium move paint; FIELD FX come from projectiles.lua
--   • Drive present-clock ticks so idle bob keeps moving under menus
--   • FIELD input UX on top of vanilla BattleState phases:
--       - Start on FIGHT / PKMN / ITEM / RUN until the player picks FIGHT
--       - After FIGHT, keep opening the move diamond each turn until PAUSE
--       - Right Shift = PAUSE back to the command menu (clears move latch)
--       - While ENTRENCHED, stay on command so FIGHT opens HOLD/BREAK
--       - U/R/L/D instantly cast that slot (inject A) while on the diamond
--   • Redraw compact UI last so Move Inspector / typed-move panels cannot cover it
--   • Forward battle.* cues into Lifecycle / Cues / Projectiles
--
-- Install is idempotent via _arFbv* guards; bump the update guard when the
-- BattleState:update wrap must replace an older FIELD wrap after hot reload.

local Hooks = {}

function Hooks.install(FBV, mod)
    if not mod then
        return false
    end
    mod._arFieldBattleViewerInstalled = true

    local Compat = FBV and FBV.Compat
    local function isFieldBattle(self)
        if Compat and type(Compat.isFieldBattle) == "function" then
            return Compat.isFieldBattle(self, FBV, mod)
        end
        if not self then
            return false
        end
        if self._arAnimeField or self._arFieldCombat or self._arFieldStandalone then
            return true
        end
        return FBV and mod and type(FBV.shouldUse) == "function"
            and FBV.shouldUse(mod, self)
    end

    if FBV and FBV.Intercept and type(FBV.Intercept.install) == "function" then
        pcall(FBV.Intercept.install, FBV, mod)
    end

    if Compat and type(Compat.suppressDramaticShape) == "function" then
        pcall(Compat.suppressDramaticShape, FBV, mod)
    end
    if FBV and FBV.Audio and type(FBV.Audio.installEngineMute) == "function" then
        pcall(FBV.Audio.installEngineMute)
    end
    FBV.suppressForeignStages = function()
        if Compat and type(Compat.suppressDramaticShape) == "function" then
            Compat.suppressDramaticShape(FBV, mod)
        end
    end

    -- Latch Right Shift for PAUSE (move diamond → command menu).
    -- Wait until a trainer has made move
    do
        local okG, Game = pcall(require, "src.core.Game")
        if okG and type(Game) == "table" and type(Game.keypressed) == "function" and not Game._arFbvRShiftLatch then
            local origKey = Game.keypressed
            function Game:keypressed(key, ...)
                if key == "rshift" then
                    mod._arFieldShiftEdge = true
                end
                return origKey(self, key, ...)
            end

            Game._arFbvRShiftLatch = true
        end
    end

    local function focusEntrenched(battle)
        -- Entrench used to eat PreferMoves attacks via executeAction → holdPosition.
        -- We still avoid auto-opening the diamond so FIGHT can show ENTRENCH!.
        local pkgs = mod and mod._arPackages
        local RD = pkgs and pkgs.battle and pkgs.battle.ReactiveDefense
        if not (RD and type(RD.sideState) == "function" and battle) then
            return false
        end
        local ok, side = pcall(RD.sideState, battle, true)
        return ok and side and side.entrenched == true and (side.entrenchTurns or 0) > 0
    end

    -- ---- BattleState presentation wraps (pics / HUD / world bg) ----
    local ok, BattleState = pcall(require, "src.battle.BattleState")
    if ok and type(BattleState) == "table" then
        if type(BattleState.bgMode) == "function" and not BattleState._arFbvBgMode then
            local origBg = BattleState.bgMode
            function BattleState:bgMode()
                if isFieldBattle(self) then
                    return "world"
                end
                return origBg(self)
            end

            BattleState._arFbvBgMode = true
        end

        if type(BattleState.drawPicsLayer) == "function" and not BattleState._arFbvPics then
            local origPics = BattleState.drawPicsLayer
            function BattleState:drawPicsLayer(...)
                if isFieldBattle(self) then
                    return
                end
                return origPics(self, ...)
            end

            BattleState._arFbvPics = true
        end

        if type(BattleState.drawBattlerPic) == "function" and not BattleState._arFbvBattlerPic then
            local origBattler = BattleState.drawBattlerPic
            function BattleState:drawBattlerPic(...)
                if isFieldBattle(self) then
                    return
                end
                return origBattler(self, ...)
            end

            BattleState._arFbvBattlerPic = true
        end

        if type(BattleState.drawHUDs) == "function" and not BattleState._arFbvHud then
            local origHUDs = BattleState.drawHUDs
            function BattleState:drawHUDs(...)
                if isFieldBattle(self) then
                    return
                end
                return origHUDs(self, ...)
            end

            BattleState._arFbvHud = true
        end

        -- Bump guard so hot reload replaces the older affine-remap wrap.
        if type(BattleState.drawAnimLayer) == "function" and not BattleState._arFbvAnim21 then
            local origAnim = BattleState.drawAnimLayer
            function BattleState:drawAnimLayer(colorized, ...)
                if isFieldBattle(self) then
                    -- SPEC: suppress classic/Stadium paint. Engine anim rows still
                    -- advance for timing + SFX; world FX come from projectiles.lua.
                    return
                end
                return origAnim(self, colorized, ...)
            end

            BattleState._arFbvAnim21 = true
        end

        if type(BattleState.drawClassic) == "function" and not BattleState._arFbvDraw then
            local origDraw = BattleState.drawClassic
            function BattleState:drawClassic(...)
                if not isFieldBattle(self) then
                    return origDraw(self, ...)
                end
                self.showPlayerBack = false
                self.showEnemyTrainer = false
                self.introBalls = false
                self.introSlide = 0
                local g = love.graphics
                local rectangle = g.rectangle
                g.rectangle = function(mode, x, y, w, h, ...)
                    if mode == "fill" and x == 0 and y == 0 and w == 160 and h == 144 then
                        local r, gr, b, a = g.getColor()
                        if r > 0.99 and gr > 0.99 and b > 0.99 and (not a or a > 0.99) then
                            local target = g.getCanvas()
                            if target ~= nil
                                and (target == self.bgCanvas or target == self.waveCanvas) then
                                g.clear(0, 0, 0, 0)
                            end
                            return
                        end
                    end
                    return rectangle(mode, x, y, w, h, ...)
                end
                local okDraw, err = pcall(origDraw, self, ...)
                g.rectangle = rectangle
                if not okDraw then
                    error(err, 0)
                end
            end

            BattleState._arFbvDraw = true
        end

        if type(BattleState.wideLayout) == "function" and not BattleState._arFbvWide then
            local origWide = BattleState.wideLayout
            function BattleState:wideLayout(...)
                if isFieldBattle(self) then
                    return false
                end
                return origWide(self, ...)
            end

            BattleState._arFbvWide = true
        end

        -- ---- FIELD turn UX (menu latch + directional cast) ----
        -- _arFbvUpdate22 rebinds even if an older FIELD update wrap was installed.
        if type(BattleState.update) == "function" and not BattleState._arFbvUpdate22 then
            local origUpdate = BattleState.update
            function BattleState:update(dt, ...)
                if isFieldBattle(self) then
                    self.showPlayerBack = false
                    self.showEnemyTrainer = false

                    local input = self.game and self.game.input

                    -- PAUSE = Right Shift (edge), only meaningful on the move diamond.
                    local shiftEdge = mod._arFieldShiftEdge == true
                    mod._arFieldShiftEdge = false
                    do
                        local down = false
                        if love and love.keyboard then
                            local function keyDown(name)
                                local okK, v = pcall(function()
                                    return love.keyboard.isDown(name)
                                end)
                                return okK and v and true or false
                            end
                            local function scanDown(name)
                                if type(love.keyboard.isScancodeDown) ~= "function" then
                                    return false
                                end
                                local okK, v = pcall(function()
                                    return love.keyboard.isScancodeDown(name)
                                end)
                                return okK and v and true or false
                            end
                            down = scanDown("rshift") or keyDown("rshift")
                        end
                        if not shiftEdge then
                            shiftEdge = down and not self._arFieldShiftHeld
                        end
                        self._arFieldShiftHeld = (down or shiftEdge) and true or false
                    end

                    local pauseEdge = shiftEdge
                    local swallowPause = false
                    local swallowB = false
                    local phaseBefore = self.phase
                    local pressedA = false
                    if input and type(input.wasPressed) == "function" then
                        pressedA = input:wasPressed("a") == true
                    end
                    local entrenched = focusEntrenched(self)

                    -- `_arFieldPreferMoves`: sticky after FIGHT until PAUSE.
                    if self.phase == "messages" then
                        self._arFieldCommandHold = nil
                    end

                    if self.phase == "moveSelect" and pauseEdge then
                        self.phase = "menu"
                        self.menuIndex = self.menuIndex or 1
                        self.moveSwapIndex = nil
                        self._arFieldPreferMoves = nil
                        self._arFieldCommandHold = true
                        swallowPause = true
                    elseif self.phase == "menu" and pauseEdge and self._arFieldPreferMoves then
                        self._arFieldPreferMoves = nil
                        self._arFieldCommandHold = true
                        swallowPause = true
                    elseif self.phase == "menu" and self._arFieldPreferMoves
                        and not entrenched
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

                    -- U/R/L/D → that move slot, then inject A so BattleState resolves it.
                    if self.phase == "moveSelect" or self.phase == "mimicSelect" then
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
                        pcall(FBV.tickPresent, self.game, dt)
                    elseif type(FBV.tickActive) == "function" then
                        pcall(FBV.tickActive, self.game, dt)
                    else
                        pcall(FBV.tick, self, dt)
                    end

                    local heldBefore = self._arFieldShiftHeld
                    if swallowPause then
                        self._arFieldShiftHeld = true
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
                            if swallowB and key == "b" then
                                return false
                            end
                            if swallowPause and key == "select" then
                                return false
                            end
                            return origWasPressed(inp, key)
                        end
                        local okU, a, b, c = pcall(origUpdate, self, dt, ...)
                        input.wasPressed = origWasPressed
                        self._arFieldInstantMove = nil
                        if not okU then
                            error(a, 0)
                        end
                        result = { a, b, c }
                    else
                        result = { origUpdate(self, dt, ...) }
                    end

                    self._arFieldShiftHeld = heldBefore

                    -- FIGHT (menu → moveSelect via A) latches move mode.
                    if phaseBefore == "menu" and self.phase == "moveSelect" and pressedA then
                        self._arFieldPreferMoves = true
                        self._arFieldCommandHold = nil
                    end
                    -- Also latch when COVER!/ENTRENCH! STRIKE/EMERGE/BREAK called
                    -- goMoveSelect (phase becomes moveSelect without our A).
                    if self.phase == "moveSelect" and not entrenched
                        and (phaseBefore == "menu" or pressedA) then
                        self._arFieldPreferMoves = true
                        self._arFieldCommandHold = nil
                    end

                    return result[1], result[2], result[3]
                end
                return origUpdate(self, dt, ...)
            end

            BattleState._arFbvUpdate22 = true
            BattleState._arFbvUpdate21 = true
            BattleState._arFbvUpdate20 = true
            BattleState._arFbvUpdate = true
        end

        -- Confusion / recoil / crash lines → self-hit field cue.
        local function wrapSelfHitSay(methodName)
            local guard = "_arFbvSelfHit_" .. methodName
            if type(BattleState[methodName]) ~= "function" or BattleState[guard] then
                return
            end
            local orig = BattleState[methodName]
            BattleState[methodName] = function(self, text, ...)
                local a, b, c = orig(self, text, ...)
                if isFieldBattle(self) and FBV.Cues then
                    if type(FBV.Cues.tagSelfDamage) == "function" then
                        pcall(FBV.Cues.tagSelfDamage, self, text)
                    end
                    if type(FBV.Cues.tagFaint) == "function" then
                        pcall(FBV.Cues.tagFaint, self, text)
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
                if interrupted and isFieldBattle(self) and user
                    and FBV.Cues and type(FBV.Cues.tagSelfDamage) == "function" then
                    pcall(FBV.Cues.tagSelfDamage, self, "hurt itself",
                        user.isPlayer and "player" or "enemy")
                end
                return interrupted
            end
            BattleState._arFbvSelfHitInterrupt = true
        end
    end

    -- ---- Overlay / visibility hooks ----
    -- Draw FIELD chrome last so Move Inspector / typed-move panels cannot cover it.
    if mod.hooks and type(mod.hooks.wrap) == "function"
        and not mod._arFbvOverlayTop then
        mod._arFbvOverlayTop = true
        mod.hooks:wrap("battle.overlay", function(next, battle)
            next(battle)
            if battle and isFieldBattle(battle)
                and FBV and type(FBV.drawUI) == "function" then
                FBV.drawUI(battle)
            end
        end, 12000)
    end

    if mod.hooks and type(mod.hooks.wrap) == "function"
        and not mod._arFbvCompactUiHooks then
        mod._arFbvCompactUiHooks = true
        mod.hooks:wrap("battle.status_hud_visible", function(next, battle)
            if battle and isFieldBattle(battle) then
                return false
            end
            return next(battle)
        end)
        mod.hooks:wrap("battle.bottom_ui_visible", function(next, battle)
            if battle and isFieldBattle(battle) then
                return false
            end
            return next(battle)
        end)
        mod.hooks:wrap("battle.move_grid_navigation", function(next, battle)
            if battle and isFieldBattle(battle) then
                local phase = battle.phase
                return phase == "moveSelect" or phase == "mimicSelect"
            end
            return next(battle)
        end)
    end

    -- ---- Present clock (keep bob alive under menus) ----
    local function presentTick(game, dt)
        if not FBV.enabled(mod) then
            return
        end
        local tick = FBV.tickPresent or FBV.tickActive
        if type(tick) == "function" then
            pcall(tick, game, dt)
        end
    end

    local function frameDt()
        local dt = 1 / 60
        if love and love.timer and type(love.timer.getDelta) == "function" then
            dt = love.timer.getDelta() or dt
        end
        return dt
    end

    local function gameSingleton()
        local okG, Game = pcall(require, "src.core.Game")
        if okG then
            return Game
        end
        return nil
    end

    -- Advance bob BEFORE the world is drawn this frame (letterbox is too late).
    -- Unwedge a voxel pass that threw mid-beginScene. Paint field FX/HP after
    -- the world body so they share the world canvas camera (not the 160×144 UI).
    local function wrapDrawWorld(OverworldState)
        if not (type(OverworldState) == "table"
                and type(OverworldState.drawWorld) == "function"
                and not OverworldState._arFbvPresentDraw21) then
            return
        end
        local origDrawWorld = OverworldState.drawWorld
        function OverworldState:drawWorld(...)
            if FBV.enabled(mod) then
                presentTick(self.game or gameSingleton(), frameDt())
            end
            local ok, a, b, c, d = pcall(origDrawWorld, self, ...)
            if not ok then
                if FBV.Compat and type(FBV.Compat.unwedgeVoxelPass) == "function" then
                    pcall(FBV.Compat.unwedgeVoxelPass, mod)
                end
                if not FBV.enabled(mod) then
                    error(a, 0)
                end
                a = nil
            elseif FBV.enabled(mod)
                and FBV.Lifecycle and type(FBV.Lifecycle.liveBattle) == "function"
                and type(FBV.Lifecycle.drawWorldOverlay) == "function" then
                local battle = select(1, FBV.Lifecycle.liveBattle(self.game or gameSingleton()))
                if battle and isFieldBattle(battle) then
                    pcall(FBV.Lifecycle.drawWorldOverlay, battle)
                end
            end
            return a, b, c, d
        end

        OverworldState._arFbvPresentDraw21 = true
    end
    do
        local okOW, OverworldController = pcall(require, "src.world.OverworldController")
        if okOW then
            wrapDrawWorld(OverworldController)
        end
        local okOS, OverworldState = pcall(require, "src.world.OverworldState")
        if okOS then
            wrapDrawWorld(OverworldState)
        end
    end

    if mod.hooks and type(mod.hooks.wrap) == "function" and not mod._arFbvInputStep then
        mod._arFbvInputStep = true
        mod.hooks:wrap("input.step", function(next, game, dt)
            -- Tick before and after: before covers draw-order races; after covers
            -- BattleState:update work that may have happened inside next().
            presentTick(game, dt)
            local out = next(game, dt)
            presentTick(game, dt)
            return out
        end)
    end

    -- Draw-path fallback: letterbox runs every frame even when PartyMenu /
    -- callout modals sit on top of BattleState (stack only updates the top).
    if mod.hooks and type(mod.hooks.wrap) == "function" and not mod._arFbvLetterbox then
        mod._arFbvLetterbox = true
        mod.hooks:wrap("render.letterbox", function(next, ctx)
            local game = gameSingleton()
            presentTick(game, frameDt())
            next(ctx)
            if not FBV.enabled(mod) then
                return
            end
            presentTick(game, frameDt())
            if type(FBV.drawDebug) == "function"
                and mod.options and type(mod.options.get) == "function"
                and mod.options:get("dev_overlay") == true
                and FBV.Lifecycle and type(FBV.Lifecycle.liveBattle) == "function" then
                local battle = select(1, FBV.Lifecycle.liveBattle(game))
                if battle then
                    pcall(FBV.drawDebug, battle)
                end
            end
        end)
    end

    if mod.hooks and type(mod.hooks.wrap) == "function" and not mod._arFbvOverlay then
        mod._arFbvOverlay = true
        mod.hooks:wrap("battle.overlay", function(next, battle)
            if battle and isFieldBattle(battle) then
                presentTick(battle.game, frameDt())
            end
            next(battle)
            if battle and isFieldBattle(battle) then
                presentTick(battle.game, frameDt())
            end
        end)
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
                if ev.side == "player" or (ev.battler and ev.battler.isPlayer) then
                    battle._arFieldRevealPlayer = true
                end
                pcall(FBV.syncMons, battle, mod)
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
            local status = (move.power or 0) <= 0 or move.category == "status"
            local kind = status and "status" or "attack"
            local skip = false
            if type(FBV.shouldSkipEventReact) == "function" then
                local okS, s = pcall(FBV.shouldSkipEventReact, battle, side, kind)
                skip = okS and s
            end
            if not skip then
                pcall(FBV.react, battle, side, kind, {
                    category = status and "status" or moveCategory(move),
                    moveType = move.type,
                    moveId = move.id,
                })
            end
        end)

        mod.events:on("battle.damage_dealt", function(ev)
            local battle = ev and ev.battle
            if not (battle and isFieldBattle(battle)
                    and ev.target and (ev.damage or 0) > 0) then
                return
            end
            local side = ev.target.isPlayer and "player" or "enemy"
            local skip = false
            if type(FBV.shouldSkipEventReact) == "function" then
                local okS, s = pcall(FBV.shouldSkipEventReact, battle, side, "hit")
                skip = okS and s
            end
            if not skip then
                local cat = moveCategory(ev.move)
                pcall(FBV.react, battle, side, "hit", {
                    category = cat,
                    typeMult = ev.typeMult,
                    moveId = ev.move and ev.move.id,
                    moveType = ev.move and ev.move.type,
                })
            end
        end)

        mod.events:on("battle.fainted", function(ev)
            local battle = ev and ev.battle
            if not (battle and isFieldBattle(battle) and ev.battler) then
                return
            end
            local side = ev.battler.isPlayer and "player" or "enemy"
            pcall(FBV.react, battle, side, "faint")
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

    return true
end

return Hooks
