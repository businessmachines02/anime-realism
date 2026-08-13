-- Field battle — arFieldCue → grid steps + cast anims.
-- Physical attacks step in toward the foe; specials cast in place.
-- Hits may knock the target back one cell (both categories).

local Cues = {}

local function now(session)
  if session and session._now ~= nil then
    return session._now
  end
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return 0
end

local function rr(...)
  local random = (love and love.math and love.math.random) or math.random
  return random(...)
end

local function foeOf(session, side)
  if side == "player" then
    return session.enemyMon
  end
  return session.playerMon
end

local function normCategory(cat)
  cat = tostring(cat or ""):lower()
  if cat == "special" or cat == "sp" then
    return "special"
  end
  if cat == "physical" or cat == "phys" then
    return "physical"
  end
  return nil
end

--- Apply a cue kind to a side. opts.category = "physical"|"special"
function Cues.apply(session, side, kind, Grid, nudgeCamera, battle, opts)
  if not (session and session.live and session.grid) then
    return false
  end
  local ent = (side == "player") and session.playerMon or session.enemyMon
  if not ent or ent._removed then
    return false
  end
  kind = tostring(kind or "attack")
  opts = opts or {}
  local category = normCategory(opts.category)
  session._lastCueSide = side
  session._lastCueKind = kind
  session._lastCueAt = now(session)
  if category then
    session._lastAttackCategory = category
  end
  local foe = foeOf(session, side)
  local g = session.grid

  ent.returning = nil
  ent.wanderTx, ent.wanderTy = nil, nil
  ent._wanderCD = 2.4

  if kind == "dodge" then
    Grid.dodge(g, ent, foe)
    if type(ent.play) == "function" then
      ent:play("dodge")
    end
    return true
  end

  if kind == "cover" or kind == "hide" then
    local hasCover = (session.grid and session.grid.props and #session.grid.props > 0)
        or (session.coverSlots and #session.coverSlots > 0)
    if hasCover then
      Grid.seekCover(g, ent, foe)
      if type(ent.play) == "function" then
        ent:play("cover")
      end
    else
      Grid.dodge(g, ent, foe)
      if type(ent.play) == "function" then
        ent:play("dodge")
      end
    end
    return true
  end

  if kind == "brace" then
    if type(ent.play) == "function" then
      ent:play("brace")
    end
    return true
  end

  if kind == "status" then
    local Projectiles = session._deps and session._deps.Projectiles
    if Projectiles and type(Projectiles.status) == "function" then
      Projectiles.status(session, side, opts)
    end
    if type(ent.play) == "function" then
      ent:play("cast")
    end
    return true
  end

  if kind == "attack" then
    if type(nudgeCamera) == "function" and battle then
      local foeSide = (side == "player") and "enemy" or "player"
      nudgeCamera(battle, foeSide, 0.45)
    end
    -- Physical: close distance on the pad, then return home.
    -- Special: hold cell; still play an in-place cast anim.
    if category == "special" then
      ent._returnAt = nil
      ent._attackStepped = nil
      local Projectiles = session._deps and session._deps.Projectiles
      if Projectiles and type(Projectiles.move) == "function" then
        Projectiles.move(session, side, opts)
      end
      if type(ent.play) == "function" then
        ent:play("cast")
      end
    else
      ent._attackStepped = Grid.attackStep(g, ent, foe) == true
      local Projectiles = session._deps and session._deps.Projectiles
      if Projectiles and type(Projectiles.contact) == "function" then
        Projectiles.contact(session, side, opts)
      end
      -- Let the one-cell lerp and attack pose land before walking home.
      ent._returnAt = now(session) + 0.48
      if type(ent.play) == "function" then
        ent:play("attack")
      end
    end
    return true
  end

  if kind == "hit" then
    if type(nudgeCamera) == "function" and battle then
      nudgeCamera(battle, side, 0.35)
    end
    local cat = category or session._lastAttackCategory or "physical"
    -- Both can shove; physical more often / more reliably.
    local pushChance = (cat == "special") and 0.45 or 0.78
    if opts.push == false then
      pushChance = 0
    elseif opts.push == true then
      pushChance = 1
    end
    if rr() <= pushChance then
      Grid.knockback(g, ent, foe)
    end
    if type(ent.play) == "function" then
      ent:play("hit")
    end
    return true
  end

  if kind == "faint" then
    if type(ent.play) == "function" then
      ent:play("faint")
    end
    return true
  end

  if type(ent.play) == "function" then
    ent:play("attack")
  end
  return true
end

function Cues.shouldSkipEvent(session, side, kind)
  if not (session and session.live and session._lastCueAt) then
    return false
  end
  if (now(session) - session._lastCueAt) > 1.25 then
    return false
  end
  if session._lastCueSide ~= side then
    return false
  end
  kind = tostring(kind or "")
  local last = session._lastCueKind
  if kind == "attack" and last == "attack" then
    return true
  end
  if kind == "hit" and last == "hit" then
    return true
  end
  if kind == "status" and last == "status" then
    return true
  end
  return false
end

--- Drain one-shot cue from battle.current when it becomes active.
function Cues.pumpCurrent(session, battle, Grid, nudgeCamera)
  local cur = battle and battle.current
  local cue = cur and cur.arFieldCue
  if not (cur and cue and not cur._arFieldCueDone) then
    return false
  end
  cur._arFieldCueDone = true
  return Cues.apply(session, cue.side, cue.kind, Grid, nudgeCamera, battle, {
    category = cue.category,
    moveType = cue.moveType,
    moveId = cue.moveId,
  })
end

--- Finish delayed attack returns to home cell.
function Cues.tickReturns(session, Grid)
  if not (session and session.grid) then
    return
  end
  local t = now(session)
  for _, ent in ipairs({ session.playerMon, session.enemyMon }) do
    if ent and ent._returnAt and t >= ent._returnAt then
      ent._returnAt = nil
      Grid.returnHome(session.grid, ent)
    end
  end
end

return Cues
