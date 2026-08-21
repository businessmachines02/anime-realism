# Follower combat kit

Field-battle battlers in **Anime Realism** use a custom sprite sheet so they are not stuck on Wilds of Kanto / PokePC walk frames. This file is the layout we draw toward. Check sheets in `followers/preview.html`.

Overworld followers behind the player still come from Wilds/PokePC. This kit is for **the two mons on the pad** (player lead and foe).

Wilds sheets are usually a tall Gold/Silver-style column: one cell wide, standing down, up, and to the side, then walking those same three ways. Ours is a grid: separate left and right rows, with extra blocks stacked under walking for combat. Do not edit Wilds files; put overrides in this mod’s `assets/followers/` folder.

## File

`assets/followers/follower_XXX.png` with a 3-digit National Dex number. Charmeleon is `follower_005.png`.

Lookup order (first hit wins):

1. `follower_005_normal.png` / `follower_005_shiny.png`
2. `follower_005.png`
3. `CHARMELEON.png` / `CHARMELEON_normal.png` (species name, upper case)
4. Wilds of Kanto, then PokePC

- Magenta (`#FF00FF`) is keyed out (PMD SpriteBot pad). Black outlines stay; keying near-black punches holes through the body.
- Do **not** flip right from left. Right is drawn as its own row.
- Do **not** use `followers/005/dodge.png` (horizontal clip). That path was an experiment and breaks idle if it hijacks the battler.

## Why this layout

Walk is a four-frame cycle (standing still, one foot, standing still, the other foot), the same idea as a normal follower page.

In a fight the game already hops and squashes that walk drawing. That is not enough. We need separate drawings for getting out of the way, covering up, throwing a punch, throwing a beam, and getting hurt.

When an attack is about to land, time slows and the trainer picks **dodge** or **brace**. Those two are the only poses the player chooses. **Physical** and **special** play because a move was used. **Hit** plays on whoever actually took the damage; nobody presses a button for it.

Every pose uses the same **four columns**. Stack more four-row blocks under walking. The sheet stays 128 pixels wide.

## What each animation is

Draw every pose in all four facings (front, left, right, back). Each pose is four frames, left to right: start, peak, recover, settle (walk uses idle / step / idle / other step). Keep the Pokémon inside the 32-pixel cell; the game still slides them on the pad.

### Walk

This is standing around and moving on the tiles. Frame 1 and frame 3 are idle. Frames 2 and 4 are the two steps of a walk. Same silhouette as a Gen 2 overworld follower: small, readable, not a battle stadium pose.

If a later block is missing, the game keeps using these frames.

### Dodge

The Pokémon **gets out of the way**. The trainer picked this when something was coming. It should read as a sidestep, duck, or hop off the line — not as attacking, and not as getting punched.

Think: weight shifts, body tucks, maybe a foot leaves the ground, then they settle. Face the foe (or the way they hopped). Do not draw a punch or a beam.

The code still slides them sideways a little. Put the motion in the drawing so it reads even without that slide.

### Brace

The Pokémon **plants and takes it**. Same decision window as dodge, opposite choice. Crouch, flinch inward, arms or wings in, chin down. They are guarding, not striking and not fleeing.

Keep them on their tile. A small dip is enough. They should look ready to be hit, then they can go back to idle.

### Physical

The Pokémon **swings at someone next to them**. Tackle, scratch, punch, bite, peck — contact. Wind up, commit the limb or body through the foe, then recover.

Face the foe. The game already steps them one tile and lunges; do not draw them flying across the cell. Jumping a blocker and a melee counter use this same strip, so keep it a clear strike, not a special glow.

A miss can reuse the same wind-up; the strike just never lands.

### Special

The Pokémon **stays on its tile and casts**. Thunderbolt, Psychic, Growl, a shot from two tiles away. Rise, gather, release, settle. Hands, mouth, horn, or whole body can show the charge. This must not look like a punch.

They are acting, but they are not walking into the foe. Face the target.

### Hit

The Pokémon **got hurt**. Damage landed. This is not a choice. Recoil, flash of pain, knock off balance, then recover.

Face does not have to stay heroic; a grimace or closed eyes is fine. Heavy hits knock them back in code — draw the body taking the blow, not a dodge (they failed to dodge) and not a brace (the guard broke). Confusion and recoil can use this same “bonk” read.

## Canvas

| | |
|---|---|
| Cell | 32×32 |
| Full kit | **4 columns × 24 rows = 128×768** |
| Origin | top-left; row 1 is the top |

Walk-only is **128×128**. Add more height in chunks of 128 pixels (four rows) for each extra pose. Width never changes.

## Facing (every 4-row block)

Top → bottom inside the block:

| Row in block | Facing |
|---|---|
| 1 | Front (down) |
| 2 | Left |
| 3 | Right |
| 4 | Back (up) |

Same order as the current Charmeleon four-by-four. Older follower packs store one “side” drawing and flip it for the right; we draw left and right ourselves.

## Columns

Every block uses four frames, left to right.

- **Walk:** standing still, one foot, standing still, the other foot.
- **Dodge, brace, physical, special, hit:** start, peak, recover, settle.

## Blocks (top → bottom)

| Pixel Y | Grid rows | Pose | Frames | Role |
|---|---|---|---|---|
| 0–127 | 1–4 | Walk | 4 | Standing and walking. Used if a later pose is missing. |
| 128–255 | 5–8 | Dodge | 4 | Getting out of the way. |
| 256–383 | 9–12 | Brace | 4 | Planting and taking the hit. |
| 384–511 | 13–16 | Physical | 4 | Melee swing. Jumping and counters use this too. |
| 512–639 | 17–20 | Special | 4 | Casting a beam or status from the same tile. |
| 640–767 | 21–24 | Hit | 4 | Recoil after damage. Not a player choice. |

## Incremental sizes (32px cells)

Ship a short sheet; extra blocks are optional. Preview greys out poses that are not on the PNG yet.

| Drawn | Size |
|---|---|
| Walk only | 128×128 |
| + dodge | 128×256 |
| + brace | 128×384 |
| + physical | 128×512 |
| + special | 128×640 |
| + hit | **128×768** |

## In-game

`field/fx/sprites.lua` loads a four-column grid from this mod’s follower PNG. Walking uses the top block. If the sheet is taller, dodge, brace, physical, special, and hit play from later blocks when those rows exist. A missing block keeps using the walk frames (with the usual hop and squash).

The game does not flip the right-facing row. It does not load `followers/005/dodge.png` when this grid is in use.

Preview (`followers/preview.html`) is for the four-column PNG kit. PMD Collab packs are a different format; see `followers/pmd/README.md`.

## PMD Collab packs

PMD Collab zips are **source**, not runtime. Unpack into `assets/followers/0005/`, then bake a kit the pad can actually draw:

```
python3 assets/followers/bake_pmd.py 0005
```

That writes `follower_005.png` (4 columns × combat rows). Field battle loads that PNG only — never `AnimData.xml` or the `*-Anim.png` strips, which wedge the 3D map if they go through the follower slicer. Credit the PMD Collab artists (CC BY-NC).
