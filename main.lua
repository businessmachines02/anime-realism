-- Anime Realism
--
-- Hide levels and HP so battles feel closer to the anime — play by feel,
-- not numbers. Anime-style move callouts, terrain/type dodge & brace
-- picks with buffs, callout style preset, physical momentum counters,
-- underdog EXP / faint effort rewards, optional HUD/XP hide, low-HP
-- warnings, and generic level-ups / EXP lines.

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
    {
      key = "momentum_counter",
      type = "toggle",
      label = "MOMENTUM HIT",
      default = true,
    },
    {
      key = "callout_style",
      type = "choice",
      label = "CALLOUT STYLE",
      default = "AUTO",
      choices = {
        { "AUTO", "AUTO" },
        { "BOLD", "BOLD" },
        { "TRICKY", "TRICKY" },
        { "SHOWY", "SHOWY" },
      },
    },
    {
      key = "callout_buffs",
      type = "toggle",
      label = "CALLOUT BUFFS",
      default = true,
    },
    {
      key = "callout_pick",
      type = "choice",
      label = "CALLOUT PICK",
      default = "THREAT",
      choices = {
        { "THREAT", "THREAT" },
        { "ALWAYS", "ALWAYS" },
        { "OFF", "OFF" },
      },
    },
    {
      key = "underdog_exp",
      type = "toggle",
      label = "UNDERDOG EXP",
      default = true,
    },
    {
      key = "effort_faint",
      type = "toggle",
      label = "EFFORT FAINT",
      default = true,
    },
  })

  local function opt(key)
    return mod.options:get(key) ~= false
  end

  local function calloutPickMode()
    local raw = mod.options:get("callout_pick")
    -- Migrate legacy toggle values.
    if raw == false then
      return "OFF"
    end
    if raw == true or raw == nil then
      return "THREAT"
    end
    local s = tostring(raw):upper()
    if s == "ALWAYS" or s == "OFF" or s == "THREAT" then
      return s
    end
    return "THREAT"
  end

  local function calloutStyle()
    local s = tostring(mod.options:get("callout_style") or "AUTO"):upper()
    if s == "BOLD" or s == "TRICKY" or s == "SHOWY" then
      return s
    end
    return "AUTO"
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

  -- Momentum: foe → player.
  -- Physical hit → arms counter; on your reply you pick COUNTER or HOLD.
  -- Special → dodge callout (may fail); temp buffs clear when you attack.
  local Damage = require("src.battle.Damage")
  local momentumByBattle = setmetatable({}, { __mode = "k" })
  -- Forward decls: event handlers / pick menu close over these.
  local revealPlayerPic
  local enqueueDodgeHideAnim
  local enqueueBraceAnim
  local applyCalloutBuffs
  local clearCalloutPickState
  local resolvePendingDamage
  local announceCoverHit
  local rewriteDodgeMissText

  local function freshMomentum()
    return {
      mode = nil,
      boosted = false,
      enemyActedThisTurn = false,
      pickOfferedThisTurn = false,
      awaitingPick = nil,
      pendingDamage = nil,
      -- Temporary cover buffs from dodge/brace; cleared on your attack.
      -- entrenched: strong brace — near-max DEF while you wait to counter;
      -- foe can rarely "break through" and strip it before damage.
      temp = {
        evasion = 0,
        defense = 0,
        cover = false,
        picHidden = false,
        entrenched = false,
      },
      -- Trainer-foe mirror: temp buffs clear when the foe attacks.
      enemyTemp = { evasion = 0, defense = 0, cover = false },
      enemyMode = nil,
      enemyBoosted = false,
      enemyReactedThisTurn = false,
    }
  end

  local function momentumState(battle)
    local state = momentumByBattle[battle]
    if not state then
      state = freshMomentum()
      momentumByBattle[battle] = state
    end
    if not state.temp then
      state.temp = {
        evasion = 0,
        defense = 0,
        cover = false,
        picHidden = false,
        entrenched = false,
      }
    end
    if not state.enemyTemp then
      state.enemyTemp = { evasion = 0, defense = 0, cover = false }
    end
    return state
  end

  local function resetMomentum(battle)
    if not battle then
      return
    end
    local prev = momentumByBattle[battle]
    local keepTemp = prev and prev.temp
    local keepEnemyTemp = prev and prev.enemyTemp
    local keepPending = prev and prev.pendingDamage
    local keepAwait = prev and prev.awaitingPick
    -- Keep unused counters armed across the turn boundary.
    local keepCounter = prev and prev.mode == "counter" and not prev.boosted
    local keepEnemyCounter = prev and prev.enemyMode == "counter" and not prev.enemyBoosted
    momentumByBattle[battle] = freshMomentum()
    if keepTemp then
      momentumByBattle[battle].temp = keepTemp
    end
    if keepEnemyTemp then
      momentumByBattle[battle].enemyTemp = keepEnemyTemp
    end
    if keepPending then
      momentumByBattle[battle].pendingDamage = keepPending
      momentumByBattle[battle].awaitingPick = keepAwait
      momentumByBattle[battle].pickOfferedThisTurn = true
    end
    if keepCounter then
      momentumByBattle[battle].mode = "counter"
      momentumByBattle[battle].boosted = false
    end
    if keepEnemyCounter then
      momentumByBattle[battle].enemyMode = "counter"
      momentumByBattle[battle].enemyBoosted = false
    end
  end

  local function clearBattleMomentum(battle)
    if not battle then
      return
    end
    momentumByBattle[battle] = freshMomentum()
  end

  local function foeMoveIsSpecial(move)
    if not move then
      return false
    end
    if move.category == "special" then
      return true
    end
    if move.category == "physical" or move.category == "status" then
      return false
    end
    -- Gen 1: physical/special comes from the move's type.
    local ok, special = pcall(Damage.isSpecial, move.type)
    return ok and special or false
  end

  local function playerHasCounter(battle)
    if not opt("momentum_counter") or not battle then
      return false
    end
    local state = momentumByBattle[battle]
    return state and state.mode == "counter" and not state.boosted
  end

  local function dodgeFailChance()
    local style = calloutStyle()
    if style == "TRICKY" then
      return 0.20
    end
    if style == "BOLD" then
      return 0.25
    end
    if style == "SHOWY" then
      return 0.35
    end
    return 0.30
  end

  local function rollDodgeSuccess()
    local r = (love and love.math and love.math.random) or math.random
    return r() >= dodgeFailChance()
  end

  -- Rare physical connect that still arms COUNTER/HOLD (~20%).
  local function rollPhysicalCounterArm()
    local r = (love and love.math and love.math.random) or math.random
    return r() < 0.20
  end

  -- Entrenched: foe rarely punches through max DEF (~18%).
  local function rollEntrenchBreakthrough()
    local r = (love and love.math and love.math.random) or math.random
    return r() < 0.18
  end

  -- Per-battle effort tracking (Gen 1 stat exp consolation + underdog XP).
  local effortByBattle = setmetatable({}, { __mode = "k" })
  local Stats = require("src.pokemon.Stats")

  local function effortState(battle)
    local state = effortByBattle[battle]
    if not state then
      state = { mons = {} }
      effortByBattle[battle] = state
    end
    return state
  end

  local function effortRec(battle, mon)
    if not battle or not mon then
      return nil
    end
    local state = effortState(battle)
    local rec = state.mons[mon]
    if not rec then
      rec = { damage = 0, moves = 0, fainted = false, effortPaid = false }
      state.mons[mon] = rec
    end
    return rec
  end

  local function clearEffort(battle)
    if battle then
      effortByBattle[battle] = { mons = {} }
    end
  end

  local function performedWell(rec, enemy)
    if not rec or (rec.damage or 0) <= 0 then
      return false
    end
    local maxHp = enemy and enemy.mon and enemy.mon.stats and enemy.mon.stats.hp
    maxHp = tonumber(maxHp) or 0
    if maxHp > 0 and rec.damage >= math.max(1, math.floor(maxHp * 0.25)) then
      return true
    end
    return (rec.moves or 0) >= 2 and rec.damage >= 5
  end

  local EFFORT_LINES = {
    "%s grew\nfrom the effort!",
    "%s learned\nfrom that fight!",
    "Hard fight-\n%s grew a bit!",
    "%s's effort\nwasn't wasted!",
  }

  local function awardEffortConsolation(battle, mon, foeDef)
    if not mon or not foeDef or type(foeDef.baseStats) ~= "table" then
      return false
    end
    if type(mon.statExp) ~= "table" then
      mon.statExp = {}
    end
    local order = Stats.ORDER or { "hp", "attack", "defense", "speed", "special" }
    local any = false
    for i = 1, #order do
      local key = order[i]
      local base = tonumber(foeDef.baseStats[key]) or 0
      -- About 1/5 of a normal undivided base-stat yield (capped effort).
      local gain = math.max(1, math.floor(base / 5))
      local before = mon.statExp[key] or 0
      mon.statExp[key] = math.min(65535, before + gain)
      if mon.statExp[key] > before then
        any = true
      end
    end
    -- Tiny EXP crumb so the fight still "counts" without a full share.
    if any then
      local crumb = math.max(1, math.min(8, math.floor((foeDef.baseExp or 16) / 8)))
      mon.exp = (mon.exp or 0) + crumb
    end
    if not any or not battle or type(battle.sayNext) ~= "function" then
      return any
    end
    local name = mon.nickname
    if not name or name == "" then
      local def = battle.data and battle.data.pokemon and battle.data.pokemon[mon.species]
      name = def and def.name or "POKéMON"
    end
    local line = pickLine(EFFORT_LINES) or "%s grew\nfrom the effort!"
    battle:sayNext(line:format(name))
    return true
  end

  -- Much-weaker KO → bonus EXP (exp.gain runs per receiving mon).
  mod.hooks:wrap("exp.gain", function(next, ctx)
    local exp = next(ctx)
    if not opt("underdog_exp") or type(exp) ~= "number" then
      return exp
    end
    local mon = ctx and ctx.mon
    local foeLv = ctx and ctx.level
    if not mon or not foeLv or (mon.hp or 0) <= 0 then
      return exp
    end
    local gap = (tonumber(foeLv) or 0) - (tonumber(mon.level) or 0)
    local mult = 1
    if gap >= 8 then
      mult = 1.5
    elseif gap >= 4 then
      mult = 1.25
    else
      return exp
    end
    local boosted = math.max(1, math.floor(exp * mult))
    -- Cap: never more than +50% or +80 raw over the vanilla share.
    return math.min(boosted, math.floor(exp * 1.5), exp + 80)
  end)

  -- Fainted mons who fought well still get Gen 1 stat exp (effort).
  mod.hooks:wrap("battle.exp_award", function(next, ctx)
    next(ctx)
    if not opt("effort_faint") or not ctx or not ctx.battle then
      return
    end
    local battle = ctx.battle
    local state = effortByBattle[battle]
    if not state or not state.mons then
      return
    end
    local foeDef = battle.enemy and battle.enemy.def
    if not foeDef then
      return
    end
    for mon, rec in pairs(state.mons) do
      if rec and rec.fainted and not rec.effortPaid
          and performedWell(rec, battle.enemy) then
        if awardEffortConsolation(battle, mon, foeDef) then
          rec.effortPaid = true
        end
      end
    end
  end)

  mod.events:on("battle.started", function(ev)
    if ev and ev.battle then
      lowWarned[ev.battle] = { player = false, enemy = false }
      clearBattleMomentum(ev.battle)
      clearEffort(ev.battle)
      clearCalloutPickState(ev.battle)
    end
  end)

  mod.events:on("battle.ended", function(ev)
    if ev and ev.battle then
      resolvePendingDamage(ev.battle)
      clearCalloutPickState(ev.battle)
      revealPlayerPic(ev.battle, false)
    end
  end)

  mod.events:on("battle.turn_started", function(ev)
    -- Keep cover buffs across the turn; only reset per-turn counter flags.
    resetMomentum(ev and ev.battle)
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
    -- Cover buffs belong to the mon that dodged; wipe on your switch.
    if side == "player" then
      resolvePendingDamage(battle)
      clearCalloutPickState(battle)
      revealPlayerPic(battle, false)
      local ms = momentumState(battle)
      ms.temp = {
        evasion = 0,
        defense = 0,
        cover = false,
        picHidden = false,
        entrenched = false,
      }
      ms.mode = nil
      ms.boosted = false
    elseif side == "enemy" then
      local ms = momentumState(battle)
      ms.enemyTemp = { evasion = 0, defense = 0, cover = false }
      ms.enemyMode = nil
      ms.enemyBoosted = false
      ms.enemyReactedThisTurn = false
    end
    -- New battler may already be low.
    checkLowHp(battle, ev.battler)
  end)

  mod.events:on("battle.move_used", function(ev)
    if not ev or not ev.battle or not ev.user or not ev.user.isPlayer then
      return
    end
    local mon = ev.user.mon
    local rec = effortRec(ev.battle, mon)
    if rec then
      rec.moves = (rec.moves or 0) + 1
    end
  end)

  mod.events:on("battle.fainted", function(ev)
    if not ev or not ev.battle or not ev.battler then
      return
    end
    if ev.battler.isPlayer then
      local rec = effortRec(ev.battle, ev.battler.mon)
      if rec then
        rec.fainted = true
      end
      -- Mid-pick faint should not leave a deferred hit hanging.
      resolvePendingDamage(ev.battle)
      clearCalloutPickState(ev.battle)
      revealPlayerPic(ev.battle, false)
    end
  end)

  mod.events:on("battle.damage_dealt", function(ev)
    checkLowHp(ev and ev.battle, ev and ev.target)
    if not ev or not ev.battle then
      return
    end
    local user, target = ev.user, ev.target
    if user and user.isPlayer and target and not target.isPlayer
        and (ev.damage or 0) > 0 then
      local rec = effortRec(ev.battle, user.mon)
      if rec then
        rec.damage = (rec.damage or 0) + (ev.damage or 0)
      end
    end
    if not opt("momentum_counter") then
      return
    end
    -- Physical connect: only an off-chance to arm counter (misses arm via
    -- battle.accuracy). Keeps COUNTER/HOLD from popping every trade.
    if target and target.isPlayer and user and not user.isPlayer
        and (ev.damage or 0) > 0 and not foeMoveIsSpecial(ev.move)
        and rollPhysicalCounterArm() then
      local state = momentumState(ev.battle)
      state.mode = "counter"
      state.boosted = false
    end
    if user and user.isPlayer and target and not target.isPlayer
        and (ev.damage or 0) > 0 and not foeMoveIsSpecial(ev.move)
        and rollPhysicalCounterArm() then
      local state = momentumState(ev.battle)
      state.enemyMode = "counter"
      state.enemyBoosted = false
    end
    -- In cover / breakthrough messaging after a hit lands.
    if target and (ev.damage or 0) > 0 then
      announceCoverHit(ev.battle, target)
    elseif target and target.isPlayer then
      local st = momentumByBattle[ev.battle]
      if st and st.breakthroughPending then
        announceCoverHit(ev.battle, target)
      end
    end
  end)

  -- Miss creates the opening: foe whiffs you → you can COUNTER next.
  -- Same for trainer foes when you miss them.
  -- Dodge cover miss: keep the move anim so the attack still plays.
  mod.hooks:wrap("battle.accuracy", function(next, ctx)
    local hit = next(ctx)
    if not opt("momentum_counter") or not ctx then
      return hit
    end
    local move = ctx.move
    if not move or (move.power or 0) <= 0 or move.category == "status" then
      return hit
    end
    local user, target, battle = ctx.user, ctx.target, ctx.battle
    if not battle or not user or not target then
      return hit
    end
    local state = momentumState(battle)
    if not hit then
      local function coverName(battler)
        if battler and battler.mon and type(battler.mon.nickname) == "string"
            and battler.mon.nickname ~= "" then
          return battler.mon.nickname
        end
        return (battler and battler.name) or "POKéMON"
      end
      if target.isPlayer and state.temp and state.temp.cover then
        state.keepDodgeMissAnim = true
        state.dodgeMissName = coverName(target)
      elseif (not target.isPlayer) and state.enemyTemp and state.enemyTemp.cover then
        state.keepDodgeMissAnim = true
        state.dodgeMissName = coverName(target)
      end
      if target.isPlayer and not user.isPlayer then
        state.mode = "counter"
        state.boosted = false
      elseif user.isPlayer and not target.isPlayer then
        local kind = battle.kind
        if kind == "trainer" or kind == "link" then
          state.enemyMode = "counter"
          state.enemyBoosted = false
        end
      end
    end
    return hit
  end)

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then
      return
    end
    -- Residual poison/burn and other non-damage_dealt drains.
    checkLowHp(battle, battle.player)
    checkLowHp(battle, battle.enemy)
    local state = momentumByBattle[battle]
    if state then
      state.breakthroughPending = nil
    end
  end)

  -- +25% once for an armed counter (player or trainer foe).
  -- Entrenched: small chance the foe breaks through before damage is rolled.
  mod.hooks:wrap("battle.damage", function(next, ctx)
    if opt("momentum_counter") and ctx then
      local user, target, battle = ctx.user, ctx.target, ctx.battle
      local state = battle and momentumByBattle[battle]
      if state and state.temp and state.temp.entrenched
          and target and target.isPlayer and user and not user.isPlayer
          and rollEntrenchBreakthrough() then
        local def = state.temp.defense or 0
        if def ~= 0 and target.stages then
          local cur = target.stages.defense or 0
          target.stages.defense = math.max(-6, math.min(6, cur - def))
        end
        state.temp.defense = 0
        state.temp.entrenched = false
        state.breakthroughPending = true
      end
    end
    local dmg, info = next(ctx)
    if not opt("momentum_counter") or not ctx then
      return dmg, info
    end
    local user, target, battle = ctx.user, ctx.target, ctx.battle
    if type(dmg) ~= "number" or dmg <= 0 then
      return dmg, info
    end
    local state = battle and momentumByBattle[battle]
    if not state then
      return dmg, info
    end
    if user and user.isPlayer and target and not target.isPlayer
        and state.mode == "counter" and not state.boosted then
      state.boosted = true
      dmg = math.max(1, math.floor(dmg * 5 / 4))
      return dmg, info
    end
    if user and not user.isPlayer and target and target.isPlayer
        and state.enemyMode == "counter" and not state.enemyBoosted then
      state.enemyBoosted = true
      dmg = math.max(1, math.floor(dmg * 5 / 4))
      return dmg, info
    end
    return dmg, info
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
  -- After your move announce, when a physical counter is armed.
  local PLAYER_COUNTER_CALLS = {
    AUTO = {
      "Now, %s!\n%s!",
      "%s!\nHit back! %s!",
      "%s!\nCounter with %s!",
      "That's our opening!\n%s! %s!",
    },
    BOLD = {
      "%s!\nStrike back! %s!",
      "%s!\nHit 'em hard!",
      "Now, %s!\nSmash back!",
      "%s!\nReturn it! %s!",
    },
    TRICKY = {
      "%s!\nTurn it around!",
      "Now, %s!\nCatch 'em!",
      "%s!\nUse that opening!",
      "%s!\nSlip in- %s!",
    },
    SHOWY = {
      "Show 'em,\n%s! %s!",
      "%s!\nMake it flashy!",
      "That's it!\n%s! %s!",
      "%s!\nHero time! %s!",
    },
  }
  -- Style-flavored dodge / brace bases (mon name = %s).
  local DODGE_STYLE = {
    AUTO = {
      "%s!\nDodge it!",
      "Dodge, %s!",
      "%s!\nLook out!",
      "Quick, %s!\nDodge!",
    },
    BOLD = {
      "%s!\nShrug it off!",
      "%s!\nStand tall-dodge!",
      "No way,\n%s! Move!",
      "%s!\nBreak clear!",
    },
    TRICKY = {
      "%s!\nSlip aside!",
      "Fake 'em out,\n%s!",
      "%s!\nWeave through!",
      "Easy, %s!\nSidestep!",
    },
    SHOWY = {
      "%s!\nDance aside!",
      "Show off,\n%s! Dodge!",
      "%s!\nMake it clean!",
      "Stylish,\n%s! Move!",
    },
  }
  local BRACE_STYLE = {
    AUTO = {
      "%s!\nGet ready!",
      "%s!\nBrace yourself!",
      "Hold on,\n%s!",
      "%s!\nWe can counter!",
    },
    BOLD = {
      "%s!\nTake it head-on!",
      "Stand firm,\n%s!",
      "%s!\nDon't flinch!",
      "%s!\nEat that hit!",
    },
    TRICKY = {
      "%s!\nRoll with it!",
      "Wait for it,\n%s!",
      "%s!\nLet 'em commit!",
      "%s!\nThen we hit!",
    },
    SHOWY = {
      "%s!\nMake it look easy!",
      "Chin up,\n%s!",
      "%s!\nPose-and brace!",
      "Cool under fire,\n%s!",
    },
  }
  -- Terrain lines: first %s = mon. Keep short for the text box.
  local DODGE_SCENE = {
    cave = {
      "%s!\nOnto that rock!",
      "%s!\nBehind the rocks!",
      "Dodge-jump,\n%s! That ledge!",
    },
    forest = {
      "%s!\nBehind that tree!",
      "%s!\nInto the brush!",
      "Dodge-leaf,\n%s! Hide!",
    },
    city = {
      "%s!\nBehind that cart!",
      "%s!\nUse that alley!",
      "Dodge-corner,\n%s!",
    },
    route = {
      "%s!\nInto the grass!",
      "%s!\nOff the path!",
      "Wide berth,\n%s!",
    },
    mountain = {
      "%s!\nUp that cliff!",
      "%s!\nUse the ledge!",
      "Higher ground,\n%s!",
    },
    gym = {
      "%s!\nUse the pillars!",
      "%s!\nAround the court!",
      "Sidestep,\n%s! Pillar!",
    },
    water = {
      "%s!\nAlong the shore!",
      "%s!\nSplash aside!",
      "Over the spray,\n%s!",
    },
    grave = {
      "%s!\nBehind a stone!",
      "%s!\nInto the dark!",
      "Fade back,\n%s!",
    },
    indoor = {
      "%s!\nBehind cover!",
      "%s!\nUse the wall!",
      "Clear the floor,\n%s!",
    },
  }
  local BRACE_SCENE = {
    cave = {
      "%s!\nBrace on the rock!",
      "%s!\nDig in here!",
    },
    forest = {
      "%s!\nRoot in place!",
      "%s!\nHold the line!",
    },
    city = {
      "%s!\nHold the street!",
      "%s!\nStand your ground!",
    },
    route = {
      "%s!\nHold firm!",
      "%s!\nHold the path!",
    },
    mountain = {
      "%s!\nBrace on stone!",
      "%s!\nDon't slip!",
    },
    gym = {
      "%s!\nCenter court-hold!",
      "%s!\nGuard the mark!",
    },
    water = {
      "%s!\nBrace in the surf!",
      "%s!\nHold the tide!",
    },
    grave = {
      "%s!\nStand your ground!",
      "%s!\nDon't yield!",
    },
    indoor = {
      "%s!\nHold the room!",
      "%s!\nBrace up!",
    },
  }
  -- Type spice (checked against player curTypes).
  local DODGE_TYPE = {
    FLYING = {
      "%s!\nFly up high!",
      "%s!\nTake the air!",
      "Wing it,\n%s! Up!",
    },
    WATER = {
      "%s!\nDive aside!",
      "%s!\nRide the splash!",
    },
    FIRE = {
      "%s!\nBurst aside!",
      "%s!\nHeat-dash clear!",
    },
    ELECTRIC = {
      "%s!\nZip aside!",
      "%s!\nSpark-step!",
    },
    GRASS = {
      "%s!\nInto the leaves!",
      "%s!\nBloom-step clear!",
    },
    PSYCHIC = {
      "%s!\nSense-and move!",
      "%s!\nBend aside!",
    },
    GHOST = {
      "%s!\nFade through!",
      "%s!\nPhase aside!",
    },
    BUG = {
      "%s!\nFlutter clear!",
      "%s!\nBuzz aside!",
    },
    GROUND = {
      "%s!\nDust-dash!",
      "%s!\nLow and aside!",
    },
    ROCK = {
      "%s!\nStone-step clear!",
    },
    ICE = {
      "%s!\nSlide clear!",
    },
    DRAGON = {
      "%s!\nSoar clear!",
    },
    POISON = {
      "%s!\nSlip aside!",
    },
    FIGHTING = {
      "%s!\nBob and weave!",
    },
  }
  local BRACE_TYPE = {
    FIGHTING = {
      "%s!\nGuard up!",
      "%s!\nTough it out!",
    },
    ROCK = {
      "%s!\nBe the boulder!",
      "%s!\nRock-solid!",
    },
    GROUND = {
      "%s!\nRoot down!",
    },
    STEEL = {
      "%s!\nSteel yourself!",
    },
    NORMAL = {
      "%s!\nTough it out!",
    },
    WATER = {
      "%s!\nRoll with the wave!",
    },
    FLYING = {
      "%s!\nHover-and hold!",
    },
  }
  -- Named characters only (gym leaders, E4, etc.). Class titles like
  -- YOUNGSTER / JR.TRAINER use foe mon callouts instead — no "TRAINER!".
  local NAMED_TRAINERS = {
    BROCK = true,
    MISTY = true,
    ["LT.SURGE"] = true,
    ERIKA = true,
    KOGA = true,
    SABRINA = true,
    BLAINE = true,
    GIOVANNI = true,
    LORELEI = true,
    BRUNO = true,
    AGATHA = true,
    LANCE = true,
    ["PROF.OAK"] = true,
    CHIEF = true,
    ROCKET = true,
  }
  -- trainer, mon, move — softer "NAME:" lead-in, not "NAME!"
  local TRAINER_MOVE_CALLS = {
    "%s:\n%s, use %s!",
    "%s:\n%s! %s!",
    "%s:\nGo, %s! %s!",
    "%s:\n%s, %s!",
    "%s:\n%s, now! %s!",
    "%s:\nDo it, %s! %s!",
  }
  -- Foe Pokémon callouts when the trainer label is a generic class.
  local FOE_MOVE_CALLS = {
    "%s!\nUse %s!",
    "%s, use\n%s!",
    "Go, %s!\n%s!",
    "%s!\n%s!",
    "%s!\n%s, now!",
    "%s!\nQuick, %s!",
    "Come on,\n%s! %s!",
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

  -- Personal / boss names only. Class labels (JR.TRAINER, YOUNGSTER, …)
  -- and anything containing "TRAINER" are treated as generic.
  local function personalTrainerName(battle)
    local name = battle and battle.trainer and battle.trainer.name
    if type(name) ~= "string" or name == "" then
      return nil
    end
    local key = name:upper()
    if key:find("TRAINER", 1, true) then
      return nil
    end
    if key:match("^RIVAL%d*$") then
      return nil
    end
    if NAMED_TRAINERS[key] then
      return name
    end
    -- Rival overlay uses the save's rival name (e.g. BLUE) — keep it.
    local kind = battle.oppClass
    if kind == "OPP_RIVAL1" or kind == "OPP_RIVAL2" or kind == "OPP_RIVAL3" then
      return name
    end
    return nil
  end

  -- Battle text box is 18 glyphs wide (Theme.textBox.maxCols).
  local BATTLE_TEXT_COLS = 18

  local function battleGlyphLen(s)
    local n = 0
    for _ in tostring(s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      n = n + 1
    end
    return n
  end

  local function fitsBattleLine(s)
    return battleGlyphLen(s) <= BATTLE_TEXT_COLS
  end

  -- Keep anime callouts inside the 2-line box; spill to a 3rd line or CONT.
  local function formatEnemyMoveCall(trainer, mon, move)
    mon = tostring(mon or "POKéMON")
    move = tostring(move or "MOVE")
    if trainer and trainer ~= "" then
      local head = tostring(trainer) .. ":"
      local one = mon .. ", use " .. move .. "!"
      if fitsBattleLine(head) and fitsBattleLine(one) then
        return head .. "\n" .. one
      end
      local mid = mon .. ", use"
      local tail = move .. "!"
      if fitsBattleLine(head) and fitsBattleLine(mid) and fitsBattleLine(tail) then
        return head .. "\n" .. mid .. "\n" .. tail
      end
      local short = mon .. "! " .. move .. "!"
      if fitsBattleLine(head) and fitsBattleLine(short) then
        return head .. "\n" .. short
      end
      if fitsBattleLine(head) and fitsBattleLine(mon .. "!") and fitsBattleLine(tail) then
        return head .. "\n" .. mon .. "!\n" .. tail
      end
      -- Last resort: CONT so the move name isn't clipped.
      return head .. "\n" .. mon .. "!\v" .. move .. "!"
    end
    local a = mon .. "!\nUse " .. move .. "!"
    if fitsBattleLine(mon .. "!") and fitsBattleLine("Use " .. move .. "!") then
      return a
    end
    if fitsBattleLine(mon .. ", use") and fitsBattleLine(move .. "!") then
      return mon .. ", use\n" .. move .. "!"
    end
    return mon .. "!\n" .. move .. "!"
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
      local trainer = personalTrainerName(battle)
      if trainer then
        local fitted = formatEnemyMoveCall(trainer, bare, move)
        if fitted then
          return fitted
        end
        return pickFormatted(TRAINER_MOVE_CALLS, trainer, bare, move)
          or (trainer .. ":\n" .. bare .. ", use " .. move .. "!")
      end
      return formatEnemyMoveCall(nil, bare, move)
        or pickFormatted(FOE_MOVE_CALLS, bare, move)
        or (bare .. "!\nUse " .. move .. "!")
    end
    -- Finish / counter / dodge are separate queue pages after the announce.
    return pickFormatted(PLAYER_MOVE_CALLS, bare, move)
      or (bare .. "!\nUse " .. move .. "!")
  end

  local function rewriteLevelUpText(text)
    if opt("generic_level_up") and isGrewToLevelText(text) then
      return pickLine(LEVEL_UP_LINES) or "Your POKéMON has\ngrown stronger!"
    end
    return text
  end

  local EXP_GAIN_LINES = {
    "%s grew\nfrom the battle!",
    "%s gained\nexperience!",
    "%s learned\nfrom that fight!",
    "A hard lesson-\n%s grew!",
  }

  local function rewriteExpGainText(text)
    if not opt("generic_level_up") then
      return text
    end
    local s = tostring(text or "")
    local lower = s:lower()
    if not (lower:find("exp", 1, true) or lower:find("experience", 1, true)) then
      return text
    end
    if not s:find("%d") then
      return text
    end
    local name = s:match("^([^\n]+)%s+gained")
      or s:match("^([^\n]+) gained")
    if not name or name == "" then
      name = "Your POKéMON"
    end
    name = name:gsub("%s+$", "")
    local line = pickLine(EXP_GAIN_LINES) or "%s grew\nfrom the battle!"
    return line:format(name)
  end

  local function rewriteBattleText(battle, text)
    text = rewriteLevelUpText(text)
    text = rewriteExpGainText(text)
    return rewriteMoveCallText(battle, text)
  end

  local function playerMonName(battle)
    local p = battle and battle.player
    if not p then
      return "POKéMON"
    end
    if p.mon and type(p.mon.nickname) == "string" and p.mon.nickname ~= "" then
      return p.mon.nickname
    end
    return p.name or "POKéMON"
  end

  local function findMoveByName(battle, name)
    local moves = battle and battle.data and battle.data.moves
    if not moves or not name then
      return nil
    end
    local want = tostring(name):upper()
    local direct = moves[want]
    if type(direct) == "table" then
      return direct
    end
    for _, def in pairs(moves) do
      if type(def) == "table" and def.name and tostring(def.name):upper() == want then
        return def
      end
    end
    return nil
  end

  local function battleScene(battle)
    local mapId = ""
    if battle and type(battle.currentMapId) == "function" then
      mapId = tostring(battle:currentMapId() or "")
    end
    local id = mapId:upper()
    local tileset = nil
    local maps = battle and battle.game and battle.game.data and battle.game.data.maps
    local def = maps and mapId ~= "" and maps[mapId]
    if type(def) == "table" then
      tileset = def.tileset
    end
    local ts = tostring(tileset or ""):upper()

    if ts == "CAVERN" or ts == "UNDERGROUND"
        or id:find("CAVE", 1, true) or id:find("TUNNEL", 1, true)
        or id:find("MT_MOON", 1, true) or id:find("ROCK_TUNNEL", 1, true) then
      return "cave"
    end
    if ts == "FOREST" or ts == "FOREST_GATE" or id:find("FOREST", 1, true) then
      return "forest"
    end
    if ts == "CEMETERY" or id:find("POKEMON_TOWER", 1, true)
        or id:find("LAVENDER", 1, true) then
      return "grave"
    end
    if ts == "GYM" or ts == "DOJO" or id:find("_GYM", 1, true) or id:find("GYM_", 1, true) then
      return "gym"
    end
    if ts == "PLATEAU" or id:find("VICTORY", 1, true)
        or id:find("MT_", 1, true) then
      return "mountain"
    end
    if ts == "SHIP" or ts == "SHIP_PORT" or id:find("SEAFOAM", 1, true)
        or id:find("SS_ANNE", 1, true) then
      return "water"
    end
    if id:find("CITY", 1, true) or id:find("TOWN", 1, true) then
      return "city"
    end
    if ts == "HOUSE" or ts == "MART" or ts == "POKECENTER" or ts == "INTERIOR"
        or ts == "LAB" or ts == "LOBBY" or ts == "FACILITY" or ts == "CLUB"
        or ts == "MUSEUM" or ts == "MANSION" or ts == "GATE"
        or ts == "REDS_HOUSE_1" or ts == "REDS_HOUSE_2" then
      return "indoor"
    end
    return "route"
  end

  local function playerTypeSet(battle)
    local set = {}
    local types = battle and battle.player and battle.player.curTypes
    if type(types) ~= "table" then
      return set
    end
    for _, ty in ipairs(types) do
      local key = tostring(ty or ""):upper()
      if key == "PSYCHIC_TYPE" then
        key = "PSYCHIC"
      end
      if key ~= "" then
        set[key] = true
      end
    end
    return set
  end

  local function buildCallPool(kind, battle)
    local style = calloutStyle()
    local scene = battleScene(battle)
    local types = playerTypeSet(battle)
    local pool = {}
    -- Each entry: { line = "...", boost = 1|2 } for dodge/brace tiers.

    local function add(list, boost)
      if type(list) ~= "table" then
        return
      end
      for i = 1, #list do
        pool[#pool + 1] = { line = list[i], boost = boost or 1 }
      end
    end

    if kind == "dodge" then
      add(DODGE_STYLE[style] or DODGE_STYLE.AUTO, style == "SHOWY" and 2 or 1)
      add(DODGE_SCENE[scene], 2)
      for ty, on in pairs(types) do
        if on then
          add(DODGE_TYPE[ty], 2)
        end
      end
    elseif kind == "brace" then
      add(BRACE_STYLE[style] or BRACE_STYLE.AUTO, 1)
      add(BRACE_SCENE[scene], 1)
      for ty, on in pairs(types) do
        if on then
          add(BRACE_TYPE[ty], 2)
        end
      end
    elseif kind == "counter" then
      local lines = PLAYER_COUNTER_CALLS[style] or PLAYER_COUNTER_CALLS.AUTO
      local defDrop = (style == "SHOWY" or style == "BOLD") and 2 or 1
      add(lines, defDrop)
    end

    return pool
  end

  local function pickCallEntry(kind, battle, monName, moveName)
    local pool = buildCallPool(kind, battle)
    if #pool == 0 then
      return nil, 1
    end
    local entry = pickLine(pool)
    if not entry then
      return nil, 1
    end
    local line = formatCall(entry.line, monName, moveName)
    return line, entry.boost or 1
  end

  local DODGE_FAIL_CALLS = {
    "%s!\nToo slow!",
    "%s!\nCouldn't dodge!",
    "No time,\n%s!",
    "%s!\nDidn't make it!",
    "Almost,\n%s! Too late!",
  }
  -- In cover, but the attack still connected.
  local COVER_HIT_CALLS = {
    "But it found\n%s!",
    "Still got hit,\n%s!",
    "No escape-\n%s was hit!",
    "%s!\nHit through cover!",
    "They saw\n%s anyway!",
  }
  -- Miss while dodging — replaces vanilla "attack missed!".
  local DODGE_WHIFF_CALLS = {
    "But %s\ndodged aside!",
    "%s slipped\naway!",
    "Too slow!\n%s dodged!",
    "The attack\nwhiffed past!",
    "%s!\nSafe in cover!",
  }
  -- Foe punches through your entrenched guard (DEF stripped for this hit).
  local BREAKTHROUGH_CALLS = {
    "Broke through\nthe guard!",
    "The defense\nshattered!",
    "Pushed past\n%s!",
    "Guard broken!\n%s!",
  }
  local LEAVE_COVER_CALLS = {
    "%s!\nLeft cover!",
    "Breaking cover,\n%s!",
    "%s!\nComing out!",
    "Leave cover,\n%s! Strike!",
  }
  -- Simple trainer-foe auto reactions — opposing trainer monologue, not
  -- narrator lines like "hid in the grass".
  -- With personal trainer name: (trainer, mon). Generic class: (mon) only.
  local TRAINER_FOE_DODGE_CALLS = {
    "%s:\n%s, dodge!",
    "%s:\nDodge it, %s!",
    "%s:\n%s, get aside!",
    "%s:\nMove, %s!",
    "%s:\n%s, now-dodge!",
  }
  local FOE_DODGE_CALLS = {
    "%s!\nDodge it!",
    "%s, get\naside!",
    "%s!\nMove!",
    "Quick,\n%s! Dodge!",
  }
  local TRAINER_FOE_DODGE_FAIL_CALLS = {
    "%s:\nToo slow, %s!",
    "%s:\n%s, no!",
    "%s:\nMissed it,\n%s!",
  }
  local FOE_DODGE_FAIL_CALLS = {
    "%s!\nToo slow!",
    "%s!\nCouldn't dodge!",
    "No escape,\n%s!",
  }
  local TRAINER_FOE_BRACE_CALLS = {
    "%s:\n%s, brace!",
    "%s:\nDig in, %s!",
    "%s:\n%s, hold firm!",
    "%s:\nStand firm,\n%s!",
  }
  local FOE_BRACE_CALLS = {
    "%s!\nBrace!",
    "%s, dig\nin!",
    "%s!\nHold firm!",
    "Stand firm,\n%s!",
  }
  local TRAINER_FOE_COUNTER_CALLS = {
    "%s:\n%s, hit back!",
    "%s:\nCounter,\n%s!",
    "%s:\nNow, %s!\nStrike!",
  }
  local FOE_COUNTER_CALLS = {
    "%s!\nHit back!",
    "%s!\nCounter!",
    "Now, %s!\nStrike!",
  }
  local TRAINER_FOE_AGAIN_CALLS = {
    "%s:\nAgain, %s!",
    "%s:\n%s, once more!",
    "%s:\nDon't stop,\n%s!",
  }
  local FOE_AGAIN_CALLS = {
    "%s!\nAgain!",
    "%s, once\nmore!",
    "Don't stop,\n%s!",
  }
  local TRAINER_FOE_LEAVE_COVER_CALLS = {
    "%s:\n%s, break cover!",
    "%s:\nCome out, %s!",
    "%s:\n%s, now-strike!",
  }
  local FOE_LEAVE_COVER_CALLS = {
    "%s!\nBreak cover!",
    "Come out,\n%s!",
    "%s, now-\nstrike!",
  }
  local AGAIN_CALLS = {
    "%s!\nAgain!",
    "%s!\nOne more!",
    "Don't stop!\n%s!",
    "%s!\nKeep going!",
    "Again!\n%s!",
  }

  local function enemyMonName(battle)
    local e = battle and battle.enemy
    if not e then
      return "POKéMON"
    end
    if e.mon and type(e.mon.nickname) == "string" and e.mon.nickname ~= "" then
      return e.mon.nickname
    end
    return e.name or "POKéMON"
  end

  -- Prefer "BROCK: Onix, dodge!" when we know the trainer; else mon order.
  local function pickFoeTrainerLine(battle, trainerTemplates, monTemplates, monName)
    monName = monName or enemyMonName(battle)
    local trainer = personalTrainerName(battle)
    if trainer and trainerTemplates then
      return pickFormatted(trainerTemplates, trainer, monName)
        or (trainer .. ":\n" .. monName .. "!")
    end
    return pickFormatted(monTemplates, monName)
      or (monName .. "!")
  end

  announceCoverHit = function(battle, target)
    if not opt("momentum_counter") or not battle or not target then
      return
    end
    local state = momentumByBattle[battle]
    if not state then
      return
    end
    if state.breakthroughPending and target and target.isPlayer then
      state.breakthroughPending = false
      local name = playerMonName(battle)
      local line = pickFormatted(BREAKTHROUGH_CALLS, name)
        or "Broke through\nthe guard!"
      if type(battle.sayNext) == "function" then
        battle:sayNext(line)
      end
    end
    local inCover = false
    local name = nil
    if target.isPlayer and state.temp and state.temp.cover then
      inCover = true
      name = playerMonName(battle)
    elseif (not target.isPlayer) and state.enemyTemp and state.enemyTemp.cover then
      inCover = true
      name = enemyMonName(battle)
    end
    if not inCover then
      return
    end
    local line = pickFormatted(COVER_HIT_CALLS, name)
      or ("But it found\n" .. (name or "POKéMON") .. "!")
    if type(battle.sayNext) == "function" then
      battle:sayNext(line)
    end
  end

  rewriteDodgeMissText = function(battle, text)
    if type(text) ~= "string" or not text:lower():find("attack missed", 1, true) then
      return text
    end
    local state = battle and momentumByBattle[battle]
    if not state or not state.keepDodgeMissAnim then
      return text
    end
    local name = state.dodgeMissName or "POKéMON"
    state.keepDodgeMissAnim = false
    state.dodgeMissName = nil
    return pickFormatted(DODGE_WHIFF_CALLS, name)
      or ("But " .. name .. "\ndodged aside!")
  end

  local function trainerFoeReactionsOn(battle)
    if not opt("momentum_counter") or not battle then
      return false
    end
    local kind = battle.kind
    return kind == "trainer" or kind == "link"
  end

  -- Auto foe dodge/brace once per turn when you attack (trainer battles).
  -- Returns reactionText, buffList, trackTempBuffs.
  local function tryFoeCoverReaction(battle, moveDef)
    if not trainerFoeReactionsOn(battle) or not moveDef then
      return nil
    end
    if (moveDef.power or 0) <= 0 or moveDef.category == "status" then
      return nil
    end
    local state = momentumState(battle)
    if state.enemyReactedThisTurn then
      return nil
    end
    state.enemyReactedThisTurn = true
    local foe = enemyMonName(battle)
    if foeMoveIsSpecial(moveDef) then
      if not rollDodgeSuccess() then
        local fail = pickFoeTrainerLine(
          battle, TRAINER_FOE_DODGE_FAIL_CALLS, FOE_DODGE_FAIL_CALLS, foe)
        return fail, nil, false
      end
      state.enemyTemp.cover = true
      local line = pickFoeTrainerLine(
        battle, TRAINER_FOE_DODGE_CALLS, FOE_DODGE_CALLS, foe)
      return line, {
        { who = "enemy", stat = "evasion", delta = 1 },
      }, true
    end
    state.enemyTemp.cover = true
    local line = pickFoeTrainerLine(
      battle, TRAINER_FOE_BRACE_CALLS, FOE_BRACE_CALLS, foe)
    return line, {
      { who = "enemy", stat = "defense", delta = 1 },
    }, true
  end

  local function rollEnemyCounter()
    local r = (love and love.math and love.math.random) or math.random
    return r() < 0.50
  end

  local function rollEnemyAgain()
    local r = (love and love.math and love.math.random) or math.random
    return r() < 0.40
  end

  -- Player-facing pick options per scene (label shown in menu).
  local SCENE_PICK = {
    cave = {
      { label = "ROCK", line = "%s!\nOnto that rock!", boost = 2 },
      { label = "LEDGE", line = "%s!\nUp that ledge!", boost = 2 },
      { label = "DODGE", line = "%s!\nDodge it!", boost = 1 },
    },
    forest = {
      { label = "TREE", line = "%s!\nBehind that tree!", boost = 2 },
      { label = "BRUSH", line = "%s!\nInto the brush!", boost = 2 },
      { label = "DODGE", line = "%s!\nDodge it!", boost = 1 },
    },
    city = {
      { label = "CART", line = "%s!\nBehind that cart!", boost = 2 },
      { label = "ALLEY", line = "%s!\nUse that alley!", boost = 2 },
      { label = "DODGE", line = "%s!\nDodge it!", boost = 1 },
    },
    route = {
      { label = "GRASS", line = "%s!\nInto the grass!", boost = 2 },
      { label = "PATH", line = "%s!\nOff the path!", boost = 1 },
      { label = "DODGE", line = "%s!\nDodge it!", boost = 1 },
    },
    mountain = {
      { label = "CLIFF", line = "%s!\nUp that cliff!", boost = 2 },
      { label = "LEDGE", line = "%s!\nUse the ledge!", boost = 2 },
      { label = "DODGE", line = "%s!\nDodge it!", boost = 1 },
    },
    gym = {
      { label = "PILLAR", line = "%s!\nUse the pillars!", boost = 2 },
      { label = "COURT", line = "%s!\nAround the court!", boost = 1 },
      { label = "DODGE", line = "%s!\nDodge it!", boost = 1 },
    },
    water = {
      { label = "SHORE", line = "%s!\nAlong the shore!", boost = 2 },
      { label = "SPLASH", line = "%s!\nSplash aside!", boost = 2 },
      { label = "DODGE", line = "%s!\nDodge it!", boost = 1 },
    },
    grave = {
      { label = "STONE", line = "%s!\nBehind a stone!", boost = 2 },
      { label = "SHADOW", line = "%s!\nInto the dark!", boost = 2 },
      { label = "DODGE", line = "%s!\nDodge it!", boost = 1 },
    },
    indoor = {
      { label = "WALL", line = "%s!\nUse the wall!", boost = 2 },
      { label = "COVER", line = "%s!\nBehind cover!", boost = 2 },
      { label = "DODGE", line = "%s!\nDodge it!", boost = 1 },
    },
  }
  local SCENE_BRACE_PICK = {
    cave = {
      { label = "ROCK", line = "%s!\nBrace on the rock!", boost = 2 },
      { label = "DIG IN", line = "%s!\nDig in here!", boost = 2 },
      { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
    },
    forest = {
      { label = "ROOTS", line = "%s!\nRoot in place!", boost = 2 },
      { label = "HOLD", line = "%s!\nHold the line!", boost = 1 },
      { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
    },
    city = {
      { label = "STREET", line = "%s!\nHold the street!", boost = 2 },
      { label = "GROUND", line = "%s!\nStand your ground!", boost = 1 },
      { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
    },
    route = {
      { label = "PATH", line = "%s!\nHold the path!", boost = 1 },
      -- Strong brace: high DEF, but next attack is locked out (body-agnostic).
      { label = "DIG IN", line = "%s!\nEntrench!", boost = 2, entrench = true },
      { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
    },
    mountain = {
      { label = "STONE", line = "%s!\nBrace on stone!", boost = 2 },
      { label = "HOLD", line = "%s!\nDon't slip!", boost = 1 },
      { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
    },
    gym = {
      { label = "COURT", line = "%s!\nCenter court-hold!", boost = 2 },
      { label = "GUARD", line = "%s!\nGuard the mark!", boost = 1 },
      { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
    },
    water = {
      { label = "SURF", line = "%s!\nBrace in the surf!", boost = 2 },
      { label = "TIDE", line = "%s!\nHold the tide!", boost = 1 },
      { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
    },
    grave = {
      { label = "STAND", line = "%s!\nStand your ground!", boost = 1 },
      { label = "HOLD", line = "%s!\nDon't yield!", boost = 2 },
      { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
    },
    indoor = {
      { label = "ROOM", line = "%s!\nHold the room!", boost = 1 },
      { label = "BRACE", line = "%s!\nBrace up!", boost = 1 },
      { label = "GUARD", line = "%s!\nGuard up!", boost = 2 },
    },
  }
  local TYPE_PICK_EXTRA = {
    FLYING = { label = "FLY UP", line = "%s!\nFly up high!", boost = 2 },
    WATER = { label = "DIVE", line = "%s!\nDive aside!", boost = 2 },
    ELECTRIC = { label = "ZIP", line = "%s!\nZip aside!", boost = 2 },
    FIRE = { label = "BURST", line = "%s!\nBurst aside!", boost = 2 },
    PSYCHIC = { label = "SENSE", line = "%s!\nSense-and move!", boost = 2 },
    GHOST = { label = "FADE", line = "%s!\nFade through!", boost = 2 },
    GRASS = { label = "BRUSH", line = "%s!\nInto the leaves!", boost = 2 },
  }

  local MoveEffects = require("src.battle.MoveEffects")
  local Menu = require("src.ui.Menu")
  local EffectRegistry = require("src.battle.EffectRegistry")
  local origRunDamaging = EffectRegistry.runDamaging

  -- Callout pages need a beat so they aren't instant.
  local CALLOUT_AUTO_DELAY = 55

  local function enqueuePromptAfter(battle, text)
    if type(battle) ~= "table" or type(battle.queue) ~= "table" then
      return
    end
    battle.nextInsert = (battle.nextInsert or 0) + 1
    table.insert(battle.queue, battle.nextInsert, { text = text })
  end

  local function enqueueAutoAfter(battle, text, delay)
    if type(battle) ~= "table" or type(battle.queue) ~= "table" then
      return
    end
    battle.nextInsert = (battle.nextInsert or 0) + 1
    table.insert(battle.queue, battle.nextInsert, {
      text = text,
      auto = true,
      autoDelay = delay or CALLOUT_AUTO_DELAY,
    })
  end

  -- True second strike after a counter (separate anim + damage roll).
  -- Stripped record: never miss, single hit, no recoil/secondary re-fire.
  local function tryAgainStrike(battle, ctx, monName, foeSide)
    if not opt("momentum_counter") or not battle or not ctx then
      return false
    end
    local state = momentumState(battle)
    if state.againInProgress then
      return false
    end
    local target = ctx.target
    local user = ctx.user
    local move = ctx.move
    if not target or not target.mon or (target.mon.hp or 0) <= 0 then
      return false
    end
    if not user or not user.mon or (user.mon.hp or 0) <= 0 then
      return false
    end
    if (ctx.totalDealt or 0) <= 0 then
      return false
    end
    if not move or (move.power or 0) <= 0 or move.category == "status" then
      return false
    end
    local mid = tostring(move.id or ""):upper()
    if mid == "COUNTER" or mid == "EXPLOSION" or mid == "SELFDESTRUCT"
        or mid == "STRUGGLE" then
      return false
    end

    state.againInProgress = true
    local line
    if foeSide then
      line = pickFoeTrainerLine(
        battle, TRAINER_FOE_AGAIN_CALLS, FOE_AGAIN_CALLS, monName or enemyMonName(battle))
    else
      line = pickFormatted(AGAIN_CALLS, monName or playerMonName(battle))
        or ((monName or "POKéMON") .. "!\nAgain!")
    end
    enqueueAutoAfter(battle, line, CALLOUT_AUTO_DELAY)
    -- Force a fresh anim row (don't reuse the first strike's moveAnimRow).
    battle.moveAnimRow = nil
    local stripped = {
      neverMiss = true,
      hitCount = function()
        return 1
      end,
    }
    local ok = pcall(origRunDamaging, battle, ctx, stripped)
    state.againInProgress = false
    return ok and true or false
  end

  local function buildPickChoices(kind, battle)
    local scene = battleScene(battle)
    local tableFor = kind == "brace" and SCENE_BRACE_PICK or SCENE_PICK
    local list = tableFor[scene] or tableFor.route or {}
    local choices = {}
    for i = 1, #list do
      choices[#choices + 1] = list[i]
    end
    if kind == "dodge" then
      local types = playerTypeSet(battle)
      for ty, on in pairs(types) do
        if on and TYPE_PICK_EXTRA[ty] then
          choices[#choices + 1] = TYPE_PICK_EXTRA[ty]
        end
      end
    end
    if #choices == 0 then
      if kind == "brace" then
        choices[1] = { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 }
      else
        choices[1] = { label = "DODGE", line = "%s!\nDodge it!", boost = 1 }
      end
    end
    return choices
  end

  local function insertBeforeAnim(battle, item)
    if type(battle) ~= "table" or type(battle.queue) ~= "table" then
      return
    end
    local idx = nil
    -- Prefer the foe move anim row, not a dodge hide we may have queued.
    if battle.moveAnimRow then
      for i, row in ipairs(battle.queue) do
        if row == battle.moveAnimRow then
          idx = i
          break
        end
      end
    end
    if not idx then
      for i, row in ipairs(battle.queue) do
        if type(row) == "table" and row.anim then
          idx = i
          break
        end
      end
    end
    if idx then
      table.insert(battle.queue, idx, item)
    else
      table.insert(battle.queue, 1, item)
    end
  end

  local function indexOfMoveAnim(battle)
    if type(battle) ~= "table" or type(battle.queue) ~= "table" then
      return nil
    end
    local want = battle.moveAnimRow
    if not want then
      return nil
    end
    for i, row in ipairs(battle.queue) do
      if row == want then
        return i
      end
    end
    return nil
  end

  -- Dig charge = SLIDE_DOWN_ANIM; Fly charge = TELEPORT. Reuse those hides
  -- even alongside Stadium/Dramaless — the GB pic hide still reads well.
  local function dodgeAnimFor(choice, battle)
    local label = ""
    if type(choice) == "table" then
      label = tostring(choice.label or ""):upper()
    elseif type(choice) == "string" then
      label = choice:upper()
    end
    if label == "FLY UP" or label == "ZIP" or label == "BURST"
        or label == "FADE" or label == "SENSE" then
      return "TELEPORT"
    end
    if label == "DIVE" or label == "SPLASH" then
      return "SLIDE_DOWN_ANIM"
    end
    if label == "" and battle then
      local types = playerTypeSet(battle)
      if types.FLYING or types.PSYCHIC or types.GHOST or types.ELECTRIC then
        return "TELEPORT"
      end
    end
    return "SLIDE_DOWN_ANIM"
  end

  enqueueDodgeHideAnim = function(battle, choice)
    if type(battle) ~= "table" or type(battle.queue) ~= "table" then
      return
    end
    if battle.animationsOn and not battle:animationsOn() then
      local state = momentumState(battle)
      state.temp.picHidden = true
      local player = battle.player
      if player and battle.picFxFor then
        local pf = battle:picFxFor(player)
        if pf then
          pf.kind, pf.hidden = nil, true
        end
      end
      return
    end
    local anim = dodgeAnimFor(choice, battle)
    battle.nextInsert = (battle.nextInsert or 0) + 1
    table.insert(battle.queue, battle.nextInsert, {
      anim = anim,
      attackerIsPlayer = true,
    })
    momentumState(battle).temp.picHidden = true
  end

  enqueueBraceAnim = function(battle)
    if type(battle) ~= "table" or type(battle.queue) ~= "table" then
      return
    end
    battle.nextInsert = (battle.nextInsert or 0) + 1
    table.insert(battle.queue, battle.nextInsert, {
      fn = function()
        if not battle.picFxFor or not battle.player then
          return
        end
        local pf = battle:picFxFor(battle.player)
        if pf then
          -- Blink ends shown (unlike shakeBF, which clears the pic).
          pf.kind, pf.t = "blink", 0
          pf.hidden = nil
        end
      end,
    })
  end

  revealPlayerPic = function(battle, withEmerge)
    local state = battle and momentumByBattle[battle]
    local wasHidden = state and state.temp and state.temp.picHidden
    if state and state.temp then
      state.temp.picHidden = false
    end
    local player = battle and battle.player
    if not player or not wasHidden then
      return
    end
    local function showNow()
      if not battle.picFxFor then
        return
      end
      local pf = battle:picFxFor(player)
      if not pf then
        return
      end
      if withEmerge then
        pf.kind, pf.t = "slideUp", 0
        pf.hidden, pf.ox, pf.oy = nil, 0, 0
      else
        pf.kind, pf.t, pf.hidden, pf.ox, pf.oy = nil, nil, nil, 0, 0
      end
    end
    if withEmerge and type(battle.queue) == "table" then
      battle.nextInsert = (battle.nextInsert or 0) + 1
      table.insert(battle.queue, battle.nextInsert, { fn = showNow })
    else
      showNow()
    end
  end

  clearCalloutPickState = function(battle)
    if not battle then
      return
    end
    local state = momentumByBattle[battle]
    if not state then
      return
    end
    state.awaitingPick = nil
    state.pendingDamage = nil
    state.pendingFoeReaction = nil
  end

  -- Foe dodge/brace stashed while COUNTER/HOLD is pending (so that menu
  -- isn't shown after "couldn't dodge!" as if they were related).
  local function flushPendingFoeReaction(battle)
    if not battle then
      return
    end
    local state = momentumByBattle[battle]
    local pending = state and state.pendingFoeReaction
    if state then
      state.pendingFoeReaction = nil
    end
    if not pending or not pending.moveDef then
      return
    end
    local foeLine, foeBuffs, foeTrack = tryFoeCoverReaction(battle, pending.moveDef)
    if not foeLine then
      return
    end
    applyCalloutBuffs(battle, foeBuffs, foeTrack)
    insertBeforeAnim(battle, {
      text = foeLine,
      auto = true,
      autoDelay = CALLOUT_AUTO_DELAY,
    })
  end

  resolvePendingDamage = function(battle)
    if not battle then
      return
    end
    local state = momentumByBattle[battle]
    if not state or not state.pendingDamage then
      return
    end
    local pending = state.pendingDamage
    local wasCounter = state.awaitingPick == "counter"
    state.awaitingPick = nil
    state.pendingDamage = nil
    if wasCounter then
      -- Abandoned menu counts as HOLD.
      state.mode = nil
      state.boosted = false
    end
    if not pending.ctx then
      state.pendingFoeReaction = nil
      return
    end
    -- Strip any leftover pick UI rows so the hit can finish.
    if type(battle.queue) == "table" then
      for i = #battle.queue, 1, -1 do
        local row = battle.queue[i]
        if type(row) == "table" and row.ui then
          table.remove(battle.queue, i)
        end
      end
    end
    flushPendingFoeReaction(battle)
    if type(battle.queue) == "table" then
      local animIdx = indexOfMoveAnim(battle) or #battle.queue
      battle.nextInsert = animIdx
    end
    origRunDamaging(battle, pending.ctx, pending.record)
  end

  local function threatWantsPick(battle, move)
    if calloutPickMode() == "ALWAYS" then
      return true
    end
    if calloutPickMode() ~= "THREAT" then
      return false
    end
    local player = battle and battle.player
    local mon = player and player.mon
    if mon and mon.stats and mon.stats.hp and mon.stats.hp > 0 then
      if (mon.hp or 0) / mon.stats.hp <= lowHpRatio() then
        return true
      end
    end
    local power = move and (move.power or 0) or 0
    if power >= 80 then
      return true
    end
    if power >= 40 and foeMoveIsSpecial(move) then
      return true
    end
    local foeLv = battle and battle.enemy and battle.enemy.mon and battle.enemy.mon.level
    local myLv = mon and mon.level
    if foeLv and myLv and (foeLv - myLv) >= 5 then
      return true
    end
    -- First meaningful foe hit this turn still opens the menu once.
    local state = momentumState(battle)
    if not state.pickOfferedThisTurn then
      return power >= 40
    end
    return false
  end

  local function shouldOfferCalloutPick(battle, move)
    if calloutPickMode() == "OFF" or not opt("momentum_counter") then
      return false
    end
    if not battle or not move then
      return false
    end
    if (move.power or 0) <= 0 or move.category == "status" then
      return false
    end
    return threatWantsPick(battle, move)
  end

  local function finishCalloutPick(battle, me, moveName, kind, choice)
    local state = momentumState(battle)
    state.awaitingPick = nil
    local pending = state.pendingDamage
    state.pendingDamage = nil
    state.enemyActedThisTurn = true

    local failed = kind == "dodge" and not rollDodgeSuccess()
    if failed then
      local fail = pickFormatted(DODGE_FAIL_CALLS, me)
        or (me .. "!\nCouldn't dodge!")
      table.insert(battle.queue, 1, {
        text = fail,
        auto = true,
        autoDelay = CALLOUT_AUTO_DELAY,
      })
    else
      local line = formatCall(choice.line, me, moveName)
        or (me .. "!\n" .. (kind == "brace" and "Brace!" or "Dodge!"))
      table.insert(battle.queue, 1, {
        text = line,
        auto = true,
        autoDelay = CALLOUT_AUTO_DELAY,
      })
      battle.nextInsert = 1
      if kind == "dodge" then
        state.temp.cover = true
        applyCalloutBuffs(battle, {
          { who = "player", stat = "evasion", delta = choice.boost or 1 },
        }, true)
        enqueueDodgeHideAnim(battle, choice)
      else
        local boost = choice.boost or 1
        -- Strong brace: entrench at near-max DEF and wait for a counter opening.
        if boost >= 2 or choice.entrench or choice.guardLock then
          local cur = (battle.player and battle.player.stages
            and battle.player.stages.defense) or 0
          boost = math.max(1, 6 - cur)
          state.temp.entrenched = true
        end
        applyCalloutBuffs(battle, {
          { who = "player", stat = "defense", delta = boost },
        }, true)
        enqueueBraceAnim(battle)
      end
    end

    if pending and pending.ctx then
      -- Damage/faint text must come AFTER the foe's move anim, not after
      -- our dodge hide (which also has row.anim).
      local animIdx = indexOfMoveAnim(battle) or #battle.queue
      battle.nextInsert = animIdx
      -- If the move anim was cancelled/removed, still resolve damage at end.
      if not indexOfMoveAnim(battle) and battle.cancelMoveAnim then
        -- keep nextInsert at end of queue
        battle.nextInsert = #battle.queue
      end
      origRunDamaging(battle, pending.ctx, pending.record)
    end
  end

  local function queueCalloutPickMenu(battle, me, moveName, kind)
    local choices = buildPickChoices(kind, battle)
    insertBeforeAnim(battle, {
      ui = function()
        local items = {}
        for i = 1, #choices do
          local choice = choices[i]
          items[#items + 1] = {
            label = choice.label,
            onSelect = function()
              finishCalloutPick(battle, me, moveName, kind, choice)
            end,
          }
        end
        return Menu.new(battle.game, items, {
          cancelable = false,
          tx = 11,
          ty = 1,
          tw = 9,
        })
      end,
    })
  end

  local function finishCounterPick(battle, me, moveName, doCounter)
    local state = momentumState(battle)
    state.awaitingPick = nil
    local pending = state.pendingDamage
    state.pendingDamage = nil

    if doCounter then
      -- Leave mode=counter so battle.damage still applies +25%.
      state.mode = "counter"
      state.boosted = false
      local line, drop = pickCallEntry("counter", battle, me, moveName)
      line = line or ("Now, " .. me .. "!\nHit back!")
      drop = drop or 1
      table.insert(battle.queue, 1, {
        text = line,
        auto = true,
        autoDelay = CALLOUT_AUTO_DELAY,
      })
      battle.nextInsert = 1
      applyCalloutBuffs(battle, {
        { who = "enemy", stat = "defense", delta = -drop, fromEnemy = true },
      }, false)
    else
      state.mode = nil
      state.boosted = false
    end

    if pending and pending.ctx then
      -- Foe dodge/brace after your COUNTER/HOLD choice, before the hit.
      flushPendingFoeReaction(battle)
      local animIdx = indexOfMoveAnim(battle) or #battle.queue
      battle.nextInsert = animIdx
      origRunDamaging(battle, pending.ctx, pending.record)
      if doCounter then
        -- Damage hook should have consumed the boost; clear arming either way.
        state.mode = nil
        -- Anime follow-through: true second hit if the foe is still up.
        tryAgainStrike(battle, pending.ctx, me, false)
      end
    elseif doCounter then
      state.mode = nil
      state.pendingFoeReaction = nil
    end
  end

  local function queueCounterPickMenu(battle, me, moveName)
    insertBeforeAnim(battle, {
      ui = function()
        return Menu.new(battle.game, {
          {
            label = "COUNTER",
            onSelect = function()
              finishCounterPick(battle, me, moveName, true)
            end,
          },
          {
            label = "HOLD",
            onSelect = function()
              finishCounterPick(battle, me, moveName, false)
            end,
          },
        }, {
          cancelable = false,
          tx = 11,
          ty = 1,
          tw = 9,
        })
      end,
    })
  end

  local function shouldDeferForCalloutPick(battle, ctx)
    if not battle or not ctx then
      return false
    end
    local user, target, move = ctx.user, ctx.target, ctx.move
    if not user or user.isPlayer or not target or not target.isPlayer then
      return false
    end
    if not shouldOfferCalloutPick(battle, move) then
      return false
    end
    local state = momentumState(battle)
    if state.awaitingPick or state.pendingDamage then
      return false
    end
    return true
  end

  local function shouldDeferForCounterPick(battle, ctx)
    if not opt("momentum_counter") or not battle or not ctx then
      return false
    end
    local user, target, move = ctx.user, ctx.target, ctx.move
    if not user or not user.isPlayer or not target or target.isPlayer then
      return false
    end
    if not move or (move.power or 0) <= 0 or move.category == "status" then
      return false
    end
    if not playerHasCounter(battle) then
      return false
    end
    local state = momentumState(battle)
    if state.awaitingPick or state.pendingDamage then
      return false
    end
    return true
  end

  function EffectRegistry.runDamaging(battle, ctx, record)
    if shouldDeferForCalloutPick(battle, ctx) then
      local state = momentumState(battle)
      local move = ctx.move
      local kind = foeMoveIsSpecial(move) and "dodge" or "brace"
      state.awaitingPick = kind
      state.pendingDamage = { ctx = ctx, record = record }
      state.pickOfferedThisTurn = true
      local me = playerMonName(battle)
      local moveName = tostring(move.name or move.id or "MOVE")
      queueCalloutPickMenu(battle, me, moveName, kind)
      return
    end
    if shouldDeferForCounterPick(battle, ctx) then
      local state = momentumState(battle)
      local move = ctx.move
      state.awaitingPick = "counter"
      state.pendingDamage = { ctx = ctx, record = record }
      local me = playerMonName(battle)
      local moveName = tostring(move.name or move.id or "MOVE")
      queueCounterPickMenu(battle, me, moveName)
      return
    end
    local state = battle and momentumState(battle)
    local enemyCounterArmed = state
        and ctx and ctx.user and not ctx.user.isPlayer
        and state.enemyMode == "counter" and not state.enemyBoosted
    -- If COUNTER/HOLD wasn't needed, still play any stashed foe reaction.
    flushPendingFoeReaction(battle)
    local result = origRunDamaging(battle, ctx, record)
    -- Trainer foe mirror: after their counter lands, sometimes Again!
    if enemyCounterArmed and state.enemyBoosted and trainerFoeReactionsOn(battle)
        and rollEnemyAgain() then
      tryAgainStrike(battle, ctx, enemyMonName(battle), true)
    end
    if enemyCounterArmed then
      state.enemyMode = nil
    end
    return result
  end

  local function silentStageDelta(who, stat, delta)
    if not who or not who.stages or not stat or not delta or delta == 0 then
      return
    end
    local cur = who.stages[stat] or 0
    who.stages[stat] = math.max(-6, math.min(6, cur + delta))
    who.hazeStatReset = nil
  end

  applyCalloutBuffs = function(battle, buffs, trackTemp)
    if not opt("callout_buffs") or not buffs or not battle then
      return
    end
    local state = momentumState(battle)
    for i = 1, #buffs do
      local b = buffs[i]
      local who = b.who
      if who == "player" then
        who = battle.player
      elseif who == "enemy" then
        who = battle.enemy
      end
      if who and who.stages and b.stat and b.delta and b.delta ~= 0 then
        local before = who.stages[b.stat] or 0
        -- Callout already said what to do — apply stages with no rose/fell dialogue.
        MoveEffects.changeStage(
          battle, who, b.stat, b.delta, b.fromEnemy and true or false)
        local after = who.stages[b.stat] or 0
        local applied = after - before
        if trackTemp and applied ~= 0 then
          if who == battle.player then
            if b.stat == "evasion" then
              state.temp.evasion = (state.temp.evasion or 0) + applied
            elseif b.stat == "defense" then
              state.temp.defense = (state.temp.defense or 0) + applied
            end
          elseif who == battle.enemy then
            if not state.enemyTemp then
              state.enemyTemp = { evasion = 0, defense = 0, cover = false }
            end
            if b.stat == "evasion" then
              state.enemyTemp.evasion = (state.enemyTemp.evasion or 0) + applied
            elseif b.stat == "defense" then
              state.enemyTemp.defense = (state.enemyTemp.defense or 0) + applied
            end
          end
        end
      end
    end
  end

  -- Drop temporary dodge/brace stages when you leave cover to attack.
  local function resolveCoverOnPlayerAttack(battle, monName)
    local state = momentumState(battle)
    local temp = state.temp or { evasion = 0, defense = 0, cover = false, picHidden = false }
    local player = battle.player
    if player and player.stages then
      if (temp.evasion or 0) ~= 0 then
        silentStageDelta(player, "evasion", -(temp.evasion or 0))
      end
      if (temp.defense or 0) ~= 0 then
        silentStageDelta(player, "defense", -(temp.defense or 0))
      end
    end
    local hadCover = temp.cover
    local goingFirst = not state.enemyActedThisTurn
    -- Pop back onto the field when leaving cover.
    revealPlayerPic(battle, hadCover)
    state.temp = {
      evasion = 0,
      defense = 0,
      cover = false,
      picHidden = false,
      entrenched = false,
    }

    if not opt("callout_buffs") or not hadCover or not goingFirst or not player then
      return nil
    end
    -- Leaving cover to strike first is risky (silent — leave-cover line is enough).
    silentStageDelta(player, "defense", -1)
    local line = pickFormatted(LEAVE_COVER_CALLS, monName)
      or (monName .. "!\nLeft cover!")
    enqueueAutoAfter(battle, line, CALLOUT_AUTO_DELAY)
    return true
  end

  -- Foe leaves cover to attack: strip their temp EVADE/DEF.
  local function resolveCoverOnEnemyAttack(battle, monName)
    local state = momentumState(battle)
    local temp = state.enemyTemp or { evasion = 0, defense = 0, cover = false }
    local enemy = battle.enemy
    if enemy and enemy.stages then
      if (temp.evasion or 0) ~= 0 then
        silentStageDelta(enemy, "evasion", -(temp.evasion or 0))
      end
      if (temp.defense or 0) ~= 0 then
        silentStageDelta(enemy, "defense", -(temp.defense or 0))
      end
    end
    local hadCover = temp.cover
    state.enemyTemp = { evasion = 0, defense = 0, cover = false }
    if not opt("callout_buffs") or not hadCover or not enemy then
      return nil
    end
    local line = pickFoeTrainerLine(
      battle,
      TRAINER_FOE_LEAVE_COVER_CALLS,
      FOE_LEAVE_COVER_CALLS,
      monName or enemyMonName(battle))
    enqueueAutoAfter(battle, line, CALLOUT_AUTO_DELAY)
    return true
  end

  -- Follow-up line after a "NAME\nused MOVE!" announce (before the anim).
  -- Returns reactionText, buffList, trackTempBuffs.
  local function reactionAfterMoveAnnounce(battle, originalText)
    local mon, moveName = parseUsedMoveText(originalText)
    if not mon or not moveName then
      return nil
    end
    local bare, isEnemy = stripEnemyPrefix(mon)
    local moveDef = findMoveByName(battle, moveName)
    if moveDef and ((moveDef.power or 0) <= 0 or moveDef.category == "status") then
      return nil
    end

    local me = playerMonName(battle)
    local state = momentumState(battle)

    if isEnemy then
      if not opt("momentum_counter") then
        return nil
      end
      if not moveDef then
        return nil
      end
      -- Foe leaves cover as they commit to the attack.
      resolveCoverOnEnemyAttack(battle, bare)
      state.enemyActedThisTurn = true
      -- Armed foe counter: 50% they take it (auto), else HOLD.
      local enemyCounterLine = nil
      if trainerFoeReactionsOn(battle)
          and state.enemyMode == "counter" and not state.enemyBoosted then
        if rollEnemyCounter() then
          enemyCounterLine = pickFoeTrainerLine(
            battle, TRAINER_FOE_COUNTER_CALLS, FOE_COUNTER_CALLS, bare)
          -- Leave enemyMode armed so battle.damage still boosts.
        else
          state.enemyMode = nil
          state.enemyBoosted = false
        end
      end
      -- Interactive pick defers player dodge/brace to EffectRegistry.runDamaging.
      if shouldOfferCalloutPick(battle, moveDef) then
        if enemyCounterLine then
          return enemyCounterLine, nil, false
        end
        return nil
      end
      if foeMoveIsSpecial(moveDef) then
        if not rollDodgeSuccess() then
          local fail = pickFormatted(DODGE_FAIL_CALLS, me)
            or (me .. "!\nCouldn't dodge!")
          if enemyCounterLine then
            return enemyCounterLine .. "\v" .. fail, nil, false
          end
          return fail, nil, false
        end
        local line, boost = pickCallEntry("dodge", battle, me, moveName)
        line = line or (me .. "!\nDodge it!")
        boost = boost or 1
        state.temp.cover = true
        if enemyCounterLine then
          line = enemyCounterLine .. "\v" .. line
        end
        return line, {
          { who = "player", stat = "evasion", delta = boost },
        }, true
      end
      local line, boost = pickCallEntry("brace", battle, me, moveName)
      line = line or (me .. "!\nGet ready!")
      boost = boost or 1
      if boost >= 2 then
        local cur = (battle.player and battle.player.stages
          and battle.player.stages.defense) or 0
        boost = math.max(1, 6 - cur)
        state.temp.entrenched = true
      end
      if enemyCounterLine then
        line = enemyCounterLine .. "\v" .. line
      end
      return line, {
        { who = "player", stat = "defense", delta = boost },
      }, true
    end

    -- Your move announce.
    if opt("anime_move_calls") and enemyLooksWeak(battle) then
      return pickFormatted(PLAYER_FINISH_CALLS, bare, moveName)
        or ("Finish it!\n" .. bare .. "!"), nil, false
    end
    -- Counter is a COUNTER/HOLD menu (deferred with the damage pipeline).
    if playerHasCounter(battle) then
      return nil
    end
    return nil
  end

  local Font = require("src.render.Font")
  local HudTiles = require("src.render.HudTiles")
  local BattleState = require("src.battle.BattleState")
  local WideBattle = require("src.battle.WideBattle")
  local PartyMenu = require("src.ui.PartyMenu")
  local SummaryMenu = require("src.ui.SummaryMenu")

  -- Keep Dig/Fly-style dodge hides through the foe's attack anim.
  do
    local origResetPicFx = BattleState.resetPicFx
    if type(origResetPicFx) == "function" then
      function BattleState.resetPicFx(self)
        origResetPicFx(self)
        local state = self and momentumByBattle[self]
        if not (state and state.temp and state.temp.picHidden) then
          return
        end
        local player = self.player
        if not player then
          return
        end
        local pf = self:picFxFor(player)
        if pf then
          pf.hidden = true
        end
      end
    end
  end

  -- Dodge miss: leave the move anim queued so the attack still plays past cover
  -- (vanilla cancelMoveAnim removes it on accuracy miss).
  do
    local origCancelMoveAnim = BattleState.cancelMoveAnim
    if type(origCancelMoveAnim) == "function" then
      function BattleState.cancelMoveAnim(self)
        local state = self and momentumByBattle[self]
        if state and state.keepDodgeMissAnim then
          return
        end
        return origCancelMoveAnim(self)
      end
    end
  end

  -- True only while a battle HUD paint is in progress.
  local hidingHud = false
  -- Functions are not tables, so track wraps in a weak set.
  local patched = setmetatable({}, { __mode = "k" })

  -- Must be after local BattleState / patched (Lua locals aren't visible above).
  local function willShowCalloutPick(battle, originalText)
    local mon, moveName = parseUsedMoveText(originalText)
    if not mon or not moveName then
      return false
    end
    local _, isEnemy = stripEnemyPrefix(mon)
    if not isEnemy then
      return false
    end
    local moveDef = findMoveByName(battle, moveName)
    return shouldOfferCalloutPick(battle, moveDef)
  end

  local function willShowCounterPick(battle, originalText)
    local mon, moveName = parseUsedMoveText(originalText)
    if not mon or not moveName then
      return false
    end
    local _, isEnemy = stripEnemyPrefix(mon)
    if isEnemy then
      return false
    end
    local moveDef = findMoveByName(battle, moveName)
    if not moveDef or (moveDef.power or 0) <= 0 or moveDef.category == "status" then
      return false
    end
    return playerHasCounter(battle)
  end

  local function wrapBattleSay(methodName)
    local original = BattleState[methodName]
    if type(original) ~= "function" or patched[original] then
      return
    end
    local wrapped = function(self, text, ...)
      -- Parse the engine's original announce before anime rewrite.
      local mon, moveName = parseUsedMoveText(text)
      local bare, isEnemy = nil, false
      if mon then
        bare, isEnemy = stripEnemyPrefix(mon)
      end
      local reaction, buffs, trackTemp = reactionAfterMoveAnnounce(self, text)
      -- Dodge cover miss: keep anim + replace vanilla "attack missed!".
      text = rewriteDodgeMissText(self, text)
      local result = original(self, rewriteBattleText(self, text), ...)
      -- Let callouts finish (A/B) before dodge/brace or counter menus.
      if (methodName == "sayNextAuto" or methodName == "sayAuto")
          and (willShowCalloutPick(self, text) or willShowCounterPick(self, text)) then
        local item = self.queue and self.queue[self.nextInsert]
        if item and item.text then
          item.auto = nil
          item.autoDelay = nil
        end
      end
      -- After your announce is queued: drop temp dodge/brace stages.
      if mon and not isEnemy then
        resolveCoverOnPlayerAttack(self, bare or playerMonName(self))
        -- Trainer foe may auto-dodge/brace before your hit resolves.
        -- If COUNTER/HOLD is armed, stash that reaction until after the
        -- menu — otherwise "couldn't dodge!" then COUNTER/HOLD feels wrong.
        local moveDef = moveName and findMoveByName(self, moveName)
        local damaging = moveDef and (moveDef.power or 0) > 0
            and moveDef.category ~= "status"
        if damaging and playerHasCounter(self) then
          momentumState(self).pendingFoeReaction = { moveDef = moveDef }
        else
          local foeLine, foeBuffs, foeTrack = tryFoeCoverReaction(self, moveDef)
          if foeLine then
            enqueueAutoAfter(self, foeLine, CALLOUT_AUTO_DELAY)
            applyCalloutBuffs(self, foeBuffs, foeTrack)
          end
        end
      end
      if reaction then
        enqueueAutoAfter(self, reaction, CALLOUT_AUTO_DELAY)
        applyCalloutBuffs(self, buffs, trackTemp)
        local st = momentumByBattle[self]
        if isEnemy and st and st.temp and trackTemp then
          if st.temp.cover then
            enqueueDodgeHideAnim(self, nil)
          else
            enqueueBraceAnim(self)
          end
        end
      end
      return result
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
