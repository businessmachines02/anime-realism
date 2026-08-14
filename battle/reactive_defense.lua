-- Anime Realism — Reactive Defense
--
-- Focus-meter reactions: Commit / Dodge / Take Cover / Brace / Entrench.
-- Pure logic module; main.lua owns menus, queue splicing, and engine hooks.

local RD = {}

local byBattle = setmetatable({}, { __mode = "k" })

-- Tunables (design sketch).
RD.FOCUS_START = 50
RD.FOCUS_CAP_BASE = 100
RD.FOCUS_REGEN_COMMIT = 15
RD.FOCUS_REGEN_REACT = 5

RD.COST = {
  commit = 0,
  dodge = 25,
  cover = 20,
  cover_exit = 10,
  brace = 15,
  entrench = 30,
}

RD.DODGE_COUNTER_CHANCE = 0.30
RD.DODGE_COUNTER_POWER = 0.40
RD.DODGE_COUNTER_CD = 2
RD.DODGE_FAIL_MULT = 1.20

RD.BRACE_WRONG_MULT = 1.18
RD.BRACE_COUNTER_CHANCE = 0.35
RD.BRACE_COUNTER_CD = 4
RD.BRACE_STATUS_RESIST = 0.30

RD.COVER_DEF_MULT = 1.5
RD.COVER_TYPE_BONUS = 1.20
RD.COVER_EMERGE_MULT = 1.20
RD.COVER_PIERCE_MULT = 2.0
RD.COVER_UNREACT_DUR_MULT = 2.75

RD.ENTRENCH_TURNS_MIN = 2
RD.ENTRENCH_TURNS_MAX = 3
RD.ENTRENCH_PEN_PHYSICAL = 0.35
RD.ENTRENCH_PEN_SPECIAL = 0.18
RD.ENTRENCH_COUNTER_CHANCE = 0.20
RD.ENTRENCH_EARLY_REFUND = 5

-- Small curated set; expand later. Unreactable still hits Cover durability hard.
RD.UNREACTABLE = {
  EXPLOSION = true,
  SELFDESTRUCT = true,
  HYPER_BEAM = true,
}

RD.COVER_PIERCE = {
  EARTHQUAKE = true,
  FISSURE = true,
  EXPLOSION = true,
  SELFDESTRUCT = true,
  SURF = true,
  BLIZZARD = true,
}

RD.COVER_TYPE_BONUS_TYPES = {
  GROUND = true,
  WATER = true,
  GHOST = true,
}

local function clamp(n, lo, hi)
  if n < lo then
    return lo
  end
  if n > hi then
    return hi
  end
  return n
end

local function rng()
  local r = (love and love.math and love.math.random) or math.random
  return r()
end

local function rngInt(a, b)
  local r = (love and love.math and love.math.random) or math.random
  return r(a, b)
end

local function monOf(battler)
  return battler and battler.mon or nil
end

local function levelOf(battler)
  local mon = monOf(battler)
  return (mon and tonumber(mon.level)) or 50
end


-- local function baseSpeedOf(battler)
--   -- Prefer species base if present; else battle speed stat.
--   local mon = monOf(battler)
--   if mon and mon.species and battler and battler.data and battler.data.pokemon then
--     local def = battler.data.pokemon[mon.species]
--     if def and def.stats and def.stats.speed then
--       return tonumber(def.stats.speed) or 0
--     end
--   end
--   if battler and battler.stats and battler.stats.speed then
--     return tonumber(battler.stats.speed) or 0
--   end
--   return 0
-- end

local function baseSpeedOf(battler)
  -- Prefer species base if present; else battle speed stat.
  local mon = monOf(battler)
  if mon and mon.species and battler and battler.data and battler.data.pokemon then
    local def = battler.data.pokemon[mon.species]
    if def and def.stats and def.stats.speed then
      print("Base speed: " .. (tonumber(def.stats.speed) or 0) .. " for " .. mon.species .. " with current battle speed " .. (tonumber(battler.stats.speed) or 0))
      return tonumber(def.stats.speed) or 0
    end
  end
  if battler and battler.stats and battler.stats.speed then
    return tonumber(battler.stats.speed) or 0
  end
  return 0
end

local function battleStat(battler, key)
  if not battler then
    return 1
  end
  if battler.stats and battler.stats[key] then
    return math.max(1, tonumber(battler.stats[key]) or 1)
  end
  local mon = monOf(battler)
  if mon and mon.stats and mon.stats[key] then
    return math.max(1, tonumber(mon.stats[key]) or 1)
  end
  return 1
end

local function speedStat(battler)
  return battleStat(battler, "speed")
end

local function defenseStat(battler)
  return battleStat(battler, "defense")
end

local function specialStat(battler)
  -- Gen 1: one Special stat covers special offense/defense.
  return battleStat(battler, "special")
end

local function moveId(move)
  if not move then
    return ""
  end
  return tostring(move.id or move.index or ""):upper()
end

local function moveIsSpecial(move)
  if not move then
    return false
  end
  if move.category == "special" then
    return true
  end
  if move.category == "physical" or move.category == "status" then
    return false
  end
  local ok, Damage = pcall(require, "src.battle.Damage")
  if ok and Damage and type(Damage.isSpecial) == "function" then
    local sOk, special = pcall(Damage.isSpecial, move.type)
    if sOk then
      return special and true or false
    end
  end
  return false
end

local function moveCategory(move)
  if not move then
    return "status"
  end
  if move.category == "status" or (move.power or 0) <= 0 then
    return "status"
  end
  return moveIsSpecial(move) and "special" or "physical"
end

local function hasCoverTypeBonus(battler)
  local mon = monOf(battler)
  if not mon then
    return false
  end
  local t1 = tostring(mon.type1 or mon.types and mon.types[1] or ""):upper()
  local t2 = tostring(mon.type2 or mon.types and mon.types[2] or ""):upper()
  return (RD.COVER_TYPE_BONUS_TYPES[t1] or RD.COVER_TYPE_BONUS_TYPES[t2]) and true or false
end

function RD.focusCap(battler)
  local cap = RD.FOCUS_CAP_BASE
  local level = levelOf(battler)
  if level > 50 then
    cap = cap + math.floor((level - 50) / 2)
  end
  local baseSpe = baseSpeedOf(battler)
  if baseSpe > 80 then
    cap = cap + math.floor((baseSpe - 80) / 20)
  end
  return cap
end

local function freshSide()
  return {
    focus = RD.FOCUS_START,
    reactedThisTurn = false,
    cover = false,
    coverDurability = 0,
    coverMax = 0,
    emergeExposed = false,
    entrenched = false,
    entrenchTurns = 0,
    dodgeCounterCd = 0,
    braceCounterCd = 0,
    losePriorityNext = false,
  }
end

function RD.state(battle)
  local st = byBattle[battle]
  if not st then
    st = {
      player = freshSide(),
      enemy = freshSide(),
      pending = nil,
      lastResult = nil,
    }
    byBattle[battle] = st
    -- Cap-aware start (may be >50 start still).
    local pCap = RD.focusCap(battle and battle.player)
    local eCap = RD.focusCap(battle and battle.enemy)
    st.player.focus = math.min(RD.FOCUS_START, pCap)
    st.enemy.focus = math.min(RD.FOCUS_START, eCap)
  end
  return st
end

function RD.clear(battle)
  if battle then
    byBattle[battle] = nil
  end
end

-- New battler in a slot: Focus back to default, clear cover/entrench/CDs.
function RD.resetSide(battle, isPlayer)
  if not battle then
    return
  end
  local st = RD.state(battle)
  local side = freshSide()
  local battler = isPlayer and battle.player or battle.enemy
  local cap = RD.focusCap(battler)
  side.focus = math.min(RD.FOCUS_START, cap)
  if isPlayer then
    st.player = side
    st.hitMod = nil
  else
    st.enemy = side
  end
  return side
end

function RD.sideState(battle, isPlayer)
  local st = RD.state(battle)
  return isPlayer and st.player or st.enemy
end

function RD.isUnreactable(move)
  return RD.UNREACTABLE[moveId(move)] == true
end

function RD.isCoverPierce(move)
  local id = moveId(move)
  if RD.COVER_PIERCE[id] then
    return true
  end
  -- High BP as soft pierce.
  return (move and (move.power or 0) >= 100) and true or false
end

function RD.canReact(battle, isPlayer)
  local side = RD.sideState(battle, isPlayer)
  if side.entrenched and (side.entrenchTurns or 0) > 0 then
    return false
  end
  return true
end

function RD.affordable(battle, isPlayer, action)
  local side = RD.sideState(battle, isPlayer)
  local cost = RD.COST[action] or 0
  if action == "cover" and side.cover then
    cost = 0 -- stay is free; entering costs
  end
  if action == "cover_exit" then
    cost = RD.COST.cover_exit
  end
  return (side.focus or 0) >= cost, cost
end

function RD.spend(battle, isPlayer, action)
  local side = RD.sideState(battle, isPlayer)
  local ok, cost = RD.affordable(battle, isPlayer, action)
  if not ok then
    return false, 0
  end
  if action == "cover" and side.cover then
    return true, 0
  end
  side.focus = math.max(0, (side.focus or 0) - cost)
  return true, cost
end

function RD.addFocus(battle, isPlayer, amount)
  local side = RD.sideState(battle, isPlayer)
  local battler = isPlayer and battle.player or battle.enemy
  local cap = RD.focusCap(battler)
  side.focus = clamp((side.focus or 0) + (amount or 0), 0, cap)
end

function RD.dodgeSuccessChance(defender, attacker)
  local speDef = speedStat(defender)
  local speAtk = speedStat(attacker)
  local chance = clamp(35 + (speDef - speAtk) * 0.14, 20, 85) / 100
  print("Dodge success chance: " .. chance .. " for defender speed " .. speDef .. " vs attacker speed " .. speAtk)
  return chance
end

function RD.braceReduction(defender, category)
  local bulk = (category == "special") and specialStat(defender) or defenseStat(defender)
  -- Design: 50% + min(20%, Def_or_SpDef ÷ 10) as percentage points.
  local bonus = math.min(0.20, (bulk / 10) / 100)
  return clamp(0.50 + bonus, 0.50, 0.70)
end

function RD.entrenchMitigation(defender, category)
  local bulk = (category == "special") and specialStat(defender) or defenseStat(defender)
  local bonus = math.min(0.35, (bulk / 10) / 100)
  return clamp(0.50 + bonus, 0.50, 0.85)
end

function RD.coverMaxDurability(defender)
  local pool = defenseStat(defender) * RD.COVER_DEF_MULT
  if hasCoverTypeBonus(defender) then
    pool = pool * RD.COVER_TYPE_BONUS
  end
  return math.max(1, math.floor(pool + 0.5))
end

function RD.enterCover(battle, isPlayer)
  local side = RD.sideState(battle, isPlayer)
  local battler = isPlayer and battle.player or battle.enemy
  local ok = RD.spend(battle, isPlayer, "cover")
  if not ok then
    return false
  end
  side.cover = true
  side.coverMax = RD.coverMaxDurability(battler)
  side.coverDurability = side.coverMax
  side.emergeExposed = false
  side.reactedThisTurn = true
  return true
end

function RD.exitCover(battle, isPlayer, expose)
  local side = RD.sideState(battle, isPlayer)
  if not side.cover then
    return false
  end
  local ok = RD.spend(battle, isPlayer, "cover_exit")
  if not ok then
    return false
  end
  side.cover = false
  side.coverDurability = 0
  side.coverMax = 0
  side.emergeExposed = expose ~= false
  side.reactedThisTurn = true
  return true
end

function RD.beginEntrench(battle, isPlayer)
  local side = RD.sideState(battle, isPlayer)
  local ok = RD.spend(battle, isPlayer, "entrench")
  if not ok then
    return false
  end
  side.entrenched = true
  side.entrenchTurns = rngInt(RD.ENTRENCH_TURNS_MIN, RD.ENTRENCH_TURNS_MAX)
  side.reactedThisTurn = true
  -- Entering entrench leaves cover.
  side.cover = false
  side.coverDurability = 0
  return true, side.entrenchTurns
end

function RD.earlyExitEntrench(battle, isPlayer)
  local side = RD.sideState(battle, isPlayer)
  if not side.entrenched then
    return false
  end
  local left = side.entrenchTurns or 0
  local refund = left * RD.ENTRENCH_EARLY_REFUND
  side.entrenched = false
  side.entrenchTurns = 0
  if refund > 0 then
    RD.addFocus(battle, isPlayer, refund)
  end
  return true, refund
end

--- Resolve a player reaction to an incoming foe move.
-- action: "commit"|"dodge"|"cover"|"brace"|"entrench"
-- braceCall: "physical"|"special"|"status"|nil
-- Returns a result table consumed by main.lua.
function RD.resolveIncoming(battle, action, braceCall, ctx)
  local user = ctx and ctx.user
  local target = ctx and ctx.target
  local move = ctx and ctx.move
  local side = RD.sideState(battle, true)
  local cat = moveCategory(move)
  local result = {
    action = action,
    lines = {},
    forceMiss = false,
    damageMult = 1,
    cancelAnim = false,
    counter = nil,
    focusSpent = 0,
    coverBroke = false,
    absorbed = 0,
    unreactable = RD.isUnreactable(move),
  }

  -- if our pokemon is frozen or asleep then we can't react
  if (side.frozen or side.asleep) then
    result.lines[#result.lines + 1] = "Pokemon is frozen or asleep!"
    return result
  end

  -- Entrench lockout: forced commit-style soak with mitigation.
  if side.entrenched and (side.entrenchTurns or 0) > 0 and action ~= "entrench" then
    action = "entrench_hold"
  end

  if result.unreactable and (action == "dodge" or action == "brace") then
    result.lines[#result.lines + 1] = "There's no\nescaping this!"
    action = "commit"
  end

  if action == "commit" then
    local ok, cost = RD.spend(battle, true, "commit")
    result.focusSpent = cost
    side.reactedThisTurn = false -- Commit counts as "no reactive option"
    if side.cover then
      result.coverSoak = true
      if result.unreactable then
        result.coverDurMult = RD.COVER_UNREACT_DUR_MULT
      elseif RD.isCoverPierce(move) then
        result.coverDurMult = RD.COVER_PIERCE_MULT
      else
        result.coverDurMult = 1
      end
    end
    if side.emergeExposed then
      result.damageMult = RD.COVER_EMERGE_MULT
      side.emergeExposed = false
      result.lines[#result.lines + 1] = "Caught coming\nout of cover!"
    end
    return result
  end

  if action == "dodge" then
    local ok, cost = RD.spend(battle, true, "dodge")
    if not ok then
      result.action = "commit"
      result.lines[#result.lines + 1] = "Not enough\nFocus!"
      return RD.resolveIncoming(battle, "commit", nil, ctx)
    end
    result.focusSpent = cost
    side.reactedThisTurn = true
    local chance = RD.dodgeSuccessChance(target, user)
    if rng() <= chance then
      result.forceMiss = true
      result.cancelAnim = false -- keep swing for drama; main may still cancel
      local dodgeLines = {
        "Dodged aside!",
        "Leapt clear just in time!",
        "Slipped past the attack!",
        "Narrowly avoided it!",
        "Evaded skillfully!"
      }
      result.lines[#result.lines + 1] = dodgeLines[math.random(#dodgeLines)]
 
      if (side.dodgeCounterCd or 0) <= 0 and rng() < RD.DODGE_COUNTER_CHANCE then
        side.dodgeCounterCd = RD.DODGE_COUNTER_CD
        result.counter = {
          kind = "dodge",
          powerFrac = RD.DODGE_COUNTER_POWER,
          useSpeed = true,
        }
        local counterLines = {
          "It's a counterattack!",
          "But it countered right away!",
          "Counter! The foe strikes back!",
          "A sudden counter!",
          "It retaliated with a counter move!",
        }
   
        result.lines[#result.lines + 1] = counterLines[math.random(#counterLines)]
   
      end
    else
      result.damageMult = RD.DODGE_FAIL_MULT
      side.losePriorityNext = true
      result.lines[#result.lines + 1] = "Couldn't dodge!\nCaught off-balance!"
    end
    return result
  end

  if action == "cover" then
    if not side.cover then
      if not RD.enterCover(battle, true) then
        result.lines[#result.lines + 1] = "Not enough\nFocus!"
        return RD.resolveIncoming(battle, "commit", nil, ctx)
      end
      result.focusSpent = RD.COST.cover
      result.lines[#result.lines + 1] = "Took cover!"
    else
      side.reactedThisTurn = true
      result.lines[#result.lines + 1] = "Holding cover!"
    end
    -- Incoming hit vs durability handled in RD.applyCoverHit after damage known,
    -- or we estimate via damageMult 0 and absorb in hook.
    result.coverSoak = true
    if result.unreactable then
      result.coverDurMult = RD.COVER_UNREACT_DUR_MULT
    elseif RD.isCoverPierce(move) then
      result.coverDurMult = RD.COVER_PIERCE_MULT
    else
      result.coverDurMult = 1
    end
    return result
  end

  if action == "brace" then
    local ok, cost = RD.spend(battle, true, "brace")
    if not ok then
      result.lines[#result.lines + 1] = "Not enough\nFocus!"
      return RD.resolveIncoming(battle, "commit", nil, ctx)
    end
    result.focusSpent = cost
    side.reactedThisTurn = true
    braceCall = tostring(braceCall or ""):lower()
    if braceCall ~= "physical" and braceCall ~= "special" and braceCall ~= "status" then
      braceCall = cat
    end
    result.braceCall = braceCall
    if braceCall == cat then
      local red = RD.braceReduction(target, cat)
      result.damageMult = 1 - red
      result.lines[#result.lines + 1] = "Braced right!\nTook it well!"
      result.statusResist = RD.BRACE_STATUS_RESIST
      if (side.braceCounterCd or 0) <= 0 and rng() < RD.BRACE_COUNTER_CHANCE then
        side.braceCounterCd = RD.BRACE_COUNTER_CD
        result.counter = {
          kind = "brace",
          -- power scales with absorbed fraction later
          absorbScale = true,
          reduction = red,
        }
        result.lines[#result.lines + 1] = "Countered\nthe blow!"
      end
    else
      result.damageMult = RD.BRACE_WRONG_MULT
      result.lines[#result.lines + 1] = "Braced the\nwrong way!"
    end
    return result
  end

  if action == "entrench" or action == "entrench_hold" then
    if action == "entrench" and not side.entrenched then
      local ok, turns = RD.beginEntrench(battle, true)
      if not ok then
        result.lines[#result.lines + 1] = "Not enough\nFocus!"
        return RD.resolveIncoming(battle, "commit", nil, ctx)
      end
      result.focusSpent = RD.COST.entrench
      result.lines[#result.lines + 1] = "Entrenched!\n(" .. tostring(turns) .. " turns)"
    else
      side.reactedThisTurn = true
    end
    local penChance = (cat == "physical") and RD.ENTRENCH_PEN_PHYSICAL
        or (cat == "special") and RD.ENTRENCH_PEN_SPECIAL
        or 0
    if cat == "status" then
      result.damageMult = 1
      result.lines[#result.lines + 1] = "Status slips\nthrough!"
      return result
    end
    if rng() < penChance then
      result.damageMult = 1
      result.lines[#result.lines + 1] = "It broke\nthrough!"
      if rng() < RD.ENTRENCH_COUNTER_CHANCE then
        result.counter = { kind = "entrench", powerFrac = 0.25, useSpeed = false }
        result.lines[#result.lines + 1] = "Clipped them\non the way in!"
      end
    else
      local mit = RD.entrenchMitigation(target, cat)
      result.damageMult = 1 - mit
      result.lines[#result.lines + 1] = "The shell\nheld!"
    end
    return result
  end

  return result
end

--- Apply an incoming damage amount against cover durability.
-- Returns remaining HP damage to apply to the mon, and updates side state.
function RD.applyCoverHit(battle, isPlayer, rawDamage, durMult)
  local side = RD.sideState(battle, isPlayer)
  if not side.cover then
    return rawDamage, false
  end
  durMult = durMult or 1
  local hit = math.max(0, (rawDamage or 0) * durMult)
  local dur = side.coverDurability or 0
  if hit <= dur then
    side.coverDurability = dur - hit
    return 0, false
  end
  local overflow = hit - dur
  side.coverDurability = 0
  side.cover = false
  side.emergeExposed = true
  return overflow, true
end

function RD.endTurn(battle)
  if not battle then
    return
  end
  local st = RD.state(battle)
  for _, key in ipairs({ "player", "enemy" }) do
    local side = st[key]
    local isPlayer = key == "player"
    local battler = isPlayer and battle.player or battle.enemy
    if side.dodgeCounterCd and side.dodgeCounterCd > 0 then
      side.dodgeCounterCd = side.dodgeCounterCd - 1
    end
    if side.braceCounterCd and side.braceCounterCd > 0 then
      side.braceCounterCd = side.braceCounterCd - 1
    end
    if side.entrenched and (side.entrenchTurns or 0) > 0 then
      side.entrenchTurns = side.entrenchTurns - 1
      if side.entrenchTurns <= 0 then
        side.entrenched = false
        side.entrenchTurns = 0
      end
    end
    local regen = side.reactedThisTurn and RD.FOCUS_REGEN_REACT or RD.FOCUS_REGEN_COMMIT
    RD.addFocus(battle, isPlayer, regen)
    side.reactedThisTurn = false
  end
end

function RD.menuActions(battle, move)
  local side = RD.sideState(battle, true)
  local actions = {}
  local function add(id, label, hint, costKey)
    local cost = RD.COST[costKey or id] or 0
    if id == "cover" and side.cover then
      cost = 0
      label = "STAY COVER"
      hint = "Hold position"
    end
    -- Don't list options you can't pay for (Commit is always free).
    if (side.focus or 0) < cost then
      return
    end
    if id == "entrench" and side.entrenched then
      return
    end
    if side.entrenched then
      -- Only early break shown elsewhere; no other reacts.
      return
    end
    actions[#actions + 1] = {
      id = id,
      label = label,
      hint = hint,
      cost = cost,
      afford = true,
      focus = side.focus,
    }
  end

  if side.entrenched then
    actions[1] = {
      id = "entrench_hold",
      label = "HOLD",
      hint = "Stay entrenched",
      cost = 0,
      afford = true,
      focus = side.focus,
    }
    actions[2] = {
      id = "entrench_break",
      label = "BREAK",
      hint = "Leave early",
      cost = 0,
      afford = true,
      focus = side.focus,
    }
    return actions
  end

  local unreactable = RD.isUnreactable(move)
  if not unreactable then
    add("dodge", "DODGE", "Evade or bust", "dodge")
  end
  add("cover", side.cover and "STAY COVER" or "TAKE COVER",
    side.cover and "Hold position" or "Durability pool", "cover")
  if not unreactable then
    add("brace", "BRACE", "Match the hit", "brace")
  end
  add("entrench", "ENTRENCH", "Lock in 2-3 turns", "entrench")
  add("commit", "COMMIT", "Take the hit", "commit")

  return actions
end

function RD.focusLabel(battle, isPlayer)
  local side = RD.sideState(battle, isPlayer)
  local battler = isPlayer and battle.player or battle.enemy
  local cap = RD.focusCap(battler)
  return string.format("FOCUS %d/%d", math.floor(side.focus or 0), cap)
end

return RD
