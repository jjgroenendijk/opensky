// Hosts the MTKView, the input, and the draw loop. With game data it builds the
// session scope that holds every game object; without it the renderer draws
// `DemoScene`. Without Metal 4 it shows a message instead of crashing.

import AppKit
import MetalKit
import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyWorld
import simd

final class GameViewController: NSViewController {
    /// Locator failure shown inside World. Settings remains reachable so the
    /// root can be corrected without relaunching or dismissing an alert loop.
    var startupErrorMessage: String?
    /// Set by the launch mode; the player setting can also ask for it.
    var startsAtTitleScreen = false
    /// Where Play starts, from the launcher. Ignored when `continueSlot` is set.
    var launchStart = LaunchStart.normal
    /// The save the launcher's Continue loads.
    var continueSlot: String?

    /// Loaded off the main actor before the view loads, on the system default
    /// device the view also uses. Nil falls back to `DemoScene`.
    var cellSession: CellSession?
    /// The stage times of the load that built `cellSession`.
    var worldLoadReport: WorldLoadReport?
    /// Times the work between the load and the first frame.
    let sessionStart = SessionStartRecorder()
    /// Times the streamer's builds by asset phase; set only when a benchmark tour will run.
    var benchmarkLoadPhases: LoadPhaseRecorder?

    /// Thread-safe effective INI and settings LOD values shared with the off-main
    /// DistantLODBuilder. AppDelegate replaces this before view load.
    var terrainLODConfigurationStore = TerrainLODConfigurationStore(
        snapshot: TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        )
    )

    /// The draw loop: the simulation and the renderer it drives. Only this file assigns it.
    private(set) var gameSession: GameSession?
    /// Every object of the loaded game. Nil without game data.
    private(set) var session: GameSessionScope?
    /// Runs once the session scope exists, such as to start a benchmark tour. The
    /// view can load before the shell sets it, so it also runs on a set.
    var onSessionStart: ((GameSessionScope) -> Void)? {
        didSet {
            if let session {
                onSessionStart?(session)
            }
        }
    }

    var renderer: Renderer? {
        gameSession?.renderer
    }

    /// Free-fly input shared with the renderer; the view writes it from
    /// NSEvents, the renderer drains it each frame.
    let cameraInput = CameraInputState()
    /// The clock every frame clock reads. Agent control freezes and steps it.
    let simulationClock = SteppedWallClock()

    /// Entering menu mode pauses the world sim and drops held world input.
    let menuMode = MenuModeController()

    /// Builds the plugin's string tables over the located install. Set by the
    /// AppDelegate; nil without game data, and the journal then shows editor IDs.
    /// Called once, lazily, because it walks the VFS.
    var localizedStringsLoader: (() -> LocalizedStrings)?

    /// Resource lookup over the install. Set by the AppDelegate; nil without game data.
    var audioFileSystem: (any GameFileSource)?
    /// The SWF movie loader; the AppDelegate sets its factory.
    let swfMovies = SWFMovieSource()

    /// The INI defaults under the player's own values. The AppDelegate sets the catalog.
    var settingsCatalog = PlayerSettingsCatalog.vanilla
    private(set) lazy var playerSettingsStore = PlayerSettingsStore(
        catalog: settingsCatalog, persistence: try? PlayerSettingsFile.defaultFile()
    )
    var keyNamesLoader: () -> KeyboardNameTable? = { nil }
    /// `interface\translations` for the `$` keys movies show; nil without game data.
    var menuTextLoader: (() -> LocalizedLabels)?
    var controlMapLoader: (() throws -> ControlMapFile)?
    /// The data root agent control reports and teleports load plugins from.
    var dataRoot: GameDataRoot?

    override func loadView() {
        let gameView = GameMetalView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        wireInput(gameView)
        view = gameView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = view as? MTKView else { return }

        if let startupErrorMessage {
            show(message: startupErrorMessage)
            return
        }

        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            show(message: "OpenSky requires a GPU with Metal 4 support.")
            return
        }
        mtkView.device = device

        // With game data the renderer starts empty and streams cells in;
        // without it the renderer shows `DemoScene`.
        let loaded = cellSession.take()
        let provider = loaded?.data

        do {
            let newGameSession = try sessionStart.measure(.renderer) {
                try GameSession(
                    view: mtkView,
                    scene: provider != nil ? RenderScene(instances: []) : nil,
                    camera: nil,
                    input: cameraInput,
                    movementConfiguration: provider?.movementConfiguration ?? .synthetic,
                    pipelineCache: PipelineCache.fromSettings(
                        device: device, store: playerSettingsStore
                    ),
                    wallClock: simulationClock
                )
            }
            let newRenderer = newGameSession.renderer
            newGameSession.applyGraphicsSettings(playerSettingsStore)
            newGameSession.timeOfDay = TimeOfDaySettings.load()
            try newGameSession.attachWeather(from: provider)
            newRenderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
            mtkView.delegate = newRenderer
            gameSession = newGameSession
            if let loaded {
                startSession(loaded, gameSession: newGameSession)
            }
            sessionStart.waitForFirstFrame()
            newGameSession.frameSteps.register(.sessionStartTiming) { [weak sessionStart] _ in
                sessionStart?.frameDidDraw()
            }
        } catch {
            show(message: "Renderer setup failed: \(error)")
        }
    }

    private func startSession(_ loaded: CellSession, gameSession: GameSession) {
        let session = GameSessionScope(
            worldData: loaded.data,
            cellRunner: loaded.runner,
            gameSession: gameSession,
            services: appServices
        )
        self.session = session
        sessionStart.measure(.systems) {
            session.start()
        }
        onSessionStart?(session)
    }

    private var appServices: GameAppServices {
        GameAppServices(
            hostView: view,
            cameraInput: cameraInput,
            simulationClock: simulationClock,
            menuMode: menuMode,
            swfMovies: swfMovies,
            playerSettingsStore: playerSettingsStore,
            keyNamesLoader: keyNamesLoader,
            localizedStringsLoader: localizedStringsLoader,
            audioFileSystem: audioFileSystem,
            menuTextLoader: menuTextLoader,
            controlMapLoader: controlMapLoader,
            sessionStart: sessionStart,
            worldLoadReport: worldLoadReport,
            benchmarkLoadPhases: benchmarkLoadPhases,
            terrainLODConfigurationStore: terrainLODConfigurationStore,
            launch: GameLaunchChoice(
                startsAtTitleScreen: startsAtTitleScreen,
                launchStart: launchStart,
                continueSlot: continueSlot
            ),
            dataRoot: dataRoot
        )
    }
}

extension GameViewController {
    private func wireInput(_ gameView: GameMetalView) {
        gameView.input = cameraInput
        gameView.menuMode = menuMode
        gameView.onJournalKey = { [weak self] in self?.session?.journalMenu.open() }
        gameView.onInventoryKey = { [weak self] in self?.session?.inventoryMenu.open() }
        gameView.onInputEvent = { [weak self] event in
            self?.session?.messages.noteInputEvent(event)
        }
        gameView.onCommand = { [weak self] action in self?.session?.runCommand(action) }
        gameView.isBeastForm = { [weak self] in self?.session?.playerBeastForm.isBeast ?? false }
        gameView.onCapturedKey = { [weak self] code in
            self?.session?.systemMenu.captureKey(scanCode: code) ?? false
        }
        gameView.onTypedText = { [weak self] text in
            guard let session = self?.session else { return false }
            return session.raceMenu.type(text) || session.menuScreens.textEntry.type(text)
        }
    }

    private func show(message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.alignment = .center
        label.font = Theme.displayFont(size: 16)
        label.textColor = Theme.parchment
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }

    func writeScreenshot(to url: URL) async throws {
        try await WindowCapture.write(from: renderer, to: url)
    }
}
