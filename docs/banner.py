#!/usr/bin/env python3
"""Render docs/banner.png: the picture a README opens on.

The wordmark is not drawn here. It is read out of the product's own oak.yaml -
the same block of characters the splash screen comes up on - so the banner and
the program cannot come to disagree about what the product is called. The name,
the accent and the eyebrow come from there too.

This file is the same in every project that uses it. What belongs to one
project - which screenshots it collages, what it says under the name, how large
the wordmark is set - is passed in by that project's Makefile.

Output is 1280x640 at two device pixels to the CSS pixel, which is also the
size GitHub wants for a repository's social preview: one image, both jobs.

Needs: chromium, imagemagick.
"""

import argparse
import base64
import pathlib
import subprocess
import sys
from collections import defaultdict

W, H = 1280, 640
SCALE = 2

BACK = "#232830"  # a shade under Nord polar night, so the cards lift off it
TEXT = "#d8dee9"
MUTED = "rgba(216,222,233,.42)"


# --- the wordmark, as one path -------------------------------------------
#
# A block of cells becomes a single outline rather than one rect per cell:
# adjacent rects show hairline seams wherever the browser lands them on a
# fractional pixel, and an outline cannot.


def rings(filled):
    """Closed, clockwise rings around a set of cells."""
    edges = defaultdict(list)
    for x, y in filled:
        if (x, y - 1) not in filled:
            edges[(x, y)].append((x + 1, y))
        if (x + 1, y) not in filled:
            edges[(x + 1, y)].append((x + 1, y + 1))
        if (x, y + 1) not in filled:
            edges[(x + 1, y + 1)].append((x, y + 1))
        if (x - 1, y) not in filled:
            edges[(x, y + 1)].append((x, y))

    out = []
    while edges:
        start = next(iter(edges))
        ring, point, heading = [start], start, None
        while True:
            point, heading = step(edges, point, heading)
            if point == start:
                break
            ring.append(point)
        out.append(straighten(ring))
    return out


def step(edges, point, heading):
    """Leave a vertex, turning as tightly clockwise as its edges allow.

    Where two cells meet at a corner only, the vertex between them carries two
    ways out. Taking the clockwise-most keeps them two rings that touch instead
    of one ring that crosses itself.
    """
    out = edges[point]
    if len(out) > 1 and heading is not None:
        dx, dy = heading
        for turn in ((-dy, dx), (dx, dy), (dy, -dx)):
            nxt = (point[0] + turn[0], point[1] + turn[1])
            if nxt in out:
                out.remove(nxt)
                break
        else:
            nxt = out.pop()
    else:
        nxt = out.pop()
    if not out:
        del edges[point]
    return nxt, (nxt[0] - point[0], nxt[1] - point[1])


def straighten(ring):
    """Drop the vertices sitting in the middle of a straight run."""
    kept = []
    for i, (x, y) in enumerate(ring):
        ax, ay = ring[i - 1]
        bx, by = ring[(i + 1) % len(ring)]
        if (x - ax, y - ay) != (bx - x, by - y):
            kept.append((x, y))
    return kept


def outline(filled):
    out = []
    for ring in rings(filled):
        px = py = None
        for i, (x, y) in enumerate(ring):
            if i == 0:
                out.append(f"M{x} {y}")
            elif x == px:
                out.append(f"v{y - py}")
            else:
                out.append(f"h{x - px}")
            px, py = x, y
        out.append("z")
    return "".join(out)


def wordmark(block, colour, cell):
    """The yaml's block characters, set at the terminal's own cell shape."""
    filled = {
        (x, y)
        for y, row in enumerate(block.split("\n"))
        for x, ch in enumerate(row)
        if ch != " "
    }
    cols = max(x for x, _ in filled) + 1
    rows = max(y for _, y in filled) + 1
    return (
        f'<svg class="wordmark" viewBox="0 0 {cols} {rows}" '
        f'width="{cols * cell}" height="{rows * cell * 2}" '
        f'preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">'
        f'<path fill="{colour}" d="{outline(filled)}"/></svg>'
    )


# --- the product, as it describes itself ---------------------------------


def logo_block(product):
    """The `logo: |` block, without a yaml parser for one field."""
    lines = product.read_text().split("\n")
    start = next(i for i, l in enumerate(lines) if l.startswith("logo:"))
    body = []
    for line in lines[start + 1:]:
        if line and not line.startswith("  "):
            break
        body.append(line[2:])
    return "\n".join(body)


def field(product, key):
    for line in product.read_text().split("\n"):
        if line.startswith(f"{key}:"):
            return line.split(":", 1)[1].strip().strip('"')
    raise SystemExit(f"{product}: no {key}:")


def data_uri(path):
    kind = "jpeg" if path.suffix in (".jpg", ".jpeg") else "png"
    blob = base64.b64encode(path.read_bytes()).decode()
    return f"data:image/{kind};base64,{blob}"


# --- the page ------------------------------------------------------------


def page(args):
    block = logo_block(args.product)
    eyebrow, _, art = block.strip("\n").partition("\n\n")
    accent = field(args.product, "accent")
    mark = args.logo.read_text().split("-->", 1)[-1].strip()
    back, front = (data_uri(p) for p in args.card)
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  html,body {{ width:{W}px; height:{H}px; overflow:hidden; }}
  body {{
    background:{BACK};
    font-family:"FiraCode Nerd Font Mono", ui-monospace, monospace;
    position:relative;
  }}

  /* The field: a faint grid, a glow behind the cards, a vignette. No scan
     lines - at one device pixel they moire the moment GitHub scales the
     banner down, and they cost more in bytes than they carry. */
  .grid, .glow, .vig {{ position:absolute; inset:0; }}
  .grid {{
    background-image:
      linear-gradient(rgba(216,222,233,.030) 1px, transparent 1px),
      linear-gradient(90deg, rgba(216,222,233,.030) 1px, transparent 1px);
    background-size:16px 16px;
    -webkit-mask-image:radial-gradient(120% 90% at 30% 40%, #000 30%, transparent 78%);
  }}
  .glow {{
    background:
      radial-gradient(52% 70% at 76% 46%, {accent}24, transparent 68%),
      radial-gradient(38% 52% at 12% 78%, {accent}12, transparent 70%);
  }}
  .vig {{
    z-index:4;
    background:radial-gradient(78% 78% at 50% 46%, transparent 42%, rgba(0,0,0,.42));
  }}

  /* the name */
  .said {{
    position:absolute; left:76px; top:50%; transform:translateY(-50%);
    width:560px; z-index:5;
  }}
  .mark, .mark svg {{ width:64px; height:64px; display:block; }}
  /* a selector, so a mark drawn in currentColor takes the product's accent
     rather than the fallback its own file carries */
  .mark svg {{ color:{accent}; }}
  .eyebrow {{
    margin-top:30px; font-size:13px; letter-spacing:.34em;
    text-transform:uppercase; color:{MUTED};
  }}
  .wordmark {{ display:block; margin-top:20px; }}
  .rule {{ width:52px; height:3px; background:{accent}; margin-top:28px; }}
  .tag {{
    margin-top:22px; font-size:17px; line-height:1.62; color:{TEXT};
    max-width:500px; letter-spacing:-.005em;
  }}

  /* the collage */
  .cards {{ position:absolute; inset:0; z-index:2; }}
  .cards img {{
    position:absolute; display:block; border-radius:12px;
    box-shadow:0 26px 60px rgba(0,0,0,.55), 0 0 0 1px {accent}2e;
  }}
  .back  {{ width:596px; left:700px; top:26px; opacity:.66; }}
  .front {{ width:648px; left:664px; top:274px; }}
  .fade {{
    position:absolute; inset:0; z-index:3; pointer-events:none;
    background:linear-gradient(90deg, {BACK} 0 26%, {BACK}00 52%);
  }}
</style></head><body>
  <div class="glow"></div>
  <div class="grid"></div>
  <div class="cards">
    <img class="back" src="{back}" alt="">
    <img class="front" src="{front}" alt="">
  </div>
  <div class="fade"></div>
  <div class="vig"></div>
  <div class="said">
    <span class="mark">{mark}</span>
    <div class="eyebrow">{eyebrow.strip()}</div>
    {wordmark(art.rstrip(), accent, args.cell)}
    <div class="rule"></div>
    <div class="tag">{args.tagline}</div>
  </div>
</body></html>"""


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--product", type=pathlib.Path, default=pathlib.Path("oak.yaml"))
    p.add_argument("--logo", type=pathlib.Path, default=pathlib.Path("docs/logo.svg"))
    p.add_argument("--card", type=pathlib.Path, action="append", required=True,
                   help="a screenshot for the collage; give it twice, back then front")
    p.add_argument("--tagline", required=True)
    p.add_argument("--cell", type=int, default=12,
                   help="width of one wordmark cell in px; its height is twice that")
    p.add_argument("--out", type=pathlib.Path, default=pathlib.Path("docs/banner.png"))
    args = p.parse_args()

    if len(args.card) != 2:
        p.error("--card is given exactly twice: the card behind, then the one in front")

    out = args.out.resolve()
    html = out.with_suffix(".html")
    html.write_text(page(args))
    try:
        subprocess.run([
            "chromium", "--headless",
            f"--force-device-scale-factor={SCALE}",
            "--default-background-color=00000000",
            "--hide-scrollbars",
            f"--window-size={W},{H}",
            f"--screenshot={out}",
            html.as_uri(),
        ], check=True, capture_output=True)
    finally:
        html.unlink(missing_ok=True)

    # The banner is opaque and its gradients survive a 256-colour palette:
    # measured at RMSE 0.002, with no banding under a contrast stretch, for a
    # quarter of the bytes. An alpha channel it never uses costs the rest.
    subprocess.run([
        "magick", str(out),
        "-background", BACK, "-alpha", "remove", "-alpha", "off",
        "-dither", "None", "-colors", "256",
        "-strip", "-define", "png:compression-level=9", str(out),
    ], check=True)
    print(f"{out}  {out.stat().st_size} bytes")


if __name__ == "__main__":
    sys.exit(main())
