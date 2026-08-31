# Builds a release: the runtime binary next to the installer tree — the only
# thing the runtime looks for, and the only thing an installation needs (see
# runtime/README.md).
#
# Two folders, and the difference between them is the whole layout here:
# release/ is the installer as a machine runs it, and dist/ is what a person
# downloads. `tarball` and `iso` each turn the first into one of the second.
#
# VERSION is the single source of truth this whole project uses: the short
# commit SHA of HEAD, or "dev" outside a repository.
VERSION := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

RELEASE_DIR := release
DIST_DIR    := dist
RUNTIME_BIN := runtime/bin/installer-linux-amd64

# What the installer tree is, and the only place it is written down: everything
# in setup/ that a machine being installed onto needs, and nothing meant for a
# developer.
TREE := installer.yaml lib.sh data locales hooks tasks

# What a download is called. Both artefacts of a build carry the same name and
# differ only by extension, the way archiso already names the image — so a
# release page reads as one build rather than two. Only x86_64 is built: the
# runtime binary is linux/amd64, which is the same thing under its other name.
STEM    := archos-$(VERSION)
TARBALL := $(STEM)-x86_64.tar.gz

.PHONY: all build tarball iso check clean

# Every target here writes release/, and build empties it first. Running two of
# them at once would pull the folder out from under the other.
.NOTPARALLEL:

all: build

# The runtime binary, plus a clean copy of the setup tree. The folder is emptied
# first, so what is in it afterwards is exactly this build and nothing a
# previous one left behind.
build:
	$(MAKE) -C runtime release
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	install -m 755 $(RUNTIME_BIN) $(RELEASE_DIR)/installer
	cp -r $(addprefix setup/,$(TREE)) $(RELEASE_DIR)/

# The release as one file, for a stock Arch ISO: unpack it, run ./installer.
# It unpacks into a folder of its own rather than over the directory it was
# downloaded into, and gets a checksum beside it the way the image does.
tarball: build
	mkdir -p $(DIST_DIR)
	tar -czf $(DIST_DIR)/$(TARBALL) --owner=0 --group=0 --sort=name \
		--transform 's,^,$(STEM)/,' \
		-C $(RELEASE_DIR) installer $(TREE)
	cd $(DIST_DIR) && sha256sum $(TARBALL) > $(TARBALL).sha256

# build, then the ISO on top of it. What CI runs on a merge into main, next to
# `tarball`.
iso: build
	$(MAKE) -C iso build RELEASE_DIR=../$(RELEASE_DIR) DIST_DIR=../$(DIST_DIR) VERSION=$(VERSION)

# The one command that has to pass before anything is committed.
check:
	$(MAKE) -C runtime check
	$(MAKE) -C setup check
	$(MAKE) -C iso check

clean:
	$(MAKE) -C runtime clean
	rm -rf $(RELEASE_DIR) $(DIST_DIR)
