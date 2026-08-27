# installer — a runtime for an installer that lives beside it

A single Go binary that draws an interface, asks questions, keeps the answers
and runs shell in order, reporting exactly where it broke.

It installs nothing. It knows nothing about Arch Linux, disks, packages,
bootloaders or desktops — there is not one of those words anywhere in the source.
What is asked, what the answers mean and what the shell does is an
**installer.yaml and a folder of tasks** beside it. Started without one, the
binary says so and stops.

That split is the whole design. Every system-specific thing there is lives in the
tree, so the same binary drives an installer for anything, and the tree can be
maintained, versioned and translated entirely on its own.

```
installer                     # runs the installer.yaml beside the binary
installer -check              # loads it, reports what it holds, changes nothing
installer -strings            # prints an empty translation catalog for it
installer -dir /path/to/tree  # runs that one instead (for development and CI)
installer -version
```

## The tree

One file that says what the installer is, and one folder holding the work.

```
installer.yaml           the whole declaration: what it is, what it asks, what order it works in
tasks/<id>/task.yaml     where that unit belongs
tasks/<id>/task.sh       what it does
tasks/_lib/              anything several units share — a folder named _* is not a unit
```

The binary looks for `installer.yaml` **next to itself** and nowhere else, so a
release is one folder holding the program and everything it runs.

### `installer.yaml`

```yaml
title: Arch OS Installer
accent: "#1793d1"        # the one colour the interface is built from
logo: |                  # everything above the blank line is a dim eyebrow
  Arch Linux

  ██████ …               # the wordmark, swept in behind the accent

lib: ./tasks/_lib/lib.sh      # sourced before every script of this tree
locales: ./tasks/_lib/locales # one <code>.yaml per language it speaks
language: ARCH_OS_LOCALE_LANG # optional: an answer that also settles the words on screen
preflight: preflight          # runs before all but the `first` questions

stages: [prepare, disk, base, finish]   # the order the installation happens in

confirm: |               # the last thing read before anything changes
  Arch Linux will be installed on {{ARCH_OS_DISK}}.

presets:                 # pages of starting points, offered on a machine with no answers
  - id: system
    title: Setup                    # the page's own name and sentence
    description: What kind of system to install.
    options:
      - id: desktop
        title: Desktop
        description: A full GNOME desktop.
        values:
          ARCH_OS_DESKTOP_ENABLED: true

variables:
  - name: ARCH_OS_USERNAME     # reaches every script as an environment variable
    title: User name           # what the row and the question are called
    description: |             # shown on the page that asks it
      The account you will log in with.
    group: Identity            # the heading its run of rows sits under
    required: true             # required and unanswered is what makes it ask
    pattern: '^[a-z_][a-z0-9_-]*$'
    error: Lower case letters, digits, - and _ only.
```

`preflight` names a task that belongs to no stage. It runs once at startup
and is a wall: what it writes to stderr is what the user reads, and the only
thing left to do is leave. `confirm` is filled in from the answers, so it names
the disk it is about rather than warning in the abstract.

`leave:` is what makes leaving the interface a question rather than an exit:

```yaml
leave:
  restart: systemctl reboot
  shutdown: systemctl poweroff
  console: Type installer to start it again.   # optional
```

A tree that declares it is saying the machine booted to run this installer, so
every way out of the interface — ctrl+c, the row that says quit, backing off the
first page, the end of an installation — lands on a page offering these instead
of closing. A tree that declares none leaves the program exiting the way
anything does, which is right for an installer somebody started from a shell
they are still sitting in.

The first two are shell like any other field here, so a tree that simulates its
work simulates these too, and an installer being tried out on somebody's own
machine closes rather than switching it off.

**`console:`** is the way out that runs nothing: the program stops and the
machine keeps running. Declare it where there is something behind the interface
to stop into — a login shell on a live image, the terminal it was started from —
and leave it out where there is not. Its value is the sentence saying how to
start the installer again, which is printed on the terminal once the frame is
gone: what the installer is called out there is something only the tree knows,
and somebody who has just left it is looking at a bare prompt.

### `task.yaml`

```yaml
name: Install the graphics driver    # the line somebody reads while they wait
stage: desktop                       # one of the stages, which is what puts it in the run
needs: [desktop]                     # ordered after these, inside the same stage
conditions:                          # every one has to hold, or it is not in the run at all
  - ARCH_OS_DESKTOP_ENABLED == true
  - ARCH_OS_DESKTOP_GRAPHICS_DRIVER != none
```

Three more keys change what a unit *is* rather than what it does:

| | |
|---|---|
| `confirm:` | asked as a yes or no in the frame before it runs; declining skips it |
| `quits: true` | the program does not come back from this one — a reboot |
| `tty: true` | the interface stands aside and the script has the terminal, whole |

Nothing lists the tasks: the folder is the list, and the order comes out of
the stages and the needs. A unit added is a step added, and the two can never
disagree. A cycle, an unknown stage, a need pointing at nothing — each is a
message at startup rather than an installation that stops halfway.

### The shape of a question

Decided by the declaration rather than by a switch:

| declaration | what is drawn |
|---|---|
| nothing further | a text box |
| `values: [btrfs, ext4]` | a list |
| `command: timedatectl list-timezones` | a list, from what the command printed |
| `type: bool` | Yes / No, in the interface's language |
| `type: secret` | a password field, asked twice, never written down |

Further fields: `default` (any scalar — `true`, `8`, `pc105`), `prefill` (shell
printing a suggestion), `apply` (shell run when the answer takes effect), `first`
(asked before everything else), `free` (a row under a list that opens a text
box), and `conditions`.

`true` and `false` are read out loud as Yes and No wherever they turn up, not
only under `type: bool` — so `values: [auto, true, false]` is a bool with a
third answer beside it and still reads as one.

A **secret** is the one required value that does not stop the program from being
ready. It is never written to the answer file, so it would be missing at every
start; instead it is asked for immediately before the run that needs it, used,
and forgotten.

**`apply`** is for the answer that changes the machine the installer is running
on rather than the one being installed — the console keyboard, which is unusable
as a stored string:

```yaml
apply: loadkeys "$ARCH_OS_VCONSOLE_KEYMAP"
```

It runs the moment the answer is given, and once at startup for an answer this
run began with, so a restart stands where the last one left off. A failure is a
warning in the log: the answer stands either way.

**`first: true`** puts a question before everything else the program does — before
the network screen, before the preflight, before the presets. It is what makes
the keyboard the passphrase is typed on a settled thing rather than a guess, and
it is a promise to make sparingly: every question here is one asked before the
check that says this machine cannot be installed onto at all.

An options command may hand back a value and the text it is chosen by, separated
by a **tab** — everything before the tab is stored, everything after it is read:

```sh
lsblk -dn -o PATH,SIZE,MODEL | awk '{printf "%s\t%s  %s %s\n", $1, $1, $2, $3}'
# /dev/nvme0n1<TAB>/dev/nvme0n1  1.8T WD Black
```

An empty value in front of the tab is a real answer — "no variant", "the
default" — not a blank line.

### `conditions`

One condition, or a list of them where every one has to hold:

```
VAR == value
VAR != value
```

Deliberately not an expression language. Three tokens cover every guard an
installer needs, they read as a sentence, and they are checked against the
declared variables when the tree is opened — so a renamed variable is a message
at startup, never a task that silently never runs. There is no `or`: a row
that belongs under two unrelated circumstances is two rows.

### Shell fields

`command:`, `prefill:` and `apply:` take either shell or a file: a single line beginning
with `./` or `../` names one, anything else is the shell itself. So a one-line
option list stays in the YAML where it is read together with the variable, and a
long one moves into a file beside it.

## What the interface does

In this order, and each page shown only if there is something on it:

- **Language**, on a machine that has never answered anything, if more than one
  is on offer. Afterwards it is a row in the settings.
- **The `first` questions**, unnumbered — the few that cannot wait, because
  everything after them is typed on the keyboard they settle.
- **Network**, if the tree describes one, since every stage past it downloads
  something.
- **The check**, if the tree declares a preflight. A failure here is a wall.
- **Presets**, one page for each the tree declares, in the order they are
  declared. A set of answers, not a mode: every value one fills in is an ordinary
  value from the next page on. Offered once, on a machine that has never answered
  anything.
- **The questions** that are required, mean something, and have no acceptable
  answer yet — one to a page, numbered, in the order the tree declared them.
- **Install** or **Settings**, once nothing is left open.
- **Settings** — every answer on one page with what it is set to. Opening one is
  the same page the opening questions used. `/` narrows the page to what is
  being looked for, by name or by the heading it sits under.
- **Installing** — a list of tasks filling in from the top, and nothing else.
  Not one line of what any script printed: a package manager's progress bars are
  not information here, they are noise with escape codes in it. All of it goes to
  the log. A task that asks stops the list to ask, and a declined one keeps
  its row, marked as passed over.
- **A failure** — what the tool said, then which script, which line, which
  command, which exit code, then where the rest is written down.
- **The way out**, where the tree declared one: a restart, a shutdown, and —
  where the tree named a console to stop into — closing the installer with the
  machine left running. Reached from everywhere leaving is asked for, and reached
  in place of the page that was running when it was — what ctrl+c stops is over,
  so there is nothing to go back to.

Every answer is written to the answer file the moment it is given, so an
interruption costs nothing.

## Files it writes

Beside whoever started the program — never inside the tree, which may be a
read-only medium or a git checkout:

```
./installer.conf   every answer, as KEY='value' # what it is — shell, editable by hand
./installer.log    everything: the runtime's own progress and every line a script printed
```

`-conf` or `INSTALLER_CONF` moves them.

## What a script is handed

Every declared variable under its own name, answered or not, plus:

| | |
|---|---|
| `INSTALLER_DIR` | the tree, absolute |
| `INSTALLER_CONF` | the answer file |
| `INSTALLER_LOG` | the log |
| `INSTALLER_LANG` | the language showing |
| `INSTALLER_VERSION` | the runtime's version |

Scripts are **sourced** into a shell that already carries an `ERR` trap and,
where the tree declares one, the shared library. They need no preamble, no
`set -e`, no imports, no error handling: if a command fails, the task fails,
and the user is told the file, the line, the command and the exit code. The one
idiom this rests on — `[ "$X" = true ] && do_it` leaving a non-zero status when
the test is false — is not a failure and never reported as one.

Scripts ask nothing and print nothing for a person to read. Every question is
declared in `installer.yaml` and asked inside the frame; every line of output
goes to the log. The single exception is a `tty: true` task, which is a
session somebody is sitting in front of rather than a step.

## Translations

The source string is the key. A line of Go says `T("Back")` and a catalog answers
with `"Zurück"`; a catalog with nothing to say about it leaves the English
standing. So a half-finished translation is useful from its first line, and the
code and the YAML stay readable on their own.

Two independent catalogs are merged: the runtime's own, compiled into the binary
under `locales/`, and the tree's, wherever its `locales:` points. Adding a
language is adding a file.

```sh
installer -strings > .../locales/fr.yaml   # every word the tree says, empty
installer -check                           # reports coverage per language
```

The language is chosen on the first run, changed in the settings, and otherwise
read from `LC_ALL`, `LC_MESSAGES` or `LANG`.

**`language:`** ties it to one of the tree's own answers instead. The value is
matched against the catalogs the way a machine's own locale is — `de_DE` is
German — so a tree that asks where a machine is has asked which language it
speaks: the opening page of languages is not shown, and neither is the language
row in the settings, because that answer is already there as a row of its own.

## Building

```sh
make build     # bin/installer-linux-amd64, and its checksum
make run       # straight from source, against ../setup
make check     # vet, test, build — must pass before anything is committed
```

The binary is static and has no runtime dependencies of its own. It has to live
in the tree it runs, since that is where it looks for `installer.yaml`.

## Layout

```
main.go              find the tree, load it, open the interface
internal/spec        the tree, read into memory, checked over and put in order
internal/store       the answers, and the file they survive a restart in
internal/exec        the only place a process is started, and the failure shape
internal/runner      what a question offers, which tasks this run consists of
internal/i18n        the message catalogs
internal/logging     the single sink for everything a run records
locales/             the runtime's own words, compiled in
tui/                 the interface: one frame, a stack of pages, no page draws its own
```
