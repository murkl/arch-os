#!/usr/bin/env python3
"""Render the README's pictures: docs/download.svg and docs/requirements/.

Text is set as outlines of the banner's font, since GitHub lets an SVG shown as
an image load no font, and the viewer's own would differ on every machine. The
button is the accent in oak.yaml. Under it, each starting point is a quiet pill
of its own, so the two wrap on a narrow screen, once for each GitHub theme and
on a ground of its own, so it reads on the other theme too. The text
alternatives are written into README.md from the same run.

Needs: python-fonttools, ttf-firacode-nerd.
"""

import pathlib
import re
import subprocess
import sys

try:
    from fontTools.pens.boundsPen import BoundsPen
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont
except ImportError:
    sys.exit("needs python-fonttools: sudo pacman -S python-fonttools")

DOCS = pathlib.Path(__file__).resolve().parent
FAMILY = "FiraCode Nerd Font Mono"

ARCH = ("x86_64", "UEFI")
SPECS = ("memory", "disk")
# Name, icon, what it is, and what it needs of each spec in GiB.
TIERS = (
    ("Core", "\uf489", "Text console", (2, 16)),  # nf-oct-terminal
    ("Desktop", "\U000f0379", "GNOME on Wayland", (4, 32)),  # nf-md-monitor
)
# GitHub's own colours for a secondary button, so a pill sits on its theme as part of the page.
THEMES = {
    "light": {"fill": "#f6f8fa", "line": "#d1d9e0", "text": "#1f2328", "muted": "#59636e"},
    "dark": {"fill": "#151b23", "line": "#3d444d", "text": "#f0f6fc", "muted": "#9198a1"},
}


def number(value):
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return "0" if text in ("", "-0") else text


class Face:
    """One style of the font, set as outlines."""

    def __init__(self, style):
        found = subprocess.run(
            ["fc-match", "--format=%{family}|%{style}|%{file}", f"{FAMILY}:style={style}"],
            capture_output=True, text=True, check=True).stdout
        family, styles, file = found.split("|", 2)
        if FAMILY not in family.split(",") or style not in styles.split(","):
            sys.exit(f"needs {FAMILY} {style}: sudo pacman -S ttf-firacode-nerd")
        font = TTFont(file)
        self.glyphs = font.getGlyphSet()
        self.cmap = font.getBestCmap()
        self.em = font["head"].unitsPerEm
        self.ascent, self.descent = font["hhea"].ascent, -font["hhea"].descent
        self.advance = font["hmtx"][self.cmap[ord("0")]][0]

    def glyph(self, char):
        name = self.cmap.get(ord(char))
        if name is None:
            sys.exit(f"{FAMILY} has no U+{ord(char):04X}")
        return self.glyphs[name]

    def width(self, text, size):
        return len(text) * self.advance * size / self.em

    def baseline(self, top, size, line):
        """Where text sits in a line box, as a browser centres it."""
        scale = size / self.em
        return top + (line - (self.ascent + self.descent) * scale) / 2 + self.ascent * scale

    def text(self, text, x, y, size):
        """One line of text, its baseline at y."""
        pen = SVGPathPen(self.glyphs, ntos=number)
        scale = size / self.em
        for i, char in enumerate(text):
            at = x + i * self.advance * scale
            self.glyph(char).draw(TransformPen(pen, (scale, 0, 0, -scale, at, y)))
        return pen.getCommands()

    def icon(self, char, cx, cy, size):
        """One icon, its ink as large as a square size pixels across, centred on (cx, cy).

        Measured by its ink, since the font squeezes every icon into one cell,
        and by area, so a wide one weighs as much as a square one.
        """
        glyph = self.glyph(char)
        bounds = BoundsPen(self.glyphs)
        glyph.draw(bounds)
        x0, y0, x1, y1 = bounds.bounds
        scale = size / ((x1 - x0) * (y1 - y0)) ** .5
        pen = SVGPathPen(self.glyphs, ntos=number)
        glyph.draw(TransformPen(pen, (scale, 0, 0, -scale,
                                      cx - (x0 + x1) / 2 * scale, cy + (y0 + y1) / 2 * scale)))
        return pen.getCommands()


def accent():
    for line in (DOCS.parent / "oak.yaml").read_text().split("\n"):
        if line.startswith("accent:"):
            return line.split(":", 1)[1].strip().strip('"')
    sys.exit("oak.yaml: no accent:")


def mix(a, b, share):
    """a with share of b laid over it."""
    pa, pb = (int(a[i:i + 2], 16) for i in (1, 3, 5)), (int(b[i:i + 2], 16) for i in (1, 3, 5))
    return "#" + "".join(f"{round(x + (y - x) * share):02x}" for x, y in zip(pa, pb))


def svg(width, height, title, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{number(width)}" height="{number(height)}"'
            f' viewBox="0 0 {number(width)} {number(height)}">\n'
            f"  <title>{title}</title>\n" + "".join(f"  {line}\n" for line in body) + "</svg>\n")


def path(d, fill, opacity=None):
    alpha = f' fill-opacity="{number(opacity)}"' if opacity is not None else ""
    return f'<path fill="{fill}"{alpha} d="{d}"/>'


def download(regular, bold, fill):
    """The button the README opens with.

    Clear field above it makes the gap to the tagline as wide as the one the
    pills keep under them, since GitHub lets a README set no spacing of its own.
    """
    h, radius, chip, margin = 64, 10, 20, 8
    cx = cy = h / 2
    x = cx + chip + 14
    title = "Download ISO"
    w = round(x + bold.width(title, 20) + 26)
    top = (h - 26 - 18) / 2
    return svg(w, h + margin, alt_download(), [
        f'<g transform="translate(0 {margin})">',
        '<defs><linearGradient id="fill" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{fill}"/>'
        f'<stop offset="1" stop-color="{mix(fill, "#000000", 0.2)}"/></linearGradient></defs>',
        f'<rect width="{w}" height="{h}" rx="{radius}" fill="url(#fill)"/>',
        f'<rect x=".5" y=".5" width="{w - 1}" height="{h - 1}" rx="{radius - .5}"'
        ' fill="none" stroke="#fff" stroke-opacity=".16"/>',
        f'<circle cx="{number(cx)}" cy="{number(cy)}" r="{chip}" fill="#fff" fill-opacity=".16"/>',
        path(regular.icon("\U000f0120", cx, cy, 20), "#fff"),  # nf-md-tray_arrow_down
        path(bold.text(title, x, bold.baseline(top, 20, 26), 20), "#fff"),
        path(regular.text(" · ".join(ARCH), x, regular.baseline(top + 26, 13, 18), 13), "#fff", .8),
        "</g>",
    ])


def needs_line(needs):
    """What a starting point needs, as runs of text and whether each is a value."""
    runs = []
    for i, (need, spec) in enumerate(zip(needs, SPECS)):
        runs += [(f"{need} GiB", True), (f" {spec}" + (" · " if i < len(SPECS) - 1 else ""), False)]
    return runs


def pill(regular, bold, theme, index):
    """One starting point and what it needs, as wide as the widest of them.

    A margin of clear field around it keeps two side by side apart, and apart
    when they wrap.
    """
    name, icon, kind, needs = TIERS[index]
    h, radius, chip, margin = 56, 10, 16, 8
    cx = cy = h / 2
    x = cx + chip + 12
    widest = max(max(bold.width(each[0], 14) + regular.width(f"  {each[2]}", 12),
                     regular.width("".join(run for run, _ in needs_line(each[3])), 12)) for each in TIERS)
    w = round(x + widest + 20)
    top = (h - 20 - 16) / 2
    first, second = bold.baseline(top, 14, 20), regular.baseline(top + 20, 12, 16)
    body = [
        f'<g transform="translate({margin} {margin})">',
        f'<rect x=".5" y=".5" width="{w - 1}" height="{h - 1}" rx="{radius - .5}" fill="{theme["fill"]}"'
        f' stroke="{theme["line"]}"/>',
        f'<circle cx="{number(cx)}" cy="{number(cy)}" r="{chip}" fill="{theme["text"]}" fill-opacity=".06"/>',
        path(regular.icon(icon, cx, cy, 16), theme["muted"]),
        path(bold.text(name, x, first, 14), theme["text"]),
        path(regular.text(f"  {kind}", x + bold.width(name, 14), first, 12), theme["muted"]),
    ]
    at = x
    for run, value in needs_line(needs):
        body.append(path(regular.text(run, at, second, 12), theme["text" if value else "muted"]))
        at += regular.width(run, 12)
    body.append("</g>")
    return svg(w + 2 * margin, h + 2 * margin, alt_pill(index), body)


def alt_download():
    return f"Download the latest ISO, for {ARCH[0]} with {ARCH[1]}"


def alt_pill(index):
    name, _, kind, needs = TIERS[index]
    return f"{name} ({kind}): " + ", ".join(f"{need} GiB {spec}" for need, spec in zip(needs, SPECS))


def main():
    regular, bold = Face("Regular"), Face("Bold")
    (DOCS / "download.svg").write_text(download(regular, bold, accent()))
    alts = {"download.svg": alt_download()}
    (DOCS / "requirements").mkdir(exist_ok=True)
    for index, (name, *_) in enumerate(TIERS):
        for mode, theme in THEMES.items():
            (DOCS / "requirements" / f"{name.lower()}-{mode}.svg").write_text(pill(regular, bold, theme, index))
        alts[f"requirements/{name.lower()}-light.svg"] = alt_pill(index)
    readme = DOCS / "README.md"
    page = readme.read_text()
    for src, text in alts.items():
        page, found = re.subn(rf'(<img src="{re.escape(src)}"[^>]* alt=")[^"]*"',
                              lambda m: m.group(1) + text + '"', page)
        if found != 1:
            sys.exit(f'README.md: no <img src="{src}" ... alt="...">')
    readme.write_text(page)


if __name__ == "__main__":
    main()
