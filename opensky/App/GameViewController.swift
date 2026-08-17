// Hosts the MTKView and wires it to the renderer. Fails soft with an on-screen
// message when the GPU lacks Metal 4 — the engine requires it (AGENTS.md
// "Environment & tech stack"); a missing GPU feature must not crash the app.

import AppKit
import MetalKit
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

    /// Builds the off-main cell provider on the view's Metal device. Set by
    /// the AppDelegate before the window content loads; nil factory or nil
    /// result (missing game data / setup throw) -> no streamer, renderer
    /// falls back to the synthetic DemoScene. The factory runs here (not in
    /// the AppDelegate) because the asset libraries bind GPU resources to the
    /// device the view renders with.
    var cellProviderFactory: ((MTLDevice) -> (any CellSceneProvider)?)?

    /// Thread-safe effective INI/sidebar LOD values shared with the off-main
    /// DistantLODBuilder. AppDelegate replaces this before view load.
    var terrainLODConfigurationStore = TerrainLODConfigurationStore(
        snapshot: TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        )
    )

    /// Readable by the UI Lab bridge (GameViewControllerUILab.swift); only this
    /// file assigns it.
    private(set) var renderer: Renderer?
    var canWriteScreenshot: Bool {
        renderer != nil
    }

    /// Retains the streaming controller (and, through it, the build runner +
    /// provider) for the window's lifetime. Readable by the world-stats bridge
    /// (GameViewControllerWorldStats.swift); only this file assigns it.
    var streamer: CellStreamer?
    /// Mutable runtime world state for this session (issue #160). It is the
    /// production owner of `WorldStateStore`: `wireStreaming` reads snapshots
    /// off it at build dispatch and rebuilds resident cells when it changes.
    /// Papyrus, inventory and quests mutate it later; the sidebar readout
    /// (issue #162) reads it.
    let worldState = WorldStateStore()
    /// Papyrus VM for this session (issue #171), built by `wirePapyrus` when
    /// the provider can supply compiled scripts. Cell streaming attaches and
    /// detaches script instances on it, and the renderer's world-simulation
    /// hook ticks it once per drawn frame. nil without game data.
    var papyrus: PapyrusWorldRuntime?
    /// Seam Papyrus natives reach the world through (issue #172), built beside
    /// `papyrus`. Retained here because it is also the `onInteraction`
    /// subscriber that turns a use key into a recorded activation.
    var papyrusBridge: PapyrusWorldStateBridge?
    /// GLOB defaults of the loaded plugin, set by `wireStreaming` (issue
    /// #165). nil without game data; the time-of-day scrub then writes the
    /// renderer's clock directly instead of going through the global seam.
    var globalStore: GlobalStore?
    /// QUST index of the loaded plugin, set by `wirePapyrus` (issue #322). nil
    /// without game data, and then the `Quest` natives report themselves
    /// unavailable rather than inventing quest state.
    var questStore: QuestStore?
    /// Free-fly input shared with the renderer; the view writes it from
    /// NSEvents, the renderer drains it each frame (todo 2.8).
    let cameraInput = CameraInputState()

    /// Menu-mode source of truth (todo 8.1.2), shared with the input view and
    /// the renderer. Entering menu mode pauses world sim and drops held world
    /// input; leaving it resumes with no time jump. The Developer > UI Lab preview
    /// (M8.1.4, via GameViewControllerUILab.swift) is the only trigger until
    /// real SWF menus land (M8.2).
    let menuMode = MenuModeController()

    /// Which built-in overlay sample Developer > UI Lab shows (M8.1.4). Stored here
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

    /// Builds the plugin's string tables over the located install (issue
    /// #184). Set by the AppDelegate; nil when game data is missing, and the
    /// journal then falls back to editor IDs. Invoked once, lazily, by the
    /// journal bridge, because constructing it walks the VFS.
    var localizedStringsLoader: (() -> LocalizedStrings)?

    /// Builds the SWF movie loader over the located install (M8.2.5). Set by
    /// the AppDelegate; nil when game data is missing. The UI Lab SWF bridge
    /// invokes it once, lazily, into `swfLab`.
    var swfMovieLoaderFactory: (() -> SWFMovieLoader)?

    /// Resource lookup for World > Audio (M9.1.3). Set by the AppDelegate; nil
    /// when game data is missing — the panel then lists nothing to play.
    var audioFileSystem: VirtualFileSystem?
    /// World audio graph, created on first enable by the audio bridge
    /// (GameViewControllerAudio.swift), which also hands it to the renderer.
    var worldAudio: WorldAudioEngine?
    /// World SFX + ambience director (M9.2.2), built beside the engine on
    /// first enable. Subscribed to streamer callbacks; lives in
    /// `opensky/Audio/WorldAudioSoundDirector.swift`.
    var soundDirector: WorldAudioSoundDirector?
    /// Music director (M9.2.3), built beside the engine on first enable.
    /// Subscribed to the streamer's music-context callback and ticked by the
    /// renderer; lives in `opensky/Audio/WorldMusicDirector.swift`.
    var musicDirector: WorldMusicDirector?
    /// Footstep director (issue #352), built beside the engine on first
    /// enable. Fed by the renderer's audio tick from the locomotion bridge's
    /// fired graph events; lives in
    /// `opensky/Audio/WorldAudioFootstepDirector.swift`.
    var footstepDirector: WorldAudioFootstepDirector?
    /// Cell provider the audio bridge reads sound/aspc stores off when it
    /// constructs the SFX director (M9.2.2). Held weakly because the build
    /// runner (and through it the streamer) already retains the provider.
    var streamerCellProvider: (any CellSceneProvider)?
    /// Cached picker paths — enumerating every archive entry is not free.
    var cachedAudioFileNames: [String]?
    /// Voice picker filter, playback tracking and last-error state (item
    /// 17.5). The implementation lives in `GameViewControllerAudioVoice.swift`;
    /// stored here because extensions cannot add state.
    var voice = VoiceLabState()
    /// Selector state owned by the UI Lab SWF bridge
    /// (`GameViewControllerSWFLab.swift`); nothing else writes it.
    var swfLab = SWFLabState()
    /// Vanilla gameplay HUD state. The implementation lives in
    /// `GameViewControllerHUD.swift`; stored here because extensions cannot
    /// add state.
    var hud = HUDRuntimeState()
    /// System menu selector + presentation state. The implementation lives in
    /// `GameViewControllerSystemMenu.swift`; stored here because extensions
    /// cannot add state.
    var systemMenu = SystemMenuRuntimeState()
    /// Inventory menu row list + presentation state (issue #289). The
    /// implementation lives in `GameViewControllerInventoryMenu.swift`; stored
    /// here because extensions cannot add state.
    var inventoryMenu = InventoryMenuRuntimeState()
    /// Journal page model and presentation state (issue #184). The
    /// implementation lives in `GameViewControllerJournal.swift`; stored here
    /// because extensions cannot add state.
    var journal = JournalRuntimeState()
    /// Dialogue index, conversation model and presentation state (issue #205).
    /// The implementation lives in `GameViewControllerDialogue.swift` and
    /// `GameViewControllerDialogueMenu.swift`; stored here because extensions
    /// cannot add state.
    var dialogue = DialogueBridgeState()
    /// Conversation camera override and speaker focus (issue #427). The
    /// implementation lives in `GameViewControllerDialogueCamera.swift`; stored
    /// here because extensions cannot add state.
    var dialogueCamera = DialogueCameraBridgeState()
    /// Container and barter menu two-pane list, merchant nomination and
    /// presentation state (issue #179). The implementation lives in
    /// `GameViewControllerContainerMenu.swift`; stored here because extensions
    /// cannot add state.
    var containerMenu = ContainerMenuRuntimeState()
    /// World > Runtime State bridge caches (save store, plugin fingerprint,
    /// slot list). The implementation lives in
    /// `GameViewControllerRuntimeState.swift`; stored here because extensions
    /// cannot add state.
    var runtimeState = RuntimeStateBridgeState()
    /// World items: the take/drop/container runtime and the panel's last
    /// outcome line (issue #177). The implementation lives in
    /// `GameViewControllerItems.swift`; stored here because extensions cannot
    /// add state.
    var worldItems = WorldItemBridgeState()
    /// Player behavior graph + rendered body state (issue #189). The
    /// implementation lives in `GameViewControllerPlayerBody.swift`; stored
    /// here because extensions cannot add state.
    var playerBodyBridge = PlayerBodyBridgeState()
    /// Actor values: the damage/restore/regeneration runtime, the HUD meter
    /// gate and the panel's last outcome line (issue #194). The implementation
    /// lives in `GameViewControllerActorValues.swift`; stored here because
    /// extensions cannot add state.
    var actorValues = ActorValueBridgeState()

    /// Active magic effects: the apply/tick/dispel runtime, its fixed-step
    /// accumulator and the panel's last outcome line (issue #469). The
    /// implementation lives in `GameViewControllerMagic.swift`; stored here
    /// because extensions cannot add state.
    var magicEffects = MagicBridgeState()

    /// Spellcasting: the spellbook, the cast loop, the panel's spell selection
    /// and its last outcome line (issue #470). The implementation lives in
    /// `GameViewControllerCasting.swift`; stored here because extensions cannot
    /// add state.
    var casting = CastingBridgeState()

    /// Item enchantments: the ENCH index equipped items resolve through, and the
    /// last hit and worn-item outcomes the readouts show (issue #472). The
    /// implementation lives in `GameViewControllerEnchantments.swift`; stored
    /// here because extensions cannot add state.
    var enchantments = EnchantmentBridgeState()

    /// Melee combat: the swing runtime, the WEAP index it reads combat data
    /// out of, and the panel's last outcome line (issue #195). The
    /// implementation lives in `GameViewControllerMelee.swift`; stored here
    /// because extensions cannot add state.
    var melee = MeleeBridgeState()

    /// Archery: the shot and projectile runtimes, the AMMO/PROJ index they
    /// read flight data out of, and the panel's last outcome line (issue
    /// #196). The implementation lives in `GameViewControllerArchery.swift`;
    /// stored here because extensions cannot add state.
    var archery = ArcheryBridgeState()

    /// Death and ragdoll: the runtime, the per-skeleton ragdoll definitions it
    /// spawns from, and the panel's last outcome line (issue #197). The
    /// implementation lives in `GameViewControllerRagdoll.swift`; stored here
    /// because extensions cannot add state.
    var ragdoll = RagdollBridgeState()

    /// The combat loop: hostility, the derived combat state, the dev target's
    /// attack clock and the reaction clips it plays (issue #374). The
    /// implementation lives in `GameViewControllerCombat.swift`; stored here
    /// because extensions cannot add state.
    var combat = CombatBridgeState()
    /// Kinematic NPC gait clips and failed clip keys (issue #423).
    var npcMovementBridge = NPCMovementBridgeState()
    /// Live resident-actor package selection (issue #201).
    var packages = PackageBridgeState()
    /// The perception pass: view cones, line of sight, and per-pair detection
    /// levels (issue #202). The implementation lives in
    /// `GameViewControllerPerception.swift`; stored here because extensions
    /// cannot add state.
    var perception = PerceptionBridgeState()
    /// The M16 gate panel's shared actor selection and its last outcome line
    /// (issue #203). The implementation lives in
    /// `GameViewControllerAINavigation.swift`; stored here because extensions
    /// cannot add state.
    var aiNavigation = AINavigationBridgeState()

    override func loadView() {
        let gameView = GameMetalView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        gameView.input = cameraInput
        gameView.menuMode = menuMode
        gameView.onJournalKey = { [weak self] in self?.openJournal() }
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
        let provider = cellProviderFactory?(device)

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
            // Exterior weather runtime (M7.2.2); nil provider / no weather data
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
                // (issue #205) and a key held into it would otherwise keep
                // driving the camera nobody is steering.
                if route == .menu {
                    cameraInput?.releaseAll()
                }
            }
            if let provider {
                streamerCellProvider = provider
                startStreaming(provider: provider, renderer: newRenderer)
            }
            // Registered after streaming so the HUD still refreshes after the
            // streamer's per-frame update, exactly as it did when streaming
            // owned the only `onFrame` assignment.
            wireHUDFrameUpdates(renderer: newRenderer)
        } catch {
            show(message: "Renderer setup failed: \(error)")
        }
    }

    /// Wires a streamer over the provider: builds run off-main on a serial
    /// runner, the recomposed scene swaps in via `Renderer.setScene`, and the
    /// renderer's per-frame hook drives the streamer with the live camera
    /// position. Body lives in `GameViewControllerStreaming.swift` to keep this
    /// file under the strict-lint size cap.
    private func startStreaming(provider: any CellSceneProvider, renderer: Renderer) {
        wireStreaming(provider: provider, renderer: renderer)
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

// Weather bridge for the World > Environment panel (M7.2.2). Reads/forces the
// live renderer's weather runtime on the main thread. A nil renderer or no
// weather data degrades to an empty list + calm readout.
