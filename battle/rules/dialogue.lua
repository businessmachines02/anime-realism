-- Battle dialogue — callout rewrite, say wraps, banter enqueue.
--
-- Bubble paint and trainer cameo live in chrome/bubbles.lua.
-- FIELD world-anchored trainer strips live in field/chrome/callouts.lua.

local Dialogue = {}
local host = {}
local Chrome

function Dialogue.attachChrome(mod)
    if type(mod) == "table" then
        Chrome = mod
        Dialogue.Banter = Chrome.Banter
        Dialogue.Bubbles = Chrome.Bubbles
        if type(Chrome.bind) == "function" and type(host) == "table" then
            Chrome.bind(host)
        end
    end
    return Dialogue
end

function Dialogue.bind(h)
    if type(h) == "table" then
        for k, v in pairs(h) do
            host[k] = v
        end
        if Chrome and type(Chrome.bind) == "function" then
            Chrome.bind(host)
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

local function startBanter(battle, line)
    local Banter = Dialogue.Banter
    if Banter and type(Banter.start) == "function" then
        Banter.start(battle, line)
    end
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
    elseif kind == "cover" then
        add(strings().COVER_CALLS, 1)
        add(strings().DODGE_SCENE[scene], 2)
    elseif kind == "commit" then
        add(strings().COMMIT_CALLS, 1)
    elseif kind == "entrench" or kind == "entrench_hold" then
        add(strings().STAY_ENTRENCHED_CALLS, 1)
        add(strings().BRACE_SCENE[scene], 2)
    elseif kind == "entrench_break" then
        add(strings().BREAK_ENTRENCH_CALLS, 1)
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
        startBanter(battle, line)
        return
    end
    local item = { text = line, arBanter = true }
    if not hostCall("markBubbleWait", item, "foe", true, battle) then
        item.auto = true
        item.autoDelay = strings().CALLOUT_AUTO_DELAY
    end
    table.insert(battle.queue, 1, item)
    startBanter(battle, line)
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
        startBanter(battle, line)
        return
    end
    local item = { text = line, arBanter = true }
    if not hostCall("markBubbleWait", item, "foe", true, battle) then
        item.auto = true
        item.autoDelay = strings().CALLOUT_AUTO_DELAY
    end
    table.insert(battle.queue, item)
    startBanter(battle, line)
end


return Dialogue
