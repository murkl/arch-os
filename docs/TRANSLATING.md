# Translating

Everything on screen can be translated and a translation is useful long before it is finished: **the English sentence is the key**. A message no catalog answers is shown exactly as it was written, so the first line you fill in is the first line somebody reads in their own language.

The catalogs are gettext `.po` files, the format Weblate, Crowdin, Transifex and Pontoon all read.

## The two Catalogs

Kept apart because they belong to different things. Each is a component of its own on a translation platform.

| Component | Template | Catalogs | Description |
| --- | --- | --- | --- |
| Installer | `modules/installer/locales/installer.pot` | `modules/installer/locales/<code>.po` | What the Arch Linux installation asks and says about itself |
| Recovery | `modules/recovery/locales/recovery.pot` | `modules/recovery/locales/<code>.po` | The same, for repairing a system already on disk |

The frame's own words — buttons, key hints, the labels on a failure report — belong to **[Oak](https://github.com/murkl/oak)** and are translated there. Two catalogs are in use at once: Oak's and the one belonging to the module being run. They are merged at startup and behave as one, with the module's laid over Oak's.

**Note:** _The `.pot` files are generated and never edited. A module's comes out of the module itself, with `make locales`._

## Adding a Language

Copy the template, fill in the `msgstr` lines, open a pull request:

```
cp modules/installer/locales/installer.pot modules/installer/locales/fr.po
```

Nothing else has to be declared anywhere. The language is offered as soon as the file exists and a machine whose own locale matches it opens in it.

Two entries deserve a word:

- `msgid "English"` is not a word on screen. Its translation is the name of your language **in your language**: `Deutsch`, `Français`, `Português`. That is what the language picker lists
- `msgstr ""` left empty means *not translated yet*, never *translate this to nothing*. The English is shown instead, which is the right outcome

## What a Translation must keep

| Element | Description |
| --- | --- |
| `%s`, `%d` | Values filled in when the message is printed. Every one in the English has to appear in the translation, of the same kind and in the same order |
| `{{ARCH_OS_DISK}}` | An answer filled in by name. Leave the braces and the name exactly as they are |
| `⏎ ↑↓ esc · …` | Keys and separators in the hint lines. Translate the words around them, keep the marks |
| Line breaks | A blank line between two paragraphs is a blank line on screen. Line breaks inside a paragraph are rewrapped to the terminal |

**Note:** _Go can reorder placeholders with `%[2]s`, but the check that keeps the rest honest refuses it. A sentence your language cannot build in that order is worth an issue: the English gets reworded rather than the check dropped._

A message with a placeholder is flagged `#, c-format` and `make check` runs `msgfmt --check-format` over every catalog. A `%s` dropped or changed fails the build rather than the installation.

`#, fuzzy` on an entry means the English changed under an existing translation. It is not shown while the flag is there. Check it, correct it, remove the flag.

## What the Console can draw

The Installer runs on the Linux virtual console before any desktop exists and a console font holds at most 512 glyphs. What is safe is **ASCII and the Latin-1 letters**: `äöüß`, `éèê`, `ñ`, `ç`, `å`, plus the handful of box and arrow marks the interface already uses.

- Supported: German, French, Spanish, Italian, Portuguese, Dutch and the Nordic languages
- Not supported: Polish, Czech, Turkish, Greek, Cyrillic or anything written in a script of its own

Those letters are not in the font the live image loads and the console draws a replacement mark in their place. A module's catalog is not checked for it and would simply be unreadable on screen.

**Note:** _Making those languages possible is a change to the image (a console font loaded for the chosen language), not to the catalog. Open an issue if you want to translate into one._

## For Maintainers

After a word is added, reworded or deleted anywhere:

```
make locales   # rewrites every template, brings every catalog up to it
make check     # refuses a stale template and a broken placeholder
```

`make locales` needs `gettext` and the runtime, which the Makefile downloads. It calls `msgmerge`, which keeps every translation whose English is unchanged, marks the ones whose English moved as fuzzy and drops nothing silently.

**Note:** _`make check` in a module's folder reports coverage per language, which is how a catalog that has fallen behind gets noticed._

## On a Translation Platform

Weblate reads this repository as it stands. One component per catalog:

| Setting | Installer | Recovery |
| --- | --- | --- |
| File format | gettext PO | gettext PO |
| File mask | `modules/installer/locales/*.po` | `modules/recovery/locales/*.po` |
| Template for new translations | `modules/installer/locales/installer.pot` | `modules/recovery/locales/recovery.pot` |
| Monolingual base file | *(none, PO is bilingual)* | |

Point them both at the `dev` branch.

**Note:** _`.weblate` in the repository root holds the server and project for the `wlc` command line client. The API key belongs in `~/.config/weblate`, never here._
