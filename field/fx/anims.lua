-- Field battle — classic move FX affine map onto live pad centers.
--
-- Gen1 battle anims are authored in classic screen space (player/enemy pic
-- anchors). We map those offsets onto the live overworld pad centers so FX
-- land on the FIELD sprites without a staged arena.

local Coords = require("coords")

local Anims = {}

Anims.CLASSIC_PLAYER = { 26, 96 }
Anims.CLASSIC_ENEMY = { 124, 56 }
-- Anims.ANIM_SCALE_MIN = 0.5
-- Anims.ANIM_SCALE_MAX = 2.0
Anims.ANIM_SCALE_MIN = 0.8
Anims.ANIM_SCALE_MAX = 3.0

function Anims.monScreen(session, battle, side)
    if not (session and session.live) then
        return nil, nil
    end
    local ent = (side == "player") and session.playerMon or session.enemyMon
    if not ent then
        return nil, nil
    end
    local cam = battle and battle.game and battle.game.overworld
        and battle.game.overworld.camera
    -- Pad center is the FX anchor; bob/anim offsets ride on px/py.
    local wx, wy
    if session.grid and ent.padU ~= nil and Coords then
        wx, wy = Coords.padCenterPx(session.grid, ent.padU, ent.padV)
        local bobX = (ent.px or ent.basePx or wx) - (ent.basePx or (wx - 8))
        local bobY = (ent.py or ent.basePy or wy) - (ent.basePy or (wy - 8))
        wx = wx + bobX
        wy = wy + bobY - 4
    else
        wx = (ent.px or ent.basePx or (ent.cellX or 0) * 16) + 8
        wy = (ent.py or ent.basePy or (ent.cellY or 0) * 16) + 4
    end
    if not cam then
        return wx, wy
    end
    return wx - (cam.x or 0), wy - (cam.y or 0)
end

function Anims.transform(session, battle)
    local px, py = Anims.monScreen(session, battle, "player")
    local ex, ey = Anims.monScreen(session, battle, "enemy")
    local aP, aE = Anims.CLASSIC_PLAYER, Anims.CLASSIC_ENEMY

    if not (px and ex) then
        if ex then
            return {
                mode = "shift",
                dx = ex - aE[1],
                dy = ey - aE[2],
                k = 1,
                ax = aE[1],
                ay = aE[2],
            }
        end
        if px then
            return {
                mode = "shift",
                dx = px - aP[1],
                dy = py - aP[2],
                k = 1,
                ax = aP[1],
                ay = aP[2],
            }
        end
        return { mode = "shift", dx = 0, dy = 0, k = 1, ax = 75, ay = 76 }
    end

    local cdx, cdy = aE[1] - aP[1], aE[2] - aP[2]
    local fdx, fdy = ex - px, ey - py
    local cspan = math.sqrt(cdx * cdx + cdy * cdy)
    local fspan = math.sqrt(fdx * fdx + fdy * fdy)
    if cspan < 1 or fspan < 1 then
        return {
            mode = "shift",
            dx = ((px + ex) / 2) - ((aP[1] + aE[1]) / 2),
            dy = ((py + ey) / 2) - ((aP[2] + aE[2]) / 2),
            k = 1,
            ax = (aP[1] + aE[1]) / 2,
            ay = (aP[2] + aE[2]) / 2,
        }
    end

    local k = fspan / cspan
    k = math.max(Anims.ANIM_SCALE_MIN, math.min(Anims.ANIM_SCALE_MAX, k))
    return {
        mode = "affine",
        apx = aP[1],
        apy = aP[2],
        fpx = px,
        fpy = py,
        cang = math.atan2(cdy, cdx),
        fang = math.atan2(fdy, fdx),
        k = k,
    }
end

function Anims.cache(session, battle)
    if session then
        session._animXform = Anims.transform(session, battle)
    end
end

function Anims.cached(session, battle)
    if session and session._animXform then
        return session._animXform
    end
    return Anims.transform(session, battle)
end

function Anims.shift(session, battle)
    local t = Anims.transform(session, battle)
    if type(t) == "table" and t.mode == "shift" then
        return t.dx, t.dy
    end
    if type(t) == "table" and t.mode == "affine" then
        return (t.fpx or 0) - (t.apx or 0), (t.fpy or 0) - (t.apy or 0)
    end
    return 0, 0
end

return Anims
