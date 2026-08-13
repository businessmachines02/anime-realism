-- Field battle — BattleState presentation hooks + events + standalone intercept.
-- FIELD: classic battle mon pics stay off; cast lives as OW sprites on the map.

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
  FBV.suppressForeignStages = function()
    if Compat and type(Compat.suppressDramaticShape) == "function" then
      Compat.suppressDramaticShape(FBV, mod)
    end
  end

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

    if type(BattleState.drawAnimLayer) == "function" and not BattleState._arFbvAnim then
      local origAnim = BattleState.drawAnimLayer
      function BattleState:drawAnimLayer(colorized, ...)
        if isFieldBattle(self) then
          -- FIELD uses world-space contact/projectile/area effects. BattleState
          -- still advances its animation timer, preserving turn and sound logic.
          return
        end
        return origAnim(self, colorized, ...)
      end
      BattleState._arFbvAnim = true
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

    if type(BattleState.update) == "function" and not BattleState._arFbvUpdate then
      local origUpdate = BattleState.update
      function BattleState:update(dt, ...)
        if isFieldBattle(self) then
          self.showPlayerBack = false
          self.showEnemyTrainer = false
          -- Prefer present-clock tick (deduped) so menus can't starve idle.
          if type(FBV.tickPresent) == "function" then
            pcall(FBV.tickPresent, self.game, dt)
          elseif type(FBV.tickActive) == "function" then
            pcall(FBV.tickActive, self.game, dt)
          else
            pcall(FBV.tick, self, dt)
          end
        end
        return origUpdate(self, dt, ...)
      end
      BattleState._arFbvUpdate = true
    end
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
        return true
      end
      return next(battle)
    end)
  end

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
  do
    local okOW, OverworldState = pcall(require, "src.world.OverworldController")
    if okOW and type(OverworldState) == "table"
        and type(OverworldState.drawWorld) == "function"
        and not OverworldState._arFbvPresentDraw then
      local origDrawWorld = OverworldState.drawWorld
      function OverworldState:drawWorld(...)
        if FBV.enabled(mod) then
          presentTick(self.game or gameSingleton(), frameDt())
        end
        return origDrawWorld(self, ...)
      end
      OverworldState._arFbvPresentDraw = true
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
      pcall(FBV.begin, battle, mod)
    end)

    mod.events:on("battle.ended", function(ev)
      local battle = ev and ev.battle
      if battle then
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
        pcall(FBV.react, battle, side, "hit", { category = cat })
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
