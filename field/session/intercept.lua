-- Field battle — map fight with BattleState as a transparent stack host.
--
-- When BATTLE STAGE = FIELD:
--   • no BattleTransition wipe / white episode
--   • BattleState is pushed with isOpaque=false / bgMode=world (map shows under)
--   • push BattleState itself (not a proxy) so gen3_battle_ui sees
--     stack:top() == battle and draws move names / command menu
--   • overworld stays underneath (frozen — not top of stack)
--   • finish pops the battle host only; no white battleReturn fade
--
-- Flags stamped on the battle: _arAnimeField, _arFieldCombat, _arFieldStandalone.
-- hooks.lua and ui.lua key off those to suppress classic chrome.

local Intercept = {}

local function armBattle(battle)
  if not battle then
    return
  end
  battle._arFieldCombat = true
  battle._arFieldStandalone = true
  battle._arAnimeField = true
  battle._arFieldHost = battle
  battle.isOpaque = false
  battle.isBattle = true
  battle.letterboxWhite = false
  battle.BG_WORLD_DIM = 0
  battle.showPlayerBack = false
  battle.showEnemyTrainer = false
  battle.introSlide = 0
  battle.introBalls = false
end

local function resolveOverworldState()
  local ok, modClass = pcall(require, "src.world.OverworldController")
  if ok and type(modClass) == "table" and type(modClass.pushBattle) == "function" then
    return modClass
  end
  ok, modClass = pcall(require, "src.world.OverworldState")
  if ok and type(modClass) == "table" and type(modClass.pushBattle) == "function" then
    return modClass
  end
  return nil
end

local function lockOverworld(ow)
  if not ow then
    return
  end
  ow.engaging = true
  ow._arFieldEngaging = true
  if ow.player then
    ow.player.inputLocked = true
    ow.player.frozen = true
    ow.player.moving = false
  end
end

local function clearOwBattle(battle)
  local game = battle and battle.game
  local ow = game and game.overworld
  if not ow then
    return
  end
  if ow._arFieldBattle == battle then
    ow._arFieldBattle = nil
  end
  if ow._arFieldBattle == nil then
    ow._arFieldEngaging = nil
    ow.engaging = false
    if ow.player then
      ow.player.inputLocked = false
    end
  end
end

local function popFieldHost(battle)
  local host = battle and battle._arFieldHost or battle
  local game = battle and battle.game
  local stack = game and game.stack
  local ow = game and game.overworld
  if not (stack and type(stack.pop) == "function") then
    if battle then
      battle._arFieldHost = nil
    end
    return
  end

  -- Pop everything above the overworld so flee/win always returns control.
  local guard = 0
  while stack:top() and stack:top() ~= ow and guard < 16 do
    local top = stack:top()
    if top and top.isOverworld then
      break
    end
    -- Pop our battle host and any leftover fight overlays (menus/text).
    if top == host or top == battle
        or (top and top._arFieldHost)
        or (top and top.battle == battle)
        or (host ~= nil) then
      stack:pop()
    else
      break
    end
    guard = guard + 1
  end

  if host and stack:top() == host then
    stack:pop()
  end
  if battle then
    battle._arFieldHost = nil
  end
end

local function finishStandalone(self, fbv, _mod)
  if self.payDay and self.result == "win" then
    self.game.save.money = self.game.save.money + self.payDay
    if type(self.say) == "function" and type(self.romText) == "function" then
      self:say(self:romText("_PickUpPayDayMoneyText", "%s picked up\n¥%d!",
        self.game.save.player.name, self.payDay))
    end
    self.payDay = nil
    self.afterQueue = "finish"
    self.phase = "messages"
    return true
  end

  local Party = require("src.pokemon.Party")
  if self.result ~= "lose" and not self.demo
      and not Party.firstHealthy(self.game.save.party) then
    self.result = "lose"
  end

  self.lockedBall = nil
  if type(self.restoreMimicked) == "function" then
    self:restoreMimicked(self.player)
    self:restoreMimicked(self.enemy)
  end
  require("src.core.Sound").stopLoop("Low_Health_Alarm")
  require("src.core.Music").restoreMap(self.data)

  local result = self.result or "run"
  local onFinish = self.onFinish
  self._arFieldEnded = true

  -- Restore cast / arena / zoom BEFORE popping, while OW refs are still valid.
  if fbv and type(fbv.finish) == "function" then
    pcall(fbv.finish, self)
  end

  popFieldHost(self)
  clearOwBattle(self)

  -- Prefer mods Runtime so battle.ended (map restore, cleanup) actually fires.
  local Runtime = nil
  do
    local okR, rt = pcall(require, "src.mods.Runtime")
    if okR and rt and type(rt.emit) == "function" then
      Runtime = rt
    else
      okR, rt = pcall(require, "src.core.Runtime")
      if okR and rt and type(rt.emit) == "function" then
        Runtime = rt
      end
    end
  end
  if Runtime then
    Runtime.emit("battle.ended", { battle = self, result = result })
  end

  if type(self.exit) == "function" then
    pcall(self.exit, self)
  end

  self._arFieldStandalone = nil
  self._arFieldCombat = nil
  self._arAnimeField = nil
  self._arFieldEnterDone = nil
  self._arFieldBeginDone = nil

  -- Guarantee the player can move again after flee/win/lose.
  local ow = self.game and self.game.overworld
  if ow then
    ow._arFieldBattle = nil
    ow._arFieldEngaging = nil
    ow.engaging = false
    if ow.player then
      ow.player.inputLocked = false
      ow.player.frozen = false
      ow.player.moving = false
    end
    if ow.camera and ow.player and type(ow.camera.follow) == "function" then
      local vw, vh = 160, 144
      local ren = self.game.renderer
      if ren and type(ren.worldViewSize) == "function" then
        local ok, a, b = pcall(ren.worldViewSize, ren)
        if ok and type(a) == "number" then
          vw, vh = a, b or vh
        end
      end
      pcall(ow.camera.follow, ow.camera, ow.player.px, ow.player.py, vw, vh)
      -- Preserve FIELD exit soft-pan (offset rides on top of follow).
      local pan = ow.cameraPan
      if pan and pan.arFieldReturn then
        ow.camera.x = (ow.camera.x or 0) + (pan.ox or 0)
        ow.camera.y = (ow.camera.y or 0) + (pan.oy or 0)
      end
    end
  end

  if onFinish then
    onFinish(result)
  end
  return false
end

local function handleDeadEnter(self)
  local name = self.game.save.player.name
  self.result = "lose"
  require("src.core.Music").restoreMap(self.data)
  local Runtime = nil
  do
    local okR, rt = pcall(require, "src.mods.Runtime")
    if okR and rt and type(rt.emit) == "function" then
      Runtime = rt
    else
      okR, rt = pcall(require, "src.core.Runtime")
      if okR and rt and type(rt.emit) == "function" then
        Runtime = rt
      end
    end
  end
  if Runtime then
    Runtime.emit("battle.ended", { battle = self, result = "lose", skipped = true })
  end
  clearOwBattle(self)
  local fbv = Intercept._fbv
  if fbv and type(fbv.finish) == "function" then
    pcall(fbv.finish, self)
  end
  local onFinish = self.onFinish
  local function blackedOut()
    if onFinish then
      onFinish("lose")
    end
  end
  local okBS, BattleState = pcall(require, "src.battle.BattleState")
  if okBS and BattleState and type(BattleState.isOaksLabStarterRival) == "function"
      and BattleState.isOaksLabStarterRival(self) then
    return blackedOut()
  end
  local Strings = require("src.core.Strings")
  self.game.stack:push(require("src.render.TextBox").new(self.game,
    Strings("%s is out of\nuseable POKéMON!", name) .. "\f"
      .. Strings("%s blacked\nout!", name), blackedOut))
end

function Intercept.install(FBV, mod)
  Intercept._fbv = FBV
  Intercept._mod = mod

  local OverworldState = resolveOverworldState()
  if not OverworldState then
    print("[anime_realism] field: OverworldState.pushBattle not found")
    return false
  end

  if not OverworldState._arFbvPushBattle then
    local orig = OverworldState.pushBattle
    function OverworldState:pushBattle(battle)
      local fbv = Intercept._fbv
      local m = Intercept._mod
      if not (fbv and m and type(fbv.shouldUse) == "function"
          and fbv.shouldUse(m, battle)) then
        return orig(self, battle)
      end
      if not battle then
        return orig(self, battle)
      end

      local game = self.game or battle.game
      if not game then
        local okG, Game = pcall(require, "src.core.Game")
        if okG then
          game = Game
        end
      end
      local stack = game and game.stack
      if not (stack and type(stack.push) == "function") then
        return orig(self, battle)
      end

      -- Kill Dramatic Shape arena / DOF staging before we mount FIELD.
      if type(fbv.suppressForeignStages) == "function" then
        pcall(fbv.suppressForeignStages)
      end

      armBattle(battle)
      self._arFieldBattle = battle
      lockOverworld(self)

      if type(battle.playBattleTheme) == "function" then
        pcall(function()
          battle:playBattleTheme()
        end)
      end

      -- Enter exactly once. choose_lead hooks battle.started and will open a
      -- PartyMenu per emit — calling enter() then stack:push(battle) used to
      -- re-enter and prompt "send out" repeatedly.
      if type(battle.enter) == "function" and not battle._arFieldEnterDone then
        battle:enter()
      end
      armBattle(battle)
      self._arFieldBattle = battle
      lockOverworld(self)

      -- Blackout path already pushed a TextBox; do not mount a host.
      if battle.dead and not battle.player then
        return true
      end

      -- Staging is owned by the enter wrap (once). Do not begin again here.
      armBattle(battle)
      battle._arFieldHost = battle
      stack:push(battle)
      return true
    end
    OverworldState._arFbvPushBattle = true
  end

  -- Safety: if OW somehow updates while a field fight is pinned, do not walk.
  if type(OverworldState.handleInput) == "function" and not OverworldState._arFbvInput then
    local origInput = OverworldState.handleInput
    function OverworldState:handleInput(...)
      if self._arFieldBattle or self._arFieldEngaging then
        return
      end
      return origInput(self, ...)
    end
    OverworldState._arFbvInput = true
  end

    local okBS, BattleState = pcall(require, "src.battle.BattleState")
  if okBS and type(BattleState) == "table" then
    -- FIELD already paints its own cues. Classic AnimPlayer still starts
    -- those rows (wavy screen, palettes, pic FX) after ANY damaging move
    -- and can kill Love with no error screen. Shared path, not per-move.
    -- Ball/send-out anims still run via BALL_ANIMS.
    if type(BattleState.animationsOn) == "function"
        and not BattleState._arFbvAnimOff then
      local origAnimsOn = BattleState.animationsOn
      function BattleState:animationsOn(...)
        local fbv = Intercept._fbv
        local m = Intercept._mod
        if self and fbv and m and type(fbv.shouldUse) == "function"
            and fbv.shouldUse(m, self) then
          return false
        end
        return origAnimsOn(self, ...)
      end
      BattleState._arFbvAnimOff = true
    end
    if type(BattleState.enter) == "function" and not BattleState._arFbvEnterArm then
      local origEnter = BattleState.enter
      function BattleState:enter(...)
        local fbv = Intercept._fbv
        local m = Intercept._mod
        -- stack:push may call enter again after pushBattle already entered.
        if self and self._arFieldEnterDone then
          return
        end
        if self and self._arFieldStandalone and self.dead and not self.player then
          return handleDeadEnter(self)
        end
        if fbv and m and type(fbv.shouldUse) == "function"
            and fbv.shouldUse(m, self) then
          armBattle(self)
        end
        local result = origEnter(self, ...)
        if self and (self._arFieldCombat or self._arFieldStandalone) then
          self._arFieldEnterDone = true
          armBattle(self)
          -- Stage the FIELD cast once after the real enter/queue build.
          if fbv and type(fbv.begin) == "function" and not self._arFieldBeginDone then
            self._arFieldBeginDone = true
            pcall(fbv.begin, self, m)
          end
        end
        return result
      end
      BattleState._arFbvEnterArm = true
    end

    if type(BattleState.finish) == "function" and not BattleState._arFbvFinish then
      local origFinish = BattleState.finish
      function BattleState:finish(...)
        if self and (self._arFieldStandalone or self._arFieldCombat)
            and not self._arFieldEnded then
          finishStandalone(self, Intercept._fbv, Intercept._mod)
          return
        end
        if self and self._arFieldEnded then
          return
        end
        return origFinish(self, ...)
      end
      BattleState._arFbvFinish = true
    end

    if type(BattleState.updateQueue) == "function" and not BattleState._arFbvUQ28 then
      local origUQ = BattleState.updateQueue
      local function noteUQ(battle, tag, ...)
        local Log = Intercept._fbv and Intercept._fbv.Log
        if Log and type(Log.note) == "function" then
          pcall(Log.note, battle, tag, ...)
        end
      end
      function BattleState:updateQueue(...)
        if self and self._arFieldStandalone and self.waitingUI then
          local top = self.game.stack and self.game.stack:top()
          -- Logic queue may wait; FIELD present clock (tickPresent) does not.
          -- Host is the battle itself; resume when menus / choice boxes close.
          if top ~= self then
            return true
          end
          self.waitingUI = nil
        end
        -- CLOSE THE GAP: park the engine queue until the sprite is in range.
        -- Instant-move confirm must still run executeAction once so damage
        -- can be held. After that (or any other tick), Harden / the next
        -- turn cannot start while the punch is still walking in.
        local fbv = Intercept._fbv
        local session = fbv and type(fbv.session) == "function" and fbv.session(self)
        local Cues = fbv and fbv.Cues
        local holding = session
            and Cues and type(Cues.shouldParkEngineQueue) == "function"
            and Cues.shouldParkEngineQueue(session)
        local heldDmg = self and (self._arCloseGapDamage or self._arCloseGapApply)
        local confirmStart = self and self._arFieldInstantMove and not heldDmg
        if holding and not confirmStart then
          if not self._arCloseGapParked then
            self._arCloseGapParked = true
            local p = session.playerMon
            local e = session.enemyMon
            local who = (p and p._pendingCloseStrike and "you")
                or (e and e._pendingCloseStrike and "foe")
                or "react"
            local mid = (p and p._pendingCloseStrike and p._pendingCloseStrike.moveId)
                or (e and e._pendingCloseStrike and e._pendingCloseStrike.moveId)
                or "-"
            noteUQ(self, "uq park", who, mid)
            if Cues and type(Cues.notePos) == "function" then
              pcall(Cues.notePos, session, self, "pos park")
            end
          end
          return true
        end
        if self and self._arCloseGapParked then
          self._arCloseGapParked = nil
          noteUQ(self, "uq resume", self._arAwaitingReact and "react" or nil)
        end
        if confirmStart and holding then
          noteUQ(self, "uq pass confirm")
        elseif self and self._arAwaitingReact and not self._arReactPassNoted then
          self._arReactPassNoted = true
          noteUQ(self, "uq pass react")
        end
        if self and not self._arAwaitingReact then
          self._arReactPassNoted = nil
        end
        return origUQ(self, ...)
      end
      BattleState._arFbvUQ28 = true
      BattleState._arFbvUQ27 = true
      BattleState._arFbvUQ24 = true
    end
  end

  Intercept._installed = true
  return true
end

return Intercept
