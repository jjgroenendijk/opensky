# OpenSky - the one entry point for everything scripted (AGENTS.md).
#
#   make help        list the main targets, grouped by task (ALL=1 lists every one)
#   make bootstrap   once per checkout: install tools
#   make fix         autoformat, then run every linter
#   make test-unit   build and run the unit tests
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
# The unused-code scan's own build tree: uncached, so its index store is complete.
INDEX_DATA       ?= $(DERIVED_DATA)-index
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
	$(XCODEBUILD_DD) $(COVERAGE_$(2)) $(ARCHS_$(2)) $(XCODEBUILD_FLAGS)
# A test build compiles every target with coverage and a plain build does not, and
# both write the same package intermediates. So each Debug build turns coverage on,
# or `make cli` and `make test` rebuild each other's engine (issue #714). Only the
# command line wins over the setting each action picks; an xcconfig does not.
COVERAGE_Debug   := CLANG_COVERAGE_MAPPING=YES
# Apple Silicon only. Release would also compile x86_64, where Float16 does not
# exist. ARCHS in Overrides.xcconfig still left package targets on x86_64.
ARCHS_Release    := ARCHS=arm64
# The same for the index tree: Debug, its own derived data, no compilation cache,
# because a task replayed from the cache writes no index data.
xcb_index = xcodebuild -workspace $(WORKSPACE) -scheme $(1) -configuration Debug \
	-derivedDataPath $(INDEX_DATA) COMPILATION_CACHE_ENABLE_CACHING=NO \
	$(COVERAGE_Debug) $(XCODEBUILD_FLAGS)
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

# Line coverage each OpenSkyFormats* module keeps in a `make test` run: the value
# measured when the floor was set, rounded down to a multiple of 5. Raise it when
# coverage grows; lower it only with a reason in the commit.
COVERAGE_FLOOR   := 80

ICON_SVG         := Sources/OpenSky/Resources/Branding/opensky-logo.svg
ICON_DIR         := Sources/OpenSky/Resources/Assets.xcassets/AppIcon.appiconset

# Test plans (Config/TestPlans/*.xctestplan) choose which test bundles a run builds and
# runs, instead of -only-testing flags (issue #346). Each plan holds exactly one
# bundle. The UI bundle must never share a plan with an app-hosted bundle
# (OpenSkyTests, OpenSkyRealDataTests): both would drive OpenSky.app at once
# and deadlock (issue #380). The unit plan's Locale configuration runs only through
# `make test-locale`, so every other run names the Unit configuration.
UNIT_PLAN        := -testPlan UnitTests -only-test-configuration Unit

# Formatter and linter configuration.
SWIFTFORMAT_CFG  := tools/format/.swiftformat
SWIFTLINT_CFG    := tools/lint/.swiftlint.yml
JSCPD_CFG        := tools/lint/.jscpd.json
PERIPHERY_CFG    := tools/lint/.periphery.yml
CLANGFORMAT_CFG  := tools/format/.clang-format
MD_CFG           := tools/markdown/.markdownlint-cli2.yaml
MD_GLOB          := **/*.md
# The tool commands. Override one to try another build of the tool.
SWIFTLINT        ?= swiftlint
CLANG_FORMAT     ?= xcrun clang-format
METAL_FILES      := $(shell find Sources -name '*.metal' 2>/dev/null)

.DEFAULT_GOAL := help

##@ Getting started

.PHONY: help bootstrap ffmpeg link-shared

# A `#|` target is a part of a listed one, such as each check inside `lint`.
help: ## Show the main targets [ALL=1 also lists the parts]
	@awk -v all="$(ALL)" 'BEGIN { FS = ":.*#[#|] "; print "Usage: make <target> [VAR=value]" } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
		/^[a-z-]+:.*## / || (all != "" && /^[a-z-]+:.*#\| /) \
			{ printf "  \033[36m%-19s\033[0m %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)

bootstrap: ## Install the toolchain with Homebrew
	@./tools/bootstrap.sh

ffmpeg: #| Build the vendored decode-only LGPL ffmpeg into .vendor/ffmpeg
	@./tools/vendor-ffmpeg.sh

link-shared: #| Point this worktree's ffmpeg and compile cache at the main checkout's
	@./tools/link-shared.sh

##@ Format and lint

.PHONY: fix check format format-check swift-format-check metal-format-check lint \
        swift-baseline swift-format swift-lint metal-format md-format md-lint sh-lint \
        cli-boundary module-graph realdata-plan lint-test-plans lint-test-tags lint-test-targets no-game-content \
        docs-links docs-length agent-files workflow-lint comment-length panel-text comment-blocks comment-apply \
        duplicates no-suppressions

fix: format lint ## Autoformat, then run every linter (the everyday gate)

check: swift-baseline format-check lint docs-links ## The same gate without writing files

format: swift-format metal-format md-format ## Autoformat Swift, Metal, and Markdown

format-check: swift-format-check metal-format-check md-lint #| Fail if anything is unformatted, without writing

swift-format-check: #| Fail if any Swift is unformatted
	@swiftformat --lint --config $(SWIFTFORMAT_CFG) $(SWIFT_PATHS)

metal-format-check: #| Fail if any Metal shader is unformatted
	@[ -z "$(METAL_FILES)" ] || $(CLANG_FORMAT) --style=file:$(CLANGFORMAT_CFG) \
		--dry-run --Werror $(METAL_FILES)

lint: swift-lint md-lint sh-lint cli-boundary realdata-plan lint-test-plans lint-test-tags lint-test-targets no-game-content docs-length agent-files workflow-lint comment-length panel-text duplicates no-suppressions ## Run every linter (warnings fail)
	@./tools/lint/module-graph.sh

swift-baseline: #| Check for Apple Swift 6.3.3+ and Swift 6 mode in every target
	@./tools/lint/swift-baseline.sh

swift-format: #| Autoformat Swift
	@swiftformat --config $(SWIFTFORMAT_CFG) $(SWIFT_PATHS)

swift-lint: #| Lint Swift strictly
	@$(SWIFTLINT) lint --strict --quiet --config $(SWIFTLINT_CFG) $(SWIFT_PATHS)

metal-format: #| Autoformat Metal shaders
	@[ -z "$(METAL_FILES)" ] || $(CLANG_FORMAT) --style=file:$(CLANGFORMAT_CFG) \
		-i $(METAL_FILES)

md-format: #| Autofix Markdown
	@markdownlint-cli2 --fix --config $(MD_CFG) "$(MD_GLOB)" || true

md-lint: #| Lint Markdown strictly
	@markdownlint-cli2 --config $(MD_CFG) "$(MD_GLOB)"

sh-lint: #| Shellcheck the tools/ scripts
	@shellcheck -s sh $$(find tools -type f -name '*.sh')

# Every Sources/ folder except OpenSky/ is built into or linked by OpenSkyCLI, so an
# app-only import there breaks the CLI build. This catches it without building.
cli-boundary: #| Keep AppKit out of the engine and format sources the CLI also builds
	@offenders=$$(grep -rlE '^[[:space:]]*import (AppKit|Cocoa|SwiftUI)' --include='*.swift' \
		$$(find Sources -mindepth 1 -maxdepth 1 -type d ! -name OpenSky) | sort); \
	if [ -n "$$offenders" ]; then \
		printf '[FAIL] app-only sources compiled into OpenSkyCLI:\n%s\n' "$$offenders" >&2; \
		echo 'Fix: move the file to Sources/OpenSky/ with git mv, or drop the import.' >&2; \
		exit 1; \
	fi; \
	echo "[ OK ] CLI target boundary clean"

module-graph: #| Check the package graph follows The Modular Architecture
	@./tools/lint/module-graph.sh

realdata-plan: #| Check every env-gated suite is in the RealData plan
	@./tools/lint/realdata-plan.sh \
		&& echo "[ OK ] real-data suites and the RealData plan line up"

lint-test-plans: #| Check every test plan sets timeouts and selects by target or tag
	@./tools/lint/test-plans.sh && echo "[ OK ] test plans follow the rules"

lint-test-targets: #| Check every Makefile target that runs tests is named test-<kind>
	@./tools/lint/test-targets.sh && echo "[ OK ] test targets are named test-<kind>"

lint-test-tags: #| Check suites carry the shared tags and .disabled names an issue [FIX=1]
	@./tools/lint/test-tags.sh $(if $(FIX),--fix,) && echo "[ OK ] suites carry their tags"

no-game-content: #| Check no game assets or rendered captures are tracked
	@./tools/lint/no-game-content.sh && echo "[ OK ] no tracked game content"

docs-links: #| Check links inside docs/ resolve
	@./tools/check-docs-links.sh

docs-length: #| Check no docs page is longer than DOCS_MAX_LINES
	@find docs -name '*.md' -exec wc -l {} + | LC_ALL=C sort -k2 | awk -v max=$(DOCS_MAX_LINES) \
		'$$2 != "total" && $$1 > max { printf "[FAIL] %s has %s lines; the limit is %s. Split or cut it.\n", $$2, $$1, max; bad = 1 } \
		END { if (!bad) printf "[ OK ] docs pages within %s lines\n", max; exit bad }'

agent-files: #| Check AGENTS.md symlinks and the skill format limits
	@./tools/lint/agent-files.sh

workflow-lint: #| Lint the GitHub Actions workflows with actionlint
	@actionlint && echo "[ OK ] workflows clean"

comment-length: #| Check no comment block is over the line limit
	@./tools/lint/comment-length.sh

panel-text: #| Check app panels hold no prose paragraphs or long tooltips
	@./tools/lint/panel-text.sh

# The whole tree in under a second. A scan of changed files only would miss a new
# copy of code that did not change.
duplicates: #| Check for duplicated Swift blocks (jscpd)
	@./tools/lint/duplicates.sh $(JSCPD_CFG) $(SWIFT_PATHS)

# Fix the finding instead (docs/decisions/code-health-automation.md).
no-suppressions: #| Check no Swift file disables a SwiftLint rule
	@offenders=$$(grep -rn 'swiftlint:disable' --include='*.swift' $(SWIFT_PATHS)); \
	if [ -n "$$offenders" ]; then \
		printf '[FAIL] SwiftLint suppressions:\n%s\n' "$$offenders" >&2; \
		echo 'Fix: change the code so the rule passes, then drop the comment.' >&2; \
		exit 1; \
	fi; \
	echo "[ OK ] no SwiftLint suppressions"

comment-blocks: #| Print long comment blocks to rewrite in bulk [PATHS='Sources/X'] [REFS=1]
	@./tools/comment-blocks.sh dump $(if $(REFS),-r,) $(PATHS)

comment-apply: #| Write rewritten blocks from a comment-blocks spec back [SPEC=file]
	@./tools/comment-blocks.sh apply "$(SPEC)"

##@ Build checks

.PHONY: compile verify-build shader-library

# swift build of the package modules the branch changed, or M='A B', plus their
# dependents. No Xcode, so it is the quick loop while fixing compile errors;
# Xcode-only code still needs verify-build.
compile: link-shared ## Compile changed package modules and their dependents [M='Module ...']
	@./tools/compile-modules.sh $(M)

# The app, openskycli, and the unit bundles compiled, no test run. Catches a change
# that breaks a target it did not test; realdata-build does the same for the
# real-data suites. The OpenSky scheme builds openskycli for testing, so the CLI
# shares the test builds' context. A separate OpenSkyCLI build recompiles the
# engine (issue #717).
verify-build: link-shared ## Compile the app, the CLI, and the unit bundles without running tests
	@$(XCB_RUN) verify-build $(XCB_TEST) $(UNIT_PLAN) build-for-testing

shader-library: $(SHADER_LIBRARY) #| Compile the shaders the package tests load

# Rebuilt only when a shader source is newer, so a warm test run pays nothing.
# Written to a temporary name first, so a failed compile never leaves a file that
# looks current to make.
$(SHADER_LIBRARY): $(SHADER_SOURCES)
	@mkdir -p $(@D)
	@xcrun -sdk macosx metal $(METAL_FLAGS) -o $@.tmp Sources/Shaders/Shaders.metal
	@mv $@.tmp $@ && echo "[ OK ] shader library: $@"

##@ Code health

.PHONY: health health-index

# Periphery reads the index store the compiler writes. The index tree is built
# uncached, so its first run in a checkout is a full build; later runs are
# incremental. The OpenSky scheme builds openskycli for testing, so the two plans
# cover the app, the CLI, and every test bundle.
health: health-index ## Build the index, then fail on any unused code (Periphery)
	@./tools/lint/unused-code.sh $(PERIPHERY_CFG) "$(INDEX_DATA)/Index.noindex/DataStore"

health-index: link-shared
	@$(XCB_RUN) health-unit $(call xcb_index,$(SCHEME)) \
		-destination '$(DESTINATION)' $(UNIT_PLAN) build-for-testing
	@$(XCB_RUN) health-realdata $(call xcb_index,$(SCHEME)) \
		-destination '$(DESTINATION)' -testPlan RealData build-for-testing

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
	@$(XCB_RUN) install $(XCB_RELEASE) build
	@rm -rf /Applications/OpenSky.app
	@ditto $(DERIVED_DATA)/Build/Products/Release/OpenSky.app /Applications/OpenSky.app
	@echo "[ OK ] /Applications/OpenSky.app updated"

app-path: #| Print the built OpenSky.app path [CONFIG]
	@echo "$(PRODUCTS)/OpenSky.app"

cli-path: #| Print the built openskycli path [CONFIG]
	@echo "$(PRODUCTS)/openskycli"

probe: ## Smoke-test the CLI against the local install (skips if absent)
	@./tools/probe.sh

icon: #| Regenerate the AppIcon PNGs from ICON_SVG (needs librsvg)
	@command -v rsvg-convert >/dev/null || { echo "[ERROR] rsvg-convert not found: brew install librsvg" >&2; exit 1; }
	@for size in 16 32 64 128 256 512 1024; do \
		rsvg-convert -w $$size -h $$size $(ICON_SVG) -o $(ICON_DIR)/icon_$$size.png || exit 1; \
	done; echo "[ OK ] $(ICON_DIR)"

##@ Test

# Each kind of test has one target named test-<kind> (tools/lint/test-targets.sh).
# Each is one plain `xcodebuild test` call on one test plan, so Xcode decides what
# runs. T adds -only-testing. A typo in T runs zero tests and still passes.

.PHONY: test-unit test-ui test-sanitize test-real test-report test-perms coverage-floor \
        realdata-build sanitizer-shaders profile

# The result bundle of one run, in its own run directory (issue #347).
test_bundle = -resultBundlePath "$$($(RUN_DIR) -b $(TEST_RESULTS) $(1))/$(1).xcresult"
# -only-testing for T. A T that does not start with an OpenSky*Tests target
# resolves under the bundle in $(1).
only_testing = $(if $(T),-only-testing:'$(if $(filter OpenSky%Tests,$(firstword \
	$(subst /, ,$(T)))),,$(1)/)$(T)')
# One test host, watched by the memory watchdog: a real-data run once reached
# 30 GB and locked the machine. $(1) is the default cap in MB, CAP overrides it.
guarded = sh tools/memguard.sh $(or $(CAP),$(1)) 10800 & guard=$$!; \
	trap 'kill $$guard 2>/dev/null' EXIT INT TERM; \
	$(2) -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
# The perf gates measure the engine, not -Onone, so they build optimized in their
# own cache, which keeps the Debug build (issue #392).
XCB_PERF         := xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) \
	-configuration Debug -derivedDataPath $(DERIVED_DATA)-optimized \
	-destination '$(DESTINATION)' $(XCODEBUILD_FLAGS) \
	SWIFT_OPTIMIZATION_LEVEL=-O GCC_OPTIMIZATION_LEVEL=s \
	SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG OPENSKY_OPTIMIZED"

# The unit plan by default. TAG runs one tag plan across every unit target, and
# LOCALE=nl the unit plan in Dutch, where the decimal separator is a comma.
# N hunts a flaky test: it reruns until the first failure, at most N times.
unit_plan = $(if $(TAG),-testPlan $(or $(UNIT_TAG_PLAN_$(TAG)),$(error TAG must be parser or gpu)), \
	-testPlan UnitTests -only-test-configuration $(if $(LOCALE),$(or $(UNIT_LOCALE_$(LOCALE)), \
	$(error LOCALE must be nl)),Unit))
UNIT_TAG_PLAN_parser := Parser
UNIT_TAG_PLAN_gpu    := GPU
UNIT_LOCALE_nl       := Locale
test-unit: link-shared $(SHADER_LIBRARY) ## Run the unit plan [T='Suite/test()'] [N=100] [TAG=parser|gpu] [LOCALE=nl]
	@TEST_RUNNER_OPENSKY_DATA_ROOT="$(OPENSKY_DATA_ROOT)" \
		$(XCB_RUN) test-unit $(XCB_TEST) $(call test_bundle,unit$(if $(TAG),-$(TAG))$(if $(LOCALE),-$(LOCALE))) \
		$(unit_plan) $(call only_testing,OpenSkyTests) \
		$(if $(N),-run-tests-until-failure -test-iterations $(N)) test

# A timeout in "enabling automation mode" means Automation Mode asks for a
# password: run make test-perms.
test-ui: link-shared ## Run the UI tests (launches and drives the app) [T='Suite/test()']
	@$(XCB_RUN) test-ui $(XCB_TEST) $(call test_bundle,ui) -testPlan UITests \
		$(call only_testing,OpenSkyUITests) test

# The sanitized builds have their own BUILD_DIR, and the plan finds the shaders
# through $(BUILD_DIR). The shaders are not sanitized, so each gets a copy.
sanitizer-shaders: $(SHADER_LIBRARY)
	@for variant in Variant-TSan Variant-ASan-UBSan; do \
		mkdir -p "$(DERIVED_DATA)/Build/Products/$$variant" && \
		cp "$(SHADER_LIBRARY)" "$(DERIVED_DATA)/Build/Products/$$variant/" || exit 1; \
	done

# TSan and ASan with UBSan cannot share a build (issue #383), so SAN picks one. Too
# slow for routine runs, so run them periodically and before a milestone acceptance.
SANITIZER_CONFIG_thread  := Thread
SANITIZER_CONFIG_address := Address
test-sanitize: link-shared sanitizer-shaders ## Run the unit tests under a sanitizer SAN=thread|address [CAP=MB]
	@$(call guarded,12288,$(XCB_RUN) test-sanitize-$(SAN) $(XCB_TEST) \
		$(call test_bundle,sanitize-$(SAN)) -testPlan Sanitizers -only-test-configuration \
		$(or $(SANITIZER_CONFIG_$(SAN)),$(error SAN must be thread or address)))

# Real-data tests read the user's install, so they run on demand and before a
# milestone acceptance, never in CI. The plan holds the install path. PERF=1 runs
# the Perf plan, which selects the real-data tests tagged `.perf`, built optimized.
test-real: link-shared ## Run the real-data plan [T='Suite/test()'] [CAP=MB] [PERF=1]
	@$(call guarded,6144,$(if $(PERF), \
		$(XCB_RUN) test-perf $(XCB_PERF) $(call test_bundle,perf) -testPlan Perf, \
		$(XCB_RUN) test-real $(XCB_TEST) $(call test_bundle,real) -testPlan RealData) \
		$(call only_testing,OpenSkyRealDataTests))

##@ Test tools

test-report: ## Summarize the newest test result bundle, failures included
	@./tools/test-report.sh $(TEST_RESULTS)

test-perms: ## Check the one-time macOS permission grants tests need
	@./tools/test-perms.sh

coverage-floor: ## Fail when a parser module is under COVERAGE_FLOOR in the last test run
	@./tools/lint/coverage-floor.sh $(COVERAGE_FLOOR) $(DERIVED_DATA)

# test-unit never compiles the real-data suites, so a build break there used to
# stay hidden (issue #457). Compiling needs no install, so CI runs it.
realdata-build: link-shared ## Compile the real-data suites without running them
	@$(XCB_RUN) realdata-build $(XCB_TEST) -testPlan RealData build-for-testing

profile: link-shared ## Record a Time Profiler trace of a Release CLI bench [MODE=walk|fly] [ARGS=...]
	@$(MAKE) --no-print-directory cli CONFIG=Release
	@./tools/profile.sh "$(DERIVED_DATA)/Build/Products/Release/openskycli" $(or $(MODE),walk) $(ARGS)

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
			-type d -name 'OpenSky-*' -exec rm -rf {} +; \
	fi
