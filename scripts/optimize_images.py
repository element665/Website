#!/usr/bin/env python3
"""Shrink oversized JPEGs before they are baked into the nginx image.

Usage: optimize_images.py DIR

Why: photos straight off a phone are ~3000x4000 px and ~1 MB each, but the site shows
them in cards that are at most a few hundred CSS pixels wide (roughly 1350 px even on a 3x
phone once object-fit crops them). Originals in git are never modified: this only runs
inside the Docker build stage, on a copy.

For every .jpg / .jpeg under DIR it:
  - bakes the EXIF rotation into the pixels (the EXIF block is then dropped, so GPS and
    other camera metadata are not published),
  - scales the long edge down to MAX_EDGE (never up),
  - re-encodes as a progressive JPEG at QUALITY, keeping the embedded colour profile,
  - keeps the result only if it is actually smaller.
PNG and every other format are left untouched.
"""
import sys
from pathlib import Path

from PIL import Image, ImageOps

MAX_EDGE = 1800          # px, longest side
QUALITY = 82
SKIP_BELOW = 200 * 1024  # already small: don't re-encode (avoids lossy generations for no gain)


def optimize(path: Path):
    """Return (before_bytes, after_bytes, size_before, size_after) or None if not a JPEG."""
    before = path.stat().st_size
    with Image.open(path) as im:
        if im.format != "JPEG":
            return None
        size_before = im.size
        icc = im.info.get("icc_profile")
        img = ImageOps.exif_transpose(im)  # applies rotation; result has no Orientation tag
        size_after_rotate = img.size

        if max(size_after_rotate) <= MAX_EDGE and before < SKIP_BELOW:
            return before, before, size_before, size_before

        img.thumbnail((MAX_EDGE, MAX_EDGE), Image.Resampling.LANCZOS)  # only ever shrinks
        if img.mode not in ("RGB", "L"):
            img = img.convert("RGB")
            icc = None  # profile no longer matches the converted pixels

        tmp = path.with_name(path.name + ".tmp")
        options = {"quality": QUALITY, "optimize": True, "progressive": True}
        if icc:
            options["icc_profile"] = icc
        img.save(tmp, "JPEG", **options)

    after = tmp.stat().st_size
    if after < before:
        tmp.replace(path)
        return before, after, size_before, img.size
    tmp.unlink()
    return before, before, size_before, size_before


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    root = Path(argv[1])
    files = sorted(p for p in root.rglob("*") if p.suffix.lower() in (".jpg", ".jpeg"))
    total_before = total_after = 0
    for path in files:
        result = optimize(path)  # an unreadable image raises and fails the build on purpose
        if result is None:
            continue
        before, after, s0, s1 = result
        total_before += before
        total_after += after
        print(f"{path.name:32} {s0[0]}x{s0[1]} -> {s1[0]}x{s1[1]}  {before // 1024:5d} KB -> {after // 1024:5d} KB")
    print(f"\n{len(files)} JPEGs: {total_before / 1048576:.1f} MB -> {total_after / 1048576:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
