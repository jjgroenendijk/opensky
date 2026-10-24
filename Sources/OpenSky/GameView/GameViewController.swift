// Hosts the MTKView and wires it to the renderer. Without Metal 4 it shows a
// message instead of crashing.

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
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
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
    var cellSession: CellSession? {
        // Set before any coordinator is built, so each one is built over the stores.
        didSet {
            if let cellSession {
                worldData = cellSession.data
            }
        }
    }

    /// The stage times of the load that built `cellSession`.
    var worldLoadReport: WorldLoadReport?
    /// The session's asset cache.
    var assetCache: AssetCacheReader?
    var fastTextureLoad: FastTextureLoadControl?
    /// Times the work between the load and the first frame.
    let sessionStart = SessionStartRecorder()
    /// Times the streamer's builds by asset phase; set only when a benchmark tour will run.
    var benchmarkLoadPhases: LoadPhaseRecorder?
    /// The benchmark tour through the live window (docs/tools/benchmark.md).
    lazy var benchmarkWorld = BenchmarkWorldAdapter(game: self)

    /// Thread-safe effective INI and settings LOD values shared with the off-main
    /// DistantLODBuilder. AppDelegate replaces this before view load.
    var terrainLODConfigurationStore = TerrainLODConfigurationStore(
        snapshot: TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        )
    )

    /// The simulation and the renderer it drives. Only this file assigns it.
    private(set) var gameSession: GameSession?

    var renderer: Renderer? {
        gameSession?.renderer
    }

    /// Holds the build runner and the provider for the window's lifetime.
    /// `WorldSessionWiring` assigns it.
    var streamer: CellStreamer?
    /// The session's runtime world state. Every cell build reads a snapshot of it.
    let worldState = WorldStateStore()
    /// Reference mutations, save slots, game time, globals, and condition lists.
    lazy var runtimeState = RuntimeStateCoordinator(store: worldState, world: runtimeStateWorld)

    lazy var runtimeStateWorld = RuntimeStateWorldAdapter(game: self)
    /// The Papyrus VM and its world bridge. Both stay nil without game data;
    /// session start replaces it with one built over the loaded world.
    lazy var scripts = ScriptCoordinator(world: scriptWorld)

    lazy var scriptWorld = ScriptWorldAdapter(game: self)
    /// The renderer and streamer controls of agent control.
    lazy var renderControls = WorldRenderControls(runtimeState: runtimeState, world: self)

    lazy var sessionWiring = WorldSessionWiring(game: self)
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
    /// The session stores the audio, crime and faction bridges read. The build
    /// runner holds the builder half, so the two share nothing mutable.
    var worldData: WorldDataStores?
    /// The audio engine, the world directors and the audio picker state.
    lazy var audio = AudioCoordinator(world: audioWorld)

    lazy var audioWorld = AudioWorldAdapter(game: self)
    /// The SWF movie loader; the AppDelegate sets its factory.
    let swfMovies = SWFMovieSource()
    lazy var hud = HUDCoordinator(movies: swfMovies, world: self)

    lazy var systemMenu = menuRouter.makeSystemMenu()

    /// The INI defaults under the player's own values. The AppDelegate sets the catalog.
    var settingsCatalog = PlayerSettingsCatalog.vanilla
    lazy var playerSettings = PlayerSettingsCoordinator(
        store: PlayerSettingsStore(
            catalog: settingsCatalog, persistence: try? PlayerSettingsFile.defaultFile()
        ),
        world: menuWorld
    )
    /// Answers the Survival Mode plugin's prompt from the settings.
    lazy var survivalMode = SurvivalModeCoordinator(
        store: playerSettings.store, world: survivalModeWorld
    )
    lazy var survivalModeWorld = SurvivalModeWorldAdapter(runtimeState: runtimeState)
    /// `interface\translations` for the `$` keys movies show; nil without game data.
    var menuTextLoader: (() -> LocalizedLabels)?
    var controlMapLoader: (() throws -> ControlMapFile)?
    lazy var saveGames = SaveGameWorldAdapter(game: self)
    lazy var menuWorld = MenuWorldAdapter(game: self)
    lazy var mapWorld = MapWorldAdapter(game: self)
    /// Builds and routes the menu coordinators below.
    lazy var menuRouter = MenuRouter(game: self)
    lazy var titleMenu = menuRouter.makeTitleMenu()
    lazy var raceMenu = menuRouter.makeRaceMenu()
    lazy var skillsMenu = menuRouter.makeSkillsMenu()
    lazy var mapMenu = menuRouter.makeMapMenu()

    /// Inventory menu row list + presentation state.
    lazy var inventoryMenu = InventoryMenuController(game: self)
    /// The quest the journal readout names and the quest changes it runs.
    lazy var journal = JournalCoordinator(world: journalMenu)

    lazy var journalMenu = JournalMenuController(game: self)
    /// The dialogue index, the open conversation, and the speaker focus.
    lazy var dialogue = dialogueWorld.makeDialogue()

    lazy var dialogueWorld = DialogueWorldAdapter(game: self)
    /// Owns the scene and story-manager coordinators.
    lazy var storyWorld = StoryWorldAdapter(game: self)
    lazy var dialogueMenu = DialogueMenuController(game: self)
    lazy var dialogueCamera = DialogueCameraController(game: self)
    /// Container and barter menu two-pane list, merchant nomination and presentation state.
    lazy var containerMenu = ContainerMenuController(game: self)
    lazy var lockpickingMenu = LockpickingMenuController(game: self)
    /// Notifications, help messages, and message boxes for scripts and agent control.
    lazy var messages = MessageCoordinator(
        menuMode: menuMode, movies: swfMovies, hud: hud, world: messageWorld
    )
    lazy var subtitles = SubtitleCoordinator(presenter: hud)

    lazy var messageWorld = MessageWorldAdapter(game: self)
    /// Wait, training, books, help, magic, gifts, crafting, and text entry.
    lazy var menuScreens = MenuScreens(game: self)
    lazy var menuScreensWorld = MenuScreensWorldAdapter(game: self)
    /// Kill cams and camera shake.
    lazy var cinematicCamera = CinematicCameraCoordinator(world: cinematicWorld)
    lazy var cinematicWorld = CinematicCameraWorldAdapter(game: self)
    lazy var loadingScreens = LoadingScreenCoordinator(world: loadingWorld)
    lazy var loadingWorld = LoadingScreenWorldAdapter(game: self)
    /// World items, equipment, vendors and trades. Its runtimes stay nil without game data;
    /// session start replaces it with one built over the loaded world.
    lazy var inventory = InventoryCoordinator(
        world: inventoryWorld,
        lockWorld: lockWorld,
        data: nil
    )
    lazy var inventoryWorld = InventoryWorldAdapter(game: self)
    lazy var lockWorld = LockWorldAdapter(game: self)
    /// The player's Activate perk choices on a use-key press.
    lazy var perkActivation = PerkActivationCoordinator(
        messages: messages, world: perkActivationWorld
    )
    lazy var perkActivationWorld = PerkActivationWorldAdapter(game: self)
    lazy var hazards = HazardCoordinator()
    lazy var hazardWorld = HazardWorldAdapter(HazardWorldDependencies(
        hazards: hazards,
        combat: combat,
        magic: { [unowned self] in magic },
        magicWorld: { [unowned self] in magicWorld },
        gameSession: { [unowned self] in gameSession }
    ))
    /// Session start replaces it with one built over the loaded effect records.
    lazy var effects = EffectsCoordinator()
    lazy var effectsWorld = EffectsWorldAdapter(game: self)
    lazy var trapControl = TrapControlAdapter(TrapControlDependencies(
        hazards: hazards,
        worldState: worldState,
        streamer: { [unowned self] in streamer }
    ))
    /// The player graphs, the body, and the locomotion and first-person readouts.
    lazy var player = PlayerCoordinator(input: cameraInput, world: playerWorld)

    lazy var playerWorld = PlayerWorldAdapter(game: self)
    /// The Face Morphs readout, over the actor in conversation.
    lazy var faceMorphs = FaceMorphCoordinator(world: playerWorld, settings: playerSettings.store)

    lazy var headTracking =
        HeadTrackingCoordinator(world: playerWorld, settings: playerSettings.store)

    /// Actor values: damage, restore, regeneration, and the control controls.
    lazy var actorValues = ActorValueCoordinator(store: worldState, world: actorWorld)

    lazy var actorWorld = ActorWorldAdapter(game: self)

    /// Active effects, spellcasting and item enchantments. Its runtimes stay nil without game
    /// data; session start replaces it with one built over the loaded world.
    lazy var magic = MagicCoordinator(world: magicWorld)
    lazy var magicWorld = MagicWorldAdapter(game: self)

    /// Perk ownership and the entry points every combat and magic seam folds in.
    lazy var perks = PerkCoordinator(world: progressionWorld)

    /// Memberships, relationship ranks and derived hostility. Its runtimes stay nil without
    /// game data.
    lazy var factions: FactionCoordinator = .init(store: worldState, world: factionWorld)
    lazy var factionWorld: FactionWorldAdapter = .init(FactionWorldDependencies(
        factions: { [unowned self] in factions },
        actors: actorWorld,
        streamer: { [unowned self] in streamer }
    ))
    /// Bounties, ownership, guard response and the Crime & Factions readout.
    lazy var crime = CrimeCoordinator(world: crimeWorld)
    lazy var crimeWorld = CrimeWorldAdapter(game: self)

    /// Skill advancement, character leveling, and the Progression readout.
    lazy var progression = ProgressionCoordinator(perks: perks, world: progressionWorld)

    lazy var progressionWorld = ProgressionWorldAdapter(game: self)

    /// Death and ragdoll. Its runtime stays nil without a renderer.
    lazy var ragdoll = RagdollCoordinator(store: worldState, world: ragdollWorld)

    lazy var ragdollWorld = RagdollWorldAdapter(game: self)

    /// Melee, archery and the combat loop. Its runtimes stay nil without game data.
    lazy var combat = CombatCoordinator(
        world: combatWorld, explosions: effectsWorld.makeExplosions()
    )
    lazy var combatWorld = CombatWorldAdapter(game: self)
    /// Live resident-actor package selection.
    lazy var packages = PackageCoordinator(world: aiWorld)
    /// The furniture seats the player and the packages share.
    lazy var furniture = FurnitureCoordinator(world: aiWorld)

    /// The perception pass: view cones, line of sight, and per-pair detection levels.
    lazy var perception = PerceptionCoordinator(world: aiWorld)

    /// The gait clip each NPC mover plays.
    lazy var npcAnimation = NPCAnimationCoordinator(world: aiWorld)

    lazy var aiWorld = AIWorldAdapter(game: self)
    /// What `openskycli game` drives. The app's `AgentControlHost` owns the server.
    lazy var agentWorld = AgentWorldAdapter(game: self)
    var agentControl: AgentControlCoordinator?

    /// Ambient idles and the head switch, with the coordinators they drive.
    lazy var idleWorld = IdleWorldAdapter(game: self)
    /// Carts, riders, and the actor AI natives.
    lazy var vehicleWorld = VehicleWorldAdapter(game: self)
    /// The player's horse or dragon.
    lazy var mountWorld = MountWorldAdapter(game: self)
    /// Traps, doors, and levers that a behaviour graph runs.
    lazy var objectAnimationWorld = ObjectAnimationWorldAdapter(game: self)
    /// The behaviour graph each loaded NPC and creature runs.
    lazy var actorGraphWorld = ActorGraphWorldAdapter(game: self)

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
        let session = cellSession.take()
        let provider = session?.data

        do {
            let newGameSession = try sessionStart.measure(.renderer) {
                try GameSession(
                    view: mtkView,
                    scene: provider != nil ? RenderScene(instances: []) : nil,
                    camera: nil,
                    input: cameraInput,
                    movementConfiguration: provider?.movementConfiguration ?? .synthetic,
                    pipelineCache: makePipelineCache(device: device),
                    wallClock: simulationClock
                )
            }
            let newRenderer = newGameSession.renderer
            newGameSession.applyGraphicsSettings(playerSettings.store)
            effects.applyGraphicsSettings(playerSettings.store)
            newGameSession.timeOfDay = TimeOfDaySettings.load()
            try newGameSession.attachWeather(from: provider)
            newRenderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
            mtkView.delegate = newRenderer
            gameSession = newGameSession
            sessionStart.measure(.systems) {
                wireSystems(session: session, gameSession: newGameSession)
            }
            sessionStart.waitForFirstFrame()
            newGameSession.frameSteps.register(.sessionStartTiming) { [weak sessionStart] _ in
                sessionStart?.frameDidDraw()
            }
            // After streaming, so the HUD reads the streamer's update of this frame.
            newGameSession.frameSteps.register(.hud) { [weak self] _ in
                guard let self else { return }
                // Before the HUD draws, so a skill notice from this frame shows now.
                progressionWorld.run(progression.takeCommands())
                hud.updateFrame()
            }
        } catch {
            show(message: "Renderer setup failed: \(error)")
        }
    }
}

extension GameViewController {
    var sessionStartTiming: SessionStartTiming {
        sessionStart.timing
    }

    private func wireSystems(session: CellSession?, gameSession newGameSession: GameSession) {
        hud.start()
        menuRouter.wire(gameSession: newGameSession)
        benchmarkWorld.wire(gameSession: newGameSession)
        wireMenuMode(gameSession: newGameSession)
        if let session {
            worldData = session.data
            sessionWiring.wireStreaming(session: session, gameSession: newGameSession)
        }
        newGameSession.worldTick.register(.survivalMode) { [weak self] _ in
            self?.survivalMode.tick()
        }
        // The engine reads the world's sound records once, so it starts after they load.
        audio.audioEnabled = playerSettings.store.bool(.audioEnabled)
        // After the world data, because the title's logo loads through it.
        if let continueSlot {
            loadingWorld.coverSessionStart()
            titleMenu.load(continueSlot)
        } else if launchStart != .normal {
            menuWorld.startPlayer(at: launchStart)
        } else if startsAtTitleScreen || playerSettings.store.bool(.startAtTitleScreen) {
            titleMenu.open()
        } else {
            loadingWorld.coverSessionStart()
        }
    }
}

extension GameViewController {
    enum ScreenshotError: LocalizedError {
        case rendererNotReady
        case noWindowFrame

        var errorDescription: String? {
            switch self {
            case .rendererNotReady: "World renderer is not ready for a screenshot."
            case .noWindowFrame: "The game window presented no frame to capture."
            }
        }
    }

    private func wireInput(_ gameView: GameMetalView) {
        gameView.input = cameraInput
        gameView.menuMode = menuMode
        gameView.onJournalKey = { [weak self] in self?.journalMenu.open() }
        gameView.onInventoryKey = { [weak self] in self?.inventoryMenu.open() }
        gameView.onInputEvent = { [weak self] event in self?.messages.noteInputEvent(event) }
        gameView.onCommand = { [weak self] action in self?.runCommand(action) }
        gameView.onCapturedKey = { [weak self] code in
            self?.systemMenu.captureKey(scanCode: code) ?? false
        }
        gameView.onTypedText = { [weak self] text in
            guard let self else { return false }
            return raceMenu.type(text) || menuScreens.textEntry.type(text)
        }
    }

    /// Menu mode drives the renderer's world-sim pause and clears held world
    /// input on entry, so no key sticks while the menu owns input.
    private func wireMenuMode(gameSession: GameSession) {
        menuMode.onModeChange = { [weak self, weak gameSession, weak cameraInput] route, paused in
            gameSession?.worldSimPaused = paused
            self?.menuRouter.modeChanged(to: route)
            // Released on the route flip, not the pause: the dialogue menu
            // captures input without stopping the world.
            if route == .menu {
                cameraInput?.releaseAll()
            }
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

    /// Saves the next frame the window presents, without app chrome. Gives up after
    /// 60 drawn frames with no copy, or 10 s: a hidden window encodes none. Frames bound
    /// that wait, because a busy main actor draws few frames a second. An encoded copy
    /// waits for a busy GPU until the 10 s end.
    func writeScreenshot(to url: URL) async throws {
        guard let renderer else { throw ScreenshotError.rendererNotReady }
        renderer.requestWindowCapture()
        let firstFrame = renderer.frameIndex
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while clock.now < deadline {
            if let texture = renderer.takeWindowCapture() {
                try FrameScreenshot.write(texture: texture, to: url)
                return
            }
            if !renderer.hasEncodedWindowCapture, renderer.frameIndex - firstFrame >= 60 {
                break
            }
            try await Task.sleep(for: .milliseconds(8))
        }
        throw ScreenshotError.noWindowFrame
    }

    /// The playback drawing one resident actor, matched by its ACHR.
    func actorPlayback(for key: ReferenceKey) -> ActorAnimationPlayback? {
        guard let actor = streamer?.referenceEntry(key: key)?.placedActor else { return nil }
        return renderer?.scene.actorPlayback(for: actor.formID)
    }

    /// The pose one actor's clip holds now, keyed by bone name.
    func animatedPose(for key: ReferenceKey) -> [String: float4x4]? {
        guard let renderer, let playback = actorPlayback(for: key) else { return nil }
        return playback.clip.namedWorldTransforms(at: renderer.animationTime)
    }
}

extension GameViewController: @MainActor SystemMenuWorld {
    var viewCamera: FreeFlyCamera? {
        gameSession?.freeFlyCamera
    }

    var uiScene: UIScene {
        get { gameSession?.uiScene ?? .empty }
        set { gameSession?.uiScene = newValue }
    }

    var audioEnabled: Bool {
        audio.audioEnabled
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    func quitToMainMenu() {
        systemMenu.close()
        titleMenu.open()
    }

    func runCommand(_ action: GameInputAction) {
        menuRouter.run(action)
    }

    func handleMenuInput(_ event: MenuInputEvent) {
        menuRouter.route(event)
    }

    func handleMenuPointer(_ event: MenuPointerEvent) {
        menuRouter.route(event)
    }
}

extension GameViewController: RenderControlWorld {
    var playerSettingsStore: PlayerSettingsStore {
        playerSettings.store
    }

    func makePipelineCache(device: MTLDevice) throws -> PipelineCache {
        try PipelineCache.fromSettings(device: device, store: playerSettings.store)
    }

    func refocusGameView() {
        view.window?.makeFirstResponder(view)
    }
}

extension GameViewController {
    var scenes: SceneCoordinator {
        storyWorld.scenes
    }
}
