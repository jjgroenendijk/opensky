// Hosts the MTKView and wires it to the renderer. Fails soft with an on-screen
// message when the GPU lacks Metal 4 — the engine requires it (AGENTS.md
// "Environment & tech stack"); a missing GPU feature must not crash the app.

import AppKit
import MetalKit
import OpenSkyAudio
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import OSLog
import simd

final class GameViewController: NSViewController {
    enum ScreenshotError: LocalizedError {
        case rendererNotReady

        var errorDescription: String? {
            "World renderer is not ready for a screenshot."
        }
    }

    /// Locator failure shown inside World. Settings remains reachable so the
    /// root can be corrected without relaunching or dismissing an alert loop.
    var startupErrorMessage: String?

    /// Builds the cell streaming session on the view's Metal device. Set by
    /// the AppDelegate before the window content loads; nil factory or nil
    /// result (missing game data / setup throw) -> no streamer, renderer
    /// falls back to the synthetic DemoScene. The factory runs here (not in
    /// the AppDelegate) because the asset libraries bind GPU resources to the
    /// device the view renders with.
    var cellSessionFactory: ((MTLDevice) -> CellSession?)?

    /// Thread-safe effective INI/sidebar LOD values shared with the off-main
    /// DistantLODBuilder. AppDelegate replaces this before view load.
    var terrainLODConfigurationStore = TerrainLODConfigurationStore(
        snapshot: TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        )
    )

    /// Readable by the UI Lab bridge (GameViewController+UILab.swift); only this
    /// file assigns it.
    private(set) var renderer: Renderer?
    var canWriteScreenshot: Bool {
        renderer != nil
    }

    /// Retains the streaming controller (and, through it, the build runner +
    /// provider) for the window's lifetime. Readable by the world-stats bridge
    /// (GameViewController+WorldStats.swift); only this file assigns it.
    var streamer: CellStreamer?
    /// Mutable runtime world state for this session. It is the
    /// production owner of `WorldStateStore`: `wireStreaming` reads snapshots
    /// off it at build dispatch and rebuilds resident cells when it changes.
    /// Papyrus, inventory and quests mutate it later; the sidebar readout
    /// reads it.
    let worldState = WorldStateStore()
    /// Papyrus VM for this session, built by `wirePapyrus` when
    /// the provider can supply compiled scripts. Cell streaming attaches and
    /// detaches script instances on it, and the renderer's world-simulation
    /// hook ticks it once per drawn frame. nil without game data.
    var papyrus: PapyrusWorldRuntime?
    /// Seam Papyrus natives reach the world through, built beside
    /// `papyrus`. Retained here because it is also the `onInteraction`
    /// subscriber that turns a use key into a recorded activation.
    var papyrusBridge: PapyrusWorldStateBridge?
    /// GLOB defaults of the loaded plugin, set by `wireStreaming`. Nil without
    /// game data; the time-of-day scrub then writes the renderer's clock directly.
    var globalStore: GlobalStore?
    /// Free-fly input shared with the renderer; the view writes it from
    /// NSEvents, the renderer drains it each frame.
    let cameraInput = CameraInputState()

    /// Menu-mode source of truth, shared with the input view and the renderer.
    /// Entering menu mode pauses world sim and drops held world input; leaving
    /// it resumes with no time jump.
    let menuMode = MenuModeController()

    /// Which built-in overlay sample Developer > UI Lab shows. Stored here
    /// because both samples share `Renderer.uiScene`; the UI Lab bridge maps it
    /// onto the renderer and declares the enum beside itself.
    var uiLabSampleSelection: UILabSampleSelection = .none

    /// Builds the merged translation provider over the located install. Set by
    /// the AppDelegate; nil when game data is missing. The UI Lab bridge
    /// invokes it once, lazily, caching into `installLocalizedLabels`.
    var localizedLabelsLoader: (() -> LocalizedLabels)?
    /// Cache written only by the UI Lab bridge (`resolveInstallLabels`).
    var installLocalizedLabels: LocalizedLabels?
    var installLocalizedLabelsResolved = false

    /// Builds the plugin's string tables over the located install. Set by the
    /// AppDelegate; nil without game data, and the journal then shows editor IDs.
    /// Called once, lazily, because it walks the VFS.
    var localizedStringsLoader: (() -> LocalizedStrings)?

    /// Builds the SWF movie loader over the located install. Set by
    /// the AppDelegate; nil when game data is missing. The UI Lab SWF bridge
    /// invokes it once, lazily, into `swfLab`.
    var swfMovieLoaderFactory: (() -> SWFMovieLoader)?

    /// Resource lookup for World > Audio. Set by the AppDelegate; nil
    /// when game data is missing — the panel then lists nothing to play.
    var audioFileSystem: (any GameFileSource)?
    /// World audio graph, created on first enable by the audio bridge
    /// (GameViewController+Audio.swift), which also hands it to the renderer.
    var worldAudio: WorldAudioEngine?
    /// World SFX + ambience director, built beside the engine on
    /// first enable. Subscribed to streamer callbacks; lives in
    /// `Sources/OpenSkyWorld/Session/WorldAudioSoundDirector.swift`.
    var soundDirector: WorldAudioSoundDirector?
    /// Music director, built beside the engine on first enable.
    /// Subscribed to the streamer's music-context callback and ticked by the
    /// renderer; lives in `Sources/OpenSkyWorld/Session/WorldMusicDirector.swift`.
    var musicDirector: WorldMusicDirector?
    /// Footstep director, built beside the engine on first
    /// enable. Fed by the renderer's audio tick from the locomotion bridge's
    /// fired graph events; lives in
    /// `Sources/OpenSkyWorld/Session/WorldAudioFootstepDirector.swift`.
    var footstepDirector: WorldAudioFootstepDirector?
    /// The session stores the audio, crime and faction bridges read. The build
    /// runner holds the builder half, so the two share nothing mutable.
    var worldData: (any WorldDataProviding)?
    /// Cached picker paths — enumerating every archive entry is not free.
    var cachedAudioFileNames: [String]?
    /// Voice picker filter, playback tracking and last-error state.
    var voice = VoiceLabState()
    /// Selector state owned by the UI Lab SWF bridge
    /// (`GameViewController+SWFLab.swift`); nothing else writes it.
    var swfLab = SWFLabState()
    /// Vanilla gameplay HUD state.
    var hud = HUDRuntimeState()
    /// System menu selector + presentation state.
    var systemMenu = SystemMenuRuntimeState()
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
    lazy var dialogueMenu = DialogueMenuController(game: self)
    lazy var dialogueCamera = DialogueCameraController(game: self)
    /// Container and barter menu two-pane list, merchant nomination and presentation state.
    lazy var containerMenu = ContainerMenuController(game: self)
    /// World > Runtime State bridge caches (save store, plugin fingerprint, slot list).
    var runtimeState = RuntimeStateBridgeState()
    /// World items, equipment, vendors and trades. Its runtimes stay nil without game data.
    let inventory = InventoryCoordinator()
    lazy var inventoryWorld = InventoryWorldAdapter(game: self)
    /// Player behavior graph + rendered body state.
    var playerBodyBridge = PlayerBodyBridgeState()
    /// Actor values: the damage/restore/regeneration runtime, the HUD meter gate and the
    /// panel's last outcome line.
    var actorValues = ActorValueBridgeState()

    /// Active effects, spellcasting and item enchantments. Its runtimes stay nil without game
    /// data.
    let magic = MagicCoordinator()
    lazy var magicWorld = MagicWorldAdapter(game: self)

    /// Perks: the ownership runtime, the entry-point evaluator behind every wired combat and
    /// magic seam, and the authored `PRKR` baselines.
    var perks = PerkBridgeState()

    /// Memberships, relationship ranks and derived hostility. Its runtimes stay nil without
    /// game data.
    lazy var factions = FactionCoordinator(store: worldState)
    lazy var factionWorld = FactionWorldAdapter(game: self)
    /// Bounties, ownership, guard response and the Crime & Factions panel.
    let crime = CrimeCoordinator()
    lazy var crimeWorld = CrimeWorldAdapter(game: self)

    /// Skill advancement: the use-to-experience-to-level runtime every combat and magic seam
    /// reports into, and the last advance the readouts show.
    var skills = SkillBridgeState()

    /// Character leveling: the level runtime skill advancement banks into, the AVIF perk-tree
    /// index a perk-point spend is validated against, and the last outcome line.
    var progression = ProgressionBridgeState()

    /// Death and ragdoll: the runtime, the per-skeleton ragdoll definitions it spawns from, and
    /// the panel's last outcome line.
    var ragdoll = RagdollBridgeState()

    /// Melee, archery and the combat loop. Its runtimes stay nil without game data.
    let combat = CombatCoordinator()
    lazy var combatWorld = CombatWorldAdapter(game: self)
    /// Kinematic NPC gait clips and failed clip keys.
    var npcMovementBridge = NPCMovementBridgeState()
    /// Live resident-actor package selection.
    var packages = PackageBridgeState()
    /// The perception pass: view cones, line of sight, and per-pair detection levels.
    var perception = PerceptionBridgeState()
    /// The AI & Navigation panel's shared actor selection and its last outcome line.
    var aiNavigation = AINavigationBridgeState()

    override func loadView() {
        let gameView = GameMetalView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        gameView.input = cameraInput
        gameView.menuMode = menuMode
        gameView.onJournalKey = { [weak self] in self?.journalMenu.open() }
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

        // Async launch: no scene is built here. A provider (game data) starts
        // the renderer on an empty scene and streams cells in around the
        // camera; no provider (missing data / setup throw) falls back to the
        // synthetic DemoScene so the window is never blank forever.
        let session = cellSessionFactory?(device)
        let provider = session?.data

        do {
            let newRenderer = try Renderer(
                view: mtkView,
                scene: provider != nil ? RenderScene(instances: []) : nil,
                camera: nil,
                input: cameraInput,
                movementConfiguration: (provider as? MovementConfigurationProviding)?
                    .movementConfiguration ?? .synthetic
            )
            // Persisted World > Environment > Sun shadows choice; invalid stored
            // value falls back to .high inside ShadowQualitySettings.load().
            newRenderer.shadowQuality = ShadowQualitySettings.load()
            // Persisted World > Environment > Time of day; invalid stored value
            // falls back to 13:00 inside TimeOfDaySettings.load().
            newRenderer.timeOfDay = TimeOfDaySettings.load()
            // Exterior weather runtime; nil provider / no weather data
            // leaves the renderer on its procedural sky, exactly as before.
            newRenderer.weather = (provider as? WeatherProviding)?.weatherSystem
            newRenderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
            mtkView.delegate = newRenderer
            renderer = newRenderer
            startHUD(renderer: newRenderer)
            // Menu mode drives the renderer's world-sim pause and clears held
            // world input on entry so no key sticks while the menu owns input.
            menuMode.onModeChange = { [weak newRenderer, weak cameraInput] route, paused in
                newRenderer?.worldSimPaused = paused
                // Released on the route flip rather than on the pause, because
                // the dialogue menu captures input without stopping the world
                // and a key held into it would otherwise keep
                // driving the camera nobody is steering.
                if route == .menu {
                    cameraInput?.releaseAll()
                }
            }
            if let session {
                worldData = session.data
                wireStreaming(session: session, renderer: newRenderer)
            }
            // Registered after streaming so the HUD still refreshes after the
            // streamer's per-frame update, exactly as it did when streaming
            // owned the only `onFrame` assignment.
            wireHUDFrameUpdates(renderer: newRenderer)
        } catch {
            show(message: "Renderer setup failed: \(error)")
        }
    }

    /// Saves the live World camera + current streamed scene, excluding app
    /// chrome. Runs on main, same as draw(in:), so renderer state cannot race.
    func writeScreenshot(to url: URL) throws {
        guard let renderer, let view = view as? MTKView else {
            throw ScreenshotError.rendererNotReady
        }
        let width = Int(view.drawableSize.width.rounded())
        let height = Int(view.drawableSize.height.rounded())
        guard width > 0, height > 0 else {
            throw ScreenshotError.rendererNotReady
        }
        let texture = try renderer.renderOffscreen(width: width, height: height)
        try FrameScreenshot.write(texture: texture, to: url)
    }

    static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "CellStream"
    )

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
}

/// Renderer bridge for the World > Environment panel. Reads/writes the live
/// renderer's shadow state on the main thread (same context as draw(in:)) and
/// persists the quality choice. A nil renderer (Metal 4 unavailable) degrades to
/// the stored/default quality and empty stats so the panel never crashes.
extension GameViewController: ShadowControlProviding {
    /// Not persisted: an A/B flip is a transient dev comparison, unlike the
    /// quality tier. A shadowless world restored on next launch would read as a
    /// rendering bug.
    var sunShadowsEnabled: Bool {
        get { renderer?.sunShadowsEnabled ?? true }
        set { renderer?.sunShadowsEnabled = newValue }
    }

    var shadowQuality: ShadowQuality {
        get { renderer?.shadowQuality ?? ShadowQualitySettings.load() }
        set {
            renderer?.shadowQuality = newValue
            ShadowQualitySettings.store(newValue)
        }
    }

    var shadowDrawStats: ShadowDrawStats {
        renderer?.lastShadowDrawStats ?? ShadowDrawStats()
    }

    var shadowUpdateMS: Double {
        renderer?.lastShadowUpdateMS ?? 0
    }

    var shadowsActive: Bool {
        renderer?.shadowRenders ?? false
    }

    func refocusGameView() {
        view.window?.makeFirstResponder(view)
    }
}

extension GameViewController: TerrainLODControlProviding {
    var terrainLODConfigurationSnapshot: TerrainLODConfigurationSnapshot {
        terrainLODConfigurationStore.snapshot()
    }

    var terrainLODOverrideActive: Bool {
        TerrainLODSettings.hasOverride()
    }

    func applyTerrainLODConfiguration(_ configuration: TerrainLODConfiguration) -> Bool {
        guard configuration.isValid else { return false }
        TerrainLODSettings.store(configuration)
        terrainLODConfigurationStore.replace(with: TerrainLODConfigurationSnapshot(
            configuration: configuration,
            source: "OpenSky sidebar override"
        ))
        streamer?.invalidateDistantLOD()
        return true
    }

    func resetTerrainLODConfiguration() {
        TerrainLODSettings.clearOverride()
        let root = try? GameDataLocator.locate()
        terrainLODConfigurationStore.replace(with: TerrainLODSettings.load(root: root))
        streamer?.invalidateDistantLOD()
    }
}
