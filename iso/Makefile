# Turns a release (see the root Makefile's `build` target) into a bootable
# ISO. There is nothing to build here without one already in place.

RELEASE_DIR ?= ../release
VERSION     ?= $(shell git -C .. rev-parse --short HEAD 2>/dev/null || echo dev)

SCRIPTS := build.sh src/usr/local/bin/installer src/usr/local/bin/installer-console-theme

.PHONY: build lint check

build:
	RELEASE_DIR=$(RELEASE_DIR) SNAPSHOT_VERSION=$(VERSION) ./build.sh

lint:
	@for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done
	shellcheck -S style $(SCRIPTS)
	shfmt -d -i 4 $(SCRIPTS)

fmt:
	shfmt -w -i 4 $(SCRIPTS)

# The one command that has to pass before anything is committed.
check: lint
