# Arch OS Runtime

The program behind the Installer and the Recovery. It draws the pages, asks the questions, stores the answers and runs the scripts. What it shows and does is declared in YAML, with bash scripts beside it, and all of it is compiled into one binary. Another Arch distribution swaps the YAML and the scripts and keeps the runtime.

```
arch-os <module> [--dry-run] [--kiosk]
arch-os glyphs
arch-os --version
```

| Argument | Meaning |
| --- | --- |
| `<module>` | The module to open: a folder beside `runtime/` with a `module.yaml`, so `installer` or `recovery` |
| `--dry-run` | Shows the run without doing it, see [Dry Run](#dry-run) |
| `--kiosk` | Runs as the machine's only program: leaving restarts it with every answer kept |
| `glyphs` | Every character the interface draws on a console, for **[iso/glyphs.sh](../iso/glyphs.sh)** |

```
cargo build --release   # the program, with every module inside it
cargo test              # every module loaded as a run loads it, every catalog held to every text
```

## The Product

```
product.yaml        the product: its name, color and wordmark
lib.sh              the one library every script gets
locales/<code>.po   one catalog per language
<module>/           one folder per module
runtime/            this program
```

The build embeds everything except `runtime/` into the binary, so the binary is the whole program. At start it writes the scripts to `$XDG_RUNTIME_DIR/arch-os-<pid>/` and runs them there. The folder is removed when the program ends, a stale one at the next start.

### `product.yaml`

```yaml
title: Arch OS
accent: "#1793d1"
console-accent: bright-blue
surface: "#3b4252"
console-surface: blue
status:
  check: check_online()
  pass: Online
  fail: Offline
logo: |
  Arch Linux

   █████  ██████   ██████ ██   ██      ██████  ███████
```

| Key | Description |
| --- | --- |
| `title` | The product's name, first in the breadcrumb above every page |
| `accent` | `#rrggbb`, the one color the interface is built from |
| `console-accent` | Its slot on a 16-color console, see [The Console](#the-console) |
| `surface` | `#rrggbb`, behind the row under the cursor. Dark gray without it |
| `console-surface` | Its slot on a console: `red`, `green`, `yellow`, `blue`, `magenta`, `cyan` or `white`, since a console has only eight background colors. Blue without it |
| `status` | One line about the machine in the header. `check` is a function of `lib.sh`: exit 0 shows `pass`, anything else `fail`. Checked every `every` seconds, default 10, and right after an action ran |
| `logo` | The wordmark, shown on the way in. Above the first blank line, a dim eyebrow |

### `lib.sh`

The one place for shared script code. Loaded before every task, test and action, and before everything the YAML calls. It defines functions and exports constants, and computes nothing while it loads.

### Shell in the YAML

A key that runs shell code names it in one of two forms:

| Form | Runs |
| --- | --- |
| `name()` | That function of `lib.sh`. Refused at startup where `lib.sh` has none by that name |
| `./file.sh` | That file, relative to the folder of the YAML |

Shell code inside the YAML is refused: every line lives where a linter reads it and a failure can point to it. The keys are `check` of the status, and `options-from`, `value-from`, `prefill`, `apply` and `check` of a setting. Both forms are named after the key that calls them. A function serves more than one declaration or script, such as `options_disks()` or `check_online()`. A file serves one declaration alone, such as `./prefill-timezone.sh` or `./apply-timezone.sh`.

## A Module

| Path | Description |
| --- | --- |
| `module.yaml` | What it is, asks and does |
| `tasks/<stage>/<task>/task.yaml` | A task |
| `tasks/<stage>/<task>/task.sh` | Its work |
| `tasks/<stage>/<task>/test.sh` | Optional: checks that it worked |
| `actions/<action>/action.yaml` | An action |
| `actions/<action>/action.sh` | Its work |

The folder name is the module's identity: `arch-os recovery` opens it, and it writes `recovery.conf` and `recovery.log`.

### `module.yaml`

```yaml
title: Installer
start: Install now
confirm: |
  Install Arch OS on {{ARCH_OS_DISK}}?

  Everything on the disk is erased.
report: |
  Arch OS installed

  {{ARCH_OS_DISK}} is ready to boot.
requires: [live-image, root, internet]
dashboard: [start, settings, reset, wifi]
language: Region
on:
  leave: [restart, shutdown]
  failure: [share-log]
  success: [chroot]
errors:
  3: |
    No internet connection

    Connect this machine and choose Install now again.
stages: [prepare, system, finish]
presets: …
settings: …
```

| Key | Description |
| --- | --- |
| `title` | **Required.** The module's name, in the breadcrumb above every page |
| `start` | The first row of the dashboard, which starts the work. `Start` without it |
| `confirm` | A question asked after every password and before the work, opening on No. The first paragraph is the headline |
| `report` | The words a finished run ends on. The first paragraph is the headline |
| `requires` | Actions checked before anything is asked, in this order. The first that returns no blocks everything with its page and is checked again every few seconds. Skipped on a dry run |
| `dashboard` | **Required.** The dashboard's rows in order, see [The Dashboard](#the-dashboard) |
| `language` | The group whose first row is the interface language. Refused at startup where no setting is in it |
| `on` | Where its other actions are offered, see [Actions](#actions) |
| `errors` | The words for each status any of its scripts stops with, see [Stopping on Purpose](#stopping-on-purpose) |
| `stages` | **Required.** The phases of the work, in order. Each is a folder `tasks/<stage>/` |
| `presets` | The profiles, see [Presets](#presets) |
| `settings` | The questions, see [Settings](#settings) |

### The Way In

1. The wordmark, then the language, unless the answer file holds one
2. Every setting marked `first`
3. The actions under `requires`
4. The profiles, while there are no answers yet
5. Every required setting without an answer, one page each, counted in the header
6. The dashboard

### The Dashboard

The module's home: its rows in the order `dashboard` lists them, each name once. `f` filters the rows.

| Name | Row |
| --- | --- |
| `start` | **Required.** The row `start` names, which starts the work |
| `settings` | **Required.** Every answer under its group heading, each a row that opens its question. The interface language heads the group `language` names |
| `reset` | **Reset all answers**, which deletes the answer file after a question that opens on No |
| An action | Its row, wherever its `requires` return yes, under the heading its `group` names. Right under answers that end with that group, a blank row stands in place of the heading. An action folder may not use one of the names above |

A blank row follows `start`, the answers and each group of actions. Right after `start`, the headings of the answers take its place.

`start` asks what is still missing, then every password, then `confirm`, then runs the tasks: one row each, checked off as it ends, counted in the header. `tab` switches to their output, each under its task's title, and back, during the run and after it. While the tasks run, `systemd-inhibit` blocks shutdown and sleep, so closing the lid never suspends a run halfway. A task that `asks` or has a `confirm` pauses the run on its page. The run ends on a page with its outcome, which the header names: **Done** or **Failed**. A finished run shows the module's `report` and how long it took, then the actions under `on: success` and **Continue**. A failed run shows what failed and where, the actions under `on: failure`, and **Back to the dashboard**, after a confirmation.

`q` or `esc` on the dashboard leaves. A module with `on: leave`, or a kiosk, shows a page first: the actions under `on: leave`, then **Exit**, or **Start over** in a kiosk. During a run, the same page shows that every choice stops it. The run goes on behind it, and what it asks waits until the page closes. A choice stops the run first: its script and everything it started get `SIGTERM`, and `SIGKILL` after 10 seconds. The choice is carried out once none of it runs.

## Settings

One entry under `settings:` is one question and one environment variable.

```yaml
settings:
  - name: ARCH_OS_DISK
    type: list
    title: Disk
    description: Everything on it is erased.
    group: Storage
    required: true
    options-from: options_disks()
    pattern: '^/dev/'
    error: Choose a disk that exists.
```

Every setting names its type. The type sets how it is drawn and which keys apply:

| `type` | Drawn as | Takes |
| --- | --- | --- |
| `text` | A text box | `default`, `prefill`, `pattern`, `value-from` |
| `bool` | Yes or No | `default`, `value-from` |
| `list` | A list | `options` or `options-from`, `default`, `prefill`, `pattern`, `filter` |
| `open-list` | A list, plus a row for a custom entry | `options` or `options-from`, `default`, `prefill`, `pattern`, `filter` |
| `password` | An existing password, typed once | `check` |
| `new-password` | A new password, typed twice | |

| Key | Description |
| --- | --- |
| `name` | **Required.** The variable a script reads. `MODULE_` and `DRY_RUN` are reserved for the runtime |
| `type` | **Required.** One of the types above |
| `title` | **Required.** The question, and its row on the dashboard |
| `description` | What the value is for |
| `group` | Its heading on the dashboard |
| `required` | Asked for while unanswered |
| `default` | The initial answer, such as `true`, `auto` or `pc105` |
| `options` | The answers, listed inline |
| `options-from` | Shell that prints the answers, one per line. `value<TAB>label` stores the value and shows the label |
| `value-from` | Shell that prints the value instead of asking. Never asked, never on the dashboard, never stored |
| `prefill` | Shell that prints a suggestion. Still asked |
| `apply` | Shell that applies the answer to this machine, such as a keymap |
| `check` | Shell that tests a `password` before it is accepted |
| `first` | Asked before everything else, `requires` included, with the list's filter open |
| `filter` | The list's filter box: `collapsed` behind `f`, or `open` |
| `pattern` | A regular expression the answer must match |
| `error` | The message for a wrong answer |
| `when` | When it is asked, see [Conditions](#conditions) |

- `true` and `false` show as Yes and No
- A password is asked right before the run, used and forgotten
- `value-from` is read when the module opens and whenever an answer changes
- An answer from `options-from` is checked against its list again when the work starts, before any password. One the list no longer prints is asked again
- An answer read from the file goes through `pattern` and the list like one typed. One that fails is asked again

**Note:** _A key its type does not take is refused at startup, and so is `value-from` together with `prefill` or `first`, and a password with `first`._

### Conditions

```yaml
when:
  - ARCH_OS_DESKTOP != none
  - ARCH_OS_FLATPAK_ENABLED == true
```

`VAR == value` and `VAR != value`, one or several, and every one must hold. There is no `or`: a row for two unrelated conditions is two rows. A name no setting declares is refused at startup.

### Placeholders

`{{VAR}}` is filled in from the answers in every `confirm`, `report`, `error` and `errors`. A name the module does not declare is refused at startup, and a translation that drops or adds one fails the tests.

## Presets

On screen a profile, offered once while there are no answers yet. A preset is a set of answers, not a mode.

```yaml
presets:
  - title: Desktop
    description: The Core with GNOME.
    values:
      ARCH_OS_DESKTOP: gnome

  - title: Online (paste.rs)
    description: Every answer of a shared configuration.
    action: import-config
```

A preset lists its answers under `values` or names the action that fetches them, never both. The action's script appends them to `MODULE_CONF`.

## Tasks

A folder under its stage: `tasks/<stage>/<task>/`. The stage is a **when**, the folder in it a **what**.

```yaml
title: Install the graphics drivers
needs: [gnome]
when: ARCH_OS_DESKTOP != none
```

| Key | Description |
| --- | --- |
| `title` | **Required.** Its row in the run |
| `needs` | Tasks of its own stage it runs after |
| `when` | Every condition must hold, or it is left out of the run |
| `asks` | A question the run pauses for first: `name`, `title`, `description`, `filter` and `options` or `options-from`, read once the run reaches it. An empty list skips the task. Never stored |
| `confirm` | A yes or no before it runs, opening on No. No skips it |
| `yes-after` | Tasks before it: where one of them ran in this run, `confirm` opens on Yes |
| `report` | A page the run pauses on afterwards. The first paragraph is the headline |
| `progress` | `true`: its last printed line shows under it while it runs |
| `simulates` | `true`: runs on a dry run too, reading `DRY_RUN` itself |
| `allow-failure` | `true`: its failure does not stop the run |
| `errors` | The words for each status its `task.sh` stops with, see [Stopping on Purpose](#stopping-on-purpose) |

- A task runs after every task of an earlier stage, and within its stage after its `needs`
- A `needs` into another stage, an unknown name and a cycle are refused
- A folder under `tasks/` that is no declared stage is refused

### Tests

A `test.sh` beside `task.sh` runs right after the task, on the machine it worked on. It reads without changing anything, and its exit status is the result.

- A failed test does not stop the run
- The page the run ends on counts them: `38 of 40 tests passed`
- Where a test or an `allow-failure` task failed, that page offers **Test results**: the list, each row opening the file, the line, the command and its output

## Actions

A script a module runs outside its work: `actions/<action>/action.yaml` and `action.sh`. The YAML declares how it behaves, the script only does the work: exit 0 is yes, any other status no.

```yaml
title: Connect to Wi-Fi
description: Connects to a wireless network.
requires: [wifi-card, no-cable]
on:
  failure: [wifi-passphrase]
inputs:
  - name: ARCH_OS_WIFI_SSID
    type: list
    title: Network
    required: true
    options-from: options_wifi_networks()
```

| Key | Description |
| --- | --- |
| `title` | **Required.** Its row, and the heading over its page |
| `description` | The sentence under its row. Choosing the row is the consent, so it names what leaves the machine |
| `group` | The dashboard heading its row stands under. Refused where `dashboard` does not list the action |
| `error` | What a no means. **Required** under a module's `requires` |
| `requires` | Actions that must return yes before this one is offered |
| `on: failure` | Where this action returns no, the first of these offered on this machine opens |
| `inputs` | Its questions before it runs, a page each: settings without `first`, `group` or `value-from`. Answered for this run only, never stored |
| `confirm` | A yes or no after its inputs and before its work, opening on No. For a second consent: choosing the row agrees to the lookup, this to its result |
| `report` | Its page after it ran. The first paragraph is the headline |
| `qr` | A variable shown on that page as a QR code, such as an address. No setting declares it: the script appends it to `MODULE_CONF` |
| `tty` | The terminal itself is its only page |
| `simulates` | `true`: runs on a dry run too |
| `errors` | The words for each status its `action.sh` stops with, see [Stopping on Purpose](#stopping-on-purpose) |

Where a module places an action:

| Under | Offered |
| --- | --- |
| `requires` | Nowhere: run by itself before anything is asked, a check without a page. Its `error` blocks everything until it returns yes |
| `dashboard` | A row on the dashboard, where the list puts it |
| `on: leave` | A row on the way out, above **Exit** |
| `on: failure` | A row under a run that failed. None under a run [stopped on purpose](#stopping-on-purpose) |
| `on: success` | A row under a run that finished |

- A row opens the action's inputs, its `confirm`, its work and its `report` in turn. A longer flow is several actions, chained by `on: failure`
- `on: leave` declares that the machine booted to run the module, so leaving becomes a choice
- Refused at startup: an unknown name, an action nothing names, a cycle of actions, an action that names itself under `on: failure`, a page beside the terminal, a page or a `confirm` on an action only run by itself, `errors` beside `tty`, a check without `error`, and an input or a `confirm` under `on: leave`

## What a Script Receives

Every declared variable under its own name, and the runtime's:

| Variable | Description |
| --- | --- |
| `MODULE_CONF` | The answer file. A script stores an answer by appending `KEY='value'` |
| `MODULE_LOG` | The log |
| `MODULE_LANGUAGE` | The interface language, such as `de` |
| `MODULE_VERSION` | The version of the program |
| `DRY_RUN` | `true` on a dry run, absent otherwise |

Scripts run with `lib.sh` loaded and an `ERR` trap: no shebang, no `set -e`, no error handling. Each runs in its own session, without a terminal, unless the action has `tty: true`.

- **Any non-zero status is a failure**, from a failed command or from the script itself. `[ "$X" = y ] && do_it` as the last line fails where the test is false. A status that means no error is allowed by name: `grep x file || allow 1`
- **Ask nothing.** Every question is in the YAML, unless the action has `tty: true`. A program that prompts on the terminal anyway fails at once, as there is none
- **Print nothing for a person.** stdout and stderr go to the log
- A `test.sh` also changes nothing

A failure shows the module, the task or action, the script and its line, the command, the exit code and the tool's output. Inside a function of `lib.sh`, the line is that of the calling script.

### Stopping on Purpose

A script stops on an expected problem itself, with a status of its own. The YAML puts that status into words:

```yaml
errors:
  3: |
    No internet connection

    Connect this machine and choose Install now again.
```

`exit 3` stops the run with these words, the first paragraph as the headline. No technical details and no `on: failure` row appear with them: the words say what to do. Every other failure is reported where the script broke, for whoever fixes it.

- A task or an action declares them for its own script, the module for every script it has. The unit's own words take precedence
- A status from 1 to 125: bash reserves 126 and up for a command it cannot run or find, and for signals
- Only `exit` counts, in the script or in a function it calls. A failed command, a status from `return` or the last line, and an `exit` inside `$(…)` or `( … )` count as a broken script, whatever the status
- A status no YAML puts into words is a failure like any other
- An action stopped this way opens nothing under its `on: failure`

### Dry Run

`--dry-run` shows a run without doing it. No task, test or action starts unless it declares `simulates: true`, and nothing under `requires` is checked. What a setting calls still runs, with `DRY_RUN=true`.

## Files It Writes

In the directory the program was started from:

| File | Description |
| --- | --- |
| `<module>.conf` | Every answer as `KEY='value'`, under its group and with its title as a comment, the interface language first. Editable by hand. No password, no derived answer, no answer of a task or an action |
| `<module>.log` | The run's progress and everything every script printed, timestamped in the machine's time zone. The previous log stays as `<module>.log.old` |

## Keys

| Key | Meaning |
| --- | --- |
| `⏎` `→` `l` | Open, confirm |
| `esc` `←` `h` `backspace` | Back |
| `↑` `↓` `k` `j` | Move |
| `⇞` `⇟` `g` `G` | A page up or down, the top, the bottom |
| `f` `/` | Filter a list, where the footer shows it |
| `q` `ctrl+c` | Leave |
| `tab` | Switch a run between its list and its output |

**Note:** _An empty text box shows a placeholder: the title of its question, or **Repeat** for a password typed twice. In a text box every letter is typed, and backspace deletes one. Pasted text goes into a text box and is ignored elsewhere. A held key repeats only for moving and typing._

## Translations

The English text is the key. A catalog without a translation shows the English.

- `locales/<code>.po` holds every text of the runtime and of every module, checked by the tests: a missing or unused text fails them, and so does a dropped or added placeholder
- `msgid "English"` translates to the language's own name: `Deutsch`. That is how the language page lists it
- The language is chosen on the first page and stored on the first line of the answer file, as `MODULE_LANGUAGE`. A file that holds one skips the page
- The first page is never translated: it appears before a language is chosen

## The Console

A 16-color terminal, such as the Linux console (`TERM=linux`), shows every color in the slot of its hue, and the accent in the slot `console-accent` names: `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, or any of them with `bright-`. Lines and marks switch to what a console font holds, and `arch-os glyphs` prints every character the interface draws there, so the ISO's font can be checked against it.

**Note:** _A console font holds 512 glyphs at most: Latin with its accents, Greek and Cyrillic. **[➜ What the Console Can Draw](../iso/README.md#what-the-console-can-draw)**_
