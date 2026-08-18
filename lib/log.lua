-- DEV console logger (Love stdout / terminal).
--
-- Loaded from main via ModLoad.loadFile("lib/log.lua"). Silent when DEV is
-- off. Never throws — logging must not become the crash.

return function(env)
  local Log = {}
  local trail = {}
  local trailMax = 80
  local seq = 0

  pcall(function()
    if io and io.stdout and io.stdout.setvbuf then
      io.stdout:setvbuf("no")
    end
  end)

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
      if #s > 220 then
        return s:sub(1, 217) .. "..."
      end
      return s
    end
    return t
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
      trail[#trail + 1] = line
      while #trail > trailMax do
        table.remove(trail, 1)
      end
    end)
    if not ok then
      pcall(print, "[ar] logger: " .. tostring(err))
    end
  end

  function Log.err(battle, tag, err)
    Log.note(battle, "ERR " .. tostring(tag or "?"), err)
    Log.dump()
  end

  function Log.trace(battle, tag, err)
    local tb = err
    if type(debug) == "table" and type(debug.traceback) == "function" then
      tb = debug.traceback(tostring(err or tag), 2)
    end
    Log.err(battle, tag, tb)
    return tb
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
