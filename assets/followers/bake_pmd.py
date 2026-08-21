#!/usr/bin/env python3
"""Flatten a PMD Collab pack into the 4×N field kit (follower_XXX.png).

Battle never loads AnimData.xml or *-Anim.png. Unpack a SpriteBot zip, then:

    python3 assets/followers/bake_pmd.py 0005
    python3 assets/followers/bake_pmd.py        # every pack under this folder
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.stderr.write("Need Pillow: python3 -m pip install pillow\n")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent
CELL = 32
COLS = 4
BLOCK_ROWS = 4
DEX_DIR = re.compile(r"^\d{3,4}$")

# Occupancy: after trim, scale into the 32px cell (feet on the bottom).
# Caps are never below FIT_MIN. Art smaller than its cap stays that size
# unless FIT_UPSCALE is True (nearest-neighbor, can look chunky).
FIT_MIN = 23
FIT_MAX = 32
FIT_UPSCALE = False

# (height_m exclusive upper bound, max px). First match wins.
# Add more steps for finer-grained variation, especially for smaller and larger Pokémon.
# <0.5m → 21, <0.8m → 23, <1.0m → 24, <1.2m → 25, <1.4m → 27, <1.6m → 28, <2.0m → 29, <2.5m → 30, else FIT_MAX.
FIT_BY_HEIGHT: list[tuple[float, int]] = [
    (0.5, 21),
    (0.8, 23),
    (1.0, 24),
    (1.2, 25),
    (1.4, 27),
    (1.6, 28),
    (2.0, 29),
    (2.5, 30),
]
# Dex → max px. Still clamped to [FIT_MIN, CELL].
FIT_MAX_BY_DEX: dict[int, int] = {
    3: 32,    # Venusaur - make a bit bigger
    6: 29,    # Charizard - make a bit bigger
    9: 29,    # Blastoise - make a bit bigger
    19: 20,   # Rattata
    25: 20,   # Pikachu - make smaller, like Growlithe
    26: 25,   # Raichu - make the size of Ninetales
    37: 20,   # Vulpix
    38: 27,   # Ninetales
    58: 20,   # Growlithe
    133: 20,  # Eevee
    134: 20,  # Vaporeon (1.0m would otherwise sit in the 24px band)
    135: 20,  # Jolteon
    136: 20,  # Flareon
    196: 20,  # Espeon
    197: 20,  # Umbreon
}

# Gen 1 Pokédex height in meters. Index 0 unused.
HEIGHT_M = [
    0,
    0.7, 1.0, 2.4, 0.6, 1.1, 1.7, 0.5, 1.0, 1.6, 0.3,  # 1–10
    0.7, 1.1, 0.3, 0.6, 1.0, 0.3, 1.1, 1.5, 0.3, 0.7,  # 11–20
    0.3, 1.2, 2.0, 3.5, 0.4, 0.8, 0.6, 1.0, 0.4, 0.8,  # 21–30
    1.3, 0.5, 0.9, 1.4, 0.6, 1.3, 0.6, 1.1, 0.5, 1.0,  # 31–40
    0.8, 1.6, 0.5, 0.8, 1.2, 0.3, 1.0, 1.0, 1.5, 0.2,  # 41–50
    0.7, 0.4, 1.0, 0.8, 1.7, 0.5, 1.0, 0.7, 1.9, 0.6,  # 51–60
    1.0, 1.3, 0.9, 1.3, 1.5, 0.8, 1.5, 1.6, 0.7, 1.0,  # 61–70
    1.7, 0.9, 1.6, 0.4, 1.0, 1.4, 1.0, 1.7, 1.2, 1.6,  # 71–80
    0.3, 1.0, 0.8, 1.4, 1.8, 1.1, 1.7, 0.9, 1.2, 0.3,  # 81–90
    1.5, 1.3, 1.6, 1.5, 8.8, 1.0, 1.6, 0.4, 1.3, 0.5,  # 91–100
    1.2, 0.4, 2.0, 0.4, 1.0, 1.5, 1.4, 1.2, 0.6, 1.2,  # 101–110
    1.0, 1.9, 1.1, 1.0, 2.2, 0.4, 1.2, 0.6, 1.3, 0.8,  # 111–120
    1.1, 1.3, 1.5, 1.4, 1.1, 1.3, 1.5, 1.4, 0.9, 6.5,  # 121–130
    2.5, 0.3, 0.3, 1.0, 0.8, 0.9, 0.8, 0.4, 1.0, 0.5,  # 131–140
    1.3, 1.8, 2.1, 1.7, 1.6, 2.0, 1.8, 4.0, 2.2, 2.0,  # 141–150
    0.4,  # 151 Mew
]

# Pad pose → PMD anim names. First sheet with 4+ directions wins; 1-dir
# strips (Cringe, LeapForth) are last-resort so facings stay distinct.
# Idle then Faint sit LAST so combat rows stay at the same Y. Extra
# poses APPEND after Faint so an 8-block kit still maps 0–7.
POSES = [
    ("walk", ("Walk", "Idle")),
    ("dodge", ("Hop", "Rotate", "LeapForth", "Walk")),
    ("brace", ("Cringe", "LostBalance", "Hurt")),
    ("physical", ("Attack", "Strike", "Swing", "Kick")),
    ("special", ("Shoot", "Charge", "SpAttack", "Strike")),
    ("hit", ("Pain", "Hurt", "Cringe")),
    ("idle", ("Idle", "Walk")),
    ("faint", ("Faint", "Sleep", "EventSleep", "Pain", "Hurt")),
]

# prefer_named, fallback pose if the strip is missing (keeps block indices).
EXTRA_POSES = [
    ("charge", ("Charge", "SpAttack", "Shoot"), True, "special"),
    ("jump", ("LeapForth", "Hop", "Attack"), True, "physical"),
    ("counter", ("Strike", "Attack", "Swing"), True, "physical"),
    ("miss", ("Trip", "Tumble", "LostBalance", "Hurt"), True, "physical"),
    ("sleep", ("Sleep", "EventSleep", "Laying"), True, "idle"),
    ("freeze", ("Sit", "Idle"), True, "idle"),
    ("confuse", ("Rotate", "Tumble", "LostBalance"), True, "idle"),
    ("float", ("Float", "Hop", "Idle"), True, "dodge"),
    # Last and optional: skip when the pack has no FlapAround/Hover so
    # Charizard does not grow a dummy 17th block.
    ("flap", ("FlapAround", "Hover"), True, None),
]

PREFER_NAMED = {"idle", "faint"}

# Kit rows: front, left, right, back.
# PMD 8-dir rows: down, down-right, right, up-right, up, up-left, left, down-left.
FACE_ROWS_8 = (0, 6, 2, 4)
FACE_ROWS_4 = (0, 3, 1, 2)


def parse_pack(xml_path: Path) -> dict[str, dict]:
    root = ET.parse(xml_path).getroot()
    by_name: dict[str, dict] = {}
    order: list[str] = []
    for anim in root.findall(".//Anim"):
        name_el = anim.find("Name")
        name = (name_el.text or "").strip() if name_el is not None else ""
        if not name:
            continue
        copy = anim.findtext("CopyOf")
        copy = copy.strip() if copy else None
        durations = [int(d.text or 1) for d in anim.findall("Durations/Duration")]
        rec = {
            "name": name,
            "copy": copy or None,
            "width": _int(anim.findtext("FrameWidth")),
            "height": _int(anim.findtext("FrameHeight")),
            "rush": _int(anim.findtext("RushFrame")),
            "hit": _int(anim.findtext("HitFrame")),
            "return_frame": _int(anim.findtext("ReturnFrame")),
            "durations": durations,
            "source": name,
        }
        by_name[name] = rec
        order.append(name)
    for name in order:
        rec = by_name[name]
        src = by_name.get(rec["copy"] or "")
        if src and not src["copy"]:
            rec["width"] = rec["width"] or src["width"]
            rec["height"] = rec["height"] or src["height"]
            rec["rush"] = rec["rush"] if rec["rush"] is not None else src["rush"]
            rec["hit"] = rec["hit"] if rec["hit"] is not None else src["hit"]
            rec["return_frame"] = rec["return_frame"] if rec["return_frame"] is not None else src["return_frame"]
            if not rec["durations"]:
                rec["durations"] = list(src["durations"])
            rec["source"] = src["name"]
    return by_name


def _int(text: str | None) -> int | None:
    if text is None or text.strip() == "":
        return None
    try:
        return int(text)
    except ValueError:
        return None


def pick_frames(count: int) -> tuple[int, int, int, int]:
    if count <= 1:
        return (0, 0, 0, 0)
    if count == 2:
        return (0, 1, 0, 1)
    if count == 3:
        return (0, 1, 2, 1)
    last = count - 1
    return (0, max(1, count // 3), max(2, (2 * count) // 3), last)


def pick_anim_frames(anim: dict, count: int) -> tuple[int, int, int, int]:
    """Use PMD hit / return when both exist and actually spread the strip."""
    even = pick_frames(count)
    if count <= 4:
        return even
    hit = anim.get("hit")
    ret = anim.get("return_frame")
    if hit is None or ret is None:
        return even

    def clamp(n: int) -> int:
        if n < 0:
            return 0
        if n >= count:
            return count - 1
        return n

    start, peak, recover, settle = 0, clamp(hit), clamp(ret), count - 1
    if peak <= start or recover <= peak or settle <= recover:
        return even
    return (start, peak, recover, settle)


def pose_anim(pack_dir: Path, by_name: dict, names: tuple[str, ...],
              prefer_named: bool = False):
    """First 4+ direction sheet in `names`; otherwise the best 1-dir fallback.

    `prefer_named`: take the first existing sheet even if it is 1-dir
    (Faint/Idle should not lose to an 8-dir Hurt).
    """
    fallback = None
    fallback_dirs = -1
    for name in names:
        cand = by_name.get(name)
        if not cand or not cand["width"] or not cand["height"]:
            continue
        png = pack_dir / f"{cand['source']}-Anim.png"
        if not png.is_file():
            continue
        with Image.open(png) as im:
            dirs = max(1, im.height // cand["height"])
        if prefer_named or dirs >= 4:
            return cand, dirs
        if dirs > fallback_dirs:
            fallback = cand
            fallback_dirs = dirs
    if fallback:
        return fallback, max(1, fallback_dirs)
    return None, 0


def key_magenta(im: Image.Image) -> Image.Image:
    """PMD SpriteBot pads with magenta. Black is outline/shade — keep it."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0 and r > 250 and g < 8 and b > 250:
                px[x, y] = (0, 0, 0, 0)
    return im


def trim_sprite(frame: Image.Image) -> Image.Image:
    """Drop empty canvas so 72×80 Attack cells do not shrink to a speck."""
    bbox = frame.getbbox()
    if not bbox:
        return frame
    return frame.crop(bbox)


def fit_cap(dex: int | None) -> int:
    if dex is not None and dex in FIT_MAX_BY_DEX:
        cap = FIT_MAX_BY_DEX[dex]
    else:
        cap = FIT_MAX
        h = HEIGHT_M[dex] if dex and 0 < dex < len(HEIGHT_M) else None
        if h is not None:
            cap = FIT_MAX
            for limit, px in FIT_BY_HEIGHT:
                if h < limit:
                    cap = px
                    break
    return max(FIT_MIN, min(CELL, int(cap)))


def fit_cell(frame: Image.Image, max_px: int | None = None) -> Image.Image:
    frame = trim_sprite(key_magenta(frame))
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    fw, fh = frame.size
    if fw < 1 or fh < 1:
        return cell
    cap = CELL if max_px is None else max(1, min(CELL, int(max_px)))
    limit = min(cap / fw, cap / fh)
    scale = limit if FIT_UPSCALE else min(limit, 1.0)
    nw = max(1, int(round(fw * scale)))
    nh = max(1, int(round(fh * scale)))
    nw = min(nw, CELL)
    nh = min(nh, CELL)
    resized = frame if (nw == fw and nh == fh) else frame.resize(
        (nw, nh), Image.Resampling.NEAREST)
    # Feet on the bottom of the 32px cell, centered.
    x = (CELL - nw) // 2
    y = CELL - nh
    cell.paste(resized, (x, y), resized)
    return cell


def slice_frame(sheet: Image.Image, col: int, row: int, fw: int, fh: int) -> Image.Image:
    x = col * fw
    y = row * fh
    return sheet.crop((x, y, x + fw, y + fh))


def bake_block(pack_dir: Path, anim: dict, dirs: int, max_px: int | None = None):
    png = pack_dir / f"{anim['source']}-Anim.png"
    if not png.is_file():
        return None
    with Image.open(png) as sheet:
        fw, fh = anim["width"], anim["height"]
        cols = max(1, sheet.width // fw)
        dirs = max(1, sheet.height // fh)
        face_rows = FACE_ROWS_8 if dirs >= 8 else FACE_ROWS_4
        idxs = pick_anim_frames(anim, cols)
        block = Image.new("RGBA", (CELL * COLS, CELL * BLOCK_ROWS), (0, 0, 0, 0))
        for face, pmd_row in enumerate(face_rows):
            row = min(pmd_row, dirs - 1)
            for col, fi in enumerate(idxs):
                fi = min(fi, cols - 1)
                cell = fit_cell(slice_frame(sheet, fi, row, fw, fh), max_px)
                block.paste(cell, (col * CELL, face * CELL), cell)
        return block, dirs, cols, idxs, fw, fh


def bake_dir(pack_dir: Path, out_path: Path, dex: int | None = None) -> bool:
    xml_path = pack_dir / "AnimData.xml"
    if not xml_path.is_file():
        return False
    by_name = parse_pack(xml_path)
    blocks: list[Image.Image] = []
    by_pose: dict[str, Image.Image] = {}
    used = 0
    max_px = fit_cap(dex)
    for pose, names in POSES:
        anim, dirs = pose_anim(
            pack_dir, by_name, names,
            prefer_named=(pose in PREFER_NAMED))
        if not anim:
            if pose == "walk":
                sys.stderr.write(f"{pack_dir}: no Walk/Idle PNG\n")
                return False
            if pose == "idle" or pose == "faint":
                continue
            break
        baked = bake_block(pack_dir, anim, dirs, max_px)
        if not baked:
            if pose == "idle" or pose == "faint":
                continue
            break
        block, dirs, cols, idxs, fw, fh = baked
        blocks.append(block)
        by_pose[pose] = block
        used += 1
        print(f"  {pose}: {anim['source']} {fw}x{fh} x{cols}/{dirs} frames={idxs}")
    if used < 1:
        return False
    # Only append extras when Idle+Faint already occupy blocks 6–7.
    if used >= 8:
        for pose, names, prefer, fallback in EXTRA_POSES:
            anim, dirs = pose_anim(pack_dir, by_name, names, prefer_named=prefer)
            baked = bake_block(pack_dir, anim, dirs, max_px) if anim else None
            if baked:
                block, dirs, cols, idxs, fw, fh = baked
                print(f"  {pose}: {anim['source']} {fw}x{fh} x{cols}/{dirs} frames={idxs}")
            else:
                if fallback is None:
                    print(f"  {pose}: skip")
                    continue
                src = by_pose.get(fallback) or by_pose.get("walk")
                if not src:
                    break
                block = src.copy()
                print(f"  {pose}: copy {fallback}")
            blocks.append(block)
            by_pose[pose] = block
            used += 1
    kit = Image.new("RGBA", (CELL * COLS, CELL * BLOCK_ROWS * used), (0, 0, 0, 0))
    for i, block in enumerate(blocks):
        kit.paste(block, (0, i * CELL * BLOCK_ROWS), block)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    kit.save(out_path)
    print(f"wrote {out_path} ({kit.width}x{kit.height})")
    return True


def pack_dirs(root: Path) -> list[Path]:
    found: list[Path] = []
    for xml in sorted(root.glob("**/AnimData.xml")):
        parent = xml.parent
        # Skip nested form dumps (0005/0000/0001) when the dex root also has XML.
        rel = parent.relative_to(root)
        parts = rel.parts
        if len(parts) >= 2 and (root / parts[0] / "AnimData.xml").is_file():
            if parent != root / parts[0]:
                continue
        if len(parts) >= 1 and DEX_DIR.fullmatch(parts[0]):
            found.append(parent)
    # Unique, prefer shorter paths.
    by_dex: dict[str, Path] = {}
    for d in found:
        dex = d.relative_to(root).parts[0]
        if dex not in by_dex or len(d.parts) < len(by_dex[dex].parts):
            by_dex[dex] = d
    return [by_dex[k] for k in sorted(by_dex)]


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        dirs = [ROOT / argv[1]]
        if not (dirs[0] / "AnimData.xml").is_file():
            alt = ROOT / "pmd" / argv[1]
            dirs = [alt]
    else:
        dirs = pack_dirs(ROOT)
    if not dirs:
        sys.stderr.write("no AnimData.xml packs found\n")
        return 1
    ok = True
    for pack_dir in dirs:
        dex = pack_dir.name if DEX_DIR.fullmatch(pack_dir.name) else None
        if dex is None:
            for p in pack_dir.parts:
                if DEX_DIR.fullmatch(p):
                    dex = p
                    break
        if not dex or int(dex) == 0:
            sys.stderr.write(f"skip {pack_dir}: no dex folder\n")
            continue
        dex_n = int(dex)
        out = ROOT / f"follower_{dex_n:03d}.png"
        print(f"bake {pack_dir} → {out.name} (fit≤{fit_cap(dex_n)})")
        if not bake_dir(pack_dir, out, dex_n):
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
