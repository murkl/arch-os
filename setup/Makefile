# The installer is data, not a program: there is nothing here to build. What
# there is, is a way to be sure it still loads and that every script in it is
# sound — before it reaches a machine with a disk in it.

# The runtime that drives this tree, as `make build` in ../runtime leaves it.
# Nothing is copied in here: the tree is data, and a binary sitting in it would
# be a build artefact in the middle of the source.
RUNTIME ?= ../runtime/bin/installer-$(shell go env GOOS)-$(shell go env GOARCH)

# -dir because the runtime otherwise looks for its installer.yaml beside itself,
# and here it is the tree that stays put while the binary lives elsewhere.
RUN := $(RUNTIME) -dir .

SCRIPTS := $(shell find . -name '*.sh')

.PHONY: check load lint fmt strings

# The one command that has to pass before anything is committed.
check: load lint

# Loads the tree exactly as the runtime does at startup, so every task, every
# condition and every preset is resolved — and the order they add up to is
# printed, which is the one thing about a tree nobody writes down.
load: $(RUNTIME)
	$(RUN) -check

lint:
	shellcheck -x $(SCRIPTS)
	shfmt -d -i 4 $(SCRIPTS)

fmt:
	shfmt -w -i 4 $(SCRIPTS)

# Prints an empty translation catalog for this tree. Redirect it to
# locales/<code>.yaml and fill in the right-hand side.
strings: $(RUNTIME)
	@$(RUN) -strings

# Both targets need a built runtime, and neither builds one: what drives this
# tree is the other half of the project, and building it from here would hide
# which half a failure came from.
$(RUNTIME):
	@echo "no runtime at $@ — run 'make build' in ../runtime first" >&2 && exit 1
