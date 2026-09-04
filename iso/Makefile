# Turns a release (the root Makefile's `build` target) into a bootable ISO.
# There is nothing to build here without one already in place.

RELEASE_DIR ?= ../release
DIST_DIR    ?= ../dist
VERSION     ?= $(shell git -C .. describe --tags --always --dirty 2>/dev/null || echo dev)

# The image `make smoke` boots: the newest one built, so `make build && make
# smoke` needs no argument.
ISO ?= $(shell ls -t $(DIST_DIR)/*.iso 2>/dev/null | head -1)

# Empty when there is nothing to elevate, which is the case in CI. Only `clean`
# reaches for it, and only when a plain removal was refused.
SUDO := $(shell [ "$$(id -u)" -eq 0 ] || echo sudo)

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

# Everything build.sh leaves behind, the vendored theme in download/ included:
# a clean tree is one the next build starts from nothing with, and fetching the
# theme again is one shallow clone.
#
# mkarchiso writes as root, and a build killed before its own cleanup ran leaves
# those files here. The plain removal is tried first, so an ordinary clean never
# asks for a password; what survives it is root-owned and needs the escalation
# the build itself used — see build.sh.
clean:
	rm -rf archiso download smoke || $(SUDO) rm -rf archiso download smoke
