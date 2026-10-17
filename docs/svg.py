#!/usr/bin/env python3
"""Render the README's pictures: docs/download.svg and docs/requirements.svg.

Text is set as outlines of the banner's font, since GitHub lets an SVG shown as
an image load no font, and the viewer's own would differ on every machine. The
requirements lie on the banner's field, in its colours out of banner.py, so they
read on either GitHub theme. The accent is the one in oak.yaml. Their text
alternative is written into README.md from the same run.

Needs: python-fonttools, ttf-firacode-nerd.
"""

import ast
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
PHI = (1 + 5 ** .5) / 2

PROCESSOR = ("\uf4bc", "Processor", "x86_64 with UEFI")  # nf-oct-cpu
SPECS = (("\uefc5", "Memory"), ("\uf0a0", "Disk"))  # nf-fa-memory, nf-fa-hdd_o
# Name, icon, what it is, and what it needs of each spec in GiB.
TIERS = (
    ("Core", "\uf489", "Text console", (2, 16)),  # nf-oct-terminal
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

    def centred(self, text, cx, y, size):
        return self.text(text, cx - self.width(text, size) / 2, y, size)

    def ink(self, char, size):
        """An icon's ink box, and the scale that makes it as large as a square size pixels across.

        Measured by its ink, since the font squeezes every icon into one cell,
        and by area, so a wide one weighs as much as a square one.
        """
        bounds = BoundsPen(self.glyphs)
        self.glyph(char).draw(bounds)
        x0, y0, x1, y1 = bounds.bounds
        scale = size / ((x1 - x0) * (y1 - y0)) ** .5
        return (x0, y0, x1, y1), scale

    def icon(self, char, cx, cy, size):
        """One icon, its ink centred on (cx, cy)."""
        (x0, y0, x1, y1), scale = self.ink(char, size)
        pen = SVGPathPen(self.glyphs, ntos=number)
        self.glyph(char).draw(TransformPen(pen, (scale, 0, 0, -scale,
                                                 cx - (x0 + x1) / 2 * scale, cy + (y0 + y1) / 2 * scale)))
        return pen.getCommands()

    def wide(self, char, size):
        (x0, _, x1, _), scale = self.ink(char, size)
        return (x1 - x0) * scale


def accent():
    for line in (DOCS.parent / "oak.yaml").read_text().split("\n"):
        if line.startswith("accent:"):
            return line.split(":", 1)[1].strip().strip('"')
    sys.exit("oak.yaml: no accent:")


def constants(file):
    """The plain values a script assigns at its top."""
    found = {}
    for node in ast.parse(file.read_text()).body:
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant):
            found.update((t.id, node.value.value) for t in node.targets if isinstance(t, ast.Name))
    return found


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


def rect(x, y, w, h, fill, opacity=None, rx=None):
    alpha = f' fill-opacity="{number(opacity)}"' if opacity is not None else ""
    corner = f' rx="{number(rx)}"' if rx is not None else ""
    return (f'<rect x="{number(x)}" y="{number(y)}" width="{number(w)}" height="{number(h)}"'
            f'{corner} fill="{fill}"{alpha}/>')


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
        path(regular.text(note, x, regular.baseline(top + 26, 13, 18), 13), "#fff", .8),
    ])


def requirements(regular, bold, lit):
    """Both starting points side by side, mirrored on the middle, each centred on its own axis.

    Sizes and gaps are Fibonacci numbers, and the field is phi squared as wide
    as it is high.
    """
    field = constants(DOCS / "banner.py")
    back, text = field["BACK"], field["TEXT"]
    muted, radius, bar = 1 / PHI, 13, 89

    # Top to bottom, the same for both.
    y = 34
    mark = y + 17
    y += 34 + 13
    name = bold.baseline(y, 21, 26)
    y += 26
    kind = regular.baseline(y, 13, 21)
    y += 21 + 13
    rule = y
    y += 2 + 21
    label = regular.baseline(y, 13, 21)
    y += 21
    value = bold.baseline(y, 34, 42)
    y += 42 + 8
    track = y
    y += 3 + 21
    foot = regular.baseline(y, 13, 21)
    h = round(y + 21 + 34)
    w = round(h * PHI ** 2)
    axes = [w * (1 + 2 * i) / (2 * len(TIERS)) for i in range(len(TIERS))]

    # The banner's field: a faint grid, a glow behind each, a vignette, a ring.
    grid = (f'<pattern id="grid" width="16" height="16" patternUnits="userSpaceOnUse"'
            f' x="{number(w / 2 % 16)}" y="{number(h / 2 % 16)}">'
            f'{rect(0, 0, 16, 1, text, .03)}{rect(0, 0, 1, 16, text, .03)}</pattern>')
    glows = "".join(
        f'<radialGradient id="glow{i}" gradientUnits="userSpaceOnUse" cx="{number(x)}" cy="{number(mark)}"'
        f' r="{number(w / 3)}"><stop offset="0" stop-color="{lit}" stop-opacity=".14"/>'
        f'<stop offset="1" stop-color="{lit}" stop-opacity="0"/></radialGradient>' for i, x in enumerate(axes))
    body = [
        f'<defs>{grid}{glows}'
        '<radialGradient id="fade" r=".9"><stop offset=".3" stop-color="#fff"/>'
        '<stop offset=".78" stop-color="#000"/></radialGradient>'
        f'<mask id="fade-grid">{rect(0, 0, w, h, "url(#fade)")}</mask>'
        '<radialGradient id="vignette" r=".78"><stop offset=".42" stop-opacity="0"/>'
        '<stop offset="1" stop-opacity=".42"/></radialGradient>'
        f'<clipPath id="card">{rect(0, 0, w, h, "#000", rx=radius)}</clipPath></defs>',
        '<g clip-path="url(#card)">',
        rect(0, 0, w, h, back),
        f'<rect width="{w}" height="{h}" fill="url(#grid)" mask="url(#fade-grid)"/>',
        *(rect(0, 0, w, h, f"url(#glow{i})") for i in range(len(TIERS))),
        rect(0, 0, w, h, "url(#vignette)"),
        "</g>",
        f'<rect x=".5" y=".5" width="{w - 1}" height="{h - 1}" rx="{radius - .5}" fill="none"'
        f' stroke="{lit}" stroke-opacity=".18"/>',
        rect(w / 2 - .5, 34, 1, track + 3 - 34, text, .08),
    ]

    for cx, (tier, icon, what, needs) in zip(axes, TIERS):
        body += [
            path(regular.icon(icon, cx, mark, 34), lit),
            path(bold.centred(tier, cx, name, 21), text),
            path(regular.centred(what, cx, kind, 13), text, muted),
            rect(cx - 17, rule, 34, 2, lit),
        ]
        for row, ((symbol, spec), need) in enumerate(zip(SPECS, needs)):
            # The two specs mirrored on the axis, a bar and a gap of 34 apart.
            x = cx + (row - (len(SPECS) - 1) / 2) * (bar + 34)
            most = max(each[3][row] for each in TIERS)
            mark_w = regular.wide(symbol, 13)
            start = x - (mark_w + 8 + regular.width(spec, 13)) / 2
            body.append(path(regular.icon(symbol, start + mark_w / 2, regular.middle(label, 13), 13), text, muted))
            body.append(path(regular.text(spec, start + mark_w + 8, label, 13), text, muted))
            amount = str(need)
            start = x - (bold.width(amount, 34) + regular.width(" GiB", 13)) / 2
            body.append(path(bold.text(amount, start, value, 34), text))
            body.append(path(regular.text(" GiB", start + bold.width(amount, 34), value, 13), text, muted))
            body.append(rect(x - bar / 2, track, bar, 3, lit, .2, 1.5))
            body.append(rect(x - bar / 2, track, bar * need / most, 3, lit, rx=1.5))

    symbol, spec, kind = PROCESSOR
    mark_w = regular.wide(symbol, 13)
    start = w / 2 - (mark_w + 8 + regular.width(f"{spec}  {kind}", 13)) / 2
    body += [
        path(regular.icon(symbol, start + mark_w / 2, regular.middle(foot, 13), 13), text, muted),
        path(regular.text(spec, start + mark_w + 8, foot, 13), text, muted),
        path(regular.text(kind, start + mark_w + 8 + regular.width(f"{spec}  ", 13), foot, 13), text),
    ]
    return svg(w, h, alt(), body)


def alt():
    tiers = [f"{name} ({what}): " + ", ".join(f"{n} GiB {spec.lower()}" for n, (_, spec) in zip(needs, SPECS))
             for name, _, what, needs in TIERS]
    _, spec, kind = PROCESSOR
    return ". ".join(tiers + [f"{spec} for both: {kind}"])


def main():
    regular, bold = Face("Regular"), Face("Bold")
    lit = accent()
    (DOCS / "download.svg").write_text(download(regular, bold, lit))
    (DOCS / "requirements.svg").write_text(requirements(regular, bold, lit))
    readme = DOCS / "README.md"
    page, found = re.subn(r'(<img src="requirements\.svg"[^>]* alt=")[^"]*"',
                          lambda m: m.group(1) + alt() + '"', readme.read_text())
    if found != 1:
        sys.exit('README.md: no <img src="requirements.svg" ... alt="...">')
    readme.write_text(page)


if __name__ == "__main__":
    main()
