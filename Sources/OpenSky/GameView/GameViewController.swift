// Hosts the MTKView and wires it to the renderer. Without Metal 4 it shows a
// message instead of crashing.

import AppKit
import MetalKit
import OpenSkyActors
import OpenSkyAgentControl
import OpenSkyAssetCache
import OpenSkyAudio
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyLaunch
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyProgression
import OpenSkyQuests
import OpenSkyRendering
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
    var cellSession: CellSession?
    /// The stage times of the load that built `cellSession`, for World > World Load.
    var worldLoadReport: WorldLoadReport?
    /// The session's asset cache, for World > Asset Cache.
    var assetCache: AssetCacheReader?
    var fastTextureLoad: FastTextureLoadControl?
    /// Times the work between the load and the first frame, for World > World Load.
    let sessionStart = SessionStartRecorder()

    /// Thread-safe effective INI/sidebar LOD values shared with the off-main
    /// DistantLODBuilder. AppDelegate replaces this before view load.
    var terrainLODConfigurationStore = TerrainLODConfigurationStore(
        snapshot: TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        )
    )

    /// Only this file assigns it.
    private(set) var renderer: Renderer?

    /// Holds the build runner and the provider for the window's lifetime.
    /// `WorldSessionWiring` assigns it.
    var streamer: CellStreamer?
    /// The session's runtime world state. Every cell build reads a snapshot of it.
    let worldState = WorldStateStore()
    /// Reference mutations, save slots, game time, globals, and condition lists.
    lazy var runtimeState: RuntimeStateCoordinator = {
        let runtimeState = RuntimeStateCoordinator(store: worldState)
        runtimeState.attach(world: runtimeStateWorld)
        return runtimeState
    }()

    lazy var runtimeStateWorld = RuntimeStateWorldAdapter(game: self)
    /// The Papyrus VM and its world bridge. Both stay nil without game data.
    lazy var scripts: ScriptCoordinator = {
        let scripts = ScriptCoordinator()
        scripts.attach(world: scriptWorld)
        return scripts
    }()

    lazy var scriptWorld = ScriptWorldAdapter(game: self)
    /// The renderer and streamer controls of the World panels.
    lazy var renderControls: WorldRenderControls = {
        let controls = WorldRenderControls(runtimeState: runtimeState)
        controls.attach(world: self)
        return controls
    }()

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
    var worldData: (any WorldDataProviding)?
    /// The audio engine, the world directors and the World > Audio lab state.
    lazy var audio: AudioCoordinator = {
        let audio = AudioCoordinator()
        audio.attach(world: audioWorld)
        return audio
    }()

    lazy var audioWorld = AudioWorldAdapter(game: self)
    /// The SWF movie loader; the AppDelegate sets its factory.
    let swfMovies = SWFMovieSource()
    lazy var hud: HUDCoordinator = {
        let hud = HUDCoordinator(movies: swfMovies)
        hud.attach(world: self)
        return hud
    }()

    lazy var swfLab: SWFLabCoordinator = {
        let swfLab = SWFLabCoordinator(movies: swfMovies, hud: hud)
        swfLab.attach(world: self)
        return swfLab
    }()

    lazy var uiLab: UILabCoordinator = {
        let uiLab = UILabCoordinator(menuMode: menuMode)
        uiLab.attach(world: self)
        return uiLab
    }()

    lazy var systemMenu: SystemMenuCoordinator = {
        let systemMenu = SystemMenuCoordinator(menuMode: menuMode, movies: swfMovies, hud: hud)
        systemMenu.attach(world: self)
        systemMenu.attach(settings: playerSettings)
        systemMenu.saves = saveGames
        return systemMenu
    }()

    /// The INI defaults under the player's own values. The AppDelegate sets the catalog.
    var settingsCatalog = PlayerSettingsCatalog.vanilla
    lazy var playerSettings = PlayerSettingsCoordinator(store: PlayerSettingsStore(
        catalog: settingsCatalog, persistence: try? PlayerSettingsFile.defaultFile()
    ))
    /// `interface\translations` for the `$` keys movies show; nil without game data.
    var menuTextLoader: (() -> LocalizedLabels)?
    var controlMapLoader: (() throws -> ControlMapFile)?
    lazy var saveGames = SaveGameWorldAdapter(game: self)
    lazy var menuWorld = MenuWorldAdapter(game: self)
    lazy var mapWorld = MapWorldAdapter(game: self)
    lazy var titleMenu: TitleMenuCoordinator = {
        let titleMenu = TitleMenuCoordinator(menuMode: menuMode, movies: swfMovies, hud: hud)
        titleMenu.attach(world: menuWorld)
        titleMenu.saves = saveGames
        return titleMenu
    }()

    lazy var raceMenu: RaceMenuCoordinator = {
        let raceMenu = RaceMenuCoordinator(menuMode: menuMode, movies: swfMovies, hud: hud)
        raceMenu.attach(world: menuWorld)
        return raceMenu
    }()

    lazy var mapMenu: MapMenuCoordinator = {
        let mapMenu = MapMenuCoordinator(menuMode: menuMode)
        mapMenu.attach(world: mapWorld)
        return mapMenu
    }()

    /// Inventory menu row list + presentation state.
    lazy var inventoryMenu = InventoryMenuController(game: self)
    /// The quest the journal panel names and the quest changes it runs.
    lazy var journal: JournalCoordinator = {
        let journal = JournalCoordinator()
        journal.attach(world: journalMenu)
        return journal
    }()

    lazy var journalMenu = JournalMenuController(game: self)
    /// The dialogue index, the open conversation, and the speaker focus.
    lazy var dialogue: DialogueCoordinator = {
        let dialogue = DialogueCoordinator(store: worldState)
        dialogue.attach(world: dialogueWorld)
        return dialogue
    }()

    lazy var dialogueWorld = DialogueWorldAdapter(game: self)
    /// Owns the scene and story-manager coordinators.
    lazy var storyWorld = StoryWorldAdapter(game: self)
    lazy var dialogueMenu = DialogueMenuController(game: self)
    lazy var dialogueCamera = DialogueCameraController(game: self)
    /// Container and barter menu two-pane list, merchant nomination and presentation state.
    lazy var containerMenu = ContainerMenuController(game: self)
    lazy var lockpickingMenu = LockpickingMenuController(game: self)
    /// Notifications, help messages, and message boxes for scripts and the sidebar.
    lazy var messages = MessageCoordinator(menuMode: menuMode)
    lazy var subtitles: SubtitleCoordinator = {
        let subtitles = SubtitleCoordinator()
        subtitles.attach(presenter: hud)
        return subtitles
    }()

    lazy var messageWorld = MessageWorldAdapter(game: self)
    /// Kill cams and camera shake.
    lazy var cinematicCamera = CinematicCameraCoordinator()
    lazy var cinematicWorld = CinematicCameraWorldAdapter(game: self)
    lazy var loadingScreens = LoadingScreenCoordinator()
    lazy var loadingWorld = LoadingScreenWorldAdapter(game: self)
    /// World items, equipment, vendors and trades. Its runtimes stay nil without game data.
    let inventory = InventoryCoordinator()
    lazy var inventoryWorld = InventoryWorldAdapter(game: self)
    lazy var lockWorld = LockWorldAdapter(game: self)
    lazy var hazards = HazardCoordinator()
    lazy var hazardWorld = HazardWorldAdapter(game: self)
    lazy var effects = EffectsCoordinator()
    lazy var effectsWorld = EffectsWorldAdapter(game: self)
    lazy var trapControl = TrapControlAdapter(game: self)
    /// The player graphs, the body, and the locomotion and first-person panels.
    lazy var player: PlayerCoordinator = {
        let player = PlayerCoordinator(input: cameraInput)
        player.attach(world: playerWorld)
        return player
    }()

    lazy var playerWorld = PlayerWorldAdapter(game: self)
    /// The Face Morphs panel, over the actor in conversation.
    lazy var faceMorphs: FaceMorphCoordinator = {
        let faceMorphs = FaceMorphCoordinator()
        faceMorphs.attach(world: playerWorld)
        return faceMorphs
    }()

    /// Actor values: damage, restore, regeneration, and the panel controls.
    lazy var actorValues: ActorValueCoordinator = {
        let actorValues = ActorValueCoordinator(store: worldState)
        actorValues.attach(world: actorWorld)
        return actorValues
    }()

    lazy var actorWorld = ActorWorldAdapter(game: self)

    /// Active effects, spellcasting and item enchantments. Its runtimes stay nil without game
    /// data.
    let magic = MagicCoordinator()
    lazy var magicWorld = MagicWorldAdapter(game: self)

    /// Perk ownership and the entry points every combat and magic seam folds in.
    lazy var perks: PerkCoordinator = {
        let perks = PerkCoordinator()
        perks.attach(world: progressionWorld)
        return perks
    }()

    /// Memberships, relationship ranks and derived hostility. Its runtimes stay nil without
    /// game data.
    lazy var factions = FactionCoordinator(store: worldState)
    lazy var factionWorld = FactionWorldAdapter(game: self)
    /// Bounties, ownership, guard response and the Crime & Factions panel.
    let crime = CrimeCoordinator()
    lazy var crimeWorld = CrimeWorldAdapter(game: self)

    /// Skill advancement, character leveling, and the Progression panel.
    lazy var progression: ProgressionCoordinator = {
        let progression = ProgressionCoordinator(perks: perks)
        progression.attach(world: progressionWorld)
        return progression
    }()

    lazy var progressionWorld = ProgressionWorldAdapter(game: self)

    /// Death and ragdoll. Its runtime stays nil without a renderer.
    lazy var ragdoll: RagdollCoordinator = {
        let ragdoll = RagdollCoordinator(store: worldState)
        ragdoll.attach(world: ragdollWorld)
        return ragdoll
    }()

    lazy var ragdollWorld = RagdollWorldAdapter(game: self)

    /// Melee, archery and the combat loop. Its runtimes stay nil without game data.
    let combat = CombatCoordinator()
    lazy var combatWorld = CombatWorldAdapter(game: self)
    /// Live resident-actor package selection.
    lazy var packages = PackageCoordinator(world: aiWorld)

    /// The perception pass: view cones, line of sight, and per-pair detection levels.
    lazy var perception: PerceptionCoordinator = {
        let perception = PerceptionCoordinator()
        perception.attach(world: aiWorld)
        return perception
    }()

    /// The AI & Navigation panel's shared actor selection and its last outcome line.
    lazy var aiNavigation: AINavigationCoordinator = {
        let aiNavigation = AINavigationCoordinator(packages: packages)
        aiNavigation.attach(world: aiWorld)
        return aiNavigation
    }()

    /// The gait clip each NPC mover plays.
    lazy var npcAnimation: NPCAnimationCoordinator = {
        let npcAnimation = NPCAnimationCoordinator()
        npcAnimation.attach(world: aiWorld)
        return npcAnimation
    }()

    lazy var aiWorld = AIWorldAdapter(game: self)
    /// What `openskycli game` drives. The app's `AgentControlHost` owns the server.
    lazy var agentWorld = AgentWorldAdapter(game: self)
    var agentControl: AgentControlCoordinator?

    /// Ambient idles and the head switch, with the coordinators they drive.
    lazy var idleWorld = IdleWorldAdapter(game: self)
    /// Carts, riders, and the actor AI natives.
    lazy var vehicleWorld = VehicleWorldAdapter(game: self)

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
            let newRenderer = try sessionStart.measure(.renderer) {
                try Renderer(
                    view: mtkView,
                    scene: provider != nil ? RenderScene(instances: []) : nil,
                    camera: nil,
                    input: cameraInput,
                    movementConfiguration: (provider as? MovementConfigurationProviding)?
                        .movementConfiguration ?? .synthetic,
                    pipelineCache: makePipelineCache(device: device),
                    wallClock: simulationClock
                )
            }
            newRenderer.shadowQuality = ShadowQualitySettings.load()
            newRenderer.applyGraphicsSettings(playerSettings.store)
            newRenderer.timeOfDay = TimeOfDaySettings.load()
            // Without weather data the renderer keeps its procedural sky.
            newRenderer.weather = (provider as? WeatherProviding)?.weatherSystem
            newRenderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
            mtkView.delegate = newRenderer
            renderer = newRenderer
            sessionStart.measure(.systems) {
                wireSystems(session: session, renderer: newRenderer)
            }
            sessionStart.waitForFirstFrame()
            newRenderer.onFrame.add { [weak sessionStart] _ in
                sessionStart?.frameDidDraw()
            }
            // After streaming, so the HUD reads the streamer's update of this frame.
            newRenderer.onFrame.add { [weak self] _ in
                self?.hud.updateFrame()
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

    private func wireSystems(session: CellSession?, renderer newRenderer: Renderer) {
        hud.start()
        wireMenus(renderer: newRenderer)
        wireMenuMode(renderer: newRenderer)
        if let session {
            worldData = session.data
            sessionWiring.wireStreaming(session: session, renderer: newRenderer)
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

    static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "CellStream"
    )

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
        gameView.onTypedText = { [weak self] text in self?.raceMenu.type(text) ?? false }
    }

    /// Menu mode drives the renderer's world-sim pause and clears held world
    /// input on entry, so no key sticks while the menu owns input.
    private func wireMenuMode(renderer: Renderer) {
        menuMode.onModeChange = { [weak renderer, weak cameraInput] route, paused in
            renderer?.worldSimPaused = paused
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

extension GameViewController: HUDControlForwarding, SWFLabControlForwarding,
    UILabControlForwarding, SystemMenuControlForwarding, SceneControlForwarding,
    StoryManagerControlForwarding, DialogueBranchControlForwarding, IdleControlForwarding,
    HeadAssemblyControlForwarding, AgentControlForwarding, RaceMenuControlForwarding,
    TitleMenuControlForwarding, MapMenuControlForwarding, WorldLoadReportProviding,
    AssetCacheControlProviding {}

extension GameViewController: @MainActor SystemMenuWorld {
    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    func quitToMainMenu() {
        systemMenu.close()
        titleMenu.open()
    }

    /// The bound keys that open a menu or save, outside any menu.
    func runCommand(_ action: GameInputAction) {
        switch action {
        case .map:
            mapMenu.open()
        case .quicksave:
            systemMenu.quicksave()
        case .quickload:
            saveGames.quickload()
        case .pause:
            saveGames.autosave(.pause)
            systemMenu.open()
        default:
            return
        }
    }

    /// Settings, key bindings, menu text, the menu natives, map discovery, and
    /// the menu movies' late calls.
    private func wireMenus(renderer: Renderer) {
        playerSettings.loadControlMap(try? controlMapLoader?())
        playerSettings.attach(world: menuWorld)
        audio.onEngineBuilt = { [weak self] in self?.playerSettings.applyAll() }
        if let labels = menuTextLoader?() {
            renderer.swfTextTranslator = { labels.label(for: $0) }
        }
        renderer.onFrame.add { [weak self] _ in
            self?.mapMenu.tick()
            let now = Date().timeIntervalSinceReferenceDate
            self?.titleMenu.tick(now: now)
            self?.raceMenu.tick(now: now)
            self?.menuWorld.refreshTitleBackdrop()
        }
    }

    /// The one menu input consumer routes by the top of the menu stack. Each
    /// route checks that its own menu is open.
    func handleMenuInput(_ event: MenuInputEvent) {
        switch menuMode.topMenu {
        case InventoryMenuController.identifier:
            inventoryMenu.route(event)
        case ContainerMenuController.containerIdentifier, ContainerMenuController.barterIdentifier:
            containerMenu.route(event)
        case JournalMenuController.identifier:
            journalMenu.route(event)
        case DialogueMenuController.identifier:
            dialogueMenu.route(event)
        case LockpickingMenuController.identifier:
            lockpickingMenu.route(event)
        case MessageCoordinator.identifier:
            messages.route(event)
        case LoadingScreenWorldAdapter.identifier:
            return
        case TitleMenuCoordinator.identifier:
            titleMenu.route(event)
        case RaceMenuCoordinator.identifier:
            raceMenu.route(event)
        case MapMenuCoordinator.identifier:
            mapMenu.route(event)
        default:
            systemMenu.route(event)
        }
    }

    /// The main menu movie hit tests the cursor. The other menus still take a
    /// press as their accept button.
    func handleMenuPointer(_ event: MenuPointerEvent) {
        if menuMode.topMenu == TitleMenuCoordinator.identifier {
            titleMenu.route(event)
        } else if event.phase == .pressed {
            handleMenuInput(.button(.accept))
        }
    }
}

extension GameViewController: AudioControlForwarding, RuntimeStateControlForwarding,
    ScriptControlForwarding, WorldRenderControlForwarding, RenderControlWorld,
    EffectsControlForwarding, ExplosionControlForwarding, CinematicCameraControlForwarding,
    LoadingScreenControlForwarding, MessageControlForwarding
{
    var playerSettingsStore: PlayerSettingsStore {
        playerSettings.store
    }

    func makePipelineCache(device: MTLDevice) throws -> PipelineCache {
        try PipelineCache.fromSettings(device: device, store: playerSettings.store)
    }

    var cinematicSelectedActor: ReferenceKey? {
        actorWorld.nearestActorValueHolder()?.key
    }

    var cinematicRemainingHostiles: Int {
        combat.combatLoopSnapshot.hostileCount
    }

    var effectsSelectedActor: ReferenceKey? {
        actorWorld.nearestActorValueHolder()?.key
    }

    var explosionControlWorld: any ExplosionControlWorld {
        effectsWorld
    }

    func refocusGameView() {
        view.window?.makeFirstResponder(view)
    }
}

extension GameViewController {
    var canWriteScreenshot: Bool {
        renderer != nil
    }
}
