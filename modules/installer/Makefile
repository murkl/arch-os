# The installer is data, not a program: there is nothing here to build. What
# there is, is a way to be sure it still loads and that every script in it is
# sound — before it reaches a machine with a disk in it.

ROOT := ../..

# What reads this module the way the runtime does at startup — see
# ../../runtime/tools/inspect. It runs out of the runtime's own folder, so -dir
# is relative to that: the source tree is not the shape a runtime looks for,
# each component keeping its own declaration in its own folder, and `make dev`
# at the root is that shape in symlinks — so what is loaded below is this folder
# itself rather than a copy of it. MODULE is named last, after any flag, because
# everything below is about this one module alone.
INSPECT := go run -C $(ROOT)/runtime ./tools/inspect -dir ../.dev
MODULE  := installer

SCRIPTS := $(shell find . -name '*.sh')

# The template this module's catalogs are filled in from, and the catalogs
# themselves. Both are generated: the template out of the module, the catalogs
# out of the template.
POT      := locales/installer.pot
CATALOGS := $(wildcard locales/*.po)

.PHONY: check load lint fmt locales locales-check dev

# What has to pass before anything is committed.
check: load lint locales-check

# Loads the module exactly as the runtime does at startup, so every task, every
# condition and every preset is resolved — and prints the order they add up to,
# which is the one thing about a module nobody writes down.
load: dev
	$(INSPECT) $(MODULE)

lint:
	shellcheck -x $(SCRIPTS)
	shfmt -d -i 4 $(SCRIPTS)

fmt:
	shfmt -w -i 4 $(SCRIPTS)

# Asks the loaded module for every word it says, writes the template, and brings
# each catalog up to it. msgmerge keeps every translation whose source text is
# unchanged and marks the rest fuzzy rather than dropping it — a reworded
# sentence is a translation to look at again, not one to write from scratch.
locales: dev
	@$(INSPECT) -strings $(MODULE) > $(POT)
	@for po in $(CATALOGS); do msgmerge --quiet --update --backup=none --no-wrap "$$po" $(POT); done

# A question added or reworded without `make locales` being run is a question no
# translator will ever be shown. And a translation that drops a placeholder is a
# message that breaks where it is printed rather than where it was written.
locales-check: dev
	@$(INSPECT) -strings $(MODULE) | diff -u $(POT) - \
		|| { echo "$(POT) is out of date — run 'make locales'" >&2; exit 1; }
	@for po in $(CATALOGS); do msgfmt --check-format -o /dev/null "$$po" || exit 1; done

dev:
	@$(MAKE) -C $(ROOT) dev
