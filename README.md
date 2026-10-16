# OpenSky

OpenSky lets you play Skyrim Special Edition natively on a Mac with Apple Silicon. It is a new
game engine, written from scratch. It reads the game files from your own copy of Skyrim and draws
the world with Metal, Apple's graphics system. There is no Windows emulator and no translation
layer.

OpenSky is not made by or connected to Bethesda. It does not include any part of Skyrim. You need
to own the game.

## Status

OpenSky is an early work in progress. You can load the world and walk around, but many parts of
the game are missing or incomplete, such as quests, magic, and crafting. Expect bugs. You cannot
play the game from start to finish yet.

### Completion progress

The table shows, per area, how many of the things the game data uses OpenSky handles. "Done"
means a program could check it. It does not mean the item behaves exactly like the game. A row
with "-" has no total to count against: it lists failures or names to check. `make gaps` counts
this on a real install and updates the table. The [gap report page](docs/tools/gaps.md) says what
each area counts.

<!-- gaps:begin -->

Measured on 2026-10-16 by `make gaps`.

| Area | Done | Left | Total | Done % |
| --- | --: | --: | --: | --: |
| Papyrus natives | 442 | 66 | 508 | 87% |
| Papyrus events | 52 | 16 | 68 | 76% |
| Condition functions | 256 | 2 | 258 | 99% |
| Record types | 119 | 1 | 120 | 99% |
| Game settings | 144 | 1504 | 1648 | 8% |
| Magic effect archetypes | 21 | 16 | 37 | 56% |
| Perk entry points | 9 | 59 | 68 | 13% |
| Perk entry-point functions | 5 | 4 | 9 | 55% |
| AI package procedures | 8 | 22 | 30 | 26% |
| AI packages that do not resolve | - | 0 | - | - |
| Behavior node classes | 52 | 2 | 54 | 96% |
| Behavior features ignored | - | 256 | - | - |
| Havok classes | 71 | 29 | 100 | 71% |
| Animation events | 68 | 76 | 144 | 47% |
| Behavior graph variables | 565 | 131 | 696 | 81% |
| NIF block types | 82 | 63 | 145 | 56% |
| Lighting shader types | 11 | 0 | 11 | 100% |
| Lighting shader flags | 38 | 0 | 38 | 100% |
| Effect shader flags | 10 | 7 | 17 | 58% |
| Mesh decode failures | - | 6 | - | - |
| Texture variants | 9 | 1 | 10 | 90% |
| Sound file variants | 3 | 0 | 3 | 100% |
| Lip sync data | 1 | 0 | 1 | 100% |
| Menus with no bridge | 9 | 14 | 23 | 39% |
| AS2 runtime | - | 222 | - | - |
| SWF tags | 24 | 4 | 28 | 85% |

<!-- gaps:end -->

## What you need

- A Mac with Apple Silicon (M1 or newer).
- macOS 26 (Tahoe) or newer.
- Skyrim Special Edition, bought and installed, for example through Steam.

## Getting the game files onto your Mac

OpenSky reads the normal Windows install of Skyrim Special Edition. Steam for macOS does not
offer the game, so get the files in one of these ways:

- Copy the whole game folder from a Windows PC where Skyrim Special Edition is installed.
- Download it with SteamCMD, Steam's command-line tool (`brew install --cask steamcmd`):

  ```sh
  steamcmd +@sSteamCmdForcePlatformType windows +login YOUR_STEAM_NAME +app_update 489830 validate +quit
  ```

The game folder holds a `Data` folder with `Skyrim.esm` inside it. OpenSky looks in the
usual Steam folder,
`~/Library/Application Support/Steam/steamapps/common/Skyrim Special Edition/`.

## Installing OpenSky

There is no ready-made download yet, so you build the app yourself. This takes some time once.

1. Install Xcode from the Mac App Store, and open it once.
2. Install [Homebrew](https://brew.sh).
3. Open Terminal and run:

   ```sh
   git clone https://github.com/jjgroenendijk/opensky.git
   cd opensky
   make bootstrap
   make install
   ```

`make install` puts `OpenSky.app` in your Applications folder.

## Playing

1. Open OpenSky from your Applications folder.
2. If OpenSky cannot find Skyrim, it asks for the game folder. Choose the folder that holds
   `Data/Skyrim.esm`.
3. Press Play.

The launcher also has pages for graphics settings and for the asset cache. The asset cache
stores game files in a form your Mac can load faster.

## Problems and ideas

Found a bug, or have an idea? Open an issue on
[GitHub](https://github.com/jjgroenendijk/opensky/issues). Say what you did, what happened, and
what you expected.

## License

OpenSky's own code is under the [Apache License 2.0](LICENSE). This covers only OpenSky. Skyrim
and its files belong to Bethesda and are not part of this project.

Developers: start with [AGENTS.md](AGENTS.md) and [docs/](docs/).
