-- Named lab simulations. Each returns a step list for Stage.enqueue.

local Ember = {
  id = "EMBER", power = 40, category = "special", type = "FIRE",
}
local Tackle = {
  id = "TACKLE", power = 35, category = "physical", type = "NORMAL",
}
local Water = {
  id = "WATER_GUN", power = 40, category = "special", type = "WATER",
}

local M = {}

M.list = {
  { key = "1", id = "idle", title = "idle bob" },
  { key = "2", id = "dodge", title = "player DODGE" },
  { key = "3", id = "brace", title = "player BRACE" },
  { key = "4", id = "tackle", title = "player TACKLE" },
  { key = "5", id = "ember", title = "foe EMBER" },
  { key = "6", id = "clash", title = "beam clash" },
  { key = "7", id = "charge", title = "CHARGE crash" },
  { key = "8", id = "chips", title = "DODGE + MISS chips" },
}

function M.steps(id)
  if id == "idle" then
    return {
      { rebuild = true, note = "idle — watch the kits breathe" },
    }
  end
  if id == "dodge" then
    return {
      { cue = { side = "player", kind = "dodge" }, chip = { side = "player", text = "DODGE" } },
    }
  end
  if id == "brace" then
    return {
      { cue = { side = "player", kind = "brace" }, chip = { side = "player", text = "BRACE" } },
    }
  end
  if id == "tackle" then
    return {
      {
        cue = {
          side = "player",
          kind = "attack",
          opts = {
            category = "physical",
            moveId = Tackle.id,
            moveType = Tackle.type,
          },
        },
      },
    }
  end
  if id == "ember" then
    return {
      {
        cue = {
          side = "enemy",
          kind = "attack",
          opts = {
            category = "special",
            moveId = Ember.id,
            moveType = Ember.type,
          },
        },
      },
    }
  end
  if id == "clash" then
    return {
      { note = "ember vs water gun" },
      {
        cue = {
          side = "enemy",
          kind = "attack",
          opts = {
            category = "special",
            moveId = Ember.id,
            moveType = Ember.type,
          },
        },
      },
      { wait = 0.12 },
      {
        cue = {
          side = "player",
          kind = "fire",
          opts = {
            category = "special",
            moveId = Water.id,
            moveType = Water.type,
          },
        },
      },
    }
  end
  if id == "charge" then
    return {
      { cue = { side = "player", kind = "charge" }, chip = { side = "player", text = "CHARGE" } },
      { wait = 0.15 },
      {
        cue = {
          side = "enemy",
          kind = "attack",
          opts = {
            category = "physical",
            moveId = Tackle.id,
            moveType = Tackle.type,
          },
        },
      },
    }
  end
  if id == "chips" then
    return {
      { chip = { side = "player", text = "DODGE" } },
      { wait = 0.4 },
      { chip = { side = "enemy", text = "MISS" } },
    }
  end
  return { { note = "unknown scenario " .. tostring(id) } }
end

return M
