# The installer is data, not a program: there is nothing here to build. What
# there is, is a way to be sure it still loads and that every script in it is
# sound — before it reaches a machine with a disk in it.

# The runtime that drives this tree, as `make build` in ../runtime leaves it.
# Nothing is copied in here: a binary in the tree would be a build artefact in
# the middle of the source.
RUNTIME ?= ../runtime/bin/installer-$(shell go env GOOS)-$(shell go env GOARCH)

# -dir because the runtime otherwise looks for a tree beside its own binary.
RUN := $(RUNTIME) -dir .

SCRIPTS := $(shell find . -name '*.sh')

.PHONY: check load lint fmt strings

# What has to pass before anything is committed.
check: load lint

# Loads the tree exactly as the runtime does at startup, so every task, every
# condition and every preset is resolved — and prints the order they add up to,
# which is the one thing about a tree nobody writes down.
load: $(RUNTIME)
	$(RUN) -check

lint:
	shellcheck -x $(SCRIPTS)
	shfmt -d -i 4 $(SCRIPTS)

fmt:
	shfmt -w -i 4 $(SCRIPTS)

# An empty translation catalog for this tree. Redirect it to locales/<code>.yaml
# and fill in the right-hand side.
strings: $(RUNTIME)
	@$(RUN) -strings

# Neither target builds a runtime: building it from here would hide which half a
# failure came from.
$(RUNTIME):
	@echo "no runtime at $@ — run 'make build' in ../runtime first" >&2 && exit 1
