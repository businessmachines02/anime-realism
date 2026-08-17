-- Field battle — location-themed arena kits.
--
-- Themes.scene(battle) picks a kit from the current map id (route, cave,
-- gym, …). Kits describe overlay prop density/colors only — live map tiles
-- are never read or written. Optional arenas/*.lua files can supply hand-
-- crafted pad layouts when present.

local Themes = {}

local KITS = {
  cave = {
    cover = "ROCK",
    coverN = { 2, 4 },
    grassN = { 1, 3 },
    grassKind = "moss",
    pondN = { 1, 2 },
    floor = { 0.30, 0.28, 0.26 },
    floor2 = { 0.24, 0.22, 0.20 },
    grass = { 0.22, 0.32, 0.24 },
    pond = { 0.14, 0.22, 0.34 },
    pond2 = { 0.20, 0.32, 0.42 },
  },
  forest = {
    cover = "TREE",
    coverN = { 2, 4 },
    grassN = { 3, 6 },
    grassKind = "grass",
    pondN = { 0, 1 },
    floor = { 0.20, 0.38, 0.18 },
    floor2 = { 0.16, 0.32, 0.14 },
    grass = { 0.28, 0.52, 0.22 },
    pond = { 0.16, 0.28, 0.40 },
    pond2 = { 0.22, 0.38, 0.50 },
  },
  route = {
    cover = "TREE",
    coverN = { 2, 3 },
    grassN = { 2, 5 },
    grassKind = "grass",
    pondN = { 0, 1 },
    floor = { 0.42, 0.62, 0.28 },
    floor2 = { 0.36, 0.54, 0.24 },
    grass = { 0.32, 0.58, 0.22 },
    pond = { 0.22, 0.40, 0.58 },
    pond2 = { 0.30, 0.52, 0.68 },
  },
  city = {
    cover = "CRATE",
    coverN = { 2, 3 },
    grassN = { 0, 1 },
    grassKind = "planter",
    pondN = { 0, 0 },
    floor = { 0.52, 0.50, 0.46 },
    floor2 = { 0.46, 0.44, 0.40 },
    grass = { 0.28, 0.48, 0.24 },
    pond = { 0.30, 0.42, 0.52 },
    pond2 = { 0.36, 0.50, 0.60 },
  },
  mountain = {
    cover = "ROCK",
    coverN = { 2, 4 },
    grassN = { 1, 2 },
    grassKind = "scrub",
    pondN = { 0, 1 },
    floor = { 0.40, 0.36, 0.32 },
    floor2 = { 0.34, 0.30, 0.26 },
    grass = { 0.30, 0.38, 0.22 },
    pond = { 0.18, 0.28, 0.40 },
    pond2 = { 0.24, 0.36, 0.48 },
  },
  water = {
    cover = "ROCK",
    coverN = { 2, 3 },
    grassN = { 1, 2 },
    grassKind = "sandgrass",
    pondN = { 1, 2 },
    floor = { 0.72, 0.66, 0.48 },
    floor2 = { 0.64, 0.58, 0.40 },
    grass = { 0.40, 0.56, 0.28 },
    pond = { 0.20, 0.42, 0.62 },
    pond2 = { 0.28, 0.54, 0.74 },
  },
  grave = {
    cover = "ROCK",
    coverN = { 2, 3 },
    grassN = { 1, 2 },
    grassKind = "weeds",
    pondN = { 0, 1 },
    floor = { 0.28, 0.26, 0.24 },
    floor2 = { 0.22, 0.20, 0.18 },
    grass = { 0.24, 0.28, 0.18 },
    pond = { 0.12, 0.16, 0.18 },
    pond2 = { 0.16, 0.20, 0.22 },
  },
  gym = {
    cover = "CRATE",
    coverN = { 1, 2 },
    grassN = { 0, 0 },
    grassKind = "mat",
    pondN = { 0, 0 },
    floor = { 0.62, 0.50, 0.32 },
    floor2 = { 0.54, 0.42, 0.26 },
    grass = { 0.50, 0.40, 0.24 },
    pond = { 0.30, 0.30, 0.32 },
    pond2 = { 0.36, 0.36, 0.38 },
  },
  indoor = {
    cover = "CRATE",
    coverN = { 0, 1 },
    grassN = { 0, 0 },
    grassKind = "rug",
    pondN = { 0, 0 },
    floor = { 0.58, 0.48, 0.36 },
    floor2 = { 0.50, 0.40, 0.30 },
    grass = { 0.48, 0.30, 0.22 },
    pond = { 0.30, 0.30, 0.32 },
    pond2 = { 0.36, 0.36, 0.38 },
  },
}

KITS.default = KITS.route

local LAYOUTS = {}

function Themes.registerLayout(id, layout)
  if type(id) == "string" and type(layout) == "table" then
    LAYOUTS[id] = layout
  end
end

function Themes.layout(scene)
  return LAYOUTS[scene]
end

function Themes.scene(battle)
  local mapId = ""
  if battle and type(battle.currentMapId) == "function" then
    mapId = tostring(battle:currentMapId() or "")
  end
  local id = mapId:upper()
  local tileset = nil
  local maps = battle and battle.game and battle.game.data and battle.game.data.maps
  local def = maps and mapId ~= "" and maps[mapId]
  if type(def) == "table" then
    tileset = def.tileset
  end
  local ts = tostring(tileset or ""):upper()

  if ts == "CAVERN" or ts == "UNDERGROUND"
      or id:find("CAVE", 1, true) or id:find("TUNNEL", 1, true)
      or id:find("MT_MOON", 1, true) or id:find("ROCK_TUNNEL", 1, true)
      or id:find("CERULEAN_CAVE", 1, true) then
    return "cave"
  end
  if ts == "FOREST" or ts == "FOREST_GATE" or id:find("FOREST", 1, true) then
    return "forest"
  end
  if ts == "CEMETERY" or id:find("POKEMON_TOWER", 1, true)
      or id:find("LAVENDER", 1, true) then
    return "grave"
  end
  if ts == "GYM" or ts == "DOJO" or id:find("_GYM", 1, true) or id:find("GYM_", 1, true) then
    return "gym"
  end
  if ts == "PLATEAU" or id:find("VICTORY", 1, true)
      or id:find("MT_", 1, true) then
    return "mountain"
  end
  if ts == "SHIP" or ts == "SHIP_PORT" or id:find("SEAFOAM", 1, true)
      or id:find("SS_ANNE", 1, true) then
    return "water"
  end
  if id:find("CITY", 1, true) or id:find("TOWN", 1, true) then
    return "city"
  end
  if ts == "HOUSE" or ts == "MART" or ts == "POKECENTER" or ts == "INTERIOR"
      or ts == "LAB" or ts == "LOBBY" or ts == "FACILITY" or ts == "CLUB"
      or ts == "MUSEUM" or ts == "MANSION" or ts == "GATE"
      or ts == "REDS_HOUSE_1" or ts == "REDS_HOUSE_2" then
    return "indoor"
  end
  return "route"
end

function Themes.kit(scene)
  local base = KITS[scene] or KITS.default
  local hand = LAYOUTS[scene]
  if type(hand) ~= "table" then
    return base
  end
  return {
    cover = hand.coverKind or (hand.cover and hand.cover[1] and hand.cover[1].kind) or base.cover,
    coverN = base.coverN,
    grassN = base.grassN,
    grassKind = base.grassKind,
    pondN = base.pondN,
    floor = hand.floor or base.floor,
    floor2 = hand.floor2 or base.floor2,
    grass = hand.grassColor or base.grass,
    pond = hand.pondColor or base.pond,
    pond2 = hand.pondColor2 or base.pond2,
    layout = hand,
  }
end

return Themes
