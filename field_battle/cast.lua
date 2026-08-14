-- Field battle — stage trainers + mons onto pad cells.
--
-- Pad (u, v) is truth; pixels come from Coords.padToPx. Homes come from
-- Layout's tight opening (adjacent mons, trainers one tile back). Cast.tick
-- lerps px/py toward the current pad each frame.

local Coords = require("coords")

local Cast = {}

Cast.STEP_SPEED = 56

local function appendOw(ow, ent)
    if not (ow and type(ow.entities) == "table" and ent) then
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
    ent.stepSpeed = Cast.STEP_SPEED
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

local function occupyPad(Grid, session, ent)
    if not (Grid and session and session.grid and ent) then
        return
    end
    local u, v = ent.padU, ent.padV
    if u == nil and session.grid and ent.cellX then
        u, v = Coords.worldToPad(session.grid, ent.cellX, ent.cellY)
        ent.padU, ent.padV = u, v
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
        print("[anime_realism] field_battle: enemy mon failed to stage")
        return nil
    end
    bindHome(ent, plan, "enemy", session.grid)
    occupyPad(Grid, session, ent)
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
        print("[anime_realism] field_battle: player mon failed to stage")
        return nil
    end
    bindHome(ent, plan, "player", session.grid)
    occupyPad(Grid, session, ent)
    if type(ent.play) == "function" then
        ent:play("sendout")
    end
    session.playerMon = ent
    session.awaitPlayerMon = false
    appendOw(game and game.overworld, ent)
    return ent
end

function Cast.replace(session, battle, mod, Sprites, Grid, side, battler)
    local game = battle.game
    local ow = game and game.overworld
    local plan = session.plan
    local old = (side == "player") and session.playerMon or session.enemyMon
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
    if old and Grid then
        Grid.release(session.grid, old.id)
    end
    if old and ow then
        for i = #ow.entities, 1, -1 do
            if ow.entities[i] == old then
                table.remove(ow.entities, i)
            end
        end
    end
    local species = battler and battler.mon and battler.mon.species
    local ent = Sprites.makeMon(mod, game, species, cx, cy, face, side, battler,
        session.grid)
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
        occupyPad(Grid, session, ent)
        appendOw(ow, ent)
    end
    if side == "player" then
        session.playerMon = ent
        session.awaitPlayerMon = false
    else
        session.enemyMon = ent
    end
    return ent
end

function Cast.despawn(session, battle, Grid, side)
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
    -- Also tick any FIELD battler still in the OW list (ref safety).
    local battle = session and session._battle
    local ow = battle and battle.game and battle.game.overworld
    local ents = ow and ow.entities
    if type(ents) == "table" then
        for i = 1, #ents do
            local ent = ents[i]
            if ent and ent._arFieldBattler and ent ~= p and ent ~= e
                and type(ent.tick) == "function" then
                local other = (ent._arFieldSide == "player") and e or p
                ent:tick(dt, other and other.basePx, other and other.basePy)
                flushDetach(ent)
            end
        end
    end
end

return Cast
