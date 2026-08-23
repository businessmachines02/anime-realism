#!/usr/bin/env python3
"""Flatten a PMD Collab pack into the field kit (follower_XXX.png + .kit).

Battle never loads AnimData.xml or *-Anim.png. Each pose keeps every frame
in its PMD row (sheet width = longest pose × cell). Shadow.png / Offsets.png
plant each frame's feet and keep side-lunge travel from the shadow X.
A sidecar `.kit` file stores per-pose tick counts (60/sec) so the pad can
play the whole strip. Shadow.png is the plant, not the lowest pixel —
feet often hang a few rows below it, so dest_ay leaves that room.

    python3 assets/followers/bake_pmd.py 0005
    python3 assets/followers/bake_pmd.py        # every pack under this folder
"""

from __future__ import annotations

import math
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
CELL_MAX = 64
COLS = 4
BLOCK_ROWS = 4
BLOCK_ROWS_MAX = 8
DEX_DIR = re.compile(r"^\d{3,4}$")

# Occupancy: one scale per facing, from FIT_MAX_BY_DEX / FIT_BY_HEIGHT.
# Rest hits that cap. The sheet cell then grows (up to CELL_MAX) if a hop
# or lunge would clip. A long side view must not shrink the front.
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
# Dex → max px. Clamped to CELL_MAX, not FIT_MIN.
FIT_MAX_BY_DEX: dict[int, int] = {
    15: 23,   # Beedrill - a bit smaller
    3: 33,    #  Venusaur - make a bit bigger
    5: 23,    # charmeleon - make a bit smaller
    6: 36,    # Charizard — wings read small at the 2.2m / 31px cap
    9: 31,    # Blastoise - make a bit bigger
    19: 20,   # ratata 
    20: 23,   # raticate - a bit smaller
    25: 20,   # pikachu - make smaller, like Growlite
    26: 25,   # raichu - make the size of Ninetales
    37: 20,   # Vulpix
    31: 27,  # nidoqueen 
    34: 27,  # nidoking
    38: 27,   # Ninetales
    58: 22,   # Growlithe
    133: 22,  # Eevee (a bit bigger)
    134: 24,  # Vaporeon (a bit bigger; 1.0m would otherwise sit in the 24px band)
    135: 24,  # Jolteon (a bit bigger)
    136: 24,  # Flareon (a bit bigger)
    196: 22,  # Espeon
    197: 22,  # Umbreon
    95: 38,    # Onix
    130: 38,   # Gyarados
}

# Gen 1 Pokédex height in meters. Index 0 unused.
HEIGHT_M = [
    0,
    0.7, 1.0, 2.4, 0.6, 1.1, 2.2, 0.5, 1.0, 2.0, 0.3,  # 1–10
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
    ("physical", ("Attack", "Kick", "Punch", "MultiStrike", "MultiScratch",
                  "MultiAttack", "Stomp", "Jab", "Strike", "Swing")),
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
    # Charizard does not grow a dummy flap block. Kick / Punch / Multi
    # trail after flap so a missing flap does not shift those rows.
    ("flap", ("FlapAround", "Hover"), True, None),
    ("kick", ("Kick", "Stomp"), True, None),
    ("punch", ("Punch", "Jab"), True, None),
    ("multi", ("MultiStrike", "MultiScratch", "MultiAttack", "Double"), True, None),
]

# Dex → pose → PMD names. Golem's Attack is Special0 (the roll).
POSE_NAMES_BY_DEX: dict[int, dict[str, tuple[str, ...]]] = {
    76: {
        "physical": ("Special0", "Attack", "Kick", "Punch", "Strike", "Swing"),
    },
}

PREFER_NAMED = {"idle", "faint"}

# Kit rows: front, left, right, back, then the four diagonals.
# PMD 8-dir rows: down, down-right, right, up-right, up, up-left, left, down-left.
FACE_ROWS_8 = (0, 6, 2, 4, 1, 7, 3, 5)
# 4-dir PMD: down, right, up, left — expand diagonals to the nearest side.
FACE_ROWS_8_FROM_4 = (0, 3, 1, 2, 1, 3, 1, 3)
FACE_ROWS_4 = (0, 3, 1, 2)


def face_rows_for(dirs: int, faces: int) -> tuple[int, ...]:
    if faces >= 8:
        if dirs >= 8:
            return FACE_ROWS_8
        if dirs >= 4:
            return FACE_ROWS_8_FROM_4
        return (0,) * 8
    if dirs >= 4:
        return FACE_ROWS_4
    return (0,) * 4


def _nfaces(frames: list) -> int:
    n = 0
    for item in frames:
        n = max(n, int(item[0]) + 1)
    return max(1, n)


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


def anim_cols(pack_dir: Path, anim: dict | None) -> int:
    """How many cells sit in the source row (sheet width ÷ frame width)."""
    if not anim or not anim.get("width"):
        return 0
    png = pack_dir / f"{anim['source']}-Anim.png"
    if not png.is_file():
        return 0
    with Image.open(png) as im:
        return max(1, im.width // anim["width"])


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
    return max(1, min(CELL_MAX, int(cap)))


def kit_cell(cap: int | None) -> int:
    """Minimum sheet cell: 32, or the occupancy cap for large mons."""
    n = CELL if cap is None else int(cap)
    return max(CELL, min(CELL_MAX, n))


def pose_scale(bboxes: list[tuple[int, int, int, int] | None], max_px: int | None,
               cell: int = CELL) -> float:
    """Hit the occupancy cap on the rest/first frame. Later frames may be larger."""
    ref = None
    for bb in bboxes:
        if bb:
            ref = bb
            break
    if not ref:
        return 1.0
    max_d = max(1, ref[2] - ref[0], ref[3] - ref[1])
    cap = cell if max_px is None else max(1, min(cell, int(max_px)))
    limit = cap / max_d
    return limit if FIT_UPSCALE else min(limit, 1.0)


def place_anchored(frame: Image.Image, bbox: tuple[int, int, int, int] | None,
                   origin: tuple[float, float] | None, scale: float,
                   dest_ax: float | None = None, dest_ay: float | None = None,
                   extra: tuple[float, float] = (0.0, 0.0),
                   cell: int = CELL) -> Image.Image:
    """Map one source point to the cell feet; keep the rest of the pose."""
    dest_ax = cell / 2 if dest_ax is None else dest_ax
    dest_ay = float(cell - 1) if dest_ay is None else dest_ay
    canvas = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    if not bbox:
        return canvas
    trimmed = frame.crop(bbox)
    fw, fh = trimmed.size
    if fw < 1 or fh < 1:
        return canvas
    nw = max(1, min(cell, int(round(fw * scale))))
    nh = max(1, min(cell, int(round(fh * scale))))
    resized = trimmed if (nw == fw and nh == fh) else trimmed.resize(
        (nw, nh), Image.Resampling.NEAREST)
    if origin is None:
        ox, oy = (bbox[0] + bbox[2]) / 2, bbox[3] - 1
    else:
        ox, oy = float(origin[0]), float(origin[1])
    paste_x = int(round(dest_ax - (ox - bbox[0]) * scale + extra[0]))
    paste_y = int(round(dest_ay - (oy - bbox[1]) * scale + extra[1]))
    # Rounding can drop a foot row past the cell; slide up rather than clip.
    if paste_y + nh > cell:
        paste_y -= paste_y + nh - cell
    if paste_y < 0 and nh <= cell:
        paste_y = 0
    canvas.paste(resized, (paste_x, paste_y), resized)
    return canvas


def facing_origin(anchors: list[tuple[int, int] | None],
                  bboxes: list[tuple[int, int, int, int] | None],
                  cell: int = CELL):
    for anchor in anchors:
        if anchor:
            return float(anchor[0]), float(anchor[1])
    for bbox in bboxes:
        if bbox:
            return (bbox[0] + bbox[2]) / 2.0, float(bbox[3] - 1)
    return cell / 2.0, float(cell - 1)


def plant_origin(anchor: tuple[int, int] | None,
                 bbox: tuple[int, int, int, int] | None,
                 cell: int = CELL):
    if anchor:
        return float(anchor[0]), float(anchor[1])
    if bbox:
        return (bbox[0] + bbox[2]) / 2.0, float(bbox[3] - 1)
    return cell / 2.0, float(cell - 1)


def lunge_ax(anchor: tuple[int, int] | None, ref: tuple[float, float],
             scale: float, cell: int = CELL) -> float:
    if not anchor:
        return cell / 2.0
    return cell / 2.0 + (anchor[0] - ref[0]) * scale * MOTION_AMP


def sprite_extents(bbox, origin, scale: float) -> tuple[float, float]:
    """Pixels of ink above / below the plant (shadow or bbox feet)."""
    if not bbox:
        return 0.0, 0.0
    if origin is None:
        oy = float(bbox[3] - 1)
    else:
        oy = float(origin[1])
    above = max(0.0, (oy - bbox[1]) * scale)
    # PIL bbox lower is exclusive; match paste_rect's py + nh.
    below = max(0.0, (bbox[3] - oy) * scale)
    return above, below


def paste_rect(bbox, origin, scale: float, dest_ax: float, dest_ay: float):
    nw = max(1, int(round((bbox[2] - bbox[0]) * scale)))
    nh = max(1, int(round((bbox[3] - bbox[1]) * scale)))
    px = dest_ax - (origin[0] - bbox[0]) * scale
    py = dest_ay - (origin[1] - bbox[1]) * scale
    return px, py, nw, nh


def nudge_ax_into_cell(bbox, origin, scale: float, dest_ax: float,
                       dest_ay: float, cell: int = CELL) -> float:
    """Keep a side lunge; pull it back if it would leave the cell."""
    if not bbox:
        return dest_ax
    px, _, nw, _ = paste_rect(bbox, origin, scale, dest_ax, dest_ay)
    if px < 0:
        dest_ax += -px
    px, _, nw, _ = paste_rect(bbox, origin, scale, dest_ax, dest_ay)
    if px + nw > cell:
        dest_ax -= (px + nw - cell)
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


def _read_block_frames(pack_dir: Path, anim: dict, faces: int = BLOCK_ROWS):
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
            face_rows = face_rows_for(dirs, faces)
            ticks = frame_ticks(anim, cols)
            frames: list[tuple[int, int, Image.Image, tuple | None, tuple | None]] = []
            for face, pmd_row in enumerate(face_rows):
                row = min(pmd_row, dirs - 1)
                for col in range(cols):
                    raw = key_magenta(slice_frame(sheet, col, row, fw, fh))
                    bbox = raw.getbbox()
                    anchor = cell_anchor(shadow, offsets, col, row, fw, fh, bbox)
                    frames.append((face, col, raw, bbox, anchor))
            return {
                "frames": frames,
                "cols": cols,
                "dirs": dirs,
                "faces": len(face_rows),
                "ticks": ticks,
                "fw": fw,
                "fh": fh,
            }
    finally:
        if shadow is not None:
            shadow.close()
        if offsets is not None:
            offsets.close()


def _fit_faces(frames: list, max_px: int | None, cell: int, nudge: bool = True):
    nfaces = _nfaces(frames)
    by_face: list[list] = [[] for _ in range(nfaces)]
    for face, col, raw, bbox, anchor in frames:
        if 0 <= face < nfaces:
            by_face[face].append((col, raw, bbox, anchor))
    face_scales: list[float] = []
    face_origins: list[list] = []
    face_refs: list[tuple[float, float]] = []
    rest_below = 0.0
    max_below = 0.0
    for face in range(nfaces):
        face_frames = by_face[face]
        rest_bb = None
        for item in face_frames:
            if item[0] == 0 and item[2]:
                rest_bb = item[2]
                break
        if rest_bb is None:
            for item in face_frames:
                if item[2]:
                    rest_bb = item[2]
                    break
        face_scale = pose_scale([rest_bb], max_px, cell)
        face_scales.append(face_scale)
        ref = facing_origin(
            [item[3] for item in face_frames],
            [item[2] for item in face_frames], cell)
        face_refs.append(ref)
        origins = [plant_origin(item[3], item[2], cell) for item in face_frames]
        face_origins.append(origins)
        for item, origin in zip(face_frames, origins):
            _above, below = sprite_extents(item[2], origin, face_scale)
            if below > max_below:
                max_below = below
            # Column 0 is the stand/rest plant. Combat frames with more
            # ink below the shadow must not lift that ground line.
            if item[0] == 0 and below > rest_below:
                rest_below = below
    plant_below = rest_below if rest_below > 0 else max_below
    dest_ay = min(float(cell - 1), float(cell) - math.ceil(plant_below + 0.01))
    if dest_ay < 0:
        dest_ay = 0.0
    fitted = []
    for face in range(nfaces):
        face_frames = by_face[face]
        face_scale = face_scales[face]
        origins = face_origins[face]
        ref = face_refs[face]
        dests = []
        for item, origin in zip(face_frames, origins):
            dest_ax = lunge_ax(item[3], ref, face_scale, cell)
            if nudge:
                dest_ax = nudge_ax_into_cell(
                    item[2], origin, face_scale, dest_ax, dest_ay, cell)
            dests.append((dest_ax, dest_ay))
        fitted.append((origins, dests, face_scale))
    return fitted


def measure_needed_cell(frames: list, max_px: int | None, probe: int) -> int:
    """Grow the probe cell so rest-scaled hops and bigger frames stay inside.

    Side lunges still get pulled back by nudge_ax_into_cell; do not inflate
    the sheet to keep the full MOTION_AMP travel.
    """
    fitted = _fit_faces(frames, max_px, probe, nudge=False)
    extra_top = 0
    max_nw = max_nh = 0
    max_above = max_below = 0.0
    for face, col, _raw, bbox, anchor in frames:
        if not bbox:
            continue
        origins, dests, face_scale = fitted[face]
        origin = origins[col] if col < len(origins) else plant_origin(anchor, bbox, probe)
        dest_ax, dest_ay = dests[col] if col < len(dests) else (probe / 2.0, float(probe - 1))
        # Size vs a centered plant; hops use the real dest so they keep headroom.
        _px, py, nw, nh = paste_rect(bbox, origin, face_scale, dest_ax, dest_ay)
        max_nw = max(max_nw, nw)
        max_nh = max(max_nh, nh)
        above, below = sprite_extents(bbox, origin, face_scale)
        if above > max_above:
            max_above = above
        if below > max_below:
            max_below = below
        if py < 0:
            extra_top = max(extra_top, int(math.ceil(-py)))
    needed = max(
        probe, max_nw, max_nh, probe + extra_top,
        int(math.ceil(max_above + max_below + 1)),
    )
    return min(CELL_MAX, needed)


def pack_needed_cell(pack_dir: Path, by_name: dict, max_px: int | None,
                     faces: int = BLOCK_ROWS) -> int:
    probe = kit_cell(max_px)
    needed = probe
    checks = [names for _pose, names in POSES]
    checks.extend(names for _pose, names, _prefer, _fb in EXTRA_POSES)
    seen: set[str] = set()
    for names in checks:
        anim, _dirs = pose_anim(pack_dir, by_name, names, prefer_named=True)
        if not anim:
            continue
        key = anim.get("source") or anim.get("name")
        if not key or key in seen:
            continue
        seen.add(key)
        data = _read_block_frames(pack_dir, anim, faces=faces)
        if not data:
            continue
        needed = max(needed, measure_needed_cell(data["frames"], max_px, probe))
    return needed


def pack_block_rows(pack_dir: Path, by_name: dict) -> int:
    checks = [names for _pose, names in POSES]
    checks.extend(names for _pose, names, _prefer, _fb in EXTRA_POSES)
    for names in checks:
        _anim, dirs = pose_anim(pack_dir, by_name, names, prefer_named=True)
        if dirs >= 8:
            return BLOCK_ROWS_MAX
    return BLOCK_ROWS


def bake_block(pack_dir: Path, anim: dict, dirs: int, max_px: int | None = None,
               cell: int = CELL, faces: int = BLOCK_ROWS):
    data = _read_block_frames(pack_dir, anim, faces=faces)
    if not data:
        return None
    frames = data["frames"]
    cols, dirs = data["cols"], data["dirs"]
    ticks, fw, fh = data["ticks"], data["fw"], data["fh"]
    nfaces = data.get("faces") or _nfaces(frames)
    fitted = _fit_faces(frames, max_px, cell, nudge=True)
    dest_ay = float(cell - 1)
    block = Image.new("RGBA", (cell * cols, cell * nfaces), (0, 0, 0, 0))
    for face, col, raw, bbox, anchor in frames:
        origins, dests, face_scale = fitted[face]
        origin = origins[col] if col < len(origins) else plant_origin(anchor, bbox, cell)
        dest_ax, face_ay = dests[col] if col < len(dests) else (cell / 2.0, dest_ay)
        tile = place_anchored(
            raw, bbox, origin, face_scale, dest_ax, face_ay, cell=cell)
        block.paste(tile, (col * cell, face * cell), tile)
    return block, dirs, cols, ticks, fw, fh


def write_kit_meta(path: Path, max_cols: int, pose_ticks: list[tuple[str, list[int]]],
                   cell: int = CELL, faces: int = BLOCK_ROWS) -> None:
    header = f"kit {cell} {max_cols}"
    if faces and int(faces) != BLOCK_ROWS:
        header += f" {int(faces)}"
    lines = [
        "# follower kit timing; 60 ticks/sec. Pad plays every column.",
        header,
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
    faces = pack_block_rows(pack_dir, by_name)
    cell = pack_needed_cell(pack_dir, by_name, max_px, faces)
    if cell > kit_cell(max_px):
        print(f"  cell {cell} (occupancy {max_px}; room for hops)")
    if faces > BLOCK_ROWS:
        print(f"  faces {faces} (cardinals + diagonals)")
    for pose, names in POSES:
        override = POSE_NAMES_BY_DEX.get(dex or 0, {}).get(pose)
        if override:
            names = override
        anim, dirs = pose_anim(
            pack_dir, by_name, names,
            prefer_named=(pose in PREFER_NAMED) or override is not None)
        # One-cell Idle is often a sit / faint hold. Walk has the stand cycle.
        if pose == "idle" and anim and anim_cols(pack_dir, anim) < 2:
            walk, wdirs = pose_anim(pack_dir, by_name, ("Walk",), prefer_named=True)
            if walk:
                print(f"  idle: Walk ({anim_cols(pack_dir, anim)}-frame Idle)")
                anim, dirs = walk, wdirs
        if not anim:
            if pose == "walk":
                sys.stderr.write(f"{pack_dir}: no Walk/Idle PNG\n")
                return False
            if pose == "idle" or pose == "faint":
                src_name = "walk" if pose == "idle" else (
                    "hit" if "hit" in by_pose else "walk")
                src = by_pose.get(src_name) or by_pose.get("walk")
                if not src:
                    continue
                ticks = list(ticks_by_pose.get(src_name)
                             or ticks_by_pose.get("walk")
                             or [2] * COLS)
                blocks.append(src.copy())
                by_pose[pose] = src
                ticks_by_pose[pose] = ticks
                pose_ticks.append((pose, ticks))
                used += 1
                print(f"  {pose}: copy {src_name}")
                continue
            break
        baked = bake_block(pack_dir, anim, dirs, max_px, cell, faces)
        if not baked:
            if pose == "idle" or pose == "faint":
                src_name = "walk" if pose == "idle" else (
                    "hit" if "hit" in by_pose else "walk")
                src = by_pose.get(src_name) or by_pose.get("walk")
                if not src:
                    continue
                ticks = list(ticks_by_pose.get(src_name)
                             or ticks_by_pose.get("walk")
                             or [2] * COLS)
                blocks.append(src.copy())
                by_pose[pose] = src
                ticks_by_pose[pose] = ticks
                pose_ticks.append((pose, ticks))
                used += 1
                print(f"  {pose}: copy {src_name}")
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
            baked = bake_block(pack_dir, anim, dirs, max_px, cell, faces) if anim else None
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
    max_cols = max((max(1, b.width // cell) for b in blocks), default=COLS)
    kit = Image.new("RGBA", (cell * max_cols, cell * faces * used), (0, 0, 0, 0))
    for i, block in enumerate(blocks):
        kit.paste(block, (0, i * cell * faces), block)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    kit.save(out_path)
    write_kit_meta(out_path.with_suffix(".kit"), max_cols, pose_ticks, cell, faces)
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
