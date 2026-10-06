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
# When this make started, so tools/xcodebuild-run.sh can report the time make spent
# before xcodebuild. A nested make keeps the outer value.
export OPENSKY_MAKE_STARTED ?= $(shell date +%s)
# The Swift files the branch changed, for the per-file format and lint checks.
# ALL=1 checks the whole tree, as CI does.
CHANGED_SWIFT     = $(shell { git diff --name-only --diff-filter=AMR $$(git merge-base HEAD origin/main 2>/dev/null || echo HEAD) -- '*.swift'; \
	git ls-files --others --exclude-standard -- '*.swift'; } 2>/dev/null | sort -u | while read -r f; do [ -f "$$f" ] && printf '%s ' "$$f"; done)
LINT_SWIFT        = $(if $(ALL),$(SWIFT_PATHS),$(CHANGED_SWIFT))

# Build cache. One tree per checkout, named after the checkout folder, on the boot
# volume: it is about fifteen times faster to write than the external data volume,
# and `make prune` (also run when a session ends) removes the trees of worktrees
# that are gone. Every xcodebuild below passes it, and the tools/ scripts read it
# from OPENSKY_DERIVED_DATA. CI sets that variable to a path inside its workspace.
CACHE_ROOT       ?= $(HOME)/Library/Caches/OpenSky
export OPENSKY_CACHE_ROOT := $(CACHE_ROOT)
DERIVED_DATA     ?= $(or $(OPENSKY_DERIVED_DATA),$(CACHE_ROOT)/$(notdir $(CURDIR)))
XCODEBUILD_DD    := -derivedDataPath $(DERIVED_DATA)
export OPENSKY_DERIVED_DATA := $(DERIVED_DATA)
# The compilation cache store. Every worktree shares the main checkout's, which
# stays on the data volume because it runs to tens of gigabytes. Prefix mapping in
# Config/Build/Debug.xcconfig makes the keys the same in every worktree. It lives
# in a hidden folder: xcodebuild scans every visible file under the package root
# at each start, and the store holds hundreds of thousands (docs/tools/build-system.md).
SHARED_ROOT      := $(abspath $(dir $(shell git rev-parse --git-common-dir)))
COMPILATION_CACHE ?= $(or $(OPENSKY_COMPILATION_CACHE),$(SHARED_ROOT)/.cache/CompilationCache.noindex)
export OPENSKY_COMPILATION_CACHE := $(COMPILATION_CACHE)
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
# .logs/ and prints each diagnostic once, failures, and the final counts. It also
# clears stale module copies (tools/stale-modules.sh). OPENSKY_XCODEBUILD_RAW=1
# prints everything.
XCB_RUN          := ./tools/xcodebuild-run.sh
# Allocates a per-run output directory, .logs/<name>/<UTC timestamp>/, and points
# <name>/latest at it, so `make prune` can age whole runs out (issue #347).
RUN_DIR          := ./tools/run-dir.sh
# How many days of run output `make prune` keeps. One: xcodebuild scans every
# file under .logs/ at each start (docs/tools/build-system.md).
PRUNE_DAYS       ?= 1

# The shared xcodebuild command line: $(1) is the scheme, $(2) the configuration.
# Targets append only their action and their own flags, so the project, cache
# location, and XCODEBUILD_FLAGS cannot drift apart. tools/xcodebuild-lib.sh is
# the shell twin of this.
# A build keeps going after an error: a build that stops at the first error cancels
# the Products copy of a module whose emit already finished, and that stale copy
# breaks every build above it (docs/tools/build-system.md).
xcb = xcodebuild -workspace $(WORKSPACE) -scheme $(1) -configuration $(2) \
	$(XCODEBUILD_DD) COMPILATION_CACHE_CAS_PATH=$(COMPILATION_CACHE) \
	-IDEBuildingContinueBuildingAfterErrors=YES \
	$(COVERAGE_$(2)) $(ARCHS_$(2)) $(XCODEBUILD_FLAGS)
# A test build compiles every target with coverage and a plain build does not, and
# both write the same package intermediates. So each Debug build turns coverage on,
# or `make build-cli` and `make test` rebuild each other's engine (issue #714). Only the
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

# Test plans (Config/TestPlans/*.xctestplan) choose which test bundles a run builds
# and runs, instead of -only-testing flags (issue #346). A plan builds only the
# bundles it lists, so the layer plans are the quick runs. The UI bundle must never
# share a plan with an app-hosted bundle (OpenSkyTests, OpenSkyRealDataTests): both
# would drive OpenSky.app at once and deadlock (issue #380).
UNIT_PLAN        := -testPlan UnitTests
# The plan with the smallest test bundle: the build context every Debug build of
# the app and the CLI uses, so a test run after it compiles nothing again.
BUILD_PLAN       := -testPlan AgentControl
# Coverage is gathered only on request (CI, make coverage-floor): the profile merge
# and the coverage archive in the result bundle cost time on every run otherwise.
coverage_flag     = -enableCodeCoverage $(if $(COVERAGE),YES,NO)

# Formatter and linter configuration.
SWIFTFORMAT_CFG  := tools/format/.swiftformat
SWIFTLINT_CFG    := tools/lint/.swiftlint.yml
JSCPD_CFG        := tools/lint/.jscpd.json
PERIPHERY_CFG    := tools/lint/.periphery.yml
CLANGFORMAT_CFG  := tools/format/.clang-format
MD_CFG           := tools/markdown/.markdownlint-cli2.yaml
ACTIONLINT_CFG   := tools/lint/actionlint.yaml
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

check: swift-baseline format-check lint docs-links ## The same gate without writing files [ALL=1 lints every Swift file]

format: swift-format metal-format md-format ## Autoformat Swift, Metal, and Markdown

format-check: swift-format-check metal-format-check md-lint #| Fail if anything is unformatted, without writing

swift-format-check: #| Fail if any changed Swift file is unformatted [ALL=1 whole tree]
	@files="$(LINT_SWIFT)"; [ -n "$$files" ] || { echo "[ OK ] no changed Swift file to check"; exit 0; }; \
		swiftformat --lint --config $(SWIFTFORMAT_CFG) $$files

metal-format-check: #| Fail if any Metal shader is unformatted
	@[ -z "$(METAL_FILES)" ] || $(CLANG_FORMAT) --style=file:$(CLANGFORMAT_CFG) \
		--dry-run --Werror $(METAL_FILES)

lint: swift-lint md-lint sh-lint cli-boundary realdata-plan lint-test-plans lint-test-tags lint-test-targets no-game-content docs-length agent-files workflow-lint comment-length panel-text duplicates no-suppressions ## Run every linter (warnings fail)
	@./tools/lint/module-graph.sh

swift-baseline: #| Check for the Apple Swift that CI uses and Swift 6 mode in every target
	@./tools/lint/swift-baseline.sh

swift-format: #| Autoformat the changed Swift files [ALL=1 whole tree]
	@files="$(LINT_SWIFT)"; [ -n "$$files" ] || { echo "[ OK ] no changed Swift file to format"; exit 0; }; \
		swiftformat --config $(SWIFTFORMAT_CFG) $$files

swift-lint: #| Lint the changed Swift files strictly [ALL=1 whole tree]
	@files="$(LINT_SWIFT)"; [ -n "$$files" ] || { echo "[ OK ] no changed Swift file to lint"; exit 0; }; \
		$(SWIFTLINT) lint --strict --quiet --config $(SWIFTLINT_CFG) $$files

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
	@actionlint -config-file $(ACTIONLINT_CFG) && echo "[ OK ] workflows clean"

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

.PHONY: compile build-tests shader-library

# swift build of the package modules the branch changed, or M='A B', plus their
# dependents. No Xcode, so it is the quick loop while fixing compile errors;
# Xcode-only code still needs build-app, build-cli, or build-tests.
compile: link-shared ## Compile changed package modules and their dependents [M='Module ...']
	@./tools/compile-modules.sh $(M)

# Every bundle of a plan compiled, no test run. Catches a change that breaks a test
# target it did not run. Hosted bundles need the app, so it builds too.
build-tests: link-shared ## Compile a plan's test bundles without running tests [PLAN=UnitTests|RealData|...]
	@$(XCB_RUN) build-tests $(XCB_TEST) -testPlan $(or $(PLAN),UnitTests) build-for-testing

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

.PHONY: build-app build-cli run-cli install app-path cli-path probe icon

# A Debug build of the app or the CLI runs as a test build of the smallest plan, so
# it shares one build context with every test run and compiles nothing twice
# (docs/tools/environment.md, the dirty driver record). Release has no test context.
build-app: link-shared ## Build the app [CONFIG]
	@$(XCB_RUN) build-app $(if $(filter Release,$(CONFIG)),$(XCB_APP) build,$(XCB_TEST) $(BUILD_PLAN) build-for-testing)

build-cli: link-shared ## Build the openskycli dev tool [CONFIG]
	@$(XCB_RUN) build-cli $(if $(filter Release,$(CONFIG)),$(XCB_CLI) build,$(XCB_TEST) $(BUILD_PLAN) build-for-testing)

run-cli: build-cli ## Build and run openskycli, e.g. make run-cli ARGS="vfs ls"
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

.PHONY: test-unit test-rerun test-package test-ui test-sanitize test-real test-report test-perms \
        coverage-floor sanitizer-shaders profile benchmark launch-sample

# The result bundle of one run, in its own run directory (issue #347).
test_bundle = -resultBundlePath "$$($(RUN_DIR) -b $(TEST_RESULTS) $(1))/$(1).xcresult"
# -only-testing for T. A T that does not start with an OpenSky*Tests target
# resolves under the bundle in $(1).
only_testing = $(if $(T),-only-testing:'$(if $(filter OpenSky%Tests,$(firstword \
	$(subst /, ,$(T)))),,$(1)/)$(T)')
# One test host, watched by the memory watchdog: a real-data run once reached
# 30 GB and locked the machine. $(1) is the default cap in MB, CAP overrides it.
# $(3) is the run's derived data: the watchdog only watches processes built there.
guarded = sh tools/memguard.sh "$(3)" $(or $(CAP),$(1)) 10800 & guard=$$!; \
	trap 'kill $$guard 2>/dev/null' EXIT INT TERM; \
	$(2) -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
# The perf gates measure the engine, not -Onone, so they build optimized in their
# own cache, which keeps the Debug build (issue #392).
XCB_PERF         := xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) \
	-configuration Debug -derivedDataPath $(DERIVED_DATA)-optimized \
	COMPILATION_CACHE_CAS_PATH=$(COMPILATION_CACHE) \
	-destination '$(DESTINATION)' $(XCODEBUILD_FLAGS) \
	SWIFT_OPTIMIZATION_LEVEL=-O GCC_OPTIMIZATION_LEVEL=s \
	SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG OPENSKY_OPTIMIZED"

# PLAN picks the unit plan. Quick, the default, is every package test bundle without
# the slow and GPU tests, so it builds no app. A layer plan (Formats, Engine,
# Features, App) builds only its bundles. UnitTests is everything, as CI runs it.
# GPU selects the GPU tag across every bundle. N hunts a flaky test: it reruns
# until the first failure, at most N times.
PLAN             ?= Quick
UNIT_PLANS       := Quick Formats Engine Features App UnitTests GPU
check_plan = $(if $(filter $(PLAN),$(UNIT_PLANS)),,$(error PLAN must be one of: $(UNIT_PLANS)))
test-unit: link-shared $(SHADER_LIBRARY) ## Run a unit plan [PLAN=Quick|Formats|Engine|Features|App|UnitTests|GPU] [T='Target/Suite/test()'] [N=100] [COVERAGE=1]
	@$(check_plan)TEST_RUNNER_OPENSKY_DATA_ROOT="$(OPENSKY_DATA_ROOT)" \
		$(XCB_RUN) test-unit $(XCB_TEST) $(call test_bundle,unit-$(PLAN)) \
		-testPlan $(PLAN) $(call only_testing,OpenSkyTests) $(coverage_flag) \
		$(if $(N),-run-tests-until-failure -test-iterations $(N)) test

# The .xctestrun that the last test or build-for-testing run of PLAN wrote. A rerun
# through it skips the build system: seconds instead of minutes. It runs the
# products as built, so an edit since then needs `make test-unit` again.
xctestrun = $(lastword $(sort $(wildcard $(DERIVED_DATA)/Build/Products/$(SCHEME)_$(PLAN)_*.xctestrun)))
test-rerun: ## Rerun the last built plan without the build system [PLAN=Quick|...] [T='Target/Suite/test()']
	@$(check_plan)test -n "$(xctestrun)" || { \
		echo "[ERROR] no built $(PLAN) plan under $(DERIVED_DATA): run make test-unit PLAN=$(PLAN) first" >&2; exit 2; }
	@newer="$$(find Sources Tests Config Package.swift -type f -newer "$(xctestrun)" 2>/dev/null | head -n 1)"; \
		[ -z "$$newer" ] || echo "[WARNING] $$newer changed after the last build of $(PLAN); run make test-unit PLAN=$(PLAN) to rebuild"
	@$(XCB_RUN) test-rerun xcodebuild -xctestrun "$(xctestrun)" $(XCODEBUILD_DD) \
		-destination '$(DESTINATION)' $(call test_bundle,rerun-$(PLAN)) \
		$(call only_testing,OpenSkyTests) $(coverage_flag) test-without-building

# One package test target through `swift test`: no Xcode, no app, no other bundle.
# The package keeps its own build tree in .build/. A filter that matches nothing
# still exits 0, so the recipe counts what ran.
test-package: link-shared $(SHADER_LIBRARY) ## Run one package test target with swift test [T='OpenSkyFormatsESMTests[/Suite[/test()]]']
	@test -n "$(T)" || { echo "[ERROR] usage: make test-package T='Target[/Suite[/test()]]'" >&2; exit 2; }
	@target="$(firstword $(subst /, ,$(T)))"; rest="$(T)"; rest="$${rest#"$$target"}"; rest="$${rest#/}"; \
		[ -d "Tests/$$target" ] || { echo "[ERROR] no package test target $$target (no Tests/$$target/)" >&2; exit 2; }; \
		filter="^$$target\\.$$(printf '%s' "$$rest" | sed 's/[()]/\\&/g')"; \
		run="$$($(RUN_DIR) test-package)"; log="$$run/test-package.log"; \
		echo "[INFO] swift test --filter $$filter"; status=0; \
		. ./tools/xcodebuild-lib.sh; opensky_build_lock; \
		swift test --filter "$$filter" >"$$log" 2>&1 || status=$$?; opensky_build_unlock; \
		grep -E '(error|warning): |^✘|Test run with' "$$log" || true; \
		echo "[INFO] full transcript: $$log"; [ "$$status" -eq 0 ] || exit "$$status"; \
		ran="$$(sed -n 's/.*Test run with \([0-9][0-9]*\) test.*/\1/p' "$$log" | tail -n 1)"; \
		[ -n "$$ran" ] && [ "$$ran" -gt 0 ] || { echo "[ERROR] selector matched no test: $(T)" >&2; exit 1; }

# A timeout in "enabling automation mode" means Automation Mode asks for a
# password: run make test-perms.
test-ui: link-shared ## Run the UI tests (launches and drives the app) [T='Suite/test()']
	@$(XCB_RUN) test-ui $(XCB_TEST) $(call test_bundle,ui) -testPlan UITests \
		$(call only_testing,OpenSkyUITests) $(coverage_flag) test

# The sanitized builds have their own BUILD_DIR, and the plan finds the shaders
# through $(BUILD_DIR). The shaders are not sanitized, so each gets a copy.
sanitizer-shaders: $(SHADER_LIBRARY)
	@for variant in Variant-TSan Variant-ASan-UBSan; do \
		mkdir -p "$(DERIVED_DATA)/Build/Products/$$variant" && \
		cp "$(SHADER_LIBRARY)" "$(DERIVED_DATA)/Build/Products/$$variant/" || exit 1; \
	done

# TSan and ASan with UBSan cannot share a build (issue #383), so SAN picks one. The
# weekly CI workflow runs both; locally they are a milestone check.
SANITIZER_CONFIG_thread  := Thread
SANITIZER_CONFIG_address := Address
test-sanitize: link-shared sanitizer-shaders ## Run the unit tests under a sanitizer SAN=thread|address [CAP=MB]
	@$(call guarded,12288,$(XCB_RUN) test-sanitize-$(SAN) $(XCB_TEST) \
		$(call test_bundle,sanitize-$(SAN)) -testPlan Sanitizers -only-test-configuration \
		$(or $(SANITIZER_CONFIG_$(SAN)),$(error SAN must be thread or address)) $(coverage_flag),$(DERIVED_DATA))

# Real-data tests read the user's install, so they run on demand and before a
# milestone acceptance, never in CI. The RealData plan is the smoke set, the tests
# tagged `.smoke`; ALL=1 runs the RealDataAll plan, every real-data test. PERF=1
# runs the Perf plan, the tests tagged `.perf`, built optimized.
# The checkout, for real-data tests that write into `.logs/`; the build cache is
# outside it. Xcode passes TEST_RUNNER_ variables to the test process.
real_env = TEST_RUNNER_OPENSKY_CHECKOUT="$(CURDIR)" \
	TEST_RUNNER_OPENSKY_SKYRIM_SAVES="$(OPENSKY_SKYRIM_SAVES)"
test-real: link-shared ## Run the real-data smoke plan [ALL=1] [T='Suite/test()'] [CAP=MB] [PERF=1]
	@$(call guarded,6144,$(if $(PERF), \
		$(real_env) $(XCB_RUN) test-perf $(XCB_PERF) $(call test_bundle,perf) -testPlan Perf, \
		$(real_env) $(XCB_RUN) test-real $(XCB_TEST) $(call test_bundle,real) -testPlan $(if $(ALL),RealDataAll,RealData)) \
		$(call only_testing,OpenSkyRealDataTests) $(coverage_flag),$(DERIVED_DATA)$(if $(PERF),-optimized))

##@ Test tools

test-report: ## Summarize the newest test result bundle, failures included
	@./tools/test-report.sh $(TEST_RESULTS)

test-perms: ## Check the one-time macOS permission grants tests need
	@./tools/test-perms.sh

coverage-floor: ## Fail when a parser module is under COVERAGE_FLOOR in the last `test-unit COVERAGE=1` run
	@./tools/lint/coverage-floor.sh $(COVERAGE_FLOOR) $(DERIVED_DATA)

profile: link-shared ## Record a Time Profiler trace of a Release CLI bench [MODE=walk|fly] [ARGS=...]
	@$(MAKE) --no-print-directory build-cli CONFIG=Release
	@./tools/profile.sh "$(DERIVED_DATA)/Build/Products/Release/openskycli" $(or $(MODE),walk) $(ARGS)

benchmark: link-shared ## Run the shared load and frame time benchmark on a Release CLI
	@$(MAKE) --no-print-directory build-cli CONFIG=Release
	@./tools/benchmark.sh "$(DERIVED_DATA)/Build/Products/Release/openskycli"

launch-sample: ## Sample the installed app's main thread through its first minute [SECONDS=60]
	@./tools/launch-sample.sh "$(DERIVED_DATA)/Build/Products/Release/openskycli" \
		/Applications/OpenSky.app $(or $(SECONDS),60)

##@ Housekeeping

.PHONY: prune clean

# `clean` empties this checkout. `prune` reaches what no checkout owns any more,
# chiefly the caches of removed worktrees, which is what fills the data volume.
prune: ## Delete stale worktree caches and old run output [PRUNE_DAYS=1] [DRY_RUN=1]
	@./tools/prune.sh --days $(PRUNE_DAYS) $(if $(DRY_RUN),--dry-run,)

# Keeps the shared compilation cache store. Its entries are keyed on the full
# compile command and inputs, so they cannot go stale. DEEP=1 removes it too, for
# timing a truly cold build; every worktree then starts cold.
clean: ## Remove build output and caches [DEEP=1 also drops the shared compile cache]
	@rm -rf build "$(DERIVED_DATA)" "$(DERIVED_DATA)-optimized" "$(INDEX_DATA)"
	@rm -rf DerivedData DerivedData-optimized DerivedData-index
	@[ -z "$(DEEP)" ] || rm -rf "$(COMPILATION_CACHE)"
	@if [ -d "$(XCODE_DERIVED_DATA)" ]; then \
		find "$(XCODE_DERIVED_DATA)" -mindepth 1 -maxdepth 1 \
			-type d -name 'OpenSky-*' -exec rm -rf {} +; \
	fi
