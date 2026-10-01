// Hosts the MTKView and wires it to the renderer. Without Metal 4 it shows a
// message instead of crashing.

import AppKit
import MetalKit
import OpenSkyActors
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
import OpenSkyPerception
import OpenSkyProgression
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

    /// Runs here, not in the AppDelegate, because the asset libraries bind GPU
    /// resources to the view's device. A nil result falls back to `DemoScene`.
    var cellSessionFactory: ((MTLDevice) -> CellSession?)?

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
    var canWriteScreenshot: Bool {
        renderer != nil
    }

    /// Only this file assigns it.
    var streamer: CellStreamer?
    /// `wireStreaming` rebuilds resident cells when it changes.
    let worldState = WorldStateStore()
    /// nil without game data. Ticked once per drawn frame.
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
        return systemMenu
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
    lazy var dialogueMenu = DialogueMenuController(game: self)
    lazy var dialogueCamera = DialogueCameraController(game: self)
    /// Container and barter menu two-pane list, merchant nomination and presentation state.
    lazy var containerMenu = ContainerMenuController(game: self)
    /// World > Runtime State bridge caches (save store, plugin fingerprint, slot list).
    var runtimeState = RuntimeStateBridgeState()
    /// World items, equipment, vendors and trades. Its runtimes stay nil without game data.
    let inventory = InventoryCoordinator()
    lazy var inventoryWorld = InventoryWorldAdapter(game: self)
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
    lazy var packages: PackageCoordinator = {
        let packages = PackageCoordinator()
        packages.attach(world: aiWorld)
        return packages
    }()

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

        // With game data the renderer starts empty and streams cells in;
        // without it the renderer shows `DemoScene`.
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
            newRenderer.shadowQuality = ShadowQualitySettings.load()
            newRenderer.timeOfDay = TimeOfDaySettings.load()
            // Without weather data the renderer keeps its procedural sky.
            newRenderer.weather = (provider as? WeatherProviding)?.weatherSystem
            newRenderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
            mtkView.delegate = newRenderer
            renderer = newRenderer
            hud.start()
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
            // After streaming, so the HUD reads the streamer's update of this frame.
            newRenderer.onFrame.add { [weak self] _ in
                self?.hud.updateFrame()
            }
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
extension GameViewController: AudioControlForwarding {}

extension GameViewController: HUDControlForwarding, SWFLabControlForwarding,
    UILabControlForwarding, SystemMenuControlForwarding {}

extension GameViewController: SystemMenuWorld {
    func quitApplication() {
        NSApplication.shared.terminate(nil)
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
        default:
            systemMenu.route(event)
        }
    }
}

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
