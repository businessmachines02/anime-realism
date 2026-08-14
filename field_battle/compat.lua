-- Field battle — gate foreign staged battles when FIELD is on.
--
-- We only prevent OverworldBattle / Dramatic Shape from *staging* a fight
-- (begin/ensure/update session). We do NOT force the user's 3D-BTL / VOXEL
-- options off — free-roam potato_voxel must keep drawing the extruded map
-- under FIELD. On battle exit, Compat.releaseVoxelOverlay unbinds any
-- leftover Voxel3D canvas and clears Voxel3D.camera so free-roam orbit resumes.

local Compat = {}

function Compat.suppressDramaticShape(FBV, mod)
  if not (mod and type(mod.find) == "function") then
    return
  end
  local function shouldUse(battle)
    return FBV and type(FBV.shouldUse) == "function"
      and FBV.shouldUse(mod, battle)
  end
  local function hasActiveFieldBattle()
    local Lifecycle = FBV and FBV.Lifecycle
    if not (Lifecycle and type(Lifecycle.liveBattle) == "function") then
      return false
    end
    local okG, Game = pcall(require, "src.core.Game")
    if not okG then
      return false
    end
    local battle = select(1, Lifecycle.liveBattle(Game))
    return shouldUse(battle)
  end
  local ids = { "DRAMATIC_SHAPE", "DRAMALESS_SHAPE", "potato_voxel" }
  for i = 1, #ids do
    local okH, handle = pcall(mod.find, mod, ids[i])
    if not okH or not handle then
      okH, handle = pcall(mod.find, ids[i])
    end
    local lib = handle and handle.exports and handle.exports.lib
    if lib and type(lib.require) == "function" then
      local ok, OB = pcall(lib.require, "OverworldBattle")
      if ok and type(OB) == "table" and not OB._arFieldGate then
        if type(OB.begin) == "function" then
          local origBegin = OB.begin
          function OB.begin(state, battle, ...)
            if shouldUse(battle) then
              if type(OB.finish) == "function" then
                pcall(OB.finish)
              end
              return false
            end
            return origBegin(state, battle, ...)
          end
        end
        if type(OB.ensure) == "function" then
          local origEnsure = OB.ensure
          function OB.ensure(battle, ...)
            if shouldUse(battle) then
              if type(OB.finish) == "function" then
                pcall(OB.finish)
              end
              return
            end
            return origEnsure(battle, ...)
          end
        end
        if type(OB.update) == "function" then
          local origUpdate = OB.update
          function OB.update(dt, ...)
            if hasActiveFieldBattle() then
              if type(OB.arena) == "function" then
                local a = OB.arena()
                if a and type(OB.finish) == "function" then
                  pcall(OB.finish)
                end
              end
              return
            end
            return origUpdate(dt, ...)
          end
        end
        OB._arFieldGate = true
      end
    end
  end
end

local VOXEL_MODS = { "DRAMATIC_SHAPE", "DRAMALESS_SHAPE", "potato_voxel" }

local function eachVoxelLib(mod, fn)
  if not (mod and type(mod.find) == "function") then
    return
  end
  for i = 1, #VOXEL_MODS do
    local okH, handle = pcall(mod.find, mod, VOXEL_MODS[i])
    if not okH or not handle then
      okH, handle = pcall(mod.find, VOXEL_MODS[i])
    end
    local lib = handle and handle.exports and handle.exports.lib
    if lib and type(lib.require) == "function" then
      fn(lib)
    end
  end
end

--- Unbind a 3D pass that threw after Voxel3D.beginScene (nil sprite.def).
--- Safe during a live FIELD fight: does not call OverworldBattle.finish.
function Compat.unwedgeVoxelPass(mod)
  eachVoxelLib(mod, function(lib)
    local okV, Voxel3D = pcall(lib.require, "Voxel3D")
    if okV and type(Voxel3D) == "table" then
      if type(Voxel3D.endScene) == "function" then
        pcall(Voxel3D.endScene)
      end
      Voxel3D.camera = nil
    end
    local okS, Voxel = pcall(lib.require, "VoxelState")
    if okS and type(Voxel) == "table" then
      Voxel.ready = true
    end
  end)
  if love and love.graphics and type(love.graphics.setCanvas) == "function" then
    pcall(love.graphics.setCanvas)
  end
end

--- Hand the diorama back: finish any staged OverworldBattle session and
--- clear Voxel3D.camera so free-roam orbit resumes.
function Compat.releaseVoxelOverlay(mod)
  Compat.unwedgeVoxelPass(mod)
  eachVoxelLib(mod, function(lib)
    local okOB, OB = pcall(lib.require, "OverworldBattle")
    if okOB and type(OB) == "table" and type(OB.finish) == "function" then
      pcall(OB.finish)
    end
  end)
end

--- True when battle presentation must skip main.lua cover stamps / HUD props.
function Compat.isFieldBattle(battle, FBV, mod)
  if not battle then
    return false
  end
  if battle._arAnimeField or battle._arFieldCombat or battle._arFieldStandalone then
    return true
  end
  return FBV and mod and type(FBV.shouldUse) == "function"
    and FBV.shouldUse(mod, battle)
end

--- FIELD hides the classic bottom dialogue slab, but stacked translucent
--- prompts (MoveLearnMenu TextBox / YES-NO ChoiceBox, nickname boxes, …)
--- still need to paint. Opaque menus (Party/Bag) already own the screen.
function Compat.fieldAllowsStackedBottomUI(battle)
  if not battle then
    return false
  end
  local stack = battle.game and battle.game.stack
  local top = stack and type(stack.top) == "function" and stack:top() or nil
  if not top or top == battle then
    return false
  end
  -- Opaque full-screen menus draw themselves; don't unhide battle chrome.
  if top.isOpaque == true then
    return false
  end
  return true
end

return Compat
