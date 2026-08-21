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

# Pad pose → PMD anim names. First sheet with 4+ directions wins; 1-dir
# strips (Cringe, LeapForth) are last-resort so facings stay distinct.
# Idle then Faint sit LAST so combat rows stay at the same Y.
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


def fit_cell(frame: Image.Image) -> Image.Image:
    frame = trim_sprite(key_magenta(frame))
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    fw, fh = frame.size
    if fw < 1 or fh < 1:
        return cell
    scale = min(CELL / fw, CELL / fh, 1.0)
    nw = max(1, int(round(fw * scale)))
    nh = max(1, int(round(fh * scale)))
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


def bake_dir(pack_dir: Path, out_path: Path) -> bool:
    xml_path = pack_dir / "AnimData.xml"
    if not xml_path.is_file():
        return False
    by_name = parse_pack(xml_path)
    blocks: list[Image.Image] = []
    used = 0
    for pose, names in POSES:
        anim, dirs = pose_anim(
            pack_dir, by_name, names,
            prefer_named=(pose in ("idle", "faint")))
        if not anim:
            if pose == "walk":
                sys.stderr.write(f"{pack_dir}: no Walk/Idle PNG\n")
                return False
            if pose == "idle" or pose == "faint":
                continue
            break
        sheet = Image.open(pack_dir / f"{anim['source']}-Anim.png")
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
                cell = fit_cell(slice_frame(sheet, fi, row, fw, fh))
                block.paste(cell, (col * CELL, face * CELL), cell)
        blocks.append(block)
        used += 1
        print(f"  {pose}: {anim['source']} {fw}x{fh} x{cols}/{dirs} frames={idxs}")
    if used < 1:
        return False
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
        out = ROOT / f"follower_{int(dex):03d}.png"
        print(f"bake {pack_dir} → {out.name}")
        if not bake_dir(pack_dir, out):
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
