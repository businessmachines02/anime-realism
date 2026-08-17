# Anime Realism

A [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) mod for anime-style immersion: Play by feel instead of numbers, and experience the major overhaul of the REACT battle system focused on live overworld field battles. In the anime, you never see a health bar or level — just whether a Pokémon looks strong, tired, or ready to keep fighting, and now, battles play **out in the overworld** with dynamic reactions and focus-based mechanics for a more cinematic feel.

<p align="center">
  <img width="550" height="410" alt="ezgif com-optimize" src="https://github.com/user-attachments/assets/cd3cd582-08dc-4b5a-8e24-87603efa9c53" style="display: inline-block; margin-right: 8px;" />
  <img width="550" height="410" alt="added-animations-ezgif com-optimize" src="https://github.com/user-attachments/assets/74ea5cd7-0f45-41cd-ab26-db53226e0c43" style="display: inline-block;" />
</p>
<p align="center">
  <img width="400" height="298" alt="water" src="https://github.com/user-attachments/assets/eb277dcf-562a-4adc-a44d-481071a1c10a" style="display: inline-block; vertical-align: top; margin-right: 8px;" />
  <img width="400" height="298" alt="wild-encounter" src="https://github.com/user-attachments/assets/6f86a3a4-6e48-43c2-a0df-c94ac85b4449" style="display: inline-block; vertical-align: top;" />
</p>
<img width="800" height="614" alt="caves-ezgif com-video-to-gif-converter" src="https://github.com/user-attachments/assets/56d2ea5f-9469-493f-8d89-b78ed2815563" />






> **Important Note:**  
> This mod is not an engine overhaul or a competitive balance patch. It is designed for immersion and guided by anime logic and feel, not for tournament fairness or transparency. Most mechanics are explained in spirit or flavor-first — for technical engine or API boundaries, see [ARCHITECTURE.md](./ARCHITECTURE.md).


> **Need help or found a bug?**  
> [![Discord](https://img.shields.io/badge/discord-blue?logo=discord&logoColor=white)](https://discord.com/channels/1019387038820216882/1536576688526336122)  
> Reach out to the developer in the [Anime Realism Discord channel](https://discord.com/channels/1019387038820216882/1536576688526336122).



## Compatibility

FIELD sits on the live overworld. This is the companion stack and Dramatic Shape / Dramaless settings currently used with this mod. Anime Realism itself has no hard deps; without the mods below you still get hidden numbers and REACT, but FIELD battlers and the voxel map will be missing or flat.

> **📣 Note:**
> **Latest Working gen1recomp Version:** `0.1.86`

## General Settings for Optimized Play

`battle speed`: 2x

### Companion mods

Enable **one** voxel world mod only — Dramatic Shape, Dramaless Shape, and Potato Voxel conflict.

| Mod | Id | Why | Working Release |
|-----|----|-----|-----|
| [Dramatic Shape](https://github.com/DramaticShape/DramaticShapeVoxelMod) or [Dramaless Shape](https://github.com/artyrambles/DRAMALESS_SHAPE) | `DRAMATIC_SHAPE` / `DRAMALESS_SHAPE` | Voxel overworld under FIELD. Staging is gated so a 3D arena does not cover map fights. | n/a |
| [Wilds of Kanto](https://github.com/YoDrehDenSwagAuf/overworld-spawn-mod) | `overworld_wild_spawns` | Visible wilds plus overworld sheets FIELD can use | n/a |
| [PokéPC Followers (Voxel Merge)](https://github.com/mfrtechconsult/PokePCFollowers) | `PokePCFollowers_VoxelMerge` | GSC-style follower / battler sheets | n/a |
| [Followers EX](https://github.com/masterwebx/gen1recomp-followers-ex) | `FOLLOWERS_EX` | Follower control on voxel maps (needs PokéPC Followers + Wilds) | n/a |
| [Weather FX](https://github.com/MrKrisSatan/Weather-fx) | `Weather-fx` | Recommended. Adds dynamic weather effects (rain, snow, sandstorm, etc.) to the overworld battles for extra immersion. | 4.10.0 |
| [Battle Cinematics](https://github.com/EnterPlayerOne/Battle-Cinematics-Stadium-Camera) | `BATTLE_CINEMATICS` | Optional. Again! / extra swings re-emit `battle.move_used` | n/a |
| [Quality of Life](https://github.com/unxpected-uxp/pokemon-gen1-recomp-mod-qol) | `quality_of_life` | Optional HUD/XP helpers (skipped while FIELD compact UI is up) | n/a |
| Gen 3 Inspired UI | `gen3_battle_ui` | Optional; skipped during FIELD compact UI | n/a |

Leave **Stadium Overworld Models** (`STADIUM_OVERWORLD_MODELS`) and **Stadium Battle FX** (`STADIUM_BATTLE_FX`) off. FIELD owns the fight; Stadium staging and FX fight that presentation.

On this install, Anime Realism is **BATTLE STAGE = FIELD** and **FIELD SPRITES = HGSS**.

If you didn't catch it above: 

> Set your `battle speed`: `2x` to make the battles flow more nicely.

### Dramatic Shape / Dramaless settings

Same OPTIONS rows on Dramatic Shape and Dramaless Shape. Values below are the current saved set (Dramatic Shape 1.8.1).

| Row | Value | Notes |
|-----|-------|-------|
| **VOXEL** | `35` | Keep a walking camera on (not `OFF`) so FIELD has a 3D map |
| **T-SHIFT** | `1` | Tilt-shift blur on the diorama |
| **3D-BTL** | `2D-3D A` | Can stay on; FIELD still blocks DS from staging a separate arena. Do not use `STADIUM A` / `STADIUM B` |
| **BACK SPRITES** | `OFF` | FIELD uses overworld battler sprites, not GB back pics |
| **WATER** | `FULL` | Sky + shoreline reflections |
| **V-CURVE** | `2` | Horizon bend |
| **V-GRID** | `ON` | Voxel edge wireframe |
| **FOREST FX** | `FULL` | Haze / light shafts in woods |
| **AA** | `4X` | Drop to `2X` or `OFF` if the machine stutters |
| **SHINY ODDS** | `1:256` | Unrelated to FIELD; included because it is on this save |

If Potato Voxel is installed, leave it **disabled** while Dramatic Shape or Dramaless is on.

## Why hide levels too?

HP bars make every fight about percentages. Levels do the same for power: you start comparing numbers instead of reading the matchup. In the anime, nobody calls out “it’s only level 12” — a Pokémon is just tough, green, or clearly outmatched, and growth is “they’ve gotten stronger,” not “+1 to the counter.”

So levels stay hidden for the same reason as HP: keep decisions grounded in what you see in battle and how your team feels, not in a spreadsheet. The optional generic level-up / EXP lines lean into that — you still get stat gains and new moves, without the level number breaking the immersion.

## Features

- **Always on:** Levels and HP numbers/classic bars are hidden in battle, party,
  summary, and related UI. FIELD uses slim proportional bars without numbers.
  Generic level-up flavor, anime move callouts, speech bubbles, trainer banter,
  underdog EXP, and effort-faint consolations are part of
  the same feel (not extra toggles).
- **Reactive Defense:** Focus-meter reactions under fire — **Commit / Dodge / Take Cover / Brace / Entrench**. Toggle **REACTIVE DEF**; pick how often the menu appears via **REACT MENU** (ALWAYS / THREAT / OFF). Trainer foes still auto-react; your physical **COUNTER** openings and **Again!** remain.
- **Field Battles:** Wild and trainer single battles can stay on the live map (**BATTLE STAGE = FIELD**), with both Pokémon represented by grid-tracked overworld sprites while the normal battle rules and menus remain in control.
- **Field choreography:** Contact slashes, projectiles, beams, area rings, and status effects play in world space; switching recalls the old Pokémon before the replacement appears; Poké Balls arc toward wild targets and resolve their shakes/capture on the field.

## Mechanics

### Reactive Defense (Focus)

The overhauled battle system to create a more anime-like experience. Requires **REACTIVE DEF**. Your reactions use a **Focus** meter (starts at 50, caps around 75 and scales a bit with level / base Speed).

See the detailed [The REACT Battle System Design](./battle/OVERVIEW.md) for full mechanics and examples.

### Trainer foe reactions

- Once per turn when you use a damaging move: special → dodge attempt, physical → brace (with the same random harden-style sparkle on their mon). Lines are **opposing trainer orders** (e.g. `BROCK: Onix, dodge!`), not narrator flavor.
- Foe dodge can fail (same fail roll as yours); success → EVADE **+1**; brace → DEF **+1**.
- Foe counter arms when **you miss** them, or rarely (~20%) when your **physical** hit lands; then ~**50%** they take the counter (**+25%** once) on their next attack.
- After a foe counter that lands, ~**40%** chance they also **Again!** (same true second-hit rules).
- Foe cover clears when they attack (with a short leave-cover line when they had cover).
- Enemy switch clears foe cover / counter state.

### Underdog EXP

When a living mon gains EXP for a KO:

- Foe level − your level ≥ **8** → about **1.5×** that share  
- Gap ≥ **4** → about **1.25×**  
- Cap: never more than **+50%** or **+80** raw over the vanilla share

### Effort faint

If a mon fought well then fainted before EXP award:

- “Fought well” ≈ dealt ≥ **25%** of foe max HP, or ≥ **2** moves and ≥ **5** damage
- Awards ~**1/5** of the foe’s undivided base-stat yield as Gen 1 stat exp (plus a tiny EXP crumb and a short flavor line)
- Once per mon per battle

### Immersion helpers

- **GENERIC LVL UP** — no “grew to level N”; EXP-gain dialogue is always hidden
- **ANIME MOVES** — trainer-style announce lines; finish-flavored lines when the foe looks weak (same threshold as LOW HP AT)
- **LOW HP WARN** / **MUTE HP ALARM** — soft cues instead of spreadsheet HP

### Field Battles

Set **BATTLE STAGE** to `FIELD` to use the overworld presentation for ordinary
wild and trainer single battles. Link, demo, doubles, and other special battles
remain on their normal presentation path.

- The map remains visible beneath a compact FIELD interface: tiny proportional
  HP bars follow the Pokémon in world space, with smaller command/move panels
  and a narrow dialogue overlay. Party, Bag, naming, and forced-switch screens
  remain engine-owned.
- FIELD skips companion battle-UI foreground passes so the compact menu is the
  only command layer. HP bars render in each Pokémon's world draw pass, keeping
  them attached through camera movement and bobbing.
- During FIELD message beats, the large bottom panel yields to small speech
  popups. Common narration is condensed (`DEFENSE DOWN!`, `CRITICAL!`,
  `MISSED!`) and speaker bubbles track the active Pokémon. Lines auto-advance
  about every 1.5 seconds so fights flow into the move HUD. On the
  move list or diamond (end of turn), **B** pauses into FIGHT / PKMN / ITEM / RUN.
  Pick FIGHT to return to moves. During dialogue, **B** pauses a
  toast; **A** or **B** again resumes.
- FIELD move selection defaults to a compact full-width **classic** 2×2
  (U/R/L/D labels, D-pad moves the cursor, **A** confirms). **MOVE HUD**
  `DIAMOND` keeps the compass layout and instant-casts on that direction.
  The **REACT!** menu defaults to that same 2×2 (`REACT HUD` **GRID**) and
  tints from the player's **COLORS** option. **TABS** slides a one-row strip
  up from the bottom of the screen, each choice a slightly different soft
  color.
  Trainers step aside when a Pokémon moves onto or beside them.
- Trainers and Pokémon begin on a compact 5×3 formation, then move across a
  read-only surveyed fight envelope (normally about 9×7 nearby tiles).
- Water, warps, blocked map cells, and unrelated overworld entities are excluded
  from movement. The map itself is never edited.
- Each Pokémon owns a tracked pad cell; pixel movement is derived from that cell.
- Idle Pokémon use a gentle vertical overworld-style bob without horizontal sway.
- Physical moves step toward the target, special/status moves cast in place,
  and hits recoil or faint without changing battle calculations.
- Switches use recall/send-out scale animations. Capture throws and special-move
  projectiles are overworld entities, so they stay aligned with the active
  world camera.
- `PokePCFollowers_VoxelMerge`, `FOLLOWERS_EX`, or **Wilds of Kanto** supplies
  overworld sheets. **FIELD SPRITES** picks the set: `AUTO` matches Wilds'
  Sprite Style when that mod is loaded, otherwise GSC followers. `GSC` /
  `HGSS` / `POKEDEX` force a pack. A visible placeholder is used if no art is
  found.
- Hybrid voxel mode is preserved: the voxelized map remains active while the
  Pokémon and generic FIELD effects use animated 2D overworld sprites. FIELD
  suppresses duplicate staged arenas. On battle exit the pre-battle voxel
  pipeline level is restored so the free-roam overlay resets.
- Generated cover remains session-only and is kept sparse and small so the live
  map—not an artificial arena—stays visually dominant.
- Ending by victory, capture, run, or blackout restores the original map
  entities, player pose, input state, camera, and zoom.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| **BATTLE STAGE** | FIELD | `FIELD` keeps wild/trainer singles on the live map; `AUTO` leaves other presentation mods alone |
| **FIELD SPRITES** | AUTO | Overworld battler art. `AUTO` follows Wilds of Kanto Sprite Style when that mod is on, else GSC followers. `GSC` / `HGSS` / `POKEDEX` pick a pack |
| **MOVE HUD** | CLASSIC | FIELD fight menu. `CLASSIC` is a compact full-width 2×2 with U/R/L/D labels (D-pad + **A**). `DIAMOND` is the compass with instant-cast |
| **REACTIVE DEF** | On | Focus reactions (Commit/Dodge/Cover/Brace/Entrench); COUNTER → Again!; trainer foes may mirror |
| **REACT MENU** | ALWAYS | `ALWAYS` = Focus **REACT!** every damaging hit; `THREAT` = serious hits only; `OFF` = no Focus menu |
| **REACT HUD** | GRID | `GRID` is the compact 2×2 (U/R/L/D + **A**). `TABS` is a one-row strip that slides up from the bottom, each choice a soft tint |
| **CLOSE THE GAP** | On | Physical attacks close to the foe when more than a tile away, then idle 1–2 tiles off instead of returning home. Gait follows Speed; Attack adds a boost, with a cap so fast mons do not teleport |
| **DEV OVERLAY** | Off | Compact top-right battle debug chip (live cover/counter + last event) |


## Layout

Three packages under one mod:

| Package | Role |
|---------|------|
| `hud/` | HP / EXP / numbers feel (hide HUD, underdog EXP, effort faint) |
| `battle/` | The overhauled REACT battle system math |
| `field/` | Overworld FIELD combat (tile-grid cast + OW sprites) |

`main.lua` orchestrates options + shared hooks. `lib/modload.lua` loads folder packages for zip and loose installs. How the pieces connect: [`architecture.md`](architecture.md). FIELD pad rules: [`field/SPEC.md`](field/SPEC.md).

## License

Original code and writing in this repository are licensed under
[Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
(`LICENSE`). You may copy, modify, and redistribute it — including as a
derived mod — if you credit **Anime Realism** / **businessmachines02** and
link to [this repository](https://github.com/businessmachines02/anime-realism).
Keep `LICENSE`, and note your changes.

## Files

- `manifest.json` — mod metadata
- `main.lua` — orchestrator + shared hooks
- `lib/modload.lua` — package loader
- `hud/` — hide numbers + EXP/effort rewards
- `battle/` — battle systems (`reactive_defense.lua` lives here)
- `field/` — overworld FIELD combat (tile-grid movement tracker)
- `LICENSE` — CC BY 4.0 (attribution required)
- `DIFFERENCES.md` — what this mod changes from vanilla
- `build.sh` — local zip for testing
- `.github/workflows/release.yml` — Gen1Recomp launcher release pipeline

---

Developed with ❤️ by **businessmachines02**.
