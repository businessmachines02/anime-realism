-- Battle dialogue chrome — trainer banter cameo + speech-bubble paint.
--
-- Callout rewrite, say wraps, and banter enqueue live here.
-- FIELD world-anchored trainer strips live in
-- field/chrome/callouts.lua. This module is the packed BanterCameo + bubble
-- HUD tables, injected via Dialogue.bind(host).

local Dialogue = {}
local host = {}

function Dialogue.bind(h)
    if type(h) == "table" then
        for k, v in pairs(h) do
            host[k] = v
        end
    end
    return Dialogue
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

local function strings()
    return host.S or {}
end

local function pickLine(lines)
    if type(lines) ~= "table" then
        return nil
    end
    local n = #lines
    if n == 0 then
        return nil
    end
    local r = (love and love.math and love.math.random) or math.random
    return lines[r(n)]
end

function Dialogue.isGrewToLevelText(text)
    local s = tostring(text or ""):lower()
    return s:find("grew", 1, true) and s:find("level", 1, true)
end

function Dialogue.parseUsedMoveText(text)
    local s = tostring(text or "")
    local mon, move = s:match("^([^\n]+)\nused ([^\n!]+)!$")
    if mon and move and mon ~= "" and move ~= "" then
        return mon, move
    end
    return nil
end

function Dialogue.stripEnemyPrefix(mon)
    local bare = tostring(mon or ""):match("^[Ee]nemy%s+(.+)$")
    if bare and bare ~= "" then
        return bare, true
    end
    return mon, false
end

function Dialogue.formatCall(template, a, b, c)
    local _, n = tostring(template or ""):gsub("%%s", "")
    if n <= 0 then
        return template
    end
    if n >= 3 then
        return template:format(a, b, c)
    end
    if n >= 2 then
        return template:format(a, b)
    end
    return template:format(a)
end

function Dialogue.pickFormatted(templates, a, b, c)
    local t = pickLine(templates)
    if not t then
        return nil
    end
    return Dialogue.formatCall(t, a, b, c)
end

local function battleGlyphLen(s)
    local n = 0
    for _ in tostring(s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
    end
    return n
end

local function fitsBattleLine(s)
    local cols = tonumber(strings().BATTLE_TEXT_COLS) or 18
    return battleGlyphLen(s) <= cols
end

function Dialogue.formatEnemyMoveCall(trainer, mon, move)
    mon = tostring(mon or "POKéMON")
    move = tostring(move or "MOVE")
    if trainer and trainer ~= "" then
        local head = tostring(trainer) .. ":"
        local one = mon .. ", use " .. move .. "!"
        if fitsBattleLine(head) and fitsBattleLine(one) then
            return head .. "\n" .. one
        end
        local mid = mon .. ", use"
        local tail = move .. "!"
        if fitsBattleLine(head) and fitsBattleLine(mid) and fitsBattleLine(tail) then
            return head .. "\n" .. mid .. "\n" .. tail
        end
        local short = mon .. "! " .. move .. "!"
        if fitsBattleLine(head) and fitsBattleLine(short) then
            return head .. "\n" .. short
        end
        if fitsBattleLine(head) and fitsBattleLine(mon .. "!") and fitsBattleLine(tail) then
            return head .. "\n" .. mon .. "!\n" .. tail
        end
        return head .. "\n" .. mon .. "!\v" .. move .. "!"
    end
    local a = mon .. "!\nUse " .. move .. "!"
    if fitsBattleLine(mon .. "!") and fitsBattleLine("Use " .. move .. "!") then
        return a
    end
    if fitsBattleLine(mon .. ", use") and fitsBattleLine(move .. "!") then
        return mon .. ", use\n" .. move .. "!"
    end
    return mon .. "!\n" .. move .. "!"
end

function Dialogue.isExpGainDialogue(text)
    local s = tostring(text or "")
    if s == "" or Dialogue.isGrewToLevelText(s) then
        return false
    end
    local lower = s:lower()
    if lower:find("exp. points", 1, true) or lower:find("exp points", 1, true) then
        return true
    end
    if lower:find("experience", 1, true) then
        return true
    end
    if lower:find("exp.all", 1, true) or lower:find("exp all", 1, true) then
        return true
    end
    if lower:find("gained", 1, true)
        and (lower:find("exp", 1, true) or lower:find("boosted", 1, true)) then
        return true
    end
    if lower:find("exp", 1, true) and lower:find("point", 1, true) then
        return true
    end
    return false
end

function Dialogue.rewriteLevelUpText(text)
    local S = strings()
    if opt("generic_level_up") and Dialogue.isGrewToLevelText(text) then
        return pickLine(S.LEVEL_UP_LINES) or "Your POKéMON has\ngrown stronger!"
    end
    return text
end

function Dialogue.rewriteMoveCallText(battle, text)
    local mon, move = Dialogue.parseUsedMoveText(text)
    if not mon then
        return text
    end
    local bare, isEnemy = Dialogue.stripEnemyPrefix(mon)
    if isEnemy and hostCall("enemyStatusLocked", battle) then
        return text
    end
    if (not isEnemy) and hostCall("playerStatusLocked", battle) then
        return text
    end
    if not isEnemy and hostCall("playerHasCounter", battle) then
        local line = hostCall("formatAutoCounterCall", bare, move)
        if line then
            return line
        end
    end
    if not opt("anime_move_calls") then
        return text
    end
    local S = strings()
    if isEnemy then
        local kind = battle and battle.kind
        if kind ~= "trainer" and kind ~= "link" then
            return text
        end
        local trainer = hostCall("personalTrainerName", battle)
        if trainer then
            local fitted = Dialogue.formatEnemyMoveCall(trainer, bare, move)
            if fitted then
                return fitted
            end
            return Dialogue.pickFormatted(S.TRAINER_MOVE_CALLS, trainer, bare, move)
                or (trainer .. ":\n" .. bare .. ", use " .. move .. "!")
        end
        return Dialogue.formatEnemyMoveCall(nil, bare, move)
            or Dialogue.pickFormatted(S.FOE_MOVE_CALLS, bare, move)
            or (bare .. "!\nUse " .. move .. "!")
    end
    return Dialogue.pickFormatted(S.PLAYER_MOVE_CALLS, bare, move)
        or (bare .. "!\nUse " .. move .. "!")
end

function Dialogue.rewriteBattleText(battle, text)
    text = Dialogue.rewriteLevelUpText(text)
    return Dialogue.rewriteMoveCallText(battle, text)
end

-- BattleState.say wraps: rewrite + bubble tag + FIELD cue stamp.
-- Host supplies FIELD/REACT helpers so this file does not import field/.
function Dialogue.wrapBattleSay(methodName)
    local BattleState = host.BattleState
    local patched = host.patched
    if type(BattleState) ~= "table" or type(methodName) ~= "string" then
        return
    end
    BattleState._arAnimeSayPatched = BattleState._arAnimeSayPatched or {}
    if BattleState._arAnimeSayPatched[methodName] then
        return
    end
    local original = BattleState[methodName]
    if type(original) ~= "function" then
        return
    end
    if patched and patched[original] then
        return
    end
    local wrapped = function(self, text, ...)
        if Dialogue.isExpGainDialogue(text) then
            return
        end
        local mon, moveName = Dialogue.parseUsedMoveText(text)
        local bare, isEnemy = nil, false
        if mon then
            bare, isEnemy = Dialogue.stripEnemyPrefix(mon)
        end
        local reaction, buffs, trackTemp, fieldCue = hostCall("reactionAfterMoveAnnounce", self, text)
        local dodgeWhiff
        text, dodgeWhiff = hostCall("rewriteDodgeMissText", self, text)
        if dodgeWhiff == nil and type(text) == "table" then
            -- host forgot to return two values
        end
        local displayText = Dialogue.rewriteBattleText(self, text)
        local pendingNpcOrder
        if hostCall("fieldFlowsText", self) and mon and isEnemy then
            local narrative = Dialogue.rewriteLevelUpText(text)
            if displayText ~= narrative then
                pendingNpcOrder = displayText
                displayText = narrative
            end
        end
        local result = original(self, displayText, ...)
        if mon and moveName then
            local moveDef = hostCall("findMoveByName", self, moveName)
            if moveDef then
                local damaging = (moveDef.power or 0) > 0
                    and moveDef.category ~= "status"
                local cat = hostCall("foeMoveIsSpecial", moveDef) and "special" or "physical"
                local kind = damaging and "attack" or "status"
                local moveId = moveDef.id
                    or tostring(moveName):upper():gsub("[^A-Z0-9]+", "_")
                hostCall("tagLatestQueueFieldCue", self, isEnemy and "enemy" or "player",
                    kind, damaging and cat or nil, moveDef.type, moveId)
            end
        end
        if pendingNpcOrder then
            if not hostCall("stampNpcOrderOnAnnounce", self, displayText, pendingNpcOrder) then
                hostCall("pushNpcCallout", self, pendingNpcOrder, true, {
                    kind = "order",
                    urgent = true,
                })
            end
        end
        if dodgeWhiff then
            local item = self.queue and self.queue[self.nextInsert]
            if type(item) == "table" and item.text then
                item.arDodgeWhiff = true
                hostCall("tagFieldCue", item, "player", "dodge")
            end
        end
        if dodgeWhiff then
            hostCall("maybeQueueSameTurnCounter", self)
        end
        if opt("speech_bubbles") then
            if mon then
                local locked = isEnemy and hostCall("enemyStatusLocked", self)
                    or ((not isEnemy) and hostCall("playerStatusLocked", self))
                if locked or (hostCall("fieldFlowsText", self) and isEnemy) then
                    hostCall("tagQueueBubble", self, "narrator")
                else
                    hostCall("tagQueueBubble", self, isEnemy and "foe" or "player")
                end
            else
                local side = hostCall("inferBubbleSide", self, text) or "narrator"
                local item = self.queue and self.queue[self.nextInsert]
                local keepAuto = item and item.auto == true
                hostCall("tagQueueBubble", self, side, not keepAuto)
            end
        end
        if hostCall("fieldFlowsText", self) then
            local item = self.queue and self.queue[self.nextInsert]
            if item and item.text then
                hostCall("applyFieldToastAuto", item)
            end
        end
        do
            local api = BattleState._arSendBanterApi
            if api and type(api.enqueue) == "function" then
                api.enqueue(self, text)
            else
                hostCall("maybeEnqueueSendBanter", self, text)
            end
        end
        if (methodName == "sayNextAuto" or methodName == "sayAuto")
            and (hostCall("willShowCalloutPick", self, text)
                or hostCall("willShowCounterPick", self, text))
            and not hostCall("fieldFlowsText", self) then
            local item = self.queue and self.queue[self.nextInsert]
            if item and item.text then
                item.auto = nil
                item.autoDelay = nil
            end
        end
        if mon and not isEnemy then
            hostCall("resolveCoverOnPlayerAttack", self, bare or hostCall("playerMonName", self))
            local st = hostCall("momentumState", self)
            if type(st) == "table" and st.sameTurnCounterStrike then
                st.sameTurnCounterStrike = nil
            elseif type(st) == "table" then
                local moveDef = moveName and hostCall("findMoveByName", self, moveName)
                local damaging = moveDef and (moveDef.power or 0) > 0
                    and moveDef.category ~= "status"
                if damaging and (st.sameTurnCounterQueued or st.offerSameTurnCounter) then
                    st.pendingFoeReaction = { moveDef = moveDef }
                elseif damaging then
                    local foeLine, foeBuffs, foeTrack, failNarr =
                        hostCall("tryFoeCoverReaction", self, moveDef)
                    if foeLine then
                        local foeBubble = hostCall("isDodgeFailNarrator", foeLine) and "narrator" or "foe"
                        local foeCue = hostCall("fieldCueForFoeCover", foeBuffs, foeLine)
                        hostCall("enqueueReactWithAttack", self, foeLine,
                            strings().CALLOUT_AUTO_DELAY or 55, foeBubble, foeCue)
                        hostCall("applyCalloutBuffs", self, foeBuffs, foeTrack)
                        if foeTrack and foeBuffs then
                            local braced = false
                            for i = 1, #foeBuffs do
                                if foeBuffs[i].stat == "defense" then
                                    braced = true
                                    break
                                end
                            end
                            if braced then
                                hostCall("enqueueBraceAnim", self, { foe = true })
                            end
                        end
                    end
                    if failNarr then
                        hostCall("enqueueAutoAfter", self, failNarr,
                            strings().CALLOUT_AUTO_DELAY or 55, "narrator",
                            { side = "enemy", kind = "hit" })
                    end
                end
            end
        end
        if reaction then
            local bubbleSide = "narrator"
            if not hostCall("isDodgeFailNarrator", reaction) then
                bubbleSide = isEnemy and "foe" or "player"
            end
            hostCall("enqueueReactWithAttack", self, reaction,
                strings().CALLOUT_AUTO_DELAY or 55, bubbleSide, fieldCue)
            hostCall("applyCalloutBuffs", self, buffs, trackTemp)
            local st = peek(self)
            if isEnemy and st and st.temp and trackTemp then
                if st.temp.cover then
                    if st.temp.hidAway then
                        hostCall("tryVanishEvasion", self, hostCall("playerMonName", self))
                    end
                    hostCall("enqueueDodgeHideAnim", self, nil)
                else
                    hostCall("enqueueBraceAnim", self, {
                        entrenched = st.temp.entrenched == true,
                    })
                end
            end
        end
        return result
    end
    if patched then
        patched[original] = true
        patched[wrapped] = true
    end
    BattleState._arAnimeSayPatched[methodName] = true
    BattleState[methodName] = wrapped
end


-- Call pools + send/idle banter enqueue (classic queue).
function Dialogue.buildCallPool(kind, battle)
    local style = hostCall("calloutStyle")
    local scene = hostCall("battleScene", battle)
    local types = hostCall("playerTypeSet", battle) or {}
    local pool = {}
    -- Each entry: { line = "...", boost = 1|2 } for dodge/brace tiers.

    local function add(list, boost)
        if type(list) ~= "table" then
            return
        end
        for i = 1, #list do
            pool[#pool + 1] = { line = list[i], boost = boost or 1 }
        end
    end

    if kind == "dodge" then
        add(strings().DODGE_STYLE[style] or strings().DODGE_STYLE.AUTO, style == "SHOWY" and 2 or 1)
        add(strings().DODGE_SCENE[scene], 2)
        for ty, on in pairs(types) do
            if on then
                add(strings().DODGE_TYPE[ty], 2)
            end
        end
    elseif kind == "brace" then
        add(strings().BRACE_STYLE[style] or strings().BRACE_STYLE.AUTO, 1)
        add(strings().BRACE_SCENE[scene], 1)
        for ty, on in pairs(types) do
            if on then
                add(strings().BRACE_TYPE[ty], 2)
            end
        end
    elseif kind == "counter" then
        local lines = strings().PLAYER_COUNTER_CALLS[style] or strings().PLAYER_COUNTER_CALLS.AUTO
        local defDrop = (style == "SHOWY" or style == "BOLD") and 2 or 1
        add(lines, defDrop)
    end

    return pool
end

function Dialogue.pickCallEntry(kind, battle, monName, moveName)
    local pool = Dialogue.buildCallPool(kind, battle)
    if #pool == 0 then
        return nil, 1
    end
    local entry = pickLine(pool)
    if not entry then
        return nil, 1
    end
    local line = Dialogue.formatCall(entry.line, monName, moveName)
    return line, entry.boost or 1
end


-- Personality buckets from oppClass / trainer name (Gen 1 classes).
function Dialogue.trainerPersona(battle)
    local cls = tostring(battle and battle.oppClass or ""):upper()
    local name = tostring(battle and battle.trainer and battle.trainer.name or ""):upper()
    local blob = cls .. " " .. name
    local function has(s)
        return blob:find(s, 1, true) ~= nil
    end
    if has("RIVAL") then
        return "rival"
    end
    if has("ROCKET") or has("BURGLAR") or has("GIOVANNI") then
        return "evil"
    end
    if has("BROCK") or has("MISTY") or has("SURGE") or has("ERIKA")
        or has("KOGA") or has("SABRINA") or has("BLAINE")
        or has("LORELEI") or has("BRUNO") or has("AGATHA") or has("LANCE") then
        return "gym"
    end
    if has("YOUNGSTER") or has("BUG_CATCHER") or has("BUG CATCHER")
        or has("LASS") or has("JR_TRAINER") or has("JR.TRAINER")
        or has("SCHOOL") then
        return "kid"
    end
    if has("COOLTRAINER") or has("ACE") or has("BLACKBELT")
        or has("BLACKBELT") or has("BIKER") or has("CUE_BALL")
        or has("BIRD_KEEPER") or has("TAMER") then
        return "cocky"
    end
    if has("CHANNELER") or has("GHOST") then
        return "spooky"
    end
    if has("SUPER_NERD") or has("SCIENTIST") or has("POKEMANIAC")
        or has("ENGINEER") or has("PSYCHIC") then
        return "nerd"
    end
    if has("GENTLEMAN") or has("BEAUTY") or has("SAILOR")
        or has("HIKER") or has("FISHER") or has("SWIMMER") then
        return "chill"
    end
    return "generic"
end

function Dialogue.banterSpeaker(battle)
    return hostCall("personalTrainerName", battle)
        or (battle.trainer and battle.trainer.name)
        or "TRAINER"
end

-- speaker (+ optional mon). Persona lines when you or they send out.
-- player lines: (speaker, your mon). enemy lines: (speaker, their mon).

function Dialogue.rollTrainerBanter()
    local r = (love and love.math and love.math.random) or math.random
    return r() < 0.70
end

function Dialogue.battlerHpRatio(battler)
    local mon = battler and battler.mon
    local max = mon and mon.stats and mon.stats.hp
    if not max or max <= 0 then
        return 1
    end
    return (mon.hp or 0) / max
end

-- Build a context-weighted idle pool (ahead/behind/low HP/long fight).

function Dialogue.pickContextualIdleLine(battle, persona, speaker)
    local pack = strings().BANTER[persona] or strings().BANTER.generic
    local pools = {}
    local function add(list, weight)
        if type(list) ~= "table" or #list == 0 then
            return
        end
        weight = weight or 1
        for _ = 1, weight do
            pools[#pools + 1] = list
        end
    end
    add(pack.idle or strings().BANTER.generic.idle, 1)
    local pr = Dialogue.battlerHpRatio(battle.player)
    local er = Dialogue.battlerHpRatio(battle.enemy)
    local turn = tonumber(battle.turnCount) or 0
    if er > pr + 0.18 then
        add(pack.ahead, persona == "rival" and 3 or 2)
    elseif pr > er + 0.18 then
        add(pack.behind, persona == "rival" and 3 or 2)
    end
    if pr <= 0.35 then
        add(pack.player_weak, persona == "rival" and 3 or 2)
    end
    if er <= 0.35 then
        add(pack.self_weak, persona == "rival" and 3 or 2)
    end
    if turn >= 6 then
        add(pack.long, persona == "rival" and 2 or 1)
    end
    if #pools == 0 then
        return Dialogue.pickFormatted(strings().BANTER.generic.idle, speaker)
    end
    local r = (love and love.math and love.math.random) or math.random
    local list = pools[r(1, #pools)]
    local ms = hostCall("momentumState", battle)
    -- Prefer a line we didn't just use.
    for _ = 1, 6 do
        local line = Dialogue.pickFormatted(list, speaker)
        if line and line ~= ms.lastIdleBanterLine then
            return line
        end
    end
    return Dialogue.pickFormatted(list, speaker)
end

-- True send-outs only. Anime move callouts like "Go! PIKACHU!\nTHUNDER!"
-- must NOT arm send-in banter (they share the "Go! " prefix).
function Dialogue.isPlayerSendOutText(text)
    local s = tostring(text or "")
    if s:match("^Go! [^\n]+!$")
        or s:match("^Do it! [^\n]+!$")
        or s:match("^Get'm! [^\n]+!$") then
        return true
    end
    local low = s:lower()
    return low:find("enemy's weak", 1, true) ~= nil
        and low:find("get'm!", 1, true) ~= nil
end

function Dialogue.isEnemySendOutText(text)
    return tostring(text or ""):find("sent\nout ", 1, true) ~= nil
end


function Dialogue.queueHasBanter(battle)
    if type(battle) ~= "table" then
        return false
    end
    if battle.current and battle.current.arBanter then
        return true
    end
    local q = battle.queue
    if type(q) ~= "table" then
        return false
    end
    for i = 1, #q do
        if q[i] and q[i].arBanter then
            return true
        end
    end
    return false
end

-- Battle box is 2 lines; extra \n scrolls like separate callouts.
function Dialogue.clampBanterText(line)
    local parts = {}
    for chunk in (tostring(line or "") .. "\n"):gmatch("(.-)\n") do
        chunk = chunk:match("^%s*(.-)%s*$") or chunk
        if chunk ~= "" then
            parts[#parts + 1] = chunk
        end
    end
    if #parts <= 2 then
        return table.concat(parts, "\n")
    end
    local speaker = parts[1]
    local body = table.concat(parts, " ", 2)
    if fitsBattleLine(body) then
        return speaker .. "\n" .. body
    end
    return speaker .. "\n" .. parts[2]
end

function Dialogue.maybeEnqueueSendBanter(battle, originalText)
    if not opt("trainer_banter") or not hostCall("trainerFoeReactionsOn", battle) then
        return
    end
    if type(battle) ~= "table" then
        return
    end
    local aboutPlayer = Dialogue.isPlayerSendOutText(originalText)
    local aboutEnemy = Dialogue.isEnemySendOutText(originalText)
    if not aboutPlayer and not aboutEnemy then
        return
    end
    -- Pending / cooldown live on the battle object so they survive
    -- clearBattleMomentum (battle.started) and stay shared across any
    -- accidental double-wraps of say / updateQueue from hot reload.
    -- Prefer the player's Go! when both foe-send and Go! land in one wave.
    local replacing = battle._arPendingSendBanter
        and aboutPlayer
        and battle._arPendingSendBanter.side == "enemy"
    if battle._arPendingSendBanter and not replacing then
        return
    end
    if not replacing then
        if (battle._arSendBanterCooldown or 0) > 0 then
            return
        end
        if Dialogue.queueHasBanter(battle) then
            return
        end
        if not Dialogue.rollTrainerBanter() then
            return
        end
    end
    -- Do not bake the mon name here. The engine's "Go!" names party[1]
    -- (often the overworld follower). choose_lead and other send-out
    -- mods rebind battle.player after that line is queued.
    battle._arPendingSendBanter = {
        side = aboutPlayer and "player" or "enemy",
        persona = Dialogue.trainerPersona(battle),
        speaker = Dialogue.banterSpeaker(battle),
    }
    battle._arSendBanterArmFrames = 8
    if aboutPlayer and battle.sendingOut then
        battle._arSendBanterSawOut = true
        battle._arSendBanterArmFrames = nil
    elseif aboutEnemy and battle.enemySendingOut then
        battle._arSendBanterSawOut = true
        battle._arSendBanterArmFrames = nil
    end
end
function Dialogue.flushPendingSendBanter(battle)
    if type(battle) ~= "table" then
        return
    end
    if (battle._arSendBanterCooldown or 0) > 0 then
        battle._arSendBanterCooldown = battle._arSendBanterCooldown - 1
    end
    local pending = battle._arPendingSendBanter
    if not pending then
        return
    end

    local function pickerOpen()
        local stack = battle.game and battle.game.stack
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

    local function queueStillHasSendOut()
        local function match(text)
            if pending.side == "player" then
                return Dialogue.isPlayerSendOutText(text)
            end
            return Dialogue.isEnemySendOutText(text)
        end
        if battle.current and match(battle.current.text) then
            return true
        end
        local q = battle.queue
        if type(q) ~= "table" then
            return false
        end
        for i = 1, #q do
            if q[i] and match(q[i].text) then
                return true
            end
        end
        return false
    end

    local function composeLine()
        local persona = pending.persona or Dialogue.trainerPersona(battle)
        local pack = strings().BANTER[persona] or strings().BANTER.generic
        local speaker = pending.speaker or Dialogue.banterSpeaker(battle)
        local line
        if pending.side == "enemy" then
            local mon = hostCall("enemyMonName", battle)
            line = Dialogue.pickFormatted(pack.enemy, speaker, mon)
                or (speaker .. ":\nGo, " .. mon .. "!")
        else
            local mon = hostCall("playerMonName", battle)
            line = Dialogue.pickFormatted(pack.player, speaker, mon)
                or (speaker .. ":\nA " .. mon .. ", huh?!")
        end
        return Dialogue.clampBanterText(line)
    end

    -- choose_lead opens PartyMenu before the real send. Keep waiting so
    -- we name the mon that actually comes out, not party[1].
    if pickerOpen() then
        return
    end
    if queueStillHasSendOut() then
        return
    end
    local sending = (pending.side == "player" and battle.sendingOut)
        or (pending.side == "enemy" and battle.enemySendingOut)
    if sending then
        battle._arSendBanterSawOut = true
        battle._arSendBanterArmFrames = nil
        return
    end
    if hostCall("queueHasPoof", battle) then
        battle._arSendBanterSawOut = true
        battle._arSendBanterArmFrames = nil
        return
    end
    if battle._arSendBanterArmFrames and battle._arSendBanterArmFrames > 0 then
        battle._arSendBanterArmFrames = battle._arSendBanterArmFrames - 1
        return
    end
    -- Ready: send-out finished and POOF is gone. Name the live battler.
    local line = composeLine()
    battle._arPendingSendBanter = nil
    battle._arSendBanterSawOut = nil
    battle._arSendBanterArmFrames = nil
    if type(battle.queue) ~= "table" then
        return
    end
    if Dialogue.queueHasBanter(battle) then
        -- Still consume the pending so a stuck wave can't retry forever.
        battle._arSendBanterCooldown = 120
        return
    end
    battle._arSendBanterDidIntro = true
    battle._arSendBanterCooldown = 120
    if hostCall("pushNpcCallout", battle, line, true, { kind = "banter" }) then
        Banter.start(battle, line)
        return
    end
    local item = { text = line, arBanter = true }
    if not hostCall("markBubbleWait", item, "foe", true, battle) then
        item.auto = true
        item.autoDelay = strings().CALLOUT_AUTO_DELAY
    end
    table.insert(battle.queue, 1, item)
    Banter.start(battle, line)
end

function Dialogue.maybeEnqueueIdleBanter(battle)
    if not opt("trainer_banter") or not hostCall("trainerFoeReactionsOn", battle) then
        return
    end
    if type(battle) ~= "table" or type(battle.queue) ~= "table" then
        return
    end
    local ms = hostCall("momentumState", battle)
    -- Skip while anything cinematic / cover-related is going on.
    if ms.awaitingPick or ms.pendingDamage or ms.againInProgress then
        return
    end
    if battle._arPendingSendBanter or (battle._arSendBanterCooldown or 0) > 0 then
        return
    end
    if Dialogue.queueHasBanter(battle) then
        return
    end
    local t = ms.temp or {}
    if t.picHidden or t.cover or t.entrenched then
        return
    end
    local et = ms.enemyTemp or {}
    if et.cover then
        return
    end
    local turn = tonumber(battle.turnCount) or 0
    if turn < 1 then
        return
    end
    local last = ms.lastIdleBanterTurn or 0
    local persona = Dialogue.trainerPersona(battle)
    local gap = (persona == "rival") and 1 or 2
    if turn - last < gap then
        return
    end
    local chance = (persona == "rival") and 0.48 or 0.20
    local r = (love and love.math and love.math.random) or math.random
    if r() >= chance then
        return
    end
    local speaker = Dialogue.banterSpeaker(battle)
    local line = Dialogue.pickContextualIdleLine(battle, persona, speaker)
        or (speaker .. ":\nCome on!")
    line = Dialogue.clampBanterText(line)
    ms.lastIdleBanterTurn = turn
    ms.lastIdleBanterLine = line
    if hostCall("pushNpcCallout", battle, line, true, { kind = "banter" }) then
        Banter.start(battle, line)
        return
    end
    local item = { text = line, arBanter = true }
    if not hostCall("markBubbleWait", item, "foe", true, battle) then
        item.auto = true
        item.autoDelay = strings().CALLOUT_AUTO_DELAY
    end
    table.insert(battle.queue, item)
    Banter.start(battle, line)
end


Dialogue.Banter = Banter
Dialogue.Bubbles = Bubbles

return Dialogue
