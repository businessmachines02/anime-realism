-- Anime Realism
--
-- Hide levels and HP so battles feel closer to the anime — play by feel,
-- not numbers. Anime-style move callouts, optional HUD/XP hide, low-HP
-- warnings, and generic level-ups.

return function(mod)
  mod.options:define({
    {
      key = "hide_battle_hud",
      type = "toggle",
      label = "HIDE BATTLE HUD",
      default = true,
    },
    {
      key = "hide_xp_bar",
      type = "toggle",
      label = "HIDE XP BAR",
      default = true,
    },
    {
      key = "low_hp_warn",
      type = "toggle",
      label = "LOW HP WARN",
      default = true,
    },
    {
      key = "low_hp_threshold",
      type = "choice",
      label = "LOW HP AT",
      default = "20",
      choices = {
        { "20%", "20" },
        { "40%", "40" },
      },
    },
    {
      key = "mute_low_hp_alarm",
      type = "toggle",
      label = "MUTE HP ALARM",
      default = true,
    },
    {
      key = "generic_level_up",
      type = "toggle",
      label = "GENERIC LVL UP",
      default = true,
    },
    {
      key = "anime_move_calls",
      type = "toggle",
      label = "ANIME MOVES",
      default = true,
    },
  })

  local function opt(key)
    return mod.options:get(key) ~= false
  end

  local function hideAllHud()
    return opt("hide_battle_hud")
  end

  -- Levels and HP are always hidden everywhere.
  local function hideLevelsNow()
    return true
  end

  local function hideHpNow()
    return true
  end

  local function lowHpRatio()
    local choice = tostring(mod.options:get("low_hp_threshold") or "20")
    if choice == "40" then
      return 0.40
    end
    return 0.20
  end

  local PLAYER_LOW = {
    "Your POKéMON is\nlooking weak!",
    "Your POKéMON is\nlooking tired!",
    "Your POKéMON looks\nweak...",
    "Your POKéMON looks\ntired...",
  }
  local ENEMY_LOW = {
    "The enemy POKéMON\nis looking weak!",
    "The enemy POKéMON\nis looking tired!",
    "The foe's POKéMON\nlooks weak!",
    "The foe's POKéMON\nlooks tired...",
  }

  -- Short party-list lines (fit the old HP row).
  local PARTY_HINTS = {
    "WEAK-HEAL SOON!",
    "TIRED-HEAL SOON!",
    "LOOKING WEAK!",
    "LOOKING TIRED!",
    "NEEDS HEALING!",
  }

  local function pickLine(lines)
    local n = #lines
    if n == 0 then
      return nil
    end
    local r = (love and love.math and love.math.random) or math.random
    return lines[r(n)]
  end

  -- Stable per-mon hint so the line does not flicker every frame.
  local partyHintFor = setmetatable({}, { __mode = "k" })

  local function partyRowHint(mon)
    if not mon or not mon.stats or not mon.stats.hp or mon.stats.hp <= 0 then
      return nil
    end
    local hp = mon.hp or 0
    if hp <= 0 then
      return "FAINTED-HEAL!"
    end
    local ratio = hp / mon.stats.hp
    local needs = (ratio <= lowHpRatio()) or mon.status or (ratio < 1)
    if not needs then
      partyHintFor[mon] = nil
      return nil
    end
    local hint = partyHintFor[mon]
    if not hint then
      hint = pickLine(PARTY_HINTS)
      partyHintFor[mon] = hint
    end
    return hint
  end

  -- Per-battle: warn once per side until healed above the threshold or switched.
  local lowWarned = setmetatable({}, { __mode = "k" })

  local function sideKey(battler)
    if not battler then
      return nil
    end
    if battler.isPlayer then
      return "player"
    end
    return "enemy"
  end

  local function checkLowHp(battle, battler)
    if not opt("low_hp_warn") or not battle or not battler or not battler.mon then
      return
    end
    local mon = battler.mon
    local max = mon.stats and mon.stats.hp
    local hp = mon.hp or 0
    local side = sideKey(battler)
    if not side or not max or max <= 0 then
      return
    end

    local state = lowWarned[battle]
    if not state then
      state = { player = false, enemy = false }
      lowWarned[battle] = state
    end

    if hp <= 0 or (hp / max) > lowHpRatio() then
      state[side] = false
      return
    end
    if state[side] then
      return
    end
    state[side] = true

    local text = pickLine(side == "player" and PLAYER_LOW or ENEMY_LOW)
    if not text then
      return
    end
    if type(battle.sayNext) == "function" then
      battle:sayNext(text)
    elseif type(battle.say) == "function" then
      battle:say(text)
    end
  end

  -- Official seam for the looping low-health siren (see Reference: Hooks).
  mod.hooks:wrap("battle.low_health_alarm", function(next, ctx)
    if opt("mute_low_hp_alarm") and ctx then
      ctx.on = false
    end
    return next(ctx)
  end)

  mod.events:on("battle.started", function(ev)
    if ev and ev.battle then
      lowWarned[ev.battle] = { player = false, enemy = false }
    end
  end)

  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    if not battle then
      return
    end
    local state = lowWarned[battle]
    if not state then
      return
    end
    local side = ev.side
    if side ~= "player" and side ~= "enemy" then
      side = sideKey(ev.battler)
    end
    if side then
      state[side] = false
    end
    -- New battler may already be low.
    checkLowHp(battle, ev.battler)
  end)

  mod.events:on("battle.damage_dealt", function(ev)
    checkLowHp(ev and ev.battle, ev and ev.target)
  end)

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then
      return
    end
    -- Residual poison/burn and other non-damage_dealt drains.
    checkLowHp(battle, battle.player)
    checkLowHp(battle, battle.enemy)
  end)

  -- Replace "X grew to level N!" with a generic line. StatBox + move
  -- learning still queue right after via uiNext / learnMove.
  local LEVEL_UP_LINES = {
    "Your POKéMON has\ngrown stronger!",
    "Your POKéMON looks\nmore powerful!",
    "Your POKéMON's power\nhas surged!",
    "Your POKéMON has\nbecome tougher!",
  }

  -- Anime-style trainer callouts for "NAME\nused MOVE!" (not item use).
  -- Wild battles keep the vanilla line. Trainer foes use the trainer's name.
  local PLAYER_MOVE_CALLS = {
    "%s!\nUse %s!",
    "%s, use\n%s!",
    "Go! %s!\n%s!",
    "%s!\n%s!",
    "%s!\nNow! %s!",
    "%s!\nQuick, %s!",
    "OK, %s!\n%s!",
    "%s, go!\nUse %s!",
    "That's it!\n%s! %s!",
    "%s!\nHit 'em! %s!",
    "Come on!\n%s! %s!",
    "%s!\n%s! Go!",
  }
  -- When the foe looks weak (same threshold as LOW HP AT).
  local PLAYER_FINISH_CALLS = {
    "Finish it!\n%s! %s!",
    "%s!\nFinish it!",
    "%s!\nFinish it! %s!",
    "Now's our chance!\n%s! %s!",
    "%s!\nEnd it! %s!",
    "One more!\n%s! %s!",
    "%s!\nTake 'em down!",
    "Go for it!\n%s! %s!",
    "%s!\nThis is it! %s!",
    "Finish them!\n%s! %s!",
  }
  -- Always trainer, mon, move.
  local TRAINER_MOVE_CALLS = {
    "%s!\n%s, use %s!",
    "%s:\n%s! %s!",
    "%s!\n%s! %s!",
    "%s!\nGo, %s! %s!",
    "%s:\n%s, %s!",
    "%s!\n%s, %s!",
    "%s!\n%s, now! %s!",
    "%s:\n%s- %s!",
  }
  local TRAINER_MOVE_FALLBACK = {
    "%s!\nUse %s!",
    "%s, use\n%s!",
    "%s!\n%s!",
  }

  local function isGrewToLevelText(text)
    local s = tostring(text or ""):lower()
    return s:find("grew", 1, true) and s:find("level", 1, true)
  end

  -- Engine move announce is "NAME\nused MOVE!". Item use is "NAME used\nITEM!".
  local function parseUsedMoveText(text)
    local s = tostring(text or "")
    local mon, move = s:match("^([^\n]+)\nused ([^\n!]+)!$")
    if mon and move and mon ~= "" and move ~= "" then
      return mon, move
    end
    return nil
  end

  local function stripEnemyPrefix(mon)
    local bare = tostring(mon or ""):match("^[Ee]nemy%s+(.+)$")
    if bare and bare ~= "" then
      return bare, true
    end
    return mon, false
  end

  local function formatCall(template, a, b, c)
    local _, n = template:gsub("%%s", "")
    if n >= 3 then
      return template:format(a, b, c)
    end
    if n >= 2 then
      return template:format(a, b)
    end
    return template:format(a)
  end

  local function pickFormatted(templates, a, b, c)
    local t = pickLine(templates)
    if not t then
      return nil
    end
    return formatCall(t, a, b, c)
  end

  local function enemyLooksWeak(battle)
    local mon = battle and battle.enemy and battle.enemy.mon
    if not mon then
      return false
    end
    local max = mon.stats and mon.stats.hp
    local hp = mon.hp or 0
    if not max or max <= 0 or hp <= 0 then
      return false
    end
    return (hp / max) <= lowHpRatio()
  end

  local function rewriteMoveCallText(battle, text)
    if not opt("anime_move_calls") then
      return text
    end
    local mon, move = parseUsedMoveText(text)
    if not mon then
      return text
    end
    local bare, isEnemy = stripEnemyPrefix(mon)
    if isEnemy then
      local kind = battle and battle.kind
      -- Wild: leave "Enemy X used Y!" alone.
      if kind ~= "trainer" and kind ~= "link" then
        return text
      end
      local trainer = battle.trainer and battle.trainer.name
      if type(trainer) == "string" and trainer ~= "" then
        return pickFormatted(TRAINER_MOVE_CALLS, trainer, bare, move)
          or (trainer .. "!\n" .. bare .. ", use " .. move .. "!")
      end
      return pickFormatted(TRAINER_MOVE_FALLBACK, bare, move)
        or (bare .. "!\nUse " .. move .. "!")
    end
    if enemyLooksWeak(battle) then
      return pickFormatted(PLAYER_FINISH_CALLS, bare, move)
        or ("Finish it!\n" .. bare .. "! " .. move .. "!")
    end
    return pickFormatted(PLAYER_MOVE_CALLS, bare, move)
      or (bare .. "!\nUse " .. move .. "!")
  end

  local function rewriteLevelUpText(text)
    if opt("generic_level_up") and isGrewToLevelText(text) then
      return pickLine(LEVEL_UP_LINES) or "Your POKéMON has\ngrown stronger!"
    end
    return text
  end

  local function rewriteBattleText(battle, text)
    text = rewriteLevelUpText(text)
    return rewriteMoveCallText(battle, text)
  end

  local Font = require("src.render.Font")
  local HudTiles = require("src.render.HudTiles")
  local BattleState = require("src.battle.BattleState")
  local WideBattle = require("src.battle.WideBattle")
  local PartyMenu = require("src.ui.PartyMenu")
  local SummaryMenu = require("src.ui.SummaryMenu")

  -- True only while a battle HUD paint is in progress.
  local hidingHud = false
  -- Functions are not tables, so track wraps in a weak set.
  local patched = setmetatable({}, { __mode = "k" })

  -- Must be after local BattleState / patched (Lua locals aren't visible above).
  local function wrapBattleSay(methodName)
    local original = BattleState[methodName]
    if type(original) ~= "function" or patched[original] then
      return
    end
    local wrapped = function(self, text, ...)
      return original(self, rewriteBattleText(self, text), ...)
    end
    patched[original] = true
    patched[wrapped] = true
    BattleState[methodName] = wrapped
  end

  wrapBattleSay("sayNext")
  wrapBattleSay("say")
  wrapBattleSay("sayNextAuto")
  wrapBattleSay("sayAuto")

  local function isDigits(text)
    return type(text) == "string" and text:match("^%d+$") ~= nil
  end

  local function isHpFraction(text)
    return type(text) == "string" and text:match("^%s*%d+%s*/%s*%d+%s*$") ~= nil
  end

  -- Gen 3 UI / modern overlays print "Lv.12" instead of the native <LV> tile.
  local function isLevelTag(text)
    local s = tostring(text or "")
    return s:match("^[Ll][Vv]%.") ~= nil
  end

  local function isHpLabel(text)
    local s = tostring(text or ""):upper()
    return s == "HP" or s == "EXP"
  end

  local function wrapHudPaint(fn, ...)
    local prev = hidingHud
    hidingHud = true
    local ok, a, b, c = pcall(fn, ...)
    hidingHud = prev
    if not ok then
      error(a, 0)
    end
    return a, b, c
  end

  -- Live Font.draw lookup: native digits + "Lv." tags from UI overhaul mods.
  local origFontDraw = Font.draw
  function Font.draw(text, x, y, ...)
    if isLevelTag(text) or isHpFraction(text) then
      return
    end
    if hidingHud and not hideAllHud() then
      if isDigits(text) and (y == 8 or y == 64) then
        return
      end
    end
    return origFontDraw(text, x, y, ...)
  end

  -- True while a patched Gen3 (etc.) battle status HUD is painting.
  local suppressingBattleHpText = false

  -- Catch TrueType love.graphics.print/printf "Lv." tags from UI overhauls.
  -- HP numbers are filtered only while a battle status HUD paint is active,
  -- so party/summary HP text stays visible when only HIDE BATTLE HP is on.
  local function installLoveTextFilters()
    if not (love and love.graphics) or patched.__love_text then
      return
    end
    patched.__love_text = true
    local g = love.graphics
    local origPrint, origPrintf = g.print, g.printf
    function g.print(text, ...)
      if isLevelTag(text) or isHpFraction(text) or isHpLabel(text) then
        return
      end
      return origPrint(text, ...)
    end
    function g.printf(text, ...)
      if isLevelTag(text) or isHpFraction(text) or isHpLabel(text) then
        return
      end
      return origPrintf(text, ...)
    end
  end

  -- Table-path draws (WideBattle, party, etc.).
  local origHPBar = HudTiles.drawHPBar
  function HudTiles.drawHPBar(data, tx, ty, mon, barType, ...)
    -- Never draw HP bars (battle, party, summary).
    return
  end

  local origTile = HudTiles.tile
  function HudTiles.tile(code, x, y, ...)
    if code == 0x6E then
      return
    end
    return origTile(code, x, y, ...)
  end

  local origStatusTile = HudTiles.statusTile
  if origStatusTile then
    function HudTiles.statusTile(code, x, y, ...)
      if code == 0x6E then
        return
      end
      return origStatusTile(code, x, y, ...)
    end
  end

  local function wrapHudDraw(inner)
    return function(...)
      if hideAllHud() then
        return
      end
      return wrapHudPaint(inner, ...)
    end
  end

  -- Classic BattleState caches drawHPBar/hudTile as locals. Dramatic Shape
  -- also keeps an innerHUDs upvalue that bypasses later BattleState.drawHUDs
  -- wraps. Patch those upvalues after every mod has installed.
  local function patchDrawLocals(fn, seen)
    if type(fn) ~= "function" then
      return
    end
    seen = seen or {}
    if seen[fn] then
      return
    end
    seen[fn] = true

    local i = 1
    while true do
      local name, val = debug.getupvalue(fn, i)
      if not name then
        break
      end

      if name == "drawHPBar" and type(val) == "function" and not patched[val] then
        local wrapped = function()
          return
        end
        patched[val] = true
        patched[wrapped] = true
        debug.setupvalue(fn, i, wrapped)
      elseif name == "hudTile" and type(val) == "function" and not patched[val] then
        local wrapped = function(code, x, y, tint)
          if code == 0x6E then
            return
          end
          return val(code, x, y, tint)
        end
        patched[val] = true
        patched[wrapped] = true
        debug.setupvalue(fn, i, wrapped)
      elseif (name == "innerHUDs" or name == "drawHUDs") and type(val) == "function" then
        if not patched[val] then
          local wrapped = wrapHudDraw(val)
          patched[val] = true
          patched[wrapped] = true
          debug.setupvalue(fn, i, wrapped)
          patchDrawLocals(val, seen)
        else
          patchDrawLocals(val, seen)
        end
      end
      i = i + 1
    end
  end

  local function installBattleDrawWrap()
    local current = BattleState.drawHUDs
    if patched[current] then
      patchDrawLocals(current)
      return
    end
    local wrapped = wrapHudDraw(current)
    patched[current] = true
    patched[wrapped] = true
    BattleState.drawHUDs = wrapped
    patchDrawLocals(current)
    patchDrawLocals(wrapped)
  end

  local function installWideWrap()
    -- Only patch WideBattle's local drawHUDs — do not wrap the whole wide
    -- draw (that would also filter the dialogue box).
    patchDrawLocals(WideBattle.draw)
  end

  -- Dramatic Shape snaps HUD bands + frosted panels outside drawHUDs.
  local function installDramaticShapeHide()
    local handle = mod.find and mod.find("DRAMATIC_SHAPE")
    local lib = handle and handle.exports and handle.exports.lib
    if not (lib and type(lib.require) == "function") then
      return
    end
    local ok, OverworldBattle = pcall(lib.require, "OverworldBattle")
    if not ok or type(OverworldBattle) ~= "table" then
      return
    end

    -- Frosted name/HP panels follow hudLive; returning false skips those
    -- boxes while leaving the dialogue panel alone.
    if type(OverworldBattle.hudLive) == "function" and not patched[OverworldBattle.hudLive] then
      local origLive = OverworldBattle.hudLive
      OverworldBattle.hudLive = function(battle, slide)
        if hideAllHud() then
          return false, false
        end
        return origLive(battle, slide)
      end
      patched[origLive] = true
      patched[OverworldBattle.hudLive] = true
    end
  end

  -- Gen 3 Inspired UI (and similar) keep their own printText / HUD drawers as
  -- upvalues on render.hud / battle.overlay wraps. Patch those after load so
  -- "Lv." tags and status panels honor this mod's options.
  local function patchCompatUiFn(fn, seen)
    if type(fn) ~= "function" or seen[fn] then
      return
    end
    seen[fn] = true
    local i = 1
    while true do
      local name, val = debug.getupvalue(fn, i)
      if not name then
        break
      end
      if type(val) == "function" and not patched[val] then
        if name == "printText" or name == "partyText" or name == "finalText" then
          local inner = val
          local wrapped = function(text, ...)
            local s = tostring(text or "")
            if isLevelTag(s) or isHpLabel(s) or isHpFraction(s) then
              return
            end
            if suppressingBattleHpText and isHpFraction(s) then
              return
            end
            return inner(text, ...)
          end
          patched[val] = true
          patched[wrapped] = true
          debug.setupvalue(fn, i, wrapped)
        elseif name == "drawEnemyHUD" or name == "drawPlayerHUD" then
          local inner = val
          local wrapped = function(...)
            if hideAllHud() then
              return
            end
            local prev = suppressingBattleHpText
            suppressingBattleHpText = true
            local ok, a, b, c = pcall(inner, ...)
            suppressingBattleHpText = prev
            if not ok then
              error(a, 0)
            end
            return a, b, c
          end
          patched[val] = true
          patched[wrapped] = true
          debug.setupvalue(fn, i, wrapped)
        elseif name == "drawStyledHP" or name == "drawPartyExpBar" then
          local wrapped = function()
            return
          end
          patched[val] = true
          patched[wrapped] = true
          debug.setupvalue(fn, i, wrapped)
        elseif name == "partyHPBarFinal" then
          local inner = val
          local partyTextFn = nil
          for j = 1, 48 do
            local n, v = debug.getupvalue(fn, j)
            if n == "partyText" and type(v) == "function" then
              partyTextFn = v
              break
            end
          end
          local wrapped = function(x, y, w, mon, ...)
            local hint = partyRowHint(mon)
            if hint and partyTextFn then
              partyTextFn(hint, x, y - 2, 3, { 0.46, 0.14, 0.12, 1 })
              return
            end
            -- Still never draw the real HP bar.
            return
          end
          patched[val] = true
          patched[wrapped] = true
          debug.setupvalue(fn, i, wrapped)
        elseif name == "drawEXPRow" then
          local inner = val
          local wrapped = function(...)
            if opt("hide_xp_bar") or hideAllHud() then
              return
            end
            return inner(...)
          end
          patched[val] = true
          patched[wrapped] = true
          debug.setupvalue(fn, i, wrapped)
        else
          patchCompatUiFn(val, seen)
        end
      end
      i = i + 1
    end
  end

  local function installCompatUiOverrides()
    installLoveTextFilters()
    local Runtime = require("src.mods.Runtime")
    local chains = Runtime.hooks and Runtime.hooks.chains
    if type(chains) ~= "table" then
      return
    end
    local seen = {}
    for _, hookName in ipairs({ "render.hud", "battle.overlay" }) do
      local chain = chains[hookName]
      if type(chain) == "table" then
        for _, entry in ipairs(chain) do
          if entry and type(entry.callback) == "function" then
            -- Prefer known UI overhaul owners; still walk unknown wraps that
            -- close over printText/drawEnemyHUD.
            if entry.owner == "gen3_battle_ui"
              or entry.owner == nil
              or type(entry.owner) == "string" then
              patchCompatUiFn(entry.callback, seen)
            end
          end
        end
      end
    end
  end

  mod.events:on("mods.loaded", function()
    installBattleDrawWrap()
    installWideWrap()
    installDramaticShapeHide()
    installCompatUiOverrides()
  end)
  mod.events:on("game.ready", function()
    installLoveTextFilters()
    installCompatUiOverrides()
  end)
  -- Hot reload / late installers.
  installBattleDrawWrap()
  installWideWrap()
  installDramaticShapeHide()
  installCompatUiOverrides()

  -- Suppress the QoL thin XP rectangle (classic, wide, and Dramatic Shape).
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle or type(battle.draw) ~= "function" or battle.__lhh_draw then
      return
    end
    local baseDraw = battle.draw
    battle.draw = function(self, ...)
      if not (opt("hide_xp_bar") or hideAllHud()) then
        return baseDraw(self, ...)
      end
      local g = love.graphics
      local origRect = g.rectangle
      g.rectangle = function(mode, x, y, w, h, ...)
        if mode == "fill" and type(h) == "number" and type(w) == "number"
          and h > 0 and h <= 16 and w >= 2 then
          local shot = rawget(self, "dramaticShapeShot")
          if type(shot) == "table" and type(shot.ly) == "number"
            and type(shot.scale) == "number" and shot.scale > 0 then
            local expY = shot.ly + 89 * shot.scale
            if math.abs((y or 0) - expY) <= shot.scale then
              return
            end
          end
          -- Classic / wide QoL XP strip sits on rows 88-91.
          if (y or 0) >= 88 and (y or 0) <= 94 and h <= 4 then
            return
          end
        end
        return origRect(mode, x, y, w, h, ...)
      end
      local ok, a, b, c = pcall(baseDraw, self, ...)
      g.rectangle = origRect
      if not ok then
        error(a, 0)
      end
      return a, b, c
    end
    battle.__lhh_draw = true
  end)

  -- Party menu: never show level/HP; print a heal hint on the old HP row.
  local origPartyDraw = PartyMenu.draw
  function PartyMenu.draw(self)
    local prevDraw, prevTile = Font.draw, HudTiles.tile
    local prevHPBar = HudTiles.drawHPBar

    Font.draw = function(text, x, y, ...)
      if isLevelTag(text) or isHpFraction(text) then
        return
      end
      if isDigits(text) and (x == 104 or x == 112) and (y % 16 == 0) then
        return
      end
      return prevDraw(text, x, y, ...)
    end
    HudTiles.tile = function(code, x, y, ...)
      if code == 0x6E then
        return
      end
      return prevTile(code, x, y, ...)
    end
    HudTiles.drawHPBar = function()
      return
    end

    local ok, err = pcall(origPartyDraw, self)
    Font.draw = prevDraw
    HudTiles.tile = prevTile
    HudTiles.drawHPBar = prevHPBar
    if not ok then
      error(err, 0)
    end

    if self.tmhm then
      return
    end
    local party = self.party or (self.game.save and self.game.save.party) or {}
    love.graphics.setColor(0, 0, 0, 1)
    for i, mon in ipairs(party) do
      local hint = partyRowHint(mon)
      if hint then
        local y = PartyMenu.entryY(i)
        prevDraw(hint, 40, y + 8)
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- Summary (STATS): hide level + HP bar/numbers.
  local origSummaryDraw = SummaryMenu.draw
  function SummaryMenu.draw(self)
    local prevDraw = Font.draw
    local prevStatus = HudTiles.statusTile
    local prevTile = HudTiles.tile
    local prevHPBar = HudTiles.drawHPBar

    Font.draw = function(text, x, y, ...)
      if isLevelTag(text) or isHpFraction(text) then
        return
      end
      if isDigits(text) then
        if (y == 16 and (x == 112 or x == 120))
          or (y == 48 and (x == 128 or x == 136)) then
          return
        end
      end
      return prevDraw(text, x, y, ...)
    end
    local function hideLv(code, x, y)
      return code == 0x6E
        and ((x == 112 and y == 16) or (x == 128 and y == 48))
    end
    if prevStatus then
      HudTiles.statusTile = function(code, x, y, tint)
        if hideLv(code, x, y) then
          return
        end
        return prevStatus(code, x, y, tint)
      end
    end
    HudTiles.tile = function(code, x, y, tint)
      if hideLv(code, x, y) then
        return
      end
      return prevTile(code, x, y, tint)
    end
    HudTiles.drawHPBar = function()
      return
    end

    local ok, err = pcall(origSummaryDraw, self)
    Font.draw = prevDraw
    HudTiles.statusTile = prevStatus
    HudTiles.tile = prevTile
    HudTiles.drawHPBar = prevHPBar
    if not ok then
      error(err, 0)
    end
  end

  mod.log:info("levels/HP hidden; party list shows heal hints only")
end
