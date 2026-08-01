# OpenSky — automation hub. If it can be scripted, it lives here (AGENTS.md).
# `make help` lists targets. Single automation entrypoint at the repo root.

PROJECT        := opensky.xcodeproj
SCHEME         := opensky
CLI_SCHEME     := openskycli
CONFIG         ?= Debug
DESTINATION    ?= platform=macOS
XCODEBUILD_FLAGS ?=
UI_TEST_SIGNING_FLAGS := CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
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

SWIFTFORMAT_CFG := tools/format/.swiftformat
SWIFTLINT_CFG   := tools/lint/.swiftlint.yml
CLANGFORMAT_CFG := tools/format/.clang-format
MD_CFG          := tools/markdown/.markdownlint-cli2.yaml
MD_GLOB         := **/*.md
METAL_FILES     := $(shell find opensky openskycli -name '*.metal' 2>/dev/null)

.DEFAULT_GOAL := help
.PHONY: help bootstrap ffmpeg vendor-link vendor-prune hooks format format-check lint \
        check fix swift-format \
        swift-lint metal-format md-format md-lint sh-lint cli-boundary no-game-content \
        docs-links build cli \
        probe test \
        test-ui test-one test-report realtest test-perms app-path cli-path run-cli \
        install clean icon

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

check: format-check lint docs-links ## Format + lint gate without building

fix: format lint ## Autoformat, then strict lint — one-shot dev gate

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

cli-boundary: ## AppKit files under opensky/ must be excluded from openskycli
	@./tools/lint/cli-boundary.sh && echo "[ OK ] CLI target boundary clean"

no-game-content: ## No extracted game assets or rendered captures are tracked
	@./tools/lint/no-game-content.sh && echo "[ OK ] no tracked game content"

sh-lint: ## Shellcheck the hook + tooling scripts
	@shellcheck -s sh $$(find .githooks tools -type f -name '*.sh') .githooks/hooks/*

docs-links: ## Check intra-wiki links in docs/ resolve (log.md skipped)
	@./tools/check-docs-links.sh

build: vendor-link ## Build the app ($(CONFIG))
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		$(XCODEBUILD_DD) $(XCODEBUILD_FLAGS) build

cli: vendor-link ## Build the openskycli dev tool ($(CONFIG))
	@xcodebuild -project $(PROJECT) -scheme $(CLI_SCHEME) -configuration $(CONFIG) \
		$(XCODEBUILD_DD) $(XCODEBUILD_FLAGS) build

probe: ## CLI smoke checks against the local install (skips if absent)
	@./tools/probe.sh

test: vendor-link ## Build + run unit tests (no UI tests)
	@rm -rf $(TEST_RESULTS)/unit.xcresult && mkdir -p $(TEST_RESULTS)
	@TEST_RUNNER_OPENSKY_DATA_ROOT="$(OPENSKY_DATA_ROOT)" \
		xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		$(XCODEBUILD_DD) $(XCODEBUILD_FLAGS) -resultBundlePath $(TEST_RESULTS)/unit.xcresult \
		-skip-testing:openskyUITests test

test-ui: vendor-link ## Build + run UI tests (launches the app, drives it via automation)
	@OPENSKY_RESULT_BUNDLE=$(TEST_RESULTS)/ui.xcresult ./tools/test-ui.sh \
		$(PROJECT) $(SCHEME) '$(DESTINATION)' $(UI_TEST_SIGNING_FLAGS) $(XCODEBUILD_FLAGS)

test-one: vendor-link ## Run one test: make test-one T=Class[/method] or Target/Class/method
	@test -n "$(T)" || { \
		echo "[ERROR] usage: make test-one T=ClassName[/methodName]"; \
		echo "        or: make test-one T=TargetName/ClassName/methodName"; \
		echo "        ClassName[/methodName] resolves under openskyTests"; \
		exit 2; }
	@rm -rf $(TEST_RESULTS)/one.xcresult && mkdir -p $(TEST_RESULTS)
	@case "$(T)" in */*/*) spec="$(T)";; *) spec="openskyTests/$(T)";; esac; \
	TEST_RUNNER_OPENSKY_DATA_ROOT="$(OPENSKY_DATA_ROOT)" \
		xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		$(XCODEBUILD_DD) $(XCODEBUILD_FLAGS) -resultBundlePath $(TEST_RESULTS)/one.xcresult \
		-only-testing:"$$spec" test

test-report: ## Print pass/fail summary + failure detail from the newest result bundle
	@./tools/test-report.sh $(TEST_RESULTS)

realtest: ## Run one env-gated real-data test under the RSS watchdog: make realtest T=Class/method() [CAP=MB]
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
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		$(XCODEBUILD_DD) $(XCODEBUILD_FLAGS) -showBuildSettings 2>/dev/null \
		| awk '$$1 == "BUILT_PRODUCTS_DIR" {print $$3 "/opensky.app"; exit}'

cli-path: ## Print built openskycli path ($(CONFIG))
	@xcodebuild -project $(PROJECT) -scheme $(CLI_SCHEME) -configuration $(CONFIG) \
		$(XCODEBUILD_DD) $(XCODEBUILD_FLAGS) -showBuildSettings 2>/dev/null \
		| awk '$$1 == "BUILT_PRODUCTS_DIR" {print $$3 "/openskycli"; exit}'

run-cli: cli ## Build + run openskycli: make run-cli ARGS="vfs ls"
	@"$$($(MAKE) --no-print-directory cli-path)" $(ARGS)

icon: ## Regenerate AppIcon PNGs from opensky/Branding/opensky-logo.svg
	@./tools/gen-appicon.sh

install: vendor-link ## Build Release app (arm64) + copy to /Applications
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath build/install ARCHS=arm64 $(XCODEBUILD_FLAGS) build
	@rm -rf /Applications/opensky.app
	@ditto build/install/Build/Products/Release/opensky.app /Applications/opensky.app
	@echo "[ OK ] /Applications/opensky.app updated"

clean: ## Remove OpenSky build artifacts and Xcode caches
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) $(XCODEBUILD_DD) clean
	@rm -rf build DerivedData
	@if [ -d "$(XCODE_DERIVED_DATA)" ]; then \
		find "$(XCODE_DERIVED_DATA)" -mindepth 1 -maxdepth 1 \
			-type d -name 'opensky-*' -exec rm -rf {} +; \
	fi
