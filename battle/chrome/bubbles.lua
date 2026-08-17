-- Battle chrome — trainer banter cameo + speech-bubble paint.
--
-- Rewrite / say wraps / banter enqueue stay in rules/dialogue.lua.
-- FIELD world-anchored trainer strips live in field/chrome/callouts.lua.

local Chrome = {}
local host = {}

function Chrome.bind(h)
    if type(h) == "table" then
        for k, v in pairs(h) do
            host[k] = v
        end
    end
    return Chrome
end

local function hostCall(name, ...)
    local fn = host[name]
    if type(fn) == "function" then
        return fn(...)
    end
end

local function opt(key)
    local fn = host.opt
    if type(fn) == "function" then
        return fn(key)
    end
    return false
end

local function peek(battle)
    local React = host.React
    if React and type(React.peek) == "function" then
        return React.peek(battle)
    end
end

local function cameoDur(key, fallback)
    local S = host.S
    local n = S and S[key]
    return tonumber(n) or fallback
end

local Font
local function getFont()
    if Font ~= nil then
        return Font or nil
    end
    local ok, value = pcall(require, "src.render.Font")
    Font = (ok and value) or false
    return Font or nil
end

-- 2D trainer-pic slide while a banter line is up. Classic overlay only.
local Banter = {}

function Banter.image(battle)
    if type(battle) ~= "table" then
        return nil
    end
    local img = battle.enemyTrainerImage or battle.trainerPic
    if not img then
        return nil
    end
    if type(battle.picImage) == "function" and battle.trainerPic then
        local ok, painted = pcall(battle.picImage, battle, battle.trainerPic)
        if ok and painted then
            return painted
        end
    end
    return img
end

function Banter.stillShowing(battle, line)
    if type(battle) ~= "table" then
        return false
    end
    local session = hostCall("liveFieldSession", battle)
    local overlays = session and session._trainerCallouts
    if overlays and overlays.foe and #overlays.foe > 0 then
        return true
    end
    local cur = battle.current
    if cur and cur.arBanter then
        return true
    end
    if line and cur and cur.text == line then
        return true
    end
    if line and battle._arLastBubbleText == line then
        return true
    end
    return false
end

function Banter.progress(cameo)
    if not cameo then
        return 0
    end
    local t
    if cameo.mode == "in" then
        local dur = cameoDur("BANTER_CAMEO_IN", 14)
        t = math.min(1, (cameo.frame or 0) / math.max(1, dur))
    elseif cameo.mode == "out" then
        local dur = cameoDur("BANTER_CAMEO_OUT", 12)
        t = 1 - math.min(1, (cameo.frame or 0) / math.max(1, dur))
    else
        t = 1
    end
    return t * t * (3 - 2 * t)
end

function Banter.start(battle, line)
    if not opt("trainer_banter") or not hostCall("trainerFoeReactionsOn", battle) then
        return
    end
    if battle.showEnemyTrainer then
        return
    end
    if not Banter.image(battle) then
        return
    end
    local state = hostCall("momentumState", battle)
    if type(state) ~= "table" then
        return
    end
    state.banterCameoWanted = line or true
end

function Banter.tick(battle)
    if type(battle) ~= "table" then
        return
    end
    local state = peek(battle)
    if not state then
        return
    end
    local cameo = state.banterCameo
    local wanted = state.banterCameoWanted
    local cur = battle.current

    local session = hostCall("liveFieldSession", battle)
    local foeToasts = session and session._trainerCallouts
        and session._trainerCallouts.foe
    local overlayBanter = type(foeToasts) == "table" and #foeToasts > 0
    if not cameo and wanted and (overlayBanter or (cur and cur.arBanter)) then
        if not battle.showEnemyTrainer and Banter.image(battle) then
            state.banterCameo = {
                mode = "in",
                frame = 0,
                line = (wanted ~= true and wanted)
                    or (cur and cur.text) or nil,
            }
            cameo = state.banterCameo
        end
        state.banterCameoWanted = nil
    end

    if not cameo then
        return
    end

    if cameo.mode == "in" then
        cameo.frame = (cameo.frame or 0) + 1
        if cameo.frame >= cameoDur("BANTER_CAMEO_IN", 14) then
            cameo.mode = "hold"
            cameo.frame = 0
        end
    elseif cameo.mode == "hold" then
        if not Banter.stillShowing(battle, cameo.line) then
            cameo.mode = "out"
            cameo.frame = 0
        end
    elseif cameo.mode == "out" then
        cameo.frame = (cameo.frame or 0) + 1
        if cameo.frame >= cameoDur("BANTER_CAMEO_OUT", 12) then
            state.banterCameo = nil
        end
    end
end

function Banter.draw(battle)
    if not opt("trainer_banter") then
        return
    end
    local state = battle and peek(battle)
    local cameo = state and state.banterCameo
    if not cameo or not love or not love.graphics then
        return
    end
    if battle.showEnemyTrainer then
        return
    end
    local img = Banter.image(battle)
    if not img or type(img.getDimensions) ~= "function" then
        return
    end

    local t = Banter.progress(cameo)
    if t <= 0 then
        return
    end

    local iw, ih = img:getDimensions()
    -- Same enemy-intro box Gen 2 / Gen3 switch overlay uses: tile (12,0), 7×7.
    local boxX, boxY, boxSize = 96, 0, 56
    local scale = 1
    if type(battle.picScale) == "function" then
        local path = battle.enemyTrainerPath
            or (battle.trainer and (battle.trainer.picJessieJames or battle.trainer.pic))
        local ok, value = pcall(battle.picScale, battle, path, nil, false)
        if ok and tonumber(value) then
            scale = tonumber(value)
        end
    end
    local px = boxX + (boxSize - iw * scale) / 2
    local py = boxY + (boxSize - ih * scale)
    px = px + (1 - t) * boxSize

    local g = love.graphics
    g.push("all")
    g.setColor(1, 1, 1, 1)
    local drew = false
    local okPal, Palettes = pcall(require, "src.world.gen2.Palettes")
    local okGbc, GbcPalette = pcall(require, "src.render.GbcPalette")
    local class = battle.enemyTrainerClass
        or (battle.trainer and (battle.trainer.class or battle.trainer.id))
    local colors = okPal and battle.palettes and type(Palettes.trainerColors) == "function"
        and Palettes.trainerColors(battle.palettes, class) or nil
    local function body()
        g.draw(img, px, py, 0, scale, scale)
    end
    if colors and okGbc and GbcPalette and type(GbcPalette.with) == "function"
        and (type(GbcPalette.available) ~= "function" or GbcPalette.available()) then
        drew = pcall(GbcPalette.with, colors, body)
    end
    if not drew then
        body()
    end
    g.pop()
end

-- Speech-bubble paint + ownership. Tagging queue rows stays in main.lua.
local Bubbles = {}

local function fieldCompact(battle)
    return hostCall("fieldCompactActive", battle) and true or false
end

function Bubbles.wrapText(text, maxPx)
    local font = getFont()
    local lines = {}
    local raw = tostring(text or ""):gsub("\v", "\n")
    if not (font and type(font.width) == "function") then
        for chunk in (raw .. "\n"):gmatch("(.-)\n") do
            chunk = chunk:match("^%s*(.-)%s*$") or chunk
            if chunk ~= "" then
                lines[#lines + 1] = chunk
            end
        end
        return lines
    end
    local function flushWord(word)
        while word ~= "" do
            if font.width(word) <= maxPx then
                return word
            end
            local cut = 1
            while cut < #word and font.width(word:sub(1, cut + 1)) <= maxPx do
                cut = cut + 1
            end
            if cut < 1 then
                cut = 1
            end
            lines[#lines + 1] = word:sub(1, cut)
            word = word:sub(cut + 1)
        end
        return ""
    end
    for chunk in (raw .. "\n"):gmatch("(.-)\n") do
        chunk = chunk:match("^%s*(.-)%s*$") or chunk
        if chunk ~= "" then
            local line = ""
            for word in chunk:gmatch("%S+") do
                local trial = (line == "") and word or (line .. " " .. word)
                if font.width(trial) <= maxPx then
                    line = trial
                else
                    if line ~= "" then
                        lines[#lines + 1] = line
                    end
                    line = flushWord(word)
                end
            end
            if line ~= "" then
                lines[#lines + 1] = line
            end
        end
    end
    return lines
end

function Bubbles.fieldPopupText(text)
    local s = tostring(text or ""):gsub("\v", "\n")
        :match("^%s*(.-)%s*$") or ""
    -- Keep short status callouts, but leave ordinary dialogue readable.
    local flat = s:gsub("\n", " "):gsub("%s+", " ")
    local upper = flat:upper()
    local stat = upper:match("^.-'S%s+(.+)%s+GREATLY FELL!?$")
        or upper:match("^.-'S%s+(.+)%s+FELL!?$")
    if stat then return stat .. " DOWN!" end
    stat = upper:match("^.-'S%s+(.+)%s+ROSE SHARPLY!?$")
        or upper:match("^.-'S%s+(.+)%s+GREATLY ROSE!?$")
        or upper:match("^.-'S%s+(.+)%s+ROSE!?$")
    if stat then return stat .. " UP!" end
    local move = upper:match("^.- USED%s+(.+)!$")
    if move then return move .. "!" end
    if upper:find("SUPER EFFECTIVE", 1, true) then return "SUPER EFFECTIVE!" end
    if upper:find("NOT VERY EFFECTIVE", 1, true) then return "NOT VERY EFFECTIVE!" end
    if upper:find("CRITICAL HIT", 1, true) then return "CRITICAL HIT!" end
    if upper:find("BUT IT MISSED", 1, true)
        or upper:find("ATTACK MISSED", 1, true) then
        return "MISSED THE TARGET!"
    end
    if upper:find("NO EFFECT", 1, true) then return "NO EFFECT!" end
    if upper:find("REGAINED HEALTH", 1, true) then return "HEALED!" end
    return s
end

function Bubbles.visibleText(battle)
    local cur = battle and battle.current
    local text
    if cur and cur.text and cur.text ~= "" then
        text = cur.text
    else
        text = (battle and battle._arLastBubbleText) or ""
    end
    if fieldCompact(battle) then
        return Bubbles.fieldPopupText(text)
    end
    return text
end

function Bubbles.draw(battle, side)
    if not side or not love or not love.graphics then
        return
    end
    local font = getFont()
    if not font then
        return
    end
    local text = Bubbles.visibleText(battle)
    if text == "" then
        return
    end
    -- FIELD: trainer speech belongs on the tinted foe strip, not here.
    if fieldCompact(battle) then
        local fbv = host.FieldBattleViewer
        local Callouts = fbv and fbv.Callouts
        local session = hostCall("liveFieldSession", battle)
        local raw = (battle.current and battle.current.text)
            or battle._arLastBubbleText or text
        if Callouts and type(Callouts.isTrainerSpeech) == "function"
            and Callouts.isTrainerSpeech(raw) then
            -- Already shown (or about to show) on the attack/react beat.
            return
        end
        if session and type(Callouts) == "table"
            and type(Callouts.ownsText) == "function"
            and (Callouts.ownsText(session, raw)
                or Callouts.ownsText(session, text)) then
            return
        end
        if side == "foe" then
            side = "narrator"
        end
    end
    local g = love.graphics
    local narrator = (side == "narrator")
    local fieldToast = fieldCompact(battle)
    -- FIELD keeps a wide, readable bottom bubble (not a tiny tip).
    local maxInner = fieldToast and 144 or (narrator and 128 or 112)
    local padX, padY = fieldToast and 6 or 4, fieldToast and 4 or 3
    local lineH = 8
    local lines = Bubbles.wrapText(text, maxInner)
    if #lines == 0 then
        lines[1] = ""
    end
    local maxLines = fieldToast and 4 or (narrator and 4 or 5)
    if #lines > maxLines then
        local trimmed = {}
        for i = 1, maxLines - 1 do
            trimmed[i] = lines[i]
        end
        trimmed[maxLines] = "..."
        lines = trimmed
    end
    local contentW = 0
    for i = 1, #lines do
        contentW = math.max(contentW, font.width(lines[i]))
    end
    contentW = math.max(fieldToast and 120 or 32, math.min(maxInner, contentW))
    local bw = contentW + padX * 2
    local bh = padY * 2 + #lines * lineH
    local floorY = 142
    local x, y
    local anchorX, anchorY
    -- FIELD: pin to the bottom so multi-line toasts stay readable.
    if fieldToast then
        x = math.floor((160 - bw) / 2)
        y = floorY - bh
        if y < 1 then y = 1 end
        battle._arNarratorTop = y
    elseif fieldCompact(battle) and not narrator then
        local wanted = (side == "foe") and "enemy" or "player"
        local ow = battle.game and battle.game.overworld
        for i = 1, #(ow and ow.entities or {}) do
            local ent = ow.entities[i]
            if ent and ent._arFieldBattler and ent._arFieldSide == wanted
                and ent._fieldScreenX and ent._fieldScreenY then
                anchorX, anchorY = ent._fieldScreenX, ent._fieldScreenY
                break
            end
        end
    end
    if fieldToast then
        -- already placed
    elseif anchorX then
        x = math.floor(anchorX - bw / 2)
        y = math.floor(anchorY - bh - 9)
        x = math.max(1, math.min(159 - bw, x))
    elseif narrator then
        x = math.floor((160 - bw) / 2)
        y = floorY - bh
    elseif side == "foe" then
        x = 160 - bw - 1
        y = floorY - bh
    else
        x = 1
        y = floorY - bh
    end
    if y < 1 then
        y = 1
    end

    local totalGlyphs = 0
    local encoded = {}
    for i = 1, #lines do
        encoded[i] = font.encode(lines[i])
        totalGlyphs = totalGlyphs + #encoded[i]
    end
    local shownBudget = totalGlyphs
    if battle.total and battle.total > 0 and battle.charIndex then
        shownBudget = math.floor(totalGlyphs * (battle.charIndex / battle.total) + 0.5)
    end

    -- Classic text-box look: white fill, double black border.
    -- FIELD: the tinted foe strip owns threat red. This slab stays white
    -- so "Enemy used X!" / switch prompts are not a second red order.
    local threat = not fieldToast and (
        battle._arLastBubbleThreat == true
        or (battle.current and battle.current.arThreatToast == true)
    )
    local fillR, fillG, fillB = 1, 1, 1
    if threat then
        fillR, fillG, fillB = 1.00, 0.78, 0.74
    end
    g.push("all")
    g.setColor(fillR, fillG, fillB, 1)
    g.rectangle("fill", x, y, bw, bh)
    g.setColor(0, 0, 0, 1)
    g.rectangle("line", x + 0.5, y + 0.5, bw - 1, bh - 1)
    g.rectangle("line", x + 1.5, y + 1.5, bw - 3, bh - 3)
    if anchorX then
        local tailX = math.max(x + 5, math.min(x + bw - 5, anchorX))
        g.setColor(fillR, fillG, fillB, 1)
        g.polygon("fill", tailX - 4, y + bh - 1,
            tailX + 4, y + bh - 1, anchorX, math.min(anchorY - 2, y + bh + 6))
        g.setColor(0, 0, 0, 1)
        g.line(tailX - 4, y + bh - 1,
            anchorX, math.min(anchorY - 2, y + bh + 6))
        g.line(anchorX, math.min(anchorY - 2, y + bh + 6),
            tailX + 4, y + bh - 1)
    elseif not narrator then
        if side == "foe" then
            g.setColor(fillR, fillG, fillB, 1)
            g.polygon("fill", x + bw - 12, y + 1, x + bw - 4, y - 5, x + bw - 20, y + 1)
            g.setColor(0, 0, 0, 1)
            g.line(x + bw - 12, y + 1, x + bw - 4, y - 5)
            g.line(x + bw - 4, y - 5, x + bw - 20, y + 1)
        else
            g.setColor(fillR, fillG, fillB, 1)
            g.polygon("fill", x + 12, y + 1, x + 4, y - 5, x + 20, y + 1)
            g.setColor(0, 0, 0, 1)
            g.line(x + 12, y + 1, x + 4, y - 5)
            g.line(x + 4, y - 5, x + 20, y + 1)
        end
    end

    local textX = x + padX
    g.setColor(0, 0, 0, 1)
    local left = shownBudget
    local ty = y + padY
    for i = 1, #lines do
        local codes = encoded[i]
        local tx = textX
        for j = 1, #codes do
            if left <= 0 then
                break
            end
            font.drawCode(codes[j], tx, ty)
            tx = tx + (font.advanceOf(codes[j]) or 8)
            left = left - 1
        end
        ty = ty + lineH
        if left <= 0 then
            break
        end
    end
    if (battle.msgWaiting or battle.msgPrompt) and (battle.frame or 0) % 60 < 30
        and (not fieldCompact(battle) or battle._arFieldToastPaused) then
        font.drawCode(0xED, x + bw - 10, y + bh - 9)
    end
    if fieldCompact(battle) and battle._arFieldToastPaused
        and type(font.draw) == "function" then
        g.setColor(0, 0, 0, 1)
        font.draw("II", x + 2, y + 1)
    end
    g.setColor(1, 1, 1, 1)
    g.pop()
end

-- SPEECH BUBBLE mode: all battle dialogue rides in bubbles; classic box hidden.
function Bubbles.sideActive(battle)
    if not opt("speech_bubbles") or type(battle) ~= "table" then
        return nil
    end
    if battle.phase ~= "messages" then
        battle._arLastBubble = nil
        battle._arLastBubbleText = nil
        battle._arLastBubbleThreat = nil
        return nil
    end
    local cur = battle.current
    if cur and cur.text and cur.text ~= "" then
        local side = cur.bubble
        if not side then
            side = hostCall("inferBubbleSide", battle, cur.text) or "narrator"
            cur.bubble = side
        end
        battle._arLastBubble = side
        battle._arLastBubbleText = cur.text
        -- Incoming foe move announce → reddish toast (QoL threat cue).
        local cue = cur.arFieldCue
        local threat = cur.arThreatToast == true
        if not threat and cue and cue.side == "enemy" and cue.kind == "attack" then
            threat = true
        end
        if not threat then
            local mon, move = hostCall("parseUsedMoveText", cur.text)
            if mon and move then
                local _, isEnemy = hostCall("stripEnemyPrefix", mon)
                threat = isEnemy and true or false
            end
        end
        battle._arLastBubbleThreat = threat and true or nil
        return side
    end
    -- Keep the last bubble up through move anim / CONT waits (pokered keeps
    -- the announce text visible while the anim plays).
    if battle._arLastBubbleText and (battle.animPlaying or battle.msgHold
            or battle.msgWaiting or battle.msgPrompt
            or (battle.shown and #battle.shown > 0)) then
        return battle._arLastBubble
    end
    battle._arLastBubble = nil
    battle._arLastBubbleText = nil
    battle._arLastBubbleThreat = nil
    return nil
end

function Bubbles.stackedPromptActive(battle)
    local fbv = host.FieldBattleViewer
    local Compat = fbv and fbv.Compat
    return Compat and type(Compat.fieldAllowsStackedBottomUI) == "function"
        and Compat.fieldAllowsStackedBottomUI(battle)
end

function Bubbles.ownDialogue(battle)
    if not opt("speech_bubbles") or type(battle) ~= "table" then
        return false
    end
    -- Learn-move / YES-NO overlays paint through the classic box path
    -- (UIVisibility asks the enclosing battle). Don't hide them.
    if Bubbles.stackedPromptActive(battle) then
        return false
    end
    if battle.phase ~= "messages" then
        return false
    end
    if Bubbles.sideActive(battle) then
        return true
    end
    return battle.current ~= nil
        or battle.animPlaying
        or battle.msgHold
        or battle.msgWaiting
        or battle.msgPrompt
        or (battle.shown and #battle.shown > 0)
end

-- Keep drawTextArea lifecycle (scroll / typewriter) but paint nothing.
function Bubbles.runDrawInvisible(fn, self, ...)
    if not (love and love.graphics and type(fn) == "function") then
        if type(fn) == "function" then
            return fn(self, ...)
        end
        return
    end
    local g = love.graphics
    g.push("all")
    g.setScissor(0, 0, 0, 0)
    local ok, a, b, c = pcall(fn, self, ...)
    g.pop()
    if not ok then
        error(a, 0)
    end
    return a, b, c
end

Chrome.Banter = Banter
Chrome.Bubbles = Bubbles

return Chrome
