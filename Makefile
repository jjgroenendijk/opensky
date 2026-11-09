# OpenSky - the one entry point for everything scripted (AGENTS.md). `make help`
# lists every target. A recipe is one command: the logic lives in a script under
# tools/ that takes arguments, so the Makefile reads as a table of what runs
# (docs/tools/build-system.md).

# The options, each with one meaning everywhere. Any other variable on the command
# line fails the run, so a mistyped option is not silently ignored.
OPTIONS := PLAN CONFIG T N COVERAGE SAN CAP DIFF_BASE ARGS XCODEBUILD_FLAGS
unknown := $(filter-out $(OPTIONS),$(foreach v,$(.VARIABLES),$(if $(filter command line,$(origin $(v))),$(v))))
$(if $(unknown),$(error unknown variable $(unknown); the options are: $(OPTIONS)))
export PLAN CONFIG T N COVERAGE SAN CAP DIFF_BASE XCODEBUILD_FLAGS

DERIVED_DATA   := $(shell . tools/build-env.sh && echo "$$OPENSKY_DERIVED_DATA")
PRODUCTS       := $(DERIVED_DATA)/Build/Products/$(or $(CONFIG),Debug)
RELEASE        := $(DERIVED_DATA)/Build/Products/Release
# The vendored libraries, built once in the main checkout and linked into worktrees.
VENDOR         := src/.vendor/ffmpeg/opensky-build-stamp src/.vendor/astcenc/opensky-build-stamp
ICON_SVG       := src/Sources/OpenSky/Resources/Branding/opensky-logo.svg
ICON_DIR       := src/Sources/OpenSky/Resources/Assets.xcassets/AppIcon.appiconset
# The Python tools are one uv project. The uv cache is on the boot disk and the
# project on the data volume, so uv copies instead of hard-linking.
UV_RUN         := UV_LINK_MODE=copy uv run --locked --quiet --project tools/wiki-mirror

.DEFAULT_GOAL := help
.PHONY: help bootstrap build-app build-cli build-tests compile install test test-rerun \
	test-package check-perms check fix format format-check lint lint-index dump-comments \
	apply-comments run-cli benchmark profile sample-launch probe rank-gaps sync-wiki \
	add-cli-command package-dmg render-icon prune clean setup-reference build-bridge

##@ Getting started

help: ## Show the targets and the options
	@awk -f tools/make-help.awk $(MAKEFILE_LIST)

bootstrap: ## Install the toolchain and build the vendored libraries, once per checkout
	@./tools/bootstrap.sh

##@ Build

build-app: | $(VENDOR) ## Build the app [CONFIG=Debug|Release]
	@./tools/build.sh app

build-cli: | $(VENDOR) ## Build openskycli [CONFIG=Debug|Release]
	@./tools/build.sh cli

build-tests: | $(VENDOR) ## Compile a plan's test bundles without running them [PLAN]
	@./tools/build.sh tests

compile: | $(VENDOR) ## swift build the changed package modules and their dependents [ARGS=modules]
	@./tools/compile-modules.sh $(ARGS)

install: | $(VENDOR) ## Build the Release app and CLI and copy them to /Applications
	@./tools/build.sh install

##@ Test

test: | $(VENDOR) ## Run a test plan [PLAN=Quick] [T] [N] [COVERAGE=1] [SAN] [CAP]
	@./tools/test.sh $(or $(PLAN),Quick)

test-rerun: ## Rerun the last built plan without the build system [PLAN] [T]
	@./tools/test-rerun.sh $(or $(PLAN),Quick)

test-package: | $(VENDOR) ## Run package test targets with swift test [T]
	@./tools/test-package.sh "$(T)"

check-perms: ## Check the one-time macOS permission grants the UI tests need
	@./tools/test-perms.sh

##@ Check and fix

check: ## Run every format check and lint, writing nothing (what CI runs)
	@./tools/run-checks.sh check

fix: ## Format every file, then run check
	@./tools/run-checks.sh format && ./tools/run-checks.sh check

format: ## Format every file
	@./tools/run-checks.sh format

format-check: ## The format half of check, as the CI Format job runs it
	@./tools/run-checks.sh format-check

lint: ## The lint half of check, as the CI Static checks job runs it
	@./tools/run-checks.sh lint

lint-index: | $(VENDOR) ## Build the index, then fail on unused code or an adapter that uses another
	@./tools/lint-index.sh

dump-comments: ## Print long comment blocks to rewrite in bulk [ARGS='-r src/Sources/X']
	@./tools/comment-blocks.sh dump $(ARGS)

apply-comments: ## Write rewritten comment blocks back [ARGS=spec-file]
	@./tools/comment-blocks.sh apply $(ARGS)

##@ Play and measure

run-cli: build-cli ## Build and run openskycli [ARGS='vfs ls']
	@"$(PRODUCTS)/openskycli" $(ARGS)

benchmark: ## Fly the benchmark tour in the Release app [ARGS='--preset quick']
	@./tools/benchmark.sh $(ARGS)

profile: ## Record a Time Profiler trace of the benchmark tour [ARGS]
	@./tools/profile.sh $(ARGS)

sample-launch: ## Sample the installed app's main thread through its first minute [ARGS=seconds]
	@./tools/launch-sample.sh "$(RELEASE)/openskycli" /Applications/OpenSky.app $(ARGS)

probe: build-cli ## Smoke-test the CLI against the local install (skips if absent)
	@./tools/probe.sh "$(PRODUCTS)/openskycli"

rank-gaps: ## Rank what the install uses and the engine does not do yet [ARGS='--only papyrus']
	@./tools/gaps.sh $(ARGS)

##@ Data and code tools

sync-wiki: ## Download or update an offline wiki in Markdown [ARGS='--site ck|uesp']
	@$(UV_RUN) wiki-mirror $(ARGS)

add-cli-command: ## Stub a new openskycli command [ARGS='light-probe World']
	@./tools/new-cli-command.sh $(ARGS)

##@ Release

package-dmg: ## Pack the Release app into a disk image [ARGS=OpenSky-<version>]
	@./tools/package-dmg.sh "$(RELEASE)/OpenSky.app" $(or $(ARGS),OpenSky)

render-icon: $(ICON_DIR)/icon_1024.png ## Render the AppIcon PNGs from the SVG logo

##@ Housekeeping

prune: ## Delete stale worktree caches and old run output [ARGS='--days 1 --dry-run']
	@./tools/prune.sh $(ARGS)

clean: ## Remove this checkout's build output [ARGS=--deep also drops the shared cache]
	@./tools/clean.sh $(ARGS)

##@ Reference game

setup-reference: ## Build the Wine prefix with Steam and a game copy [ARGS='<prefix> [<install>]']
	@./reference/setup.sh $(ARGS)

build-bridge: ## Install SKSE and build the bridge plugin [ARGS=<prefix>]
	@./reference/bridge/build.sh $(ARGS)

# The files the targets above produce, so make skips work that is done.

src/.vendor/ffmpeg/opensky-build-stamp: tools/vendor-ffmpeg.sh
	@./tools/link-shared.sh && ./tools/vendor-ffmpeg.sh && touch $@

src/.vendor/astcenc/opensky-build-stamp: tools/vendor-astcenc.sh
	@./tools/link-shared.sh && ./tools/vendor-astcenc.sh && touch $@

$(ICON_DIR)/icon_1024.png: $(ICON_SVG)
	@./tools/render-icon.sh $< $(ICON_DIR)
