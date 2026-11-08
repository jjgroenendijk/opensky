// The session scope: every object that belongs to one loaded game. It is built
// when the loaded world and the frame session both exist, and released with the
// game view. Each adapter sees it only through its own host protocol
// (docs/decisions/session-scope.md).

import AppKit
import MetalKit
import OpenSkyActorAdapters
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryAdapters
import OpenSkyLoading
import OpenSkyMagic
import OpenSkyMagicAdapters
import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyObjectAnimation
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionAdapters
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkySessionAdapters
import OpenSkySessionInterface
import OpenSkyStoryAdapters
import OpenSkyWorld
import OpenSkyWorldState

final class GameSessionScope {
    let services: GameAppServices
    /// The loaded stores. The build runner holds the builder half, so the two
    /// share nothing mutable. Nil only in a test that builds a scope without data.
    let worldData: WorldDataStores?
    /// The session's cell build queue; nil in a test without a loaded world.
    let cellRunner: SerialCellBuildRunner?
    /// The simulation and the renderer it drives; nil in a test without Metal.
    let gameSession: GameSession?
    /// The session's runtime world state. Every cell build reads a snapshot of it.
    let worldState = WorldStateStore()

    lazy var playerSettings = PlayerSettingsCoordinator(
        store: services.playerSettingsStore,
        world: menuWorld,
        keyNamesLoader: services.keyNamesLoader
    )

    init(
        worldData: WorldDataStores?,
        cellRunner: SerialCellBuildRunner?,
        gameSession: GameSession?,
        services: GameAppServices
    ) {
        self.worldData = worldData
        self.cellRunner = cellRunner
        self.gameSession = gameSession
        self.services = services
    }

    /// The benchmark tour through the live window (docs/tools/benchmark.md).
    lazy var benchmarkWorld = factories.makeBenchmarkWorld()
    lazy var benchmarkTour = BenchmarkTourCoordinator(world: benchmarkWorld)

    /// Holds the build runner and the provider for the window's lifetime.
    /// `WorldSessionWiring` assigns it.
    var streamer: CellStreamer?
    /// Reference mutations, save slots, game time, globals, and condition lists.
    lazy var runtimeState = RuntimeStateCoordinator(
        store: worldState,
        world: runtimeStateWorld,
        calendarTexts: worldData.map { data in
            CalendarTexts.resolve(store: data.gameSettings) { [unowned self] in mapWorld.text($0) }
        } ?? .vanilla
    )

    lazy var runtimeStateWorld = RuntimeStateWorldAdapter(game: ports)
    /// The Papyrus VM and its world bridge. Both stay nil without game data;
    /// session start replaces it with one built over the loaded world.
    lazy var scripts = ScriptCoordinator(world: scriptWorld)

    lazy var scriptWorld = factories.makeScriptWorld()

    /// The renderer and streamer controls of agent control.
    lazy var renderControls = WorldRenderControls(runtimeState: runtimeState, world: self)

    /// Every adapter's view of this scope.
    lazy var ports = SessionPorts(scope: self)
    var factories: GameSessionScopeFactories {
        GameSessionScopeFactories(scope: self)
    }

    lazy var sessionWiring = WorldSessionWiring(game: self)

    /// The audio engine, the world directors and the audio picker state.
    lazy var audio = AudioCoordinator(world: audioWorld)

    lazy var audioWorld = AudioWorldAdapter(game: ports)

    lazy var hud = HUDCoordinator(movies: swfMovies, world: ports)
    lazy var questNotices = QuestNoticeCoordinator(hud: hud) { [unowned self] in
        mapWorld.settingTexts(QuestNoticeText.self)
    }

    lazy var controllerRumble = ControllerRumble()

    lazy var systemMenu = factories.makeSystemMenu()

    /// Answers the Survival Mode plugin's prompt from the settings.
    lazy var survivalMode = SurvivalModeCoordinator(
        store: playerSettings.store, world: survivalModeWorld
    )
    lazy var survivalModeWorld = SurvivalModeWorldAdapter(runtimeState: runtimeState)

    lazy var saveGames = SaveGameWorldAdapter(game: ports)
    lazy var menuWorld = factories.makeMenuWorld()
    lazy var mapWorld = MapWorldAdapter(game: ports)
    /// Builds and routes the menu coordinators below.
    lazy var menuRouter = MenuRouter(game: ports)
    lazy var titleMenu = TitleMenuCoordinator(
        menuMode: menuMode, movies: swfMovies, hud: hud, saves: saveGames, world: menuWorld
    )
    lazy var raceMenu = factories.makeRaceMenu()
    lazy var skillsMenu = SkillsMenuCoordinator(
        menuMode: menuMode, movies: swfMovies, hud: hud, world: menuWorld
    )
    lazy var mapMenu = MapMenuCoordinator(menuMode: menuMode, world: mapWorld)
    /// Bink movies: the startup logo and `Game.PlayBink`.
    lazy var movies = MoviePlayerCoordinator(menuMode: menuMode, world: movieWorld)
    lazy var movieWorld = MovieWorldAdapter(game: ports)
    /// The opening titles of a new game, over the world.
    lazy var titleSequence = TitleSequenceCoordinator(movies: swfMovies) { [weak self] in
        self?.renderer
    }

    /// Inventory menu row list + presentation state.
    lazy var inventoryMenu = InventoryMenuController(game: ports)
    /// The quest the journal readout names and the quest changes it runs.
    lazy var journal = JournalCoordinator(world: journalMenu)

    lazy var journalMenu = JournalMenuController(game: ports)
    /// The dialogue index, the open conversation, and the speaker focus.
    lazy var dialogue = DialogueCoordinator(
        store: worldState,
        world: dialogueWorld,
        index: worldData?.dialogueStore,
        speechTimers: worldData.map { SpeechTimerSettings.resolve(store: $0.gameSettings) }
            ?? .vanilla
    )

    lazy var dialogueWorld = DialogueWorldAdapter(game: ports)
    /// Scenes, story-manager events, and their voice lines.
    lazy var storyWorld = StoryWorldAdapter(game: ports)
    /// The quest store's space, so a DLC scene names its quest as the runtime does.
    lazy var scenes = factories.makeScenes()
    lazy var storyManager = factories.makeStoryManager()
    lazy var dialogueMenu = DialogueMenuController(game: ports)
    lazy var dialogueCamera = DialogueCameraController(game: ports)
    /// Container and barter menu two-pane list, merchant nomination and presentation state.
    lazy var containerMenu = ContainerMenuController(game: ports)
    lazy var lockpickingMenu = LockpickingMenuController(game: ports)
    /// Notifications, help messages, and message boxes for scripts and agent control.
    lazy var messages = MessageCoordinator(
        menuMode: menuMode, movies: swfMovies, hud: hud, world: messageWorld
    )
    lazy var subtitles = SubtitleCoordinator(presenter: hud)

    lazy var messageWorld = MessageWorldAdapter(game: ports)
    /// Wait, training, books, help, magic, gifts, crafting, and text entry.
    lazy var menuScreens = MenuScreens(game: ports, screens: factories.makeMenuScreenCoordinators())
    lazy var menuScreensWorld = MenuScreensWorldAdapter(game: ports)
    /// Kill cams and camera shake.
    lazy var cinematicCamera = CinematicCameraCoordinator(
        world: cinematicWorld, settings: CinematicCameraWorldAdapter.killCamSettings(worldData)
    )
    lazy var cinematicWorld = CinematicCameraWorldAdapter(game: ports)
    lazy var loadingScreens = LoadingScreenCoordinator(world: loadingWorld)
    lazy var loadingWorld = LoadingScreenWorldAdapter(game: ports)
    /// World items, equipment, vendors and trades. Its runtimes stay nil without game data;
    /// session start replaces it with one built over the loaded world.
    lazy var inventory = InventoryCoordinator(
        world: inventoryWorld, lockWorld: lockWorld, data: nil
    )
    lazy var inventoryWorld = InventoryWorldAdapter(game: ports)
    lazy var lockWorld = LockWorldAdapter(game: ports)
    /// The player's Activate perk choices on a use-key press.
    lazy var perkActivation = PerkActivationCoordinator(
        messages: messages, world: perkActivationWorld
    )
    lazy var perkActivationWorld = PerkActivationWorldAdapter(game: ports)
    lazy var hazards: HazardCoordinator = .init(world: hazardWorld)
    lazy var hazardWorld = factories.makeHazardWorld()
    /// Session start replaces it with one built over the loaded effect records.
    lazy var effects = EffectsCoordinator()
    lazy var effectsWorld = EffectsWorldAdapter(game: ports)
    lazy var trapControl = factories.makeTrapControl()
    /// The player graphs, the body, and the locomotion and first-person readouts.
    lazy var player = PlayerCoordinator(
        input: cameraInput, world: playerWorld, source: playerWorld.rigSource()
    )

    lazy var playerWorld = factories.makePlayerWorld()

    /// The Face Morphs readout, over the actor in conversation.
    lazy var faceMorphs = FaceMorphCoordinator(
        world: playerWorld,
        settings: playerSettings.store,
        animation: worldData
            .map { FaceAnimationSettings.resolve(store: $0.gameSettings) } ?? .vanilla
    )

    lazy var headTracking = HeadTrackingCoordinator(
        world: playerWorld,
        settings: playerSettings.store,
        tracking: worldData.map { HeadTrackingSettings.resolve(store: $0.gameSettings) } ?? .vanilla
    )

    /// Actor values: damage, restore, regeneration, and the control controls.
    /// A provider without stat indexes, such as every synthetic scene, leaves the runtime nil.
    lazy var actorValues = ActorValueCoordinator(
        store: worldState,
        world: actorWorld,
        baselines: worldData?.actorValueBaselines,
        regeneration: worldData.map { RegenerationSettings.resolve(store: $0.gameSettings) }
            ?? .vanilla,
        stamina: worldData.map { StaminaSettings.resolve(store: $0.gameSettings) } ?? .vanilla
    )

    lazy var actorWorld = ActorWorldAdapter(game: ports)

    /// Active effects, spellcasting and item enchantments. Its runtimes stay nil without game
    /// data.
    lazy var magic = MagicCoordinator(world: magicWorld)
    lazy var magicWorld = MagicWorldAdapter(game: ports)

    /// Perk ownership and the entry points every combat and magic seam folds in.
    lazy var perks = PerkCoordinator(
        world: progressionWorld,
        runtime: progressionWorld.perkRuntime(store: worldState),
        baselines: worldData?.actorValueBaselines?.resolver
            .map(ActorPerkBaselineResolver.init(actorValues:)),
        pluginName: worldData?.magicItemPluginName
    )

    /// Memberships, relationship ranks and derived hostility. Its runtimes stay nil without
    /// game data.
    lazy var factions: FactionCoordinator = .init(
        store: worldState, world: factionWorld, data: FactionWorldAdapter.sessionData(worldData)
    )
    lazy var factionWorld = factories.makeFactionWorld()
    /// Bounties, ownership, guard response and the Crime & Factions readout.
    lazy var crime = CrimeCoordinator(
        world: crimeWorld,
        data: worldData.flatMap { crimeWorld.sessionData($0, store: worldState) },
        witnesses: crimeWorld.witnesses(),
        storyEvents: storyWorld
    )
    lazy var crimeWorld = CrimeWorldAdapter(game: ports)

    /// Skill advancement, character leveling, and the Progression readout.
    lazy var progression = ProgressionCoordinator(
        perks: perks,
        world: progressionWorld,
        data: progressionWorld.progressionData(),
        storyEvents: storyWorld
    )

    lazy var progressionWorld = ProgressionWorldAdapter(game: ports)

    /// Death and ragdoll. Its runtime stays nil without game data.
    lazy var ragdoll = RagdollCoordinator(
        store: worldState, world: ragdollWorld, data: ragdollWorld.sessionData()
    )

    lazy var ragdollWorld = RagdollWorldAdapter(game: ports)

    /// Melee, archery and the combat loop. Its runtimes stay nil without game data.
    lazy var combat = CombatCoordinator(
        world: combatWorld,
        data: combatWorld.sessionData(),
        explosions: effectsWorld.makeExplosions()
    )
    lazy var combatWorld = CombatWorldAdapter(game: ports)
    /// Live resident-actor package selection.
    lazy var packages = PackageCoordinator(world: aiWorld, data: aiWorld.packageData())
    /// The furniture seats the player and the packages share.
    lazy var furniture = FurnitureCoordinator(world: aiWorld)

    /// The perception pass: view cones, line of sight, and per-pair detection levels.
    lazy var perception = PerceptionCoordinator(
        world: aiWorld,
        settings: worldData?.detectionSettings,
        stealthPoints: worldData.map { StealthPointSettings.resolve(store: $0.gameSettings) }
            ?? .vanilla
    )

    /// The gait clip each NPC mover plays.
    lazy var npcAnimation = factories.makeNPCAnimation()

    lazy var aiWorld = AIWorldAdapter(game: ports)
    /// What `openskycli game` drives. The app's `AgentControlHost` owns the server.
    lazy var agentWorld = factories.makeAgentWorld()

    /// Ambient idles and the head switch, with the coordinators they drive.
    lazy var idleWorld = IdleWorldAdapter(game: ports)
    /// Ambient idles at idle markers, with their props.
    lazy var idles = factories.makeIdles()

    /// Carts, riders, and the actor AI natives.
    lazy var vehicleWorld = VehicleWorldAdapter(game: ports)
    lazy var vehicles = VehicleCoordinator(world: vehicleWorld)
    /// The player's horse or dragon.
    lazy var mountWorld = MountWorldAdapter(game: ports)
    lazy var mounts = MountCoordinator(
        world: mountWorld, settings: mountSettings, flightSettings: dragonFlightSettings
    )
    /// The werewolf and vampire lord forms.
    lazy var beastForms = BeastFormWorldAdapter(game: ports)
    lazy var activationRefusals = ActivationRefusalWorldAdapter(game: ports)
    /// Follower command mode: the follower uses the target the player picks.
    lazy var followerCommandWorld = FollowerCommandWorldAdapter(game: ports)
    lazy var followerCommands = FollowerCommandCoordinator(world: followerCommandWorld)

    /// Dragons nobody rides: take-off, flight, and landing.
    lazy var dragonFlightWorld = DragonFlightWorldAdapter(game: ports)
    lazy var dragonFlight = DragonFlightCoordinator(world: dragonFlightWorld)
    /// Traps, doors, and levers that a behaviour graph runs.
    lazy var objectAnimationWorld = factories.makeObjectAnimationWorld()

    lazy var objectBehaviors = ObjectBehaviorCoordinator(
        settings: playerSettings.store, world: objectAnimationWorld,
        files: { [unowned self] in audioFileSystem },
        viewer: { [unowned self] in billboardViewer }
    )
    lazy var sequenceDoors = factories.makeSequenceDoors()
    lazy var nodeControllers = factories.makeNodeControllers()

    /// The behaviour graphs of the effects on actors, which hear the actors' events.
    lazy var effectGraphWorld = EffectGraphWorldAdapter(game: ports)
    lazy var effectGraphs = EffectGraphCoordinator(
        world: effectGraphWorld, files: { [unowned self] in audioFileSystem }
    )
    /// Poses the effect models whose nodes move; the "Animated objects" setting turns it off.
    lazy var effectModelPoser = factories.makeEffectModelPoser()

    /// The behaviour graph each loaded NPC and creature runs.
    lazy var actorGraphWorld = ActorGraphWorldAdapter(game: ports)
    lazy var actorGraphs = factories.makeActorGraphs()
}
