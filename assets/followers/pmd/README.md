# PMD Collab packs

Unpack a [PMD Sprite Repository](https://sprites.pmdcollab.org/) zip, then **bake** it. The pad never loads `AnimData.xml` or `*-Anim.png` in a fight — those strips wedge the 3D field if they go through the follower slicer.

```
./assets/followers/run_bake.sh 0005
./assets/followers/run_bake.sh
```

That writes `follower_005.png` (every PMD frame in each pose row) and `follower_005.kit` (per-pose ticks at 60/sec). The script creates `assets/followers/.venv` (Pillow) on first run if needed. Drop-in `follower_XXX.png` still wins if you draw one by hand (4 columns, no `.kit`).

## Folder

```
assets/followers/0005/AnimData.xml
assets/followers/0005/Walk-Anim.png
assets/followers/0005/Idle-Anim.png
assets/followers/0005/Attack-Anim.png
…
```

That is the SpriteBot zip unpacked as `assets/followers/<dex>/`. `pmd/0005/` still works if you prefer that folder.

Dex folder is three digits (`0004` Charmander, `0005` Charmeleon). Shiny: `0005-shiny/` or `0005/0001/` when that is how the zip nested the shiny form.

A hand-drawn `follower_005.png` still wins if present.

Bake after unpacking:

```
./assets/followers/run_bake.sh 0005
./assets/followers/run_bake.sh
```

## How to get a pack

1. Open the species on [sprites.pmdcollab.org](https://sprites.pmdcollab.org/#/0005?form=0).
2. Download the sprite zip (or copy `sprite/0005/` from [SpriteCollab](https://github.com/PMDCollab/SpriteCollab)).
3. Unpack so `AnimData.xml` and the `*-Anim.png` files sit in `assets/followers/0005/` (this is what the Charmeleon zip already looks like). Offsets and shadow PNGs are bake-time only. The baker plants each frame's white shadow pixel so hops rise, and it keeps sideways shadow drift so Attack still lunges. Nested `0000/` / `0001/` form folders can stay; the pad uses the files in the dex root. The fight still never opens those source strips.

Example from GitHub (Charmeleon):

```
curl -L -o AnimData.xml \
  https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/sprite/0005/AnimData.xml
```

Then copy the `*-Anim.png` files from that same `sprite/0005/` folder.

## What plays

| Pad | PMD animation (first hit that exists) |
|---|---|
| Idle / walk | Idle, Walk |
| Dodge | Hop, Rotate, LeapForth |
| Brace | Cringe, LostBalance, Hurt |
| Physical | Attack, then Kick / Punch / Multi / Stomp / Jab, then Strike, Swing |
| Kick (optional) | Kick, Stomp |
| Punch (optional) | Punch, Jab |
| Multi (optional) | MultiStrike, MultiScratch, MultiAttack, Double |
| Special (Shoot) | Shoot, Charge, SpAttack |
| Hit | Pain, Hurt, Cringe |
| Faint | Faint, Sleep, EventSleep |
| Charge | Charge, SpAttack, Shoot |
| Jump | LeapForth, Hop, Attack |
| Counter | Strike, Attack, Swing |
| Miss | Trip, Tumble, LostBalance |
| Sleep | Sleep, EventSleep, Laying |
| Freeze | Sit, Idle |
| Confuse | Rotate, Tumble, LostBalance |
| Float | Float, Hop, Idle |
| TumbleBack | TumbleBack, Tumble, Pain |
| Flap (Flying move) | FlapAround, Hover |

Kick, Punch, and Multi are extra rows after Flap when that PMD strip exists. The pad keeps generic Attack for a single hit, then plays Multi for Fury Attack / Pin Missile / Double Kick (and Kick / Punch when those match and Multi is missing). Re-bake after unpacking so those rows land on the sheet.

Eight-direction sheets use south / east / north / west (skip diagonals). The baker copies every column of the chosen strip — it does not pick four keyframes. Frame timing is written into `follower_XXX.kit` from `AnimData.xml` (60 ticks per second). The pad loads that sidecar next to the PNG; it still never opens the XML or `*-Anim.png` in a fight.

## Credit

Packs come from the [PMD Sprite Repository](https://sprites.pmdcollab.org/) / [SpriteCollab](https://github.com/PMDCollab/SpriteCollab). Keep each folder’s upstream `credits.txt`. Community work is [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) (credit the artists, non-commercial). Official Explorers-style frames belong to **Spike Chunsoft**.

**Charmeleon (`0005`)** — from `sprite/0005/credits.txt`:

- **Spike Chunsoft** — Walk, Idle, Attack, Charge, Shoot, Strike, Swing, Hurt, Hop, Sleep, Rotate, Double
- **PMDCollab_1** — Cringe, LeapForth, Faint, and other extra dungeon poses
- **[bwappi](https://bsky.app/profile/bwappi.bsky.social)** — Eat, Pose, Pull, Pain, DeepBreath, Nod, Sink, Trip, Head, LostBalance, HitGround, Faint
- **[Grimlin](https://twitter.com/Griimlin)** — EventSleep, Wake, Tumble, Float, Sit, LookUp, Laying, LeapForth, Cringe, TumbleBack, Trip, HitGround, Faint

**Charmander (`0004`)** walk and combat sheets in that repo are credited to Spike Chunsoft.

The same credit list is in the mod [README](../../../README.md#art-credits).
