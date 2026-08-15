# Differences from vanilla Gen 1

What **Anime Realism** changes from the stock Gen1Recomp battle. The engine's
own ledger stays in `docs/known-differences.md`; this file is only this mod.

## Presentation

- Wild and trainer singles can stay on the live overworld (FIELD) instead of
  the classic white battle screen. Link, demo, doubles, and other special
  battles keep the engine presentation.
- HP numbers, classic bars, and level readouts are hidden in battle, party,
  and summary UI. FIELD uses slim proportional bars without numbers.
- Level-up and EXP-gain dialogue is generic (no “grew to level N”).

## Battle rules that still use the engine

Damage rolls, type chart, accuracy, menus, Party/Bag, faint, and switch
resolution stay engine-owned. FIELD does not edit the map or rewrite the
damage formula.

## Additions

- **REACT / Focus:** Commit, Dodge, Take Cover, Brace, Entrench. Optional
  menu on damaging hits; trainer foes may auto-react.
- Physical **COUNTER** openings and **Again!** extra swings.
- Underdog EXP (small bonus vs a much higher-level foe) and effort-faint
  consolation stat EXP.
- Anime move callouts, speech bubbles, and trainer banter.

None of this ships ROM-derived art, audio banks, or patches.
