#!/usr/bin/env python3
"""Stamp Diglett Walk into every follower kit as pose `dig`.

The pad plays that row for vanish / buried / emerge. Battle never loads
Diglett's sheet as a borrow. Re-run after a full bake; safe to repeat.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.stderr.write("Need Pillow: python3 -m pip install pillow\n")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent
DIGLETT_PNG = ROOT / "follower_050.png"
DIGLETT_KIT = ROOT / "follower_050.kit"
DIG_TICKS = (8, 8, 8)


def parse_kit(path: Path) -> dict:
    poses: list[tuple[str, list[int]]] = []
    cell, cols, faces = 32, 4, 4
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        words = line.split()
        kind = words[0]
        if kind == "kit":
            cell = int(words[1]) if len(words) > 1 else cell
            cols = int(words[2]) if len(words) > 2 else cols
            faces = int(words[3]) if len(words) > 3 else faces
        elif kind == "faces":
            faces = int(words[1]) if len(words) > 1 else faces
        elif len(words) > 1:
            ticks = [max(1, int(w)) for w in words[1:]]
            poses.append((kind, ticks))
    if faces != 8:
        faces = 4
    return {"cell": cell, "cols": cols, "faces": faces, "poses": poses}


def write_kit(path: Path, meta: dict) -> None:
    header = f"kit {meta['cell']} {meta['cols']}"
    if int(meta["faces"]) != 4:
        header += f" {int(meta['faces'])}"
    lines = [
        "# follower kit timing; 60 ticks/sec. Pad plays every column.",
        header,
    ]
    for pose, ticks in meta["poses"]:
        lines.append(pose + " " + " ".join(str(t) for t in ticks))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def walk_block_from_diglett() -> tuple[Image.Image, int, int, int] | None:
    if not DIGLETT_PNG.is_file() or not DIGLETT_KIT.is_file():
        return None
    meta = parse_kit(DIGLETT_KIT)
    cell, faces = meta["cell"], meta["faces"]
    walk_ticks = None
    walk_index = 0
    for i, (pose, ticks) in enumerate(meta["poses"]):
        if pose == "walk":
            walk_ticks = ticks
            walk_index = i
            break
    if not walk_ticks:
        return None
    cols = len(walk_ticks)
    with Image.open(DIGLETT_PNG) as im:
        im = im.convert("RGBA")
        y0 = walk_index * cell * faces
        block = im.crop((0, y0, cell * cols, y0 + cell * faces)).copy()
    return block, cell, faces, cols


def resample_dig_block(
    src: Image.Image, src_cell: int, src_faces: int, src_cols: int,
    dest_cell: int, dest_faces: int,
) -> Image.Image:
    out = Image.new("RGBA", (dest_cell * src_cols, dest_cell * dest_faces), (0, 0, 0, 0))
    for face in range(dest_faces):
        src_face = face if face < src_faces else min(src_faces - 1, face % src_faces)
        for col in range(src_cols):
            tile = src.crop((
                col * src_cell,
                src_face * src_cell,
                (col + 1) * src_cell,
                (src_face + 1) * src_cell,
            ))
            if dest_cell < src_cell:
                nearest = getattr(Image, "Resampling", Image).NEAREST
                tile = tile.resize((dest_cell, dest_cell), nearest)
                px = col * dest_cell
                py = face * dest_cell
            else:
                px = col * dest_cell + (dest_cell - tile.width) // 2
                py = face * dest_cell + (dest_cell - tile.height)
            out.paste(tile, (px, py), tile)
    return out


def stamp_dig_onto_sheet(
    sheet: Image.Image, meta: dict, dig_block: Image.Image,
) -> Image.Image:
    cell, faces = meta["cell"], meta["faces"]
    poses = meta["poses"]
    n = len(poses)
    expect_h = cell * faces * n
    if sheet.height != expect_h or sheet.width % cell != 0:
        raise ValueError(
            f"sheet {sheet.width}x{sheet.height} != {n} poses "
            f"at cell {cell} faces {faces}"
        )
    dig_index = None
    for i, (pose, _ticks) in enumerate(poses):
        if pose == "dig":
            dig_index = i
            break
    if dig_index is None:
        canvas = Image.new(
            "RGBA",
            (max(sheet.width, dig_block.width), sheet.height + cell * faces),
            (0, 0, 0, 0),
        )
        canvas.paste(sheet, (0, 0), sheet)
        canvas.paste(dig_block, (0, sheet.height), dig_block)
        poses.append(("dig", list(DIG_TICKS)))
        meta["cols"] = max(meta["cols"], dig_block.width // cell)
        return canvas
    y0 = dig_index * cell * faces
    canvas = sheet.copy()
    if canvas.width < dig_block.width:
        wider = Image.new("RGBA", (dig_block.width, canvas.height), (0, 0, 0, 0))
        wider.paste(canvas, (0, 0), canvas)
        canvas = wider
    blank = Image.new("RGBA", (canvas.width, cell * faces), (0, 0, 0, 0))
    canvas.paste(blank, (0, y0))
    canvas.paste(dig_block, (0, y0), dig_block)
    poses[dig_index] = ("dig", list(DIG_TICKS))
    meta["cols"] = max(meta["cols"], dig_block.width // cell)
    return canvas


def inject_kit(png_path: Path, source: tuple[Image.Image, int, int, int]) -> bool:
    kit_path = png_path.with_suffix(".kit")
    if not kit_path.is_file():
        return False
    meta = parse_kit(kit_path)
    src_block, src_cell, src_faces, src_cols = source
    block = resample_dig_block(
        src_block, src_cell, src_faces, src_cols, meta["cell"], meta["faces"])
    with Image.open(png_path) as im:
        sheet = im.convert("RGBA")
        stamped = stamp_dig_onto_sheet(sheet, meta, block)
        stamped.save(png_path)
    write_kit(kit_path, meta)
    return True


def append_dig_to_bake(
    blocks: list, pose_ticks: list, cell: int, faces: int,
    by_pose: dict, ticks_by_pose: dict,
    walk_override: Image.Image | None = None,
) -> None:
    """Used by bake_pmd.py after extras so a rebake keeps `dig`."""
    if any(name == "dig" for name, _ticks in pose_ticks):
        return
    if walk_override is not None:
        src = walk_override
        src_cell = cell
        src_faces = max(1, src.height // cell)
        src_cols = max(1, src.width // cell)
        block = resample_dig_block(src, src_cell, src_faces, src_cols, cell, faces)
    else:
        source = walk_block_from_diglett()
        if not source:
            print("  dig: skip (no follower_050 Walk)")
            return
        src, src_cell, src_faces, src_cols = source
        block = resample_dig_block(src, src_cell, src_faces, src_cols, cell, faces)
    ticks = list(DIG_TICKS)
    blocks.append(block)
    pose_ticks.append(("dig", ticks))
    by_pose["dig"] = block
    ticks_by_pose["dig"] = ticks
    print(f"  dig: Diglett Walk {src_cols} frames")


def main(argv: list[str]) -> int:
    source = walk_block_from_diglett()
    if not source:
        sys.stderr.write("need baked follower_050.png + .kit (Walk row)\n")
        return 1
    targets = []
    if len(argv) > 1:
        for arg in argv[1:]:
            p = ROOT / arg if not arg.endswith(".png") else Path(arg)
            if p.name.startswith("follower_") and p.suffix == ".png":
                targets.append(p if p.is_absolute() else ROOT / p.name)
            else:
                targets.append(ROOT / f"follower_{int(arg):03d}.png")
    else:
        targets = sorted(ROOT.glob("follower_[0-9][0-9][0-9].png"))
    n = 0
    for png in targets:
        if not png.is_file():
            sys.stderr.write(f"missing {png}\n")
            continue
        inject_kit(png, source)
        print(f"dig {png.name}")
        n += 1
    print(f"{n} kits have Diglett Walk as dig")
    return 0 if n else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
