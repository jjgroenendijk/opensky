# OpenSky — automation hub. If it can be scripted, it lives here (AGENTS.md).
# `make help` lists targets. Single automation entrypoint at the repo root.

PROJECT        := opensky.xcodeproj
SCHEME         := opensky
CLI_SCHEME     := openskycli
CONFIG         ?= Debug
DESTINATION    ?= platform=macOS
XCODEBUILD_FLAGS ?=
SWIFT_PATHS    := opensky openskycli openskyTests openskyUITests
TEST_RESULTS   := build/test-results
# Build cache lives beside the checkout, not under $HOME. The repo sits on a
# large external volume while the boot volume is small, and an Xcode-default
# DerivedData for this project runs to tens of gigabytes — enough to fill the
# boot disk mid-session. Keeping it here puts the cache on the same volume as
# the sources it describes, and `DerivedData/` is already gitignored. Every
# xcodebuild call below passes it, and the shell tools read it from
# OPENSKY_DERIVED_DATA, so there is exactly one place to change it.
DERIVED_DATA   ?= $(CURDIR)/DerivedData
XCODEBUILD_DD  := -derivedDataPath $(DERIVED_DATA)
export OPENSKY_DERIVED_DATA := $(DERIVED_DATA)
# Xcode's default location, kept only so `make clean` can also sweep the caches
# a pre-DERIVED_DATA checkout (or a plain Xcode GUI build) left behind there.
XCODE_DERIVED_DATA ?= $(HOME)/Library/Developer/Xcode/DerivedData

# Every xcodebuild below runs through this wrapper: it keeps the whole
# transcript in logs/<name>.log and prints only diagnostics, failures, and the
# closing counts, which is the difference between a few dozen lines and a few
# thousand for a green build or test run. OPENSKY_XCODEBUILD_RAW=1 prints
# everything; a failing run does that on its own.
XCB_RUN        := ./tools/xcodebuild-run.sh
# Run output is per-run, not per-name: every script that writes something a
# human reads later allocates <base>/<name>/<UTC timestamp>/ through this and
# repoints <base>/<name>/latest at it, so `make prune` can age a whole run out
# and a stale capture cannot be mistaken for the current one (issue #347).
RUN_DIR        := ./tools/run-dir.sh
# Retention for `make prune`, in days. Overridable: make prune PRUNE_DAYS=2.
PRUNE_DAYS     ?= 14
# The one xcodebuild invocation every target below shares: $(1) is the scheme,
# $(2) the configuration. A target adds only its action and the flags specific
# to it, so project, cache location, and the caller's escape hatch cannot drift
# apart again. The tools/ scripts rebuild the same core in shell from
# tools/xcodebuild-lib.sh.
xcb = xcodebuild -project $(PROJECT) -scheme $(1) -configuration $(2) \
	$(XCODEBUILD_DD) $(XCODEBUILD_FLAGS)
XCB_APP     := $(call xcb,$(SCHEME),$(CONFIG))
XCB_CLI     := $(call xcb,$(CLI_SCHEME),$(CONFIG))
XCB_RELEASE := $(call xcb,$(SCHEME),Release)
XCB_TEST    := $(XCB_APP) -destination '$(DESTINATION)'
# xcodebuild puts a macOS scheme's products at this fixed path under the derived
# data root. Reading it back with -showBuildSettings costs several seconds per
# call, which `run-cli` used to pay twice, so derive it instead.
PRODUCTS       = $(DERIVED_DATA)/Build/Products/$(CONFIG)

SWIFTFORMAT_CFG := tools/format/.swiftformat
SWIFTLINT_CFG   := tools/lint/.swiftlint.yml
CLANGFORMAT_CFG := tools/format/.clang-format
MD_CFG          := tools/markdown/.markdownlint-cli2.yaml
MD_GLOB         := **/*.md
METAL_FILES     := $(shell find opensky openskycli -name '*.metal' 2>/dev/null)

.DEFAULT_GOAL := help
.PHONY: help bootstrap ffmpeg vendor-link vendor-prune hooks format format-check lint \
        check fix swift-format swift-baseline \
        swift-lint metal-format md-format md-lint sh-lint cli-boundary no-game-content \
        docs-links build cli \
        probe test \
        test-ui test-one test-report realtest test-perms app-path cli-path run-cli \
        install clean prune icon

help: ## List available targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Install toolchain (Homebrew) + wire git hooks
	@./tools/bootstrap.sh

ffmpeg: ## Build the vendored decode-only LGPL ffmpeg into .vendor/ffmpeg
	@./tools/vendor-ffmpeg.sh

vendor-link: ## Point this worktree's .vendor at the shared one (no-op in main checkout)
	@./tools/ffmpeg/link-vendor.sh

vendor-prune: ## Replace per-worktree .vendor copies with shared symlinks (run when idle)
	@./tools/ffmpeg/prune-vendor.sh

hooks: ## Point git at .githooks/hooks (idempotent)
	@git config core.hooksPath .githooks/hooks
	@find .githooks -type f \( -name '*.sh' -o -path '*/hooks/*' \) -exec chmod +x {} +
	@echo "[ OK ] core.hooksPath = .githooks/hooks"

format: swift-format metal-format md-format ## Autoformat everything in place

format-check: ## Fail if anything is unformatted (no writes) — for CI
	@swiftformat --lint --config $(SWIFTFORMAT_CFG) $(SWIFT_PATHS)
	@[ -z "$(METAL_FILES)" ] || xcrun clang-format --style=file:$(CLANGFORMAT_CFG) \
		--dry-run --Werror $(METAL_FILES)
	@markdownlint-cli2 --config $(MD_CFG) "$(MD_GLOB)"

lint: swift-lint md-lint sh-lint cli-boundary no-game-content ## Run all linters (strict)

check: swift-baseline format-check lint docs-links ## Format + lint gate without building

fix: format lint ## Autoformat, then strict lint — one-shot dev gate

swift-baseline: ## Toolchain is >= Apple Swift 6.3.3 and every target is in Swift 6 mode
	@./tools/lint/swift-baseline.sh

swift-format: ## Autoformat Swift
	@swiftformat --config $(SWIFTFORMAT_CFG) $(SWIFT_PATHS)

swift-lint: ## Strict Swift lint (warnings fail)
	@swiftlint lint --strict --quiet --config $(SWIFTLINT_CFG) $(SWIFT_PATHS)

metal-format: ## Autoformat Metal shaders (clang-format via Xcode)
	@[ -z "$(METAL_FILES)" ] || xcrun clang-format --style=file:$(CLANGFORMAT_CFG) \
		-i $(METAL_FILES)

md-format: ## Autofix Markdown
	@markdownlint-cli2 --fix --config $(MD_CFG) "$(MD_GLOB)" || true

md-lint: ## Strict Markdown lint
	@markdownlint-cli2 --config $(MD_CFG) "$(MD_GLOB)"

cli-boundary: ## No AppKit imports under opensky/Engine (openskycli builds it)
	@./tools/lint/cli-boundary.sh && echo "[ OK ] CLI target boundary clean"

no-game-content: ## No extracted game assets or rendered captures are tracked
	@./tools/lint/no-game-content.sh && echo "[ OK ] no tracked game content"

sh-lint: ## Shellcheck the hook + tooling scripts
	@shellcheck -s sh $$(find .githooks tools -type f -name '*.sh') .githooks/hooks/*

docs-links: ## Check intra-wiki links in docs/ resolve (log.md skipped)
	@./tools/check-docs-links.sh

build: vendor-link ## Build the app ($(CONFIG))
	@$(XCB_RUN) build $(XCB_APP) build

cli: vendor-link ## Build the openskycli dev tool ($(CONFIG))
	@$(XCB_RUN) cli $(XCB_CLI) build

probe: ## CLI smoke checks against the local install (skips if absent)
	@./tools/probe.sh

# Which bundles a run touches is a checked-in test plan (issue #346), not a
# pile of -only-testing/-skip-testing flags: UnitTests lists openskyTests
# alone, AllTests lists both. Selecting the unit plan is what actually drops
# the UI bundle's compile and link — xcodebuild builds every buildable in the
# Test action before it looks at selectors, so a selector alone never did.
UNIT_PLAN   := -testPlan UnitTests
ALL_PLAN    := -testPlan AllTests

test: vendor-link ## Build + run unit tests (no UI tests)
	@bundle="$$($(RUN_DIR) -b $(TEST_RESULTS) unit)/unit.xcresult"; \
		TEST_RUNNER_OPENSKY_DATA_ROOT="$(OPENSKY_DATA_ROOT)" \
		$(XCB_RUN) test $(XCB_TEST) -resultBundlePath "$$bundle" \
		$(UNIT_PLAN) test

test-ui: vendor-link ## Build + run UI tests (launches the app, drives it via automation)
	@./tools/test-ui.sh \
		$(PROJECT) $(SCHEME) '$(DESTINATION)' $(XCODEBUILD_FLAGS)

# The unit plan cannot select a UI test, so a selector naming openskyUITests
# switches to the plan that lists it. Every other selector keeps the default.
test-one: vendor-link ## Run one test: make test-one T=Class[/method] or Target/Class/method
	@test -n "$(T)" || { \
		echo "[ERROR] usage: make test-one T=ClassName[/methodName]"; \
		echo "        or: make test-one T=TargetName/ClassName/methodName"; \
		echo "        ClassName[/methodName] resolves under openskyTests"; \
		exit 2; }
	@case "$(T)" in */*/*) spec="$(T)";; *) spec="openskyTests/$(T)";; esac; \
	case "$$spec" in openskyUITests/*) plan="$(ALL_PLAN)";; *) plan="$(UNIT_PLAN)";; esac; \
	bundle="$$($(RUN_DIR) -b $(TEST_RESULTS) one)/one.xcresult"; \
	TEST_RUNNER_OPENSKY_DATA_ROOT="$(OPENSKY_DATA_ROOT)" \
		$(XCB_RUN) test-one $(XCB_TEST) -resultBundlePath "$$bundle" \
		$$plan -only-testing:"$$spec" test

test-report: ## Print pass/fail summary + failure detail from the newest result bundle
	@./tools/test-report.sh $(TEST_RESULTS)

realtest: vendor-link ## Run one env-gated real-data test under the RSS watchdog: make realtest T=Class/method() [CAP=MB]
	@test -n "$(T)" || { \
		echo "[ERROR] usage: make realtest T='Class/method()' [CAP=MB]"; \
		echo "        selector must resolve to exactly one test (fully qualified)"; \
		echo "        e.g. make realtest T='CellRenderRealDataTests/streamsFiveByFiveGridToCompletion()'"; \
		exit 2; }
	@case "$(T)" in openskyTests/*) spec="$(T)";; *) spec="openskyTests/$(T)";; esac; \
	OPENSKY_DATA_ROOT="$(OPENSKY_DATA_ROOT)" ./tools/realtest.sh "$$spec" $(CAP)

test-perms: ## Check/guide the one-time TCC grants that stop test permission popups
	@./tools/test-perms.sh

app-path: ## Print built opensky.app path ($(CONFIG))
	@echo "$(PRODUCTS)/opensky.app"

cli-path: ## Print built openskycli path ($(CONFIG))
	@echo "$(PRODUCTS)/openskycli"

run-cli: cli ## Build + run openskycli: make run-cli ARGS="vfs ls"
	@"$(PRODUCTS)/openskycli" $(ARGS)

icon: ## Regenerate AppIcon PNGs from opensky/App/Branding/opensky-logo.svg
	@./tools/gen-appicon.sh

# Release shares the main derived-data tree with Debug (xcodebuild keeps the two
# configurations in separate product and intermediate directories), so a repeat
# install is incremental instead of the cold build a private build/install cache
# forced every time.
install: vendor-link ## Build Release app (arm64) + copy to /Applications
	@$(XCB_RUN) install $(XCB_RELEASE) ARCHS=arm64 build
	@rm -rf /Applications/opensky.app
	@ditto $(DERIVED_DATA)/Build/Products/Release/opensky.app /Applications/opensky.app
	@echo "[ OK ] /Applications/opensky.app updated"

# `clean` empties this checkout; `prune` is the one that reaches the caches no
# checkout owns any more — chiefly the DerivedData a removed worktree left
# behind, which is where the data volume actually fills up.
prune: ## Delete stale worktree caches + aged-out run output (PRUNE_DAYS=14, DRY_RUN=1)
	@./tools/prune.sh --days $(PRUNE_DAYS) $(if $(DRY_RUN),--dry-run,)

# No `xcodebuild clean` first: it takes seconds to empty the same directory the
# rm below deletes outright.
clean: ## Remove OpenSky build artifacts and Xcode caches
	@rm -rf build DerivedData
	@if [ -d "$(XCODE_DERIVED_DATA)" ]; then \
		find "$(XCODE_DERIVED_DATA)" -mindepth 1 -maxdepth 1 \
			-type d -name 'opensky-*' -exec rm -rf {} +; \
	fi
