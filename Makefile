# OpenSky — automation hub. If it can be scripted, it lives here (AGENTS.md).
# `make help` lists targets. Single automation entrypoint at the repo root.

PROJECT       := opensky.xcodeproj
SCHEME        := opensky
CONFIG        ?= Debug
DESTINATION   ?= platform=macOS
SWIFT_PATHS   := opensky openskyTests openskyUITests

SWIFTFORMAT_CFG := tools/format/.swiftformat
SWIFTLINT_CFG   := tools/lint/.swiftlint.yml
MD_CFG          := tools/markdown/.markdownlint-cli2.yaml
MD_GLOB         := **/*.md

.DEFAULT_GOAL := help
.PHONY: help bootstrap hooks format format-check lint check \
        swift-format swift-lint md-format md-lint sh-lint build test test-ui clean

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

test: ## Build + run unit tests (no UI tests)
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-skip-testing:openskyUITests test

test-ui: ## Build + run UI tests (launches the app, drives it via automation)
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:openskyUITests test

clean: ## Remove build artifacts
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	@rm -rf build DerivedData
