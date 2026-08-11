# Anime Realism

A [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) mod for anime-style immersion: hide levels and HP everywhere so you play by feel instead of numbers. In the anime you never see a health bar or level — just whether a Pokémon looks strong, tired, or ready to keep fighting.

## Why hide levels too?

HP bars make every fight about percentages. Levels do the same for power: you start comparing numbers instead of reading the matchup. In the anime, nobody calls out “it’s only level 12” — a Pokémon is just tough, green, or clearly outmatched, and growth is “they’ve gotten stronger,” not “+1 to the counter.”

So levels stay hidden for the same reason as HP: keep decisions grounded in what you see in battle and how your team feels, not in a spreadsheet. The optional generic level-up line leans into that — you still get stat gains and new moves, without the level number breaking the immersion.

## Features

- **Always on:** Levels and HP numbers/bars are hidden in battle, party, summary, and related UI (including Gen 3 Inspired UI).
- **Party list:** Instead of HP, low-health Pokémon show short heal hints (e.g. `WEAK-HEAL SOON!`). Fainted mons get a fainted hint.
- **Battle level-ups (optional):** Replaces “grew to level N” with a generic line like “Your POKéMON has grown stronger!” Stat gains and move learning still work as usual.
- **Anime move calls (optional):** Turns “PIKACHU used THUNDERBOLT!” into trainer-style callouts for you and opposing trainers (e.g. “PIKACHU! Use THUNDERBOLT!”, “BROCK! ONIX, use TACKLE!”). When the foe looks weak (same threshold as **LOW HP AT**), your lines shift to finish-it callouts. Wild battles keep the vanilla line.
- **Optional battle HUD hide:** Can blank the whole status HUD in battle.
- **Optional XP bar hide:** Suppresses the QoL-style XP bar during battle draw.
- **Low HP warnings:** In-battle dialogue when your Pokémon (or the foe) dips below a threshold.
- **Mute HP alarm:** Turns off the vanilla low-HP beep.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| **HIDE BATTLE HUD** | On | Hide the battle status HUD entirely |
| **HIDE XP BAR** | On | Hide the battle XP bar |
| **LOW HP WARN** | On | Show weak/tired messages in battle |
| **LOW HP AT** | 20% | Threshold for warnings (`20%` or `40%`) |
| **MUTE HP ALARM** | On | Silence the low-HP alarm |
| **GENERIC LVL UP** | On | Use generic “grown stronger” text instead of the level number |
| **ANIME MOVES** | On | Trainer-style move callouts for you & trainers (not wild) |

## Install

1. Zip `manifest.json` and `main.lua` at the **root** of the archive (or use a prebuilt `anime_realism-*.zip`).
2. In Gen1Recomp, import the zip via the mod manager — or copy the folder into:

   `~/Library/Application Support/pokemon-love2d/mods/anime_realism/`

3. Enable the mod and restart/reload if needed.

Requires `engine_internals` permission (declared in the manifest).

## Compatibility

Works with the stock battle UI. Optional compatibility hooks for:

- **Dramatic Shape** (`DRAMATIC_SHAPE`)
- **Quality of Life** (`quality_of_life`) — XP bar suppression
- **Gen 3 Inspired UI** (`gen3_battle_ui`)

Load order uses priority `200` so HUD patches apply after many other UI mods.

## Files

- `manifest.json` — mod metadata
- `main.lua` — all behavior
