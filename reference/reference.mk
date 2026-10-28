# The Windows reference game under Wine 11 and DXVK (docs/tools/reference-game.md).
# Developer tooling: no release bundles any of it.

##@ Reference game

.PHONY: cpp-format cpp-format-check reference-setup reference-bridge reference-game reference-check reference-view reference-capture

reference-setup: ## Build the Wine prefix with Steam and a game copy PREFIX=<dir> [GAME=<install>]
	@test -n "$(PREFIX)" || { echo "[ERROR] usage: make reference-setup PREFIX=<dir>" >&2; exit 2; }
	@./reference/setup.sh "$(PREFIX)" $(if $(GAME),"$(GAME)")

reference-bridge: ## Install SKSE and build the bridge plugin [PREFIX=<dir>] [SKSE=<archive>] [ADDRESS_LIBRARY=<archive>]
	@prefix="$(or $(PREFIX),$$(defaults read nl.jjgroenendijk.opensky OpenSkyReferencePrefix 2>/dev/null))"; \
		test -n "$$prefix" || { echo "[ERROR] no prefix; pass PREFIX=<dir>" >&2; exit 2; }; \
		SKSE="$(SKSE)" ADDRESS_LIBRARY="$(ADDRESS_LIBRARY)" ./reference/bridge/build.sh "$$prefix"

reference-game: build-cli ## Start Windows Steam and the reference game [ARGS='--width 1280 --height 720']
	@"$(PRODUCTS)/openskycli" reference launch $(ARGS)

reference-check: build-cli ## Compare the reference copy with the OpenSky install
	@"$(PRODUCTS)/openskycli" reference check

reference-view: build-cli ## Write the running OpenSky view as the batch file 'bat opensky' runs
	@"$(PRODUCTS)/openskycli" reference export-view $(ARGS)

reference-capture: build-cli ## Capture both games and their difference into .logs/reference/
	@"$(PRODUCTS)/openskycli" reference capture $(ARGS)

# The bridge plugin shares the shaders' clang-format style; `make format` runs it.
BRIDGE_FILES := $(wildcard reference/bridge/src/*.cpp reference/bridge/src/*.h)

cpp-format: #| Autoformat the bridge plugin's C++
	@$(CLANG_FORMAT) --style=file:$(CLANGFORMAT_CFG) -i $(BRIDGE_FILES)

cpp-format-check: #| Fail if the bridge plugin's C++ is unformatted
	@$(CLANG_FORMAT) --style=file:$(CLANGFORMAT_CFG) --dry-run --Werror $(BRIDGE_FILES)
