# Translating Arch OS

Everything on screen can be translated, and a translation is useful long before
it is finished: **the English sentence is the key**. A message no catalog has
anything to say about is shown exactly as it was written, so the first line
filled in is the first line somebody reads in their own language.

The catalogs are gettext `.po` files, the format Weblate, Crowdin, Transifex
and Pontoon all read, and the one where what a translator is shown is the
English sentence rather than a key like `ui.button.back`.

## What there is

Three catalogs, kept apart because they belong to different things. Each is a
component of its own on a translation platform.

| | Template | Catalogs | What is in it |
|---|---|---|---|
| Runtime | `runtime/locales/runtime.pot` | `runtime/locales/<code>.po` | the frame's own words: buttons, key hints, the labels on a failure report |
| Installer | `modules/installer/locales/installer.pot` | `modules/installer/locales/<code>.po` | what the Arch Linux installation asks and says about itself |
| Recovery | `modules/recovery/locales/recovery.pot` | `modules/recovery/locales/<code>.po` | the same, for repairing a system already on a disk |

Two of them are ever in use at once: the runtime's and the one belonging to the
module being run. They are merged at startup and behave as one, with the
module's laid over the runtime's, so a module may reword something the runtime
also says.

The `.pot` files are **generated and never edited**: the runtime's out of the Go
sources, a module's out of the module itself. That is why nothing can drift: there
is no list of translatable strings to keep in step with.

## Adding a language

Copy the template, fill in the `msgstr` lines, open a pull request:

```sh
cp runtime/locales/runtime.pot runtime/locales/fr.po
```

Nothing else has to be declared anywhere. The language is offered as soon as the
file is there, and a machine whose own locale matches it opens in it.

Two entries deserve a word:

- **`msgid "English"`** is not a word on screen. Its translation is the name of
  your language *in your language*, `Deutsch`, `Français`, `Português`. It is
  what the language picker lists, so every language is offered in its own words.
- **`msgstr ""`** left empty means "not translated yet", never "translate this
  to nothing". The English is shown instead, which is the right outcome.

## What a translation must keep

| | |
|---|---|
| `%s`, `%d` | Values filled in when the message is printed. Every one in the English has to appear in the translation, of the same kind and in the same order: they are filled in from left to right. Go can reorder them with `%[2]s`, but the check that keeps the rest honest refuses it. A sentence your language cannot build in that order is worth an issue: the English gets reworded rather than the check dropped. |
| `{{ARCH_OS_DISK}}` | An answer filled in, by name. Leave the braces and the name exactly as they are. |
| `⏎ ↑↓ esc · …` | Keys and separators in the hint lines. Translate the words around them, keep the marks. |
| Line breaks | A blank line between two paragraphs is a blank line on screen. The lines *inside* a paragraph are not, they are rewrapped to the terminal. |

A message with a placeholder is flagged `#, c-format`, and `make check` runs
`msgfmt --check-format` over every catalog: a `%s` dropped or turned into
something else fails the build rather than the installation.

`#, fuzzy` on an entry means the English changed under an existing translation.
It is not shown while the flag is there: check it, correct it, remove the flag.

## What the console can draw

The installer runs on the Linux virtual console before any desktop exists, and a
console font holds at most 512 glyphs. What is safe is **ASCII and the Latin-1
letters**: `äöüß`, `éèê`, `ñ`, `ç`, `å`, plus the handful of box and arrow
marks the interface already uses.

That covers German, French, Spanish, Italian, Portuguese, Dutch and the Nordic
languages. It does not cover Polish, Czech, Turkish, Greek, Cyrillic or anything
written in a script of its own: those letters are not in the font the live image
loads, and the console puts a replacement mark where each of them should be. A
test refuses a runtime catalog that would do that; a module's catalog is not
checked, and would simply be unreadable on screen.

Making those languages possible is a change to the image (a console font loaded
for the language that was chosen), not to the catalog. Open an issue if you want
to translate into one; the translation is welcome, it just cannot be shown yet.

## For maintainers

After a word is added, reworded or deleted anywhere:

```sh
make locales   # rewrites every template, brings every catalog up to it
make check     # refuses a stale template and a broken placeholder
```

`make locales` needs `gettext`. It calls `msgmerge`, which keeps every
translation whose English is unchanged, marks the ones whose English moved as
fuzzy, and drops nothing silently.

`runtime --check` reports coverage per language, which is how a catalog that has
fallen behind is noticed.

## On a translation platform

Weblate reads this repository as it stands. One component per catalog:

| Setting | Runtime | Installer | Recovery |
|---|---|---|---|
| File format | gettext PO | gettext PO | gettext PO |
| File mask | `runtime/locales/*.po` | `modules/installer/locales/*.po` | `modules/recovery/locales/*.po` |
| Template for new translations | `runtime/locales/runtime.pot` | `modules/installer/locales/installer.pot` | `modules/recovery/locales/recovery.pot` |
| Monolingual base file | *(none, PO is bilingual)* | | |

Point them all at the `dev` branch. `.weblate` in the repository root holds the
server and project for the `wlc` command line client; the API key belongs in
`~/.config/weblate`, never here.
