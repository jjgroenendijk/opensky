# OpenSky - the one entry point for everything scripted (AGENTS.md).
#
#   make help        list every target, grouped by task
#   make bootstrap   once per checkout: install tools
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
# Settings that must also reach package targets (Config/Build/Overrides.xcconfig).
# xcodebuild reads this variable, so every xcodebuild in make and tools/ gets it.
export XCODE_XCCONFIG_FILE := $(CURDIR)/Config/Build/Overrides.xcconfig
# Test result bundles. They live under the build cache rather than build/: xcodebuild
# watches the package root, and a result bundle growing there during `test` makes it
# re-resolve the package mid-run, which crashes it once the package is large (#582).
TEST_RESULTS     := $(DERIVED_DATA)/TestResults
# Xcode's default cache location. Only `make clean` uses it, to sweep what an
# Xcode GUI build or an older checkout left there.
XCODE_DERIVED_DATA ?= $(HOME)/Library/Developer/Xcode/DerivedData

# Every xcodebuild runs through this wrapper. It keeps the full transcript under
# logs/ and prints each diagnostic once, failures, and the final counts. It also
# clears stale module copies (tools/stale-modules.sh). OPENSKY_XCODEBUILD_RAW=1
# prints everything.
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
	$(XCODEBUILD_DD) $(COVERAGE_$(2)) $(XCODEBUILD_FLAGS)
# A test build compiles every target with coverage and a plain build does not, and
# both write the same package intermediates. So each Debug build turns coverage on,
# or `make cli` and `make test` rebuild each other's engine (issue #714). Only the
# command line wins over the setting each action picks; an xcconfig does not.
COVERAGE_Debug   := CLANG_COVERAGE_MAPPING=YES
XCB_APP          := $(call xcb,$(SCHEME),$(CONFIG))
XCB_CLI          := $(call xcb,$(CLI_SCHEME),$(CONFIG))
XCB_RELEASE      := $(call xcb,$(SCHEME),Release)
XCB_TEST         := $(XCB_APP) -destination '$(DESTINATION)'
# Where xcodebuild puts built products. Derived rather than asked for, because
# `xcodebuild -showBuildSettings` costs several seconds per call.
PRODUCTS          = $(DERIVED_DATA)/Build/Products/$(CONFIG)
# The shaders compiled for the package test targets, which have no app bundle to
# load default.metallib from. Fixtures find it through OPENSKY_SHADER_LIBRARY; the
# unit test plan points at the same path as $(BUILD_DIR)/OpenSkyShaders.metallib.
SHADER_LIBRARY   := $(DERIVED_DATA)/Build/Products/OpenSkyShaders.metallib
export OPENSKY_SHADER_LIBRARY := $(SHADER_LIBRARY)
SHADER_SOURCES   := Sources/Shaders/Shaders.metal Sources/OpenSkyShaderTypes/ShaderTypes.h
# Mirrors the Metal settings in Config/Build/*.xcconfig; change both together.
METAL_FLAGS      := -mmacosx-version-min=26.0 -fmetal-math-mode=fast -Werror \
	-I Sources/OpenSkyShaderTypes

# A docs page holds only what the code cannot show, so a long one usually repeats
# the code or the history. Prose wraps at 100 columns, so 400 lines is about
# twenty minutes of reading. Split or cut a page over it; do not raise it.
DOCS_MAX_LINES   := 400

ICON_SVG         := Sources/OpenSky/Resources/Branding/opensky-logo.svg
ICON_DIR         := Sources/OpenSky/Resources/Assets.xcassets/AppIcon.appiconset

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
# The tool commands. Linux CI overrides these two, because it has no xcrun and runs
# SwiftLint from its container image (docs/tools/ci.md).
SWIFTLINT        ?= swiftlint
CLANG_FORMAT     ?= xcrun clang-format
METAL_FILES      := $(shell find Sources -name '*.metal' 2>/dev/null)

.DEFAULT_GOAL := help

##@ Getting started

.PHONY: help bootstrap ffmpeg link-shared

help: ## Show this list
	@awk 'BEGIN { FS = ":.*## "; print "Usage: make <target> [VAR=value]" } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
		/^[a-z-]+:.*## / { printf "  \033[36m%-19s\033[0m %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)

bootstrap: ## Install the toolchain with Homebrew
	@./tools/bootstrap.sh

ffmpeg: ## Build the vendored decode-only LGPL ffmpeg into .vendor/ffmpeg
	@./tools/vendor-ffmpeg.sh

link-shared: ## Point this worktree's ffmpeg and compile cache at the main checkout's
	@./tools/link-shared.sh

##@ Format and lint

.PHONY: fix check format format-check swift-format-check metal-format-check lint \
        swift-baseline swift-format swift-lint metal-format md-format md-lint sh-lint \
        cli-boundary module-graph realdata-plan no-game-content docs-links docs-length \
        agent-files workflow-lint comment-length comment-blocks comment-apply

fix: format lint ## Autoformat, then run every linter (the everyday gate)

check: swift-baseline format-check lint docs-links ## The same gate without writing files

format: swift-format metal-format md-format ## Autoformat Swift, Metal, and Markdown

format-check: swift-format-check metal-format-check md-lint ## Fail if anything is unformatted, without writing

swift-format-check: ## Fail if any Swift is unformatted
	@swiftformat --lint --config $(SWIFTFORMAT_CFG) $(SWIFT_PATHS)

metal-format-check: ## Fail if any Metal shader is unformatted
	@[ -z "$(METAL_FILES)" ] || $(CLANG_FORMAT) --style=file:$(CLANGFORMAT_CFG) \
		--dry-run --Werror $(METAL_FILES)

lint: swift-lint md-lint sh-lint cli-boundary realdata-plan no-game-content docs-length agent-files workflow-lint ## Run every linter (warnings fail)
	@./tools/lint/module-graph.sh

swift-baseline: ## Check for Apple Swift 6.3.3+ and Swift 6 mode in every target
	@./tools/lint/swift-baseline.sh

swift-format: ## Autoformat Swift
	@swiftformat --config $(SWIFTFORMAT_CFG) $(SWIFT_PATHS)

swift-lint: ## Lint Swift strictly
	@$(SWIFTLINT) lint --strict --quiet --config $(SWIFTLINT_CFG) $(SWIFT_PATHS)

metal-format: ## Autoformat Metal shaders
	@[ -z "$(METAL_FILES)" ] || $(CLANG_FORMAT) --style=file:$(CLANGFORMAT_CFG) \
		-i $(METAL_FILES)

md-format: ## Autofix Markdown
	@markdownlint-cli2 --fix --config $(MD_CFG) "$(MD_GLOB)" || true

md-lint: ## Lint Markdown strictly
	@markdownlint-cli2 --config $(MD_CFG) "$(MD_GLOB)"

sh-lint: ## Shellcheck the tools/ scripts
	@shellcheck -s sh $$(find tools -type f -name '*.sh')

# Every Sources/ folder except OpenSky/ is built into or linked by OpenSkyCLI, so an
# app-only import there breaks the CLI build. This catches it without building.
cli-boundary: ## Keep AppKit out of the engine and format sources the CLI also builds
	@offenders=$$(grep -rlE '^[[:space:]]*import (AppKit|Cocoa|SwiftUI)' --include='*.swift' \
		$$(find Sources -mindepth 1 -maxdepth 1 -type d ! -name OpenSky) | sort); \
	if [ -n "$$offenders" ]; then \
		printf '[FAIL] app-only sources compiled into OpenSkyCLI:\n%s\n' "$$offenders" >&2; \
		echo 'Fix: move the file to Sources/OpenSky/ with git mv, or drop the import.' >&2; \
		exit 1; \
	fi; \
	echo "[ OK ] CLI target boundary clean"

module-graph: ## Check the package graph follows The Modular Architecture
	@./tools/lint/module-graph.sh

realdata-plan: ## Check every env-gated suite is in the RealData plan
	@./tools/lint/realdata-plan.sh \
		&& echo "[ OK ] real-data suites and the RealData plan line up"

no-game-content: ## Check no game assets or rendered captures are tracked
	@./tools/lint/no-game-content.sh && echo "[ OK ] no tracked game content"

docs-links: ## Check links inside docs/ resolve
	@./tools/check-docs-links.sh

docs-length: ## Check no docs page is longer than DOCS_MAX_LINES
	@find docs -name '*.md' -exec wc -l {} + | LC_ALL=C sort -k2 | awk -v max=$(DOCS_MAX_LINES) \
		'$$2 != "total" && $$1 > max { printf "[FAIL] %s has %s lines; the limit is %s. Split or cut it.\n", $$2, $$1, max; bad = 1 } \
		END { if (!bad) printf "[ OK ] docs pages within %s lines\n", max; exit bad }'

agent-files: ## Check AGENTS.md symlinks and the skill format limits
	@./tools/lint/agent-files.sh

workflow-lint: ## Lint the GitHub Actions workflows with actionlint
	@actionlint && echo "[ OK ] workflows clean"

comment-length: ## Report comment blocks over the line limit (report only for now)
	@./tools/lint/comment-length.sh

comment-blocks: ## Print long comment blocks to rewrite in bulk [PATHS='Sources/X'] [REFS=1]
	@./tools/comment-blocks.sh dump $(if $(REFS),-r,) $(PATHS)

comment-apply: ## Write rewritten blocks from a comment-blocks spec back [SPEC=file]
	@./tools/comment-blocks.sh apply "$(SPEC)"

##@ Build checks

.PHONY: compile verify-build shader-library

# swift build of the package modules the branch changed, or M='A B', plus their
# dependents. No Xcode, so it is the quick loop while fixing compile errors;
# Xcode-only code still needs verify-build.
compile: link-shared ## Compile changed package modules and their dependents [M='Module ...']
	@./tools/compile-modules.sh $(M)

# Every target compiled, no test run: OpenSkyTests, the app with
# OpenSkyRealDataTests, and openskycli. Catches a change that breaks a target it
# did not test. Incremental and served from the shared cache.
verify-build: link-shared ## Compile app, CLI, and both unit bundles without running tests
	@$(XCB_RUN) verify-unit $(XCB_TEST) $(UNIT_PLAN) build-for-testing
	@$(XCB_RUN) verify-realdata $(XCB_TEST) -testPlan RealData build-for-testing
	@$(XCB_RUN) verify-cli $(XCB_CLI) build

shader-library: $(SHADER_LIBRARY) ## Compile the shaders the package tests load

# Rebuilt only when a shader source is newer, so a warm test run pays nothing.
# Written to a temporary name first, so a failed compile never leaves a file that
# looks current to make.
$(SHADER_LIBRARY): $(SHADER_SOURCES)
	@mkdir -p $(@D)
	@xcrun -sdk macosx metal $(METAL_FLAGS) -o $@.tmp Sources/Shaders/Shaders.metal
	@mv $@.tmp $@ && echo "[ OK ] shader library: $@"

##@ Build and run

.PHONY: build cli run-cli install app-path cli-path probe icon

build: link-shared ## Build the app [CONFIG]
	@$(XCB_RUN) build $(XCB_APP) build

cli: link-shared ## Build the openskycli dev tool [CONFIG]
	@$(XCB_RUN) cli $(XCB_CLI) build

run-cli: cli ## Build and run openskycli, e.g. make run-cli ARGS="vfs ls"
	@"$(PRODUCTS)/openskycli" $(ARGS)

# Release shares the Debug cache directory (xcodebuild keeps the configurations
# apart inside it), so a repeat install builds incrementally.
install: link-shared ## Build the Release app and copy it to /Applications
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

icon: ## Regenerate the AppIcon PNGs from ICON_SVG (needs librsvg)
	@command -v rsvg-convert >/dev/null || { echo "[ERROR] rsvg-convert not found: brew install librsvg" >&2; exit 1; }
	@for size in 16 32 64 128 256 512 1024; do \
		rsvg-convert -w $$size -h $$size $(ICON_SVG) -o $(ICON_DIR)/icon_$$size.png || exit 1; \
	done; echo "[ OK ] $(ICON_DIR)"

##@ Test

.PHONY: test test-fast test-one test-ui test-report test-sanitize test-perms

test: link-shared $(SHADER_LIBRARY) ## Build and run the unit tests through the build system
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
test-fast: link-shared $(SHADER_LIBRARY) ## Rerun tests without rebuilding [T='Suite/test()'] [B=1]
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
test-one: link-shared $(SHADER_LIBRARY) ## Build and run one test: T=Class[/method] or T=Target/Class/method
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

test-ui: link-shared ## Build and run the UI tests (launches and drives the app)
	@./tools/test-ui.sh \
		$(WORKSPACE) $(SCHEME) '$(DESTINATION)' $(XCODEBUILD_FLAGS)

test-report: ## Summarize the newest test result bundle, failures included
	@./tools/test-report.sh $(TEST_RESULTS)

# OpenSkyTests under TSan, then under ASan with UBSan (issue #383); the two cannot
# share a build. Too slow for routine runs, so run it periodically and
# before a milestone acceptance.
test-sanitize: link-shared $(SHADER_LIBRARY) ## Run the unit tests under sanitizers [SAN=Thread|Address] [CAP=MB]
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
realtest: link-shared ## Run one real-data test: T='Class/method()' [CAP=MB] [B=1]
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

realtest-all: link-shared ## Run the whole real-data plan [CAP=MB]
	@./tools/realtest.sh $(if $(CAP),-c $(CAP),)

# `make test` never compiles the real-data suites, so a build break there used to
# stay hidden (issue #457). Compiling needs no install.
realdata-build: link-shared ## Compile the real-data suites without running them
	@$(XCB_RUN) realdata-build $(XCB_TEST) -testPlan RealData build-for-testing

# The perf gates build optimized, because -Onone makes tight simd code an order
# of magnitude slower (issue #392). They use their own cache directory,
# DerivedData-optimized/, so the Debug build survives.
realtest-perf: link-shared ## Run the physics perf gate on an optimized build [CAP=MB]
	@./tools/realtest.sh -O \
		-t 'OpenSkyRealDataTests/DynamicBodyRealDataTests/settlesAndPushesVanillaClutter()' \
		$(if $(CAP),-c $(CAP),)

realtest-npc-perf: link-shared ## Measure NPC behavior graphs at the mover cap, optimized [CAP=MB]
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
