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

WORKSPACE        := OpenSky.xcworkspace
SCHEME           := OpenSky
CLI_SCHEME       := OpenSkyCLI
CONFIG           ?= Debug
DESTINATION      ?= platform=macOS
XCODEBUILD_FLAGS ?=
SWIFT_PATHS      := Sources Tests

# Build cache. It lives inside the checkout, not in Xcode's default under $HOME:
# this project's cache runs to tens of gigabytes, and the boot volume is small
# enough to fill mid-session. Every xcodebuild below passes it, and the tools/
# scripts read it from OPENSKY_DERIVED_DATA, so this is the only place to change.
DERIVED_DATA     ?= $(CURDIR)/DerivedData
XCODEBUILD_DD    := -derivedDataPath $(DERIVED_DATA)
export OPENSKY_DERIVED_DATA := $(DERIVED_DATA)
# Test result bundles. They live under the build cache rather than build/: xcodebuild
# watches the package root, and a result bundle growing there during `test` makes it
# re-resolve the package mid-run, which crashes it once the package is large (#582).
TEST_RESULTS     := $(DERIVED_DATA)/TestResults
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
xcb = xcodebuild -workspace $(WORKSPACE) -scheme $(1) -configuration $(2) \
	$(XCODEBUILD_DD) $(XCODEBUILD_FLAGS)
XCB_APP          := $(call xcb,$(SCHEME),$(CONFIG))
XCB_CLI          := $(call xcb,$(CLI_SCHEME),$(CONFIG))
XCB_RELEASE      := $(call xcb,$(SCHEME),Release)
XCB_TEST         := $(XCB_APP) -destination '$(DESTINATION)'
# Where xcodebuild puts built products. Derived rather than asked for, because
# `xcodebuild -showBuildSettings` costs several seconds per call.
PRODUCTS          = $(DERIVED_DATA)/Build/Products/$(CONFIG)
# The shaders compiled for the package test targets, which have no app bundle to
# load default.metallib from (tools/shader-library.sh). The unit test plan points
# at the same path as $(BUILD_DIR)/OpenSkyShaders.metallib.
SHADER_LIBRARY   := $(DERIVED_DATA)/Build/Products/OpenSkyShaders.metallib
export OPENSKY_SHADER_LIBRARY := $(SHADER_LIBRARY)
SHADER_SOURCES   := Sources/Shaders/Shaders.metal Sources/OpenSkyShaderTypes/ShaderTypes.h

# Test plans (Config/TestPlans/*.xctestplan) choose which test bundles a run builds and
# runs, instead of -only-testing flags (issue #346). Each plan holds exactly one
# bundle. The UI bundle must never share a plan with an app-hosted bundle
# (OpenSkyTests, OpenSkyRealDataTests): both would drive OpenSky.app at once
# and deadlock (issue #380).
UNIT_PLAN        := -testPlan UnitTests
UI_PLAN          := -testPlan UITests

# Formatter and linter configuration.
SWIFTFORMAT_CFG  := tools/format/.swiftformat
SWIFTLINT_CFG    := tools/lint/.swiftlint.yml
CLANGFORMAT_CFG  := tools/format/.clang-format
MD_CFG           := tools/markdown/.markdownlint-cli2.yaml
MD_GLOB          := **/*.md
METAL_FILES      := $(shell find Sources -name '*.metal' 2>/dev/null)

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
        no-game-content docs-links docs-length agent-files

fix: format lint ## Autoformat, then run every linter (the everyday gate)

check: swift-baseline format-check lint docs-links ## The same gate without writing files

format: swift-format metal-format md-format ## Autoformat Swift, Metal, and Markdown

format-check: ## Fail if anything is unformatted, without writing
	@swiftformat --lint --config $(SWIFTFORMAT_CFG) $(SWIFT_PATHS)
	@[ -z "$(METAL_FILES)" ] || xcrun clang-format --style=file:$(CLANGFORMAT_CFG) \
		--dry-run --Werror $(METAL_FILES)
	@markdownlint-cli2 --config $(MD_CFG) "$(MD_GLOB)"

lint: swift-lint md-lint sh-lint cli-boundary realdata-plan no-game-content docs-length agent-files ## Run every linter (warnings fail)

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

cli-boundary: ## Keep AppKit out of the engine and format sources the CLI also builds
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

agent-files: ## Check AGENTS.md symlinks and skill limits
	@./tools/lint/agent-files.sh

##@ Build checks

.PHONY: verify-build shader-library

# Every target compiled, no test run: OpenSkyTests, the app with
# OpenSkyRealDataTests, and openskycli. Catches a change that breaks a target it
# did not test. Incremental and served from the shared cache.
verify-build: vendor-link cache-link ## Compile app, CLI, and both unit bundles without running tests
	@$(XCB_RUN) verify-unit $(XCB_TEST) $(UNIT_PLAN) build-for-testing
	@$(XCB_RUN) verify-realdata $(XCB_TEST) -testPlan RealData build-for-testing
	@$(XCB_RUN) verify-cli $(XCB_CLI) build

shader-library: $(SHADER_LIBRARY) ## Compile the shaders the package tests load

# Rebuilt only when a shader source is newer, so a warm test run pays nothing.
$(SHADER_LIBRARY): $(SHADER_SOURCES)
	@./tools/shader-library.sh $@

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
	@rm -rf /Applications/OpenSky.app
	@ditto $(DERIVED_DATA)/Build/Products/Release/OpenSky.app /Applications/OpenSky.app
	@echo "[ OK ] /Applications/OpenSky.app updated"

app-path: ## Print the built OpenSky.app path [CONFIG]
	@echo "$(PRODUCTS)/OpenSky.app"

cli-path: ## Print the built openskycli path [CONFIG]
	@echo "$(PRODUCTS)/openskycli"

probe: ## Smoke-test the CLI against the local install (skips if absent)
	@./tools/probe.sh

icon: ## Regenerate the AppIcon PNGs from Sources/OpenSky/Resources/Branding/opensky-logo.svg
	@./tools/gen-appicon.sh

##@ Test

.PHONY: test test-fast test-one test-ui test-report test-sanitize test-perms

test: vendor-link cache-link $(SHADER_LIBRARY) ## Build and run the unit tests through the build system
	@bundle="$$($(RUN_DIR) -b $(TEST_RESULTS) unit)/unit.xcresult"; \
		TEST_RUNNER_OPENSKY_DATA_ROOT="$(OPENSKY_DATA_ROOT)" \
		$(XCB_RUN) test $(XCB_TEST) -resultBundlePath "$$bundle" \
		$(UNIT_PLAN) test

# Build once, then rerun against the cached .xctestrun without touching the build
# system: seconds instead of the ~80 of `make test` (issue #417). It rebuilds on
# its own when a source, Config/, or project file is newer; B=1 forces that. The
# default for every unit run, filtered or whole plan. A selector that names a
# package test target, T='OpenSkyFormatsCoreTests/...', runs that target alone through
# `swift test`, without the app host (issue #582).
test-fast: vendor-link cache-link $(SHADER_LIBRARY) ## Rerun tests without rebuilding [T='Suite/test()'] [B=1]
	@case "$(T)" in \
		"") ./tools/test-fast.sh $(if $(B),-B,) ;; \
		OpenSkyTests/* | OpenSkyRealDataTests/* | OpenSkyUITests/*) \
			./tools/test-fast.sh $(if $(B),-B,) -t "$(T)" ;; \
		*) target="$$(printf '%s' "$(T)" | cut -d/ -f1)"; \
			if [ -d "Tests/$$target" ]; then ./tools/test-package.sh "$(T)"; \
			else ./tools/test-fast.sh $(if $(B),-B,) -t "OpenSkyTests/$(T)"; fi ;; \
	esac

# A selector under OpenSkyUITests switches to the UI plan; anything else runs in
# the unit plan. Keeping the plans apart avoids the deadlock described above.
test-one: vendor-link cache-link $(SHADER_LIBRARY) ## Build and run one test: T=Class[/method] or T=Target/Class/method
	@test -n "$(T)" || { \
		echo "[ERROR] usage: make test-one T=ClassName[/methodName]"; \
		echo "        or: make test-one T=TargetName/ClassName/methodName"; \
		echo "        ClassName[/methodName] resolves under OpenSkyTests"; \
		exit 2; }
	@case "$(T)" in */*/* | OpenSky*Tests/*) spec="$(T)";; *) spec="OpenSkyTests/$(T)";; esac; \
	case "$$spec" in OpenSkyUITests/*) plan="$(UI_PLAN)";; *) plan="$(UNIT_PLAN)";; esac; \
	bundle="$$($(RUN_DIR) -b $(TEST_RESULTS) one)/one.xcresult"; \
	TEST_RUNNER_OPENSKY_DATA_ROOT="$(OPENSKY_DATA_ROOT)" \
		$(XCB_RUN) test-one $(XCB_TEST) -resultBundlePath "$$bundle" \
		$$plan -only-testing:"$$spec" test

test-ui: vendor-link cache-link ## Build and run the UI tests (launches and drives the app)
	@./tools/test-ui.sh \
		$(WORKSPACE) $(SCHEME) '$(DESTINATION)' $(XCODEBUILD_FLAGS)

test-report: ## Summarize the newest test result bundle, failures included
	@./tools/test-report.sh $(TEST_RESULTS)

# OpenSkyTests under TSan, then under ASan with UBSan (issue #383); the two cannot
# share a build. Too slow for routine runs, so run it periodically and
# before a milestone acceptance.
test-sanitize: vendor-link cache-link $(SHADER_LIBRARY) ## Run the unit tests under sanitizers [SAN=Thread|Address] [CAP=MB]
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
	@case "$(T)" in OpenSkyRealDataTests/*) spec="$(T)";; \
		*) spec="OpenSkyRealDataTests/$(T)";; esac; \
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
		-t 'OpenSkyRealDataTests/DynamicBodyRealDataTests/settlesAndPushesVanillaClutter()' \
		$(if $(CAP),-c $(CAP),)

realtest-npc-perf: vendor-link cache-link ## Measure NPC behavior graphs at the mover cap, optimized [CAP=MB]
	@./tools/realtest.sh -O \
		-t 'OpenSkyRealDataTests/NPCMovementRealDataTests/measuresVanillaGraphsAtMoverCap()' \
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
	@for dd in "$(DERIVED_DATA)" "$(DERIVED_DATA)-optimized"; do \
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
			-type d -name 'OpenSky-*' -exec rm -rf {} +; \
	fi
