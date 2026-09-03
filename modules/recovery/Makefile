# The recovery is data, not a program: there is nothing here to build. What there
# is, is a way to be sure it still loads and that every script in it is sound —
# before it reaches a machine whose only copy of something is on that disk.

# The runtime that drives this module, as `make build` in ../../runtime leaves
# it. Nothing is copied in here: a binary in the module would be a build
# artefact in the middle of the source.
ROOT    := ../..
RUNTIME ?= $(ROOT)/runtime/bin/runtime-$(shell go env GOOS)-$(shell go env GOARCH)

# -dir because the runtime otherwise looks for its runtime.yaml beside its own
# binary, and because the source tree is not the shape it looks for: each
# component keeps its own declaration in its own folder. `make dev` at the root
# is that shape in symlinks, so what is loaded below is this folder itself
# rather than a copy of it. The module name because everything below is about
# this one alone.
RUN := $(RUNTIME) -dir $(ROOT)/.dev recovery

SCRIPTS := $(shell find . -name '*.sh')

# The template this module's catalogs are filled in from, and the catalogs
# themselves. Both are generated: the template out of the module, the catalogs
# out of the template.
POT      := locales/recovery.pot
CATALOGS := $(wildcard locales/*.po)

.PHONY: check load lint fmt locales locales-check dev

# What has to pass before anything is committed.
check: load lint locales-check

# Loads the module exactly as the runtime does at startup, so every task, every
# condition and every preset is resolved — and prints the order they add up to,
# which is the one thing about a module nobody writes down.
load: $(RUNTIME) dev
	$(RUN) -check

lint:
	shellcheck -x $(SCRIPTS)
	shfmt -d -i 4 $(SCRIPTS)

fmt:
	shfmt -w -i 4 $(SCRIPTS)

# Asks the loaded module for every word it says, writes the template, and brings
# each catalog up to it. msgmerge keeps every translation whose source text is
# unchanged and marks the rest fuzzy rather than dropping it — a reworded
# sentence is a translation to look at again, not one to write from scratch.
locales: $(RUNTIME) dev
	@$(RUN) -strings > $(POT)
	@for po in $(CATALOGS); do msgmerge --quiet --update --backup=none --no-wrap "$$po" $(POT); done

# A question added or reworded without `make locales` being run is a question no
# translator will ever be shown. And a translation that drops a placeholder is a
# message that breaks where it is printed rather than where it was written.
locales-check: $(RUNTIME) dev
	@$(RUN) -strings | diff -u $(POT) - \
		|| { echo "$(POT) is out of date — run 'make locales'" >&2; exit 1; }
	@for po in $(CATALOGS); do msgfmt --check-format -o /dev/null "$$po" || exit 1; done

dev:
	@$(MAKE) -C $(ROOT) dev

# Neither target builds a runtime: building it from here would hide which half a
# failure came from.
$(RUNTIME):
	@echo "no runtime at $@ — run 'make build' in ../../runtime first" >&2 && exit 1
