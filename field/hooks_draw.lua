-- Field battle — BattleState draw wraps, overlay, present clock, mouse look.
--
-- Loaded by field/init.lua and attached onto Hooks. Install is idempotent
-- via the same _arFbv* guards as the composer in hooks.lua.

return function(Hooks)
function Hooks.installDraw(FBV, mod, ctx)
    ctx = ctx or {}
    local isFieldBattle = ctx.isFieldBattle or function() return false end

    -- Peek around the fight while the mouse is moving. Idle → auto camera.
    do
        local okG, Game = pcall(require, "src.core.Game")
        if okG and type(Game) == "table" and not Game._arFbvMouseLook then
            local origMove = Game.mousemoved
            function Game:mousemoved(x, y, dx, dy, ...)
                if FBV.enabled(mod) and type(FBV.tryMouseLook) == "function" then
                    FBV.tryMouseLook(self, x, y, dx, dy)
                end
                if type(origMove) == "function" then
                    return origMove(self, x, y, dx, dy, ...)
                end
            end
            Game._arFbvMouseLook = true
        end
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
                    -- SPEC: suppress classic move paint. Engine anim rows still
                    -- advance for timing + SFX; world FX come from projectiles.lua.
                    return
                end
                return origAnim(self, colorized, ...)
            end

            BattleState._arFbvAnim21 = true
        end

        -- _arFbvDraw23 also drops translucent attack flashes (issue #12).
        if type(BattleState.drawClassic) == "function" and not BattleState._arFbvDraw23 then
            local origDraw = BattleState.drawClassic
            function BattleState:drawClassic(...)
                if not isFieldBattle(self) then
                    return origDraw(self, ...)
                end
                self.showPlayerBack = false
                self.showEnemyTrainer = false
                self.introBalls = false
                self.introSlide = 0
                self.letterboxWhite = false
                self.isOpaque = false
                local g = love.graphics
                local rectangle = g.rectangle
                g.rectangle = function(mode, x, y, w, h, ...)
                    local r, gr, b, a = g.getColor()
                    local drop = Hooks.shouldDropFieldFill(mode, x, y, w, h, r, gr, b, a)
                    if drop then
                        if drop == "clear" then
                            local target = g.getCanvas()
                            if target ~= nil
                                and (target == self.bgCanvas or target == self.waveCanvas) then
                                g.clear(0, 0, 0, 0)
                            end
                        end
                        return
                    end
                    return rectangle(mode, x, y, w, h, ...)
                end
                local okDraw, err = pcall(origDraw, self, ...)
                g.rectangle = rectangle
                if not okDraw then
                    error(err, 0)
                end
            end

            BattleState._arFbvDraw23 = true
            BattleState._arFbvDraw = true
        end

        -- Screen-shake zone fills are color 0 (white). Invisible on the classic
        -- field; a flickering sheet over the live map.
        if type(BattleState.drawZonePass) == "function" and not BattleState._arFbvZone23 then
            local origZone = BattleState.drawZonePass
            function BattleState:drawZonePass(...)
                if not isFieldBattle(self) then
                    return origZone(self, ...)
                end
                local g = love.graphics
                local rectangle = g.rectangle
                g.rectangle = function(mode, ...)
                    if mode == "fill" then
                        return
                    end
                    return rectangle(mode, ...)
                end
                local okZ, err = pcall(origZone, self, ...)
                g.rectangle = rectangle
                if not okZ then
                    error(err, 0)
                end
            end

            BattleState._arFbvZone23 = true
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
                if type(FBV.fieldAllowsStackedBottomUI) == "function"
                    and FBV.fieldAllowsStackedBottomUI(battle) then
                    return true
                end
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
                if type(FBV.unwedgeVoxelPass) == "function" then
                    pcall(FBV.unwedgeVoxelPass, mod)
                end
                if not FBV.enabled(mod) then
                    error(a, 0)
                end
                a = nil
            elseif FBV.enabled(mod)
                and type(FBV.liveBattle) == "function"
                and type(FBV.drawWorldOverlay) == "function" then
                local battle = select(1, FBV.liveBattle(self.game or gameSingleton()))
                if battle and isFieldBattle(battle) then
                    pcall(FBV.drawWorldOverlay, battle)
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
                and type(FBV.liveBattle) == "function" then
                local battle = select(1, FBV.liveBattle(game))
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

end
end
