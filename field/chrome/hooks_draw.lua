-- Field battle — BattleState draw wraps, overlay, present clock, mouse look.
--
-- Loaded by field/init.lua and attached onto Hooks. Install is idempotent
-- via the same _arFbv* guards as the composer in chrome/hooks.lua.

return function(Hooks)
function Hooks.installDraw(FBV, mod, ctx)
    ctx = ctx or {}
    local isFieldBattle = ctx.isFieldBattle or function() return false end

    local function dumpAndThrow(battle, tag, err)
        if FBV.Log and type(FBV.Log.err) == "function" then
            pcall(FBV.Log.err, battle, tag, err)
        end
        error(tostring(err), 0)
    end

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

        -- Do not run the classic SGB pipeline (bgCanvas, applyWavy, zone
        -- shader, white 160×144 fill) over the live voxel world. Hits arm
        -- shake/wavy; that GL mix aborts Love with no error screen and looks
        -- like "a random attack crashed". Overlay still paints compact UI.
        if type(BattleState.drawClassic) == "function" and not BattleState._arFbvDraw25 then
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
                if type(self.drawTextArea) == "function" then
                    local okT, errT = pcall(self.drawTextArea, self)
                    if not okT then
                        dumpAndThrow(self, "drawTextArea", errT)
                    end
                end
                local okRT, Runtime = pcall(require, "src.core.Runtime")
                if okRT and Runtime and type(Runtime.call) == "function" then
                    local okO, errO = pcall(Runtime.call, "battle.overlay",
                        function() end, self)
                    if not okO then
                        dumpAndThrow(self, "battle.overlay", errO)
                    end
                elseif FBV and type(FBV.drawUI) == "function" then
                    local okU, errU = pcall(FBV.drawUI, self)
                    if not okU then
                        dumpAndThrow(self, "drawUI", errU)
                    end
                end
            end

            BattleState._arFbvDraw25 = true
            BattleState._arFbvDraw24 = true
            BattleState._arFbvDraw23 = true
            BattleState._arFbvDraw = true
        end

        if type(BattleState.drawZonePass) == "function" and not BattleState._arFbvZone24 then
            local origZone = BattleState.drawZonePass
            function BattleState:drawZonePass(...)
                if isFieldBattle(self) then
                    return
                end
                return origZone(self, ...)
            end
            BattleState._arFbvZone24 = true
            BattleState._arFbvZone23 = true
        end

        if type(BattleState.applyWavy) == "function" and not BattleState._arFbvWavy then
            local origWavy = BattleState.applyWavy
            function BattleState:applyWavy(src, ...)
                if isFieldBattle(self) then
                    return src
                end
                return origWavy(self, src, ...)
            end
            BattleState._arFbvWavy = true
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
                if phase ~= "moveSelect" and phase ~= "mimicSelect" then
                    return false
                end
                return type(FBV.moveHudStyle) == "function"
                    and FBV.moveHudStyle(mod) == "DIAMOND"
            end
            return next(battle)
        end)
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

    -- ---- Present clock (keep bob alive under menus) ----
    -- PR #58 split this across input.step (×2), letterbox (×2), overlay (×2),
    -- and drawWorld. A slow later-battle frame passes the 8ms debounce and
    -- applies dt twice — attacks look bouncy, and punch+withdraw+next cue
    -- collapse onto one voxel pose. One tick per display frame.
    local presentGen = 0
    local presentOpened = false
    local function openPresentFrame()
        if not presentOpened then
            presentGen = presentGen + 1
            presentOpened = true
        end
    end
    local function presentTick(game, dt)
        if not FBV.enabled(mod) then
            return
        end
        openPresentFrame()
        local tick = FBV.tickPresent or FBV.tickActive
        if type(tick) ~= "function" then
            return
        end
        local session = nil
        if type(FBV.liveBattle) == "function" then
            local battle = select(1, FBV.liveBattle(game or gameSingleton()))
            session = battle and FBV.session and FBV.session(battle)
        end
        if session and session._arPresentGen == presentGen then
            return
        end
        if session then
            session._arPresentGen = presentGen
        end
        local ok, err = pcall(tick, game, dt)
        if not ok then
            dumpAndThrow(nil, "presentTick", err)
        end
    end

    -- Advance bob BEFORE the world is drawn this frame (letterbox is too late).
    -- Unwedge a voxel pass that threw mid-beginScene. Paint field FX/HP after
    -- the world body so they share the world canvas camera (not the 160×144 UI).
    local function wrapDrawWorld(OverworldState)
        if not (type(OverworldState) == "table"
                and type(OverworldState.drawWorld) == "function"
                and not OverworldState._arFbvPresentDraw26) then
            return
        end
        local origDrawWorld = OverworldState.drawWorld
        function OverworldState:drawWorld(...)
            -- Do not tick here. Update/input already advance the present
            -- clock. Ticking inside draw mutates ow.entities on the same
            -- frame Dramatic Shape poses them (NaN/nil → native GL abort).
            local ok, a, b, c, d = pcall(origDrawWorld, self, ...)
            if not ok then
                if type(FBV.unwedgeVoxelPass) == "function" then
                    pcall(FBV.unwedgeVoxelPass, mod)
                end
                -- Swallow on FIELD: a Lua throw mid-beginScene cannot run
                -- love.errorhandler and aborts the process instead.
                if FBV.enabled(mod) then
                    if FBV.Log and type(FBV.Log.err) == "function" then
                        pcall(FBV.Log.err, nil, "drawWorld", a)
                    end
                else
                    dumpAndThrow(nil, "drawWorld", a)
                end
                a = nil
            elseif FBV.enabled(mod)
                and type(FBV.liveBattle) == "function"
                and type(FBV.drawWorldOverlay) == "function" then
                local battle = select(1, FBV.liveBattle(self.game or gameSingleton()))
                if battle and isFieldBattle(battle) then
                    local okO, errO = pcall(FBV.drawWorldOverlay, battle)
                    if not okO and FBV.Log and type(FBV.Log.err) == "function" then
                        pcall(FBV.Log.err, battle, "drawWorldOverlay", errO)
                    end
                end
            end
            return a, b, c, d
        end

        OverworldState._arFbvPresentDraw26 = true
        OverworldState._arFbvPresentDraw24 = true
        OverworldState._arFbvPresentDraw23 = true
        OverworldState._arFbvPresentDraw22 = true
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

    if mod.hooks and type(mod.hooks.wrap) == "function" and not mod._arFbvInputStep5 then
        mod._arFbvInputStep5 = true
        mod._arFbvInputStep4 = true
        mod._arFbvInputStep3 = true
        mod._arFbvInputStep = true
        mod.hooks:wrap("input.step", function(next, game, dt)
            presentTick(game, dt)
            return next(game, dt)
        end)
    end

    -- Draw-path fallback: letterbox runs every frame even when PartyMenu /
    -- callout modals sit on top of BattleState (stack only updates the top).
    if mod.hooks and type(mod.hooks.wrap) == "function" and not mod._arFbvLetterbox5 then
        mod._arFbvLetterbox5 = true
        mod._arFbvLetterbox4 = true
        mod._arFbvLetterbox3 = true
        mod._arFbvLetterbox = true
        mod.hooks:wrap("render.letterbox", function(next, ctx)
            local game = gameSingleton()
            presentTick(game, frameDt())
            next(ctx)
            presentOpened = false
            if not FBV.enabled(mod) then
                return
            end
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

end
end
