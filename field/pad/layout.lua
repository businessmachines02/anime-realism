-- Field battle — layout helpers (axis, poses, foe find).
--
-- Opening along the fight axis (one empty cell between mons, trainers one
-- tile back): player trainer, player mon, empty, enemy mon, foe trainer.
-- Survey expands walkable cells beyond this for free movement during the fight.

local Layout = {}

-- Trainer stand-off behind each mon (pad cells along the fight axis).
Layout.TRAINER_BACK = 1
-- Gap between mon centers: 1 = adjacent, 2 = one empty cell between.
Layout.MON_GAP = 2
-- Lateral (dodge) half-width of the opening formation.
Layout.LATERAL = 1
-- Legacy aliases (wild anchor / older callers).
Layout.HALF = 2
Layout.MON = 2

function Layout.copyPose(ent)
    if not ent then
        return nil
    end
    return {
        cellX = ent.cellX,
        cellY = ent.cellY,
        px = ent.px,
        py = ent.py,
        facing = ent.facing,
        frozen = ent.frozen,
        wanders = ent.wanders,
        padU = ent.padU,
        padV = ent.padV,
        hadPad = ent.padU ~= nil or ent.padV ~= nil,
    }
end

function Layout.applyPose(ent, pose)
    if not (ent and pose) then
        return
    end
    ent.cellX = pose.cellX
    ent.cellY = pose.cellY
    ent.px = pose.px or (pose.cellX * 16)
    ent.py = pose.py or (pose.cellY * 16)
    if pose.facing ~= nil then
        ent.facing = pose.facing
    end
    if pose.frozen ~= nil then
        ent.frozen = pose.frozen
    end
    if pose.wanders ~= nil then
        ent.wanders = pose.wanders
    end
    if pose.hadPad then
        ent.padU, ent.padV = pose.padU, pose.padV
    else
        ent.padU, ent.padV = nil, nil
    end
end

function Layout.axisFrom(ax, ay, bx, by)
    local dx, dy = (bx or ax) - ax, (by or ay) - ay
    if math.abs(dx) >= math.abs(dy) and dx ~= 0 then
        return dx > 0 and 1 or -1, 0
    end
    if dy ~= 0 then
        return 0, dy > 0 and 1 or -1
    end
    return 0, -1
end

function Layout.facingFromAxis(sx, sy)
    if sx > 0 then
        return "right"
    end
    if sx < 0 then
        return "left"
    end
    if sy > 0 then
        return "down"
    end
    return "up"
end

function Layout.opposite(facing)
    if facing == "up" then
        return "down"
    end
    if facing == "down" then
        return "up"
    end
    if facing == "left" then
        return "right"
    end
    if facing == "right" then
        return "left"
    end
    return "down"
end

function Layout.findFoeTrainer(ow, battle)
    local player = ow and ow.player
    if not (player and battle and battle.kind == "trainer") then
        return nil
    end
    local origin = battle.checkpointOrigin
    local npcId = origin and origin.npcId
    if npcId and ow.npcPool and ow.npcPool[npcId] then
        return ow.npcPool[npcId]
    end
    local best, bestD
    for _, pool in ipairs({ ow.entities or {}, ow.npcs or {} }) do
        for i = 1, #pool do
            local e = pool[i]
            local def = e and e.def
            local isTrainer = e and (e.trainer or e.trainerClass
                or (def and def.trainerClass)
                or (npcId and e.id == npcId))
            if e and e ~= player and isTrainer then
                local dx = (e.cellX or 0) - (player.cellX or 0)
                local dy = (e.cellY or 0) - (player.cellY or 0)
                local d = dx * dx + dy * dy
                if not bestD or d < bestD then
                    best, bestD = e, d
                end
            end
        end
    end
    return best
end

function Layout.wildAnchor(player)
    -- Face a foe about one full tight-formation span away.
    local span = (Layout.TRAINER_BACK or 1) * 2 + (Layout.MON_GAP or 1)
    local fx, fy = player.cellX or 0, player.cellY or 0
    local facing = player.facing or "up"
    if facing == "up" then
        return fx, fy - span
    end
    if facing == "down" then
        return fx, fy + span
    end
    if facing == "left" then
        return fx - span, fy
    end
    return fx + span, fy
end

function Layout.plan(px, py, fx, fy)
    local sx, sy = Layout.axisFrom(px, py, fx, fy)
    local midX = math.floor((px + fx) / 2)
    local midY = math.floor((py + fy) / 2)
    local gap = math.max(1, Layout.MON_GAP or 1)
    local back = math.max(0, Layout.TRAINER_BACK or 1)
    -- Mons sit around the midpoint. gap=1 → player at mid, enemy at mid+1.
    -- gap=2 → player at mid-1, enemy at mid+1 (one empty cell; trainers stay put).
    local monLo = math.floor(gap / 2)
    local monHi = math.ceil(gap / 2)
    local pMonX = midX - sx * monLo
    local pMonY = midY - sy * monLo
    local eMonX = midX + sx * monHi
    local eMonY = midY + sy * monHi
    local playerFace = Layout.facingFromAxis(sx, sy)
    return {
        sx = sx,
        sy = sy,
        midX = midX,
        midY = midY,
        playerFace = playerFace,
        foeFace = Layout.opposite(playerFace),
        pCellX = pMonX - sx * back,
        pCellY = pMonY - sy * back,
        eCellX = eMonX + sx * back,
        eCellY = eMonY + sy * back,
        pMonX = pMonX,
        pMonY = pMonY,
        eMonX = eMonX,
        eMonY = eMonY,
        padHalfV = Layout.LATERAL,
    }
end

return Layout
