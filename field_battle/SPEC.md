# FIELD combat SPEC (v4.5.18)

Overworld FIELD battle presentation owned by `field_battle/`.

FIELD intercepts ordinary single `kind == "wild"` and `kind == "trainer"`
battles. Link, demo, doubles, and other special hosts remain unchanged.

The carved fight pad is a **first-class coordinate space**: every battler, prop,
cue step, FX anchor, and camera focus resolves through one shared tile system.
Pixels are presentation only; **pad cells are truth**.

## Non‑negotiables

1. Stay on the flat map — transparent `BattleState`, `bgMode == "world"`, `BG_WORLD_DIM = 0`, no wipe / white return.
2. **The true overworld map is inviolable.** FIELD never writes map tiles. A
   bounded, one-time, read-only walkability survey excludes water, warps,
   blocked cells, and unrelated entities. The fight stays on the **live map**;
   themed props are session overlays only. Free-roam **VOXEL** keeps drawing.
3. **Pad cell is authoritative** in Live. `px/py` follow `padToPx(u,v)` plus presentation offsets only. Never derive occupancy from pixels.
4. Player mon deferred until lead / send-out; stages onto player home pad cell.
5. Callouts tag `arFieldCue`; FIELD plays pad steps when that row becomes `battle.current`. Physical vs special motion rules apply.
6. FIELD suppresses classic/Stadium move paint and uses generic world-space
   contact, projectile, beam, area, status, heal, and capture effects. Engine
   move timing and sound cues remain authoritative.
7. Exit restores poses + entity list, clears occupancy, unlocks player, emits `battle.ended` via `src.mods.Runtime`. Map tiles must already match the true overworld (nothing to rewind).
8. **Present-clock continuity:** bob, foot-swap, cell lerp, attack/cast/hit anims, and delayed return-home keep advancing during any player prompt / overlay / `waitingUI`. Logic queue may wait; **sprites must not.**
9. Move orbs and Poké Balls are temporary overworld entities. They use the same
   world camera as the cast, preserving alignment on flat and voxelized maps.
10. Switching is ordered recall → replace occupancy/entity → send-out. Capture
    resolves ball flight/shakes before shrinking a caught target away.

## Coordinate model

### Three layers

| Layer | Unit | Owner | Use |
|---|---|---|---|
| **World cell** | `(wx, wy)` | engine map | theme + read-only walkability survey; never written |
| **Pad cell** | `(u, v)` | `grid` / `coords` | occupancy, steps, lanes |
| **World pixel** | `(px, py)` | cast / sprites | draw, bob, FX |

Rules:

1. Pad cell is truth in Live.
2. `px/py` = `padToPx(u,v)` + presentation offsets only.
3. Never derive occupancy from pixels.
4. Trainers sit on fixed edge pad cells; they are not combat movers.
5. The opening formation is tight (4×3): adjacent mon homes, trainers one
   cell behind each. Its surveyed free-tile envelope is normally 8×5 so
   mons can expand during the fight.

### Pad axes

From fight axis `(sx, sy)` at Staging:

```text
u = along fight (player → foe)
v = perpendicular (dodge / lateral knock)
```

`vAxis` is a 90° CCW rotate of `uAxis`: `(sx, sy)` → `(-sy, sx)`.

Store on the live grid:

```lua
grid.originWx, grid.originWy
grid.uAxis, grid.vAxis          -- { x, y } unit cardinals
grid.sizeU, grid.sizeV
grid.home = { player, enemy, playerTrainer, enemyTrainer }  -- pad (u, v)
```

World AABB (`minX`/`maxX`/`minY`/`maxY`) is kept for debug / carve identity only.

### Conversion API (`coords.lua`)

```lua
Coords.worldToPad(g, wx, wy) -> u, v
Coords.padToWorld(g, u, v)   -> wx, wy
Coords.padToPx(g, u, v)      -> px, py      -- cell origin (wx*16, wy*16)
Coords.padCenterPx(g, u, v)  -> px, py      -- origin + (8, 8)
Coords.inPad / clampPad / key
```

All step helpers mutate **pad** only; convert at boundaries (staging, draw, FX, camera).

### Occupancy

- One battler per pad cell.
- Blocking combines the read-only live-map survey with themed session overlays.
- `Arena.generate` places overlay props on pad cells (`u`, `v`). `Grid.build` blocks those pad cells; it never occupies from pixels.
- Optional lanes by `u`: player / mid / enemy thirds.
- Trainers park on `grid.home.playerTrainer` / `enemyTrainer` via `padToWorld` / `padToPx`. They are not combat movers.

## Compact FIELD UI

- Tiny proportional HP bars follow each visible Pokémon in world space; FIELD
  does not reserve the top of the screen for status panels.
- Compact command and move cursors read `battle.menuIndex` / `battle.moveIndex`; input
  and phase transitions remain owned by `BattleState`.
- Dialogue reuses `battle.shown`, waits, and typewriter progress in a narrow
  bottom panel.
- Party, Bag, naming, and forced-switch states stay engine-owned.
- Classic and companion HUD/menu chrome is suppressed only while FIELD is active.

## Present-clock continuity

### Problem

The stack only updates the **top** state. Move menu / callout modal / PartyMenu /
bubble wait park `BattleState` underneath → `BattleState:update` stops → idle/lerp
starve unless a frame-level driver keeps presentation alive.

### Contract

Split clocks:

| Clock | Runs when | Advances |
|---|---|---|
| **Logic clock** | battle queue / top-state update | turns, damage, cue *dispatch* from `battle.current` |
| **Present clock** | every frame while FIELD session `live` | bob, walk frames, pad lerp, animT, returnHome timers, anim xform cache |

Prompts may pause the logic clock. They must **not** pause the present clock.

### Drivers (all call the same deduped entry)

`Lifecycle.tickPresent(game, dt)` (`tickActive` is an alias):

1. `input.step` — logic step
2. `render.letterbox` — **every frame**, even under opaque menus (primary safety net)
3. `battle.overlay` — when battle still draws under UI
4. `BattleState:update` — when battle is top
5. `OverworldState.drawWorld` — **before** world draw (so bob is current this frame)

Dedupe by wall time (`_lastPresentAt`, ~8ms) so multiple drivers don’t double-step.

### What present tick must always do

- `Cast.tick` → entity `tick` (bob, idle foot-swap, animT, lerp to pad target)
- `Cues.tickReturns` (physical attack return-home)
- soft camera follow (throttled)
- `Anims.cache` while `animPlaying` or moving

### What present tick must NOT depend on

- `battle.waitingUI == nil`
- stack top == battle
- player having pressed A
- callout modal closed
- PartyMenu closed

### Explicit guards to forbid

```lua
-- FORBIDDEN in tick / tickPresent / Cast.tick / sprite tick
if battle.waitingUI then return end
if stack:top() ~= battle then return end
if battle.current and battle.current.auto == false then return end
```

Cue **dispatch** (`Cues.pumpCurrent`) may wait on `battle.current`; once playing,
anim/lerp use the present clock.

## Cue contract

```lua
item.arFieldCue = {
  side = "player"|"enemy",
  kind = "dodge"|"cover"|"brace"|"attack"|"status"|"hit",
  category = "physical"|"special"|nil,  -- for attack / hit
  moveType = string|nil,
  moveId = string|nil,
}
```

One-shot via `item._arFieldCueDone`. Engine `move_used` / `damage_dealt` are fallback only (dedupe ~1.25s).

| kind | pad motion | anim |
|---|---|---|
| dodge | `±v` | `dodge` |
| cover | nearest free prop-adjacent, far on `u` | `cover` / dodge fallback |
| brace | stay | `brace` |
| attack (physical) | `u` toward foe 1, then home | `attack` |
| attack (special) | stay | `cast` (in-place) |
| status | stay | `cast` + world-space orbit |
| hit | knockback chance (phys > special) | `hit` |

## Grid rules

- Survey envelope is normally 8×5 around the tight 4×3 opening formation.
- Occupancy: one battler per walkable pad cell; surveyed and prop cells block.
- Idle wander is stepwise and bounded within two cells of home; positions
  persist between turns instead of snapping back.
- Trainers on fixed edge pad cells; not tracked for combat steps.

## Battle initiation (`Lifecycle.begin`)

Triggered from `battle.started` when `battle_stage == FIELD`. Idempotent if already Live.

Intended sequence:

1. **Idle → Armed → Staging** — if a previous session exists, `finish` it first (no remount mid-intro).
2. Resolve fight axis from player cell + foe trainer (or wild facing-anchor). `Layout.plan` → homes, mid, `(sx, sy)`.
3. **Do not edit the live map.** Survey nearby traversal methods once, relocate
   unsafe Pokémon homes to the nearest valid side, then build themed overlay
   props only on surveyed walkable cells.
4. Snapshot player + foe **poses** and the overworld **entity list** (to restore on Finish). Freeze / lock player (and foe trainer); park them on edge pad cells. Set `ow.engaging`.
5. Stage enemy mon onto enemy home pad cell. Player mon stays deferred until lead / send-out.
6. Swap `ow.entities` to the fight cast (arena floor, player, foe trainer, enemy mon, session cover). Apply zoom. `bgMode == "world"`, transparent battle, no wipe.
7. **Live** — present clock starts; camera holds stable envelope framing and
   briefly emphasizes attack targets.

## Battle end (`Lifecycle.finish`)

Triggered from `battle.ended` (and from `begin` if remounting). `Finishing` then drop the session.

1. Stop present clock (`session.live = false`). `Grid.clear` occupancy.
2. Restore player + foe **poses** (cell, pixel, facing, frozen, wanders). Unlock player; clear `engaging`.
3. Restore the saved **entity list** (drop FIELD battler sprites and overlay cover; put OW NPCs/followers back).
4. Restore zoom. Clear `_arAnimeField`. Emit `battle.ended` only via the engine/runtime path (do not double-finish).
5. **Map tiles:** no restore pass — the true overworld was never written.

## Themed session arena

The fight stays on the live overworld. At Begin, `Themes.scene` picks a kit from the map id, then `Arena.generate` rolls cover / grass / ponds onto the pad edges (session overlays only):

| Location | Kit | Cover | Flavor |
|---|---|---|---|
| Cerulean Cave / tunnels | `cave` | rocks | moss, ponds |
| Viridian Forest | `forest` | trees | grass, pond |
| Routes | `route` | trees | grass patches |
| Towns / cities | `city` | crates | planters |
| Mountains / plateau | `mountain` | rocks | scrub |
| Seafoam / ship | `water` | rocks | sand, ponds |
| Tower / Lavender | `grave` | rocks | weeds |
| Gyms / indoor | `gym` / `indoor` | crates | sparse |

Props draw as **chunky 2.5D voxel cubes** — never a painted floor wash, never `setBlock`.

- [x] Stop `setBlock` / `blockAt` during FIELD
- [x] Themed kits instead of planting into the live map
- [x] Finish does not rewind tiles
- [x] Pose + entity-list snapshot/restore only
- [x] Pad-native cover slots (`u,v`) from `Arena.generate`

## Perf budget

- No `setBlock`; one bounded walkability survey at staging
- One floor draw + ≤ 4 cover sprites
- Camera ≤ 10–20 Hz; anim xform every frame only while `animPlaying`

## Exit checklist

- [x] True overworld tiles unchanged (generate/finish never `setBlock`; tests green)
- [x] Cast removed; OW entities restored
- [x] Player + foe poses restored
- [x] Zoom restored
- [x] Player unfrozen / unlocked; `engaging` cleared
- [x] Occupancy cleared
- [x] `battle.ended` emitted
- [x] No second `begin` remount mid-intro
- [x] Present clock never gates on `waitingUI` / stack top / `current.auto`
- [x] Compat gates OverworldBattle only (never force 3D-BTL off)
