# OpenSky — automation hub. If it can be scripted, it lives here (AGENTS.md).
# `make help` lists targets. Single automation entrypoint at the repo root.

PROJECT        := opensky.xcodeproj
SCHEME         := opensky
CLI_SCHEME     := openskycli
CONFIG         ?= Debug
DESTINATION    ?= platform=macOS
SWIFT_PATHS    := opensky openskycli openskyTests openskyUITests

SWIFTFORMAT_CFG := tools/format/.swiftformat
SWIFTLINT_CFG   := tools/lint/.swiftlint.yml
MD_CFG          := tools/markdown/.markdownlint-cli2.yaml
MD_GLOB         := **/*.md

.DEFAULT_GOAL := help
.PHONY: help bootstrap hooks format format-check lint check fix swift-format \
        swift-lint md-format md-lint sh-lint build cli probe test test-ui \
        test-one test-report app-path cli-path run-cli install clean

help: ## List available targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Install toolchain (Homebrew) + wire git hooks
	@./tools/bootstrap.sh

hooks: ## Point git at .githooks/hooks (idempotent)
	@git config core.hooksPath .githooks/hooks
	@find .githooks -type f \( -name '*.sh' -o -path '*/hooks/*' \) -exec chmod +x {} +
	@echo "[ OK ] core.hooksPath = .githooks/hooks"

format: swift-format md-format ## Autoformat everything in place

format-check: ## Fail if anything is unformatted (no writes) — for CI
	@swiftformat --lint --config $(SWIFTFORMAT_CFG) $(SWIFT_PATHS)
	@markdownlint-cli2 --config $(MD_CFG) "$(MD_GLOB)"

lint: swift-lint md-lint sh-lint ## Run all linters (strict)

check: format-check lint ## Format + lint gate without building

fix: format lint ## Autoformat, then strict lint — one-shot dev gate

swift-format: ## Autoformat Swift
	@swiftformat --config $(SWIFTFORMAT_CFG) $(SWIFT_PATHS)

swift-lint: ## Strict Swift lint (warnings fail)
	@swiftlint lint --strict --quiet --config $(SWIFTLINT_CFG) $(SWIFT_PATHS)

md-format: ## Autofix Markdown
	@markdownlint-cli2 --fix --config $(MD_CFG) "$(MD_GLOB)" || true

md-lint: ## Strict Markdown lint
	@markdownlint-cli2 --config $(MD_CFG) "$(MD_GLOB)"

sh-lint: ## Shellcheck the hook + tooling scripts
	@shellcheck -s sh $$(find .githooks tools -type f -name '*.sh') .githooks/hooks/*

build: ## Build the app ($(CONFIG))
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) build

cli: ## Build the openskycli dev tool ($(CONFIG))
	@xcodebuild -project $(PROJECT) -scheme $(CLI_SCHEME) -configuration $(CONFIG) build

probe: ## CLI smoke checks against the local install (skips if absent)
	@./tools/probe.sh

test: ## Build + run unit tests (no UI tests)
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-skip-testing:openskyUITests test

test-ui: ## Build + run UI tests (launches the app, drives it via automation)
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:openskyUITests test

test-one: ## Run one test class/method: make test-one T=Class[/test]
	@test -n "$(T)" || { \
		echo "[ERROR] usage: make test-one T=ClassName[/testName]"; \
		echo "        bare names resolve to openskyTests/; prefix a target to override"; \
		exit 2; }
	@case "$(T)" in */*) spec="$(T)";; *) spec="openskyTests/$(T)";; esac; \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:"$$spec" test

test-report: ## Print summary of the newest test result bundle
	@latest=$$(ls -td \
		~/Library/Developer/Xcode/DerivedData/opensky-*/Logs/Test/*.xcresult \
		2>/dev/null | head -1); \
	test -n "$$latest" || { echo "[ERROR] no .xcresult under DerivedData"; exit 1; }; \
	echo "[INFO] $$latest"; \
	xcrun xcresulttool get test-results summary --path "$$latest"

app-path: ## Print built opensky.app path ($(CONFIG))
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-showBuildSettings 2>/dev/null \
		| awk '$$1 == "BUILT_PRODUCTS_DIR" {print $$3 "/opensky.app"; exit}'

cli-path: ## Print built openskycli path ($(CONFIG))
	@xcodebuild -project $(PROJECT) -scheme $(CLI_SCHEME) -configuration $(CONFIG) \
		-showBuildSettings 2>/dev/null \
		| awk '$$1 == "BUILT_PRODUCTS_DIR" {print $$3 "/openskycli"; exit}'

run-cli: cli ## Build + run openskycli: make run-cli ARGS="vfs ls"
	@"$$($(MAKE) --no-print-directory cli-path)" $(ARGS)

install: ## Build Release app (arm64) + copy to /Applications
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath build/install ARCHS=arm64 build
	@rm -rf /Applications/opensky.app
	@ditto build/install/Build/Products/Release/opensky.app /Applications/opensky.app
	@echo "[ OK ] /Applications/opensky.app updated"

clean: ## Remove build artifacts
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	@rm -rf build DerivedData
