-- Baked follower kits that the lab can actually spawn.

local Dex = require("dex")
local Species = require("species")

local Roster = {}

function Roster.scan(modRoot)
  local list = {}
  for dex = 1, #Dex do
    local nnn = string.format("%03d", dex)
    local path = tostring(modRoot or ".") .. "/assets/followers/follower_" .. nnn .. ".png"
    local f = io.open(path, "rb")
    if f then
      f:close()
      list[#list + 1] = {
        name = Dex[dex] or ("#" .. nnn),
        dex = dex,
        nnn = nnn,
      }
    end
  end
  return list
end

function Roster.indexOf(list, dex)
  for i = 1, #(list or {}) do
    if list[i].dex == dex then
      return i
    end
  end
  return 1
end

function Roster.filter(list, query)
  query = tostring(query or ""):upper():gsub("%s+", "")
  local out = {}
  for i = 1, #(list or {}) do
    local s = list[i]
    local name = tostring(s.name or "")
    local nnn = s.nnn or string.format("%03d", s.dex or 0)
    local tag = Species.typeTag(Species.types(s.dex)):upper()
    local hit = query == ""
      or name:upper():find(query, 1, true)
      or nnn:find(query, 1, true)
      or tag:find(query, 1, true)
    if hit then
      out[#out + 1] = {
        name = s.name,
        dex = s.dex,
        nnn = nnn,
        _index = i,
      }
    end
  end
  return out
end

return Roster
