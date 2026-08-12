# Anime Realism

A [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) mod for anime-style immersion: hide levels and HP everywhere so you play by feel instead of numbers. In the anime you never see a health bar or level — just whether a Pokémon looks strong, tired, or ready to keep fighting.

**Current build:** `2.0.8` (`anime_realism-2.0.8.zip`)

## Why hide levels too?

HP bars make every fight about percentages. Levels do the same for power: you start comparing numbers instead of reading the matchup. In the anime, nobody calls out “it’s only level 12” — a Pokémon is just tough, green, or clearly outmatched, and growth is “they’ve gotten stronger,” not “+1 to the counter.”

So levels stay hidden for the same reason as HP: keep decisions grounded in what you see in battle and how your team feels, not in a spreadsheet. The optional generic level-up / EXP lines lean into that — you still get stat gains and new moves, without the level number breaking the immersion.

## Features

- **Always on:** Levels and HP numbers/bars are hidden in battle, party, summary, and related UI (including Gen 3 Inspired UI).
- **Party list:** Instead of HP, low-health Pokémon show short heal hints (e.g. `WEAK-HEAL SOON!`). Fainted mons get a fainted hint.
- **Battle level-ups (optional):** Replaces “grew to level N” with generic growth flavor. Stat gains and move learning still work. Raw EXP-gain dialogue is hidden.
- **Anime move calls (optional):** Turns “PIKACHU used THUNDERBOLT!” into trainer-style callouts for you and opposing trainers. Long names wrap to fit the 18-column box. Wild battles keep the vanilla line.
- **Momentum / callouts (optional):** Dodge, brace, and counter for you; trainer foes auto-react. **COUNTER** can follow with a true second hit (**Again!**); foes may mirror that after their counter. Temporary cover buffs clear when that side attacks. Callout orders apply stage changes **quietly** (no vanilla “rose!” / “fell!” text after you already gave the order). Optional **SPEECH BUBBLE** replaces the classic battle text box with chat bubbles (you left / foe right / narrator center).
- **Underdog EXP (optional):** A clearly weaker Pokémon that helps KO a stronger foe gets capped bonus EXP.
- **Effort faint (optional):** If a Pokémon fights well then faints, it still earns Gen 1 stat exp (plus a tiny EXP crumb) — vanilla would give it nothing.
- **Optional battle HUD / XP bar hide**, low-HP warnings, mute HP alarm.

## Mechanics

### Momentum overview

Requires **MOMENTUM HIT**. Works in trainer (and link) battles for foe reactions; your dodge/brace/counter also apply in wild fights when a foe hits you.

| Situation | Special attacks | Physical attacks |
|-----------|-----------------|------------------|
| **You** under fire (menu) | **REACT!** — Dodge *or* Brace | **REACT!** — Dodge *or* Brace |
| **You** under fire (auto / OFF) | Auto-dodge | Auto-brace |
| **You** after taking a physical hit | — | Next damaging reply: **COUNTER** / **HOLD** |
| **Trainer foe** under your attack | Auto-dodge once/turn | Auto-brace once/turn |
| **Trainer foe** after you hit them physically | — | ~50% auto-counter on their next hit |

### Dodge & brace (you)

1. Foe announces a damaging move.
2. **CALLOUT PICK** decides whether you get a menu or an auto callout:
   - **THREAT** (default) — menu on serious hits (see below).
   - **ALWAYS** — menu on every damaging hit.
   - **OFF** — auto flavor only (no menu).
3. The menu is **REACT!** — always **Dodge** *and* **Brace** (cursor defaults to dodge on special / brace on physical). Then a scene flavor list (grass, DIG IN, FLY UP, …). Auto/OFF still maps special→dodge and physical→brace. Flavor picks set the **tier** (plain DODGE vs real hide / basic brace vs entrench); **EVADE stages are rolled** so dodge strength isn’t fixed. Plain dodge leans **+1–2**; real hides (grass / PATH / fly / dive / …) lean **+1–4** with a bit more weight on **+2–3**. Strong brace picks still push DEF hard (**DIG IN** / entrench); basic brace is **+1 DEF**.
4. Successful **dodge** applies that rolled temporary **EVADE**, plays a cover-specific hide (pic slide + thematic move anim: **FLY** for FLY UP, **RAZOR_LEAF** / grass moves in the brush, **DIG** behind rocks, **SURF** on a dive, etc. — StadiumBattleFX restyles those when loaded), may hide your sprite, then the hit resolves with accuracy against that EVADE. High rolls (**+3+**) get a short instinct callout. Leaving cover plays a matching emerge sparkle. Evasive hides (PATH, grass, fly, dive, … — not a plain DODGE sidestep) have ~**40%** chance to **vanish from sight** for **+1** extra EVADE on top of the roll.
5. If you’re in a **real hide** (grass, FLY UP, dive, … — not a plain DODGE sidestep) and the attack **still hits**, a short line may call it out (e.g. “But it found PIKACHU!”). Plain sidestep, brace, and entrench never use those lines (entrench breakthrough has its own guard text).
6. If you’re in cover and the attack **misses**, the move anim still plays (whiffs past cover) and miss text becomes a dodge line instead of vanilla “attack missed!”.
7. **Brace** applies temporary **DEF** and plays a random harden-style sparkle (HARDEN / WITHDRAW / DEFENSE CURL / …) plus a short plant/blink/bounce before the hit — no hide. Basic brace is **+1 DEF**. Strong brace picks (**DIG IN** / “Entrench!”) put you **entrenched**: DEF pushed toward stage **+6**. While entrenched you **cannot pick a move** until a **COUNTER** opening (foe miss, or rare physical connect) — **FIGHT** only offers **STAY** (“Stay entrenched, X!”), up to **3** holds; then the stance wears out (**BREAK**). With an opening, **STRIKE** is allowed. Entrench leans on barrier-style anims. Each hit has ~**18%** chance to **break through** — DEF returns to normal for that hit (usual damage). Attacking (or breaking) clears the temp DEF.
8. Dodge can fail (chance depends on **CALLOUT STYLE**): roughly **20%** TRICKY, **25%** BOLD, **30%** AUTO, **35%** SHOWY. Failed dodges use a narrator bubble (`...but it was too slow!`).
9. Threat picks use a left-side **REACT!** panel (Dodge / Brace), then **DODGE!** or **BRACE!** flavor — not the tiny top-right list.
10. **Sleep / freeze:** fully inert — no trainer callouts (anime move orders), no dodge/brace (menu or auto), no COVER!/ENTRENCH!, no idle stance pulses, no same-turn COUNTER!. Status lines still show as narrator bubbles when **SPEECH BUBBLE** is on. Same for a frozen/asleep trainer foe. Paralysis can still act (stiffer reacts).
11. **Paralysis:** you can still dodge/brace and use COVER!/ENTRENCH!, but reacts are stiffer (**+25%** fail). Each turn has a **~10%** chance to shake off PAR (vanilla Gen 1 never wears it on its own).

### Cover buffs (add / remove)

- Temp EVADE/DEF from dodge/brace are tracked per side.
- When **that side attacks**, cover buffs are stripped (silent stage undo).
- Leaving a **real hide/fly spot** to attack plays the emerge + **“Coming out!”** (going first also takes a silent **DEF −1** risk).
- While in a **hide/fly spot** (grass, cliff, FLY UP, dive, … — not a plain DODGE sidestep), **FIGHT** opens **STRIKE** / **STAY**: **STAY** (“Hold on!”) keeps the Dig/Fly-style hide on the field; **STRIKE** leaves cover to attack. Plain dodge/brace still commits you to acting next.
- While you’re **bracing / entrenched** or **hiding**, idle battle pulses loop on a delay (HARDEN-style when bracing; GROWTH / leaf for grass, DIG for rocks, SURF for dives, etc.) without stealing the command menu.
- **Deep cover (~30% per turn** while hidden): you’re stuck up a tree / underwater / behind a boulder / etc. — that turn you **can’t act** and get **no dodge/brace callout** (spot-flavored line instead).
- Trainer foes get the same add-on-cover / clear-on-attack pattern (no Dig/Fly hide for foes yet).
- With **CALLOUT BUFFS** on, stage changes from callouts still apply, but dialogue does **not** spam “rose!” / “fell!” after an order.

### Counter (you)

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

- **GENERIC LVL UP** — no “grew to level N”; EXP-gain dialogue is always hidden
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
| **GENERIC LVL UP** | On | Generic level-up text (EXP-gain dialogue is always hidden) |
| **ANIME MOVES** | On | Trainer-style move callouts for you & trainers (not wild) |
| **MOMENTUM HIT** | On | Dodge/brace/counter; COUNTER → Again!; STAY to hold cover; trainer foes may mirror |
| **CALLOUT STYLE** | AUTO | Flavor tone + dodge fail rate (`AUTO` / `BOLD` / `TRICKY` / `SHOWY`) |
| **CALLOUT BUFFS** | On | Apply EVADE/DEF (and counter DEF drop) from callouts — quietly, no rose/fell spam |
| **CALLOUT PICK** | THREAT | `THREAT` = **REACT!** (Dodge or Brace) on serious hits; `ALWAYS` = every hit; `OFF` = auto only (special→dodge / physical→brace) |
| **SPEECH BUBBLE** | On | Hides the classic battle text box (and Gen 3 / Dramatic Shape dialogue panels) during dialogue. Bubbles sit along the bottom (you left / foe right / narrator center) with tails aimed up at the field; layered shadow, accent bar, blink continue cue; typed a bit slower; **A/B** to continue (engine auto lines still auto-advance). FIGHT / move menus still use the normal bottom UI. |
| **TRAINER BANTER** | On | Large persona pools (kid / cocky / evil / gym / rival / spooky / nerd / chill / generic) for send-outs plus context idle lines (ahead / behind / low HP / long fight); rivals banter most often. While a banter line plays, the trainer sprite slides in from the right (flat battles). With **3D-BTL** staged fights, the foe trainer briefly takes the enemy billboard (same intro seam) and the camera eases toward that side, then both restore when the line clears |
| **STATUS CHIPS** | On | Tiny top-left (you) / top-right (foe) narrative chips; update only after callouts/state settle (no menu previews, no stage numbers) — e.g. “SCYTHER is hiding in brush”, “BLASTOISE is holding the trench!”, “ready to counter!” |
| **UNDERDOG EXP** | On | Capped bonus EXP when a much weaker mon helps score the KO |
| **EFFORT FAINT** | On | Stat-exp consolation when a mon fights well then faints |
| **DEV OVERLAY** | Off | Compact top-right battle debug chip (live cover/counter + last event). Full sequence appends to `anime_realism_dev.log` in the Gen1Recomp save directory |

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

- `manifest.json` — mod metadata (version `2.0.2`)
- `main.lua` — all behavior
- `build.sh` — builds `anime_realism-<version>.zip`
