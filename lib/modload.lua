-- Shared mod file loader (zip + loose App Support installs).
--
-- Usage from main:
--   local ModLoad = load("lib/modload.lua") -- via read+load
--   local pkg = ModLoad.loadPackage("field")

return function(mod)
  local M = {}

  function M.readSource(name)
    local src = nil
    if type(mod.read) == "function" then
      local ok, body = pcall(function()
        return mod:read(name)
      end)
      if ok then
        src = body
      end
    end
    if type(src) ~= "string" and type(mod.path) == "string"
        and not (love and love.graphics) then
      local path = mod.path .. "/" .. name
      local f = io.open(path, "r")
      if f then
        src = f:read("*a")
        f:close()
      end
    end
    if type(src) == "string" and src ~= "" then
      return src
    end
    return nil
  end

  function M.loadFile(name)
    local src = M.readSource(name)
    if not src then
      return nil, "missing " .. tostring(name)
    end
    local chunk, err = load(src, "@" .. name)
    if not chunk then
      return nil, err
    end
    local ok, value = pcall(chunk)
    if not ok then
      return nil, value
    end
    return value
  end

  -- Load a folder package whose init.lua returns function(env) -> table,
  -- or a plain table. Sibling files are loaded via env.load("file.lua").
  function M.loadPackage(dir)
    local cache = {}
    local prefix = dir .. "/"
    local function loadSibling(name)
      if cache[name] ~= nil then
        return cache[name]
      end
      local src = M.readSource(prefix .. name)
      if not src then
        error("missing " .. prefix .. name, 2)
      end
      local chunk, err = load(src, "@" .. prefix .. name)
      if not chunk then
        error(tostring(err), 2)
      end
      local ok, value = pcall(chunk)
      if not ok then
        error(tostring(value), 2)
      end
      cache[name] = value
      return value
    end
    local ok, initOrErr = pcall(loadSibling, "init.lua")
    if not ok then
      return nil, initOrErr
    end
    local init = initOrErr
    if type(init) == "function" then
      local okF, value = pcall(init, { load = loadSibling, mod = mod, dir = dir })
      if not okF then
        return nil, value
      end
      return value
    end
    if type(init) == "table" then
      return init
    end
    return nil, dir .. "/init.lua must return a function or table"
  end

  return M
end
