# Turns a release (the root Makefile's `build` target) into a bootable ISO.
# There is nothing to build here without one already in place.

RELEASE_DIR ?= ../release
DIST_DIR    ?= ../dist
VERSION     ?= $(shell git -C .. rev-parse --short HEAD 2>/dev/null || echo dev)

# The image `make smoke` boots: the newest one built, so `make build && make
# smoke` needs no argument.
ISO ?= $(shell ls -t $(DIST_DIR)/*.iso 2>/dev/null | head -1)

SCRIPTS := build.sh smoke.sh $(wildcard src/usr/local/bin/*)

.PHONY: build smoke lint fmt check clean

build:
	RELEASE_DIR=$(RELEASE_DIR) DIST_DIR=$(DIST_DIR) SNAPSHOT_VERSION=$(VERSION) ./build.sh

# Boots the image and waits for the interface to come up in it. See smoke.sh.
smoke:
	./smoke.sh $(ISO)

lint:
	@for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done
	shellcheck -S style $(SCRIPTS)
	shfmt -d -i 4 $(SCRIPTS)

fmt:
	shfmt -w -i 4 $(SCRIPTS)

# What has to pass before anything is committed.
check: lint

# build.sh takes its own scratch space with it whichever way it ends. What is
# left here is the download cache, which it keeps on purpose.
clean:
	rm -rf archiso download smoke
