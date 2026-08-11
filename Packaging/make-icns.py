#!/usr/bin/env python3
"""Pack a set of PNGs into a macOS .icns, from Linux.

WHY THIS EXISTS
---------------
The normal way to make an .icns is `iconutil`, which ships with Xcode and runs
only on macOS. This app is built on a Linux VPS, so either the icon comes from
here or the app ships with Electron's default one — and an app with the stock
Electron icon in the dock is not a finished app.

The format turns out to be trivial once you look at it:

    'icns' <uint32 total length>
    then, repeated: <4-byte type> <uint32 length including these 8 bytes> <data>

Since OS X 10.7 the payload for the modern types may be a plain PNG, which is
why this is forty lines and not a JPEG-2000 encoder.

WHY SO MANY SIZES
-----------------
macOS does not scale one image; it picks the nearest variant and scales from
there. Omit the small ones and the icon in a Finder list view is a 1024 image
squashed to 16 pixels, which turns a thin gold ring into grey mush. The @2x
types matter for the same reason on Retina displays, where a "16pt" icon is
really 32 pixels.
"""

from __future__ import annotations

import struct
import subprocess
import sys
from pathlib import Path

# (icns type, pixel size). The duplicated sizes are not a mistake: `ic11` is
# "16pt at 2x" and `icp5` is "32pt at 1x". They are the same bitmap, and macOS
# wants both entries present.
VARIANTS: list[tuple[bytes, int]] = [
    (b"icp4", 16),    # 16pt
    (b"icp5", 32),    # 32pt
    (b"ic11", 32),    # 16pt @2x
    (b"ic12", 64),    # 32pt @2x
    (b"ic07", 128),   # 128pt
    (b"ic13", 256),   # 128pt @2x
    (b"ic08", 256),   # 256pt
    (b"ic14", 512),   # 256pt @2x
    (b"ic09", 512),   # 512pt
    (b"ic10", 1024),  # 512pt @2x
]


def render(svg: Path, size: int, out: Path) -> bytes:
    """Rasterise the SVG at one size.

    Rendered from the vector at every size rather than downscaled from 1024:
    a 44-unit stroke resampled to 16 pixels loses its ends, while rendering it
    at 16 lets the rasteriser keep the shape antialiased and whole.
    """
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), str(svg), "-o", str(out)],
        check=True,
    )
    return out.read_bytes()


def build(svg: Path, icns: Path, workdir: Path) -> None:
    workdir.mkdir(parents=True, exist_ok=True)

    # One render per distinct size, reused across the types that share it.
    cache: dict[int, bytes] = {}
    chunks: list[bytes] = []

    for kind, size in VARIANTS:
        if size not in cache:
            cache[size] = render(svg, size, workdir / f"icon-{size}.png")
        png = cache[size]
        chunks.append(kind + struct.pack(">I", len(png) + 8) + png)

    body = b"".join(chunks)
    icns.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)

    print(f"{icns}  —  {len(VARIANTS)} variants, {icns.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    here = Path(__file__).resolve().parent.parent
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else here / "assets" / "icon-macos.svg"
    target = Path(sys.argv[2]) if len(sys.argv) > 2 else here / "assets" / "icon.icns"
    build(source, target, here / "assets" / "iconset")
