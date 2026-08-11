# Anime Realism

A [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) mod for anime-style immersion: hide levels and HP everywhere so you play by feel instead of numbers. In the anime you never see a health bar or level — just whether a Pokémon looks strong, tired, or ready to keep fighting.

**Current build:** `1.9.3` (`anime_realism-1.9.3.zip`)

## Why hide levels too?

HP bars make every fight about percentages. Levels do the same for power: you start comparing numbers instead of reading the matchup. In the anime, nobody calls out “it’s only level 12” — a Pokémon is just tough, green, or clearly outmatched, and growth is “they’ve gotten stronger,” not “+1 to the counter.”

So levels stay hidden for the same reason as HP: keep decisions grounded in what you see in battle and how your team feels, not in a spreadsheet. The optional generic level-up / EXP lines lean into that — you still get stat gains and new moves, without the level number breaking the immersion.

## Features

- **Always on:** Levels and HP numbers/bars are hidden in battle, party, summary, and related UI (including Gen 3 Inspired UI).
- **Party list:** Instead of HP, low-health Pokémon show short heal hints (e.g. `WEAK-HEAL SOON!`). Fainted mons get a fainted hint.
- **Battle level-ups / EXP (optional):** Replaces “grew to level N” and numeric EXP gain lines with generic growth flavor. Stat gains and move learning still work as usual.
- **Anime move calls (optional):** Turns “PIKACHU used THUNDERBOLT!” into trainer-style callouts for you and opposing trainers. Long names wrap to fit the 18-column box. Wild battles keep the vanilla line.
- **Momentum / callouts (optional):** Dodge, brace, and counter for you; trainer foes auto-react. **COUNTER** can follow with a true second hit (**Again!**); foes may mirror that after their counter. Temporary cover buffs clear when that side attacks. Callout orders apply stage changes **quietly** (no vanilla “rose!” / “fell!” text after you already gave the order).
- **Underdog EXP (optional):** A clearly weaker Pokémon that helps KO a stronger foe gets capped bonus EXP.
- **Effort faint (optional):** If a Pokémon fights well then faints, it still earns Gen 1 stat exp (plus a tiny EXP crumb) — vanilla would give it nothing.
- **Optional battle HUD / XP bar hide**, low-HP warnings, mute HP alarm.

## Mechanics

### Momentum overview

Requires **MOMENTUM HIT**. Works in trainer (and link) battles for foe reactions; your dodge/brace/counter also apply in wild fights when a foe hits you.

| Situation | Special attacks | Physical attacks |
|-----------|-----------------|------------------|
| **You** under fire | Dodge (evasion up; can fail) | Brace (defense up) |
| **You** after taking a physical hit | — | Next damaging reply: **COUNTER** / **HOLD** |
| **Trainer foe** under your attack | Auto-dodge once/turn | Auto-brace once/turn |
| **Trainer foe** after you hit them physically | — | ~50% auto-counter on their next hit |

### Dodge & brace (you)

1. Foe announces a damaging move.
2. **CALLOUT PICK** decides whether you get a location menu or an auto callout:
   - **THREAT** (default) — menu on serious hits (see below).
   - **ALWAYS** — menu on every damaging hit.
   - **OFF** — auto flavor only (no menu).
3. Location / type picks use the map scene (cave, forest, gym, …) plus type extras (e.g. FLY UP, DIVE). Stronger picks can apply **+2** stages; basic DODGE/BRACE are **+1**.
4. Successful **dodge** applies temporary **EVADE**, may hide your sprite (Dig/Fly-style slide/teleport), then the hit resolves with accuracy against that EVADE.
5. If you’re in cover and the attack **still hits**, a console line calls it out (e.g. “But it found PIKACHU!”).
6. If you’re in cover and the attack **misses**, the move anim still plays (whiffs past cover) and miss text becomes a dodge line instead of vanilla “attack missed!”.
7. **Brace** applies temporary **DEF** and a short blink — no hide. Basic brace is **+1 DEF**. Strong brace picks (**DIG IN** / “Entrench!”) put you **entrenched**: DEF pushed toward stage **+6** while you weather a barrage and wait for a **COUNTER** opening (foe miss, or rare physical connect). Each hit has ~**18%** chance to **break through** — DEF returns to normal for that hit (usual damage). Leaving stance to attack clears the temp DEF as usual.
8. Dodge can fail (chance depends on **CALLOUT STYLE**): roughly **20%** TRICKY, **25%** BOLD, **30%** AUTO, **35%** SHOWY.

### Cover buffs (add / remove)

- Temp EVADE/DEF from dodge/brace are tracked per side.
- When **that side attacks**, cover buffs are stripped (silent stage undo).
- If **you** leave cover to strike **first**, you also take a silent **DEF −1** risk and get a short “left cover” line.
- Trainer foes get the same add-on-cover / clear-on-attack pattern (no Dig/Fly hide for foes yet).
- With **CALLOUT BUFFS** on, stage changes from callouts still apply, but dialogue does **not** spam “rose!” / “fell!” after an order.

### Counter (you)

1. Counter arms when the foe **misses** you with a damaging move (dodge EVADE helping here is the usual path), or on a rare **~20%** chance when a **physical** hit still lands.
2. On your next **damaging** move (while armed), a **COUNTER** / **HOLD** menu appears (deferred so it runs before damage).
3. **COUNTER:** callout flavor, foe **DEF** drops (quiet), your hit deals **+25%** once.
4. If the foe **survives** that counter hit → **Again!** — a true second strike (fresh anim + damage roll, no extra PP, no double recoil/secondaries). Skipped for Explosion / Selfdestruct / Struggle / the move Counter.
5. **HOLD:** no boost; arming clears.
6. Order when counter is armed: your announce → **COUNTER/HOLD** → foe dodge/brace (if any) → hit. (Foe reactions are deferred so they don’t sit in front of the counter menu.)
7. Arming can survive across turn boundaries until you use it or hold.

### Trainer foe reactions

- Once per turn when you use a damaging move: special → dodge attempt, physical → brace. Lines are **opposing trainer orders** (e.g. `BROCK: Onix, dodge!`), not narrator flavor.
- Foe dodge can fail (same fail roll as yours); success → EVADE **+1**; brace → DEF **+1**.
- Foe counter arms when **you miss** them, or rarely (~20%) when your **physical** hit lands; then ~**50%** they take the counter (**+25%** once) on their next attack.
- After a foe counter that lands, ~**40%** chance they also **Again!** (same true second-hit rules).
- Foe cover clears when they attack (with a short leave-cover line when they had cover).
- Enemy switch clears foe cover / counter state.

### CALLOUT PICK — when THREAT opens the menu

A damaging foe move is “threat” if any of these hold:

- Your HP is at or below **LOW HP AT**
- Move power ≥ **80**
- Special move with power ≥ **40**
- Foe is ≥ **5** levels above you
- First meaningful foe hit this turn with power ≥ **40** (once)

Damage is deferred until after the pick so EVADE from dodge can affect accuracy.

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

- **GENERIC LVL UP** — no “grew to level N” / raw EXP numbers in battle text
- **ANIME MOVES** — trainer-style announce lines; finish-flavored lines when the foe looks weak (same threshold as LOW HP AT)
- **LOW HP WARN** / **MUTE HP ALARM** — soft cues instead of spreadsheet HP

## Options

| Option | Default | Description |
|--------|---------|-------------|
| **HIDE BATTLE HUD** | On | Hide the battle status HUD entirely |
| **HIDE XP BAR** | On | Hide the battle XP bar |
| **LOW HP WARN** | On | Show weak/tired messages in battle |
| **LOW HP AT** | 20% | Threshold for warnings (`20%` or `40%`) |
| **MUTE HP ALARM** | On | Silence the low-HP alarm |
| **GENERIC LVL UP** | On | Generic growth / EXP text (no level or EXP numbers) |
| **ANIME MOVES** | On | Trainer-style move callouts for you & trainers (not wild) |
| **MOMENTUM HIT** | On | Dodge/brace/counter; COUNTER → Again! second hit; trainer foes may mirror |
| **CALLOUT STYLE** | AUTO | Flavor tone + dodge fail rate (`AUTO` / `BOLD` / `TRICKY` / `SHOWY`) |
| **CALLOUT BUFFS** | On | Apply EVADE/DEF (and counter DEF drop) from callouts — quietly, no rose/fell spam |
| **CALLOUT PICK** | THREAT | `THREAT` = menu on serious hits; `ALWAYS` = every hit; `OFF` = auto only |
| **UNDERDOG EXP** | On | Capped bonus EXP when a much weaker mon helps score the KO |
| **EFFORT FAINT** | On | Stat-exp consolation when a mon fights well then faints |

## Install

1. Zip `manifest.json` and `main.lua` at the **root** of the archive (or use `./build.sh` / a prebuilt `anime_realism-*.zip`).
2. In Gen1Recomp, import the zip via the mod manager — or copy the folder into:

   `~/Library/Application Support/pokemon-love2d/mods/anime_realism/`

3. Enable the mod and restart/reload if needed.

Requires `engine_internals` permission (declared in the manifest).

## Compatibility

Works with the stock battle UI. Optional companions:

- **Dramatic Shape** (`DRAMATIC_SHAPE`)
- **Dramaless Shape** (`DRAMALESS_SHAPE`) — Stadium models
- **StadiumBattleFX** (`STADIUM_BATTLE_FX`) — Stadium move VFX (load priority 110; Anime Realism is 200 for HUD/text). Dig/Fly-style dodge hides still play alongside Stadium/Dramaless.
- **Quality of Life** (`quality_of_life`) — XP bar suppression
- **Gen 3 Inspired UI** (`gen3_battle_ui`)

## Files

- `manifest.json` — mod metadata (version `1.9.3`)
- `main.lua` — all behavior
- `build.sh` — builds `anime_realism-<version>.zip`
