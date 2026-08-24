-- Anime Realism — Reactive Defense ~ REACT
--
-- Focus-meter reactions: Commit / Dodge / Take Cover / Brace / Entrench.
-- Pure logic module; rules/react.lua owns menus, queue splicing, and engine hooks.

-- We intentionally want to hide focus points from the player to create a sense of immersion.  
-- I don't like the idea of quantifying things too much during a battle, so the goal is to craft hte battle system 
-- in a way that feels closer to what we would have fantasized as kids playing this game. 
-- some pokes are just naturally better in certain geographical areas. 

-- We do keep this turn-based, with greater variability during the "episode/battle-turn". 
-- What would have been an "i move, you move" situation, is now a "i move, you react, you move, i react situation" with the player having a bit more decision making during the overall episode.

local RD = {}

local byBattle = setmetatable({}, { __mode = "k" })

-- Tunables (design sketch).
RD.FOCUS_START = 50
-- RD.FOCUS_CAP_BASE = 100
RD.FOCUS_CAP_BASE = 75
RD.FOCUS_REGEN_COMMIT = 15
RD.FOCUS_REGEN_REACT = 5

RD.COST = {
  commit = 0, -- just take it the usual way
  dodge = 25,
  fire = 20,
  charge = 15,
  cover = 20,
  cover_exit = 10,
  brace = 15,
  entrench = 30,
}

-- Dodging is a high-risk, but potentially rewarding, play.

-- If it lands:
-- 1. You miss damage completely that turn.
-- 2. You have a 30% chance to effectively deal a weak counter move in return (was 1.5, now 1.1 damage scale).
--
-- If it doesn't:
-- 1. You are not punished too badly ( due to the inherant focus trade-off made earlier in the turn ~ you could have conserved more focus points by bracing instead )
--
-- Generally, it should consume high levels of focus, creating a clear tradeoff situation.
-- In practice, remaining stationary or not taking action ("committing") is less taxing than actively dodging or reacting, 
-- which requires more focus and effort—mirroring how it's easier to stay still than to move suddenly in real life.
--
-- Bracing on the other hand, is never likely to "miss"...unless the foe naturally does. 
-- but since bracing is a buff to yourself, it does consume focus points.

-- Change: Dodge is easier to land, but the follow-up/counter is weaker.
RD.DODGE_COUNTER_CHANCE = 0.50 -- up from .30; easier to get a dodge follow-up
RD.DODGE_COUNTER_POWER = 0.25  -- down from .50; follow-up move deals less damage
RD.DODGE_COUNTER_CD = 2
RD.DODGE_FAIL_MULT = 1.10
-- Fresh legs dodge better. +this at full HP, none when the bar is empty.
RD.DODGE_HEALTH_BONUS = 0.18
RD.FIRE_CAST_MULT = 1.20
-- Small chance the interrupt itself goes wide; incoming still lands.
RD.FIRE_WHIFF_CHANCE = 0.12
-- REACT special: no charge, so the shot itself is a bit weaker.
RD.REACT_SPECIAL_MULT = 0.75
-- Beam clash: ratio to shove the other shot aside. Below this is a deadlock.
RD.CLASH_PUSH = 1.35
RD.CLASH_LOSE_MULT = 0.55
RD.CLASH_WIN_SHOT_MULT = 0.75
-- Physical CHARGE: both hits land; a coin flip boosts one side.
RD.CHARGE_BOOST = 1.15

RD.BRACE_WRONG_MULT = 1.18
RD.BRACE_COUNTER_CHANCE = 0.35
RD.BRACE_COUNTER_CD = 4
RD.BRACE_STATUS_RESIST = 0.30

RD.COVER_MISS_CHANCE = 0.30
RD.COVER_DEF_MULT = 1.5
RD.COVER_TYPE_BONUS = 1.20 -- a rock type covering in a cave, or water type around water.
RD.COVER_EMERGE_MULT = 1.20
RD.COVER_PIERCE_MULT = 2.0 -- if a foe pierces through the defense
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

-- First-turn Dig / Fly hide. The strike turn is the one that opens REACT.
RD.VANISH_MOVES = {
  DIG = "dig",
  FLY = "fly",
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
  if type(RD._testRng) == "function" then
    return RD._testRng()
  end
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

local function defenderTypes(battler)
  if not battler then
    return { "NORMAL" }
  end
  local types = battler.curTypes
  if type(types) ~= "table" or #types == 0 then
    types = battler.types
  end
  if type(types) ~= "table" or #types == 0 then
    local mon = monOf(battler)
    types = mon and mon.types
  end
  if type(types) ~= "table" or #types == 0 then
    local def = battler.def
    types = def and def.types
  end
  if type(types) == "table" and #types > 0 then
    return types
  end
  return { "NORMAL" }
end

local function typeEffectiveness(moveType, defender)
  moveType = tostring(moveType or ""):upper()
  if moveType == "" then
    return 1
  end
  local ok, TypeChart = pcall(require, "src.battle.TypeChart")
  if ok and TypeChart and type(TypeChart.effectiveness) == "function" then
    local okE, mult = pcall(TypeChart.effectiveness, moveType, defenderTypes(defender))
    if okE and type(mult) == "number" then
      if mult <= 0 then
        return 0.25
      end
      return mult / 10
    end
  end
  return 1
end

local function clashMovePower(battle, move)
  if not move then
    return 40
  end
  local power = tonumber(move.power)
  if power and power > 0 then
    return power
  end
  local id = tostring(move.id or move.name or ""):upper():gsub("%s+", "_")
  local moves = battle and battle.data and battle.data.moves
  local def = id ~= "" and type(moves) == "table" and moves[id]
  return tonumber(def and def.power) or 40
end

local function clashMoveType(battle, move)
  if not move then
    return "NORMAL"
  end
  local typ = move.type or move.moveType
  if typ and tostring(typ) ~= "" then
    return tostring(typ):upper()
  end
  local id = tostring(move.id or move.name or ""):upper():gsub("%s+", "_")
  local moves = battle and battle.data and battle.data.moves
  local def = id ~= "" and type(moves) == "table" and moves[id]
  return tostring(def and def.type or "NORMAL"):upper()
end

--- Who shoves whom when two specials meet. `reply` is the defender's shot.
function RD.clashScore(battle, user, move, foe)
  local power = clashMovePower(battle, move)
  local spec = specialStat(user)
  local mod = typeEffectiveness(clashMoveType(battle, move), foe)
  return math.max(1, power) * spec * mod
end

--- Electric FIRE cuts a Water incoming regardless of Special.
function RD.electricCutsWater(incoming, reply, battle)
  return clashMoveType(battle, reply) == "ELECTRIC"
      and clashMoveType(battle, incoming) == "WATER"
end

--- `opts.replySide` is "player" (default) or "enemy". Win means the
--- defender's reply overpowers the incoming shot.
function RD.contestSpecialClash(battle, incoming, reply, opts)
  if not (battle and incoming and reply) then
    return "tie", 1
  end
  if RD.electricCutsWater(incoming, reply, battle) then
    return "win", math.max(RD.CLASH_PUSH or 1.35, 2)
  end
  opts = opts or {}
  local replySide = opts.replySide or "player"
  local mineUser, mineFoe, theirsUser, theirsFoe
  if replySide == "enemy" then
    mineUser, mineFoe = battle.enemy, battle.player
    theirsUser, theirsFoe = battle.player, battle.enemy
  else
    mineUser, mineFoe = battle.player, battle.enemy
    theirsUser, theirsFoe = battle.enemy, battle.player
  end
  local mine = RD.clashScore(battle, mineUser, reply, mineFoe)
  local theirs = RD.clashScore(battle, theirsUser, incoming, theirsFoe)
  local ratio = mine / math.max(1, theirs)
  if ratio >= (RD.CLASH_PUSH or 1.35) then
    return "win", ratio
  end
  if ratio <= 1 / (RD.CLASH_PUSH or 1.35) then
    return "lose", ratio
  end
  return "tie", ratio
end

local function moveId(move)
  if not move then
    return ""
  end
  return tostring(move.id or move.index or ""):upper()
end

-- Gen 1 type-split is physical; these still fly. Match field/fx/fx_catalog.lua.
local PROJECTILE_SPECIAL = {
  SWIFT = true,
  GUST = true,
  NIGHT_SHADE = true,
  TRI_ATTACK = true,
  BONEMERANG = true,
  ROCK_THROW = true,
}

local function moveIsSpecial(move)
  if not move then
    return false
  end
  if PROJECTILE_SPECIAL[moveId(move)] then
    return true
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

function RD.isSpecialClashIncoming(move)
  if not move or (move.power or 0) <= 0 then
    return false
  end
  if tostring(move.category or ""):lower() == "status" then
    return false
  end
  return moveIsSpecial(move)
end

function RD.isPhysicalClashIncoming(move)
  if not move or (move.power or 0) <= 0 then
    return false
  end
  if tostring(move.category or ""):lower() == "status" then
    return false
  end
  return not moveIsSpecial(move)
end

--- Coin flip. `opts.roll` is 0..1 for tests. Win = reply gets the boost.
function RD.contestPhysicalClash(_battle, _incoming, _reply, opts)
  opts = opts or {}
  local roll = tonumber(opts.roll)
  if roll == nil then
    roll = rng()
  end
  if roll < 0.5 then
    return "win", roll
  end
  return "lose", roll
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

function RD.vanishKind(move)
  local id = type(move) == "string" and move:upper() or moveId(move)
  if not id or id == "" then
    return nil
  end
  return RD.VANISH_MOVES[id]
end

function RD.chargingMoveId(battler)
  local charging = battler and battler.charging
  if type(charging) == "table" then
    return moveId(charging)
  end
  if type(charging) == "string" then
    return moveId({ id = charging })
  end
  return nil
end

-- Hide turn: Dig/Fly used before the engine has armed `charging`.
-- Release turn: `charging` is already set from last turn.
function RD.isVanishHideTurn(user, move)
  if not RD.vanishKind(move) then
    return false
  end
  local id = RD.chargingMoveId(user)
  if id and RD.vanishKind(id) then
    return false
  end
  return true
end

-- Semi-invulnerable Dig/Fly hold. No REACT from underground / the sky.
function RD.isVanished(battler)
  if not battler or not battler.invulnerable then
    return false
  end
  local id = RD.chargingMoveId(battler)
  if not id then
    return true
  end
  return RD.vanishKind(id) ~= nil
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
  local battler = isPlayer and battle.player or battle.enemy
  if RD.isVanished(battler) then
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

function RD.hpRatio(battler)
  local mon = monOf(battler)
  local hp = tonumber(mon and mon.hp) or tonumber(battler and battler.hp)
  if hp == nil then
    hp = tonumber(battler and battler.shownHP)
  end
  local maxHP = tonumber(mon and mon.stats and mon.stats.hp)
      or tonumber(battler and battler.stats and battler.stats.hp)
      or tonumber(mon and mon.maxHP)
  if not hp or not maxHP or maxHP <= 0 then
    return nil
  end
  return clamp(hp / maxHP, 0, 1)
end

-- Linear: full HP → DODGE_HEALTH_BONUS, fainted → 0.
function RD.dodgeHealthBonus(defender)
  local ratio = RD.hpRatio(defender)
  if not ratio then
    return 0
  end
  return (RD.DODGE_HEALTH_BONUS or 0) * ratio
end

-- Depending on where our pokemon is fighting, some poke
function RD.dodgeSuccessChance(defender, attacker, battle)
  local speDef = speedStat(defender)
  local speAtk = speedStat(attacker)
  local chance = clamp(50 + (speDef - speAtk) * 0.14, 35, 95) / 100 -- increased base/easier ceiling
  if hasCoverTypeBonus(defender) then
    chance = clamp(chance * 1.5, 0, 1)
  end
  chance = chance + RD.dodgeHealthBonus(defender)
  if type(RD.emotionDodgeBonus) == "function" then
    chance = chance + (tonumber(RD.emotionDodgeBonus(defender, attacker, battle)) or 0)
  end
  return clamp(chance, 0.15, 0.97) -- wider easier range
end

-- Trainer-foe picks live in rules/foe_ai.lua (FoeAi.attach installs
-- RD.pickFoeReact). Tests that call the picker must load both files.

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
  side.coverMax = RD.coverMaxDurability(battler) -- HERE
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

  if action == "fire" then
    local ok, cost = RD.spend(battle, true, "fire")
    if not ok then
      result.action = "commit"
      result.lines[#result.lines + 1] = "Not enough\nFocus!"
      return RD.resolveIncoming(battle, "commit", nil, ctx)
    end
    result.focusSpent = cost
    side.reactedThisTurn = true
    if rng() < (RD.FIRE_WHIFF_CHANCE or 0) then
      result.action = "commit"
      result.fireWhiff = true
      result.chip = "MISS"
      result.lines[#result.lines + 1] = "The shot\nwent wide!"
      return result
    end
    result.fireNow = true
    local incoming = ctx and ctx.move
    local reply = ctx and ctx.replyMove
    if RD.isSpecialClashIncoming(incoming) and reply then
      local verdict, ratio = RD.contestSpecialClash(battle, incoming, reply)
      result.fireClash = verdict
      result.fireClashRatio = ratio
      result.chip = "CLASH"
      if verdict == "win" then
        result.forceMiss = true
        result.fireNowContinue = true
        result.fireShotMult = RD.CLASH_WIN_SHOT_MULT
        result.damageMult = 1
        if RD.electricCutsWater(incoming, reply, battle) then
          result.fireShotMult = RD.FIRE_CAST_MULT
          result.damageMult = RD.FIRE_CAST_MULT
          result.lines[#result.lines + 1] = "Cut through\nthe water!"
        else
          result.lines[#result.lines + 1] = "Overpowered it!"
        end
      elseif verdict == "tie" then
        result.forceMiss = true
        result.fireNowContinue = false
        result.damageMult = 1
        result.lines[#result.lines + 1] = "The attacks\ncanceled out!"
      else
        result.forceMiss = false
        result.fireNowContinue = false
        result.damageMult = RD.CLASH_LOSE_MULT
        result.lines[#result.lines + 1] = "Couldn't\noverpower it!"
      end
      return result
    end
    result.damageMult = RD.FIRE_CAST_MULT
    result.chip = "FIRE"
    result.lines[#result.lines + 1] = "Struck in the\nmiddle of it!"
    return result
  end

  if action == "charge" then
    local ok, cost = RD.spend(battle, true, "charge")
    if not ok then
      result.action = "commit"
      result.lines[#result.lines + 1] = "Not enough\nFocus!"
      return RD.resolveIncoming(battle, "commit", nil, ctx)
    end
    result.focusSpent = cost
    side.reactedThisTurn = true
    result.chargeNow = true
    local incoming = ctx and ctx.move
    local reply = ctx and ctx.replyMove
    local verdict = RD.contestPhysicalClash(battle, incoming, reply, ctx)
    result.chargeClash = verdict
    result.chip = "CHARGE"
    if verdict == "win" then
      result.damageMult = 1
      result.chargeShotMult = RD.CHARGE_BOOST
      result.lines[#result.lines + 1] = "Crashed through!"
    else
      result.damageMult = RD.CHARGE_BOOST
      result.chargeShotMult = 1
      result.lines[#result.lines + 1] = "They crashed\nthrough!"
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
    local chance = RD.dodgeSuccessChance(target, user, battle)
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
      result.chip = "DODGE"
      result.lines[#result.lines + 1] = dodgeLines[math.random(#dodgeLines)]

      if (side.dodgeCounterCd or 0) <= 0 and rng() < RD.DODGE_COUNTER_CHANCE then
        side.dodgeCounterCd = RD.DODGE_COUNTER_CD
        local counterLines = {
          "It's a counterattack!",
          "Struck back right away!",
          "Counter! Hit them back!",
          "A sudden counter!",
          "Retaliated with a strike!",
        }
        result.counter = {
          kind = "dodge",
          powerFrac = RD.DODGE_COUNTER_POWER,
          useSpeed = true,
          line = counterLines[math.random(#counterLines)],
        }
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
      result.chip = "COVER"
      result.lines[#result.lines + 1] = "Took cover!"
    else
      side.reactedThisTurn = true
      result.chip = "COVER"
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
      if rng() < (RD.COVER_MISS_CHANCE or 0) then
        result.forceMiss = true
        result.coverSoak = false
        result.chip = "MISS"
        result.lines[#result.lines + 1] = "Hid just in time!"
      end
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
      result.chip = "BRACE"
      result.lines[#result.lines + 1] = "Braced right!\nTook it well!"
      result.statusResist = RD.BRACE_STATUS_RESIST
      if (side.braceCounterCd or 0) <= 0 and rng() < RD.BRACE_COUNTER_CHANCE then
        side.braceCounterCd = RD.BRACE_COUNTER_CD
        result.counter = {
          kind = "brace",
          -- power scales with absorbed fraction later
          absorbScale = true,
          reduction = red,
          line = "Countered\nthe blow!",
        }
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
      result.chip = "HOLD"
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
        result.counter = {
          kind = "entrench",
          powerFrac = 0.25,
          useSpeed = false,
          line = "Clipped them\non the way in!",
        }
      end
    else
      local mit = RD.entrenchMitigation(target, cat)
      result.damageMult = 1 - mit
      result.chip = "HOLD"
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
  print("Hit: " .. tostring(hit) .. " and dur: " .. tostring(dur))
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

function RD.menuActions(battle, move, opts)
  opts = opts or {}
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

  if RD.isVanishHideTurn(opts.user or (battle and battle.enemy), move)
      or RD.isVanished(battle and battle.player) then
    actions[1] = {
      id = "commit",
      label = "PASS",
      hint = "Wait for the strike",
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
  if opts.canFireNow then
    add("fire", "FIRE", opts.fireHint or "Strike now", "fire")
  end
  if opts.canChargeNow then
    add("charge", "CHARGE", opts.chargeHint or "Crash the charge", "charge")
  end
  add("cover", side.cover and "STAY COVER" or "TAKE COVER",
    side.cover and "Hold position" or "Durability pool", "cover")
  if not unreactable then
    add("brace", "BRACE", "Match the hit", "brace")
  end
  -- FIRE / CHARGE take the diamond's fourth slot; entrenching mid-lunge is out.
  if not opts.canFireNow and not opts.canChargeNow then
    add("entrench", "ENTRENCH", "Lock in 2-3 turns", "entrench")
  end
  add("commit", "COMMIT", "Take the hit", "commit")

  return actions
end

--- True when the REACT HUD has a real pick (not just free COMMIT).
function RD.hasReactChoice(battle, move, opts)
  local actions = RD.menuActions(battle, move, opts)
  for i = 1, #actions do
    local id = actions[i] and actions[i].id
    if id and id ~= "commit" then
      return true
    end
  end
  return false
end

function RD.focusLabel(battle, isPlayer)
  local side = RD.sideState(battle, isPlayer)
  local battler = isPlayer and battle.player or battle.enemy
  local cap = RD.focusCap(battler)
  return string.format("FOCUS %d/%d", math.floor(side.focus or 0), cap)
end

return RD
