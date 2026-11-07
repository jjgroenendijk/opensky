# Test reports, wiki mirrors, coverage floors, profiling, and benchmarks. The root
# Makefile includes this file; the variables it uses are set there.

##@ Test tools

test-report: ## Summarize the newest test result bundle, failures included
	@./tools/test-report.sh $(TEST_RESULTS)

test-perms: ## Check the one-time macOS permission grants tests need
	@./tools/test-perms.sh

ck-wiki: ## Download or update the offline Creation Kit wiki in Markdown [ARGS='--source wayback']
	@$(UV_RUN) wiki-mirror --site ck $(ARGS)

uesp-wiki: ## Download or update the offline UESP wiki (Skyrim pages) in Markdown [ARGS='--source wayback']
	@$(UV_RUN) wiki-mirror --site uesp $(ARGS)

coverage-floor: ## Fail when a parser module is under COVERAGE_FLOOR in the last `test-unit COVERAGE=1` run
	@./tools/lint/coverage-floor.sh $(COVERAGE_FLOOR) $(DERIVED_DATA)

profile: link-shared ## Record a Time Profiler trace of the Release app's benchmark tour [ARGS=...]
	@$(MAKE) --no-print-directory build-app CONFIG=Release
	@$(MAKE) --no-print-directory build-cli CONFIG=Release
	@./tools/profile.sh "$(DERIVED_DATA)/Build/Products/Release" $(ARGS)

benchmark: link-shared ## Fly the benchmark tour in the Release app [PRESET=quick|standard|full] [ARGS=...]
	@$(MAKE) --no-print-directory build-app CONFIG=Release
	@$(MAKE) --no-print-directory build-cli CONFIG=Release
	@./tools/benchmark.sh "$(DERIVED_DATA)/Build/Products/Release" --preset $(or $(PRESET),standard) $(ARGS)

benchmark-again: link-shared ## Fly the tour again in the Release app already built, such as with another --set [PRESET=...] [ARGS=...]
	@./tools/benchmark.sh "$(DERIVED_DATA)/Build/Products/Release" --preset $(or $(PRESET),standard) $(ARGS)

gaps: link-shared ## Rank what the install uses and the engine does not do yet [ONLY=papyrus,perks,...] [LIMIT=n]
	@$(MAKE) --no-print-directory build-cli CONFIG=Release
	@./tools/gaps.sh "$(DERIVED_DATA)/Build/Products/Release/openskycli" $(if $(ONLY),--only $(ONLY),) $(if $(LIMIT),--limit $(LIMIT),)

asset-cache-bench: link-shared ## Compare the quick tour from the originals, the optimised files, and direct loading
	@$(MAKE) --no-print-directory build-app CONFIG=Release
	@$(MAKE) --no-print-directory build-cli CONFIG=Release
	@./tools/asset-cache-bench.sh "$(DERIVED_DATA)/Build/Products/Release"

launch-sample: ## Sample the installed app's main thread through its first minute [SECONDS=60]
	@./tools/launch-sample.sh "$(DERIVED_DATA)/Build/Products/Release/openskycli" \
		/Applications/OpenSky.app $(or $(SECONDS),60)
