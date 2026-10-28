# AGENTS.md — reference

Tooling for the Windows reference game: the real Skyrim SE under Wine 11 with DXVK, run
beside OpenSky to compare the two. `docs/tools/reference-game.md` has the workflow.
Nothing here ships in a release.

- The Wine prefix, Windows Steam, and the game copy live outside the repo, in the folder
  `make reference-setup PREFIX=<dir>` was given. Never put the prefix under the repo or
  under the install OpenSky reads, because both rules in the root `AGENTS.md` (no game
  content in git, the install is read-only) would break. `setup.sh` refuses both.
- Every write goes into that prefix or `.logs/`: the ini edit, the console batch file,
  and the Wine logs. The original install is only read, and the copy is an APFS clone.
- The logic lives in Swift, where tests reach it: `OpenSkyReference` for the rules and
  `openskycli reference` for the commands. A script here only installs and builds the
  prefix, which needs `curl` and Rosetta 2.
- Wine, DXVK, GStreamer, and the Steam helper are never committed or bundled; setup downloads them
  and checks each SHA-256. A capture of either game is game content and stays in `.logs/`.
- `bridge/` is the C++ SKSE plugin OpenSky drives the game through
  (`docs/decisions/reference-bridge.md`). It builds only into the prefix, through
  `make reference-bridge`, and pins every download by SHA-256. It may use CommonLibSSE-NG's
  API by name; that exception is in the `using-outside-sources` skill. Keep it to commands
  and state: it changes no game rule and draws nothing, so the game stays a vanilla
  reference. `make cpp-format` formats it.
