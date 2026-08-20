-- Field battle — stage trainers + mons onto pad cells.
--
-- Pad (u, v) is truth; pixels come from Coords.padToPx. Homes come from
-- Layout's opening (one empty cell between mons, trainers one tile back). Cast.tick
-- lerps px/py toward the current pad each frame.

local Coords = require("coords")

local Cast = {}

Cast.STEP_SPEED = 56

local function clamp01(x)
    if x < 0 then
        return 0
    end
    if x > 1 then
        return 1
    end
    return x
end

local function speciesDef(ent)
    local battler = ent and ent._battleBattler
    if not battler then
        return nil
    end
    local mon = battler.mon
    local def = battler.def or (mon and (mon.pokemon or mon.def))
    if type(def) == "table" then
        return def
    end
    return nil
end

--- Pokedex weight in pounds. Gen 1/2 `dexEntry.weight` is tenths of a pound.
local function weightLbs(ent)
    if not ent then
        return nil
    end
    local hook = tonumber(ent._dexWeightLbs)
    if hook then
        return hook
    end
    local stats = ent._closeGapStats
    if type(stats) == "table" then
        if tonumber(stats.weightLbs) then
            return tonumber(stats.weightLbs)
        end
        if tonumber(stats.weightKg) then
            return tonumber(stats.weightKg) * 2.2046
        end
    end
    local def = speciesDef(ent)
    local dex = def and def.dexEntry
    if type(dex) ~= "table" then
        return nil
    end
    if tonumber(dex.weightKg) then
        return tonumber(dex.weightKg) * 2.2046
    end
    if tonumber(dex.weight) then
        return tonumber(dex.weight) / 10
    end
    return nil
end

local function gaitStats(ent)
    local stats = ent and ent._closeGapStats
    if type(stats) == "table" and (stats.hp or stats.defense or stats.def
        or stats.speed or stats.spe) then
        return stats
    end
    local def = speciesDef(ent)
    if def and type(def.baseStats) == "table" then
        return def.baseStats
    end
    local battler = ent and ent._battleBattler
    local mon = battler and battler.mon
    if battler and type(battler.stats) == "table" then
        return battler.stats
    end
    if mon and type(mon.stats) == "table" then
        return mon.stats
    end
    return nil
end

--- Wander / home-back px/s. Light mons zip; tanks lumber. Close-the-gap
--- dashes still use Cues.closeGapSpeed (speed + attack).
function Cast.idleStepSpeed(ent)
    local stats = gaitStats(ent)
    local lbs = weightLbs(ent)
    if not stats and not lbs then
        return Cast.STEP_SPEED
    end
    local hp, def, spe = 70, 70, 70
    if type(stats) == "table" then
        hp = tonumber(stats.hp) or hp
        def = tonumber(stats.defense or stats.def) or def
        spe = tonumber(stats.speed or stats.spe) or spe
    end
    -- Live battle stats are often ~2× base; keep the gait reading as species.
    if hp > 200 or def > 180 then
        hp = hp * 0.5
        def = def * 0.5
        spe = spe * 0.5
    end
    local bulkT = clamp01(((hp + def) * 0.5 - 45) / 90)
    local weightT
    if lbs then
        weightT = clamp01((lbs - 20) / 480)
    else
        local speedT = clamp01(spe / 120)
        weightT = clamp01(0.35 * bulkT + 0.65 * (1 - speedT))
    end
    local heaviness = 0.55 * weightT + 0.45 * bulkT
    local px = 78 - 46 * heaviness
    if px < 28 then
        px = 28
    elseif px > 80 then
        px = 80
    end
    return px
end

--- 0 = stay in the foe's face, 1 = glass cannon that wants space.
function Cast.keepAwayBias(ent)
    local stats = gaitStats(ent)
    if type(stats) ~= "table" then
        return 0
    end
    local spa = tonumber(stats.special or stats.spa or stats.spAtk
        or stats.spatk or stats.spAttack) or 70
    local def = tonumber(stats.defense or stats.def) or 70
    if spa > 140 or def > 160 then
        spa = spa * 0.45
        def = def * 0.45
    end
    local d = spa - def
    if d <= 10 then
        return 0
    end
    if d >= 80 then
        return 1
    end
    return (d - 10) / 70
end

local function worldBlockKeys(session, ignoreEnt)
    local keys = {}
    local function mark(e)
        if e and e ~= ignoreEnt and not e._removed and not e.hidden
            and e.cellX ~= nil then
            local wx = math.floor((e.cellX or 0) + 0.5)
            local wy = math.floor((e.cellY or 0) + 0.5)
            keys[tostring(wx) .. ":" .. tostring(wy)] = true
        end
    end
    mark(session.playerMon)
    mark(session.enemyMon)
    mark(session.foe)
    local battle = session and session._battle
    local ow = battle and battle.game and battle.game.overworld
    if ow then
        mark(ow.player)
        local ents = ow.entities
        if type(ents) == "table" then
            for i = 1, #ents do
                mark(ents[i])
            end
        end
    end
    return keys
end

-- Dramatic Shape's drawEntity does sprite:resolveImage() then Voxel3D.draw.
-- A dummy {def=...} with no resolveImage Lua-throws inside beginScene, and
-- a nil texture native-aborts Love with no error screen. Need def.image
-- (string) plus resolveImage — SpriteRenderer, or the missing-sheet stub.
local function voxelSafeSprite(ent)
    local sprite = ent and ent.sprite
    local def = sprite and sprite.def
    return sprite and type(sprite) == "table" and type(def) == "table"
        and type(def.image) == "string"
        and type(sprite.resolveImage) == "function"
end

local function ensureSpriteDef(ent)
    if not ent then
        return
    end
    if voxelSafeSprite(ent) then
        return
    end
    ent._poseSafe = ent._poseSafe or {
        def = {
            id = "ar_fbv_pose_" .. tostring(ent.id or "mon"),
            frames = 1,
            image = "ar_fbv_missing",
        },
        draw = function() end,
        resolveImage = function() return nil end,
    }
    if not ent.sprite then
        ent.sprite = ent._poseSafe
    elseif type(ent.sprite) == "table" then
        ent.sprite.def = ent.sprite.def or ent._poseSafe.def
    else
        ent.sprite = ent._poseSafe
    end
end

local function appendOw(ow, ent)
    if not (ow and type(ow.entities) == "table" and ent) then
        return
    end
    ensureSpriteDef(ent)
    if not voxelSafeSprite(ent) then
        -- 2D overlay still stamps these; voxel never should.
        return
    end
    local ents = ow.entities
    for i = 1, #ents do
        if ents[i] == ent then
            return
        end
    end
    ents[#ents + 1] = ent
end

local function bindHome(ent, plan, side, grid)
    if not ent then
        return
    end
    ent.stepSpeed = Cast.idleStepSpeed(ent)
    ent._keepAway = Cast.keepAwayBias(ent)
    ent._grid = grid
    local homeSide = (side == "player") and "player" or "enemy"
    local trainerSide = (side == "player") and "playerTrainer" or "enemyTrainer"
    if grid and grid.home and grid.home[homeSide] then
        local h = grid.home[homeSide]
        ent.padU, ent.padV = h.u, h.v
        ent.homePadU, ent.homePadV = h.u, h.v
        local wx, wy = Coords.padToWorld(grid, h.u, h.v)
        ent.cellX, ent.cellY = wx, wy
        ent.homeCellX, ent.homeCellY = wx, wy
        local px, py = Coords.padToPx(grid, h.u, h.v)
        ent:setHome(px, py)
        local t = grid.home[trainerSide]
        if t then
            local tpx, tpy = Coords.padToPx(grid, t.u, t.v)
            ent:setTrainerSide(tpx, tpy)
        end
        return
    end
    if side == "player" then
        ent.homeCellX, ent.homeCellY = plan.pMonX, plan.pMonY
        ent:setHome(plan.pMonX * 16, plan.pMonY * 16)
        ent:setTrainerSide(plan.pCellX * 16, plan.pCellY * 16)
    else
        ent.homeCellX, ent.homeCellY = plan.eMonX, plan.eMonY
        ent:setHome(plan.eMonX * 16, plan.eMonY * 16)
        ent:setTrainerSide(plan.eCellX * 16, plan.eCellY * 16)
    end
end

local function occupyPad(Grid, session, ent, ignoreId)
    if not (Grid and session and session.grid and ent) then
        return
    end
    local u, v = ent.padU, ent.padV
    if u == nil and session.grid and ent.cellX then
        u, v = Coords.worldToPad(session.grid, ent.cellX, ent.cellY)
        ent.padU, ent.padV = u, v
    end
    local blocked = worldBlockKeys(session, ent)
    if type(Grid.placeOnFreePad) == "function" then
        Grid.placeOnFreePad(session.grid, ent, u, v, ignoreId or ent.id, blocked)
        return
    end
    if u ~= nil then
        Grid.occupy(session.grid, ent.id, u, v)
        Grid.syncPx(session.grid, ent)
    end
end

function Cast.stageEnemy(session, battle, mod, Sprites, Grid)
    local plan = session.plan
    local game = battle.game
    local species = battle.enemy and battle.enemy.mon and battle.enemy.mon.species
    local ent = Sprites.makeMon(mod, game, species, plan.eMonX, plan.eMonY,
        plan.foeFace, "enemy", battle.enemy, session.grid)
    if not ent then
        print("[anime_realism] field: enemy mon failed to stage")
        return nil
    end
    bindHome(ent, plan, "enemy", session.grid)
    occupyPad(Grid, session, ent)
    if session.playerMon and type(Grid.preferDistance) == "function" then
        Grid.preferDistance(session.grid, ent, session.playerMon)
        Grid.preferDistance(session.grid, session.playerMon, ent)
    end
    if type(ent.play) == "function" then
        ent:play("sendout")
    end
    session.enemyMon = ent
    appendOw(game and game.overworld, ent)
    return ent
end

function Cast.stagePlayer(session, battle, mod, Sprites, Grid)
    local plan = session.plan
    local game = battle.game
    if not (battle.player and battle.player.mon) then
        return nil
    end
    local species = battle.player.mon.species
    local ent = Sprites.makeMon(mod, game, species, plan.pMonX, plan.pMonY,
        plan.playerFace, "player", battle.player, session.grid)
    if not ent then
        print("[anime_realism] field: player mon failed to stage")
        return nil
    end
    bindHome(ent, plan, "player", session.grid)
    occupyPad(Grid, session, ent)
    if session.enemyMon and type(Grid.preferDistance) == "function" then
        Grid.preferDistance(session.grid, ent, session.enemyMon)
        Grid.preferDistance(session.grid, session.enemyMon, ent)
    end
    if type(ent.play) == "function" then
        ent:play("sendout")
    end
    session.playerMon = ent
    session.awaitPlayerMon = false
    session._playerSendLockT = 0.7
    local battle = session._battle
    if battle then
        battle._arFieldRevealPlayer = nil
    end
    appendOw(game and game.overworld, ent)
    return ent
end

function Cast.replace(session, battle, mod, Sprites, Grid, side, battler)
    print("[anime_realism] field: replace", side, battler, session.playerMon, session.enemyMon)
    local game = battle.game
    local ow = game and game.overworld
    local plan = session.plan

    -- Special case: If replacing the player mon, but there is no old mon (e.g., after faint),
    -- we should NOT try to remove the enemyMon from entities (ow.entities)!
    local old
    if side == "player" then
        old = session.playerMon
    else
        old = session.enemyMon
    end

    local cx = old and old.cellX
    local cy = old and old.cellY
    local padU = old and old.padU
    local padV = old and old.padV
    if not cx then
        cx = (side == "player") and plan.pMonX or plan.eMonX
        cy = (side == "player") and plan.pMonY or plan.eMonY
    end
    local face = old and old.facing
        or ((side == "player") and plan.playerFace or plan.foeFace)
    local ignoreId = old and old.id

    -- Only release Grid/ow.entity if there actually was an old mon
    if old and Grid then
        Grid.release(session.grid, old.id)
    end
    if old and ow then
        -- Only remove OLD mon from ow.entities if it's the old one, not (for player's replace) the enemy!
        for i = #ow.entities, 1, -1 do
            if ow.entities[i] == old then
                table.remove(ow.entities, i)
            end
        end
    end

    local species = battler and battler.mon and battler.mon.species
    local ent = Sprites.makeMon(mod, game, species, cx, cy, face, side, battler, session.grid)
    if ent then
        bindHome(ent, plan, side, session.grid)
        if padU ~= nil then
            ent.padU, ent.padV = padU, padV
            if session.grid then
                local wx, wy = Coords.padToWorld(session.grid, padU, padV)
                ent.cellX, ent.cellY = wx, wy
                local px, py = Coords.padToPx(session.grid, padU, padV)
                ent.basePx, ent.basePy = px, py
                ent.targetPx, ent.targetPy = px, py
                ent.px, ent.py = px, py
            end
        end
        if old and old.homePx then
            ent:setHome(old.homePx, old.homePy)
            ent:setTrainerSide(old.trainerPx or old.homePx, old.trainerPy or old.homePy)
            ent.homeCellX = old.homeCellX or ent.homeCellX
            ent.homeCellY = old.homeCellY or ent.homeCellY
            if old.homePadU ~= nil then
                ent.homePadU, ent.homePadV = old.homePadU, old.homePadV
            end
        end
        occupyPad(Grid, session, ent, ignoreId)
        appendOw(ow, ent)
    end

    if side == "player" then
        session.playerMon = ent
        session.awaitPlayerMon = false
        session._playerSendLockT = 0.7
        local b = session._battle
        if b then
            b._arFieldRevealPlayer = nil
        end
    else
        session.enemyMon = ent
    end
    return ent
end

-- Called when a mon has fainted and is being removed from the field.
function Cast.despawn(session, battle, Grid, side)
    print("[anime_realism] field: despawn", side, session.playerMon, session.enemyMon)
    local ent = (side == "player") and session.playerMon or session.enemyMon
    if not ent then
        return
    end
    if Grid then
        Grid.release(session.grid, ent.id)
    end
    -- Detach before marking removed so voxel never samples a nil/removed pose.
    Cast.detachScene(session, ent)
    ent.hidden = true
    ent._removed = true
    ent._pendingDetach = nil
    ent.wanderTx, ent.wanderTy = nil, nil
    if side == "player" then
        session.playerMon = nil
    else
        session.enemyMon = nil
    end
end

--- Pull a field battler out of ow.entities (recall / faint / capture exit).
--- Must run before pose would be unsafe — Dramatic Shape crashes on nil sprite.
function Cast.detachScene(session, ent)
    if not ent or ent._arFieldDetached then
        return false
    end
    local battle = session and session._battle
    local ow = battle and battle.game and battle.game.overworld
    if ow and type(ow.entities) == "table" then
        for i = #ow.entities, 1, -1 do
            if ow.entities[i] == ent then
                table.remove(ow.entities, i)
            end
        end
    end
    ent._arFieldDetached = true
    ent._pendingDetach = nil
    ent.hidden = true
    return true
end

--- Put a detached field battler back on the live entity list for draw/pose.
function Cast.attachScene(session, ent)
    if not ent then
        return false
    end
    ent._arFieldDetached = nil
    if not ent._removed then
        ent.hidden = false
    end
    local battle = session and session._battle
    local ow = battle and battle.game and battle.game.overworld
    appendOw(ow, ent)
    return true
end

--- Soft lerp toward pad targets + presentation bob/anim.
--- Present clock: never gate on waitingUI / stack / current.auto.
function Cast.tick(session, dt)
    local p, e = session.playerMon, session.enemyMon
    -- Faint / recall / capture set _pendingDetach when the exit anim finishes.
    -- Pull them off ow.entities before the next voxel pose pass.
    local function flushDetach(ent)
        if ent and ent._pendingDetach and not ent._arFieldDetached then
            Cast.detachScene(session, ent)
        end
    end
    flushDetach(p)
    flushDetach(e)
    if p and type(p.tick) == "function" then
        p:tick(dt, e and e.basePx, e and e.basePy)
        flushDetach(p)
    end
    if e and type(e.tick) == "function" then
        e:tick(dt, p and p.basePx, p and p.basePy)
        flushDetach(e)
    end
    -- Stale FIELD battlers (failed replace / leftover send-out) stay on
    -- ow.entities and voxel-pose every frame. Strip anyone who is not the
    -- live pair — later turns otherwise accumulate extra sprites.
    local battle = session and session._battle
    local ow = battle and battle.game and battle.game.overworld
    local ents = ow and ow.entities
    if type(ents) == "table" then
        for i = #ents, 1, -1 do
            local ent = ents[i]
            if ent and ent._arFieldBattler and ent ~= p and ent ~= e then
                table.remove(ents, i)
            end
        end
    end
end

return Cast
