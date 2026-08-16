# Architecture

How **Anime Realism** is put together: boot, packages, battle logic, and FIELD
presentation. Player-facing mechanics live in `README.md`. FIELD non-negotiables
and pad math live in `field_battle/SPEC.md`. This file is the map of *who owns
what* and *what runs when*.

## What this mod is

A Gen1Recomp content mod (`manifest.json` id `anime_realism`, priority 200).
It does not replace `BattleState`. The engine still owns turns, damage rolls,
menus, Party/Bag, and faint/switch resolution. This mod:

1. Changes how fights *feel* (hide numbers, callouts, Focus reactions).
2. Optionally presents ordinary wild/trainer singles **on the live overworld**
   (FIELD) instead of the classic battle screen.

`BATTLE STAGE`:

| Value | Presentation |
|-------|----------------|
| `FIELD` | Transparent `BattleState` over the map (`field_battle/`) |
| `AUTO` | Leave other presentation mods alone; classic (or their) battle UI |

Legacy `CLASSIC` / `STADIUM` option values map to `AUTO`. This mod does not
drive Stadium / Dramaless arena models.

## Runtime constraints

The host sandbox is stricter than stock Lua:

- `require` works for **engine** modules (`src.battle.EffectRegistry`, …).
- There is often **no** `package` global and **no** `debug` library.
- Lua `io` / `love.filesystem` are not used from `main.lua` or FIELD sprites.
- Zip and loose installs both load sources through `mod:read` (host API).

Implications:

- Folder packages cannot rely on `package.loaded["coords"]` unless it exists.
  `field_battle/init.lua` temporarily aliases `require("coords")` /
  `require("themes")` / `require("fx_catalog")` while siblings load.
- HUD hiding wraps `BattleState.drawHUDs` and `HudTiles` directly. Upvalue
  patching (`debug.getupvalue`) is skipped when `debug` is missing.
- Vanilla `EffectRegistry.runDamaging` is captured from the already-required
  table, not by clearing `package.loaded`.

## Boot

`manifest.json` `entry` is `main.lua`. The host calls:

```lua
return function(mod)
```

```mermaid
flowchart TD
  host[Host loads main.lua] --> read[mod:read lib/modload.lua]
  read --> ml[ModLoad.loadPackage]
  ml --> imm[immersion/]
  ml --> bat[battle/]
  ml --> fbv[field_battle/]
  bat --> rd[battle/reactive_defense.lua]
  fbv --> sib[Sibling modules via env.load]
  ml --> pkgs[mod._arPackages]
  pkgs --> bind[FBV.bind]
  bind --> install[FBV.install: Intercept + Hooks]
  imm --> opts[mod.options:define]
  bat --> opts
  fbv --> opts
  opts --> hooks[main.lua engine wraps + events]
```

1. `main.lua` reads `lib/modload.lua` with `mod:read`, `load`s it, and gets a
   loader bound to this `mod`.
2. `ModLoad.loadPackage("immersion"|"battle"|"field_battle")` reads
   `<dir>/init.lua`, which returns `function(env)`.
3. `env.load("file.lua")` reads siblings from that folder (works in a zip).
4. `mod._arPackages` is set, then `FBV.bind` injects `ReactiveDefense` into
   FIELD, then packages `install(mod)` (FIELD actually hooks the engine here).
5. `main.lua` defines all options, then installs the remaining runtime: HUD
   filters, dialogue/callouts, Reactive Defense menus, EXP/faint feel.

Packages are exposed as `mod._arPackages` for debug and for `FBV.bind`.

`./build.sh` zips `main.lua`, `manifest.json`, `LICENSE`, and the three
package trees (tests excluded) so folder paths survive import.

## Three packages

```text
anime_realism/
  main.lua              orchestrator + most runtime hooks
  lib/modload.lua       zip-safe package loader
  immersion/            option keys for numbers-feel
  battle/               option keys + Reactive Defense logic
  field_battle/         overworld presentation (extracted)
```

Ownership today is **asymmetric on purpose** (LuaJIT 200-local budget + shared
HUD table). Option keys live on packages; most *behavior* for immersion and
classic battle still runs in `main.lua`. FIELD presentation is the extracted
viewer. Target facades, who may call whom, and the extraction sequence live in
[Composable APIs](#composable-apis).


| Package | Owns at runtime | Still in `main.lua` |
|---------|-----------------|---------------------|
| `immersion/` | Option keys / labels + `Rewards.install` (underdog EXP, effort faint) | Hide HUD/XP, generic level-up, party heal hints |
| `battle/` | `ReactiveDefense` math + `React` pipeline (momentum, REACT/COUNTER menus, `EffectRegistry` wrap) | Callouts, bubbles, banter, cover FX; `React.bind` host callbacks |
| `field_battle/` | Intercept, session, pad, sprites, FX catalog, compact UI | Forwards `battle.*` into `FBV.*`; playFocusReactFx asks FBV on FIELD |

## Engine seams `main.lua` wraps

The fight systems sit on stock `BattleState` by wrapping a few engine entry
points (not by forking the battle simulator).

### Damage: `EffectRegistry.runDamaging`

`src.battle.EffectRegistry` is the engine damage pipeline, not a Stadium
package. The wrap:

1. If the player is **entrenched**, auto-hold (no REACT menu) and resume the
   original function after mitigation.
2. If a **REACT!** pick is required, stash `{ ctx, record }` on momentum state
   and return without applying damage. `finishCalloutPick` later calls the
   stored vanilla `runDamaging`.
3. If a physical **counter** opening is armed, apply the quiet DEF drop, run
   vanilla damage, maybe **Again!**.
4. Otherwise run vanilla, then trainer-foe counter / Again! mirrors.

Vanilla is stored on `EffectRegistry._arVanillaRunDamaging` so hot reload does
not chain wraps.

### Dialogue and menus

- `battle.say` / queue rows become speech bubbles (player / foe / narrator) or
  FIELD toasts.
- Anime move callouts rewrite `"NAME used MOVE!"` into trainer orders.
- REACT / COUNTER panels are extra `Menu` pages spliced into `battle.queue`
  (before the move anim when possible).

### HUD / numbers

- `HudTiles.drawHPBar` is a no-op; `0x6E` “Lv.” tiles are skipped.
- `BattleState.drawHUDs` is wrapped so **HIDE BATTLE HUD** can blank classic
  name/HP bands without killing the dialogue box.
- Companion UIs (Gen 3 Inspired, QoL XP bar, Dramatic Shape frosted panels)
  are gated when those mods are present. FIELD also skips their overlay hooks
  so compact chrome stays on top.

### Events

| Event | Typical work |
|-------|----------------|
| `mods.loaded` / `game.ready` | HUD wraps, FIELD install |
| `battle.started` | Clear momentum / Focus |
| `battle.move_used` | FIELD cues + projectiles; camera re-arm for Again! |
| `battle.damage_dealt` | Low-HP lines |
| `battle.fainted` / `battler_switched` | FIELD recall/send-out; effort faint |
| `battle.turn_started` / `turn_ended` | Focus regen, cover/entrench clocks, FIELD turn hooks |
| `battle.ended` | FIELD teardown |

## Reactive Defense

`battle/reactive_defense.lua` is **pure logic**: Focus meter, costs, dodge
success, cover durability, brace type-call, entrench turns. No drawing, no
queue edits.

`main.lua` owns:

- When to offer **REACT!** (`ALWAYS` / `THREAT` / `OFF`) is read by `battle/react.lua` via `React.bind`.
- Dialogue rewrite, bubbles, banter, and classic dodge/brace sparkles.
- Applying presentation after a pick (`dev.playFocusReactFx`).
  - FIELD: `FieldBattleViewer.react` (OW sprite + projectiles).
  - Classic: picFx hide/brace sparkles.

`battle/react.lua` owns momentum state, the REACT / COUNTER pick modals, and the
`EffectRegistry.runDamaging` wrap. It calls `ReactiveDefense.resolveIncoming`
then host callbacks for FX and queue text.

State is weak-keyed per `BattleState` (`byBattle` in RD, `momentumByBattle` in
main) so sessions die with the fight.

## FIELD presentation

Enabled only when `battle_stage == "FIELD"` **and** the battle is a single
wild or trainer fight (not link, demo, or double). Flags stamped on the
battle: `_arAnimeField`, `_arFieldCombat`, `_arFieldStandalone`.

```mermaid
sequenceDiagram
  participant OW as Overworld
  participant I as Intercept
  participant BS as BattleState
  participant L as Lifecycle
  participant P as Present clock
  I->>OW: freeze player, skip wipe
  I->>BS: push transparent, bgMode=world
  L->>L: Survey envelope, Grid pad, Cast homes
  loop Every frame
    P->>L: tickPresent (bob, lerp, FX)
    Note over BS: Logic clock may wait on menus
  end
  L->>OW: restore entities, camera, voxel
```

### Intercept (`intercept.lua`)

Replaces the usual battle transition:

- No wipe / white return.
- Pushes **the real** `BattleState` (`isOpaque = false`, `BG_WORLD_DIM = 0`) so
  other UI mods still see `stack:top() == battle`.
- Locks the overworld player; map keeps drawing underneath.

### Lifecycle (`lifecycle.lua`)

One weak-keyed session per battle:

`Idle → Armed → Staging → Live → Finishing`

- **Survey**: read-only walkable envelope. Never writes map tiles.
- **Layout / Grid**: pad homes on the fight axis; occupancy is pad cells.
- **Cast**: trainers + mons as overworld entities with real `pose()` sprites
  (Dramatic Shape voxel crashes on nil `sprite.def`).
- **Finish**: restore entity list and camera; unlock player; spectators /
  wildlife return.

### Two clocks

The stack only updates the **top** state. Move diamond / REACT / Party freeze
`BattleState:update`. Sprites must not freeze.

| Clock | When | What |
|-------|------|------|
| Logic | Battle queue / top-state update | Turns, damage, cue *dispatch* |
| Present | Every frame while session is live | Bob, walk frames, pad lerp, FX, camera |

`Lifecycle.tickPresent` is driven from several hooks (update, overlay,
letterbox, world draw) and deduped by wall time so it does not double-step.

### Coordinates (`coords.lua`)

Three layers. **Pad is truth in Live.**

| Layer | Unit | Use |
|-------|------|-----|
| World cell | `(wx, wy)` | Survey / theme; never written |
| Pad cell | `(u, v)` | Occupancy, steps, cover |
| Pixel | `(px, py)` | Draw, bob, FX = `padToPx` + presentation offsets |

`u` is along the fight (player → foe). `v` is perpendicular (dodge / knock).
Never derive occupancy from pixels.

### FIELD module map

Loaded from `field_battle/init.lua` (plus `coords` / `themes`):

| Module | Role |
|--------|------|
| `hooks.lua` | BattleState draw/input wraps, present tick, event fan-out |
| `ui.lua` | Compact FIGHT / diamond moves / fallback dialogue (draw-only) |
| `survey.lua` | Read-only walkable envelope + water cells |
| `grid.lua` | Pad occupancy + step helpers |
| `cast.lua` | Stage trainers/mons onto pad homes |
| `cues.lua` | `arFieldCue` → step-in / cast-in-place / Dig-Fly vanish |
| `sprites.lua` | OW follower sheets via `Assets.image` / other-mod APIs |
| `projectiles.lua` | World-space move FX (not `ow.entities`) |
| `anims.lua` | Affine of classic move FX onto live pad centers |
| `audio.lua` | Cue-synced SFX; mute engine `Sound.playMove` while live |
| `arena.lua` / `themes.lua` | Session overlay props (trees/rocks/grass), not tile edits |
| `layout.lua` | Tight adjacent-mon formation |
| `spectators.lua` | Nearby trainers walk in and watch |
| `wildlife.lua` | Roaming OW mons scatter |
| `compat.lua` | Gate Dramatic Shape *staging*; keep free-roam VOXEL drawing |
| `debug.lua` | Optional pad occupancy overlay |

Also in the tree: `arenas/*.lua` (hand-crafted kit data; unused — live kits
come from `Themes.KITS` + `Arena.generate`), `callouts.lua` (world-anchored
trainer bubbles; loaded and exposed as `FBV.Callouts`), `logger.lua` (unused;
do not wire or delete yet), `tests/`.

### Sprite resolution

`sprites.lua` does not open files. It asks:

1. Wilds of Kanto `resolveFollowerSprite` / `assetPath` when those mods exist.
2. Other follower packs’ handles (`path` / `root`) and `Assets.image`.
3. `love.graphics.newImage` as a last loader.

`FIELD SPRITES` (`AUTO` / `GSC` / `HGSS` / `POKEDEX`) picks the sheet family.
Water-types can swap to a swim sheet on surveyed water cells.

### Compact UI vs engine UI

`BattleState` still owns phases, cursors, and input. FIELD paints a small
command menu and U/R/L/D move diamond, then injects **A** for instant cast.
**B** pauses back to FIGHT/PKMN/ITEM/RUN. Classic anim paint is
suppressed; engine anim *rows* still advance for timing. HP is a tiny bar
over each mon (world→UI mapped). Party/Bag stay engine screens.

## Classic vs FIELD (same fight systems)

```mermaid
flowchart LR
  engine[BattleState + EffectRegistry]
  rd[Reactive Defense + callouts]
  engine --> rd
  rd --> classic[Classic picFx / HUD]
  rd --> field[FIELD sprites / projectiles / compact UI]
```

Callouts, Focus, bubbles, underdog EXP, and effort faint run in both
modes. FIELD only replaces **where** battlers and FX appear.

## Companion mods

Optional (`manifest.json`):

- **Dramatic Shape** — voxel overworld under FIELD; staging is gated so it
  cannot drop a 3D arena on a map fight.
- **Battle Cinematics** — Again! / extra swings re-emit `battle.move_used`.
- **PokePCFollowers / FOLLOWERS_EX / Wilds** — FIELD battler art.
- **quality_of_life / gen3_battle_ui** — HUD/XP/dialogue overrides when FIELD
  is off; skipped while compact FIELD UI is active.

This mod does not depend on StadiumBattleFX or Dramaless Shape.

## Composable APIs

Packages exist on disk, but they are not yet the APIs the rest of the code
uses. `main.lua` still owns HUD hide, dialogue, and most presentation patches.
FIELD is extracted as a viewer, then historically leaked submodules
and peeked `mod._arPackages.battle`. New work should plug into the contracts
below instead of growing god-functions (`Cues.apply`, `Projectiles.move` /
`drawEffect`, `Hooks.install`).

```mermaid
flowchart TB
  subgraph host [Host]
    Main[main.lua boot]
  end
  subgraph facades [Package facades]
    Imm[Immersion.install]
    Bat[Battle.install]
    FBV[FBV.install]
  end
  subgraph battlePkg [battle]
    RD[ReactiveDefense]
    React[REACT menus plus EffectRegistry wrap]
    Call[callouts bubbles banter]
  end
  subgraph fieldPkg [field_battle]
    Life[Lifecycle composer]
    Cues[Cues.apply]
    Proj[Projectiles spawn]
    CueReg[cue kind registry]
    FxReg[MOVE_FX plus style painters]
    ArenaReg[arena kits]
  end
  Main --> Imm
  Main --> Bat
  Main --> FBV
  Bat --> RD
  Bat --> React
  Bat --> Call
  FBV --> Life
  Life --> Cues
  Life --> Proj
  Cues --> CueReg
  Proj --> FxReg
  Life --> ArenaReg
  FBV -.->|"bind RD"| RD
```

### Three layers

**1. Package facades** (what `main.lua` may call)

| Package | Public now | Public target |
|---------|------------|---------------|
| `immersion/` | `install(mod)` owns underdog EXP + effort faint | HUD hide still in `main.lua` (`hud` packed table) |
| `battle/` | `ReactiveDefense` + `React` + option keys; stub `install` | `install(mod)` owns REACT queue, `EffectRegistry` wrap, callouts/bubbles; `RD` stays pure |
| `field_battle/` | wide `FBV.*` plus every submodule | Narrow facade below; submodules are internal |

**2. Internal composers** (only these may wire siblings)

- `Lifecycle` is the FIELD composer. It receives a `deps` bag and is the only
  module allowed to orchestrate Survey / Layout / Grid / Cast / Cues /
  Projectiles / Arena / Spectators / Wildlife.
- `Battle.install` is the classic-fight composer (menus, damage wrap,
  dialogue). It may call `RD.*` and `FBV.react` / `FBV.isFieldBattle` — not
  FIELD internals.
- `Hooks.install` talks only to the FBV facade (not `FBV.Lifecycle.*` /
  `FBV.Cues.*` except during the later Hooks split).

**3. Registries** (how FIELD scales later)

Add a move, cue, or kit without editing the god `if kind ==` / `drawEffect`
switches:

- **Cue kinds** — `Cues.register(kind, handler)` behind the existing
  `Cues.apply(session, side, kind, Grid, nudgeCamera, battle, opts)` entry.
  Tests already depend on that signature.
- **Move FX** — `field_battle/fx_catalog.lua` holds `MOVE_FX` + `TYPE_COLORS` +
  type defaults. `Projectiles.move` / `contact` / `status` stay the spawn API.
  Style painters (`beam`, `ember`, `surf`, …) still live in `projectiles.lua`
  until they register by name.
- **Arena kits** — `field_battle/arenas/*.lua` already look like plugins but
  are unused; `Arena.generate` is procedural from `Themes.KITS`. Later:
  `Themes.kit` loads a file if present, else procedural.

### Public contracts

**`FBV` — presentation policy + session**

Callers (`main.lua`, later `battle/`):

- `enabled(mod)` / `supportsBattle(battle)` / `shouldUse(mod, battle)` — policy
- `isFieldBattle(battle)` — runtime: flags `_arAnimeField|_arFieldCombat|_arFieldStandalone` **or** `shouldUse`. Flags remain a cache stamped by intercept/lifecycle; they are not the public API.
- `session` / `react` / `drawUI` / `drawCallouts` / `compactUIActive` / `install`
- `bind(packages)` — inject `ReactiveDefense` (and later other cross-package services)

`compactUIActive` (and `hud.fieldCompactActive` in `main.lua`) is the **draw**
gate. It answers a different question than `isFieldBattle`.

Do **not** grow `main.lua` reads of `FBV.Cues`, `FBV.Lifecycle`, or raw
`session` fields. If cover flavor is needed, add `FBV.cover(battle)` rather
than digging the session.

**`ReactiveDefense` (`RD`) — pure rules**

`battle/reactive_defense.lua`: `state` / `sideState` / `resolveIncoming` /
`menuActions` / `endTurn` / `applyCoverHit` / tunables. No drawing, no queue
edits, no `require` of FIELD.

FIELD receives `RD` via `deps.ReactiveDefense` after `FBV.bind`, not via
`mod._arPackages` peeks.

**`Cues.apply` / `Projectiles.{move,contact,status,tick,drawUi}` / `Cast.stage*`**

Stable for `field_battle/tests/run_grid_tests.lua` (`loadfile` + partial
`session._deps`). Registry work later must keep these entry points.

### Who may call whom

| Caller | May call | Must not call |
|--------|----------|---------------|
| `main.lua` | `Immersion.install`, `Battle.install`, `FBV` facade, `RD.*` (until Battle.install owns REACT) | FIELD submodules, `session` guts |
| `battle/` | `RD.*`, `FBV.react`, `FBV.isFieldBattle` | `FBV.Cues`, `FBV.Lifecycle`, `session._deps` |
| `Lifecycle` | anything on the `deps` bag | `mod._arPackages` |
| `Cues` / `Projectiles` | Grid / spawn APIs passed in or on `session._deps` until registries land | `Lifecycle`, `RD` |
| `Hooks` | FBV facade | `mod._arPackages` |

### Hard constraints

Do not “fix” these by rewriting:

- Zip-safe `lib/modload.lua` (`env.load` siblings; no relying on
  `package.loaded` except the coords/themes/fx_catalog shim).
- LuaJIT **200-local** budget: extracted code stays on packed tables (`dev`,
  `hud`, `S`, `BanterCameo`), not a flood of new locals in
  `return function(mod)`.
- `EffectRegistry._arVanillaRunDamaging` capture (hot-reload must not chain wraps).
- `FBV.install` stays idempotent (`_arFbv*` guards); multiple `mods.loaded` /
  `game.ready` calls remain valid.
- Pad-is-truth rules in `field_battle/SPEC.md` stay non-negotiable.

### Extraction sequence

1. **Facades + wiring** — done: one boot path, `FBV.bind`, `FBV.isFieldBattle`.
2. **REACT pipeline → `battle/`** — done: `battle/react.lua` owns momentum, pick
   menus, and the `EffectRegistry.runDamaging` wrap. Host callbacks stay in
   `main.lua` until HUD/dialogue extract.
3. **HUD / EXP / effort → `immersion/`** — EXP + effort faint live in
   `immersion/rewards.lua`. HUD hide still shares the `hud` packed table with
   speech bubbles in `main.lua`.
4. **FIELD registries** — `MOVE_FX` / type colors live in
   `field_battle/fx_catalog.lua`. Cue-kind table and `arenas/*.lua` still later.
   No behavior change.
5. **Split god-files behind those registries** — `Hooks.install` into wrap
   groups; `Cues.apply` dispatches a table; projectile style painters. Public
   signatures unchanged.
6. **Narrow FBV** — stop exporting raw modules to `main`; Hooks uses facade
   methods added in step 5.

Do not start steps 2–6 until the contracts and wiring in step 1 are in.

## Where to change things

| You want to… | Start here |
|--------------|------------|
| Focus costs / dodge math | `battle/reactive_defense.lua` |
| REACT menu / queue timing | `battle/react.lua` (`React.install`; host callbacks still in `main.lua`) |
| Hide numbers / EXP feel | `main.lua` HUD hide; EXP/effort in `immersion/rewards.lua` |
| FIELD intercept / no wipe | `field_battle/intercept.lua` |
| Pad steps / Dig-Fly | `field_battle/cues.lua` + `grid.lua` |
| Move VFX | `field_battle/fx_catalog.lua` (named moves) then `projectiles.lua` |
| Compact menus | `field_battle/ui.lua` + input in `hooks.lua` |
| Follower art | `field_battle/sprites.lua` |
| Session begin/end | `field_battle/lifecycle.lua` |
| Zip contents | `build.sh` |
