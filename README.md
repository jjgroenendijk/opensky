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
