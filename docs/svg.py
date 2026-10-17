#!/usr/bin/env python3
"""Render the README's pictures: docs/download.svg and docs/requirements/.

Text is set as outlines of the banner's font, since GitHub lets an SVG shown as
an image load no font, and the viewer's own would differ on every machine. The
accent is the one in oak.yaml. Each starting point is a picture of its own on no
background, once for each GitHub theme, and its text alternative is written into
README.md from the same run.

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

# GitHub's own text colours, so the requirements read as part of the page.
THEMES = {
    "light": {"text": "#1f2328", "muted": "#59636e"},
    "dark": {"text": "#f0f6fc", "muted": "#9198a1"},
}
SPECS = (("", "Memory"), ("", "Disk"))  # nf-fa-memory, nf-fa-hdd_o
# Name, icon, what it is, and what it needs of each spec in GiB.
TIERS = (
    ("Core", "", "Text console", (2, 16)),  # nf-oct-terminal
    ("Desktop", "\U000f0379", "GNOME on Wayland", (4, 32)),  # nf-md-monitor
)


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
        self.cap = font["OS/2"].sCapHeight
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

    def middle(self, baseline, size):
        """Halfway up a capital, where an icon beside the text is centred."""
        return baseline - self.cap * size / self.em / 2

    def text(self, text, x, y, size):
        """One line of text, its baseline at y."""
        pen = SVGPathPen(self.glyphs, ntos=number)
        scale = size / self.em
        for i, char in enumerate(text):
            at = x + i * self.advance * scale
            self.glyph(char).draw(TransformPen(pen, (scale, 0, 0, -scale, at, y)))
        return pen.getCommands()

    def icon(self, char, cx, cy, size):
        """One glyph, its ink as large as a square size pixels across, centred on (cx, cy).

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
    alpha = f' fill-opacity="{opacity}"' if opacity is not None else ""
    return f'<path fill="{fill}"{alpha} d="{d}"/>'


def download(regular, bold, fill):
    """The button the README opens with."""
    h, radius, chip = 64, 10, 20
    cx = cy = h / 2
    x = cx + chip + 14
    title, note = "Download ISO", "Latest release"
    w = round(x + bold.width(title, 20) + 26)
    top = (h - 26 - 18) / 2
    return svg(w, h, "Download ISO", [
        '<defs><linearGradient id="fill" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{fill}"/>'
        f'<stop offset="1" stop-color="{mix(fill, "#000000", 0.2)}"/></linearGradient></defs>',
        f'<rect width="{w}" height="{h}" rx="{radius}" fill="url(#fill)"/>',
        f'<rect x=".5" y=".5" width="{w - 1}" height="{h - 1}" rx="{radius - .5}"'
        ' fill="none" stroke="#fff" stroke-opacity=".16"/>',
        f'<circle cx="{number(cx)}" cy="{number(cy)}" r="{chip}" fill="#fff" fill-opacity=".16"/>',
        path(regular.icon("\U000f0120", cx, cy, 20), "#fff"),  # nf-md-tray_arrow_down
        path(bold.text(title, x, bold.baseline(top, 20, 26), 20), "#fff"),
        path(regular.text(note, x, regular.baseline(top + 26, 13, 18), 13), "#fff", ".8"),
    ])


def tier(regular, bold, theme, lit, index):
    """One starting point and what it needs, its bars measured against the largest need."""
    name, icon, kind, needs = TIERS[index]
    w, side, top, gap = 380, 22, 16, 24
    text, muted = theme["text"], theme["muted"]
    first, second = bold.baseline(top, 20, 24), regular.baseline(top + 24, 14, 20)
    body = [
        path(regular.icon(icon, side + 14, (first - bold.cap * 20 / bold.em + second) / 2, 28), lit),
        path(bold.text(name, side + 44, first, 20), text),
        path(regular.text(kind, side + 44, second, 14), muted),
    ]
    y = top + 44 + 28
    column = (w - 2 * side - gap) / 2
    for row, (symbol, spec) in enumerate(SPECS):
        x = side + row * (column + gap)
        most = max(each[3][row] for each in TIERS)
        base = regular.baseline(y, 14, 20)
        body.append(path(regular.icon(symbol, x + 10, regular.middle(base, 14), 14), muted))
        body.append(path(regular.text(spec, x + 26, base, 14), muted))
        value = str(needs[row])
        base = bold.baseline(y + 20, 40, 48)
        body.append(path(bold.text(value, x, base, 40), text))
        body.append(path(regular.text("GiB", x + bold.width(value, 40) + regular.width(" ", 16), base, 16), muted))
        bar = y + 74
        body.append(f'<rect x="{number(x)}" y="{bar}" width="{number(column)}" height="4" rx="2"'
                    f' fill="{lit}" fill-opacity=".16"/>')
        body.append(f'<rect x="{number(x)}" y="{bar}" width="{number(column * needs[row] / most)}" height="4"'
                    f' rx="2" fill="{lit}"/>')
    return svg(w, y + 78 + top, alt(index), body)


def alt(index):
    name, _, kind, needs = TIERS[index]
    return f"{name} ({kind}): " + ", ".join(f"{n} GiB {spec.lower()}" for n, (_, spec) in zip(needs, SPECS))


def main():
    regular, bold = Face("Regular"), Face("Bold")
    lit = accent()
    (DOCS / "download.svg").write_text(download(regular, bold, lit))
    (DOCS / "requirements").mkdir(exist_ok=True)
    readme = DOCS / "README.md"
    page = readme.read_text()
    for index, (name, *_) in enumerate(TIERS):
        stem = name.lower()
        for mode, theme in THEMES.items():
            (DOCS / "requirements" / f"{stem}-{mode}.svg").write_text(tier(regular, bold, theme, lit, index))
        page, found = re.subn(rf'(<img src="requirements/{stem}-light\.svg"[^>]* alt=")[^"]*"',
                              lambda m: m.group(1) + alt(index) + '"', page)
        if found != 1:
            sys.exit(f'README.md: no <img src="requirements/{stem}-light.svg" ... alt="...">')
    readme.write_text(page)


if __name__ == "__main__":
    main()
