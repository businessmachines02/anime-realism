-- Field battle — the fight's life on the map, from start to teardown.
--
-- Intercept.lua steals the "go to a battle screen" call. This file is
-- what happens after that: put two Pokémon on the grass, keep the camera
-- on them, bob and walk every frame (even under menus), swap them when
-- someone faints, then put the overworld back the way it was.
--
-- One session per BattleState (weak table: if the battle dies, we go with
-- it). States, in order:
--
--   Idle        nothing running
--   Armed       fight flagged; not on the map yet
--   Staging     placing trainers, mons, cover, camera
--   Live        the fight you can see
--   Finishing   tearing down; restore camera / strip FIELD actors
--
-- Two clocks, because menus freeze BattleState:update:
--   Logic     turns, damage, "play this cue"          (engine queue)
--   Present   bob, walk frames, FX, camera            (every frame)
-- tickPresent is the present clock. Call it from anywhere; it dedupes
-- so idle bob does not freeze under the move diamond.
--
-- Where to look (scroll to the matching banner):
--
--   EXIT RESTORE       put zoom / voxel / camera / entities back
--   FOLLOWERS          hide the walking buddy so it is not in the fight
--   WORLD OVERLAY      floor + cover + clash letterbox (projectiles live in UI)
--   SESSION            get / active / liveBattle — find the live fight
--   CAMERA             pan, mouse peek, keep action on screen
--   BEGIN              survey the pad, spawn the cast, go Live
--   MONS               send-out, switch, faint when HP hits 0, capture
--   IDLE / TRAINERS    roam in place; trainers step off the pad
--   TURNS / CUES       turn start cleanup; fan a beat out to cues.lua
--   TICK               every-frame present + logic work
--   FINISH             restore entities, camera, voxel, followers
--
-- Voxel warning: never replace overworld.entities and never insert nil-sprite
-- floor/cover/projectiles into it. Dramatic Shape calls ent:pose() then
-- sprite.def; a nil sprite crashes Voxel3D.beginScene and wedges 3D.
--
-- This file does not decide how a Tackle looks. That is field/fx/cues.lua.

local Coords = require("coords")

local Lifecycle = {}
Lifecycle.CAMERA_UI_BIAS_Y = 18
-- Soft pan toward the live fight (higher = snappier). Nudges / off-screen catch-up use a faster rate.
Lifecycle.CAMERA_PAN_RATE = 4.2
Lifecycle.CAMERA_PAN_NUDGE_RATE = 10
Lifecycle.CAMERA_PAN_CLASH_RATE = 9.5
Lifecycle.CAMERA_PAN_CATCHUP_RATE = 7.2
Lifecycle.CAMERA_PAN_SNAP = 1.25
-- Follow battlers this far past the surveyed envelope (wander / knockback slack).
Lifecycle.CAMERA_CLAMP_PAD = 32
Lifecycle.CAMERA_EDGE_MARGIN_X = 22
Lifecycle.CAMERA_EDGE_MARGIN_TOP = 16
Lifecycle.CAMERA_EDGE_MARGIN_BOTTOM = 54
-- Mouse look-around: while the cursor is moving, peek around the fight.
-- When it rests, the auto camera eases back in. Desktop may look from
-- anywhere in the window. While the on-screen pad is up, only the inner
-- viewport may peek so d-pad / A / B taps do not pan the camera (#49).
-- CAMERA_LOOK_SPAN is the peek in world pixels at the classic 160×144 view;
-- focusCamera scales it (and the envelope clamp) to the live worldViewSize
-- so a phone-sized Dramaless pass pans as far as desktop.
Lifecycle.CAMERA_LOOK_HOLD = 0.45
Lifecycle.CAMERA_LOOK_RATE = 11
Lifecycle.CAMERA_LOOK_SPAN = 56
Lifecycle.CAMERA_LOOK_CLAMP_PAD = 64
Lifecycle.CAMERA_LOOK_MOVE_PX = 3
Lifecycle.CAMERA_LOOK_ZONE_INSET = 0.22

-- Weak keys: sessions die with their BattleState without explicit cleanup races.
local sessionByBattle = setmetatable({}, { __mode = "k" })

Lifecycle.STATE = {
    Idle = "Idle",
    Armed = "Armed",
    Staging = "Staging",
    Live = "Live",
    Finishing = "Finishing",
}

-- Love 11.5 LuaJIT on ARM64 macOS can SIGSEGV inside lj_alloc unlink
-- (NaN-boxed pointer as a free-list fd). FIELD's per-frame pose/walk
-- is a hot JIT path; interpreter-only avoids that class of abort.
local function fieldJit(enable)
    if type(jit) ~= "table" then
        return
    end
    if enable then
        if type(jit.on) == "function" then
            pcall(jit.on)
        end
    else
        if type(jit.off) == "function" then
            pcall(jit.off)
        end
        if type(jit.flush) == "function" then
            pcall(jit.flush)
        end
    end
end

local function now()
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return 0
end

local function rand(...)
    local random = (love and love.math and love.math.random) or math.random
    return random(...)
end

-- ---------------------------------------------------------------------------
-- EXIT RESTORE — zoom, voxel, camera, entity list.
-- Used at the end of a fight (and if begin() has to abort). Camera eases
-- back onto the player instead of snapping; voxel must not bounce through OFF.
-- ---------------------------------------------------------------------------
local function restoreZoom(session)
    if session.zoomSaved == nil then
        return
    end
    local ok, Zoom = pcall(require, "src.render.Zoom")
    if ok and type(Zoom) == "table" then
        Zoom.offset = session.zoomSaved
    end
    session.zoomSaved = nil
end

local function restoreVoxel(session)
    -- Re-apply the pre-battle rung only if something changed it. Never bounce
    -- through OFF: potato_voxel/DS treat that as "hold flat until meshes are
    -- ready", which is how FIELD exits got stuck on 2D tiles.
    if session.voxelSaved == nil then
        return
    end
    local saved = session.voxelSaved
    session.voxelSaved = nil
    local ok, Pipelines = pcall(require, "src.render.Pipelines")
    if not (ok and Pipelines and type(Pipelines.setLevel) == "function") then
        return
    end
    if type(Pipelines.level) == "function" then
        local okLevel, level = pcall(Pipelines.level, "voxel")
        if okLevel and level == saved then
            return
        end
    end
    pcall(Pipelines.setLevel, "voxel", saved)
end

--- Soft-pan the overworld camera back onto the player after FIELD ends.
--- Uses OverworldState.cameraPan (offset on top of follow) so the next
--- overworld update keeps framing continuous while we ease the offset to zero.
local function restoreCamera(session, battle, overworld)
    if not (overworld and overworld.camera and overworld.player) then
        return
    end
    local viewW, viewH = 160, 144
    local game = battle and battle.game
    local renderer = game and game.renderer
    if session and session._viewW then
        viewW, viewH = session._viewW, session._viewH or viewH
    elseif renderer and type(renderer.worldViewSize) == "function" then
        local ok, gotW, gotH = pcall(renderer.worldViewSize, renderer)
        if ok and type(gotW) == "number" then
            viewW, viewH = gotW, gotH or viewH
        end
    end
    local camera = overworld.camera
    local beforeX, beforeY = camera.x, camera.y
    if type(camera.follow) == "function" then
        pcall(camera.follow, camera, overworld.player.px, overworld.player.py, viewW, viewH)
    else
        camera.x = (overworld.player.px or 0) - viewW / 2
        camera.y = (overworld.player.py or 0) - viewH / 2
    end
    local offsetX = (type(beforeX) == "number") and (beforeX - camera.x) or 0
    local offsetY = (type(beforeY) == "number") and (beforeY - camera.y) or 0
    local snap = Lifecycle.CAMERA_PAN_SNAP
    if (offsetX * offsetX + offsetY * offsetY) <= snap * snap then
        overworld.cameraPan = nil
        return
    end
    -- Keep the current framing this frame; overworld update will follow+offset.
    camera.x = beforeX
    camera.y = beforeY
    overworld.cameraPan = {
        ox = offsetX,
        oy = offsetY,
        arFieldReturn = true,
    }
end

--- Ease battle-exit cameraPan toward zero at CAMERA_PAN_RATE.
function Lifecycle.tickReturnCamera(overworld, dt)
    if not overworld then
        return false
    end
    local pan = overworld.cameraPan
    if not (pan and pan.arFieldReturn) then
        return false
    end
    local useDt = (type(dt) == "number" and dt > 0) and dt or (1 / 60)
    if useDt > 1 / 15 then
        useDt = 1 / 15
    end
    local offsetX, offsetY = pan.ox or 0, pan.oy or 0
    local snap = Lifecycle.CAMERA_PAN_SNAP
    if (offsetX * offsetX + offsetY * offsetY) <= snap * snap then
        overworld.cameraPan = nil
        return false
    end
    local alpha = 1 - math.exp(-useDt * Lifecycle.CAMERA_PAN_RATE)
    offsetX = offsetX + (0 - offsetX) * alpha
    offsetY = offsetY + (0 - offsetY) * alpha
    if (offsetX * offsetX + offsetY * offsetY) <= snap * snap then
        overworld.cameraPan = nil
        return false
    end
    pan.ox, pan.oy = offsetX, offsetY
    -- Scripted pans use frames; keep ours outside that linear ramp.
    pan.frames = nil
    pan.onDone = nil
    return true
end

local function restoreWorldEntities(session, overworld)
    -- Same table identity the voxel pass already holds. Strip FIELD actors
    -- (mons / leftover cover) so the live map cast is what it was before.
    local saved = session.savedEntities
    if type(saved) ~= "table" then
        saved = overworld.entities
    end
    if type(saved) ~= "table" then
        return
    end
    for i = #saved, 1, -1 do
        local ent = saved[i]
        if ent and (ent._fbv or ent._arFieldBattler or ent._arFieldCover) then
            table.remove(saved, i)
        end
    end
    overworld.entities = saved
end

local function isFieldActor(ent)
    return ent ~= nil and (ent._fbv or ent._arFieldBattler or ent._arFieldCover)
end

-- ---------------------------------------------------------------------------
-- FOLLOWERS — the Pokémon walking behind you on the overworld.
-- Dramatic Shape still poses hidden entities, so we take them out of the
-- live list for the fight and put them back on finish.
-- ---------------------------------------------------------------------------
--- Party follower / trailer walking behind the player. Must leave the live
--- entity list (DS pose() ignores `hidden`) while the FIELD battler is out.
function Lifecycle.isOverworldFollower(ent, player, foe)
    if not ent or ent == player or ent == foe or isFieldActor(ent) then
        return false
    end
    if ent._arFieldParked == true then
        return true
    end
    if ent.isFollower == true or ent.follower == true or ent.wildsFollower == true
        or ent.pikachuFollower == true or ent.pokepcTrailer == true
        or ent.usingFollowerSprite == true then
        return true
    end
    if ent.id == "pikachu" or ent.id == "follower" then
        return true
    end
    if ent._pokepcFollowerSpecies ~= nil or ent._wildsFollowerSpecies ~= nil then
        return true
    end
    local def = ent.sprite and ent.sprite.def
    local spriteId = def and def.id
    return spriteId == "SPRITE_PIKACHU" or spriteId == "SPRITE_POKEPC_MON"
        or spriteId == "SPRITE_PLAYER_POKEMON"
end

local function alreadyParked(session, ent)
    local parked = session.parkedFollowers
    if type(parked) ~= "table" then
        return false
    end
    for i = 1, #parked do
        if parked[i].ent == ent then
            return true
        end
    end
    return false
end

function Lifecycle.parkOverworldFollowers(session, overworld)
    if not (session and overworld and type(overworld.entities) == "table") then
        return
    end
    session.parkedFollowers = session.parkedFollowers or {}
    local entities = overworld.entities
    local player = overworld.player
    local foe = session.foe
    local leadFollower = nil
    local okFollowerMod, PikachuFollower = pcall(require, "src.world.PikachuFollower")
    if okFollowerMod and PikachuFollower and type(PikachuFollower.current) == "function" then
        local okCurrent, npc = pcall(PikachuFollower.current, overworld)
        if okCurrent then
            leadFollower = npc
        end
    end
    for i = #entities, 1, -1 do
        local ent = entities[i]
        -- Never park the live FIELD cast. PikachuFollower.current() can
        -- return the wild/enemy sprite once our send-out is on the map.
        if ent and ent ~= player and ent ~= foe
            and ent ~= session.playerMon and ent ~= session.enemyMon
            and not isFieldActor(ent)
            and (ent == leadFollower or Lifecycle.isOverworldFollower(ent, player, foe)) then
            ent._arFieldParked = true
            ent.hidden = true
            ent.frozen = true
            ent.moving = false
            if not alreadyParked(session, ent) then
                table.insert(session.parkedFollowers, 1, { ent = ent, index = i })
            end
            table.remove(entities, i)
        end
    end
end

function Lifecycle.restoreOverworldFollowers(session, overworld)
    local parked = session and session.parkedFollowers
    if type(parked) ~= "table" or not (overworld and type(overworld.entities) == "table") then
        return
    end
    table.sort(parked, function(a, b)
        return (a.index or 1) < (b.index or 1)
    end)
    local entities = overworld.entities
    for i = 1, #parked do
        local ent = parked[i].ent
        if ent then
            ent._arFieldParked = nil
            ent.hidden = false
            ent.frozen = false
            local found = false
            for j = 1, #entities do
                if entities[j] == ent then
                    found = true
                    break
                end
            end
            if not found then
                local index = parked[i].index or (#entities + 1)
                if index < 1 then
                    index = 1
                elseif index > #entities + 1 then
                    index = #entities + 1
                end
                table.insert(entities, index, ent)
            end
        end
    end
    session.parkedFollowers = nil
end

-- ---------------------------------------------------------------------------
-- WORLD OVERLAY — grass/cover on the map canvas.
-- Projectiles and HP bars paint from the battle UI overlay, not here,
-- so they survive 3D/world draw overrides. Also stores bubble anchors.
-- ---------------------------------------------------------------------------
--- Floor / cover on the world canvas. Projectiles + HP paint from UI.draw on
--- the battle overlay (world→UI mapped) so they survive 3D/world overrides.
--- Also records UI-space anchors on each battler for speech bubbles.
function Lifecycle.drawWorldOverlay(battle)
    local session = Lifecycle.get(battle)
    if not (session and session.live) then
        return
    end
    local overworld = battle and battle.game and battle.game.overworld
    local camera = overworld and overworld.camera
    if not camera then
        return
    end
    local cameraX, cameraY = camera.x or 0, camera.y or 0
    if session.floor and type(session.floor.draw) == "function" then
        session.floor:draw(cameraX, cameraY)
    end
    local covers = session.covers
    if type(covers) == "table" then
        for i = 1, #covers do
            local prop = covers[i]
            if prop and not prop.hidden and type(prop.draw) == "function" then
                prop:draw(cameraX, cameraY)
            end
        end
    end
    -- Stash UI-canvas anchors for speech bubbles (battle overlay is 160×144).
    local deps = session._deps
    local renderer = battle.game and battle.game.renderer
    local Coords = deps and deps.Coords
    local function stampAnchor(ent)
        if not ent or ent.hidden or ent._removed then
            return
        end
        local lift = ent._fieldBarLift or 10
        local worldX = (ent.px or 0) - cameraX + 8
        local worldY = (ent.py or 0) - cameraY - lift
        ent._fieldWorldX, ent._fieldWorldY = worldX, worldY
        if Coords and type(Coords.worldViewToUi) == "function" then
            local uiX, uiY = Coords.worldViewToUi(worldX, worldY, renderer)
            ent._fieldScreenX, ent._fieldScreenY = uiX, uiY
        else
            ent._fieldScreenX, ent._fieldScreenY = worldX, worldY
        end
    end
    stampAnchor(session.playerMon)
    stampAnchor(session.enemyMon)
    stampAnchor(session.foe)
    -- Battlers that were kept off overworld.entities (no voxel-safe sprite.def) still
    -- need a 2D stamp so send-out is visible without aborting the 3D pass.
    local function onOwList(ent)
        local ents = overworld and overworld.entities
        if not (ent and type(ents) == "table") then
            return false
        end
        for i = 1, #ents do
            if ents[i] == ent then
                return true
            end
        end
        return false
    end
    local function drawBattler(ent)
        if not ent or ent.hidden or ent._removed then
            return
        end
        if onOwList(ent) then
            return
        end
        if type(ent.draw) == "function" then
            ent:draw(cameraX, cameraY)
        end
    end
    drawBattler(session.playerMon)
    drawBattler(session.enemyMon)
    if deps and deps.Spectators and type(deps.Spectators.draw) == "function" then
        pcall(deps.Spectators.draw, session, cameraX, cameraY, renderer)
    end
    Lifecycle.drawClashLetterbox(session, battle)
end

--- Soft edge vignette for COUNTER clash. Spans the world canvas (survey zoom
--- can be wider than the 160×144 UI overlay) instead of a hard cinema crop.
function Lifecycle.clashLetterboxSize(viewW, viewH)
    viewW = math.max(1, tonumber(viewW) or 160)
    viewH = math.max(1, tonumber(viewH) or 144)
    local edge = math.max(32, math.floor(viewH * (40 / 144) + 0.5))
    return viewW, viewH, edge, 0.48
end

function Lifecycle.drawClashLetterbox(session, battle)
    if not (session and (session._clashPunch or (session._clashSlowT or 0) > 0)) then
        return
    end
    local g = love and love.graphics
    if not g then
        return
    end
    local k = 1
    local dur = session._clashSlowDur
    if dur and dur > 0 and session._clashSlowT then
        k = math.min(1, session._clashSlowT / dur + 0.15)
    end
    local viewW, viewH
    local canvas = g.getCanvas and g.getCanvas()
    if canvas and canvas.getDimensions then
        local ok, gotW, gotH = pcall(canvas.getDimensions, canvas)
        if ok and type(gotW) == "number" and gotW > 0 then
            viewW, viewH = gotW, gotH or viewH
        end
    end
    if not viewW then
        if type(g.getDimensions) == "function" then
            local ok, gotW, gotH = pcall(g.getDimensions)
            if ok and type(gotW) == "number" and gotW > 0 then
                viewW, viewH = gotW, gotH
            end
        end
    end
    if not viewW then
        viewW, viewH = 160, 144
        if session._viewW then
            viewW, viewH = session._viewW, session._viewH or viewH
        else
            local renderer = battle and battle.game and battle.game.renderer
            if renderer and type(renderer.worldViewSize) == "function" then
                local ok, gotW, gotH = pcall(renderer.worldViewSize, renderer)
                if ok and type(gotW) == "number" then
                    viewW, viewH = gotW, gotH or viewH
                end
            end
        end
    end
    local w, h, _, alpha = Lifecycle.clashLetterboxSize(viewW, viewH)
    local bandH = math.max(5, math.floor(h * 5 / 144 + 0.5))
    local bandW = math.max(4, math.floor(w * 4 / 160 + 0.5))
    g.push("all")
    -- World draw may still be in camera space; the fade must span the canvas.
    if type(g.origin) == "function" then
        g.origin()
    end
    for i = 1, 8 do
        local a = (alpha - (i - 1) * (alpha / 9.5)) * k
        local y0, x0 = (i - 1) * bandH, (i - 1) * bandW
        g.setColor(0.02, 0.03, 0.08, a)
        g.rectangle("fill", 0, y0, w, bandH)
        g.rectangle("fill", 0, h - y0 - bandH, w, bandH)
        g.rectangle("fill", x0, 0, bandW, h)
        g.rectangle("fill", w - x0 - bandW, 0, bandW, h)
    end
    for i = 0, 11 do
        local y = (3 + i * 2.4) * (h / 144)
        local a = (0.20 - i * 0.012) * k
        local streakH = math.max(1.6, 1.6 * h / 144)
        g.setColor(0.04, 0.05, 0.10, a)
        g.rectangle("fill", 0, y, w, streakH)
        g.rectangle("fill", 0, h - y - streakH, w, streakH)
    end
    for i = 0, 8 do
        local x = (2 + i * 2.2) * (w / 160)
        local a = (0.16 - i * 0.012) * k
        local streakW = math.max(1.5, 1.5 * w / 160)
        g.setColor(0.04, 0.05, 0.10, a)
        g.rectangle("fill", x, 0, streakW, h)
        g.rectangle("fill", w - x - streakW, 0, streakW, h)
    end
    g.pop()
end

-- ---------------------------------------------------------------------------
-- SESSION — find the live fight for this BattleState.
-- sessionByBattle is weak-keyed: if the battle is garbage-collected, we go too.
-- ---------------------------------------------------------------------------
function Lifecycle.get(battle)
    return battle and sessionByBattle[battle] or nil
end

function Lifecycle.active(battle)
    local session = Lifecycle.get(battle)
    return session ~= nil and session.live == true and session.state == Lifecycle.STATE.Live
end

-- ---------------------------------------------------------------------------
-- CAMERA — keep the fight on screen.
-- Soft-pan between the two mons, peek when the mouse moves, clamp to the
-- surveyed envelope, restore onto the player when FIELD ends.
-- ---------------------------------------------------------------------------
local function cameraViewSize(session, game)
    local viewW, viewH = 160, 144
    local renderer = game and game.renderer
    if renderer and type(renderer.worldViewSize) == "function" then
        local ok, gotW, gotH = pcall(renderer.worldViewSize, renderer)
        if ok and type(gotW) == "number" then
            viewW, viewH = gotW, gotH or viewH
        end
    elseif session and session._viewW then
        viewW, viewH = session._viewW, session._viewH or viewH
    end
    if session then
        session._viewW, session._viewH = viewW, viewH
    end
    return viewW, viewH
end

--- Peek distance in world pixels for this view. 56px at 160×144; scales up
--- so a wide mobile world pass pans the same fraction of the screen.
function Lifecycle.mouseLookSpan(viewW, viewH)
    local base = Lifecycle.CAMERA_LOOK_SPAN or 56
    viewW = tonumber(viewW) or 160
    viewH = tonumber(viewH) or 144
    if viewW < 1 then
        viewW = 160
    end
    if viewH < 1 then
        viewH = 144
    end
    return base * (viewW / 160), base * (viewH / 144)
end

--- Invert Camera:follow / fallback top-left so we can seed a pan from the live view.
local function readCameraFocus(camera, viewW, viewH)
    if not camera or type(camera.x) ~= "number" or type(camera.y) ~= "number" then
        return nil, nil
    end
    if type(camera.follow) == "function" then
        -- Camera:follow(px, py) uses player-centric offsets (see src/render/Camera.lua).
        return camera.x + (viewW / 2 - 16), camera.y + (viewH / 2 - 8)
    end
    return camera.x + viewW / 2, camera.y + viewH / 2
end

local function applyCameraFocus(camera, focusX, focusY, viewW, viewH)
    if type(camera.follow) == "function" then
        camera:follow(focusX, focusY, viewW, viewH)
    else
        camera.x = focusX - viewW / 2
        camera.y = focusY - viewH / 2
    end
end

local function envelopeRectPx(session, pad)
    local rect = session and ((session.envelope and session.envelope.gridRect)
        or (session.grid and session.grid.worldRect))
    if not rect then
        return nil
    end
    local cell = Coords.CELL
    pad = pad or Lifecycle.CAMERA_CLAMP_PAD or 32
    return {
        minX = rect.minX * cell + cell / 2 - pad,
        maxX = rect.maxX * cell + cell / 2 + pad,
        minY = rect.minY * cell + cell / 2 - pad,
        maxY = rect.maxY * cell + cell / 2 + pad,
        midX = ((rect.minX + rect.maxX) / 2) * cell + cell / 2,
        midY = ((rect.minY + rect.maxY) / 2) * cell + cell / 2,
    }
end

local function clamp(v, lo, hi)
    if lo > hi then
        return (lo + hi) * 0.5
    end
    if v < lo then
        return lo
    end
    if v > hi then
        return hi
    end
    return v
end

local function battlerFocusPx(ent, grid)
    if not ent or ent.hidden or ent._removed then
        return nil, nil
    end
    -- basePx follows pad lerp without idle bob, so the camera does not pulse.
    if type(ent.basePx) == "number" and type(ent.basePy) == "number" then
        return ent.basePx + 8, ent.basePy + 8
    end
    if grid and ent.padU ~= nil then
        return Coords.padCenterPx(grid, ent.padU, ent.padV)
    end
    if type(ent.px) == "number" then
        return ent.px + 8, (ent.py or 0) + 8
    end
    return nil, nil
end

--- Live fight focus: midpoint of visible battlers, clamped to the battle
--- envelope so knockback / cover / wander cannot drag the camera off-map.
local function liveActionFocus(session)
    local grid = session and session.grid
    local envelopePx = envelopeRectPx(session)
    local function envelopeMid()
        if envelopePx then
            return envelopePx.midX, envelopePx.midY
        end
        return (session.midX or 0) * 16 + 8, (session.midY or 0) * 16 + 8
    end

    -- Intro: only the foe is staged. Hold the envelope so a cornered wild
    -- does not yank the camera off the pad before the player appears.
    if session.awaitPlayerMon then
        return envelopeMid()
    end

    local battlerPoints = {}
    local function add(ent)
        local x, y = battlerFocusPx(ent, grid)
        if x then
            battlerPoints[#battlerPoints + 1] = { x = x, y = y }
        end
    end
    add(session.playerMon)
    add(session.enemyMon)
    if #battlerPoints == 0 then
        return envelopeMid()
    end
    local sumX, sumY = 0, 0
    for i = 1, #battlerPoints do
        sumX = sumX + battlerPoints[i].x
        sumY = sumY + battlerPoints[i].y
    end
    local focusX, focusY = sumX / #battlerPoints, sumY / #battlerPoints
    if envelopePx then
        focusX = clamp(focusX, envelopePx.minX, envelopePx.maxX)
        focusY = clamp(focusY, envelopePx.minY, envelopePx.maxY)
    end
    return focusX, focusY, battlerPoints
end

local function viewTopLeft(camera, focusX, focusY, viewW, viewH)
    if camera and type(camera.x) == "number" and type(camera.y) == "number" then
        return camera.x, camera.y
    end
    if camera and type(camera.follow) == "function" then
        return focusX - (viewW / 2 - 16), focusY - (viewH / 2 - 8)
    end
    return focusX - viewW / 2, focusY - viewH / 2
end

local function actionLeavesView(battlerPoints, camera, focusX, focusY, viewW, viewH)
    if not battlerPoints or #battlerPoints == 0 then
        return false
    end
    local cameraX, cameraY = viewTopLeft(camera, focusX, focusY, viewW, viewH)
    local marginX = Lifecycle.CAMERA_EDGE_MARGIN_X or 22
    local marginTop = Lifecycle.CAMERA_EDGE_MARGIN_TOP or 16
    local marginBottom = Lifecycle.CAMERA_EDGE_MARGIN_BOTTOM or 54
    for i = 1, #battlerPoints do
        local screenX = battlerPoints[i].x - cameraX
        local screenY = battlerPoints[i].y - cameraY
        if screenX < marginX or screenX > viewW - marginX
            or screenY < marginTop or screenY > viewH - marginBottom then
            return true
        end
    end
    return false
end

local function windowSize()
    if love and love.graphics then
        if type(love.graphics.getDimensions) == "function" then
            local ok, w, h = pcall(love.graphics.getDimensions)
            if ok and type(w) == "number" and w > 0 then
                return w, h or w
            end
        end
        if type(love.graphics.getWidth) == "function" then
            local w = love.graphics.getWidth()
            local h = (type(love.graphics.getHeight) == "function")
                and love.graphics.getHeight() or w
            if type(w) == "number" and w > 0 then
                return w, h
            end
        end
    end
    return nil, nil
end

--- Cursor as a -1..1 offset from the window center (right/down positive).
function Lifecycle.mouseLookFromWindow(mouseX, mouseY, screenW, screenH)
    screenW = tonumber(screenW) or 0
    screenH = tonumber(screenH) or 0
    if screenW < 1 or screenH < 1 then
        return 0, 0
    end
    local lookX = ((tonumber(mouseX) or 0) / screenW) * 2 - 1
    local lookY = ((tonumber(mouseY) or 0) / screenH) * 2 - 1
    return clamp(lookX, -1, 1), clamp(lookY, -1, 1)
end

--- Inner viewport used for look-around while the on-screen pad is visible.
function Lifecycle.mouseLookInZone(mouseX, mouseY, screenW, screenH)
    screenW = tonumber(screenW) or 0
    screenH = tonumber(screenH) or 0
    if screenW < 1 or screenH < 1 then
        return false
    end
    local inset = Lifecycle.CAMERA_LOOK_ZONE_INSET or 0.22
    if inset < 0 then
        inset = 0
    elseif inset > 0.45 then
        inset = 0.45
    end
    local fracX = (tonumber(mouseX) or 0) / screenW
    local fracY = (tonumber(mouseY) or 0) / screenH
    return fracX >= inset and fracX <= (1 - inset) and fracY >= inset and fracY <= (1 - inset)
end

local touchControlsCache

local function getTouchControls()
    if touchControlsCache ~= nil then
        return touchControlsCache ~= false and touchControlsCache or nil
    end
    local ok, TouchControls = pcall(require, "src.core.TouchControls")
    if ok and type(TouchControls) == "table" then
        touchControlsCache = TouchControls
        return TouchControls
    end
    touchControlsCache = false
    return nil
end

function Lifecycle.touchOverlayVisible()
    local TouchControls = getTouchControls()
    if not (TouchControls and type(TouchControls.visible) == "function") then
        return false
    end
    local ok, vis = pcall(TouchControls.visible, TouchControls)
    return ok and vis == true
end

function Lifecycle.touchControlAt(mouseX, mouseY)
    local TouchControls = getTouchControls()
    if not TouchControls then
        return false
    end
    if type(TouchControls.visible) == "function" then
        local okVisible, vis = pcall(TouchControls.visible, TouchControls)
        if not (okVisible and vis == true) then
            return false
        end
    end
    -- A finger already claimed by the overlay must not pan, even if the
    -- sampled point has drifted a few pixels off the glyph.
    if TouchControls.dpadTouch ~= nil then
        return true
    end
    if type(TouchControls.held) == "table" and next(TouchControls.held) ~= nil then
        return true
    end
    if type(TouchControls.hitTest) ~= "function" then
        return false
    end
    local ok, hit = pcall(TouchControls.hitTest, TouchControls, tonumber(mouseX) or 0, tonumber(mouseY) or 0)
    return ok and hit ~= nil
end

--- Desktop: any window point. Touch overlay: inner zone, never on a pad hit.
function Lifecycle.mouseLookAllowed(mouseX, mouseY, screenW, screenH, opts)
    opts = opts or {}
    if opts.touchHit == true or Lifecycle.touchControlAt(mouseX, mouseY) then
        return false
    end
    local constrained = opts.touchConstrained
    if constrained == nil then
        constrained = Lifecycle.touchOverlayVisible()
    end
    if not constrained then
        return true
    end
    return Lifecycle.mouseLookInZone(mouseX, mouseY, screenW, screenH)
end

--- Tests / input hook: hold a look offset until the idle timer elapses.
function Lifecycle.noteMouseLook(session, lookX, lookY, hold)
    if not session then
        return
    end
    session.mouseLookX = clamp(tonumber(lookX) or 0, -1, 1)
    session.mouseLookY = clamp(tonumber(lookY) or 0, -1, 1)
    session.mouseLookT = hold or Lifecycle.CAMERA_LOOK_HOLD or 0.45
end

--- Arm look-around from a window-space move. Returns true when a peek starts.
function Lifecycle.tryMouseLook(session, mouseX, mouseY, screenW, screenH, dx, dy, opts)
    if not session then
        return false
    end
    local minMovePx = Lifecycle.CAMERA_LOOK_MOVE_PX or 3
    dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
    if (dx * dx + dy * dy) < (minMovePx * minMovePx) then
        return false
    end
    screenW, screenH = tonumber(screenW) or 0, tonumber(screenH) or 0
    if screenW < 1 or screenH < 1 then
        screenW, screenH = windowSize()
    end
    if not screenW then
        return false
    end
    if not Lifecycle.mouseLookAllowed(mouseX, mouseY, screenW, screenH, opts) then
        return false
    end
    local lookX, lookY = Lifecycle.mouseLookFromWindow(mouseX, mouseY, screenW, screenH)
    Lifecycle.noteMouseLook(session, lookX, lookY)
    return true
end

local function sampleMouseLook(session, dt)
    if not session then
        return
    end
    dt = (type(dt) == "number" and dt > 0) and dt or 0
    session.mouseLookT = math.max(0, (session.mouseLookT or 0) - dt)
    if session._mouseLookInjected then
        return
    end
    if not (love and love.mouse and type(love.mouse.getPosition) == "function") then
        return
    end
    if love.window and type(love.window.hasMouseFocus) == "function" then
        local ok, focused = pcall(love.window.hasMouseFocus)
        if ok and focused == false then
            return
        end
    end
    local ok, mouseX, mouseY = pcall(love.mouse.getPosition)
    if not (ok and type(mouseX) == "number") then
        return
    end
    local screenW, screenH = windowSize()
    if not screenW then
        return
    end
    local lastX, lastY = session._mouseWinX, session._mouseWinY
    session._mouseWinX, session._mouseWinY = mouseX, mouseY
    if lastX == nil then
        -- First sample: remember pose, do not look (cursor may sit in a corner).
        return
    end
    Lifecycle.tryMouseLook(session, mouseX, mouseY, screenW, screenH, mouseX - lastX, mouseY - lastY)
end

function Lifecycle.focusCamera(battle, dt)
    local session = Lifecycle.get(battle)
    if not (session and session.live) then
        return
    end
    local game = battle and battle.game
    local overworld = game and game.overworld
    local camera = overworld and overworld.camera
    if not camera then
        return
    end

    local useDt = (type(dt) == "number" and dt > 0) and dt or (1 / 60)
    if useDt > 1 / 15 then
        useDt = 1 / 15
    end
    sampleMouseLook(session, useDt)

    local focusX, focusY, battlerPoints = liveActionFocus(session)
    local looking = (session.mouseLookT or 0) > 0
    local nudgeT = session.cameraNudgeT or 0
    if not looking and nudgeT > 0 and session.cameraNudgeX and session.cameraNudgeY then
        local punch = session._clashPunch == true
        -- Full lock on the clash while the hold is up; ease out in the last 0.4s.
        local hold = punch and 0.45 or 0.35
        local blend = math.min(1, nudgeT / hold) * (punch and 1 or 0.55)
        focusX = focusX * (1 - blend) + session.cameraNudgeX * blend
        focusY = focusY * (1 - blend) + session.cameraNudgeY * blend
        if punch then
            -- Drop the menu bias so the pair fills the frame.
            session._clashUiBias = 4
        end
    else
        session._clashUiBias = nil
    end

    local viewW, viewH = cameraViewSize(session, game)

    -- Battle menus occupy the lower screen. Aim the camera below the action so
    -- the compact pad appears in the unobstructed upper viewport.
    local targetX = focusX
    local targetY = focusY + (session._clashUiBias
        or session.cameraUiBiasY or Lifecycle.CAMERA_UI_BIAS_Y)
    if looking then
        local spanX, spanY = Lifecycle.mouseLookSpan(viewW, viewH)
        targetX = targetX + (session.mouseLookX or 0) * spanX
        targetY = targetY + (session.mouseLookY or 0) * spanY
        -- Envelope clamp must grow with the view or a phone-sized world pass
        -- eats the peek and the 3D camera looks locked while UI chips slide.
        local pad = Lifecycle.CAMERA_LOOK_CLAMP_PAD or 64
        local envelopePx = envelopeRectPx(session, math.max(pad, spanX, spanY))
        if envelopePx then
            targetX = clamp(targetX, envelopePx.minX, envelopePx.maxX)
            targetY = clamp(targetY, envelopePx.minY, envelopePx.maxY + (session.cameraUiBiasY or Lifecycle.CAMERA_UI_BIAS_Y))
        end
    end
    session.cameraTargetX, session.cameraTargetY = targetX, targetY
    session.focusX, session.focusY = focusX, focusY

    local currentX, currentY = session.cameraFocusX, session.cameraFocusY
    if currentX == nil or currentY == nil then
        currentX, currentY = readCameraFocus(camera, viewW, viewH)
        if currentX == nil or currentY == nil then
            -- No live camera pose to ease from (tests / first bind): settle immediately.
            currentX, currentY = targetX, targetY
        end
    end

    local dx, dy = targetX - currentX, targetY - currentY
    local dist2 = dx * dx + dy * dy
    local snap = Lifecycle.CAMERA_PAN_SNAP
    local offscreen = actionLeavesView(battlerPoints, camera, currentX, currentY, viewW, viewH)
    if dist2 <= snap * snap then
        currentX, currentY = targetX, targetY
    else
        local rate = Lifecycle.CAMERA_PAN_RATE
        if looking then
            rate = Lifecycle.CAMERA_LOOK_RATE
        elseif session._clashPunch then
            rate = Lifecycle.CAMERA_PAN_CLASH_RATE
        elseif nudgeT > 0 then
            rate = Lifecycle.CAMERA_PAN_NUDGE_RATE
        elseif offscreen then
            rate = Lifecycle.CAMERA_PAN_CATCHUP_RATE
        end
        local alpha = 1 - math.exp(-useDt * rate)
        currentX = currentX + dx * alpha
        currentY = currentY + dy * alpha
        if (targetX - currentX) * (targetX - currentX) + (targetY - currentY) * (targetY - currentY) <= snap * snap then
            currentX, currentY = targetX, targetY
        end
    end

    applyCameraFocus(camera, currentX, currentY, viewW, viewH)
    session.cameraFocusX, session.cameraFocusY = currentX, currentY
    -- Pixel bump on the live camera, not Zoom.offset (that recrops voxel).
    if (session._camShakeT or 0) > 0 then
        local dur = session._camShakeDur or 0.10
        session._camShakeT = session._camShakeT - useDt
        local u = 0
        if dur > 0 then
            u = math.max(0, session._camShakeT / dur)
        end
        if session._camShakeT <= 0 then
            session._camShakeT = nil
            session._camShakeDur = nil
            session._camShakeAmp = nil
        else
            local amp = (session._camShakeAmp or 1.6) * u
            local r = (love and love.math and love.math.random) or math.random
            local ox = math.floor((r() * 2 - 1) * amp + 0.5)
            local oy = math.floor((r() * 2 - 1) * amp * 0.6 + 0.5)
            camera.x = (camera.x or 0) + ox
            camera.y = (camera.y or 0) + oy
        end
    end
end

function Lifecycle.nudgeCamera(battle, side, seconds)
    local session = Lifecycle.get(battle)
    if not session then
        return
    end
    local ent = (side == "player") and session.playerMon or session.enemyMon
    if not ent then
        return
    end
    local grid = session.grid
    if grid and ent.padU ~= nil then
        session.cameraNudgeX, session.cameraNudgeY = Coords.padCenterPx(grid, ent.padU, ent.padV)
    else
        session.cameraNudgeX = (ent.basePx or ent.px or session.focusX or 0) + 8
        session.cameraNudgeY = (ent.basePy or ent.py or session.focusY or 0) + 8
    end
    session.cameraNudgeT = seconds or 0.4
end

function Lifecycle.monScreen(battle, side, Anims)
    local session = Lifecycle.get(battle)
    if Anims then
        return Anims.monScreen(session, battle, side)
    end
    return nil, nil
end

function Lifecycle.animTransform(battle, Anims)
    return Anims.transform(Lifecycle.get(battle), battle)
end

function Lifecycle.animShift(battle, Anims)
    return Anims.shift(Lifecycle.get(battle), battle)
end

function Lifecycle.cacheAnimTransform(battle, Anims)
    Anims.cache(Lifecycle.get(battle), battle)
end

function Lifecycle.animTransformCached(battle, Anims)
    return Anims.cached(Lifecycle.get(battle), battle)
end

local function leadPickerOpen(battle)
    local stack = battle and battle.game and battle.game.stack
    if not (stack and type(stack.top) == "function") then
        return false
    end
    local top = stack:top()
    if not top or top == battle then
        return false
    end
    if top.battle ~= nil and top.battle ~= battle then
        return false
    end
    if top.forceSwitch then
        return true
    end
    local id = tostring(top.id or top.screenId or "")
    if id == "PartyMenu" or id == "Gen2PartyMenu" then
        return top.forceSwitch == true or top.battle == battle
    end
    return false
end

local function combatReadyForPlayerReveal(battle)
    if not battle then
        return false
    end
    if battle.sendingOut or battle._arFieldRevealPlayer then
        return true
    end
    if battle.turn and battle.turn > 0 then
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- BEGIN — put the fight on the map.
-- Survey walkable cells, build the pad grid, spawn trainers/mons/cover,
-- snapshot voxel/zoom, park followers, then go Live.
-- ---------------------------------------------------------------------------
function Lifecycle.begin(battle, mod, deps)
    -- Stage a FIELD session onto the live overworld: survey walkable cells,
    -- build grid/cast/arena props, snapshot voxel so free-roam restores cleanly.
    if not battle then
        return false
    end
    if Lifecycle.active(battle) then
        return true
    end
    local Layout = deps.Layout
    local Sprites = deps.Sprites
    local Arena = deps.Arena
    local Survey = deps.Survey
    local Grid = deps.Grid
    local Cast = deps.Cast

    Lifecycle.finish(battle, deps)

    local game = battle.game
    local overworld = game and game.overworld
    local player = overworld and overworld.player
    if not player then
        return false
    end

    local reactiveDefense = deps and deps.ReactiveDefense

    local foe = Layout.findFoeTrainer(overworld, battle)
    local foeCellX, foeCellY
    if foe then
        foeCellX, foeCellY = foe.cellX or 0, foe.cellY or 0
    else
        foeCellX, foeCellY = Layout.wildAnchor(player)
    end

    -- plan out the positional elements of the battle field
    local playerCellX, playerCellY = player.cellX or 0, player.cellY or 0
    local plan = Layout.plan(playerCellX, playerCellY, foeCellX, foeCellY)
    plan.hasFoeTrainer = foe ~= nil

    -- survey the positional elements
    local envelope = nil
    if Survey and type(Survey.build) == "function" then
        local okSurvey, result = pcall(Survey.build, overworld.map, plan, {
            entityPools = { overworld.entities or {}, overworld.npcs or {}, overworld.npcPool or {} },
            player = player,
            foe = foe,
        })
        if okSurvey then
            envelope = result
        end
    end

    -- generate the field battle
    local layout = nil
    if Arena and type(Arena.generate) == "function" then
        local okGen, result = pcall(Arena.generate, battle, plan, nil, envelope)
        if okGen then
            layout = result
        end
    end

    local coverSlots = layout and layout.coverSlots or nil
    local grid = Grid.build(layout, plan)

    local session = {
        state = Lifecycle.STATE.Staging,
        live = true,
        started = now(),
        playerPose = Layout.copyPose(player),
        foe = foe,
        foePose = Layout.copyPose(foe),
        savedEntities = {},
        playerMon = nil,
        enemyMon = nil,
        awaitPlayerMon = true,
        sawLeadPicker = false,
        plan = plan,
        grid = grid,
        _mod = mod,
        _deps = deps,
        _battle = battle,
        midX = plan.midX,
        midY = plan.midY,
        arenaEdits = layout,
        arena = layout,
        envelope = envelope,
        coverSlots = coverSlots,
        coverKind = layout and layout.coverKind or nil,
        coverScene = layout and layout.coverScene or nil,
        ReactiveDefense = reactiveDefense,
        closeTheGap = true,
    }
    if mod and mod.options and type(mod.options.get) == "function" then
        session.closeTheGap = mod.options:get("close_the_gap") ~= false
    end
    if reactiveDefense then
        battle._arReactiveDefense = reactiveDefense
    end
    -- Keep the live draw-list table identity for the whole fight. Dramatic
    -- Shape's voxel pass reads this same table every frame; replacing it, or
    -- stuffing nil-sprite floor/cover into it, throws inside Voxel3D.beginScene
    -- and leaves GL wedged after the battle (hotkey 8 cannot recover).
    session.savedEntities = overworld.entities or {}
    Lifecycle.parkOverworldFollowers(session, overworld)

    player.frozen = true
    player.inputLocked = true
    player.wanders = false
    player.moving = false
    local function parkTrainer(ent, homeKey, face, occId)
        if not ent then
            return
        end
        ent.frozen = true
        ent.wanders = false
        ent.moving = false
        ent._arFieldTrainerId = occId
        local home = grid.home and grid.home[homeKey]
        if home then
            local worldX, worldY = Coords.padToWorld(grid, home.u, home.v)
            local pixelX, pixelY = Coords.padToPx(grid, home.u, home.v)
            ent.cellX, ent.cellY = worldX, worldY
            ent.px, ent.py = pixelX, pixelY
            ent.padU, ent.padV = home.u, home.v
            Grid.occupy(grid, occId, home.u, home.v)
        end
        if face then
            ent.facing = face
        end
    end
    parkTrainer(player, "playerTrainer", plan.playerFace, "ar_field_player_trainer")
    overworld.engaging = true
    overworld._arFieldEngaging = true

    if foe then
        parkTrainer(foe, "enemyTrainer", plan.foeFace, "ar_field_enemy_trainer")
    end

    -- Nearby bystander trainers: soft-walk to a free watching tile and face
    -- the duel. Restored in finish(). Safe no-op when deps.Spectators is nil.
    if deps.Spectators and type(deps.Spectators.begin) == "function" then
        pcall(deps.Spectators.begin, session, battle, deps)
    end
    if deps.Wildlife and type(deps.Wildlife.begin) == "function" then
        pcall(deps.Wildlife.begin, session, battle, deps)
    end

    -- now put the variable pieces on the board (trainer, mon, etc)
    Cast.stageEnemy(session, battle, mod, Sprites, Grid)

    -- Floor / cover are 2D stamps with no sprite. Draw them from
    -- Lifecycle.drawWorldOverlay — never through overworld.entities.
    session.floor = layout and Arena.floorEntity(layout) or nil
    session.covers = {}
    if layout and type(layout.overlay) == "table" then
        for i = 1, #layout.overlay do
            local prop = Arena.overlayEntity(layout.overlay[i])
            if prop then
                session.covers[#session.covers + 1] = prop
            end
        end
    end

    session.state = Lifecycle.STATE.Live
    sessionByBattle[battle] = session
    fieldJit(false)
    session._arJitOff = true
    if deps and deps.Log and type(deps.Log.note) == "function" then
        pcall(deps.Log.note, battle, "jit off")
    end
    Lifecycle.focusCamera(battle)

    battle._arAnimeField = true
    battle.isOpaque = false
    battle.letterboxWhite = false
    battle.BG_WORLD_DIM = 0
    battle.showPlayerBack = false
    -- TODO: Remove this once we have a proper enemy trainer
    battle.showEnemyTrainer = true
    if battle.introSlide and battle.introSlide > 0 then
        battle.introSlide = 0
    end

    if deps and deps.Audio and type(deps.Audio.enterField) == "function" then
        pcall(deps.Audio.enterField)
        session._arFieldAudio = true
    end

    return true
end

-- ---------------------------------------------------------------------------
-- MONS — send-out, switch, faint, capture.
-- The player's first mon waits until combat is actually ready (lead picker).
-- Faint sprites follow the painted HP bar hitting 0, not the "fainted!" line.
-- ---------------------------------------------------------------------------
function Lifecycle.stagePlayerMon(battle, mod, deps)
    local session = Lifecycle.get(battle)
    if not (session and session.live) then
        return nil
    end
    if session.playerMon and not session.playerMon._removed then
        session.awaitPlayerMon = false
        return session.playerMon
    end
    deps = deps or session._deps
    mod = mod or session._mod
    return deps.Cast.stagePlayer(session, battle, mod, deps.Sprites, deps.Grid)
end

function Lifecycle.tryRevealPlayerMon(battle)
    local session = Lifecycle.get(battle)
    if not (session and session.live and session.awaitPlayerMon) then
        return
    end
    if not (battle.player and battle.player.mon) then
        return
    end
    if leadPickerOpen(battle) then
        session.sawLeadPicker = true
        return
    end
    if session.sawLeadPicker then
        Lifecycle.stagePlayerMon(battle)
        return
    end
    if combatReadyForPlayerReveal(battle) then
        Lifecycle.stagePlayerMon(battle)
    end
end

local function speciesKey(value)
    return tostring(value or ""):upper():gsub("%s+", "_")
end

local function wantedSpecies(battler)
    local mon = battler and battler.mon
    if not mon then
        return ""
    end
    return speciesKey(mon.species or mon.id)
end

local function liveSpecies(ent)
    if not ent then
        return ""
    end
    return speciesKey(ent._spriteSpecies or ent.species)
end

local function samePokemon(ent, battler)
    -- Identity is the species stamped on the sprite at spawn, not battler.mon
    -- (that pointer is overwritten before battler_switched).
    local live = liveSpecies(ent)
    if live == "" then
        return false
    end
    local mon = battler and battler.mon
    if not mon then
        return false
    end
    if live == speciesKey(mon.species) then
        return true
    end
    if live == speciesKey(mon.id) then
        return true
    end
    if live == speciesKey(mon.name) then
        return true
    end
    local dex = tonumber(mon.dex)
    if dex and (live == tostring(dex) or live == string.format("%03d", dex)) then
        return true
    end
    return false
end

local function isArriving(ent)
    return ent and ent.anim == "sendout"
end

--- Player call-in must never fire the red recall laser at the live foe.
local function holdRecallForArrival(session, battle, side)
    if side ~= "enemy" then
        return false
    end
    if session.awaitPlayerMon then
        return true
    end
    if (session._playerSendLockT or 0) > 0 then
        return true
    end
    if battle and battle.sendingOut then
        return true
    end
    if isArriving(session.playerMon) then
        return true
    end
    return false
end

local function normalizeSwitchSide(side)
    if type(side) ~= "string" then
        return nil
    end
    side = side:lower()
    if side == "player" or side == "ally" then
        return "player"
    end
    if side == "enemy" or side == "foe" or side == "opponent" then
        return "enemy"
    end
    return nil
end

local function battlerFainted(battler)
    local mon = battler and battler.mon
    local hp = tonumber(battler and battler.shownHP) or tonumber(mon and mon.hp)
    if hp ~= nil and hp <= 0 then
        return true
    end
    local status = mon and tostring(mon.status or ""):upper()
    return status == "FNT" or status == "FAINT"
end

local function shownBarHP(battler)
    return tonumber(battler and battler.shownHP)
end

--- Play faint/recall when the painted HP bar empties. Engine `battle.fainted`
--- is usually queued with the "fainted!" line, after `shownHP` is already 0.
function Lifecycle.watchHpFaint(battle, deps)
    local session = Lifecycle.get(battle)
    if not (session and session.live and battle) then
        return
    end
    deps = deps or session._deps
    if not (deps and deps.Cues and type(deps.Cues.apply) == "function") then
        return
    end
    session._barHP = session._barHP or {}
    for _, side in ipairs({ "player", "enemy" }) do
        local battler = (side == "player") and battle.player or battle.enemy
        local ent = (side == "player") and session.playerMon or session.enemyMon
        local hp = shownBarHP(battler)
        local prev = session._barHP[side]
        if hp ~= nil then
            session._barHP[side] = hp
        end
        if hp ~= nil and ent and not ent._removed
            and prev ~= nil and prev > 0 and hp <= 0 then
            Lifecycle.react(battle, side, "faint")
        end
    end
end

--- `battle.fainted` fallback. Skip while the bar is still draining so the
--- laser is not the dialogue beat; skip if watchHpFaint already played it.
function Lifecycle.onFainted(battle, side)
    if not battle or (side ~= "player" and side ~= "enemy") then
        return
    end
    local battler = (side == "player") and battle.player or battle.enemy
    local shown = shownBarHP(battler)
    if shown ~= nil and shown > 0 then
        return
    end
    if Lifecycle.shouldSkipEventReact(battle, side, "faint") then
        return
    end
    return Lifecycle.react(battle, side, "faint")
end

--- Restage a side after a switch. `onlySide` limits the pass so a player faint
--- / send-out cannot recall the foe (and vice versa).
function Lifecycle.syncMons(battle, mod, deps, onlySide)
    local session = Lifecycle.get(battle)
    if not (session and session.live) then
        return
    end
    deps = deps or session._deps
    mod = mod or session._mod
    local Cast = deps.Cast
    local Grid = deps.Grid
    local Sprites = deps.Sprites

    local function refresh(side, battler)
        -- Player call-in: never recall/replace the live foe.
        if holdRecallForArrival(session, battle, side) then
            return
        end
        if side == "player" and session.awaitPlayerMon then
            if leadPickerOpen(battle) then
                session.sawLeadPicker = true
                return
            end
            if session.sawLeadPicker or combatReadyForPlayerReveal(battle)
                or battle._arFieldRevealPlayer then
                Lifecycle.stagePlayerMon(battle, mod, deps)
            end
            return
        end
        local current = (side == "player") and session.playerMon or session.enemyMon
        -- Pointer landed on the other battler: stage ours, never recall them.
        if current and current._arFieldSide and current._arFieldSide ~= side then
            if side == "player" then
                session.playerMon = nil
            else
                session.enemyMon = nil
            end
            current = nil
        end
        local wanted = wantedSpecies(battler)
        -- No living replacement yet (party menu / fainted slot). Never recall
        -- the other battler, and never send out a corpse.
        if wanted == "" or battlerFainted(battler) then
            return
        end
        if not current or current._removed then
            local ent = Cast.replace(session, battle, mod, Sprites, Grid, side, battler)
            if ent and type(ent.play) == "function" then
                ent:play("sendout")
            end
            return
        end
        if samePokemon(current, battler) then
            return
        end
        session.pendingSwitch = session.pendingSwitch or {}
        local pending = session.pendingSwitch[side]
        if pending and pending.species == wanted then
            return
        end
        session.pendingSwitch[side] = {
            battler = battler,
            species = wanted,
            delay = 0.50,
        }
        -- Faint already fired the recall laser + shrink. Don't replay it
        -- when the replacement species lands on battle.player/enemy.
        local alreadyExiting = current._fainting or current._faintDone
            or current._recallDone
            or current.anim == "recall"
            or current.anim == "faint"
        if not alreadyExiting then
            local Projectiles = deps.Projectiles
            if Projectiles and type(Projectiles.recallBeam) == "function" then
                pcall(Projectiles.recallBeam, session, side, { target = current })
            end
            if type(current.play) == "function" then
                current:play("recall")
            end
        end
    end

    onlySide = normalizeSwitchSide(onlySide)
    -- First player send-out: never restage/recall the live foe. A nil switch
    -- side used to mismatch-recall the opponent as soon as we spawned.
    if (session.awaitPlayerMon or (battle and battle.sendingOut)
            or isArriving(session.playerMon))
        and onlySide ~= "enemy" then
        refresh("player", battle.player)
        return
    end
    if onlySide == "player" then
        refresh("player", battle.player)
    elseif onlySide == "enemy" then
        refresh("enemy", battle.enemy)
    else
        -- Unknown switch side: only restage a battler whose live sprite no
        -- longer matches. A matching opponent must never be recalled.
        local function mismatch(side, battler)
            if holdRecallForArrival(session, battle, side) then
                return false
            end
            local current = (side == "player") and session.playerMon or session.enemyMon
            local wanted = wantedSpecies(battler)
            if wanted == "" or battlerFainted(battler) then
                return false
            end
            if not current or current._removed then
                return true
            end
            if current._arFieldSide and current._arFieldSide ~= side then
                return true
            end
            return not samePokemon(current, battler)
        end
        if mismatch("player", battle.player) then
            refresh("player", battle.player)
        end
        if mismatch("enemy", battle.enemy) then
            refresh("enemy", battle.enemy)
        end
    end
end

local function tickSwitches(session, battle, deps, dt)
    local pending = session and session.pendingSwitch
    if type(pending) ~= "table" then
        return
    end
    for _, side in ipairs({ "player", "enemy" }) do
        local item = pending[side]
        if item and holdRecallForArrival(session, battle, side) then
            -- Player call-in must not finish a queued foe recall.
            pending[side] = nil
            item = nil
        end
        if item then
            local current = (side == "player") and session.playerMon or session.enemyMon
            -- Wait out the recall shrink (and detach) before staging the next mon.
            local recalling = current and (current.anim == "recall")
                and not current._recallDone
            item.delay = (item.delay or 0) - dt
            if not recalling and item.delay <= 0 then
                pending[side] = nil
                if current and not current._arFieldDetached then
                    deps.Cast.detachScene(session, current)
                end
                local ent = deps.Cast.replace(session, battle, session._mod,
                    deps.Sprites, deps.Grid, side, item.battler)
                if ent and type(ent.play) == "function" then
                    ent:play("sendout")
                end
            end
        end
    end
end

function Lifecycle.capture(battle, event)
    local session = Lifecycle.get(battle)
    if not (session and session.live and session.enemyMon) then
        return false
    end
    local Projectiles = session._deps and session._deps.Projectiles
    local function resolve()
        local enemy = session.enemyMon
        if not (enemy and type(enemy.play) == "function") then
            return
        end
        if event and event.caught then
            enemy:play("capture")
        else
            enemy:play("hit")
        end
    end
    if Projectiles and type(Projectiles.ball) == "function" then
        session.captureInFlight = true
        Projectiles.ball(session, {
            shakes = event and event.shakes,
            onDone = function()
                session.captureInFlight = nil
                resolve()
            end,
        })
    else
        resolve()
    end
    return true
end

function Lifecycle.despawnMon(battle, side)
    local session = Lifecycle.get(battle)
    if not session then
        return
    end
    local deps = session._deps
    deps.Cast.despawn(session, battle, deps.Grid, side)
end

-- ---------------------------------------------------------------------------
-- IDLE / TRAINERS — between moves, mons may roam a cell; trainers step
-- aside so they are not standing on the pad.
-- ---------------------------------------------------------------------------
local function tickIdleWander(session, Grid, ent, side, dt)
    if not ent or ent._removed or ent.hidden or ent._fainting then
        return
    end
    if ent._coverHeld or (ent.coverBlend or 0) > 0.15 then
        ent.wanderTx, ent.wanderTy = nil, nil
        return
    end
    local busy = ent.anim and ent.anim ~= "idle"
    if busy or ent._returnAt or ent._pendingCloseStrike or ent._withdrawAfterStrike then
        return
    end
    -- Still lerping to a cell target.
    local destX, destY = ent.targetPx, ent.targetPy
    if destX and destY then
        local dx = destX - (ent.basePx or 0)
        local dy = destY - (ent.basePy or 0)
        if (dx * dx + dy * dy) > 4 then
            return
        end
    end
    ent._wanderCD = (ent._wanderCD or (2.5 + rand() * 1.5)) - dt
    if ent._wanderCD > 0 then
        return
    end
    -- Often just hold the lane; only sometimes take a step.
    if rand() > 0.35 then
        ent._wanderCD = 2.8 + rand() * 2.4
        return
    end
    local foe = (side == "player") and session.enemyMon or session.playerMon
    if Grid.idleWander(session.grid, ent, side, foe) then
        ent._wanderCD = 3.2 + rand() * 2.8
    else
        ent._wanderCD = 2.0 + rand() * 1.5
    end
end



-- Trainer walk-step speed in world px/sec (comparable to the battler mons'
-- default steerBase speed of ~40-56).
local TRAINER_STEP_SPEED = 48

--- Reserve a pad cell and kick off a soft walk toward it. Player/NPC don't
--- consume targetPx/targetPy themselves, so we drive px/py ourselves via
--- stepTrainerClear below rather than routing through Player:update()/
--- NPC:update() (built for input-driven, collision-checked taps).
local function beginTrainerStep(session, Grid, trainer, nextU, nextV, deltaU, deltaV)
    local occId = trainer._arFieldTrainerId
    if not occId then
        return false
    end
    Grid.occupy(session.grid, occId, nextU, nextV)
    trainer.padU, trainer.padV = nextU, nextV
    local pixelX, pixelY = Coords.padToPx(session.grid, nextU, nextV)
    trainer._stepTX, trainer._stepTY = pixelX, pixelY
    local worldX, worldY = Coords.padDeltaToWorld(session.grid, deltaU, deltaV)
    if math.abs(worldX) >= math.abs(worldY) then
        trainer.facing = worldX >= 0 and "right" or "left"
    else
        trainer.facing = worldY >= 0 and "down" or "up"
    end
    trainer.moving = true
    return true
end

--- Per-frame lerp toward a pending trainer step. Call every tick for any
--- trainer that might have a step in flight (overworld.player, session.foe).
local function stepTrainerClear(session, trainer, dt)
    if not (trainer and trainer._stepTX and trainer._stepTY) then
        return
    end
    local pixelX, pixelY = trainer.px or 0, trainer.py or 0
    local dx = trainer._stepTX - pixelX
    local dy = trainer._stepTY - pixelY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1.5 then
        trainer.px, trainer.py = trainer._stepTX, trainer._stepTY
        if session.grid and trainer.padU ~= nil then
            trainer.cellX, trainer.cellY =
                Coords.padToWorld(session.grid, trainer.padU, trainer.padV)
        end
        trainer._stepTX, trainer._stepTY = nil, nil
        trainer.moving = false
        return
    end
    local step = math.min(dist, TRAINER_STEP_SPEED * (dt or 1 / 60))
    trainer.px = pixelX + dx / dist * step
    trainer.py = pixelY + dy / dist * step
end

-- When a battler shares / brushes a trainer cell, walk the trainer aside.
local function keepTrainerClear(session, Grid, trainer, mon)
    if not (session and session.grid and Grid and trainer and mon) then
        return
    end
    if mon._removed or mon.hidden or trainer._removed then
        return
    end
    if trainer._stepTX then
        return
    end
    local trainerU, trainerV = trainer.padU, trainer.padV
    local monU, monV = mon.padU, mon.padV
    if trainerU == nil or monU == nil then
        return
    end
    local dist = math.abs(trainerU - monU) + math.abs(trainerV - monV)
    if dist > 1 then
        return
    end
    if not trainer._arFieldTrainerId then
        return
    end
    local awayU, awayV = trainerU - monU, trainerV - monV
    local dirs = {
        { awayU, awayV },
        { 1,     0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
    }
    for i = 1, #dirs do
        local deltaU, deltaV = dirs[i][1], dirs[i][2]
        if not (deltaU == 0 and deltaV == 0) then
            if math.abs(deltaU) > 1 then deltaU = deltaU > 0 and 1 or -1 end
            if math.abs(deltaV) > 1 then deltaV = deltaV > 0 and 1 or -1 end
            local nextU, nextV = trainerU + deltaU, trainerV + deltaV
            if Grid.isFree(session.grid, nextU, nextV, trainer._arFieldTrainerId) then
                return beginTrainerStep(session, Grid, trainer, nextU, nextV, deltaU, deltaV)
            end
        end
    end
    return false
end





-- When a battler shares / brushes a trainer cell, step the trainer aside.
-- local function keepTrainerClear(session, Grid, trainer, mon)
--   if not (session and session.grid and Grid and trainer and mon) then
--     return
--   end
--   if mon._removed or mon.hidden or trainer._removed then
--     return
--   end
--   local tu, tv = trainer.padU, trainer.padV
--   local mu, mv = mon.padU, mon.padV
--   if tu == nil or mu == nil then
--     return
--   end
--   local dist = math.abs(tu - mu) + math.abs(tv - mv)
--   if dist > 1 then
--     return
--   end
--   local occId = trainer._arFieldTrainerId
--   if not occId then
--     return
--   end
--   local awayU, awayV = tu - mu, tv - mv
--   local dirs = {
--     { awayU, awayV },
--     { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
--     { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
--   }
--   for i = 1, #dirs do
--     local du, dv = dirs[i][1], dirs[i][2]
--     if not (du == 0 and dv == 0) then
--       if math.abs(du) > 1 then du = du > 0 and 1 or -1 end
--       if math.abs(dv) > 1 then dv = dv > 0 and 1 or -1 end
--       local nu, nv = tu + du, tv + dv
--       if Grid.isFree(session.grid, nu, nv, occId) then
--         Grid.occupy(session.grid, occId, nu, nv)
--         trainer.padU, trainer.padV = nu, nv
--         local wx, wy = Coords.padToWorld(session.grid, nu, nv)
--         local px, py = Coords.padToPx(session.grid, nu, nv)
--         trainer.cellX, trainer.cellY = wx, wy
--         trainer.px, trainer.py = px, py
--         if math.abs(du) >= math.abs(dv) then
--           trainer.facing = du >= 0 and "right" or "left"
--         else
--           trainer.facing = dv >= 0 and "down" or "up"
--         end
--         return true
--       end
--     end
--   end
--   return false
-- end

-- ---------------------------------------------------------------------------
-- TURNS / CUES — start-of-turn cleanup (drop leftover close-gap clocks)
-- and fan a named beat (attack, dodge, faint, …) out to cues.lua.
-- ---------------------------------------------------------------------------
function Lifecycle.onTurnEnded(battle)
    local session = Lifecycle.get(battle)
    if not (session and session.live and session.grid) then
        return
    end
    local Grid = session._deps.Grid
    local function maybeTrainer(ent, side)
        if not ent or ent._removed or ent._fainting then
            return
        end
        -- Occasional trainer check-in; keep rare so the pad doesn't thrash.
        if rand() <= 0.22 then
            local home = session.grid.home
                and ((side == "player") and session.grid.home.playerTrainer
                    or session.grid.home.enemyTrainer)
            if home and home.u ~= nil and Grid.setPad(session.grid, ent, home.u, home.v) then
                ent._returnAt = now() + 0.55
                ent._returnU = ent.homePadU
                ent._returnV = ent.homePadV
                ent._wanderCD = 3.5
            end
        end
    end
    maybeTrainer(session.playerMon, "player")
    maybeTrainer(session.enemyMon, "enemy")
end

function Lifecycle.onTurnStarted(battle)
    local session = Lifecycle.get(battle)
    if not (session and session.live and session.grid) then
        return
    end
    local Grid = session._deps.Grid
    local function repairInvalidCell(ent)
        if not ent or ent._removed or ent._fainting then
            return
        end
        -- Free-tile positions persist across turns. Only repair a cell that fell
        -- outside the surveyed envelope (for example after a compatibility swap).
        if ent.padU ~= nil and not Grid.inEnvelope(session.grid, ent.padU, ent.padV, ent)
            and ent.homePadU ~= nil then
            Grid.setPad(session.grid, ent, ent.homePadU, ent.homePadV)
            ent._wanderCD = 2.5
        end
    end
    repairInvalidCell(session.playerMon)
    repairInvalidCell(session.enemyMon)
    local Cues = session._deps and session._deps.Cues
    if Cues and type(Cues.settleOrphanCloseGap) == "function" then
        Cues.settleOrphanCloseGap(session, battle, Grid)
    end
    if Cues and type(Cues.flushHeldHit) == "function" then
        -- Apply any punch-stashed HP before this turn wipes the hold.
        pcall(Cues.flushHeldHit, session, battle)
    end
    local function keepSide(side)
        local ent = (side == "player") and session.playerMon or session.enemyMon
        if ent and ent._pendingCloseStrike then
            return true
        end
        local Cues = session._deps and session._deps.Cues
        return Cues and type(Cues.pendingMultiHitFollowUp) == "function"
            and Cues.pendingMultiHitFollowUp(session, battle, side)
    end
    local keepPlayer = keepSide("player")
    local keepEnemy = keepSide("enemy")
    if not keepPlayer and not keepEnemy then
        session._lastCueMoveId = nil
        session._arSkipEngineStrike = nil
        session._arFollowUpAnimKey = nil
        session._multiHitMoveId = nil
        session._multiHitSide = nil
    end
    if session._presentedMove then
        if not keepPlayer then
            session._presentedMove.player = nil
        end
        if not keepEnemy then
            session._presentedMove.enemy = nil
        end
    end
    if battle and not keepPlayer and not keepEnemy then
        battle._arCloseGapDamage = nil
        battle._arCloseGapApply = nil
        battle._arCloseGapResuming = nil
        battle._arAwaitingReact = nil
        battle._arWhiffCloseStrike = nil
    end
    if Cues and type(Cues.resetTurnSide) == "function" then
        Cues.resetTurnSide(session, "player", keepPlayer, Grid)
        Cues.resetTurnSide(session, "enemy", keepEnemy, Grid)
    else
        local function clearPending(ent, keep)
            if not ent or keep then
                return
            end
            ent._pendingCloseStrike = nil
            ent._closeStrikeDeadline = nil
            ent._closeStrikeWait = nil
            ent._closeStrikeArmedAt = nil
            ent._closeStruckMoveId = nil
            ent._struckMoves = nil
            ent._returnAt = nil
            ent._withdrawAfterStrike = nil
        end
        clearPending(session.playerMon, keepPlayer)
        clearPending(session.enemyMon, keepEnemy)
    end
end

function Lifecycle.react(battle, side, kind, opts)
    local session = Lifecycle.get(battle)
    if not (session and session.live) then
        return
    end
    opts = opts or {}
    if not opts.via then
        opts.via = "react"
    end
    -- Camera re-arms (REACT resume / BC tick) must not spawn another Surf/Psychic.
    if opts.presentationOnly then
        return
    end
    local deps = session._deps
    if deps.Cues.shouldSkipEvent(session, side, kind, opts) then
        return
    end
    deps.Cues.apply(session, side, kind, deps.Grid, Lifecycle.nudgeCamera, battle, opts)
end

function Lifecycle.shouldSkipEventReact(battle, side, kind, opts)
    local session = Lifecycle.get(battle)
    local deps = session and session._deps
    if not (session and deps) then
        return false
    end
    return deps.Cues.shouldSkipEvent(session, side, kind, opts)
end

local function wallNow(session)
    if session and session._now ~= nil then
        return session._now
    end
    if Lifecycle._now ~= nil then
        return Lifecycle._now
    end
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return nil
end

--- Find the live FIELD session + battle for this game (menus may sit on top).
function Lifecycle.liveBattle(game)
    local battle = nil
    for battleState, session in pairs(sessionByBattle) do
        if session and session.live then
            battle = battleState
            break
        end
    end
    if not battle then
        return nil, nil
    end
    local stack = game and game.stack
    local states = stack and stack.states
    if type(states) == "table" then
        for i = #states, 1, -1 do
            local stackState = states[i]
            local session = stackState and sessionByBattle[stackState]
            if session and session.live then
                battle = stackState
                break
            end
        end
    end
    return battle, sessionByBattle[battle]
end

--- Test hook: bind a live session without going through begin().
function Lifecycle._testBind(battle, session)
    if battle then
        sessionByBattle[battle] = session
    end
end

function Lifecycle._testUnbind(battle)
    if battle then
        sessionByBattle[battle] = nil
    end
end

-- ---------------------------------------------------------------------------
-- TICK — the every-frame clocks.
-- tickPresent: safe under menus; deduped by wall time so bob never freezes.
-- tick: wander, trainer clear, switches, lerp, projectiles, anim cache.
-- Always prefer tickPresent from input / overlay / letterbox hooks.
-- ---------------------------------------------------------------------------
--- Present-clock tick. Safe to call from input.step, BattleState:update,
--- render.letterbox, and battle.overlay — deduped so bob never freezes
--- under menus. Must NOT early-out on waitingUI / stack top / auto==false.
function Lifecycle.tickPresent(game, dt, deps)
    local overworld = game and game.overworld
    local battle, session = Lifecycle.liveBattle(game)

    local t = wallNow(session)
    local useDt = dt
    if t and session and session._lastPresentAt then
        useDt = t - session._lastPresentAt
    elseif t and Lifecycle._returnPanAt then
        useDt = t - Lifecycle._returnPanAt
    end
    if type(useDt) ~= "number" or useDt <= 0 then
        useDt = 1 / 60
    end
    if useDt > 1 / 15 then
        useDt = 1 / 15
    end

    -- Exit pan keeps running after the session is unbound.
    if overworld and overworld.cameraPan and overworld.cameraPan.arFieldReturn then
        local skip = t and Lifecycle._returnPanAt
            and (t - Lifecycle._returnPanAt) < 0.008
        if not skip then
            if t then
                Lifecycle._returnPanAt = t
            end
            Lifecycle.tickReturnCamera(overworld, useDt)
        end
    end

    if not (battle and session and session.live) then
        return false
    end
    deps = deps or session._deps

    -- Already advanced this display frame (another driver got here first).
    if t and session._lastPresentAt and (t - session._lastPresentAt) < 0.008 then
        return false
    end

    if t then
        session._lastPresentAt = t
    else
        session._lastPresentAt = (session._lastPresentAt or 0) + useDt
    end

    Lifecycle.tick(battle, useDt, deps)
    return true
end

function Lifecycle.tickActive(game, dt, deps)
    return Lifecycle.tickPresent(game, dt, deps)
end

function Lifecycle.tick(battle, dt, deps)
    -- Per-battle Live tick: idle wander, trainer clear, switches, cast lerp,
    -- projectile step, and anim-transform cache. Prefer tickPresent from
    -- drivers that need menu-safe bob advancement.
    local session = Lifecycle.get(battle)
    if not (session and session.live) then
        return
    end
    -- Present clock: never gate on waitingUI, stack top, or current.auto.
    deps = deps or session._deps
    dt = dt or (1 / 60)
    local wallDt = dt
    -- A few frozen frames on contact (not a cinematic). Clash slow-mo owns
    -- the clock when a counter is already hanging.
    if (session._hitStopT or 0) > 0 and (session._clashSlowT or 0) <= 0 then
        session._hitStopT = session._hitStopT - wallDt
        if session._hitStopT <= 0 then
            session._hitStopT = nil
        end
        dt = 0
    end
    -- Counter clash: deep slow-mo, then ease back. Camera punch uses wall
    -- time so the zoom snaps in while the mons hang in the hit.
    if (session._clashSlowT or 0) > 0 then
        local dur = session._clashSlowDur or 0.78
        session._clashSlowT = session._clashSlowT - wallDt
        if session._clashSlowT <= 0 then
            session._clashSlowT = nil
            session._clashSlowDur = nil
        else
            local u = session._clashSlowT / dur
            if u > 0.38 then
                dt = wallDt * 0.24
            else
                local k = 1 - (u / 0.38)
                dt = wallDt * (0.24 + 0.76 * k * k)
            end
        end
    end

    if session._playerSendLockT then
        session._playerSendLockT = session._playerSendLockT - dt
        if session._playerSendLockT <= 0 then
            session._playerSendLockT = nil
        end
    end

    local overworld = battle.game and battle.game.overworld
    if overworld then
        Lifecycle.parkOverworldFollowers(session, overworld)
    end

    if session.awaitPlayerMon then
        Lifecycle.tryRevealPlayerMon(battle)
    end

    -- Advance cast anims / detach finished recalls before switch staging so
    -- a hidden mon is off overworld.entities before the next pose pass.
    deps.Cast.tick(session, dt)

    tickSwitches(session, battle, deps, dt)
    if deps.Projectiles and type(deps.Projectiles.tick) == "function" then
        deps.Projectiles.tick(session, dt)
    end
    if deps.Projectiles and type(deps.Projectiles.syncCoverHold) == "function" then
        deps.Projectiles.syncCoverHold(session, battle, dt)
    end
    deps.Cues.pumpCurrent(session, battle, deps.Grid, Lifecycle.nudgeCamera)
    if type(deps.Cues.pumpFollowUpAnims) == "function" then
        deps.Cues.pumpFollowUpAnims(session, battle, deps.Grid, Lifecycle.nudgeCamera)
    end
    if deps.Callouts and type(deps.Callouts.tick) == "function" then
        deps.Callouts.tick(session, dt, battle)
    end
    Lifecycle.watchHpFaint(battle, deps)
    deps.Cues.tickReturns(session, deps.Grid)
    if type(deps.Cues.flushHeldHit) == "function" then
        pcall(deps.Cues.flushHeldHit, session, battle)
    end
    if type(deps.Cues.syncSemiInvuln) == "function" then
        deps.Cues.syncSemiInvuln(session, deps.Grid)
    end

    if session.cameraNudgeT and session.cameraNudgeT > 0 then
        local nudgeDt = session._clashPunch and wallDt or dt
        session.cameraNudgeT = math.max(0, session.cameraNudgeT - nudgeDt)
        if session.cameraNudgeT <= 0 then
            session._clashPunch = nil
        end
    end

    local playerMon, enemyMon = session.playerMon, session.enemyMon
    if playerMon and playerMon._faintDone then
        Lifecycle.despawnMon(battle, "player")
        playerMon = nil
    end
    if enemyMon and enemyMon._faintDone then
        Lifecycle.despawnMon(battle, "enemy")
        enemyMon = nil
    end

    tickIdleWander(session, deps.Grid, playerMon, "player", dt)
    tickIdleWander(session, deps.Grid, enemyMon, "enemy", dt)

    if overworld then
        keepTrainerClear(session, deps.Grid, overworld.player, playerMon)
        keepTrainerClear(session, deps.Grid, overworld.player, enemyMon)
        keepTrainerClear(session, deps.Grid, session.foe, enemyMon)
        keepTrainerClear(session, deps.Grid, session.foe, playerMon)
        stepTrainerClear(session, overworld.player, dt)
        stepTrainerClear(session, session.foe, dt)
    end

    if deps.Spectators and type(deps.Spectators.tick) == "function" then
        pcall(deps.Spectators.tick, session, dt, deps)
    end
    if deps.Wildlife and type(deps.Wildlife.tick) == "function" then
        pcall(deps.Wildlife.tick, session, dt, deps)
    end

    local moving = (playerMon and playerMon.targetPx and (
            math.abs((playerMon.basePx or 0) - playerMon.targetPx) > 1
            or math.abs((playerMon.basePy or 0) - (playerMon.targetPy or 0)) > 1))
        or (enemyMon and enemyMon.targetPx and (
            math.abs((enemyMon.basePx or 0) - enemyMon.targetPx) > 1
            or math.abs((enemyMon.basePy or 0) - (enemyMon.targetPy or 0)) > 1))
        or (playerMon and playerMon.anim and playerMon.anim ~= "idle")
        or (enemyMon and enemyMon.anim and enemyMon.anim ~= "idle")

    -- Soft-pan every present tick so intro / nudge easing stays continuous.
    -- Clash punch-in uses wall time so the camera dives while action hangs.
    Lifecycle.focusCamera(battle, (session._clashPunch or (session._camShakeT or 0) > 0) and wallDt or dt)

    session._faceAcc = (session._faceAcc or 0) + dt
    if session._faceAcc >= 0.15 then
        session._faceAcc = 0
        local grid = session.grid
        local function faceToward(ent, other)
            if not (ent and other) then
                return
            end
            -- Don't spin mid soft-step; re-aim once the lerp finishes.
            if ent._stepTX then
                return
            end
            local dx, dy
            if grid and ent.padU ~= nil and other.padU ~= nil then
                dx, dy = Coords.padDeltaToWorld(grid,
                    other.padU - ent.padU, other.padV - ent.padV)
            else
                dx = (other.cellX or 0) - (ent.cellX or 0)
                dy = (other.cellY or 0) - (ent.cellY or 0)
            end
            if math.abs(dx) >= math.abs(dy) then
                ent.facing = dx >= 0 and "right" or "left"
            else
                ent.facing = dy >= 0 and "down" or "up"
            end
        end
        local function faceCell(ent, worldX, worldY)
            if not ent or ent._stepTX or worldX == nil then
                return
            end
            local dx = (worldX or 0) - (ent.cellX or 0)
            local dy = (worldY or 0) - (ent.cellY or 0)
            if math.abs(dx) >= math.abs(dy) then
                ent.facing = dx >= 0 and "right" or "left"
            else
                ent.facing = dy >= 0 and "down" or "up"
            end
        end
        if playerMon and enemyMon and (not playerMon.anim or playerMon.anim == "idle") then
            faceToward(playerMon, enemyMon)
        end
        if enemyMon and playerMon and (not enemyMon.anim or enemyMon.anim == "idle") then
            faceToward(enemyMon, playerMon)
        end
        -- Engaged trainers watch the duel: prefer facing each other; in wild
        -- fights the player faces the foe mon / fight mid.
        if overworld then
            local playerTrainer = overworld.player
            local foeTrainer = session.foe
            if playerTrainer and foeTrainer then
                faceToward(playerTrainer, foeTrainer)
                faceToward(foeTrainer, playerTrainer)
            elseif playerTrainer then
                if enemyMon and not enemyMon._removed then
                    faceToward(playerTrainer, enemyMon)
                else
                    faceCell(playerTrainer, session.midX, session.midY)
                end
            end
        end
    end

    -- Do not restart play("attack") from battle.animPlaying. Cues own the
    -- one-shot FIELD swing (announce / move_used). REACT keeps the engine
    -- anim flag up after the clip returns to idle; retriggering here replayed
    -- the lunge when the HUD opened and again after the pick (issue #3).
    -- pumpCurrent above only arms the cue; close-the-gap physicals walk first
    -- and Cues.tickReturns plays the punch once the sprite is in reach.

    session._xformAcc = (session._xformAcc or 0) + dt
    if battle.animPlaying or moving or session._xformAcc >= 0.12 then
        session._xformAcc = 0
        deps.Anims.cache(session, battle)
    end
end

-- ---------------------------------------------------------------------------
-- FINISH — tear the fight off the map.
-- Restore poses, camera, voxel, followers, and the entity list. Never
-- bounce voxel through OFF or the exit gets stuck on 2D tiles.
-- ---------------------------------------------------------------------------
function Lifecycle.finish(battle, deps)
    -- Tear down Live cast, restore poses/camera, strip FIELD actors, unwedge voxel.
    local session = battle and sessionByBattle[battle]
    if not session then
        return
    end
    session.state = Lifecycle.STATE.Finishing
    session.live = false
    deps = deps or session._deps
    local Layout = deps and deps.Layout
    local Grid = deps and deps.Grid

    if deps and deps.Spectators and type(deps.Spectators.finish) == "function" then
        pcall(deps.Spectators.finish, session, deps)
    end
    if deps and deps.Wildlife and type(deps.Wildlife.finish) == "function" then
        pcall(deps.Wildlife.finish, session, deps)
    end

    if Grid and session.grid then
        Grid.clear(session.grid)
    end
    if deps and deps.Projectiles and type(deps.Projectiles.clear) == "function" then
        deps.Projectiles.clear(session)
    end
    if deps and deps.Callouts and type(deps.Callouts.finish) == "function" then
        pcall(deps.Callouts.finish, session)
    end
    if session._arFieldAudio and deps and deps.Audio
        and type(deps.Audio.leaveField) == "function" then
        pcall(deps.Audio.leaveField)
        session._arFieldAudio = nil
    end

    local game = battle.game
    local overworld = game and game.overworld
    if overworld then
        if session.playerPose and overworld.player and Layout then
            Layout.applyPose(overworld.player, session.playerPose)
            overworld.player.moving = false
        end
        if session.foe and session.foePose and Layout then
            Layout.applyPose(session.foe, session.foePose)
            session.foe.moving = false
        end
        overworld.engaging = nil
        overworld._arFieldEngaging = nil
        if overworld.player then
            overworld.player.inputLocked = false
        end
        restoreWorldEntities(session, overworld)
        Lifecycle.restoreOverworldFollowers(session, overworld)
        restoreCamera(session, battle, overworld)
    end

    -- FIELD never writes map tiles; no snapshot rewind.
    session.arenaEdits = nil
    session.mapSnap = nil

    restoreZoom(session)
    restoreVoxel(session)
    local Compat = deps and deps.Compat
    if Compat and type(Compat.releaseVoxelOverlay) == "function" then
        pcall(Compat.releaseVoxelOverlay, session._mod)
    end
    if battle then
        battle._arAnimeField = nil
    end
    if session._arJitOff then
        fieldJit(true)
        session._arJitOff = nil
        if deps and deps.Log and type(deps.Log.note) == "function" then
            pcall(deps.Log.note, battle, "jit on")
        end
    end
    sessionByBattle[battle] = nil
end

return Lifecycle
