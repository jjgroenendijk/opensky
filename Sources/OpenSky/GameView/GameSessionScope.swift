// The session scope: every object that belongs to one loaded game. It is built
// when the loaded world and the frame session both exist, and released with the
// game view. Each adapter sees it only through its own host protocol
// (docs/decisions/session-scope.md).

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

    var renderer: Renderer? {
        gameSession?.renderer
    }

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
    lazy var benchmarkWorld = BenchmarkWorldAdapter(game: self)

    /// Holds the build runner and the provider for the window's lifetime.
    /// `WorldSessionWiring` assigns it.
    var streamer: CellStreamer?
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

    /// The audio engine, the world directors and the audio picker state.
    lazy var audio = AudioCoordinator(world: audioWorld)

    lazy var audioWorld = AudioWorldAdapter(game: self)

    lazy var hud = HUDCoordinator(movies: swfMovies, world: self)

    lazy var systemMenu = menuRouter.makeSystemMenu()

    /// Answers the Survival Mode plugin's prompt from the settings.
    lazy var survivalMode = SurvivalModeCoordinator(
        store: playerSettings.store, world: survivalModeWorld
    )
    lazy var survivalModeWorld = SurvivalModeWorldAdapter(runtimeState: runtimeState)

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
    lazy var player = playerWorld.makePlayer()

    lazy var playerWorld = PlayerWorldAdapter(game: self)
    /// The Face Morphs readout, over the actor in conversation.
    lazy var faceMorphs = FaceMorphCoordinator(world: playerWorld, settings: playerSettings.store)

    lazy var headTracking =
        HeadTrackingCoordinator(world: playerWorld, settings: playerSettings.store)

    /// Actor values: damage, restore, regeneration, and the control controls.
    lazy var actorValues = actorWorld.makeActorValues()

    lazy var actorWorld = ActorWorldAdapter(game: self)

    /// Active effects, spellcasting and item enchantments. Its runtimes stay nil without game
    /// data.
    lazy var magic = MagicCoordinator(world: magicWorld)
    lazy var magicWorld = MagicWorldAdapter(game: self)

    /// Perk ownership and the entry points every combat and magic seam folds in.
    lazy var perks = progressionWorld.makePerks()

    /// Memberships, relationship ranks and derived hostility. Its runtimes stay nil without
    /// game data.
    lazy var factions: FactionCoordinator = .init(
        store: worldState, world: factionWorld, data: FactionWorldAdapter.sessionData(worldData)
    )
    lazy var factionWorld: FactionWorldAdapter = .init(FactionWorldDependencies(
        factions: { [unowned self] in factions },
        actors: actorWorld,
        streamer: { [unowned self] in streamer }
    ))
    /// Bounties, ownership, guard response and the Crime & Factions readout.
    lazy var crime = crimeWorld.makeCrime()
    lazy var crimeWorld = CrimeWorldAdapter(game: self)

    /// Skill advancement, character leveling, and the Progression readout.
    lazy var progression = progressionWorld.makeProgression()

    lazy var progressionWorld = ProgressionWorldAdapter(game: self)

    /// Death and ragdoll. Its runtime stays nil without game data.
    lazy var ragdoll = ragdollWorld.makeRagdoll()

    lazy var ragdollWorld = RagdollWorldAdapter(game: self)

    /// Melee, archery and the combat loop. Its runtimes stay nil without game data.
    lazy var combat = combatWorld.makeCombat()
    lazy var combatWorld = CombatWorldAdapter(game: self)
    /// Live resident-actor package selection.
    lazy var packages = aiWorld.makePackages()
    /// The furniture seats the player and the packages share.
    lazy var furniture = FurnitureCoordinator(world: aiWorld)

    /// The perception pass: view cones, line of sight, and per-pair detection levels.
    lazy var perception = aiWorld.makePerception()

    /// The gait clip each NPC mover plays.
    lazy var npcAnimation = NPCAnimationCoordinator(world: aiWorld)

    lazy var aiWorld = AIWorldAdapter(game: self)
    /// What `openskycli game` drives. The app's `AgentControlHost` owns the server.
    lazy var agentWorld = AgentWorldAdapter(game: self)

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
}
