-- Field battle — themed pad on the live overworld (session-only).
--
-- Fight stays on the real map. Cover / grass / ponds are generated from the
-- location kit as overlay props on pad cells (`_arFieldCover`). Never scans
-- or writes live tiles. Cleared on Lifecycle.finish.

local Themes = require("themes")
local Coords = require("coords")

local Arena = {}

Arena.MAX_SLOTS = 8

function Arena.scene(battle)
    return Themes.scene(battle)
end

function Arena.padRect(plan)
    plan = plan or {}
    local sx = plan.sx or 1
    local sy = plan.sy or 0
    local lateral = plan.padHalfV or 1
    local minX = math.min(plan.pCellX or 0, plan.eCellX or 0)
    local maxX = math.max(plan.pCellX or 0, plan.eCellX or 0)
    local minY = math.min(plan.pCellY or 0, plan.eCellY or 0)
    local maxY = math.max(plan.pCellY or 0, plan.eCellY or 0)
    if sx ~= 0 then
        minY = (plan.midY or 0) - lateral
        maxY = (plan.midY or 0) + lateral
    else
        minX = (plan.midX or 0) - lateral
        maxX = (plan.midX or 0) + lateral
    end
    return { minX = minX, maxX = maxX, minY = minY, maxY = maxY, sx = sx, sy = sy }
end

local function hashSeed(battle, plan)
    local n = 2166136261
    local id = ""
    if battle and type(battle.currentMapId) == "function" then
        id = tostring(battle:currentMapId() or "")
    end
    for i = 1, #id do
        n = (n * 16777619 + id:byte(i)) % 2147483647
    end
    n = (n + (plan.midX or 0) * 131 + (plan.midY or 0) * 17) % 2147483647
    local t = 0
    if love and love.timer and love.timer.getTime then
        t = math.floor(love.timer.getTime() * 50)
    elseif os and os.time then
        t = os.time()
    end
    return (n + t) % 2147483647
end

local function rng(state)
    state[1] = (state[1] * 1103515245 + 12345) % 2147483648
    return state[1] / 2147483648
end

local function ri(state, a, b)
    if a == b then
        return a
    end
    if a > b then
        a, b = b, a
    end
    return a + math.floor(rng(state) * (b - a + 1))
end

local function reservedPad(plan, layout, u, v)
    if not plan then
        return false
    end
    local cells = {
        { plan.pCellX, plan.pCellY },
        { plan.eCellX, plan.eCellY },
        { plan.pMonX,  plan.pMonY },
        { plan.eMonX,  plan.eMonY },
        { plan.midX,   plan.midY },
    }
    for i = 1, #cells do
        local cx, cy = cells[i][1], cells[i][2]
        if cx and cy then
            local pu, pv = Coords.worldToPad(layout, cx, cy)
            if pu == u and pv == v then
                return true
            end
        end
    end
    -- Keep each battler's full three-cell dodge lane readable and unblocked.
    for _, cell in ipairs({
        { plan.pMonX, plan.pMonY },
        { plan.eMonX, plan.eMonY },
    }) do
        if cell[1] ~= nil and cell[2] ~= nil then
            local pu, pv = Coords.worldToPad(layout, cell[1], cell[2])
            if pu == u and math.abs(pv - v) <= 1 then
                return true
            end
        end
    end
    return false
end

local function pushPadSlot(slots, seen, layout, u, v, kind, scene)
    local key = tostring(u) .. "," .. tostring(v)
    if seen[key] then
        return false
    end
    seen[key] = true
    local wx, wy = Coords.padToWorld(layout, u, v)
    local px, py = Coords.padToPx(layout, u, v)
    slots[#slots + 1] = {
        u = u,
        v = v,
        wx = wx,
        wy = wy,
        cx = wx,
        cy = wy,
        px = px + 8,
        py = py + 8,
        kind = kind or "COVER",
        scene = scene,
        overlay = true,
    }
    return true
end

local function edgePads(layout, plan, walkable)
    local edge = {}
    local su, sv = layout.sizeU or 0, layout.sizeV or 0
    for u = 0, su - 1 do
        for v = 0, sv - 1 do
            local onEdge = (u == 0 or u == su - 1 or v == 0 or v == sv - 1)
            local allowed = not walkable or walkable[Coords.key(u, v)]
            if allowed and onEdge and not reservedPad(plan, layout, u, v) then
                -- Keep the fight axis corridor open at the mid v / mid u.
                local midV = math.floor((sv - 1) / 2)
                local midU = math.floor((su - 1) / 2)
                local axisGap = false
                if math.abs(plan.sx or 1) >= math.abs(plan.sy or 0) then
                    if v == midV and (u == 0 or u == su - 1) then
                        axisGap = true
                    end
                else
                    if u == midU and (v == 0 or v == sv - 1) then
                        axisGap = true
                    end
                end
                if not axisGap then
                    edge[#edge + 1] = { u = u, v = v }
                end
            end
        end
    end
    return edge
end

local function interiorPads(layout, plan, walkable)
    local inner = {}
    local su, sv = layout.sizeU or 0, layout.sizeV or 0
    for u = 1, su - 2 do
        for v = 1, sv - 2 do
            local allowed = not walkable or walkable[Coords.key(u, v)]
            if allowed and not reservedPad(plan, layout, u, v) then
                inner[#inner + 1] = { u = u, v = v }
            end
        end
    end
    return inner
end

local function shuffle(list, state)
    for i = #list, 2, -1 do
        local j = ri(state, 1, i)
        list[i], list[j] = list[j], list[i]
    end
end

local function takeScattered(pool, state, want, seen)
    local out = {}
    local taken = {}
    for i = 1, #pool do
        if #out >= want then
            break
        end
        local c = pool[i]
        local key = c.u .. "," .. c.v
        if not seen[key] then
            local crowded = false
            for du = -1, 1 do
                for dv = -1, 1 do
                    if taken[(c.u + du) .. "," .. (c.v + dv)] then
                        crowded = true
                    end
                end
            end
            if not crowded then
                out[#out + 1] = c
                taken[key] = true
            end
        end
    end
    return out
end

--- Build a themed pad layout. `seed` optional (tests). Never touches map tiles.
--- `envelope` is a read-only Survey result with an expanded pad/walkable mask.
function Arena.generate(battle, plan, seed, envelope)
    plan = plan or {}
    local rect = (envelope and envelope.gridRect) or Arena.padRect(plan)
    local layout = (envelope and envelope.pad)
        or Coords.layoutPad(rect, plan.sx or 1, plan.sy or 0)
    local scene = Arena.scene(battle)
    local kit = Themes.kit(scene)
    local state = { seed or hashSeed(battle, plan) }
    if state[1] == 0 then
        state[1] = 1
    end

    local seen = {}
    local coverSlots = {}
    local walkable = envelope and envelope.walkable or nil
    local hand = kit.layout or (Themes.layout and Themes.layout(scene))
    local useHand = type(hand) == "table"
        and type(hand.cover) == "table"
        and (hand.sizeU or 0) == (layout.sizeU or 0)
        and (hand.sizeV or 0) == (layout.sizeV or 0)

    if useHand then
        for i = 1, #hand.cover do
            local c = hand.cover[i]
            if c and not reservedPad(plan, layout, c.u, c.v) then
                local allowed = not walkable or walkable[Coords.key(c.u, c.v)]
                if allowed then
                    pushPadSlot(coverSlots, seen, layout, c.u, c.v, c.kind or kit.cover, scene)
                end
            end
        end
        local ponds = {}
        for i = 1, #(hand.ponds or {}) do
            local pond = hand.ponds[i]
            if pond then
                local allowed = not walkable or walkable[Coords.key(pond.u, pond.v)]
                if allowed and not reservedPad(plan, layout, pond.u, pond.v) then
                    pushPadSlot(coverSlots, seen, layout, pond.u, pond.v, "POND", scene)
                    ponds[#ponds + 1] = coverSlots[#coverSlots]
                end
            end
        end
        local grass = {}
        for i = 1, #(hand.grass or {}) do
            local g = hand.grass[i]
            if g then
                local allowed = not walkable or walkable[Coords.key(g.u, g.v)]
                if allowed and not reservedPad(plan, layout, g.u, g.v) then
                    local wx, wy = Coords.padToWorld(layout, g.u, g.v)
                    local px, py = Coords.padToPx(layout, g.u, g.v)
                    grass[#grass + 1] = {
                        u = g.u, v = g.v, cx = wx, cy = wy, px = px, py = py,
                        w = 16, h = 16, kind = kit.grassKind,
                    }
                end
            end
        end
        local overlay = {}
        for i = 1, #coverSlots do
            if coverSlots[i].kind ~= "POND" then
                overlay[#overlay + 1] = coverSlots[i]
            end
        end
        return {
            gridRect = rect,
            pad = layout,
            walkable = envelope and envelope.walkable or nil,
            water = envelope and envelope.water or nil,
            coverSlots = (#coverSlots > 0) and coverSlots or nil,
            overlay = (#overlay > 0) and overlay or nil,
            grass = grass,
            ponds = ponds,
            kit = kit,
            coverKind = kit.cover,
            coverScene = scene,
            scene = scene,
            wroteMap = false,
            midX = plan.midX,
            midY = plan.midY,
            sx = plan.sx or 1,
            sy = plan.sy or 0,
            seed = state[1],
            handcrafted = true,
        }
    end

    local edge = edgePads(layout, plan, walkable)
    shuffle(edge, state)
    local coverN = ri(state, kit.coverN[1], kit.coverN[2])
    coverN = math.min(coverN, 2)
    local covers = takeScattered(edge, state, coverN, seen)
    for i = 1, #covers do
        pushPadSlot(coverSlots, seen, layout, covers[i].u, covers[i].v, kit.cover, scene)
    end

    local ponds = {}
    local pondN = math.min(1, ri(state, kit.pondN[1], kit.pondN[2]))
    local pondPool = {}
    for i = 1, #edge do
        pondPool[#pondPool + 1] = edge[i]
    end
    shuffle(pondPool, state)
    local pondPicks = takeScattered(pondPool, state, pondN, seen)
    for i = 1, #pondPicks do
        local c = pondPicks[i]
        pushPadSlot(coverSlots, seen, layout, c.u, c.v, "POND", scene)
        ponds[#ponds + 1] = coverSlots[#coverSlots]
    end

    local grass = {}
    local grassN = math.min(2, ri(state, kit.grassN[1], kit.grassN[2]))
    local inner = interiorPads(layout, plan, walkable)
    if #inner == 0 then
        inner = edge
    end
    shuffle(inner, state)
    local grassPicks = takeScattered(inner, state, grassN, seen)
    for i = 1, #grassPicks do
        local c = grassPicks[i]
        local wx, wy = Coords.padToWorld(layout, c.u, c.v)
        local px, py = Coords.padToPx(layout, c.u, c.v)
        grass[#grass + 1] = {
            u = c.u,
            v = c.v,
            cx = wx,
            cy = wy,
            px = px,
            py = py,
            w = 16,
            h = 16,
            kind = kit.grassKind,
        }
    end

    local overlay = {}
    for i = 1, #coverSlots do
        local s = coverSlots[i]
        if s.kind ~= "POND" then
            overlay[#overlay + 1] = s
        end
    end

    return {
        gridRect = rect,
        pad = layout,
        walkable = envelope and envelope.walkable or nil,
        water = envelope and envelope.water or nil,
        coverSlots = (#coverSlots > 0) and coverSlots or nil,
        overlay = (#overlay > 0) and overlay or nil,
        grass = grass,
        ponds = ponds,
        kit = kit,
        coverKind = kit.cover,
        coverScene = scene,
        scene = scene,
        wroteMap = false,
        midX = plan.midX,
        midY = plan.midY,
        sx = plan.sx or 1,
        sy = plan.sy or 0,
        seed = state[1],
    }
end

function Arena.apply(battle, plan, seed)
    return Arena.generate(battle, plan, seed)
end

function Arena.survey(battle, plan)
    return Arena.generate(battle, plan)
end

function Arena.carve(battle, midX, midY, sx, sy)
    return Arena.generate(battle, {
        midX = midX,
        midY = midY,
        sx = sx or 1,
        sy = sy or 0,
        pCellX = (midX or 0) - (sx or 1) * 2,
        pCellY = (midY or 0) - (sy or 0) * 2,
        eCellX = (midX or 0) + (sx or 1) * 2,
        eCellY = (midY or 0) + (sy or 0) * 2,
        pMonX = (midX or 0) - (sx or 1),
        pMonY = (midY or 0) - (sy or 0),
        eMonX = (midX or 0) + (sx or 1),
        eMonY = (midY or 0) + (sy or 0),
        padHalfV = 1,
    })
end

-- Voxel shapes tailored to resemble Pokémon overworld (Gen 4+) style.

-- Draws an isometric/tilted rectangle for a "voxel" tile; tileY squish and
-- vertical offset for the cube illusion.
local function voxelTile(g, cx, cy, w, h, color, shadow)
    local isoH = h * 0.5
    local isoW = w * 0.5
    -- Top face (isometric diamond)
    g.setColor(color[1], color[2], color[3], color[4] or 1)
    g.polygon("fill",
        cx, cy - isoH,
        cx + isoW, cy,
        cx, cy + isoH,
        cx - isoW, cy
    )
    -- Simple shadow for depth
    if shadow then
        g.setColor(shadow[1], shadow[2], shadow[3], shadow[4] or 0.5)
        g.polygon("fill",
            cx, cy + isoH,
            cx + isoW, cy,
            cx + isoW, cy + isoH,
            cx, cy + isoH * 2
        )
    end
end

-- Draws a "Pokémon-style" rock: bumpy isometric base, top highlight
local function drawRock(g, ox, oy)
    -- Main rock body
    voxelTile(g, ox + 12, oy + 13, 17, 11, { 0.47, 0.39, 0.32, 1 }, { 0.19, 0.16, 0.12, 0.5 })
    -- Bump/layer for extra shape
    voxelTile(g, ox + 14, oy + 9, 8, 6, { 0.55, 0.48, 0.40, 1 }, { 0.2, 0.18, 0.14, 0.4 })
    -- Highlight
    g.setColor(1, 1, 1, 0.19)
    g.ellipse("fill", ox + 13, oy + 7, 4, 3)
end

-- Draws a "Pokémon-style" tree: trunk rectangle + 2-3 leafy isometric blobs
local function drawTree(g, ox, oy)
    -- Trunk
    g.setColor(0.45, 0.26, 0.10, 1)
    g.rectangle("fill", ox + 9, oy + 13, 4, 10, 1, 1)
    -- Canopy blobs
    voxelTile(g, ox + 11, oy + 10, 15, 9, { 0.20, 0.62, 0.18, 1 }, { 0.15, 0.28, 0.12, 0.2 })
    voxelTile(g, ox + 7, oy + 7, 11, 7, { 0.27, 0.82, 0.34, 1 }, { 0.13, 0.34, 0.21, 0.14 })
    -- Tip highlight
    g.setColor(1, 1, 1, 0.12)
    g.ellipse("fill", ox + 14, oy + 4, 3.0, 2.1)
end

-- Crates: square, wood tone, lines at edges ("boxier" than other props)
local function drawCrate(g, ox, oy)
    voxelTile(g, ox + 10, oy + 10, 13, 13, { 0.72, 0.55, 0.22, 1 }, { 0.34, 0.20, 0.10, 0.25 })
    -- Draw plank lines for wood grain effect
    g.setColor(0.36, 0.26, 0.08, 0.29)
    for i = 1, 4 do
        g.line(ox + 10 - 5 + i * 2, oy + 10 - 5, ox + 10 - 5 + i * 2, oy + 10 + 6)
    end
end

-- "Pokémon-style" pond: round-rectangle isometric, rimmed, some highlight
local function drawPondCell(g, ox, oy, kit)
    local pc = (kit and kit.pond) or { 0.30, 0.52, 0.80, 0.90 }
    local rim = { 0.18, 0.32, 0.50, 0.55 }
    local hi = { 0.82, 0.94, 1.0, 0.23 }
    -- Water fill
    voxelTile(g, ox + 12, oy + 12, 17, 10, pc, rim)
    -- Rim highlight near top
    g.setColor(hi[1], hi[2], hi[3], hi[4])
    g.arc("fill", "open", ox + 14, oy + 5, 6, math.rad(210), math.rad(330))
end

-- Pokémon-style grass patch: cluster of small, semi-overlapping round blades
local function drawGrassPatch(g, ox, oy, kit)
    local gc = (kit and kit.grass) or { 0.34, 0.68, 0.23, 1 }
    local shade = { 0.23, 0.38, 0.21, 0.3 }
    -- Central blade
    voxelTile(g, ox + 10, oy + 13, 6, 6, gc, shade)
    -- Clumps on side
    voxelTile(g, ox + 6, oy + 12, 4, 6, gc, nil)
    voxelTile(g, ox + 14, oy + 12, 4, 6, gc, nil)
    -- light highlight
    g.setColor(1.0, 1.0, 1.0, 0.13)
    g.ellipse("fill", ox + 10, oy + 10, 2, 1.1)
end

function Arena.drawCover(kind, x, y, kit)
    if not (love and love.graphics) then
        return
    end
    local g = love.graphics
    kind = tostring(kind or "TREE"):upper()
    if kind == "ROCK" then
        drawRock(g, x, y)
    elseif kind == "CRATE" then
        drawCrate(g, x, y)
    elseif kind == "POND" then
        drawPondCell(g, x, y, kit)
    else
        drawTree(g, x, y)
    end
    g.setColor(1, 1, 1, 1)
end

--- Grass / pond voxels only — never paint a wash over the live map.
function Arena.drawFloor(layout, camX, camY)
    if not (layout and love and love.graphics) then
        return
    end
    local kit = layout.kit or Themes.kit(layout.scene)
    local g = love.graphics
    camX, camY = camX or 0, camY or 0
    local grass = layout.grass or {}
    for i = 1, #grass do
        local p = grass[i]
        local x = (p.px or ((p.cx or 0) * 16)) - camX
        local y = (p.py or ((p.cy or 0) * 16)) - camY
        drawGrassPatch(g, x, y, kit)
    end
    local ponds = layout.ponds or {}
    for i = 1, #ponds do
        local p = ponds[i]
        local x = (p.cx or 0) * 16 - camX
        local y = (p.cy or 0) * 16 - camY
        drawPondCell(g, x, y, kit)
    end
    g.setColor(1, 1, 1, 1)
end

function Arena.floorEntity(layout)
    if not layout then
        return nil
    end
    local grass = layout.grass or {}
    local ponds = layout.ponds or {}
    if #grass == 0 and #ponds == 0 then
        return nil
    end
    local rect = layout.gridRect or {}
    local ent = {
        id = "ar_fbv_floor",
        _arFieldFloor = true,
        _arFieldCover = true,
        _fbv = true,
        cellX = rect.minX or 0,
        cellY = rect.minY or 0,
        px = (rect.minX or 0) * 16,
        py = (rect.minY or 0) * 16,
        passable = true,
        frozen = true,
        wanders = false,
        layout = layout,
    }
    function ent:update()
    end

    function ent:pose()
        return nil, self.px, self.py, "down", 0, false
    end

    function ent:draw(camX, camY)
        Arena.drawFloor(self.layout, camX, camY)
    end

    return ent
end

function Arena.overlayEntity(slot)
    if not slot then
        return nil
    end
    local kind = slot.kind or "COVER"
    local cx = slot.cx or slot.wx or 0
    local cy = slot.cy or slot.wy or 0
    local ent = {
        id = "ar_fbv_cover_" .. tostring(cx) .. "_" .. tostring(cy),
        _arFieldCover = true,
        _fbv = true,
        cellX = cx,
        cellY = cy,
        padU = slot.u,
        padV = slot.v,
        px = (slot.px and (slot.px - 8)) or (cx * 16),
        py = (slot.py and (slot.py - 8)) or (cy * 16),
        kind = kind,
        passable = true,
        frozen = true,
        wanders = false,
        hidden = false,
    }
    function ent:update()
    end

    function ent:pose()
        return nil, self.px, self.py, "down", 0, false
    end

    function ent:draw(camX, camY)
        if self.hidden then
            return
        end
        local x = (self.px or 0) - (camX or 0)
        local y = (self.py or 0) - (camY or 0)
        local g = love and love.graphics
        local grow = self.coverGrow or 0
        if grow < 0 then
            grow = 0
        elseif grow > 1 then
            grow = 1
        end
        local s = 0.72 + grow * 0.50
        if g then
            g.push()
            g.translate(x + 8, y + 10 - grow * 3)
            g.scale(s, s)
            g.translate(-(x + 8), -(y + 10))
            Arena.drawCover(self.kind, x, y)
            if grow > 0.35 then
                local ox = (self._coverTowardX or 0) * grow * 5
                local oy = (self._coverTowardY or 1) * grow * 3
                Arena.drawCover(self.kind, x + ox, y + oy)
            end
            g.pop()
        else
            Arena.drawCover(self.kind, x, y)
        end
    end

    return ent
end

function Arena.restore(_edits)
end

function Arena.restoreSnapshot(_snap)
end

function Arena.snapshot(_battle, _midX, _midY)
    return nil
end

return Arena
