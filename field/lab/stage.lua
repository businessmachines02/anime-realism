-- Field lab — fake fight: kits, move pools, FoeAi on both sides, random props.

local Roster = require("roster")
local Species = require("species")
local Script = require("script")

local Stage = {}

Stage.Species = Species
Stage.DEFAULT_MOVES = Species.STAB.NORMAL

Stage.SCENES = { "ROUTE_1", "VIRIDIAN_FOREST", "MT_MOON", "SAFFRON_CITY", "VICTORY_ROAD" }
Stage.PROP_KINDS = { "TREE", "ROCK", "CRATE", "POND" }
-- Lab pad only. Fight-axis span + lateral half-width (cells).
Stage.PAD_SPAN = 22
Stage.PAD_HALF_V = 6
Stage.PAD_MARGIN = 5

local function rng()
  local r = (love and love.math and love.math.random) or math.random
  return r()
end

local function ri(a, b)
  local r = (love and love.math and love.math.random) or math.random
  return r(a, b)
end

local function pokeData(roster)
  local data = {}
  for i = 1, #(roster or Stage.SPECIES or {}) do
    local s = roster[i]
    data[s.name] = Species.def(s.dex, s.name)
  end
  return data
end

local function battlerOf(species, data)
  local def = data[species] or Species.def(0, species)
  local stats = def.stats
  local types = def.types or { "NORMAL" }
  return {
    shownHP = stats.hp,
    stats = stats,
    def = def,
    curTypes = types,
    mon = {
      name = species,
      species = species,
      hp = stats.hp,
      stats = stats,
      types = types,
      type1 = types[1],
      type2 = types[2],
    },
  }
end

function Stage.speciesName(index)
  local row = Stage.SPECIES[((index - 1) % #Stage.SPECIES) + 1]
  return row.name
end

function Stage.new(mods, opts)
  opts = opts or {}
  local roster = opts.roster
  if type(roster) ~= "table" or #roster < 1 then
    roster = Roster.scan(mods and mods.root or ".")
  end
  Stage.SPECIES = roster
  local self = {
    mods = mods,
    roster = roster,
    playerIndex = opts.playerIndex or Roster.indexOf(roster, 25),
    enemyIndex = opts.enemyIndex or Roster.indexOf(roster, 76),
    sceneIndex = opts.sceneIndex or 1,
    zoom = opts.zoom or 2,
    auto = opts.auto == true,
    hold = false,
    script = opts.script or Script.new(),
    lastMove = nil,
    lastAttacker = nil,
    log = {},
    queue = {},
    wait = 0,
    beat = 0,
  }
  Stage.rebuild(self)
  return setmetatable(self, { __index = Stage })
end

function Stage.setSpecies(self, side, index)
  local n = #(self.roster or Stage.SPECIES)
  if n < 1 then
    return
  end
  index = ((tonumber(index) or 1) - 1) % n + 1
  if side == "enemy" then
    self.enemyIndex = index
  else
    self.playerIndex = index
  end
  local keep = self.auto
  Stage.rebuild(self)
  self.auto = keep
end

local function placeMons(self, plan, grid, data)
  local mods = self.mods
  local pName = Stage.speciesName(self.playerIndex)
  local eName = Stage.speciesName(self.enemyIndex)
  local pHome, eHome = grid.home.player, grid.home.enemy
  local pCellX, pCellY = mods.Coords.padToWorld(grid, pHome.u, pHome.v)
  local eCellX, eCellY = mods.Coords.padToWorld(grid, eHome.u, eHome.v)
  local playerB = battlerOf(pName, data)
  local enemyB = battlerOf(eName, data)
  local player = mods.Sprites.makeMon(
    self.mod, self.game, pName, pCellX, pCellY, plan.playerFace, "player", playerB, grid)
  local enemy = mods.Sprites.makeMon(
    self.mod, self.game, eName, eCellX, eCellY, plan.foeFace, "enemy", enemyB, grid)
  player._arFieldBattler, player._arFieldSide = true, "player"
  enemy._arFieldBattler, enemy._arFieldSide = true, "enemy"
  mods.Grid.setPad(grid, player, player.padU or pHome.u, player.padV or pHome.v)
  mods.Grid.setPad(grid, enemy, enemy.padU or eHome.u, enemy.padV or eHome.v)
  return player, enemy, playerB, enemyB, pName, eName
end

local function overlayFromSlots(Arena, slots)
  local covers = {}
  for i = 1, #(slots or {}) do
    local prop = Arena.overlayEntity(slots[i])
    if prop then
      covers[#covers + 1] = prop
    end
  end
  return covers
end

function Stage.injectProps(self, count)
  local mods = self.mods
  local grid = self.grid
  if not (grid and grid.sizeU) then
    return 0
  end
  local free = {}
  for u = 0, (grid.sizeU or 1) - 1 do
    for v = 0, (grid.sizeV or 1) - 1 do
      local key = mods.Coords.key(u, v)
      if not (grid.blocked and grid.blocked[key]) and not (grid.occ and grid.occ[key]) then
        free[#free + 1] = { u = u, v = v }
      end
    end
  end
  count = math.min(tonumber(count) or ri(2, 4), #free)
  local added = 0
  for _ = 1, count do
    if #free < 1 then
      break
    end
    local i = ri(1, #free)
    local pad = table.remove(free, i)
    local wx, wy = mods.Coords.padToWorld(grid, pad.u, pad.v)
    local px, py = mods.Coords.padToPx(grid, pad.u, pad.v)
    local kind = Stage.PROP_KINDS[ri(1, #Stage.PROP_KINDS)]
    local slot = {
      u = pad.u, v = pad.v, cx = wx, cy = wy, px = px, py = py, kind = kind,
    }
    grid.blocked[mods.Coords.key(pad.u, pad.v)] = true
    local prop = mods.Arena.overlayEntity(slot)
    if prop then
      self.session.covers = self.session.covers or {}
      self.session.covers[#self.session.covers + 1] = prop
      added = added + 1
    end
  end
  if added > 0 then
    Stage.note(self, "dropped " .. added .. " props")
  end
  return added
end

function Stage.rebuild(self)
  local mods = self.mods
  local data = pokeData(self.roster or Stage.SPECIES)
  local scene = Stage.SCENES[((self.sceneIndex - 1) % #Stage.SCENES) + 1]
  self.sceneId = scene
  local mid = 20
  local half = math.floor((Stage.PAD_SPAN or 22) / 2)
  local plan = mods.Layout.plan(mid - half, mid, mid + half, mid)
  plan.padHalfV = Stage.PAD_HALF_V or 6
  local rect = mods.Arena.padRect(plan)
  local slack = Stage.PAD_MARGIN or 5
  rect.minX = (rect.minX or 0) - slack
  rect.maxX = (rect.maxX or 0) + slack
  rect.minY = (rect.minY or 0) - slack
  rect.maxY = (rect.maxY or 0) + slack
  local battleStub = {
    currentMapId = function()
      return scene
    end,
  }
  local layout = mods.Arena.generate(battleStub, plan, ri(1, 99999), { gridRect = rect })
  local grid = mods.Grid.build(layout, plan)

  self.game = {
    data = { pokemon = data },
    overworld = {
      camera = { x = 0, y = 0 },
      entities = {},
    },
    renderer = {
      uiSize = function() return 320, 288 end,
      worldViewSize = function() return 320, 288 end,
      fitScale = function() return 1 end,
    },
  }
  self.mod = {
    path = mods.root,
    options = {
      get = function()
        return "AUTO"
      end,
    },
  }

  local player, enemy, playerB, enemyB, pName, eName = placeMons(self, plan, grid, data)
  self.game.overworld.entities = { player, enemy }

  local battle = {
    _arAnimeField = true,
    kind = "wild",
    frame = 1,
    player = playerB,
    enemy = enemyB,
    game = self.game,
    currentMapId = function()
      return scene
    end,
  }
  if mods.RD and type(mods.RD.state) == "function" then
    mods.RD.state(battle)
  end

  local session = {
    live = true,
    state = "Live",
    grid = grid,
    playerMon = player,
    enemyMon = enemy,
    closeTheGap = true,
    projectiles = {},
    covers = overlayFromSlots(mods.Arena, layout and layout.overlay),
    floor = layout and mods.Arena.floorEntity(layout) or nil,
    _now = 1,
    _battle = battle,
    _deps = {
      Projectiles = mods.Projectiles,
      Cues = mods.Cues,
      UI = mods.UI,
      Grid = mods.Grid,
    },
  }
  battle._arFieldSession = session

  self.plan = plan
  self.grid = grid
  self.battle = battle
  self.session = session
  self.playerName = pName
  self.enemyName = eName
  local pDef = data[pName]
  local eDef = data[eName]
  self.playerMoves = Species.moves(pName, pDef and pDef.types)
  self.enemyMoves = Species.moves(eName, eDef and eDef.types)
  self.playerTypes = pDef and pDef.types or { "NORMAL" }
  self.enemyTypes = eDef and eDef.types or { "NORMAL" }
  if not self._keepQueue then
    self.queue = {}
  end
  self._keepQueue = nil
  self.wait = self.auto and 0.6 or 0
  self.beat = 0
  self.nextAttacker = "player"
  Stage.note(self, pName .. " vs " .. eName .. "  (" .. scene:lower() .. ")")
  Stage.injectProps(self, ri(4, 8))
end

function Stage.centerCamera(self)
  local grid = self.grid
  local cam = self.game and self.game.overworld and self.game.overworld.camera
  if not (grid and cam) then
    return
  end
  local midX, midY
  if grid.minX and grid.maxX then
    midX = (grid.minX + grid.maxX) * 8 + 8
    midY = (grid.minY + grid.maxY) * 8 + 8
  else
    local player = self.session and self.session.playerMon
    local enemy = self.session and self.session.enemyMon
    midX = ((player and player.px or 0) + (enemy and enemy.px or 0)) / 2
    midY = ((player and player.py or 0) + (enemy and enemy.py or 0)) / 2
  end
  local zoom = self.zoom or 2
  local vw, vh = 960, 720
  if love and love.graphics then
    vw = love.graphics.getWidth() or vw
    vh = love.graphics.getHeight() or vh
  end
  cam.x = midX - (vw / zoom) / 2
  cam.y = midY - (vh / zoom) / 2
end

function Stage.note(self, text)
  local line = tostring(text or "")
  self.log[#self.log + 1] = line
  while #self.log > 8 do
    table.remove(self.log, 1)
  end
  print("[lab] " .. line)
end

function Stage.cycleSpecies(self, side, dir)
  local cur = side == "enemy" and self.enemyIndex or self.playerIndex
  Stage.setSpecies(self, side, (cur or 1) + (dir or 1))
end

function Stage.swapSides(self)
  self.playerIndex, self.enemyIndex = self.enemyIndex, self.playerIndex
  local keep = self.auto
  Stage.rebuild(self)
  self.auto = keep
end

function Stage.randomPair(self)
  local n = #(self.roster or Stage.SPECIES)
  if n < 1 then
    return
  end
  self.playerIndex = ri(1, n)
  self.enemyIndex = ri(1, n)
  local keep = self.auto
  Stage.rebuild(self)
  self.auto = keep
end

function Stage.heal(self)
  local function refill(battler)
    if not battler then
      return
    end
    local maxHP = tonumber(battler.stats and battler.stats.hp) or 80
    if battler.mon then
      battler.mon.hp = maxHP
    end
    battler.shownHP = maxHP
  end
  refill(self.battle and self.battle.player)
  refill(self.battle and self.battle.enemy)
  Stage.note(self, "healed both sides")
end

function Stage.cycleScene(self, dir)
  self.sceneIndex = (self.sceneIndex or 1) + (dir or 1)
  Stage.rebuild(self)
end

function Stage.cue(self, side, kind, opts)
  local mods = self.mods
  local ok = mods.Cues.apply(self.session, side, kind, mods.Grid, nil, self.battle, opts or {})
  Stage.note(self, (ok and "" or "fail ") .. tostring(side) .. " " .. tostring(kind)
    .. " " .. tostring(opts and opts.moveId or ""))
  return ok
end

function Stage.chip(self, side, text)
  local UI = self.mods.UI
  if UI and type(UI.armStatusChip) == "function" then
    UI.armStatusChip(self.battle, side, text)
  end
end

local function specialsOf(pool)
  local out = {}
  for i = 1, #(pool or {}) do
    if pool[i].category == "special" then
      out[#out + 1] = pool[i]
    end
  end
  return out
end

local function physicalsOf(pool)
  local out = {}
  for i = 1, #(pool or {}) do
    if pool[i].category ~= "special" then
      out[#out + 1] = pool[i]
    end
  end
  return out
end

function Stage.poolOf(self, side)
  return side == "enemy" and self.enemyMoves or self.playerMoves
end

function Stage.reactMove(self, side, kind)
  local pool = Stage.poolOf(self, side)
  if kind == "fire" then
    local shots = specialsOf(pool)
    return shots[1] or (pool and pool[1])
  end
  if kind == "charge" then
    local hits = physicalsOf(pool)
    return hits[1] or (pool and pool[1])
  end
  return pool and pool[1]
end

function Stage.clearReactFlags(self)
  local battle = self.battle
  if not battle then
    return
  end
  battle._arFireNow = nil
  battle._arFireNowHit = nil
  battle._arFireNowCharger = nil
  battle._arChargeNow = nil
  battle._arCheckNow = nil
  battle._arHazeNow = nil
end

function Stage.playFire(self, side, asReply)
  local move = Stage.reactMove(self, side, "fire")
    or { id = "SWIFT", power = 60, category = "special", type = "NORMAL" }
  Stage.chip(self, side, "FIRE")
  if asReply and self.lastMove and Script.isSpecial({ kind = "attack", move = self.lastMove }) then
    local Cues = self.mods.Cues
    if Cues and type(Cues.playBeamClash) == "function" then
      Cues.playBeamClash(self.session, self.mods.Grid, {}, {
        move = self.lastMove,
        replyMove = move,
        replySide = side,
      })
      Stage.note(self, "beam clash  " .. tostring(self.lastMove.id) .. " vs " .. move.id)
      return move
    end
  end
  if asReply then
    self.battle._arFireNow = true
    self.battle._arFireNowCharger = side == "player" and "enemy" or "player"
    self.battle._arFireNowHit = nil
  end
  Stage.note(self, (side == "enemy" and self.enemyName or self.playerName)
    .. " FIRE " .. move.id)
  Stage.cue(self, side, "attack", {
    category = "special",
    moveId = move.id,
    moveType = move.type,
    fireNow = asReply == true,
  })
  if not asReply then
    self.lastMove = move
    self.lastAttacker = side
  end
  return move
end

function Stage.playCharge(self, side, asReply)
  local move = Stage.reactMove(self, side, "charge")
    or { id = "TACKLE", power = 35, category = "physical", type = "NORMAL" }
  Stage.chip(self, side, "CHARGE")
  if asReply and self.lastMove and Script.isPhysical({ kind = "attack", move = self.lastMove }) then
    local Cues = self.mods.Cues
    if Cues and type(Cues.playChargeClash) == "function" then
      Cues.playChargeClash(self.session, self.mods.Grid, {}, {
        move = self.lastMove,
        replyMove = move,
        replySide = side,
      })
      Stage.note(self, "charge clash  " .. tostring(self.lastMove.id) .. " vs " .. move.id)
      return move
    end
  end
  if asReply then
    self.battle._arChargeNow = true
  end
  Stage.note(self, (side == "enemy" and self.enemyName or self.playerName)
    .. " CHARGE " .. move.id)
  Stage.cue(self, side, "attack", {
    category = "physical",
    moveId = move.id,
    moveType = move.type,
  })
  if not asReply then
    self.lastMove = move
    self.lastAttacker = side
  end
  return move
end

function Stage.playBeat(self, beat, asReply)
  if not beat then
    return
  end
  if not asReply then
    Stage.clearReactFlags(self)
  end
  if beat.kind == "wait" then
    Stage.note(self, "wait")
    return
  end
  if beat.kind == "attack" then
    local move = beat.move or Stage.pickMove(self, beat.side == "player")
    if not asReply then
      self.lastMove = move
      self.lastAttacker = beat.side
    end
    Stage.note(self, (beat.side == "enemy" and self.enemyName or self.playerName)
      .. " uses " .. tostring(move.id))
    Stage.playAttack(self, beat.side, move)
    return
  end
  if beat.kind == "fire" then
    Stage.playFire(self, beat.side, asReply)
    return
  end
  if beat.kind == "charge" then
    Stage.playCharge(self, beat.side, asReply)
    return
  end
  if beat.kind == "hit" then
    Stage.cue(self, beat.side, "hit", {})
    Stage.chip(self, beat.side, "HIT")
    Stage.hurt(self, beat.side == "player", self.lastMove)
    return
  end
  if beat.kind == "miss" then
    Stage.chip(self, beat.side, "MISS")
    Stage.cue(self, beat.side, "miss", {})
    Stage.hurt(self, beat.side == "player", self.lastMove)
    Stage.note(self, beat.side .. " MISS")
    return
  end
  if beat.kind == "dodge" then
    Stage.cue(self, beat.side, "dodge", {})
    Stage.chip(self, beat.side, "DODGE")
    Stage.note(self, beat.side .. " DODGE")
    return
  end
  Stage.playReact(self, beat.side, beat.kind, self.lastMove or {})
end

function Stage.applyStep(self, step)
  if not step then
    return
  end
  if type(step.wait) == "number" then
    self.wait = step.wait
  end
  if step.rebuild then
    self._keepQueue = true
    Stage.rebuild(self)
  end
  if step.beat then
    if type(step.index) == "number" then
      self.script.playIndex = step.index
      self.script.cursor = step.index
    end
    Stage.playBeat(self, step.beat, step.reply == true)
  end
  if step.cue then
    Stage.cue(self, step.cue.side, step.cue.kind, step.cue.opts)
  end
  if step.chip then
    Stage.chip(self, step.chip.side, step.chip.text)
  end
  if type(step.note) == "string" then
    Stage.note(self, step.note)
  end
end

function Stage.playing(self)
  return self.queue and self.queue[1] and not self.hold
end

function Stage.playScript(self, from)
  local script = self.script
  if not script or #script.beats < 1 then
    Stage.note(self, "round is empty — add beats with 1-4 or the palette")
    return
  end
  if self.auto then
    self.auto = false
    Stage.dumpRound(self)
  end
  self.auto = false
  self.hold = false
  from = math.max(1, tonumber(from) or 1)
  script.playIndex = from - 1
  Stage.enqueue(self, Script.compile(script, from))
  Stage.note(self, "playing " .. (#script.beats - from + 1) .. " beats")
end

function Stage.stepScript(self)
  local script = self.script
  if not script or #script.beats < 1 then
    Stage.note(self, "round is empty")
    return
  end
  self.auto = false
  self.hold = false
  local pack = Script.nextPack(script, script.playIndex or 0)
  if not pack then
    pack = Script.nextPack(script, 0)
  end
  if not pack then
    return
  end
  script.playIndex = pack.openerIndex
  script.cursor = pack.openerIndex
  Stage.enqueue(self, Script.compilePack(pack))
  Stage.note(self, "exchange  " .. Script.label(pack.opener)
    .. (pack.replies[1] and ("  /  " .. Script.label(pack.replies[1].beat)) or ""))
end

function Stage.replayScript(self)
  local script = self.script
  local keepAuto = false
  Stage.rebuild(self)
  self.script = script
  self.auto = keepAuto
  self.lastMove = nil
  self.lastAttacker = nil
  Stage.playScript(self, 1)
end

function Stage.toggleHold(self)
  if self.queue[1] or self.wait > 0 then
    self.hold = not self.hold
    Stage.note(self, self.hold and "paused" or "resume")
    return
  end
  Stage.playScript(self, 1)
end

function Stage.pumpQueue(self)
  while self.wait <= 0 and self.queue[1] do
    local step = table.remove(self.queue, 1)
    Stage.applyStep(self, step)
    if type(step.wait) == "number" and step.wait > 0 then
      break
    end
  end
end

function Stage.enqueue(self, steps)
  self.auto = false
  self.queue = {}
  for i = 1, #(steps or {}) do
    self.queue[#self.queue + 1] = steps[i]
  end
  self.wait = 0
  Stage.pumpQueue(self)
end

function Stage.pickMove(self, isPlayer)
  local pool = isPlayer and self.playerMoves or self.enemyMoves
  if not pool or #pool < 1 then
    return { id = "TACKLE", power = 35, category = "physical", type = "NORMAL" }
  end
  local shots = specialsOf(pool)
  if #shots > 0 and rng() < 0.55 then
    return shots[ri(1, #shots)]
  end
  return pool[ri(1, #pool)]
end

function Stage.pickReact(self, isPlayer, incoming)
  local RD = self.mods.RD
  if not (RD and type(RD.pickFoeReact) == "function") then
    return "commit"
  end
  local opts = {
    fieldBattle = true,
    canFireNow = true,
    canChargeNow = incoming.category == "physical",
    fireRangeOpen = true,
    playerChargeOpen = incoming.category == "physical",
    incomingMelee = incoming.category == "physical",
    shotCount = 2,
    chargeCount = 1,
  }
  local battle = self.battle
  if isPlayer then
    battle.player, battle.enemy = battle.enemy, battle.player
    local pick = RD.pickFoeReact(battle, incoming, incoming.category == "special", opts)
    battle.player, battle.enemy = battle.enemy, battle.player
    return pick
  end
  return RD.pickFoeReact(battle, incoming, incoming.category == "special", opts)
end

function Stage.hurt(self, isPlayer, move)
  local battler = isPlayer and self.battle.player or self.battle.enemy
  local mon = battler and battler.mon
  if not mon then
    return
  end
  local maxHP = tonumber(mon.stats and mon.stats.hp) or 80
  local dmg = math.max(4, math.floor((tonumber(move and move.power) or 40) * 0.12))
  mon.hp = math.max(1, (tonumber(mon.hp) or maxHP) - dmg)
  battler.shownHP = mon.hp
  if mon.hp <= 1 then
    Stage.note(self, (isPlayer and self.playerName or self.enemyName) .. " is worn out")
    if self.auto then
      self.wait = 1.1
      self.queue = { { wait = 0.2, rebuild = true } }
    else
      self.queue = {}
      Stage.note(self, "round stopped")
    end
  end
end

function Stage.playAttack(self, side, move)
  move = move or Stage.pickMove(self, side == "player")
  local kind = "attack"
  Stage.cue(self, side, kind, {
    category = move.category,
    moveId = move.id,
    moveType = move.type,
  })
  return move
end

function Stage.playReact(self, side, pick, incoming)
  if pick == "commit" then
    return
  end
  if pick == "fire" then
    Stage.playFire(self, side, true)
    return
  end
  if pick == "charge" then
    Stage.playCharge(self, side, true)
    return
  end
  Stage.cue(self, side, pick, {
    category = incoming and incoming.category,
    moveId = incoming and incoming.id,
    moveType = incoming and incoming.type,
  })
  if pick == "dodge" then
    Stage.chip(self, side, "DODGE")
    Stage.note(self, side .. " DODGE")
  elseif pick == "brace" then
    Stage.chip(self, side, "BRACE")
  elseif pick == "cover" then
    Stage.chip(self, side, "COVER")
  end
end

function Stage.recordExchange(self, attacker, move, defender, pick)
  local script = self.script
  if not script then
    return
  end
  script:addAttack(attacker, move)
  local kind = (pick == "commit" or not pick) and "hit" or pick
  script:addReact(defender, kind)
  script.playIndex = #script.beats
  script.cursor = #script.beats
  Stage.note(self, "rec  " .. Script.label(script.beats[#script.beats - 1])
    .. "  /  " .. Script.label(script.beats[#script.beats]))
end

function Stage.roundPath(self)
  local root = self.mods and self.mods.root
  if type(root) ~= "string" or root == "" then
    return "field/lab/last_round.txt"
  end
  return root .. "/field/lab/last_round.txt"
end

function Stage.dumpRound(self)
  local script = self.script
  if not script or #script.beats < 1 then
    Stage.note(self, "round log is empty")
    return ""
  end
  local body = script:dump()
  print("[lab] --- round ---")
  print(body)
  print("[lab] --- /round  " .. #script.beats .. " beats ---")
  local path = Stage.roundPath(self)
  local f = io.open(path, "w")
  if f then
    f:write("# " .. tostring(self.playerName) .. " vs " .. tostring(self.enemyName) .. "\n")
    f:write(body)
    f:write("\n")
    f:close()
    Stage.note(self, "saved " .. #script.beats .. " beats  (L to reload)")
  else
    Stage.note(self, "logged " .. #script.beats .. " beats")
  end
  return body
end

function Stage.loadRound(self, path)
  path = path or Stage.roundPath(self)
  local f = io.open(path, "r")
  if not f then
    Stage.note(self, "no saved round")
    return 0
  end
  local body = f:read("*a")
  f:close()
  local n = self.script:load(body)
  Stage.note(self, "loaded " .. n .. " beats")
  return n
end

function Stage.setAuto(self, on)
  self.auto = on == true
  self.hold = false
  self.queue = {}
  if self.auto then
    self.wait = 0.35
    Stage.note(self, "AI recording into the round list")
  else
    self.wait = 0
    Stage.dumpRound(self)
  end
end

function Stage.autoBeat(self)
  local attacker = self.nextAttacker or "player"
  self.nextAttacker = attacker == "player" and "enemy" or "player"
  local defender = attacker == "player" and "enemy" or "player"
  local move = Stage.pickMove(self, attacker == "player")
  self.lastMove = move
  self.lastAttacker = attacker
  Stage.playAttack(self, attacker, move)
  local pick = Stage.pickReact(self, defender == "player", move)
  if pick == "commit" then
    Stage.cue(self, defender, "hit", {})
    Stage.hurt(self, defender == "player", move)
  else
    Stage.playReact(self, defender, pick, move)
  end
  Stage.recordExchange(self, attacker, move, defender, pick)
  local RD = self.mods.RD
  if RD and type(RD.addFocus) == "function" then
    RD.addFocus(self.battle, true, 10)
    RD.addFocus(self.battle, false, 10)
  end
  self.wait = 1.65
end

function Stage.tick(self, dt)
  dt = tonumber(dt) or (1 / 60)
  if dt > 1 / 15 then
    dt = 1 / 15
  end
  self.battle.frame = (self.battle.frame or 1) + 1
  self.session._now = (self.session._now or 1) + dt
  local player, enemy = self.session.playerMon, self.session.enemyMon
  if player and type(player.tick) == "function" then
    player:tick(dt, enemy and enemy.px, enemy and enemy.py)
  end
  if enemy and type(enemy.tick) == "function" then
    enemy:tick(dt, player and player.px, player and player.py)
  end
  local Projectiles = self.mods.Projectiles
  if Projectiles and type(Projectiles.tick) == "function" then
    Projectiles.tick(self.session, dt)
  end
  local Cues = self.mods.Cues
  local Grid = self.mods.Grid
  if Cues and type(Cues.pumpCurrent) == "function" then
    pcall(Cues.pumpCurrent, self.session, self.battle, Grid)
  end
  if Cues and type(Cues.pumpFollowUpAnims) == "function" then
    pcall(Cues.pumpFollowUpAnims, self.session, self.battle, Grid)
  end
  if Cues and type(Cues.tickReturns) == "function" then
    pcall(Cues.tickReturns, self.session, Grid)
  end
  if Cues and type(Cues.flushHeldHit) == "function" then
    pcall(Cues.flushHeldHit, self.session, self.battle)
  end
  if Cues and type(Cues.syncSemiInvuln) == "function" then
    pcall(Cues.syncSemiInvuln, self.session, Grid)
  end
  if Cues and type(Cues.syncReactHold) == "function" then
    pcall(Cues.syncReactHold, self.session, self.battle)
  end
  if self.hold then
    return
  end
  if self.wait > 0 then
    self.wait = self.wait - dt
    if self.wait > 0 then
      return
    end
  end
  if self.queue[1] then
    Stage.pumpQueue(self)
    return
  end
  if self.auto then
    Stage.autoBeat(self)
  end
end

function Stage.drawWorld(self)
  Stage.centerCamera(self)
  local cam = self.game.overworld.camera
  local camX, camY = cam.x or 0, cam.y or 0
  if self.session.floor and type(self.session.floor.draw) == "function" then
    self.session.floor:draw(camX, camY)
  end
  if self.mods.Debug and type(self.mods.Debug.draw) == "function" then
    self.mods.Debug.draw(self.session, self.battle)
  end
  for i = 1, #(self.session.covers or {}) do
    local prop = self.session.covers[i]
    if prop and type(prop.draw) == "function" then
      prop:draw(camX, camY)
    end
  end
  local ents = self.game.overworld.entities or {}
  for i = 1, #ents do
    local ent = ents[i]
    if ent and type(ent.draw) == "function" then
      ent:draw(camX, camY)
    end
  end
  local Projectiles = self.mods.Projectiles
  if Projectiles and type(Projectiles.draw) == "function" then
    Projectiles.draw(self.session, camX, camY)
  end
  if Projectiles and type(Projectiles.drawStatusAuras) == "function" then
    Projectiles.drawStatusAuras(self.session, self.battle, camX, camY)
  end
  if self.mods.UI and type(self.mods.UI.drawReactChips) == "function" then
    self.mods.UI.drawReactChips(self.battle, camX, camY)
  end
end

return Stage
