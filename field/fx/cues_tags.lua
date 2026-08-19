-- Field battle — reading battle text and marking it as a field beat.
--
-- Some beats never arrive as a clean "attack" or "hit" event. They show
-- up as dialogue: "It hurt itself in its confusion!", "CHARIZARD dug a
-- hole!", "PIKACHU fainted!". This file looks at that text, figures out
-- who it is about, and stamps the queue row so pumpCurrent can play it.
--
--   "hurt itself" / recoil / crash  → self-hit stumble
--   "dug a hole" / "flew up high"   → Dig/Fly vanish
--   "fainted!"                      → tagged for callers/tests only
--                                     (the actual faint sprite follows
--                                     the HP bar, not this line)
--
-- Open this file when confusion/recoil has no stumble, or Dig/Fly does
-- not go underground on the charge turn.

return function(Cues)
    local H = Cues._H

    function Cues.isSelfDamageText(text)
        local lower = H.flattenText(text)
        if lower:find("hurt itself", 1, true) then
            return true
        end
        if lower:find("hit with recoil", 1, true) then
            return true
        end
        if lower:find("kept going and", 1, true) and lower:find("crashed", 1, true) then
            return true
        end
        return false
    end

    local function inferSelfDamageSide(battle, text)
        local raw = tostring(text or "")
        local lower = H.flattenText(raw)
        if lower:find("hurt itself", 1, true) then
            local q = battle and battle.queue
            local idx = tonumber(battle and battle.nextInsert) or (q and #q) or 0
            for i = idx - 1, math.max(1, idx - 4), -1 do
                local prev = q and q[i]
                local t = H.flattenText(prev and prev.text)
                if t:find("is confused!", 1, true) then
                    if t:find("enemy ", 1, true) then
                        return "enemy"
                    end
                    return "player"
                end
            end
            return nil
        end
        if raw:find("Enemy ", 1, true) then
            return "enemy"
        end
        return "player"
    end

    --- Tag the latest (or nearby) queue row as a self-damage field cue.
    -- `sideHint` wins when the line has no name ("It hurt itself...").
    function Cues.tagSelfDamage(battle, text, sideHint)
        if type(battle) ~= "table" then
            return false
        end
        local q = battle.queue
        if type(q) ~= "table" then
            return false
        end
        local function rowMatches(row)
            return row and type(row.text) == "string" and Cues.isSelfDamageText(row.text)
        end
        local item = q[battle.nextInsert]
        if not rowMatches(item) then
            item = nil
            local start = tonumber(battle.nextInsert) or #q
            for i = start, math.max(1, start - 4), -1 do
                if rowMatches(q[i]) then
                    item = q[i]
                    break
                end
            end
        end
        if not item then
            return false
        end
        local side = sideHint or inferSelfDamageSide(battle, item.text)
        if side ~= "player" and side ~= "enemy" then
            return false
        end
        item.arFieldCue = { side = side, kind = "selfhit" }
        return true
    end

    --- Tag the latest queue row when a mon faints.
    -- Kept for tests / callers; FIELD does not play exit FX from this tag.
    -- Recall / faint sprites fire when the HP bar (`shownHP`) reaches 0.
    function Cues.tagFaint(battle, text)
        if type(battle) ~= "table" or type(text) ~= "string" then
            return false
        end
        local lower = H.flattenText(text)
        if not lower:find("fainted!", 1, true) then
            return false
        end
        local item = battle.queue and battle.queue[battle.nextInsert]
        if type(item) ~= "table" then
            return false
        end
        local side = tostring(text):find("Enemy ", 1, true) and "enemy" or "player"
        item.arFieldCue = { side = side, kind = "faint" }
        return true
    end

    --- Tag Dig/Fly charge lines ("dug a hole" / "flew up high") as vanish cues.
    function Cues.tagChargeVanish(battle, text)
        if type(battle) ~= "table" or type(text) ~= "string" then
            return false
        end
        local lower = H.flattenText(text)
        local flavor = nil
        if lower:find("dug a hole", 1, true) then
            flavor = "dig"
        elseif lower:find("flew up high", 1, true) then
            flavor = "fly"
        else
            return false
        end
        local item = battle.queue and battle.queue[battle.nextInsert]
        if type(item) ~= "table" then
            return false
        end
        local side = tostring(text):find("Enemy ", 1, true) and "enemy" or "player"
        item.arFieldCue = {
            side = side,
            kind = "vanish",
            vanish = flavor,
            moveId = flavor == "fly" and "FLY" or "DIG",
        }
        return true
    end
end
