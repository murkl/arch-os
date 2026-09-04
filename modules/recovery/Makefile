# The recovery is data, not a program: there is nothing here to build. What there
# is, is a way to be sure it still loads and that every script in it is sound —
# before it reaches a machine whose only copy of something is on that disk.

ROOT := ../..

# The runtime, which looks for a product beside its own binary. The source tree
# is not that shape — each module keeps its own declaration in its own folder —
# so `make dev` at the root lays it out in symlinks, and what is loaded below is
# this folder itself rather than a copy of it.
OAK    := $(ROOT)/.dev/oak
MODULE := recovery

SCRIPTS := $(shell find . -name '*.sh')

# The template this module's catalogs are filled in from, and the catalogs
# themselves. Both are generated: the template out of the module, the catalogs
# out of the template.
POT      := locales/recovery.pot
CATALOGS := $(wildcard locales/*.po)

.PHONY: check load lint fmt locales locales-check dev

# What has to pass before anything is committed.
check: load lint locales-check

# Loads the module exactly as a run does at startup, so every task, every
# condition and every preset is resolved — and prints the order they add up to,
# which is the one thing about a module nobody writes down.
load: dev
	$(OAK) --inspect $(MODULE)

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
	@$(OAK) --strings $(MODULE) > $(POT)
	@for po in $(CATALOGS); do msgmerge --quiet --update --backup=none --no-wrap "$$po" $(POT); done

# A question added or reworded without `make locales` being run is a question no
# translator will ever be shown. And a translation that drops a placeholder is a
# message that breaks where it is printed rather than where it was written.
locales-check: dev
	@$(OAK) --strings $(MODULE) | diff -u $(POT) - \
		|| { echo "$(POT) is out of date — run 'make locales'" >&2; exit 1; }
	@for po in $(CATALOGS); do msgfmt --check-format -o /dev/null "$$po" || exit 1; done

dev:
	@$(MAKE) -C $(ROOT) dev
