-- Trainer-foe REACT picks. Weighted commit / dodge / brace / FIRE.
--
-- Execution (Focus spend, poses, shots, clash FX) stays in main.lua and
-- reactive_defense.lua. This file only decides what they try.


-- gary stands no chance against me... but I can make him a bit stronger anyway ;)

local FoeAi = {}
local RD

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

local function battleStat(battler, key)
  if not battler then
    return 1
  end
  if battler.stats and battler.stats[key] then
    return math.max(1, tonumber(battler.stats[key]) or 1)
  end
  local mon = battler.mon
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
  return battleStat(battler, "special")
end

function FoeAi.attach(reactiveDefense)
  RD = reactiveDefense
  if RD then
    RD.pickFoeReact = FoeAi.pickFoeReact
  end
  return FoeAi
end

--- True when the foe may spend their later call on a two-tile special.
local function attackStat(battler)
  return battleStat(battler, "attack")
end

function FoeAi.canChargeNow(battle, incoming, opts)
  opts = opts or {}
  if not RD or not battle or not RD.canReact(battle, false) then
    return false
  end
  if RD.isUnreactable(incoming) then
    return false
  end
  if not opts.fieldBattle then
    return false
  end
  if opts.statusLocked or opts.alreadyActed then
    return false
  end
  if (opts.chargeCount or 0) <= 0 then
    return false
  end
  if not RD.affordable(battle, false, "charge") then
    return false
  end
  if RD.isSpecialClashIncoming(incoming) then
    return false
  end
  return opts.playerChargeOpen == true or opts.incomingMelee == true
end

function FoeAi.canFireNow(battle, incoming, opts)
  opts = opts or {}
  if not RD or not battle or not RD.canReact(battle, false) then
    return false
  end
  if RD.isUnreactable(incoming) then
    return false
  end
  if not opts.fieldBattle then
    return false
  end
  if opts.statusLocked or opts.alreadyActed then
    return false
  end
  if opts.fireRangeOpen == false then
    return false
  end
  if not RD.affordable(battle, false, "fire") then
    return false
  end
  if (opts.shotCount or 0) <= 0 then
    return false
  end
  if RD.isSpecialClashIncoming(incoming) then
    return true
  end
  return opts.playerChargeOpen == true or opts.incomingMelee == true
end

--- Strongest remaining projectile special.
function FoeAi.pickFireShot(shots)
  if type(shots) ~= "table" or #shots == 0 then
    return nil
  end
  local function powerOf(shot)
    return tonumber(shot.moveDef and shot.moveDef.power)
      or tonumber(shot.power) or 0
  end
  local best = shots[1]
  local bestPower = powerOf(best)
  for i = 2, #shots do
    local shot = shots[i]
    local power = powerOf(shot)
    if power > bestPower then
      best = shot
      bestPower = power
    end
  end
  return best
end

--- Trainer-foe REACT pick. Weighted, not a fixed special→dodge / physical→brace
--- split. Unaffordable options drop out so a drained foe has to Commit.
--- FIRE is optional: specialists may take it when the two-tile window is open.
function FoeAi.pickFoeReact(battle, move, isSpecial, opts)
  opts = opts or {}
  if not RD or not battle or not RD.canReact(battle, false)
    or RD.isUnreactable(move) then
    return "commit"
  end
  if isSpecial == nil then
    isSpecial = RD.isSpecialClashIncoming(move)
  end
  local enemy = battle.enemy
  local player = battle.player
  local focus = (RD.sideState(battle, false).focus) or 0
  local speGap = speedStat(enemy) - speedStat(player)
  local bulk = isSpecial and specialStat(enemy) or defenseStat(enemy)

  local function jitter(w)
    return math.max(0, (w or 0) * (0.70 + rng() * 0.60))
  end

  local wCommit = jitter(30)
  local wDodge = jitter(isSpecial and 32 or 16)
  local wBrace = jitter(isSpecial and 16 or 32)
  local wFire = 0
  local wCharge = 0
  wDodge = wDodge + clamp(speGap * 0.12, -14, 16)
  wBrace = wBrace + clamp((bulk - 70) * 0.08, -10, 14)
  if opts.canFireNow and RD.affordable(battle, false, "fire") then
    wFire = jitter(18)
    wFire = wFire + clamp((specialStat(enemy) - 55) * 0.18, 0, 22)
    if isSpecial then
      wFire = wFire + 12
    else
      wFire = wFire + 8
    end
  end
  if opts.canChargeNow and RD.affordable(battle, false, "charge") then
    wCharge = jitter(16)
    wCharge = wCharge + clamp((attackStat(enemy) - 55) * 0.16, 0, 20)
    if not isSpecial then
      wCharge = wCharge + 14
    end
  end
  if focus <= 22 then
    wCommit = wCommit + 20
  end
  if not RD.affordable(battle, false, "dodge") then
    wDodge = 0
  end
  if not RD.affordable(battle, false, "brace") then
    wBrace = 0
  end
  if not RD.affordable(battle, false, "fire") then
    wFire = 0
  end
  if not RD.affordable(battle, false, "charge") then
    wCharge = 0
  end
  wDodge = math.max(0, wDodge)
  wBrace = math.max(0, wBrace)
  wCommit = math.max(0, wCommit)
  wFire = math.max(0, wFire)
  wCharge = math.max(0, wCharge)
  local total = wCommit + wDodge + wBrace + wFire + wCharge
  if total <= 0 then
    return "commit"
  end
  local roll = rng() * total
  if roll < wCommit then
    return "commit"
  end
  roll = roll - wCommit
  if roll < wDodge then
    return "dodge"
  end
  roll = roll - wDodge
  if roll < wBrace then
    return "brace"
  end
  roll = roll - wBrace
  if roll < wFire then
    return "fire"
  end
  if wCharge > 0 then
    return "charge"
  end
  return "commit"
end

return FoeAi
