-- DEV console logger (Love stdout / terminal).
--
-- Loaded from main via ModLoad.loadFile("lib/log.lua"). Silent when DEV is
-- off. Never throws — logging must not become the crash.

return function(env)
  local Log = {}
  local trail = {}
  local trailMax = 24
  local seq = 0
  local errN = 0

  function Log.enabled()
    if env and type(env.enabled) == "function" then
      local ok, on = pcall(env.enabled)
      return ok and on and true or false
    end
    return env and env.DEV == true
  end

  local function fmt(v)
    local t = type(v)
    if v == nil then
      return "-"
    end
    if t == "string" or t == "number" or t == "boolean" then
      local s = tostring(v)
      if #s > 120 then
        return s:sub(1, 117) .. "..."
      end
      return s
    end
    return t
  end

  local function pushTrail(line)
    trail[#trail + 1] = line
    while #trail > trailMax do
      table.remove(trail, 1)
    end
  end

  function Log.dump()
    if not Log.enabled() then
      return
    end
    pcall(function()
      print("[ar] --- last " .. tostring(#trail) .. " events ---")
      for i = 1, #trail do
        print("  " .. trail[i])
      end
      print("[ar] --- end ---")
    end)
  end

  function Log.note(battle, tag, ...)
    if not Log.enabled() then
      return
    end
    local n = select("#", ...)
    local extras = {}
    for i = 1, n do
      extras[i] = select(i, ...)
    end
    local ok, err = pcall(function()
      seq = seq + 1
      local turn = 0
      if type(battle) == "table" then
        turn = tonumber(battle.turnCount) or 0
      end
      local extra = ""
      if n > 0 then
        local parts = {}
        for i = 1, n do
          parts[i] = fmt(extras[i])
        end
        extra = " " .. table.concat(parts, " ")
      end
      local line = string.format("[ar] #%d T%d %s%s",
        seq, turn, tostring(tag or "?"), extra)
      print(line)
      pushTrail(line)
    end)
    if not ok then
      pcall(print, "[ar] logger: " .. tostring(err))
    end
  end

  function Log.err(battle, tag, err)
    errN = errN + 1
    Log.note(battle, "ERR " .. tostring(tag or "?"), err)
    -- First few errors dump the ring; then every 30th so a per-frame
    -- tickPresent failure does not flood the console.
    if errN <= 8 or (errN % 30) == 0 then
      Log.dump()
    end
  end

  function Log.caught(battle, tag, ok, err)
    if ok then
      return ok, err
    end
    Log.err(battle, tag, err)
    return ok, err
  end

  return Log
end
