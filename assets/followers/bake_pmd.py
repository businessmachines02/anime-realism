#!/usr/bin/env python3
"""Flatten a PMD Collab pack into the field kit (follower_XXX.png + .kit).

Battle never loads AnimData.xml or *-Anim.png. Each pose keeps every frame
in its PMD row (sheet width = longest pose × 32). Shadow.png / Offsets.png
plant each frame's feet and keep side-lunge travel from the shadow X.
A sidecar `.kit` file stores per-pose tick counts (60/sec) so the pad can
play the whole strip.

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

# Occupancy: one scale per facing, from FIT_MAX_BY_DEX / FIT_BY_HEIGHT.
# A long side view (Onix, Gyarados) must not shrink the front. Those
# values are used as written (clamped only to the 32px cell). Each
# frame's own shadow Y is planted so hops rise. Horizontal shadow drift
# (side Attacks) is kept. Overflow clips the cell. Art smaller than its
# cap stays that size unless FIT_UPSCALE is True.
FIT_MIN = 23
FIT_MAX = 32
FIT_UPSCALE = False
# Side-lunge punch when a later frame's shadow leaves the facing rest X.
MOTION_AMP = 1.28

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
# Dex → max px. Clamped only to the 32px cell, not FIT_MIN.
FIT_MAX_BY_DEX: dict[int, int] = {
    3: 32,    # Venusaur - make a bit bigger
    5: 23,    # charmeleon - make a bit smaller
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
    95: 32,    # Onix
    130: 32,   # Gyarados
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
    ("tumble", ("TumbleBack", "Tumble", "Pain", "Hurt"), True, "hit"),
    # Last and optional: skip when the pack has no FlapAround/Hover so
    # Charizard does not grow a dummy flap block.
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


def frame_ticks(anim: dict, cols: int) -> list[int]:
    """One duration per column. PMD ticks are 60/sec; pad missing entries."""
    raw: list[int] = []
    for d in anim.get("durations") or []:
        try:
            raw.append(max(1, int(d)))
        except (TypeError, ValueError):
            raw.append(2)
    if not raw:
        raw = [2]
    if len(raw) < cols:
        raw = raw + [raw[-1]] * (cols - len(raw))
    return raw[: max(1, cols)]


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


def find_white_pixel(im: Image.Image) -> tuple[int, int] | None:
    """PMD Shadow.png: one white pixel is the ground-contact / shadow center."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 200 and r > 200 and g > 200 and b > 200:
                return x, y
    return None


def find_green_pixel(im: Image.Image) -> tuple[int, int] | None:
    """PMD Offsets.png: green is the body center."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 200 and g > 180 and g >= r + 30 and g >= b + 30:
                return x, y
    return None


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
    return max(1, min(CELL, int(cap)))


def pose_scale(bboxes: list[tuple[int, int, int, int] | None], max_px: int | None) -> float:
    max_d = 1
    for bb in bboxes:
        if not bb:
            continue
        max_d = max(max_d, bb[2] - bb[0], bb[3] - bb[1])
    cap = CELL if max_px is None else max(1, min(CELL, int(max_px)))
    limit = cap / max_d
    return limit if FIT_UPSCALE else min(limit, 1.0)


def place_anchored(frame: Image.Image, bbox: tuple[int, int, int, int] | None,
                   origin: tuple[float, float] | None, scale: float,
                   dest_ax: float = CELL / 2, dest_ay: float = CELL - 1,
                   extra: tuple[float, float] = (0.0, 0.0)) -> Image.Image:
    """Map one source point to the cell feet; keep the rest of the pose."""
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    if not bbox:
        return cell
    trimmed = frame.crop(bbox)
    fw, fh = trimmed.size
    if fw < 1 or fh < 1:
        return cell
    nw = max(1, min(CELL, int(round(fw * scale))))
    nh = max(1, min(CELL, int(round(fh * scale))))
    resized = trimmed if (nw == fw and nh == fh) else trimmed.resize(
        (nw, nh), Image.Resampling.NEAREST)
    if origin is None:
        ox, oy = (bbox[0] + bbox[2]) / 2, bbox[3] - 1
    else:
        ox, oy = float(origin[0]), float(origin[1])
    paste_x = int(round(dest_ax - (ox - bbox[0]) * scale + extra[0]))
    paste_y = int(round(dest_ay - (oy - bbox[1]) * scale + extra[1]))
    cell.paste(resized, (paste_x, paste_y), resized)
    return cell


def facing_origin(anchors: list[tuple[int, int] | None],
                  bboxes: list[tuple[int, int, int, int] | None]):
    for anchor in anchors:
        if anchor:
            return float(anchor[0]), float(anchor[1])
    for bbox in bboxes:
        if bbox:
            return (bbox[0] + bbox[2]) / 2.0, float(bbox[3] - 1)
    return CELL / 2.0, float(CELL - 1)


def plant_origin(anchor: tuple[int, int] | None,
                 bbox: tuple[int, int, int, int] | None):
    if anchor:
        return float(anchor[0]), float(anchor[1])
    if bbox:
        return (bbox[0] + bbox[2]) / 2.0, float(bbox[3] - 1)
    return CELL / 2.0, float(CELL - 1)


def lunge_ax(anchor: tuple[int, int] | None, ref: tuple[float, float],
             scale: float) -> float:
    if not anchor:
        return CELL / 2.0
    return CELL / 2.0 + (anchor[0] - ref[0]) * scale * MOTION_AMP


def paste_rect(bbox, origin, scale: float, dest_ax: float, dest_ay: float):
    nw = max(1, int(round((bbox[2] - bbox[0]) * scale)))
    nh = max(1, int(round((bbox[3] - bbox[1]) * scale)))
    px = dest_ax - (origin[0] - bbox[0]) * scale
    py = dest_ay - (origin[1] - bbox[1]) * scale
    return px, py, nw, nh


def nudge_ax_into_cell(bbox, origin, scale: float, dest_ax: float,
                       dest_ay: float) -> float:
    """Keep a side lunge; pull it back if it would leave the 32px cell."""
    if not bbox:
        return dest_ax
    px, _, nw, _ = paste_rect(bbox, origin, scale, dest_ax, dest_ay)
    if px < 0:
        dest_ax += -px
    px, _, nw, _ = paste_rect(bbox, origin, scale, dest_ax, dest_ay)
    if px + nw > CELL:
        dest_ax -= (px + nw - CELL)
    return dest_ax


def slice_frame(sheet: Image.Image, col: int, row: int, fw: int, fh: int) -> Image.Image:
    x = col * fw
    y = row * fh
    return sheet.crop((x, y, x + fw, y + fh))


def cell_anchor(shadow: Image.Image | None, offsets: Image.Image | None,
                col: int, row: int, fw: int, fh: int,
                bbox: tuple[int, int, int, int] | None):
    """Prefer Shadow.png white (ground), then Offsets.png green (body)."""
    if shadow is not None:
        mark = find_white_pixel(slice_frame(shadow, col, row, fw, fh))
        if mark:
            return mark
    if offsets is not None:
        mark = find_green_pixel(slice_frame(offsets, col, row, fw, fh))
        if mark:
            return mark
    if bbox:
        return ((bbox[0] + bbox[2]) // 2, bbox[3] - 1)
    return None


def bake_block(pack_dir: Path, anim: dict, dirs: int, max_px: int | None = None):
    png = pack_dir / f"{anim['source']}-Anim.png"
    if not png.is_file():
        return None
    shadow_path = pack_dir / f"{anim['source']}-Shadow.png"
    offset_path = pack_dir / f"{anim['source']}-Offsets.png"
    shadow = Image.open(shadow_path).convert("RGBA") if shadow_path.is_file() else None
    offsets = Image.open(offset_path).convert("RGBA") if offset_path.is_file() else None
    try:
        with Image.open(png) as sheet:
            fw, fh = anim["width"], anim["height"]
            cols = max(1, sheet.width // fw)
            dirs = max(1, sheet.height // fh)
            face_rows = FACE_ROWS_8 if dirs >= 8 else FACE_ROWS_4
            ticks = frame_ticks(anim, cols)
            frames: list[tuple[int, int, Image.Image, tuple | None, tuple | None]] = []
            bboxes: list[tuple[int, int, int, int] | None] = []
            for face, pmd_row in enumerate(face_rows):
                row = min(pmd_row, dirs - 1)
                for col in range(cols):
                    raw = key_magenta(slice_frame(sheet, col, row, fw, fh))
                    bbox = raw.getbbox()
                    bboxes.append(bbox)
                    anchor = cell_anchor(shadow, offsets, col, row, fw, fh, bbox)
                    frames.append((face, col, raw, bbox, anchor))
            dest_ay = float(CELL - 1)
            by_face: list[list] = [[] for _ in range(BLOCK_ROWS)]
            for face, col, raw, bbox, anchor in frames:
                by_face[face].append((col, raw, bbox, anchor))
            fitted = []
            for face in range(BLOCK_ROWS):
                face_frames = by_face[face]
                face_scale = pose_scale(
                    [item[2] for item in face_frames], max_px)
                ref = facing_origin(
                    [item[3] for item in face_frames],
                    [item[2] for item in face_frames])
                origins = [plant_origin(item[3], item[2]) for item in face_frames]
                dests = []
                for item, origin in zip(face_frames, origins):
                    dest_ax = nudge_ax_into_cell(
                        item[2], origin, face_scale,
                        lunge_ax(item[3], ref, face_scale), dest_ay)
                    dests.append((dest_ax, dest_ay))
                fitted.append((origins, dests, face_scale))
            block = Image.new("RGBA", (CELL * cols, CELL * BLOCK_ROWS), (0, 0, 0, 0))
            for face, col, raw, bbox, anchor in frames:
                origins, dests, face_scale = fitted[face]
                origin = origins[col] if col < len(origins) else plant_origin(anchor, bbox)
                dest_ax, face_ay = dests[col] if col < len(dests) else (CELL / 2.0, dest_ay)
                cell = place_anchored(
                    raw, bbox, origin, face_scale, dest_ax, face_ay)
                block.paste(cell, (col * CELL, face * CELL), cell)
            return block, dirs, cols, ticks, fw, fh
    finally:
        if shadow is not None:
            shadow.close()
        if offsets is not None:
            offsets.close()


def write_kit_meta(path: Path, max_cols: int, pose_ticks: list[tuple[str, list[int]]]) -> None:
    lines = [
        "# follower kit timing; 60 ticks/sec. Pad plays every column.",
        f"kit {CELL} {max_cols}",
    ]
    for pose, ticks in pose_ticks:
        lines.append(pose + " " + " ".join(str(t) for t in ticks))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def bake_dir(pack_dir: Path, out_path: Path, dex: int | None = None) -> bool:
    xml_path = pack_dir / "AnimData.xml"
    if not xml_path.is_file():
        return False
    by_name = parse_pack(xml_path)
    blocks: list[Image.Image] = []
    by_pose: dict[str, Image.Image] = {}
    pose_ticks: list[tuple[str, list[int]]] = []
    ticks_by_pose: dict[str, list[int]] = {}
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
        block, dirs, cols, ticks, fw, fh = baked
        blocks.append(block)
        by_pose[pose] = block
        ticks_by_pose[pose] = ticks
        pose_ticks.append((pose, ticks))
        used += 1
        print(f"  {pose}: {anim['source']} {fw}x{fh} x{cols}/{dirs} frames={cols}")
    if used < 1:
        return False
    # Only append extras when Idle+Faint already occupy blocks 6–7.
    if used >= 8:
        for pose, names, prefer, fallback in EXTRA_POSES:
            anim, dirs = pose_anim(pack_dir, by_name, names, prefer_named=prefer)
            baked = bake_block(pack_dir, anim, dirs, max_px) if anim else None
            if baked:
                block, dirs, cols, ticks, fw, fh = baked
                print(f"  {pose}: {anim['source']} {fw}x{fh} x{cols}/{dirs} frames={cols}")
            else:
                if fallback is None:
                    print(f"  {pose}: skip")
                    continue
                src = by_pose.get(fallback) or by_pose.get("walk")
                if not src:
                    break
                block = src.copy()
                ticks = list(ticks_by_pose.get(fallback) or ticks_by_pose.get("walk") or [2] * COLS)
                print(f"  {pose}: copy {fallback}")
            blocks.append(block)
            by_pose[pose] = block
            ticks_by_pose[pose] = ticks
            pose_ticks.append((pose, ticks))
            used += 1
    max_cols = max((max(1, b.width // CELL) for b in blocks), default=COLS)
    kit = Image.new("RGBA", (CELL * max_cols, CELL * BLOCK_ROWS * used), (0, 0, 0, 0))
    for i, block in enumerate(blocks):
        kit.paste(block, (0, i * CELL * BLOCK_ROWS), block)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    kit.save(out_path)
    write_kit_meta(out_path.with_suffix(".kit"), max_cols, pose_ticks)
    print(f"wrote {out_path} ({kit.width}x{kit.height}) + {out_path.with_suffix('.kit').name}")
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
