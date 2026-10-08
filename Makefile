# The only task runner. CI runs these targets, so what holds at a desk holds
# there.
#
#   dist/arch-os-$(VERSION)/                       build: oak, oak.yaml, oak.sh, modules/
#   dist/arch-os-$(VERSION)-x86_64.tar.gz          tarball: that folder as one file
#   dist/arch-os-$(VERSION)-recovery/              image: recovery.efi, recovery.img
#   dist/arch-os-$(VERSION)-recovery-x86_64.tar    image: that folder as one file
#   dist/arch-os-$(VERSION)-x86_64.iso             image: the bootable image

# One bash per recipe, with -e, -u and pipefail. A failed file target is
# removed rather than left half written.
SHELL       := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DELETE_ON_ERROR:

# ////////////////////////////////////////////////////////////////////////////
# THE PRODUCT | What a release is called and what it holds
# ////////////////////////////////////////////////////////////////////////////

# What a release is. Oak looks for all of it beside its own binary.
APP           := oak
PRODUCT       := oak.yaml
PRODUCT_SHELL := oak.sh
MODULES_DIR   := modules

# The last release. The release run raises it; nobody writes it.
RELEASED := $(shell sed -n 's/^version:[[:space:]]*//p' $(PRODUCT))

# The same number as release-please remembers it, read back so the two cannot
# drift.
MANIFEST   := .release-please-manifest.json
REMEMBERED := $(shell sed -n 's/.*"\.":[[:space:]]*"\([^"]*\)".*/\1/p' $(MANIFEST))

# The next release: the one the open release pull request raises to, as origin
# was last fetched, or the smallest after the last. A release branch no newer
# than the last release is one already merged.
RELEASE_BRANCH := origin/release-please--branches--main
PENDING := $(shell git show $(RELEASE_BRANCH):$(MANIFEST) 2>/dev/null | sed -n 's/.*"\.":[[:space:]]*"\([^"]*\)".*/\1/p')
NEXT    := $(shell printf '%s\n' '$(RELEASED)' '$(PENDING)' | sort -V | tail -n1)
ifeq ($(NEXT),$(RELEASED))
NEXT := $(shell echo '$(RELEASED)' | awk -F. '{ print $$1 "." $$2 "." $$3 + 1 }')
endif

# What a build is named after: the release it is, which the run that tags it
# hands in as `VERSION=`, or the next release as a pre-release of it. Never a
# release's own number on anything else. Only the command line sets it.
ifneq ($(origin VERSION),command line)
VERSION := $(NEXT)-dev
endif

# The folders in modules/: adding a module is adding a folder.
MODULES := $(notdir $(wildcard $(MODULES_DIR)/*))

# What of a module goes into a release. A README and a linter's config do not.
MODULE_DECL  := module.yaml
MODULE_PARTS := data locales tasks actions

# ////////////////////////////////////////////////////////////////////////////
# OAK | The runtime this is built on
# ////////////////////////////////////////////////////////////////////////////

# https://github.com/murkl/oak, downloaded rather than built, and pinned so a
# commit builds the same tomorrow. Written without the `v` of its tag.
OAK_REPO    := murkl/oak
OAK_VERSION ?= 0.23.0
OAK_ASSET   := oak-linux-amd64
OAK_DIR     := .oak

# Named after its version, so raising OAK_VERSION fetches the new one.
OAK_BIN     := $(OAK_DIR)/oak-$(OAK_VERSION)
OAK_URL     := https://github.com/$(OAK_REPO)/releases/download/v$(OAK_VERSION)/$(OAK_ASSET)
OAK_API     := https://api.github.com/repos/$(OAK_REPO)/releases/tags/v$(OAK_VERSION)

# https even after a redirect, as get.sh fetches: -L alone would follow a 302
# into plain http.
CURL := curl --proto '=https' --proto-redir '=https' -Lf --progress-bar

# ////////////////////////////////////////////////////////////////////////////
# BUILD OUTPUT | One folder, everything a build leaves
# ////////////////////////////////////////////////////////////////////////////

DIST_DIR := dist

# The product under the name it unpacks to. Only x86_64 is built.
STEM        := arch-os-$(VERSION)
RELEASE_DIR := $(DIST_DIR)/$(STEM)
TARBALL     := $(STEM)-x86_64.tar.gz

# The Recovery image beside the release, and as one tar for the release page.
RECOVERY_DIR := $(STEM)-recovery
RECOVERY_TAR := $(STEM)-recovery-x86_64.tar

# A release's shape made of symlinks, so every check reads the files being
# edited.
DEV_DIR := .dev

# What `make run` opens: MODULE names one outright, ARGS is the rest.
MODULE ?=
ARGS   ?=

# ////////////////////////////////////////////////////////////////////////////
# THE IMAGES | Stock Arch profiles, patched to boot into this
# ////////////////////////////////////////////////////////////////////////////

# Scripts rather than targets, each taking what it works on as an argument.
ISO_DIR    := iso
ISO_BUILD  := $(ISO_DIR)/build.sh
ISO_SMOKE  := $(ISO_DIR)/smoke.sh
ISO_E2E    := $(ISO_DIR)/e2e.sh
ISO_GLYPHS := $(ISO_DIR)/glyphs.sh
ISO_FONT   := $(ISO_DIR)/font.sh

# The newest images, read when used, so `make iso && make smoke` needs no
# argument.
ISO      ?= $(shell ls -t $(DIST_DIR)/*.iso 2>/dev/null | head -1)
RECOVERY ?= $(shell ls -td $(DIST_DIR)/*-recovery 2>/dev/null | head -1)

# ////////////////////////////////////////////////////////////////////////////
# THE SCRIPTS | Everything checked, by the dialect it is written in
# ////////////////////////////////////////////////////////////////////////////

# POSIX sh: get.sh runs on whatever shell the downloading machine has.
POSIX_SCRIPTS := get.sh .github/settings.sh

# Bash: what builds and boots the images, and what they run.
ISO_SCRIPTS := $(ISO_BUILD) $(ISO_SMOKE) $(ISO_E2E) $(ISO_GLYPHS) $(ISO_FONT) $(wildcard $(ISO_DIR)/src/usr/local/bin/* $(ISO_DIR)/recovery/airootfs/usr/local/bin/*)

# Bash: what renders the pictures in docs/ onto a branch.
RELEASE_PICTURES := .github/pictures.sh

# Every module script with the library they share, and every module yaml.
MODULE_SCRIPTS = $(PRODUCT_SHELL) $(shell find $(MODULES_DIR) -name '*.sh')
MODULE_YAML    = $(shell find $(MODULES_DIR) -name '*.yaml')

# Shell a module ships into somebody's home, found by the name it lands under.
# zsh is read by its own shell, since shellcheck cannot.
MODULE_SHELL = $(wildcard $(MODULES_DIR)/*/tasks/@*/*/data/bashrc $(MODULES_DIR)/*/tasks/@*/*/data/aliases)
MODULE_ZSH   = $(wildcard $(MODULES_DIR)/*/tasks/@*/*/data/zshrc)

# A program a module ships, named outright: it has no extension to find it by.
MODULE_PROGRAMS := $(MODULES_DIR)/installer/tasks/@desktop/recovery-app/data/arch-os-recovery

# Everything a module can put on a screen. The READMEs and fastfetch's config,
# drawn for a graphical terminal, never reach a console.
MODULE_TEXT = $(PRODUCT_SHELL) $(shell find $(MODULES_DIR) -type f ! -name '*.md' ! -name fastfetch.jsonc)

# Each module's own check of the lookup tables it ships.
DATA_CHECKS = $(wildcard $(MODULES_DIR)/*/data/check.sh)

# ////////////////////////////////////////////////////////////////////////////
# HOUSEKEEPING
# ////////////////////////////////////////////////////////////////////////////

# Everything a build leaves. .oak/ is a dependency, not build output.
BUILD_OUTPUT := $(DIST_DIR) $(DEV_DIR) $(ISO_DIR)/archiso $(ISO_DIR)/download

# Empty when there is nothing to elevate, which is the case in CI.
SUDO := $(shell [ "$$(id -u)" -eq 0 ] || echo sudo)

# The pictures in docs/, generated so they cannot drift: the screenshots by
# driving the modules with --debug, the banner out of two of them. Which pages
# is docs/screenshots.yaml. On this machine they need chromium, imagemagick,
# python-pyte and python-yaml, so they stay out of `check`. CI renders the ones
# committed, onto the branch they describe - see .github/pictures.sh.
BANNER_CARDS   := docs/screenshots/installer.png docs/screenshots/installing.png
BANNER_TAGLINE := Install Arch Linux with ease - as a desktop or a TTY system. Installer and Recovery on one image.
BANNER_CELL    := 9

.PHONY: all oak oak-check build dev run inspect tarball image iso smoke e2e locales \
	locales-check glyphs-check data-check actions-check lint fmt check version-check version-name \
	secrets-check github screenshots banner docs clean

# build empties the release that everything packaging it reads.
.NOTPARALLEL:

all: build

# Downloaded once, checked against the digest GitHub publishes for the asset.
# The API allows sixty calls an hour per address without a token, so the call
# carries GITHUB_TOKEN where there is one. Read into a variable first, so a
# failed read and a missing checksum say different things.
$(OAK_BIN):
	@mkdir -p $(OAK_DIR)
	$(CURL) $(OAK_URL) -o $(OAK_DIR)/$(OAK_ASSET)
	@auth=(); \
	if [ -n "$${GITHUB_TOKEN:-}" ]; then auth=(--header "Authorization: Bearer $${GITHUB_TOKEN}"); fi; \
	release="$$($(CURL) -s "$${auth[@]}" $(OAK_API))" || { \
		echo "$(OAK_API) could not be read. A call that does not say who it is gets 60 an hour per address, and one GitHub will not accept gets none - set or correct GITHUB_TOKEN." >&2; \
		exit 1; \
	}; \
	digest="$$(printf '%s' "$$release" | awk -v asset='"name": "$(OAK_ASSET)"' \
		'index($$0, asset) { want = 1 } \
		 want && !seen && /"digest": *"sha256:/ { seen = 1; sub(/.*sha256:/, ""); sub(/".*/, ""); print }')"; \
	[ -n "$$digest" ] \
		|| { echo "$(OAK_REPO) publishes no checksum for $(OAK_ASSET) at v$(OAK_VERSION)" >&2; exit 1; }; \
	echo "$$digest  $(OAK_DIR)/$(OAK_ASSET)" | sha256sum -c -
	install -m 755 $(OAK_DIR)/$(OAK_ASSET) $@

# The pin asked of the binary rather than of its file name: a binary put in
# .oak/ by hand would otherwise ship, and the image would refuse its own
# modules at boot.
oak-check: $(OAK_BIN)
	@got="$$($(OAK_BIN) --version | sed -n 's/^runtime: //p')"; [ "$$got" = "$(OAK_VERSION)" ] \
		|| { echo "$(OAK_BIN) answers to '$$got', not $(OAK_VERSION) - run 'make oak'" >&2; exit 1; }

# Fetched again, for the same tag republished.
oak:
	rm -rf $(OAK_DIR)
	$(MAKE) oak-check

# oak.yaml under the name this build goes by, written beside and moved over
# whatever lies there, so a link in its place is replaced rather than written
# through to the source.
define stamp
sed 's/^version:.*/version: $(VERSION)/' $(PRODUCT) >$(1)/$(PRODUCT).part
grep -qx 'version: $(VERSION)' $(1)/$(PRODUCT).part
mv -f $(1)/$(PRODUCT).part $(1)/$(PRODUCT)
endef

# A name handed in is a version, and a release's number only on that release.
version-name:
	@echo "$(VERSION)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$$' \
		|| { echo "'$(VERSION)' is not a version" >&2; exit 1; }
	@case "$(VERSION)" in *-*|$(RELEASED)) ;; *) \
		echo "$(VERSION) is a release's number, and this is $(RELEASED) - a build is named after its own release or a pre-release of the next" >&2; exit 1 ;; esac

# The runtime, the product and a clean copy of every module. Templates, table
# checks and linter configs go out again: none of them runs.
build: oak-check version-name
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	install -m 755 $(OAK_BIN) $(RELEASE_DIR)/$(APP)
	$(call stamp,$(RELEASE_DIR))
	install -m 644 $(PRODUCT_SHELL) $(RELEASE_DIR)/$(PRODUCT_SHELL)
	for m in $(MODULES); do \
		dest=$(RELEASE_DIR)/$(MODULES_DIR)/$$m; \
		mkdir -p $$dest; \
		cp $(MODULES_DIR)/$$m/$(MODULE_DECL) $$dest/; \
		for part in $(MODULE_PARTS); do \
			[ -e $(MODULES_DIR)/$$m/$$part ] && cp -r $(MODULES_DIR)/$$m/$$part $$dest/ || true; \
		done; \
	done
	find $(RELEASE_DIR) \( -name '*.pot' -o -name 'check.sh' -o -name .shellcheckrc \) -delete

# The same shape without the build. The binary is copied, not linked: Oak
# resolves its own path before looking beside itself.
dev: oak-check
	@mkdir -p $(DEV_DIR)
	@$(call stamp,$(DEV_DIR))
	@ln -sfn ../$(PRODUCT_SHELL) $(DEV_DIR)/$(PRODUCT_SHELL)
	@ln -sfn ../$(MODULES_DIR) $(DEV_DIR)/$(MODULES_DIR)
	@install -m 755 $(OAK_BIN) $(DEV_DIR)/$(APP)

# Arch OS out of the sources.
run: dev
	cd $(DEV_DIR) && ./$(APP) $(if $(MODULE),--module=$(MODULE)) $(ARGS)

# Every module loaded as a run loads it, and the order it resolves to.
inspect: dev
	@cd $(DEV_DIR) && ./$(APP) --inspect

# The release as one file, for a stock Arch ISO: unpack it, run ./oak. Loaded
# again out of the file, so what ships is what was checked.
tarball: build
	tar -czf $(DIST_DIR)/$(TARBALL) --owner=0 --group=0 --sort=name \
		--transform 's,^,$(STEM)/,' \
		-C $(RELEASE_DIR) $(APP) $(PRODUCT) $(PRODUCT_SHELL) $(MODULES_DIR)
	unpacked="$$(mktemp -d)"; trap 'rm -rf "$$unpacked"' EXIT; \
	tar -xzf $(DIST_DIR)/$(TARBALL) -C "$$unpacked"; \
	"$$unpacked/$(STEM)/$(APP)" --inspect >/dev/null

# The images, out of the release already in dist/.
image:
	$(ISO_BUILD) $(CURDIR)/$(RELEASE_DIR)
	tar -cf $(DIST_DIR)/$(RECOVERY_TAR) --owner=0 --group=0 --sort=name \
		-C $(DIST_DIR) $(RECOVERY_DIR)

# The whole way there.
iso: build image

# Boots both images and waits for the interface. The frames land in dist/.
smoke:
	$(ISO_SMOKE) $(ISO)
	$(ISO_SMOKE) $(RECOVERY)

# Installs the newest ISO onto a disk, boots it, repairs it with the Recovery,
# boots it again and starts the Recovery on its partition. The logs land in
# dist/e2e/.
e2e:
	$(ISO_E2E) $(ISO)

# Every template rewritten and every catalog brought up to it: a changed text
# turns fuzzy, a removed one is dropped.
locales: dev
	for m in $(MODULES); do \
		pot=$(MODULES_DIR)/$$m/locales/$$m.pot; \
		(cd $(DEV_DIR) && ./$(APP) --strings --module=$$m) >$$pot; \
		for po in $(MODULES_DIR)/$$m/locales/*.po; do \
			[ -e "$$po" ] || continue; \
			msgmerge --quiet --update --backup=none --no-wrap "$$po" $$pot; \
			msgattrib --no-obsolete --no-wrap -o "$$po" "$$po"; \
		done; \
	done

# ////////////////////////////////////////////////////////////////////////////
# CHECKS | What has to pass before anything is committed
# ////////////////////////////////////////////////////////////////////////////

# A tag is matched against the version, so anything but X.Y.Z, or two files
# that disagree, is refused here rather than at a release.
version-check:
	@echo "$(RELEASED)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$$' \
		|| { echo "$(PRODUCT) declares '$(RELEASED)', which is not a version" >&2; exit 1; }
	@[ "$(RELEASED)" = "$(REMEMBERED)" ] \
		|| { echo "$(PRODUCT) says $(RELEASED), $(MANIFEST) says $(REMEMBERED) - the release run writes both" >&2; exit 1; }

# This is installed by piping a script into a shell.
secrets-check:
	gitleaks dir . --redact --no-banner

# A reworded text needs `make locales`, or no translator sees it.
locales-check: dev
	@for m in $(MODULES); do \
		pot=$(MODULES_DIR)/$$m/locales/$$m.pot; \
		(cd $(DEV_DIR) && ./$(APP) --strings --module=$$m) | diff -u $$pot - \
			|| { echo "$$pot is out of date - run 'make locales'" >&2; exit 1; }; \
		for po in $(MODULES_DIR)/$$m/locales/*.po; do \
			[ -e "$$po" ] || continue; \
			printf '%s: ' "$$po"; msgfmt --check-format --statistics -o /dev/null "$$po" || exit 1; \
		done; \
	done

# Module scripts are checked as Oak runs them: bash, with oak.sh in scope.
# zizmor runs offline, so a finding is about a change here. The greps:
#
#   - arch-chroot execs what it is given, so a shell builtin handed to it
#     exists nowhere
#   - a file written into the new system is a template, put in place by render
#   - bash fires no ERR trap for a command inverted with !, so such a line
#     checks nothing
lint:
	shellcheck -s sh -S style $(POSIX_SCRIPTS)
	shellcheck -S style $(ISO_SCRIPTS) $(RELEASE_PICTURES) $(MODULE_PROGRAMS)
	shellcheck -x -S style $(MODULE_SCRIPTS)
	shellcheck -s bash -S style -e SC1091 $(MODULE_SHELL)
	for file in $(MODULE_ZSH); do zsh -n "$$file"; done
	shfmt -d -ln posix -i 4 $(POSIX_SCRIPTS)
	shfmt -d -i 4 $(ISO_SCRIPTS) $(RELEASE_PICTURES) $(MODULE_PROGRAMS) $(MODULE_SCRIPTS) $(MODULE_SHELL)
	yamllint .
	actionlint
	zizmor --offline --persona auditor .github
	@! grep -nE 'arch-chroot [^|&;]*[[:space:]](command|type|hash|source|alias)[[:space:]]' \
		$(MODULE_SCRIPTS) $(MODULE_YAML) \
		|| { echo "a shell builtin cannot be run through arch-chroot - see has_command" >&2; exit 1; }
	@! grep -nE '^[[:space:]]*\}[[:space:]]*>>?[[:space:]]*"\$$\{MNT\}' $(MODULE_SCRIPTS) \
		|| { echo "a file written into the new system is a template beside its task, put in place with render - see oak.sh" >&2; exit 1; }
	@! grep -nE '^[[:space:]]*![[:space:]]' $(MODULE_SCRIPTS) \
		|| { echo "a command inverted with ! fails nothing under the ERR trap a script runs in - write it as an if that exits" >&2; exit 1; }

fmt:
	shfmt -w -ln posix -i 4 $(POSIX_SCRIPTS)
	shfmt -w -i 4 $(ISO_SCRIPTS) $(RELEASE_PICTURES) $(MODULE_PROGRAMS) $(MODULE_SCRIPTS) $(MODULE_SHELL)

# A console font holds one table of glyphs, and a character outside it is a box
# on screen. Asked of the runtime, after locales-check.
glyphs-check: oak-check
	@$(ISO_GLYPHS) $(OAK_BIN) $(MODULE_TEXT)

# Every name a module's tables hand to another program, against that program's
# own list. A wrong keymap, font or time zone reads fine and is silently
# ignored.
data-check:
	@for check in $(DATA_CHECKS); do $$check || exit 1; done

# An action two modules share is a folder in each, the same file for file.
actions-check:
	@for name in $$(basename -a $(MODULES_DIR)/*/actions/*/ | sort | uniq -d); do \
		set -- $(MODULES_DIR)/*/actions/$$name; first=$$1; shift; \
		for dir in "$$@"; do \
			diff -r $$first $$dir || { echo "$$dir differs from $$first" >&2; exit 1; }; \
		done; \
	done

# The whole gate, cheapest and loudest first. CI runs exactly this.
check: version-check secrets-check lint inspect actions-check locales-check data-check glyphs-check

# The repository's settings on GitHub, out of .github/settings/. Run by hand as
# an admin: a workflow may not change the rules it is held to.
github:
	.github/settings.sh

# ////////////////////////////////////////////////////////////////////////////
# DOCUMENTATION | The pictures the README is made of
# ////////////////////////////////////////////////////////////////////////////

screenshots: dev
	python3 docs/screenshots.py --product $(DEV_DIR)

banner:
	python3 docs/banner.py \
		--product $(PRODUCT) \
		--logo docs/logo.svg \
		$(foreach c,$(BANNER_CARDS),--card $(c)) \
		--tagline "$(BANNER_TAGLINE)" \
		--cell $(BANNER_CELL)

# The banner collages the screenshots, so it comes after them.
docs:
	$(MAKE) screenshots
	$(MAKE) banner

# mkarchiso writes as root. The plain removal comes first, so an ordinary clean
# asks for no password.
clean:
	rm -rf $(BUILD_OUTPUT) || $(SUDO) rm -rf $(BUILD_OUTPUT)
