# OpenSky - the one entry point for everything scripted (AGENTS.md).
#
#   make help        list every target, grouped by task
#   make bootstrap   once per checkout: install tools and wire the git hooks
#   make fix         autoformat, then run every linter
#   make test        build and run the unit tests
#
# Common knobs: CONFIG=Debug|Release, DERIVED_DATA=<dir>, XCODEBUILD_FLAGS='...'.

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

PROJECT          := opensky.xcodeproj
SCHEME           := opensky
CLI_SCHEME       := openskycli
CONFIG           ?= Debug
DESTINATION      ?= platform=macOS
XCODEBUILD_FLAGS ?=
SWIFT_PATHS      := opensky openskycli openskyTests openskyRealDataTests \
                    openskyTestSupport openskyUITests
TEST_RESULTS     := build/test-results

# Build cache. It lives inside the checkout, not in Xcode's default under $HOME:
# this project's cache runs to tens of gigabytes, and the boot volume is small
# enough to fill mid-session. Every xcodebuild below passes it, and the tools/
# scripts read it from OPENSKY_DERIVED_DATA, so this is the only place to change.
DERIVED_DATA     ?= $(CURDIR)/DerivedData
XCODEBUILD_DD    := -derivedDataPath $(DERIVED_DATA)
export OPENSKY_DERIVED_DATA := $(DERIVED_DATA)
# The dead-code scan's own build tree: uncached, so its index store is complete.
INDEX_DATA       ?= $(DERIVED_DATA)-index
export OPENSKY_INDEX_DATA := $(INDEX_DATA)
# Xcode's default cache location. Only `make clean` uses it, to sweep what an
# Xcode GUI build or an older checkout left there.
XCODE_DERIVED_DATA ?= $(HOME)/Library/Developer/Xcode/DerivedData

# Every xcodebuild runs through this wrapper. It keeps the full transcript under
# logs/ and prints only diagnostics, failures, and the final counts; a failing
# run prints everything. OPENSKY_XCODEBUILD_RAW=1 always prints everything.
XCB_RUN          := ./tools/xcodebuild-run.sh
# Allocates a per-run output directory, logs/<name>/<UTC timestamp>/, and points
# <name>/latest at it, so `make prune` can age whole runs out (issue #347).
RUN_DIR          := ./tools/run-dir.sh
# How many days of run output `make prune` keeps.
PRUNE_DAYS       ?= 14

# The shared xcodebuild command line: $(1) is the scheme, $(2) the configuration.
# Targets append only their action and their own flags, so the project, cache
# location, and XCODEBUILD_FLAGS cannot drift apart. tools/xcodebuild-lib.sh is
# the shell twin of this.
xcb = xcodebuild -project $(PROJECT) -scheme $(1) -configuration $(2) \
	$(XCODEBUILD_DD) $(XCODEBUILD_FLAGS)
# The same for the dead-code index tree: Debug, its own derived data, no cache.
xcb_index = xcodebuild -project $(PROJECT) -scheme $(1) -configuration Debug \
	-derivedDataPath $(INDEX_DATA) COMPILATION_CACHE_ENABLE_CACHING=NO \
	$(XCODEBUILD_FLAGS)
XCB_APP          := $(call xcb,$(SCHEME),$(CONFIG))
XCB_CLI          := $(call xcb,$(CLI_SCHEME),$(CONFIG))
XCB_RELEASE      := $(call xcb,$(SCHEME),Release)
XCB_TEST         := $(XCB_APP) -destination '$(DESTINATION)'
# Where xcodebuild puts built products. Derived rather than asked for, because
# `xcodebuild -showBuildSettings` costs several seconds per call.
PRODUCTS          = $(DERIVED_DATA)/Build/Products/$(CONFIG)

# Test plans (Config/*.xctestplan) choose which test bundles a run builds and
# runs, instead of -only-testing flags (issue #346). Each plan holds exactly one
# bundle. The UI bundle must never share a plan with an app-hosted bundle
# (openskyTests, openskyRealDataTests): both would drive opensky.app at once
# and deadlock (issue #380).
UNIT_PLAN        := -testPlan UnitTests
UI_PLAN          := -testPlan UITests

# Formatter and linter configuration.
SWIFTFORMAT_CFG  := tools/format/.swiftformat
SWIFTLINT_CFG    := tools/lint/.swiftlint.yml
CLANGFORMAT_CFG  := tools/format/.clang-format
MD_CFG           := tools/markdown/.markdownlint-cli2.yaml
MD_GLOB          := **/*.md
METAL_FILES      := $(shell find opensky openskycli -name '*.metal' 2>/dev/null)

.DEFAULT_GOAL := help

##@ Getting started

.PHONY: help bootstrap hooks ffmpeg vendor-link vendor-prune cache-link

help: ## Show this list
	@awk 'BEGIN { FS = ":.*## "; print "Usage: make <target> [VAR=value]" } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
		/^[a-z-]+:.*## / { printf "  \033[36m%-19s\033[0m %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)

bootstrap: ## Install the toolchain with Homebrew and wire the git hooks
	@./tools/bootstrap.sh

hooks: ## Point git at .githooks/hooks (safe to rerun)
	@git config core.hooksPath .githooks/hooks
	@find .githooks -type f \( -name '*.sh' -o -path '*/hooks/*' \) -exec chmod +x {} +
	@echo "[ OK ] core.hooksPath = .githooks/hooks"

ffmpeg: ## Build the vendored decode-only LGPL ffmpeg into .vendor/ffmpeg
	@./tools/vendor-ffmpeg.sh

vendor-link: ## Point this worktree's .vendor at the main checkout's copy
	@./tools/ffmpeg/link-vendor.sh

vendor-prune: ## Replace per-worktree .vendor copies with links (run when idle)
	@./tools/ffmpeg/prune-vendor.sh

cache-link: ## Point this worktree's compilation cache at the main checkout's
	@./tools/link-compile-cache.sh

##@ Format and lint

.PHONY: fix check format format-check lint swift-baseline swift-format swift-lint \
        metal-format md-format md-lint sh-lint cli-boundary realdata-plan \
        no-game-content docs-links docs-length

fix: format lint ## Autoformat, then run every linter (the everyday gate)

check: swift-baseline format-check lint docs-links ## The same gate without writing files

format: swift-format metal-format md-format ## Autoformat Swift, Metal, and Markdown

format-check: ## Fail if anything is unformatted, without writing
	@swiftformat --lint --config $(SWIFTFORMAT_CFG) $(SWIFT_PATHS)
	@[ -z "$(METAL_FILES)" ] || xcrun clang-format --style=file:$(CLANGFORMAT_CFG) \
		--dry-run --Werror $(METAL_FILES)
	@markdownlint-cli2 --config $(MD_CFG) "$(MD_GLOB)"

lint: swift-lint md-lint sh-lint cli-boundary realdata-plan no-game-content docs-length dup-check ## Run every linter (warnings fail)

swift-baseline: ## Check for Apple Swift 6.3.3+ and Swift 6 mode in every target
	@./tools/lint/swift-baseline.sh

swift-format: ## Autoformat Swift
	@swiftformat --config $(SWIFTFORMAT_CFG) $(SWIFT_PATHS)

swift-lint: ## Lint Swift strictly
	@swiftlint lint --strict --quiet --config $(SWIFTLINT_CFG) $(SWIFT_PATHS)

metal-format: ## Autoformat Metal shaders
	@[ -z "$(METAL_FILES)" ] || xcrun clang-format --style=file:$(CLANGFORMAT_CFG) \
		-i $(METAL_FILES)

md-format: ## Autofix Markdown
	@markdownlint-cli2 --fix --config $(MD_CFG) "$(MD_GLOB)" || true

md-lint: ## Lint Markdown strictly
	@markdownlint-cli2 --config $(MD_CFG) "$(MD_GLOB)"

sh-lint: ## Shellcheck the hooks and tools/ scripts
	@shellcheck -s sh $$(find .githooks tools -type f -name '*.sh') .githooks/hooks/*

cli-boundary: ## Keep AppKit out of opensky/Engine, which the CLI also builds
	@./tools/lint/cli-boundary.sh && echo "[ OK ] CLI target boundary clean"

realdata-plan: ## Check every env-gated suite is in the RealData plan
	@./tools/lint/realdata-plan.sh \
		&& echo "[ OK ] real-data suites and the RealData plan line up"

no-game-content: ## Check no game assets or rendered captures are tracked
	@./tools/lint/no-game-content.sh && echo "[ OK ] no tracked game content"

docs-links: ## Check links inside docs/ resolve
	@./tools/check-docs-links.sh

docs-length: ## Check no docs page is longer than the limit
	@./tools/lint/docs-length.sh

##@ Code smells

# Both scans compare against a baseline of the findings that were already in the
# tree, so they fail only on new ones; issue #569 tracks the existing ones
# (docs/decisions/code-smell-scans.md). dup-check reads sources only and is part
# of `make lint`. dead-code reads the compiler's index store, which a build
# served from the shared compilation cache leaves nearly empty, so it builds
# every target uncached into its own tree, INDEX_DATA. On demand, not on push.

.PHONY: dup-check dup-baseline dead-code dead-code-baseline dead-code-index verify-build

dup-check: ## Fail on new copy-pasted Swift (jscpd)
	@./tools/lint/duplicates.sh $(SWIFT_PATHS)

dup-baseline: ## Rewrite the duplication baseline after removing clones
	@./tools/lint/duplicates.sh -u $(SWIFT_PATHS)

dead-code: dead-code-index ## Build uncached, then fail on new unused code (Periphery)
	@./tools/lint/dead-code.sh

dead-code-baseline: dead-code-index ## Rewrite the unused-code baseline after a cleanup
	@./tools/lint/dead-code.sh -u

# The three builds whose index store Periphery reads, with the compilation cache
# off, because a cache hit skips writing index data. Its own tree, so it never
# invalidates the cached one. The first run in a worktree is a full build.
dead-code-index: vendor-link
	@$(XCB_RUN) dead-code-unit $(call xcb_index,$(SCHEME)) \
		-destination '$(DESTINATION)' $(UNIT_PLAN) build-for-testing
	@$(XCB_RUN) dead-code-realdata $(call xcb_index,$(SCHEME)) \
		-destination '$(DESTINATION)' -testPlan RealData build-for-testing
	@$(XCB_RUN) dead-code-cli $(call xcb_index,$(CLI_SCHEME)) build

# Every target compiled, no test run: openskyTests, the app with
# openskyRealDataTests, and openskycli. Catches a change that breaks a target it
# did not test. Incremental and served from the shared cache.
verify-build: vendor-link cache-link ## Compile app, CLI, and both unit bundles without running tests
	@$(XCB_RUN) verify-unit $(XCB_TEST) $(UNIT_PLAN) build-for-testing
	@$(XCB_RUN) verify-realdata $(XCB_TEST) -testPlan RealData build-for-testing
	@$(XCB_RUN) verify-cli $(XCB_CLI) build

##@ Build and run

.PHONY: build cli run-cli install app-path cli-path probe icon

build: vendor-link cache-link ## Build the app [CONFIG]
	@$(XCB_RUN) build $(XCB_APP) build

cli: vendor-link cache-link ## Build the openskycli dev tool [CONFIG]
	@$(XCB_RUN) cli $(XCB_CLI) build

run-cli: cli ## Build and run openskycli, e.g. make run-cli ARGS="vfs ls"
	@"$(PRODUCTS)/openskycli" $(ARGS)

# Release shares the Debug cache directory (xcodebuild keeps the configurations
# apart inside it), so a repeat install builds incrementally.
install: vendor-link cache-link ## Build the Release app and copy it to /Applications
	@$(XCB_RUN) install $(XCB_RELEASE) ARCHS=arm64 build
	@rm -rf /Applications/opensky.app
	@ditto $(DERIVED_DATA)/Build/Products/Release/opensky.app /Applications/opensky.app
	@echo "[ OK ] /Applications/opensky.app updated"

app-path: ## Print the built opensky.app path [CONFIG]
	@echo "$(PRODUCTS)/opensky.app"

cli-path: ## Print the built openskycli path [CONFIG]
	@echo "$(PRODUCTS)/openskycli"

probe: ## Smoke-test the CLI against the local install (skips if absent)
	@./tools/probe.sh

icon: ## Regenerate the AppIcon PNGs from opensky/App/Resources/Branding/opensky-logo.svg
	@./tools/gen-appicon.sh

##@ Test

.PHONY: test test-fast test-one test-ui test-report test-sanitize test-perms

test: vendor-link cache-link ## Build and run the unit tests through the build system
	@bundle="$$($(RUN_DIR) -b $(TEST_RESULTS) unit)/unit.xcresult"; \
		TEST_RUNNER_OPENSKY_DATA_ROOT="$(OPENSKY_DATA_ROOT)" \
		$(XCB_RUN) test $(XCB_TEST) -resultBundlePath "$$bundle" \
		$(UNIT_PLAN) test

# Build once, then rerun against the cached .xctestrun without touching the build
# system: seconds instead of the ~80 of `make test` (issue #417). It rebuilds on
# its own when a source, Config/, or project file is newer; B=1 forces that. The
# default for every unit run, filtered or whole plan.
test-fast: vendor-link cache-link ## Rerun tests without rebuilding [T='Suite/test()'] [B=1]
	@case "$(T)" in \
		"") ./tools/test-fast.sh $(if $(B),-B,) ;; \
		openskyTests/*) ./tools/test-fast.sh $(if $(B),-B,) -t "$(T)" ;; \
		*) ./tools/test-fast.sh $(if $(B),-B,) -t "openskyTests/$(T)" ;; \
	esac

# A selector under openskyUITests switches to the UI plan; anything else runs in
# the unit plan. Keeping the plans apart avoids the deadlock described above.
test-one: vendor-link cache-link ## Build and run one test: T=Class[/method] or T=Target/Class/method
	@test -n "$(T)" || { \
		echo "[ERROR] usage: make test-one T=ClassName[/methodName]"; \
		echo "        or: make test-one T=TargetName/ClassName/methodName"; \
		echo "        ClassName[/methodName] resolves under openskyTests"; \
		exit 2; }
	@case "$(T)" in */*/*) spec="$(T)";; *) spec="openskyTests/$(T)";; esac; \
	case "$$spec" in openskyUITests/*) plan="$(UI_PLAN)";; *) plan="$(UNIT_PLAN)";; esac; \
	bundle="$$($(RUN_DIR) -b $(TEST_RESULTS) one)/one.xcresult"; \
	TEST_RUNNER_OPENSKY_DATA_ROOT="$(OPENSKY_DATA_ROOT)" \
		$(XCB_RUN) test-one $(XCB_TEST) -resultBundlePath "$$bundle" \
		$$plan -only-testing:"$$spec" test

test-ui: vendor-link cache-link ## Build and run the UI tests (launches and drives the app)
	@./tools/test-ui.sh \
		$(PROJECT) $(SCHEME) '$(DESTINATION)' $(XCODEBUILD_FLAGS)

test-report: ## Summarize the newest test result bundle, failures included
	@./tools/test-report.sh $(TEST_RESULTS)

# openskyTests under TSan, then under ASan with UBSan (issue #383); the two cannot
# share a build. Too slow for routine runs, so run it periodically and
# before a milestone acceptance.
test-sanitize: vendor-link cache-link ## Run the unit tests under sanitizers [SAN=Thread|Address] [CAP=MB]
	@./tools/test-sanitize.sh $(if $(SAN),-o $(SAN),) $(if $(CAP),-c $(CAP),)

test-perms: ## Check the one-time macOS permission grants tests need
	@./tools/test-perms.sh

##@ Real-data tests (read the local Skyrim install)

# Running these suites needs the user's install, so it happens on demand and
# before a milestone acceptance, never on push or in CI, and always under the
# memory watchdog (CAP=MB sets its limit). realdata-build compiles them without
# running, and verify-build includes that.

.PHONY: realtest realtest-all realdata-build realtest-perf realtest-npc-perf

# One test through the fast path of test-fast (issue #417): a warm rerun pays
# only for the test itself.
realtest: vendor-link cache-link ## Run one real-data test: T='Class/method()' [CAP=MB] [B=1]
	@test -n "$(T)" || { \
		echo "[ERROR] usage: make realtest T='Class/method()' [CAP=MB]"; \
		echo "        selector must resolve to exactly one test (fully qualified)"; \
		echo "        e.g. make realtest T='CellRenderRealDataTests/streamsFiveByFiveGridToCompletion()'"; \
		echo "        whole set: make realtest-all"; \
		exit 2; }
	@case "$(T)" in openskyRealDataTests/*) spec="$(T)";; \
		*) spec="openskyRealDataTests/$(T)";; esac; \
	./tools/test-fast.sh -p RealData -t "$$spec" \
		$(if $(CAP),-c $(CAP),) $(if $(B),-B,)

realtest-all: vendor-link cache-link ## Run the whole real-data plan [CAP=MB]
	@./tools/realtest.sh $(if $(CAP),-c $(CAP),)

# `make test` never compiles the real-data suites, so a build break there used to
# stay hidden (issue #457). Compiling needs no install.
realdata-build: vendor-link cache-link ## Compile the real-data suites without running them
	@$(XCB_RUN) realdata-build $(XCB_TEST) -testPlan RealData build-for-testing

# The perf gates build optimized, because -Onone makes tight simd code an order
# of magnitude slower (issue #392). They use their own cache directory,
# DerivedData-optimized/, so the Debug build survives.
realtest-perf: vendor-link cache-link ## Run the physics perf gate on an optimized build [CAP=MB]
	@./tools/realtest.sh -O \
		-t 'openskyRealDataTests/DynamicBodyRealDataTests/settlesAndPushesVanillaClutter()' \
		$(if $(CAP),-c $(CAP),)

realtest-npc-perf: vendor-link cache-link ## Measure NPC behavior graphs at the mover cap, optimized [CAP=MB]
	@./tools/realtest.sh -O \
		-t 'openskyRealDataTests/NPCMovementRealDataTests/measuresVanillaGraphsAtMoverCap()' \
		$(if $(CAP),-c $(CAP),)

##@ Housekeeping

.PHONY: prune clean

# `clean` empties this checkout. `prune` reaches what no checkout owns any more,
# chiefly the caches of removed worktrees, which is what fills the data volume.
prune: ## Delete stale worktree caches and old run output [PRUNE_DAYS=14] [DRY_RUN=1]
	@./tools/prune.sh --days $(PRUNE_DAYS) $(if $(DRY_RUN),--dry-run,)

# Keeps DerivedData/CompilationCache.noindex. Its entries are keyed on the full
# compile command and inputs, so they cannot go stale, and keeping them makes the
# next Debug build take about 18 seconds instead of 45 (issue #341). DEEP=1
# removes it too, for timing a truly cold build. In a linked worktree it is a link
# to the main checkout's shared store, and DEEP=1 removes only the link.
clean: ## Remove build output and caches [DEEP=1 also drops the compile cache]
	@rm -rf build
	@for dd in "$(DERIVED_DATA)" "$(DERIVED_DATA)-optimized" "$(INDEX_DATA)"; do \
		[ -d "$$dd" ] || continue; \
		if [ -n "$(DEEP)" ]; then \
			rm -rf "$$dd"; \
		else \
			find "$$dd" -mindepth 1 -maxdepth 1 \
				! -name 'CompilationCache.noindex' -exec rm -rf {} +; \
		fi; \
	done
	@if [ -d "$(XCODE_DERIVED_DATA)" ]; then \
		find "$(XCODE_DERIVED_DATA)" -mindepth 1 -maxdepth 1 \
			-type d -name 'opensky-*' -exec rm -rf {} +; \
	fi
