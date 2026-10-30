#!/usr/bin/env python3
"""Render docs/screenshots: every page of the interface, from the real program.

Runs the program on a pty with --dry-run, so it touches nothing, and follows
its --trace to know the page and the row under the cursor. The pages and the way
to each are in docs/screenshots.yaml. The footer's version is left out, so a
picture holds for every release.

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

# The card, one shape for every screenshot.
FONT_PX, LINE_PX = 15, 22
PAD, RADIUS, SCALE = 26, 10, 2
LEAD = (LINE_PX - FONT_PX) / 2  # room a line box keeps above and below the text

# The console's sixteen slots as the images set them, so a picture matches the
# console: iso/README.md#console.
def console_slots():
    build = (pathlib.Path(__file__).resolve().parent.parent / "iso/build.sh").read_text()
    channels = []
    for name in ("RED", "GRN", "BLU"):
        found = re.search(rf"^CONSOLE_{name}=([0-9,]+)$", build, re.M)
        if not found:
            sys.exit(f"iso/build.sh names no CONSOLE_{name}")
        channels.append([int(v) for v in found.group(1).split(",")])
    return ["#%02x%02x%02x" % rgb for rgb in zip(*channels)]


SLOTS = console_slots()
# The program writes a slot as 38;5;n, which pyte maps to xterm's color for n.
PALETTE = dict(zip(pyte.graphics.FG_BG_256[:16], SLOTS))
CARD, TEXT = SLOTS[0], SLOTS[7]

# The `monospace` fallback matters: without it, the small triangle marking the
# selected row renders big and filled.
FONT = '"FiraCode Nerd Font Mono", monospace'

# Cells a terminal fills rather than draws: a full block and its two halves.
# Painted as boxes, as a terminal does. A glyph sits in the font's box, shorter
# than its line, so two stacked leave a seam, which breaks a QR code.
PAINT = {
    "\u2588": "{ink}",
    "\u2580": "linear-gradient(to bottom, {ink} 50%, {field} 50%)",
    "\u2584": "linear-gradient(to bottom, {field} 50%, {ink} 50%)",
}

# Copied fresh, so an answer file or log from an earlier run cannot change a
# page.
PRODUCT = "arch-os"

# Short and neutral, since a failure page prints the log path into a published
# picture.
WORK = pathlib.Path("/tmp/product")

# Keys a step may press by name. Anything else is typed as is.
KEY = {
    "enter": b"\r",
    "esc": b"\x1b",
    "tab": b"\t",
    "up": b"\x1bOA",
    "down": b"\x1bOB",
    "right": b"\x1bOC",
    "left": b"\x1bOD",
}

STEP_KEYS = {"page", "shot", "frame", "choose", "press"}
FRAMES = ("settled", "running")

# Seconds a page may take. Generous, since simulated steps hold the next page
# for a minute. Still a bound, so a stray step fails.
WAIT = 180.0


class Session:
    """A program on a pty: press keys, keep every frame it drew with the page,
    the row and the count of tasks the trace named by then.

    Every read is kept, since some pages exist only for a moment.
    """

    def __init__(self, argv, cwd, trace, env=None):
        self.frames, self._buf = [], b""
        self.trace, self._read = trace, 0
        self.page = self.focus = None
        self.tasks = 0
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
            self.follow()
            self.frames.append((self._buf, self.page, self.tasks))
        return True

    def follow(self):
        """Reads the trace lines written since the last call."""
        try:
            with open(self.trace, "rb") as f:
                f.seek(self._read)
                new = f.read()
        except FileNotFoundError:
            return
        whole = new[:new.rfind(b"\n") + 1]
        self._read += len(whole)
        for line in whole.decode().splitlines():
            kind, _, value = line.partition(" ")
            if kind == "page":
                self.page = value
            elif kind == "focus":
                self.focus = value
            elif kind == "task":
                self.tasks += 1

    def press(self, keys, settle=0.25):
        for key in keys:
            os.write(self.fd, KEY.get(key, key.encode()))
            self.pump(settle)
        return self

    def choose(self, row, tries=40):
        """Put the cursor on a row by id, not by position, since rows get
        added. Up first, as far as it goes, then down."""
        for key in ("up", "down"):
            last = None
            for _ in range(tries):
                self.follow()
                if self.focus == row:
                    return self
                if self.focus == last:
                    break
                last = self.focus
                self.press([key])
        raise SystemExit(f"no row {row!r} to put the cursor on")

    def until(self, page, timeout=WAIT):
        """Wait for a page, not for a length of time."""
        end = time.time() + timeout
        while time.time() < end:
            self.follow()
            if self.page == page:
                return self
            if not self.pump(0.15):
                break
        raise SystemExit(
            f"waited {timeout:g}s for page {page!r}, and the trace was on "
            f"{self.page!r}:\n\n" + text(self._buf))

    def still(self, checks=3, step=0.12, timeout=8.0):
        """Wait until the screen stops changing: the wordmark sweeps in."""
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


def unversioned(screen, version):
    """The screen with the version blanked in its lowest line that shows it,
    the footer's, where it would date the picture."""
    for y in reversed(range(screen.lines)):
        row = screen.buffer[y]
        cells = [row[x].data for x in range(screen.columns)]
        for x in reversed(range(screen.columns - len(version) + 1)):
            if "".join(cells[x:x + len(version)]) == version:
                for i in range(len(version)):
                    row[x + i] = row[x + i]._replace(data=" ")
                return screen
    return screen


def text(stream):
    return "\n".join(grid(stream).display)


def filled(seen):
    """Lines with text. Rules and borders carry none, so this measures the
    page, not its frame."""
    return sum(1 for line in seen.split("\n") if any(c.isalnum() for c in line))


def running(frames, page, total):
    """The frame from the middle of the run that led to the page on screen.

    Which frames a run produces is a race, so this takes the one nearest the
    middle of its `total` tasks, not a fixed count. It stops at the wanted page,
    since a run paused to ask or report is past the moment worth a picture.
    """
    caught = []
    for frame, at, tasks in frames:
        if at == page:
            break
        if at == "run" and 0 < tasks < total:
            caught.append((filled(text(frame)), tasks / total, frame))
    if not caught:
        raise SystemExit(f"no frame caught the run on its way to {page!r}")

    # Between redraws the list is briefly gone. A run page keeps one size, so
    # the most common size is the whole page and a rarer one is such a gap.
    whole = Counter(rows for rows, _, _ in caught).most_common(1)[0][0]
    return min((got for got in caught if got[0] == whole),
               key=lambda got: abs(got[1] - 0.5))[2]


def color(value, fallback):
    if value in (None, "default"):
        return fallback
    if value in PALETTE:
        return PALETTE[value]
    if len(value) == 6 and all(c in "0123456789abcdefABCDEF" for c in value):
        return f"#{value}"
    sys.exit(f"no color for {value!r}")


def painted(char, bg):
    """How a cell is filled rather than lettered, or None.

    An empty cell with a background counts: it is the quiet zone a code is read
    against and must reach the edges of its line like the ink beside it.
    """
    if char in PAINT:
        return PAINT[char]
    if char in (" ", "") and bg:
        return "{field}"
    return None


def markup(screen):
    """One span per run of same-looking cells, not per character."""
    rows = []
    for y in range(screen.lines):
        line, run, style = [], "", None
        for x in range(screen.columns):
            c = screen.buffer[y][x]
            fg, bg = color(c.fg, TEXT), color(c.bg, None)
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
    """One run of cells, as text or as a filled box.

    Every run is a box exactly one line tall, so painted areas meet without a
    seam between the words of a highlighted row or the rows of a code.
    """
    fg, bg, bold, fill = style
    box = f"display:inline-block;vertical-align:top;height:{LINE_PX}px;"
    if fill:
        return '<span style="{}background:{}">{}</span>'.format(
            box, fill.format(ink=fg, field=bg or CARD), " " * len(text))
    return '<span style="{}color:{};{}{}">{}</span>'.format(
        box, fg, f"background:{bg};" if bg else "",
        "font-weight:700;" if bold else "", html.escape(text))


def card(stream, out, version):
    """The screen on a rounded card with the same gap on all four sides.

    The card sizes to its content and the picture is trimmed to the card, so
    the gap is the padding and no glyph width is needed.
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
</style></head><body><div class="card"><pre>{markup(unversioned(grid(stream), version))}</pre></div></body></html>""")
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
    """A line of text or a list of them, as a list."""
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list) or not value or not all(
            isinstance(one, str) and one for one in value):
        raise SystemExit(f"{where}: {what} is a line of text, or a list of them")
    return value


def storyboard(path):
    """The takes, checked before the first start, with single values as lists.

    An unknown key would be a step that silently does nothing.
    """
    takes = yaml.safe_load(path.read_text())
    if not isinstance(takes, list) or not takes:
        raise SystemExit(f"{path}: expected a list of takes, each with steps:")

    shots = []
    for t, take in enumerate(takes, 1):
        where = f"{path}: take {t}"
        if not isinstance(take, dict) or set(take) != {"module", "steps"}:
            raise SystemExit(f"{where}: a take is module: and steps:")
        if not isinstance(take.get("steps"), list) or not take["steps"]:
            raise SystemExit(f"{where}: steps: is a list of pages")
        for s, step in enumerate(take["steps"], 1):
            at = f"{where}, step {s}"
            if not isinstance(step, dict) or set(step) - STEP_KEYS:
                raise SystemExit(f"{at}: a step is {', '.join(sorted(STEP_KEYS))}")
            if "page" not in step:
                raise SystemExit(f"{at}: page: says which page this step is about")
            if not isinstance(step["page"], str) or not step["page"]:
                raise SystemExit(f"{at}: page: is the id of one page")
            step["press"] = lines(step["press"], at, "press:") if "press" in step else []
            if "choose" in step and len(lines(step["choose"], at, "choose:")) != 1:
                raise SystemExit(f"{at}: choose: is the one row to put the cursor on")
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
    """A fresh copy of the program in WORK."""
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    if not source.is_file():
        raise SystemExit(f"{source}: no program. Run make build.")
    shutil.copy(source, WORK / PRODUCT)
    (WORK / PRODUCT).chmod(0o755)


def play(takes, source, out):
    version = subprocess.run([source, "--version"], check=True, capture_output=True,
                             text=True).stdout.split()[1]
    for take in takes:
        pristine(source)
        argv = [f"./{PRODUCT}", take["module"], "--dry-run", "--trace", "trace"]
        # C.UTF-8, not the host's locale: the language of a published picture is
        # chosen, not leaked.
        session = Session(argv, str(WORK), WORK / "trace",
                          env={"LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"})
        # Start of the frames leading to the awaited page. A question page
        # carries a counter too, so the run search must not reach past the
        # previous page.
        since = 0
        try:
            for step in take["steps"]:
                # Settled before a shot or a key: a page still fading in is a
                # shade off and swallows keys.
                session.until(step["page"]).still()
                if "shot" in step:
                    frame = (running(session.frames[since:], step["page"],
                                     session.tasks)
                             if step.get("frame") == "running"
                             else session.screen())
                    card(frame, out / f"{step['shot']}.png", version)
                    print(f"  {step['shot']}", flush=True)
                since = len(session.frames)
                if "choose" in step:
                    session.choose(step["choose"])
                session.press(step["press"])
        finally:
            session.close()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--product", type=pathlib.Path, required=True,
                   help="the built program, runtime/target/release/arch-os")
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
