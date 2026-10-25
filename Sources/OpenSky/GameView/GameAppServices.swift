// What the app scope lends a game session: the view, the input, the clock, the
// settings, and the loaders over the install. The session reads these; the app
// scope never holds the session (docs/decisions/session-scope.md).

import AppKit
import MetalKit
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyRenderCore
import OpenSkyRendering
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
    var sessionStart = SessionStartRecorder()
    var worldLoadReport: WorldLoadReport?
    var benchmarkLoadPhases: LoadPhaseRecorder?
    var terrainLODConfigurationStore = TerrainLODConfigurationStore(
        snapshot: TerrainLODConfigurationSnapshot(configuration: .fallback, source: "safe defaults")
    )
    var launch = GameLaunchChoice()
    var dataRoot: GameDataRoot?
}
