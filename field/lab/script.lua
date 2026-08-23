-- Authored round: beats group into exchanges so reacts overlap the incoming.

local Script = {}

Script.REACTS = {
  { id = "dodge", label = "DODGE", key = "d" },
  { id = "miss", label = "MISS", key = "m" },
  { id = "brace", label = "BRACE", key = "b" },
  { id = "charge", label = "CHARGE", key = "c" },
  { id = "cover", label = "COVER", key = "v" },
  { id = "fire", label = "FIRE", key = "f" },
  { id = "hit", label = "HIT", key = "i" },
  { id = "wait", label = "WAIT", key = "w" },
}

local REPLY = {
  dodge = true,
  miss = true,
  brace = true,
  cover = true,
  hit = true,
  fire = true,
  charge = true,
}

function Script.new()
  return setmetatable({
    beats = {},
    cursor = 1,
    playIndex = 0,
  }, { __index = Script })
end

function Script.label(beat)
  if not beat then
    return ""
  end
  local who = beat.side == "enemy" and "E" or "P"
  if beat.kind == "attack" then
    local move = beat.move or {}
    return string.format("%s  %s", who, tostring(move.id or "ATTACK"))
  end
  return string.format("%s  %s", who, string.upper(tostring(beat.kind or "?")))
end

function Script.add(self, beat)
  self.beats[#self.beats + 1] = beat
  self.cursor = #self.beats
end

function Script.addAttack(self, side, move)
  if not move then
    return
  end
  Script.add(self, {
    kind = "attack",
    side = side,
    move = {
      id = move.id,
      power = move.power,
      category = move.category,
      type = move.type,
    },
  })
end

function Script.addReact(self, side, kind)
  if not kind then
    return
  end
  Script.add(self, { kind = kind, side = side or "player" })
end

function Script.remove(self, index)
  index = index or self.cursor
  if not self.beats[index] then
    return
  end
  table.remove(self.beats, index)
  self.cursor = math.max(1, math.min(index, #self.beats))
  if self.playIndex > #self.beats then
    self.playIndex = #self.beats
  end
end

function Script.clear(self)
  self.beats = {}
  self.cursor = 1
  self.playIndex = 0
end

function Script.isSpecial(beat)
  if not beat then
    return false
  end
  if beat.kind == "fire" then
    return true
  end
  return beat.kind == "attack" and beat.move and beat.move.category == "special"
end

function Script.isPhysical(beat)
  if not beat then
    return false
  end
  if beat.kind == "charge" then
    return true
  end
  return beat.kind == "attack" and (not beat.move or beat.move.category ~= "special")
end

-- Opposite-side react rides the opener. An opposite attack only pairs when
-- the opener was FIRE/CHARGE (crash / clash).
function Script.isReply(beat, opener)
  if not (beat and opener) then
    return false
  end
  if beat.kind == "wait" or opener.kind == "wait" then
    return false
  end
  if beat.side == opener.side then
    return false
  end
  if beat.kind == "attack" then
    return opener.kind == "charge" or opener.kind == "fire"
  end
  return REPLY[beat.kind] == true
end

function Script.exchanges(self, from)
  from = math.max(1, tonumber(from) or 1)
  local out = {}
  local i = from
  while i <= #self.beats do
    local opener = self.beats[i]
    local pack = { opener = opener, openerIndex = i, replies = {} }
    i = i + 1
    if i <= #self.beats and Script.isReply(self.beats[i], opener) then
      pack.replies[1] = { beat = self.beats[i], index = i }
      i = i + 1
    end
    out[#out + 1] = pack
  end
  return out
end

function Script.replyMarks(self)
  local mark = {}
  for _, pack in ipairs(Script.exchanges(self, 1)) do
    for r = 1, #pack.replies do
      mark[pack.replies[r].index] = true
    end
  end
  return mark
end

function Script.overlapOf(opener, reply)
  if not reply then
    return 0
  end
  if reply.kind == "dodge" or reply.kind == "brace" or reply.kind == "cover" then
    return 0.05
  end
  if reply.kind == "fire" or opener.kind == "fire" then
    return 0.12
  end
  if reply.kind == "charge" or opener.kind == "charge" then
    return 0.14
  end
  if reply.kind == "hit" or reply.kind == "miss" then
    return 0.62
  end
  return 0.10
end

function Script.settleOf(opener, reply)
  if opener and opener.kind == "wait" then
    return 0.7
  end
  if Script.isPhysical(opener) or (reply and (reply.kind == "charge" or Script.isPhysical(reply))) then
    return 1.75
  end
  return 1.55
end

function Script.compilePack(pack)
  local steps = {}
  if not pack or not pack.opener then
    return steps
  end
  local reply = pack.replies[1] and pack.replies[1].beat
  steps[#steps + 1] = {
    beat = pack.opener,
    index = pack.openerIndex,
    wait = reply and Script.overlapOf(pack.opener, reply) or Script.settleOf(pack.opener),
    opener = true,
  }
  if reply then
    steps[#steps + 1] = {
      beat = reply,
      index = pack.replies[1].index,
      wait = Script.settleOf(pack.opener, reply),
      reply = true,
    }
  end
  return steps
end

function Script.compile(self, from)
  local steps = {}
  local packs = Script.exchanges(self, from)
  for i = 1, #packs do
    local part = Script.compilePack(packs[i])
    for j = 1, #part do
      steps[#steps + 1] = part[j]
    end
  end
  return steps
end

function Script.packAt(self, beatIndex)
  local packs = Script.exchanges(self, 1)
  for i = 1, #packs do
    local pack = packs[i]
    if pack.openerIndex == beatIndex then
      return pack
    end
    for r = 1, #pack.replies do
      if pack.replies[r].index == beatIndex then
        return pack
      end
    end
  end
  return packs[1]
end

function Script.nextPack(self, afterIndex)
  afterIndex = tonumber(afterIndex) or 0
  local packs = Script.exchanges(self, 1)
  for i = 1, #packs do
    if packs[i].openerIndex > afterIndex then
      return packs[i]
    end
  end
  return packs[1]
end

function Script.encodeBeat(beat)
  if not beat then
    return ""
  end
  local who = beat.side == "enemy" and "E" or "P"
  if beat.kind == "attack" then
    local m = beat.move or {}
    return table.concat({
      who,
      "attack",
      tostring(m.id or "TACKLE"),
      tostring(m.category or "physical"),
      tostring(m.type or "NORMAL"),
      tostring(m.power or 40),
    }, "|")
  end
  return who .. "|" .. tostring(beat.kind)
end

function Script.decodeBeat(line)
  line = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if line == "" or line:sub(1, 1) == "#" then
    return nil
  end
  local parts = {}
  for bit in line:gmatch("[^|]+") do
    parts[#parts + 1] = bit
  end
  if #parts < 2 then
    return nil
  end
  local side = parts[1] == "E" and "enemy" or "player"
  local kind = parts[2]
  if kind == "attack" then
    return {
      kind = "attack",
      side = side,
      move = {
        id = parts[3] or "TACKLE",
        category = parts[4] or "physical",
        type = parts[5] or "NORMAL",
        power = tonumber(parts[6]) or 40,
      },
    }
  end
  return { kind = kind, side = side }
end

function Script.dump(self)
  local lines = {}
  for i = 1, #self.beats do
    lines[#lines + 1] = Script.encodeBeat(self.beats[i])
  end
  return table.concat(lines, "\n")
end

function Script.load(self, text)
  Script.clear(self)
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local beat = Script.decodeBeat(line)
    if beat then
      Script.add(self, beat)
    end
  end
  return #self.beats
end

return Script
