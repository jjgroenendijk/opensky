# The Windows reference game under Wine 11 and DXVK (docs/tools/reference-game.md).
# Developer tooling: no release bundles any of it.

##@ Reference game

.PHONY: reference-setup reference-game reference-check reference-view reference-capture

reference-setup: ## Build the Wine prefix with Steam and a game copy PREFIX=<dir> [GAME=<install>]
	@test -n "$(PREFIX)" || { echo "[ERROR] usage: make reference-setup PREFIX=<dir>" >&2; exit 2; }
	@./reference/setup.sh "$(PREFIX)" $(if $(GAME),"$(GAME)")

reference-game: build-cli ## Start Windows Steam and the reference game [ARGS='--width 1280 --height 720']
	@"$(PRODUCTS)/openskycli" reference launch $(ARGS)

reference-check: build-cli ## Compare the reference copy with the OpenSky install
	@"$(PRODUCTS)/openskycli" reference check

reference-view: build-cli ## Write the running OpenSky view as the batch file 'bat opensky' runs
	@"$(PRODUCTS)/openskycli" reference export-view $(ARGS)

reference-capture: build-cli ## Capture both games and their difference into .logs/reference/
	@"$(PRODUCTS)/openskycli" reference capture $(ARGS)
