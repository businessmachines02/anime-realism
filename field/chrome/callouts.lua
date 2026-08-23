-- Field battle — standalone foe dialogue box (UI overlay).
--
-- One live shout at a time. Same light glass as the narrator box; lifts
-- above it when both are up. Engine prompts (learn-move / "about to use" /
-- switch) and the command menu dismiss it so a used-move callout cannot
-- linger into your turn.

local Callouts = {}

Callouts.HOLD = 1.6
Callouts.HOLD_ORDER = 1.6
Callouts.HOLD_REACT = 1.6
Callouts.HOLD_BANTER = 1.6
Callouts.FADE = 0.25
Callouts.POP = 0.14
Callouts.MAX_QUEUE = 1
Callouts.MAX_PER_SIDE = 1

Callouts.BOX_X = 4
Callouts.BOX_W = 152
Callouts.VANILLA_Y = 119
Callouts.GAP = 2
Callouts.UI_W = 160
Callouts.UI_H = 144

local function font()
  local ok, Font = pcall(require, "src.render.Font")
  return ok and Font or nil
end

function Callouts.norm(text)
  local flat = tostring(text or ""):lower():gsub("\v", " "):gsub("\n", " ")
  flat = flat:gsub("%s+", " ")
  return flat:match("^%s*(.-)%s*$") or ""
end

-- Engine / narrator lines belong in the vanilla box, not the foe strip.
function Callouts.isTrainerSpeech(text)
  local raw = tostring(text or "")
  if raw == "" then
    return false
  end
  -- "BROCK: …" is always the trainer, even if the body says "too slow".
  if raw:match("^[%w%.%s']+:") then
    return true
  end
  local flat = Callouts.norm(raw)
  local narr = {
    "dodged", "whiffed", "attack missed", "too slow",
    "fainted", "hurt itself", "super effective", "not very effective",
    "critical hit", "sent out", "recoil",
    "about to use", "change pok",
  }
  for i = 1, #narr do
    if flat:find(narr[i], 1, true) then
      return false
    end
  end
  if flat:match("^go! ") then
    return false
  end
  if flat:find(" used ", 1, true) or flat:match("%w used ") then
    return false
  end
  if flat:find("will ", 1, true) and flat:find("change", 1, true) then
    return false
  end
  if flat:find("use ", 1, true) or flat:find("move!", 1, true)
      or flat:find("dodge", 1, true) or flat:find("brace", 1, true)
      or flat:find("get aside", 1, true) or flat:find("hit back", 1, true)
      or flat:find("counter", 1, true) or flat:find("hold firm", 1, true)
      or flat:find("dig in", 1, true) or flat:find("stand firm", 1, true)
      or flat:find("break cover", 1, true) or flat:find("come out", 1, true)
      or flat:find("now!", 1, true) or flat:find("go,", 1, true)
      or flat:find("come on", 1, true) or flat:find("quick,", 1, true)
      or flat:find("strike", 1, true) then
    return true
  end
  -- Generic youngster orders: "Onix! Surf!" / "Onix! Surf, now!"
  if flat:match("^[%w%-']+!%s+[%w%-']+") then
    return true
  end
  return false
end

function Callouts.isEnginePrompt(text)
  local flat = Callouts.norm(text)
  if flat == "" then
    return false
  end
  if flat:find("about to use", 1, true) or flat:find("change pok", 1, true) then
    return true
  end
  -- Level-up move learning (TextBox / YES-NO) must not lose the classic box
  -- to a lingering trainer callout (issues #45 / #36).
  local learn = {
    "trying to learn", "can't learn more", "delete an older",
    "make room for", "abandon learning", "did not learn",
  }
  for i = 1, #learn do
    if flat:find(learn[i], 1, true) then
      return true
    end
  end
  if flat:find(" forgot ", 1, true) then
    return true
  end
  return flat:find("will ", 1, true) ~= nil and flat:find("change", 1, true) ~= nil
end

-- True when the live shout no longer belongs on screen: engine prompt,
-- stacked learn-move / YES-NO, or the player has the command menu again.
function Callouts.shouldHold(battle)
  if not battle then
    return false
  end
  -- REACT HUD sits on the stack as a translucent menu. Wiping the incoming
  -- order there is the flicker: Brock shouts, menu opens, box vanishes.
  if battle._arAwaitingReact then
    return false
  end
  local phase = battle.phase
  if type(phase) == "string" and phase ~= "" and phase ~= "messages" then
    return true
  end
  local live = (battle.current and battle.current.text)
    or battle._arLastBubbleText
  if Callouts.isEnginePrompt(live) then
    return true
  end
  local stack = battle.game and battle.game.stack
  local top = stack and type(stack.top) == "function" and stack:top() or nil
  if not top or top == battle then
    return false
  end
  return top.isOpaque ~= true
end

function Callouts.ownsText(session, text)
  local n = Callouts.norm(text)
  if n == "" then
    return false
  end
  local all = session and session._trainerCallouts
  if not all then
    return false
  end
  for _, q in pairs(all) do
    for i = 1, #q do
      if Callouts.norm(q[i].text) == n then
        return true
      end
    end
  end
  return false
end

function Callouts.holdFor(kind)
  if kind == "react" then
    return Callouts.HOLD_REACT
  end
  if kind == "order" then
    return Callouts.HOLD_ORDER
  end
  if kind == "banter" then
    return Callouts.HOLD_BANTER
  end
  return Callouts.HOLD
end

-- Standalone dialogue box. Sits in the vanilla slot when the white box is
-- down; lifts just above it when both are up.
-- Returns x, y, w, h, placement ("above_box"|"slot").
function Callouts.dockRect(bh, vanillaTop)
  bh = math.max(23, tonumber(bh) or 23)
  local top = tonumber(vanillaTop)
  local y, place
  if top then
    y = math.floor(top - Callouts.GAP - bh)
    place = "above_box"
  else
    y = Callouts.VANILLA_Y
    if y + bh > 142 then
      y = 142 - bh
    end
    place = "slot"
  end
  if y < 2 then
    y = 2
  end
  return Callouts.BOX_X, y, Callouts.BOX_W, bh, place
end

-- Older tests / callers used world-anchored placement. The strip is docked now.
function Callouts.bubbleRect(_session, _side, _ow, _battle, bw, bh)
  local _, y, w, h, place = Callouts.dockRect(bh or 16, Callouts.VANILLA_Y)
  local width = tonumber(bw) or w
  local x = math.floor((Callouts.UI_W - width) / 2)
  return x, y, nil, nil, place
end

function Callouts.push(session, side, text, opts)
  if not (session and side and side ~= "narrator") then
    return false
  end
  -- Player react orders use this box too (FIELD hides the vanilla white box).
  if side ~= "foe" and side ~= "player" then
    return false
  end
  text = tostring(text or ""):gsub("\v", "\n"):match("^%s*(.-)%s*$") or ""
  if text == "" then
    return false
  end
  opts = type(opts) == "table" and opts or {}
  session._trainerCallouts = session._trainerCallouts or {}
  local q = session._trainerCallouts[side]
  if not q then
    q = {}
    session._trainerCallouts[side] = q
  end
  local n = Callouts.norm(text)
  -- Same line already live: do not restart the hold (re-push used to make
  -- a used-move order linger through the player's next turn).
  if q[1] and Callouts.norm(q[1].text) == n then
    if opts.threat == true then
      q[1].threat = true
    end
    return true
  end
  -- A new shout replaces whatever was showing. Emitted lines are not queued
  -- to play again after the next attack.
  session._trainerCallouts[side] = {
    {
      text = text,
      age = 0,
      hold = tonumber(opts.hold) or Callouts.holdFor(opts.kind),
      threat = opts.threat == true,
      kind = opts.kind,
    },
  }
  return true
end

function Callouts.tick(session, dt, battle)
  local all = session and session._trainerCallouts
  if not all then
    return
  end
  -- Learn-move / menu / switch: drop the live shout. Pausing used to resume
  -- it later on the player's turn (issues #36 / #45).
  if Callouts.shouldHold(battle) then
    session._trainerCallouts = nil
    return
  end
  dt = dt or (1 / 60)
  for side, q in pairs(all) do
    local toast = q[1]
    if toast then
      toast.age = (toast.age or 0) + dt
      local total = (toast.hold or Callouts.HOLD) + Callouts.FADE
      if toast.age >= total then
        table.remove(q, 1)
      end
    end
    if #q == 0 then
      all[side] = nil
    end
  end
end

function Callouts.finish(session)
  if session then
    session._trainerCallouts = nil
  end
end

local function wrapText(Font, text, maxPx)
  local lines = {}
  local raw = tostring(text or ""):gsub("\v", "\n")
  local function flushWord(word)
    while word ~= "" do
      if Font.width(word) <= maxPx then
        return word
      end
      local cut = 1
      while cut < #word and Font.width(word:sub(1, cut + 1)) <= maxPx do
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
        if Font.width(trial) <= maxPx then
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

local function toastAlpha(age, hold)
  age = age or 0
  hold = hold or Callouts.HOLD
  if age < Callouts.POP then
    return age / Callouts.POP
  end
  if age > hold then
    return math.max(0, 1 - (age - hold) / Callouts.FADE)
  end
  return 1
end

local function drawBox(g, Font, text, vanillaTop, alpha)
  if alpha <= 0 then
    return
  end
  local padX, padY = 6, 4
  local lineH = 8
  local maxInner = Callouts.BOX_W - padX * 2
  local lines = wrapText(Font, text, maxInner)
  if #lines == 0 then
    lines[1] = ""
  end
  local maxLines = 3
  if #lines > maxLines then
    local trimmed = {}
    for i = 1, maxLines - 1 do
      trimmed[i] = lines[i]
    end
    trimmed[maxLines] = "..."
    lines = trimmed
  end
  local bh = math.max(23, padY * 2 + #lines * lineH)
  local x, y, bw = Callouts.dockRect(bh, vanillaTop)
  local plateA = (tonumber(Callouts.PLATE_A) or 0.78) * alpha

  g.push("all")
  if type(Callouts.paintPlate) == "function" then
    Callouts.paintPlate(g, x, y, bw, bh, plateA)
  else
    g.setColor(0.98, 0.96, 0.90, plateA)
    g.rectangle("fill", x, y, bw, bh)
    g.setColor(0.18, 0.14, 0.12, math.min(1, plateA + 0.15))
    g.rectangle("line", x + 0.5, y + 0.5, bw - 1, bh - 1)
  end

  g.setColor(0.08, 0.06, 0.05, alpha)
  local ty = y + padY
  for i = 1, #lines do
    local codes = Font.encode(lines[i])
    local tx = x + padX
    for j = 1, #codes do
      Font.drawCode(codes[j], tx, ty)
      tx = tx + (Font.advanceOf(codes[j]) or 8)
    end
    ty = ty + lineH
  end
  g.setColor(1, 1, 1, 1)
  g.pop()
end

function Callouts.draw(session, battle)
  if not (session and session._trainerCallouts and love and love.graphics) then
    return
  end
  -- Switch / learn-move / "about to use" pages own the white box; pause this one.
  if Callouts.shouldHold(battle) then
    return
  end
  local all = session._trainerCallouts
  local playerQ = all.player
  local foeQ = all.foe
  local toast
  if playerQ and playerQ[1] then
    toast = playerQ[1]
  elseif foeQ and foeQ[1] then
    toast = foeQ[1]
  else
    return
  end
  local Font = font()
  if not Font then
    return
  end
  local vanillaTop = battle and battle._arNarratorTop or nil
  local g = love.graphics
  local alpha = toastAlpha(toast.age, toast.hold)
  drawBox(g, Font, toast.text, vanillaTop, alpha)
end

return Callouts
