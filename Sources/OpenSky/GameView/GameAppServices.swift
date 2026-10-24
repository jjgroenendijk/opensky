// What the app scope lends a game session: the view, the input, the clock, the
// settings, and the loaders over the install. The session reads these; the app
// scope never holds the session (docs/decisions/session-scope.md).

import AppKit
import MetalKit
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyAssetCache
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyQuests
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// Where Play starts, as the launcher chose it.
struct GameLaunchChoice {
    var startsAtTitleScreen = false
    var launchStart = LaunchStart.normal
    /// The save the launcher's Continue loads. It wins over `launchStart`.
    var continueSlot: String?
}

/// Every default suits a test that builds a session scope without an install.
struct GameAppServices {
    var hostView = NSView()
    var cameraInput = CameraInputState()
    var simulationClock = SteppedWallClock()
    var menuMode = MenuModeController()
    var swfMovies = SWFMovieSource()
    var playerSettingsStore = PlayerSettingsStore(persistence: nil)
    var keyNamesLoader: () -> KeyboardNameTable? = { nil }
    var localizedStringsLoader: (() -> LocalizedStrings)?
    var audioFileSystem: (any GameFileSource)?
    var menuTextLoader: (() -> LocalizedLabels)?
    var controlMapLoader: (() throws -> ControlMapFile)?
    var assetCache: AssetCacheReader?
    var fastTextureLoad: FastTextureLoadControl?
    var sessionStart = SessionStartRecorder()
    var worldLoadReport: WorldLoadReport?
    var benchmarkLoadPhases: LoadPhaseRecorder?
    var terrainLODConfigurationStore = TerrainLODConfigurationStore(
        snapshot: TerrainLODConfigurationSnapshot(configuration: .fallback, source: "safe defaults")
    )
    var launch = GameLaunchChoice()
    var dataRoot: GameDataRoot?
}
