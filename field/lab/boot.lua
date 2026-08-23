-- Field lab — load the real field / battle modules without the game host.
--
-- Works from Love (`love field/lab`) and from headless Lua
-- (`Boot("/path/to/mod")`). Not shipped in the mod zip.

local function join(a, b)
  a = tostring(a or ""):gsub("[/\\]+$", "")
  b = tostring(b or ""):gsub("^[/\\]+", "")
  if a == "" then
    return b
  end
  return a .. "/" .. b
end

return function(modRoot)
  if type(modRoot) ~= "string" or modRoot == "" then
    error("lab/boot.lua needs the anime-realism root", 2)
  end
  modRoot = modRoot:gsub("[/\\]+$", "")
  local fieldRoot = join(modRoot, "field")

  local function loadRel(rel)
    local path = join(fieldRoot, rel)
    local chunk, err = loadfile(path)
    if not chunk then
      error(tostring(err or path), 2)
    end
    return chunk()
  end

  local Coords = loadRel("pad/coords.lua")
  local Themes = loadRel("stage/themes.lua")
  local FxCatalog = loadRel("fx/fx_catalog.lua")
  package.loaded.coords = Coords
  package.loaded.themes = Themes
  package.loaded.fx_catalog = FxCatalog

  local TypeFace = loadRel("chrome/type.lua")
  package.loaded.field_type = TypeFace

  local Layout = loadRel("pad/layout.lua")
  local Sprites = loadRel("fx/sprites.lua")
  local Arena = loadRel("stage/arena.lua")
  local Grid = loadRel("pad/grid.lua")
  local Cues = loadRel("fx/cues.lua")
  Cues.attach(loadRel)
  local Projectiles = loadRel("fx/projectiles.lua")
  local UI = loadRel("chrome/ui.lua")
  local Debug = loadRel("chrome/debug.lua")
  local RD = assert(loadfile(join(modRoot, "battle/rules/reactive_defense.lua")))()
  local FoeAi = assert(loadfile(join(modRoot, "battle/rules/foe_ai.lua")))()
  FoeAi.attach(RD)

  local function readDisk(rel)
    if type(rel) ~= "string" or rel == "" then
      return nil
    end
    local path = rel
    if not path:match("^/") and not path:match("^%a:[/\\]") then
      path = join(modRoot, rel)
    elseif not path:find(modRoot, 1, true) then
      local tail = path:match("assets/.+$")
      if tail then
        path = join(modRoot, tail)
      end
    end
    local f = io.open(path, "rb")
    if not f then
      return nil
    end
    local body = f:read("*a")
    f:close()
    if type(body) == "string" and body ~= "" then
      return body
    end
    return nil
  end

  if Sprites and type(Sprites.bindReader) == "function" then
    Sprites.bindReader(readDisk)
  end
  if TypeFace and type(TypeFace.bindReader) == "function" then
    TypeFace.bindReader(readDisk)
  end

  return {
    root = modRoot,
    field = fieldRoot,
    read = readDisk,
    Coords = Coords,
    Themes = Themes,
    FxCatalog = FxCatalog,
    Type = TypeFace,
    Layout = Layout,
    Sprites = Sprites,
    Arena = Arena,
    Grid = Grid,
    Cues = Cues,
    Projectiles = Projectiles,
    UI = UI,
    Debug = Debug,
    RD = RD,
    FoeAi = FoeAi,
  }
end
