# PMD Collab packs

Unpack a [PMD Sprite Repository](https://sprites.pmdcollab.org/) zip, then **bake** it. The pad never loads `AnimData.xml` or `*-Anim.png` in a fight — those strips wedge the 3D field if they go through the follower slicer.

```
python3 assets/followers/bake_pmd.py 0005
```

That writes `follower_005.png`. Drop-in `follower_XXX.png` still wins if you draw one by hand.

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
python3 assets/followers/bake_pmd.py 0005
python3 assets/followers/bake_pmd.py
```

## How to get a pack

1. Open the species on [sprites.pmdcollab.org](https://sprites.pmdcollab.org/#/0005?form=0).
2. Download the sprite zip (or copy `sprite/0005/` from [SpriteCollab](https://github.com/PMDCollab/SpriteCollab)).
3. Unpack so `AnimData.xml` and the `*-Anim.png` files sit in `assets/followers/0005/` (this is what the Charmeleon zip already looks like). Offsets and shadow PNGs are optional for the pad. Nested `0000/` / `0001/` form folders can stay; the pad uses the files in the dex root.

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
| Physical | Attack, Strike, Swing, Kick |
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
| Flap (Flying move) | FlapAround, Hover |

Eight-direction sheets use south / east / north / west (skip diagonals). Frame timing comes from `AnimData.xml` (60 ticks per second).

## Credit

Packs come from the [PMD Sprite Repository](https://sprites.pmdcollab.org/) / [SpriteCollab](https://github.com/PMDCollab/SpriteCollab). Keep each folder’s upstream `credits.txt`. Community work is [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) (credit the artists, non-commercial). Official Explorers-style frames belong to **Spike Chunsoft**.

**Charmeleon (`0005`)** — from `sprite/0005/credits.txt`:

- **Spike Chunsoft** — Walk, Idle, Attack, Charge, Shoot, Strike, Swing, Hurt, Hop, Sleep, Rotate, Double
- **PMDCollab_1** — Cringe, LeapForth, Faint, and other extra dungeon poses
- **[bwappi](https://bsky.app/profile/bwappi.bsky.social)** — Eat, Pose, Pull, Pain, DeepBreath, Nod, Sink, Trip, Head, LostBalance, HitGround, Faint
- **[Grimlin](https://twitter.com/Griimlin)** — EventSleep, Wake, Tumble, Float, Sit, LookUp, Laying, LeapForth, Cringe, TumbleBack, Trip, HitGround, Faint

**Charmander (`0004`)** walk and combat sheets in that repo are credited to Spike Chunsoft.

The same credit list is in the mod [README](../../../README.md#art-credits).
