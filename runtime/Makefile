APP     := runtime
PKG     := .
BIN_DIR := bin

# The version: the short commit SHA of HEAD, or "dev" outside a repository.
# `make run` appends "-dev" so it is obvious a binary did not come from a build
# of an actual commit.
VERSION     := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
VERSION_DEV := $(VERSION)-dev

GOOS   ?= linux
GOARCH ?= $(shell go env GOARCH)

# The version lives inside the binary, not in the filename: a stable name keeps
# download links and the ISO build working across builds.
BIN := $(BIN_DIR)/$(APP)-$(GOOS)-$(GOARCH)

LDFLAGS_BUILD := -s -w -X main.version=$(VERSION)
LDFLAGS_RUN   := -X main.version=$(VERSION_DEV)
GOFLAGS       := CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH)

# What this runtime is developed against: a runtime.yaml with a modules folder
# beside it, exactly as a release has. The source tree is not that shape — each
# component keeps its own declaration in its own folder — so `make dev` at the
# root lays it out in symlinks, and this runs against the sources themselves.
# MODULE opens one outright, the way `runtime --installer` does on a machine;
# without it the interface asks which.
#
# A build leaves its binary in bin/; putting a copy of it beside the modules is
# the release's business, not this one's — `make build` at the root, then
# `release/runtime`.
DIR    ?= ../.dev
MODULE ?=

# The template every catalog here is filled in from, and the catalogs
# themselves. Both are generated: the template out of the Go sources, the
# catalogs out of the template.
POT      := locales/runtime.pot
CATALOGS := $(wildcard locales/*.po)

.PHONY: all build run tidy tidy-check test test-race vet staticcheck vuln fmt fmt-check locales locales-check clean check release

all: build

# -dir because `go run` builds into a temporary folder, where none of this is
# beside the binary.
run:
	$(MAKE) -C .. dev
	go run -ldflags="$(LDFLAGS_RUN)" $(PKG) -dir $(DIR) $(MODULE)

build: $(BIN_DIR)
	$(GOFLAGS) go build -trimpath -ldflags="$(LDFLAGS_BUILD)" -o $(BIN) $(PKG)
	cd $(BIN_DIR) && sha256sum $(notdir $(BIN)) > $(notdir $(BIN)).sha256

release:
	$(MAKE) build GOOS=linux GOARCH=amd64

tidy:
	go mod tidy

# What `tidy` would change, said as an error instead of made as a change.
tidy-check:
	go mod tidy -diff

test:
	go test ./...

# The same tests under the race detector, which is built on cgo — asking for it
# explicitly turns a silently skipped check into a missing gcc. Not in `check`:
# it doubles a run that already takes a while. CI runs it on every push.
test-race:
	CGO_ENABLED=1 go test -race ./...

vet:
	go vet ./...

# Dead code, values that go nowhere, the mistakes vet does not look for.
staticcheck:
	staticcheck ./...

# Known vulnerabilities in what this imports. It asks a server, so it stays out
# of `check`. CI runs it on every push.
vuln:
	govulncheck ./...

# Reads every T("…") out of the sources and writes the template, then brings
# each catalog up to it. msgmerge keeps every translation whose source text is
# unchanged and marks the rest fuzzy rather than dropping it — a reworded
# sentence is a translation to look at again, not one to write from scratch.
locales:
	go run ./tools/potgen > $(POT)
	@for po in $(CATALOGS); do msgmerge --quiet --update --backup=none --no-wrap "$$po" $(POT); done

# A word added or reworded without `make locales` being run is a word no
# translator will ever be shown. And a translation that drops a placeholder is a
# message that breaks where it is printed rather than where it was written,
# which is the one thing about a catalog that cannot wait for somebody to
# notice.
#
# --statistics because nothing else ever counts these. A module's coverage is
# reported by `runtime -check`, which reads the module's own messages back out
# of it; the runtime's messages only exist in the template, which is
# deliberately not shipped — so an entry left empty or fuzzy here would
# otherwise reach a release with nobody having seen a number.
locales-check:
	@go run ./tools/potgen | diff -u $(POT) - \
		|| { echo "$(POT) is out of date — run 'make locales'" >&2; exit 1; }
	@for po in $(CATALOGS); do \
		printf '%s: ' "$$po"; \
		msgfmt --check-format --statistics -o /dev/null "$$po" || exit 1; \
	done

fmt:
	gofmt -s -w .

# gofmt asked as a question rather than made as an edit, so a branch that was
# never formatted fails here instead of arriving later as a diff nobody wrote.
fmt-check:
	@unformatted="$$(gofmt -s -l .)"; \
	[ -z "$$unformatted" ] || { echo "not gofmt'd:" >&2; echo "$$unformatted" >&2; exit 1; }

# What has to pass before anything is committed.
check: fmt-check tidy-check vet staticcheck locales-check test build

# There is deliberately no install target: the binary looks for its runtime.yaml
# beside itself, so a copy on $PATH with nothing next to it can only say there is
# nothing to run. What ships is the modules with the binary beside them.

clean:
	rm -rf $(BIN_DIR)

$(BIN_DIR):
	mkdir -p $@
