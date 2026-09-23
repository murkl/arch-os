#!/usr/bin/env python3
"""Render docs/screenshots: every page of the interface, out of the product.

The real binary on a real pty, started with --debug so it touches nothing. Which
pages, and the way to each, is docs/screenshots.yaml. This file is the same in
every project that uses it.

Needs: chromium, imagemagick, python-pyte, python-yaml.
"""

import argparse
import fcntl
import html
import os
import pathlib
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import termios
import time
from collections import Counter

try:
    import pyte
except ModuleNotFoundError:
    sys.exit("needs python-pyte: sudo pacman -S python-pyte")

try:
    import yaml
except ModuleNotFoundError:
    sys.exit("needs python-yaml: sudo pacman -S python-yaml")

COLS, ROWS = 95, 25

# The card, one shape for every screenshot everywhere this is used.
FONT_PX, LINE_PX = 15, 22
PAD, RADIUS, SCALE = 26, 10, 2
LEAD = (LINE_PX - FONT_PX) / 2  # room a line box keeps above and below the text
CARD, TEXT = "#2e3440", "#d8dee9"

# The `monospace` fallback is load bearing. Without it the small triangle the
# interface marks a selected row with comes out as a big filled one.
FONT = '"FiraCode Nerd Font Mono", monospace'

# The cells a terminal fills rather than draws, and how each is painted: a whole
# cell of ink, its two halves, and a cell of nothing but its background.
#
# Painted as boxes here for the same reason a terminal paints them. A glyph is
# drawn inside the font's own box, which is shorter than the line it sits on, so
# two of them stacked leave a seam of card between them - visible in a tick and
# fatal in a QR code, which is not a picture of anything and reads as nothing
# once it has stripes through it.
PAINT = {
    "\u2588": "{ink}",
    "\u2580": "linear-gradient(to bottom, {ink} 50%, {field} 50%)",
    "\u2584": "linear-gradient(to bottom, {field} 50%, {ink} 50%)",
}

# A product, as Oak reads it. Copied part by part, so an answer file or a log an
# earlier run left beside them cannot decide what a page says. The shell the
# modules share is a part only some products have.
PRODUCT = ("oak", "oak.yaml", "modules")
OPTIONAL = ("oak.sh",)

# Where the copy is driven. A failure page prints the log's path, so this ends up
# inside a published picture: short and neutral for that reason alone.
WORK = pathlib.Path("/tmp/product")

# What a step may press by name; anything else is typed as it stands.
KEY = {
    "enter": b"\r",
    "esc": b"\x1b",
    "tab": b"\t",
    "up": b"\x1bOA",
    "down": b"\x1bOB",
    "right": b"\x1bOC",
    "left": b"\x1bOD",
}

STEP_KEYS = {"page", "shot", "frame", "press"}
FRAMES = ("settled", "running")

# How long a page is given to arrive. Generous - a run of simulated steps holds
# the page after them for a minute - but an upper bound, so a stray step says so.
WAIT = 180.0


class Session:
    """A program on a pty: press keys, keep every frame it drew.

    Every read is kept, because some pages only exist for a moment.
    """

    def __init__(self, argv, cwd, env=None):
        self.frames, self._buf = [], b""
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(cwd)
            os.execvpe(argv[0], argv, dict(
                os.environ, TERM="xterm-256color", COLORTERM="truecolor",
                LINES=str(ROWS), COLUMNS=str(COLS), **(env or {})))
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ,
                    struct.pack("HHHH", ROWS, COLS, 0, 0))

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            if not select.select([self.fd], [], [], max(0, end - time.time()))[0]:
                continue
            try:
                chunk = os.read(self.fd, 65536)
            except OSError:
                return False
            if not chunk:
                return False
            if b"\x1b[6n" in chunk:
                os.write(self.fd, b"\x1b[1;1R")  # answer as a real terminal does
            self._buf += chunk
            self.frames.append(self._buf)
        return True

    def press(self, keys, settle=0.25):
        for key in keys:
            os.write(self.fd, KEY.get(key, key.encode()))
            self.pump(settle)
        return self

    def until(self, wants, timeout=WAIT):
        """Wait for a page, not for a length of time."""
        end = time.time() + timeout
        while time.time() < end:
            if all(want in text(self._buf) for want in wants):
                return self
            if not self.pump(0.15):
                break
        raise SystemExit(
            f"waited {timeout:g}s for {wants!r}, and the page was:\n\n"
            + text(self._buf))

    def still(self, checks=3, step=0.12, timeout=8.0):
        """Wait until the screen stops changing: the interface fades in."""
        last, same, end = None, 0, time.time() + timeout
        while time.time() < end:
            now = markup(grid(self._buf))
            same = same + 1 if now == last else 0
            last = now
            if same >= checks:
                return self
            self.pump(step)
        return self

    def screen(self):
        return self._buf

    def close(self):
        try:
            os.close(self.fd)
            os.kill(self.pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except ChildProcessError:
            pass


def grid(stream):
    screen = pyte.Screen(COLS, ROWS)
    pyte.Stream(screen).feed(stream.decode("utf-8", "replace"))
    return screen


def text(stream):
    return "\n".join(grid(stream).display)


def filled(seen):
    """How many lines carry text - a rule or a border carries none, so this
    measures the page rather than the frame around it."""
    return sum(1 for line in seen.split("\n") if any(c.isalnum() for c in line))


# The counter a run page carries. The lookahead keeps it off a report, where the
# same two numbers say how many tests passed.
COUNTER = re.compile(r"(\d+) of (\d+)(?! tests)")


def running(frames, wants):
    """The frame from the middle of a run on its way to the page now on screen.

    Which frames a run lands on is a race, so this asks for the one nearest the
    middle rather than a particular count. It stops where the wanted page
    arrives: a run paused to ask or report is past the point worth a picture.
    """
    caught = []
    for frame in frames:
        seen = text(frame)
        if all(want in seen for want in wants):
            break
        at = COUNTER.search(seen)
        if not at:
            continue
        done, total = int(at.group(1)), int(at.group(2))
        if done < total:
            caught.append((filled(seen), done / total, frame))
    if not caught:
        raise SystemExit(f"no frame caught the run on its way to {wants!r}")

    # Between two redraws the list is briefly gone, leaving a frame nobody saw.
    # A run page keeps one size throughout, so the size that comes up most is the
    # whole one and a rarer size is such a gap.
    whole = Counter(rows for rows, _, _ in caught).most_common(1)[0][0]
    return min((got for got in caught if got[0] == whole),
               key=lambda got: abs(got[1] - 0.5))[2]


def colour(value, fallback):
    if value in (None, "default"):
        return fallback
    ok = len(value) == 6 and all(c in "0123456789abcdefABCDEF" for c in value)
    return f"#{value}" if ok else value


def painted(char, bg):
    """How a cell is filled rather than lettered, or None where it is neither.

    A cell of background with nothing in it counts: it is the quiet field a
    code is read against, and it has to reach the edges of its line like the
    ink beside it does.
    """
    if char in PAINT:
        return PAINT[char]
    if char in (" ", "") and bg:
        return "{field}"
    return None


def markup(screen):
    """One span a run of same-looking cells, not one a character."""
    rows = []
    for y in range(screen.lines):
        line, run, style = [], "", None
        for x in range(screen.columns):
            c = screen.buffer[y][x]
            fg, bg = colour(c.fg, TEXT), colour(c.bg, None)
            if c.reverse:
                fg, bg = bg or CARD, fg
            now = (fg, bg, c.bold, painted(c.data, bg))
            if now != style and run:
                line.append((style, run))
                run = ""
            style, run = now, run + (c.data or " ")
        if run:
            line.append((style, run))
        rows.append("".join(cell(style, text) for style, text in line))
    return "\n".join(rows)


def cell(style, text):
    """One run of cells, as writing or as a filled box."""
    fg, bg, bold, fill = style
    if fill:
        # Its own box, exactly one line tall, so what is painted meets what is
        # painted on the line above it.
        return ('<span style="display:inline-block;vertical-align:top;'
                'height:{}px;background:{}">{}</span>').format(
                    LINE_PX, fill.format(ink=fg, field=bg or CARD), " " * len(text))
    return '<span style="color:{};{}{}">{}</span>'.format(
        fg, f"background:{bg};" if bg else "",
        "font-weight:700" if bold else "", html.escape(text))


def card(stream, out):
    """The screen on a rounded card, with the same gap on all four sides.

    The card is sized by what is in it and the picture trimmed back to the card,
    so the gap is the padding and nothing here has to know how wide a glyph is.
    """
    page = out.with_suffix(".html")
    page.write_text(f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  * {{ margin:0; padding:0; }}
  body {{ background:transparent; }}
  .card {{
    display:inline-block; padding:{PAD - LEAD}px {PAD}px;
    background:{CARD}; border-radius:{RADIUS}px;
  }}
  pre {{
    font-family:{FONT}; font-size:{FONT_PX}px; line-height:{LINE_PX}px;
    color:{TEXT}; white-space:pre; font-variant-ligatures:none;
  }}
</style></head><body><div class="card"><pre>{markup(grid(stream))}</pre></div></body></html>""")
    # No monospace glyph is wider than its font size, so the card always fits.
    w = COLS * FONT_PX + 4 * PAD
    h = ROWS * LINE_PX + 4 * PAD
    try:
        subprocess.run([
            "chromium", "--headless", f"--force-device-scale-factor={SCALE}",
            "--default-background-color=00000000", "--hide-scrollbars",
            f"--window-size={w},{h}", f"--screenshot={out}", page.as_uri(),
        ], check=True, capture_output=True)
    finally:
        page.unlink(missing_ok=True)
    subprocess.run(["magick", str(out), "-trim", "+repage", "-strip",
                    "-define", "png:compression-level=9", str(out)], check=True)


# --- the project's pages -------------------------------------------------


def lines(value, where, what):
    """One line of text or several, read as several."""
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list) or not value or not all(
            isinstance(one, str) and one for one in value):
        raise SystemExit(f"{where}: {what} is a line of text, or a list of them")
    return value


def storyboard(path):
    """The takes, checked before the first program is started and handed back
    with every single value already read as a list.

    A key nobody reads is a step that quietly does nothing, and the only sign of
    it would be a picture that never changed.
    """
    takes = yaml.safe_load(path.read_text())
    if not isinstance(takes, list) or not takes:
        raise SystemExit(f"{path}: expected a list of takes, each with steps:")

    shots = []
    for t, take in enumerate(takes, 1):
        where = f"{path}: take {t}"
        if not isinstance(take, dict) or set(take) - {"module", "steps"}:
            raise SystemExit(f"{where}: a take is module: (optional) and steps:")
        if not isinstance(take.get("steps"), list) or not take["steps"]:
            raise SystemExit(f"{where}: steps: is a list of pages")
        for s, step in enumerate(take["steps"], 1):
            at = f"{where}, step {s}"
            if not isinstance(step, dict) or set(step) - STEP_KEYS:
                raise SystemExit(f"{at}: a step is {', '.join(sorted(STEP_KEYS))}")
            if "page" not in step:
                raise SystemExit(f"{at}: page: says which page this step is about")
            step["page"] = lines(step["page"], at, "page:")
            step["press"] = lines(step["press"], at, "press:") if "press" in step else []
            if step.get("frame", FRAMES[0]) not in FRAMES:
                raise SystemExit(f"{at}: frame: is one of {', '.join(FRAMES)}")
            if "frame" in step and "shot" not in step:
                raise SystemExit(f"{at}: frame: picks the frame a shot keeps, "
                                 "and this step takes none")
            if "shot" in step:
                shots += lines(step["shot"], at, "shot:")

    if not shots:
        raise SystemExit(f"{path}: not one step takes a shot")
    twice = sorted({name for name in shots if shots.count(name) > 1})
    if twice:
        raise SystemExit(f"{path}: written twice: {', '.join(twice)}")
    return takes


def pristine(source):
    """A copy of the product, in the folder every take is driven in."""
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    for part in PRODUCT + OPTIONAL:
        origin = source / part
        if not origin.exists():
            if part in OPTIONAL:
                continue
            raise SystemExit(f"{source}: no {part} - is this a built product?")
        if origin.is_dir():
            shutil.copytree(origin, WORK / part)
        else:
            shutil.copy(origin, WORK / part)
    (WORK / PRODUCT[0]).chmod(0o755)


def play(takes, source, out):
    for take in takes:
        pristine(source)
        module = take.get("module")
        argv = ["./oak", "--debug"] + ([f"--module={module}"] if module else [])
        # C.UTF-8 rather than whatever this desk is set to: the language on a
        # published picture is a decision, not a leak.
        session = Session(argv, str(WORK), env={"LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"})
        # Where the frames on the way to the page being waited for begin. A
        # question page carries a counter too, so the search for a run must not
        # reach back past the page before it.
        since = 0
        try:
            for step in take["steps"]:
                # Settled before it is photographed or typed into: a page still
                # fading in is a shade off, and it swallows a key outright.
                session.until(step["page"]).still()
                if "shot" in step:
                    frame = (running(session.frames[since:], step["page"])
                             if step.get("frame") == "running"
                             else session.screen())
                    card(frame, out / f"{step['shot']}.png")
                    print(f"  {step['shot']}", flush=True)
                since = len(session.frames)
                session.press(step["press"])
        finally:
            session.close()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--product", type=pathlib.Path, required=True,
                   help="a built product: the oak binary, its oak.yaml, modules/")
    p.add_argument("--pages", type=pathlib.Path,
                   default=pathlib.Path("docs/screenshots.yaml"))
    p.add_argument("--out", type=pathlib.Path,
                   default=pathlib.Path("docs/screenshots"))
    args = p.parse_args()

    takes = storyboard(args.pages)
    source = args.product.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)

    print(f"-> {out}", flush=True)
    try:
        play(takes, source, out)
    finally:
        shutil.rmtree(WORK, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
