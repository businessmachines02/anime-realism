# Anime Realism

A [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) mod for anime-style immersion: hide levels and HP everywhere so you play by feel instead of numbers. In the anime you never see a health bar or level — just whether a Pokémon looks strong, tired, or ready to keep fighting.

**Current build:** `4.5.20` (`anime_realism-4.5.20.zip`)

## Why hide levels too?

HP bars make every fight about percentages. Levels do the same for power: you start comparing numbers instead of reading the matchup. In the anime, nobody calls out “it’s only level 12” — a Pokémon is just tough, green, or clearly outmatched, and growth is “they’ve gotten stronger,” not “+1 to the counter.”

So levels stay hidden for the same reason as HP: keep decisions grounded in what you see in battle and how your team feels, not in a spreadsheet. The optional generic level-up / EXP lines lean into that — you still get stat gains and new moves, without the level number breaking the immersion.

## Features

- **Always on:** Levels and HP numbers/classic bars are hidden in battle, party,
  summary, and related UI. FIELD uses slim proportional bars without numbers.
- **Party list:** Instead of HP, low-health Pokémon show short heal hints (e.g. `WEAK-HEAL SOON!`). Fainted mons get a fainted hint.
- **Battle level-ups (optional):** Replaces “grew to level N” with generic growth flavor. Stat gains and move learning still work. Raw EXP-gain dialogue is hidden.
- **Anime move calls (optional):** Turns “PIKACHU used THUNDERBOLT!” into trainer-style callouts for you and opposing trainers. Long names wrap to fit the 18-column box. Wild battles keep the vanilla line.
- **Reactive Defense (optional):** Focus-meter reactions under fire — **Commit / Dodge / Take Cover / Brace / Entrench**. Menu option **REACTIVE DEF**; pick frequency via **REACT MENU** (ALWAYS / THREAT / OFF). Trainer foes still auto-react; your physical **COUNTER** openings and **Again!** remain. Optional **SPEECH BUBBLE** replaces the classic battle text box with chat bubbles (you left / foe right / narrator center).
- **Underdog EXP (optional):** A clearly weaker Pokémon that helps KO a stronger foe gets capped bonus EXP.
- **Effort faint (optional):** If a Pokémon fights well then faints, it still earns Gen 1 stat exp (plus a tiny EXP crumb) — vanilla would give it nothing.
- **Field Battles (optional):** Wild and trainer single battles can stay on the live map, with both Pokémon represented by grid-tracked overworld sprites while the normal battle rules and menus remain in control.
- **Field choreography:** Contact slashes, projectiles, beams, area rings, and status effects play in world space; switching recalls the old Pokémon before the replacement appears; Poké Balls arc toward wild targets and resolve their shakes/capture on the field.
- **Optional battle HUD / XP bar hide**, low-HP warnings, mute HP alarm.

## Mechanics

### Reactive Defense (Focus)

Requires **REACTIVE DEF**. Your reactions use a **Focus** meter (starts at 50, caps around 100 and scales a bit with level / base Speed).

| Option | Cost | Effect |
|--------|------|--------|
| **COMMIT** | 0 | Take the hit; bank Focus regen (+15 end of turn if you didn't react) |
| **DODGE** | 25 | Speed check — miss or take +30% and lose priority next |
| **TAKE COVER** | 20 | Durability pool from Defense (type bonus for Ground/Water/Ghost); soak hits |
| **BRACE** | 15 | Call Physical / Special / Status — correct call cuts damage; wrong call hurts more |
| **ENTRENCH** | 30 | Lock 2–3 turns of heavy mitigation; FIGHT offers HOLD / BREAK |

- **REACT MENU:** ALWAYS (default) / THREAT / OFF. OFF skips the menu (hits resolve without Focus spends).
- End of turn: +5 Focus if you reacted, +15 if you Committed (or didn't spend a react).
- **Cover:** while sheltered, FIGHT offers **EMERGE** (−10 Focus, exposed next hit) or **STAY**. Pierce moves (Earthquake, Surf, …) and unreactables chew durability harder.
- **Unreactable** starters: Explosion / Selfdestruct / Hyper Beam — Dodge/Brace disabled; Cover still possible but fragile.
- **Entrench:** incoming hits auto-soak with mitigation while locked; HOLD / BREAK on your turn (early break refunds a little Focus).
- Legacy trainer-foe auto dodge/brace and your physical **COUNTER** / **Again!** path still apply alongside Focus.

1. Counter arms when the foe **misses** you with a damaging move (dodge EVADE helping here is the usual path), or on a rare **~20%** chance when a **physical** hit still lands.
2. If you attack while armed (going first or second): the announce is only **“Counter with X!”** (no generic move callout under it), the hit deals **+25%** once — no OPENING! menu.
3. Same-round **COUNTER!** (pick a move / HOLD) only appears after a **successful dodge** and the foe’s attack **misses** — after the miss anim and “dodged aside!” line. Failed dodges never open it.
4. Going **second**: that panel can **change moves** from your turn-start pick (or **HOLD** to keep the plan without the counter boost). Going **first**: it fires an immediate extra counter strike.
5. **Risk (light):** counter swings have only ~**5%** extra miss chance. If your counter **misses**, there is a ~**40%** chance the foe snaps back for about **half** the damage their whiffed hit would have done (otherwise it’s just a normal miss).
6. If the foe **survives** that counter hit → a varied **Again!** callout (opening / flinch / pressure flavor, not just “Again!”) — a true second strike (fresh anim + damage roll + re-armed Stadium / Battle Cinematics attack camera, no extra PP, no double recoil/secondaries). Skipped for Explosion / Selfdestruct / Struggle / the move Counter.
7. **HOLD** (same-round panel only): no boost; arming clears (going second: your original move still happens).
8. Arming can survive across turn boundaries until you spend it on an attack.

### Trainer foe reactions

- Once per turn when you use a damaging move: special → dodge attempt, physical → brace (with the same random harden-style sparkle on their mon). Lines are **opposing trainer orders** (e.g. `BROCK: Onix, dodge!`), not narrator flavor.
- Foe dodge can fail (same fail roll as yours); success → EVADE **+1**; brace → DEF **+1**.
- Foe counter arms when **you miss** them, or rarely (~20%) when your **physical** hit lands; then ~**50%** they take the counter (**+25%** once) on their next attack.
- After a foe counter that lands, ~**40%** chance they also **Again!** (same true second-hit rules).
- Foe cover clears when they attack (with a short leave-cover line when they had cover).
- Enemy switch clears foe cover / counter state.

### REACT MENU — when THREAT opens the menu

A damaging foe move is “threat” if any of these hold:

- Your HP is at or below **LOW HP AT**
- Move power ≥ **80**
- Special move with power ≥ **40**
- Foe is ≥ **5** levels above you
- First meaningful foe hit this turn with power ≥ **40** (once)

Damage is deferred until after the Focus pick so Dodge misses / Brace mults / Cover soak apply.

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
  about every 1.5 seconds so fights flow into the directional move grid. On the
  move diamond (end of turn), **Right Shift** pauses into FIGHT / PKMN / ITEM /
  RUN; Right Shift again returns to moves. During dialogue, **B** pauses a
  toast; **A** or **B** again resumes.
- FIELD move selection is a diamond `U/R/L/D` compass (covers the classic
  TYPE/PP panel). Pressing that direction immediately casts the matching move.
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
  suppresses classic/Stadium battle chrome and duplicate staged arenas; Stadium
  visuals remain available when BATTLE STAGE is not FIELD. On battle exit the
  pre-battle voxel pipeline level is restored so the free-roam overlay resets.
- Generated cover remains session-only and is kept sparse and small so the live
  map—not an artificial arena—stays visually dominant.
- Ending by victory, capture, run, or blackout restores the original map
  entities, player pose, input state, camera, and zoom.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| **HIDE BATTLE HUD** | On | Hide the battle status HUD entirely |
| **HIDE XP BAR** | On | Hide the battle XP bar |
| **LOW HP WARN** | On | Show weak/tired messages in battle |
| **LOW HP AT** | 20% | Threshold for warnings (`20%` or `40%`) |
| **MUTE HP ALARM** | On | Silence the low-HP alarm |
| **GENERIC LVL UP** | On | Generic level-up text (EXP-gain dialogue is always hidden) |
| **ANIME MOVES** | On | Trainer-style move callouts for you & trainers (not wild) |
| **BATTLE STAGE** | AUTO | `FIELD` enables wild/trainer overworld presentation; `AUTO`/`STADIUM` keep their existing presentation |
| **FIELD SPRITES** | AUTO | Overworld battler art. `AUTO` follows Wilds of Kanto Sprite Style when that mod is on, else GSC followers. `GSC` = Poke Followers / Crystal Clear; `HGSS` = Wilds HGSS / PokeMMO; `POKEDEX` = Wilds Pokédex |
| **REACTIVE DEF** | On | Focus reactions (Commit/Dodge/Cover/Brace/Entrench); COUNTER → Again!; trainer foes may mirror |
| **CALLOUT STYLE** | AUTO | Flavor tone for callouts (`AUTO` / `BOLD` / `TRICKY` / `SHOWY`) |
| **CALLOUT BUFFS** | On | Apply foe EVADE/DEF (and counter DEF drop) from callouts — quietly, no rose/fell spam |
| **REACT MENU** | ALWAYS | `ALWAYS` = Focus **REACT!** every damaging hit; `THREAT` = serious hits only; `OFF` = no Focus menu |
| **SPEECH BUBBLE** | On | Hides the classic battle text box (and Gen 3 / Dramatic Shape dialogue panels) during dialogue. Bubbles sit along the bottom (you left / foe right / narrator center) with tails aimed up at the field; layered shadow, accent bar, blink continue cue; typed a bit slower; **A/B** to continue (engine auto lines still auto-advance). FIGHT / move menus still use the normal bottom UI. |
| **TRAINER BANTER** | On | Large persona pools (kid / cocky / evil / gym / rival / spooky / nerd / chill / generic) for send-outs plus context idle lines (ahead / behind / low HP / long fight); rivals banter most often. While a banter line plays, the trainer sprite slides in from the right (flat battles). With **3D-BTL** staged fights, the foe trainer briefly takes the enemy billboard (same intro seam) and the camera eases toward that side, then both restore when the line clears |
| **STATUS CHIPS** | On | Tiny top-left (you) / top-right (foe) narrative chips; update only after callouts/state settle (no menu previews, no stage numbers) — e.g. “SCYTHER is hiding in brush”, “BLASTOISE is holding the trench!”, “ready to counter!” |
| **FOCUS CHIP** | On | Slim top-left Focus meter (`F` + bar); sits above your status chip; hides under a player speech bubble |
| **UNDERDOG EXP** | On | Capped bonus EXP when a much weaker mon helps score the KO |
| **EFFORT FAINT** | On | Stat-exp consolation when a mon fights well then faints |
| **DEV OVERLAY** | Off | Compact top-right battle debug chip (live cover/counter + last event). Full sequence appends to `anime_realism_dev.log` in the Gen1Recomp save directory |

## Install

1. Run `./build.sh` (or use a prebuilt `anime_realism-*.zip`). The zip keeps package folders.
2. In Gen1Recomp, import the zip — or copy the mod folder into:

   `~/Library/Application Support/pokemon-love2d/mods/anime_realism/`

3. Enable the mod and restart/reload if needed.

Requires `engine_internals` permission (declared in the manifest).

## Layout

Three packages under one mod:

| Package | Role |
|---------|------|
| `immersion/` | HP / EXP / numbers feel (hide HUD, underdog EXP, effort faint) |
| `battle/` | Traditional battle systems (Reactive Defense, callouts, bubbles, banter, chips) |
| `field_battle/` | Overworld FIELD combat (tile-grid cast + OW sprites) |

`main.lua` orchestrates options + shared hooks. `lib/modload.lua` loads folder packages for zip and loose installs.

## Compatibility

Works with the stock battle UI. Optional companions:

- **Dramatic Shape** (`DRAMATIC_SHAPE`)
- **Dramaless Shape** (`DRAMALESS_SHAPE`) — Stadium models
- **StadiumBattleFX** (`STADIUM_BATTLE_FX`) — Stadium move VFX (load priority 110; Anime Realism is 200 for HUD/text). Dig/Fly-style dodge hides still play alongside Stadium/Dramaless.
- **Quality of Life** (`quality_of_life`) — XP bar suppression
- **Gen 3 Inspired UI** (`gen3_battle_ui`)

## Files

- `manifest.json` — mod metadata
- `main.lua` — orchestrator + shared hooks
- `lib/modload.lua` — package loader
- `immersion/` — immersion package
- `battle/` — battle systems (`reactive_defense.lua` lives here)
- `field_battle/` — overworld FIELD combat (tile-grid movement tracker)
- `build.sh` — builds `anime_realism-<version>.zip`
