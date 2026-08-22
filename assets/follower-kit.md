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

**Idle** is a separate PMD breathing loop (block 7). Standing still plays that strip — every frame, using the baked ticks. Walking still uses the top block. If Idle is missing, standing falls back to Walk rest frames (columns 1 and 3 on a 4-frame walk).

In a fight the game already hops and squashes that walk drawing. That is not enough. We need separate drawings for getting out of the way, covering up, throwing a punch, throwing a beam, and getting hurt.

When an attack is about to land, time slows and the trainer picks **dodge** or **brace**. Those two are the only poses the player chooses. **Physical** and **special** play because a move was used. **Hit** plays on whoever actually took the damage; nobody presses a button for it.

Hand-drawn kits use the same **four columns**. Stack more four-row blocks under walking. Width stays 128 pixels.

Baked PMD kits keep **every frame** in the source row. Width is `longest pose × cell` (32, or larger for Onix / Gyarados). Occupancy still sizes the rest frame (38px for those two); the cell grows if a hop or lunge would clip. Shorter poses sit on the left; unused cells stay empty. A `follower_XXX.kit` sidecar lists the cell size and per-pose ticks (60/sec) so the pad plays the whole strip instead of four sampled cells.

## What each animation is

Draw every pose in all four facings (front, left, right, back). A hand-drawn pose is four frames, left to right: start, peak, recover, settle (walk uses idle / step / idle / other step). A baked PMD pose is the entire source row in that order. Keep the Pokémon inside the kit cell (32px, or larger when a rest-sized mon hops out of that box). The baker caps rest occupancy by Pokédex height (`FIT_MAX_BY_DEX` / `FIT_BY_HEIGHT` in `bake_pmd.py`) and grows the cell so later frames are not cropped. The game still slides them on the pad.

### Walk

This is moving on the tiles. Frame 1 and frame 3 are rest. Frames 2 and 4 are the two steps. Same silhouette as a Gen 2 overworld follower: small, readable, not a battle stadium pose.

If a later block is missing, the game keeps using these frames — including for standing, until Idle is present.

### Idle

This is standing still on the pad. PMD Collab `Idle` (a slow breathe / shift), not a walk rest frame. Face the foe. Loop all four columns. Do not step, punch, or flinch.

If this block is missing, standing uses Walk rest frames (columns 1 and 3 when Walk is four frames).

### Dodge

The Pokémon **gets out of the way**. The trainer picked this when something was coming. It should read as a sidestep, duck, or hop off the line — not as attacking, and not as getting punched.

Think: weight shifts, body tucks, maybe a foot leaves the ground, then they settle. Face the foe (or the way they hopped). Do not draw a punch or a beam.

The code still slides them sideways a little. Put the motion in the drawing so it reads even without that slide.

### Brace

The Pokémon **plants and takes it**. Same decision window as dodge, opposite choice. Crouch, flinch inward, arms or wings in, chin down. They are guarding, not striking and not fleeing.

Keep them on their tile. A small dip is enough. They should look ready to be hit, then they can go back to idle.

### Faint

The Pokémon **goes down**. HP hit zero. This is not a choice. Collapse, crumple, eyes out, then they are gone.

Face can slump. Hold the last crumpled frame. Wild foes hide after that. Trainer-owned mons keep that pose while the red recall laser sucks them up. Do not reuse dodge (they did not get away) or hit (that is a flinch they recover from).

### Physical

The Pokémon **swings at someone next to them**. Tackle, scratch, punch, bite, peck — contact. Wind up, commit the limb or body through the foe, then recover.

Face the foe. The game already steps them one tile and lunges; do not draw them flying across the cell. Jumping a blocker and a melee counter use this same strip, so keep it a clear strike, not a special glow.

A miss can reuse the same wind-up; the strike just never lands. **Jump**, **counter**, and **miss** each have their own block after Faint when the sheet is tall enough; otherwise they reuse Physical.

### Special (Shoot)

The Pokémon **stays on its tile and casts**. Thunderbolt, Psychic, Growl, a shot from two tiles away. Rise, gather, release, settle. Hands, mouth, horn, or whole body can show the charge. This must not look like a punch.

They are acting, but they are not walking into the foe. Face the target.

### Charge

Wind-up for a special. FIRE NOW holds this while the shot is still on the pad. When the bolt leaves, **Shoot** (Special) plays.

### Jump / Counter / Miss

Cover-jumps, a melee COUNTER clash, and a whiff. Same four facings as Physical, different drawings: a leap, a rebound strike, a slip-past.

### Sleep / Freeze / Confuse

Standing still while afflicted. Sleep is a downed breathe, freeze is a held sit, confuse is a wobble or spin. Walking (sleepwalk) still uses Walk.

### Hit

The Pokémon **got hurt**. Damage landed. This is not a choice. Recoil, flash of pain, knock off balance, then recover.

Face does not have to stay heroic; a grimace or closed eyes is fine. A flinch stays on this row. Confusion and recoil can use this same “bonk” read.

### TumbleBack

The Pokémon **goes flying**. Powerful hits, crits, clashes, and FIRE NOW knocks. Farther slip than Hit, longer recover. This is the one that leaves their feet.

## Canvas

| | |
|---|---|
| Cell | 32×32 |
| Full kit (hand-drawn) | **4 columns × 68 rows = 128×2176** (plus optional flap → 128×2304) |
| Full kit (baked PMD) | **N columns × 68 rows = (N×32)×2176**, N = longest pose |
| Origin | top-left; row 1 is the top |

Walk-only hand-drawn is **128×128**. Add more height in chunks of 128 pixels (four rows) for each extra pose. Hand-drawn width stays 128. Baked width grows with the longest PMD row.

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

Hand-drawn blocks use four frames, left to right.

- **Walk:** standing still, one foot, standing still, the other foot.
- **Idle:** breathe / shift, four frames, looping.
- **Dodge, brace, physical, special, hit, faint, charge, jump, counter, miss:** start, peak, recover, settle.

Baked PMD blocks use the entire source row. Combat one-shots still finish in the same clip length; the extra frames play inside it, weighted by the `.kit` ticks. Idle / walk / sleep / charge / confuse loop the full row at those ticks.

## Blocks (top → bottom)

| Pixel Y | Grid rows | Pose | Frames (hand / baked) | Role |
|---|---|---|---|---|
| 0–127 | 1–4 | Walk | 4 | Walking. Used if a later pose is missing. |
| 128–255 | 5–8 | Dodge | 4 | Getting out of the way. |
| 256–383 | 9–12 | Brace | 4 | Planting and taking the hit. |
| 384–511 | 13–16 | Physical | 4 | Melee swing. |
| 512–639 | 17–20 | Special (Shoot) | 4 | Casting a beam or status from the same tile. |
| 640–767 | 21–24 | Hit | 4 | Recoil after damage. Not a player choice. |
| 768–895 | 25–28 | Idle | 4 | Standing still. PMD breathe loop. |
| 896–1023 | 29–32 | Faint | 4 | Collapsing when HP hits 0. |
| 1024–1151 | 33–36 | Charge | 4 | Special wind-up. Held while the shot is on the pad. |
| 1152–1279 | 37–40 | Jump | 4 | Leap over cover. |
| 1280–1407 | 41–44 | Counter | 4 | Melee rebound / clash. |
| 1408–1535 | 45–48 | Miss | 4 | Whiff / slip-past. |
| 1536–1663 | 49–52 | Sleep | 4 | Asleep, standing. |
| 1664–1791 | 53–56 | Freeze | 4 | Frozen hold. |
| 1792–1919 | 57–60 | Confuse | 4 | Dizzy wobble. |
| 1920–2047 | 61–64 | Float | 4 | Flying dodge (Ghost dodge still uses Dodge, paler). |
| 2048–2175 | 65–68 | TumbleBack | 4 | Heavy knock / crit. |
| 2176–2303 | 69–72 | Flap | 4 | Optional. FlapAround / Hover while moving (Flying types). |

## Incremental sizes (32px cells)

Ship a short sheet; extra blocks are optional. Preview greys out poses that are not on the PNG yet.

| Drawn | Size |
|---|---|
| Walk only | 128×128 |
| + dodge | 128×256 |
| + brace | 128×384 |
| + physical | 128×512 |
| + special | 128×640 |
| + hit | 128×768 |
| + idle | 128×896 |
| + faint | **128×1024** |
| + charge | 128×1152 |
| + jump | 128×1280 |
| + counter | 128×1408 |
| + miss | 128×1536 |
| + sleep | 128×1664 |
| + freeze | 128×1792 |
| + confuse | 128×1920 |
| + float | **128×2048** |
| + tumble | **128×2176** |
| + flap | **128×2304** (optional; FlapAround / Hover only) |

## In-game

`field/fx/sprites.lua` loads the grid from this mod’s follower PNG. Columns come from the image width (and `follower_XXX.kit` when present). Walking uses the top block. Standing uses the Idle block when that block exists; otherwise it uses Walk rest frames. Faint uses the last core block when present, instead of shrinking the walk sprite. Trainer faint plays that crumple, then the recall laser; wild faint holds the last frame and hides. Charge holds while a FIRE NOW shot is on the pad; Shoot plays when it leaves. Jump, counter, and miss use their own rows when present, else Physical. Powerful hits, crits, and clashes play TumbleBack; a flinch stays on Hit. Sleep / freeze / confuse replace standing Idle while afflicted. Flying dodges use Float; Ghost dodges use Dodge paler. Round bodies and the hop cycle bounce the PMD Hop strip instead of sliding it. Flying types with a FlapAround (or Hover) row sometimes travel on that strip instead of Walk. If the sheet is taller than walk, dodge, brace, physical, special, and hit play from later blocks when those rows exist. A missing block keeps using the walk frames (with the usual hop and squash), or an earlier combat strip for the extra poses.

The game does not flip the right-facing row. It does not load `followers/005/dodge.png` when this grid is in use.

Preview (`followers/preview.html`) is for the four-column PNG kit. PMD Collab packs are a different format; see `followers/pmd/README.md`.

## PMD Collab packs

PMD Collab zips are **source**, not runtime. Unpack into `assets/followers/0005/`, then bake a kit the pad can actually draw:

```
./assets/followers/run_bake.sh 0005
```

That writes `follower_005.png` (every PMD frame × combat rows, extras after Idle/Faint) and `follower_005.kit` (per-pose ticks). Each frame's feet stay planted so hops rise; sideways shadow drift is kept so Attack still lunges. Long side views (Onix, Gyarados) scale per facing so the front is not crushed. DIG plays Diglett's Walk (the ground-pop) for every user. Field battle loads those — never `AnimData.xml` or the `*-Anim.png` strips, which wedge the 3D map if they go through the follower slicer. Credit the PMD Collab artists (CC BY-NC).
