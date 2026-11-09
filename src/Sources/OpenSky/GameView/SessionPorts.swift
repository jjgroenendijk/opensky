// Each adapter sees the session through its host protocol, and every host member is
// a port or a value (docs/decisions/ports-and-adapters.md).

import AppKit
import MetalKit
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySession
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import simd

final class SessionPorts {
    unowned let scope: GameSessionScope

    init(scope: GameSessionScope) {
        self.scope = scope
    }
}

extension SessionPorts {
    var actorGraphWorld: any ActorGraphWorldPort {
        scope.actorGraphWorld
    }

    var actorGraphs: any ActorGraphPort {
        scope.actorGraphs
    }

    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)? {
        scope
            .actorPlayback(for: key)
    }

    var actorValues: any ActorValuePort {
        scope.actorValues
    }

    var actorWorld: any ActorWorldPort {
        scope.actorWorld
    }

    var agentWorld: any AgentWorldPort {
        scope.agentWorld
    }

    var aiWorld: any AIWorldPort {
        scope.aiWorld
    }

    func animatedPose(for key: ReferenceKey) -> [String: float4x4]? {
        scope.animatedPose(for: key)
    }

    var audio: any AudioPort {
        scope.audio
    }

    var audioFileSystem: (any GameFileSource)? {
        scope.audioFileSystem
    }

    var beastForms: any BeastFormWorldPort {
        scope.beastForms
    }

    var benchmarkLoadPhases: (any LoadPhaseRecorderPort)? {
        scope.benchmarkLoadPhases
    }

    var benchmarkTour: any BenchmarkTourPort {
        scope.benchmarkTour
    }

    var benchmarkWorld: any BenchmarkWorldPort {
        scope.benchmarkWorld
    }

    var cameraInput: any CameraInputStatePort {
        scope.cameraInput
    }

    var cellRunner: (any SerialCellBuildRunnerPort)? {
        scope.cellRunner
    }

    var cinematicCamera: any CinematicCameraPort {
        scope.cinematicCamera
    }

    var cinematicWorld: any CinematicCameraWorldPort {
        scope.cinematicWorld
    }

    var combat: any CombatPort {
        scope.combat
    }

    var combatWorld: any CombatWorldPort {
        scope.combatWorld
    }

    var containerMenu: any ContainerMenuPort {
        scope.containerMenu
    }

    var controlMapLoader: (() throws -> ControlMapFile)? {
        scope.controlMapLoader
    }

    var controllerRumble: any ControllerRumblePort {
        scope.controllerRumble
    }

    var crime: any CrimePort {
        scope.crime
    }

    var crimeWorld: any CrimeWorldPort {
        scope.crimeWorld
    }

    var dataRoot: GameDataRoot? {
        scope.dataRoot
    }

    var dialogue: any DialoguePort {
        scope.dialogue
    }

    var dialogueCamera: any DialogueCameraPort {
        scope.dialogueCamera
    }

    var dialogueMenu: any DialogueMenuPort {
        scope.dialogueMenu
    }

    var dialogueWorld: any DialogueWorldPort {
        scope.dialogueWorld
    }

    var dragonFlight: any DragonFlightPort {
        scope.dragonFlight
    }

    var dragonFlightWorld: any DragonFlightWorldPort {
        scope.dragonFlightWorld
    }

    var effectGraphs: any EffectGraphPort {
        scope.effectGraphs
    }

    var effectModelPoser: any EffectModelPoserPort {
        scope.effectModelPoser
    }

    var effects: any EffectsPort {
        scope.effects
    }

    var effectsWorld: any EffectsWorldPort {
        scope.effectsWorld
    }

    var faceMorphs: any FaceMorphPort {
        scope.faceMorphs
    }

    var factionWorld: any FactionWorldPort {
        scope.factionWorld
    }

    var factions: any FactionPort {
        scope.factions
    }

    var followerCommandWorld: any FollowerCommandWorldPort {
        scope.followerCommandWorld
    }

    var followerCommands: any FollowerCommandPort {
        scope.followerCommands
    }

    var furniture: any FurniturePort {
        scope.furniture
    }

    var gameSession: (any GameSessionPort)? {
        scope.gameSession
    }

    func setPlayerBody(_ body: PlayerBody) throws {
        try scope.gameSession?.setPlayerBody(body)
    }

    func setPlayerFirstPersonRig(_ rig: PlayerFirstPersonRig) throws {
        try scope.gameSession?.setPlayerFirstPersonRig(rig)
    }

    var hazardWorld: any HazardWorldPort {
        scope.hazardWorld
    }

    var hazards: any HazardPort {
        scope.hazards
    }

    var headTracking: any HeadTrackingPort {
        scope.headTracking
    }

    var drawableSize: CGSize {
        (scope.hostView as? MTKView)?.drawableSize ?? .zero
    }

    var viewBounds: CGRect {
        scope.hostView.bounds
    }

    var hud: any HUDPort {
        scope.hud
    }

    var idleWorld: any IdleWorldPort {
        scope.idleWorld
    }

    var idles: any IdlePort {
        scope.idles
    }

    var inventory: any InventoryPort {
        scope.inventory
    }

    var inventoryMenu: any InventoryMenuPort {
        scope.inventoryMenu
    }

    var inventoryWorld: any InventoryWorldPort {
        scope.inventoryWorld
    }

    var journal: any JournalPort {
        scope.journal
    }

    var journalMenu: any JournalMenuPort {
        scope.journalMenu
    }

    var loadingScreens: any LoadingScreenPort {
        scope.loadingScreens
    }

    var loadingWorld: any LoadingScreenWorldPort {
        scope.loadingWorld
    }

    var localizedStringsLoader: (() -> LocalizedStrings)? {
        scope.localizedStringsLoader
    }

    var lockpickingMenu: any LockpickingMenuPort {
        scope.lockpickingMenu
    }

    var magic: any MagicPort {
        scope.magic
    }

    var magicWorld: any MagicWorldPort {
        scope.magicWorld
    }

    var mapMenu: any MapMenuPort {
        scope.mapMenu
    }

    var mapWorld: any MapWorldPort {
        scope.mapWorld
    }

    var menuMode: any MenuModePort {
        scope.menuMode
    }

    var menuRouter: any MenuRouterPort {
        scope.menuRouter
    }

    var menuScreens: any MenuScreensPort {
        scope.menuScreens
    }

    var menuScreensWorld: any MenuScreensWorldPort {
        scope.menuScreensWorld
    }

    var menuTextLoader: (() -> any LocalizedLabelsPort)? {
        scope.menuTextLoader
    }

    var menuWorld: any MenuWorldPort {
        scope.menuWorld
    }

    var messageWorld: any MessageWorldPort {
        scope.messageWorld
    }

    var messages: any MessageCoordinatorPort {
        scope.messages
    }

    var mountWorld: any MountWorldPort {
        scope.mountWorld
    }

    var mounts: any MountPort {
        scope.mounts
    }

    var movieWorld: any MovieWorldPort {
        scope.movieWorld
    }

    var movies: any MoviePlayerPort {
        scope.movies
    }

    var nodeControllers: any NodeControllerPort {
        scope.nodeControllers
    }

    var npcAnimation: any NPCAnimationPort {
        scope.npcAnimation
    }

    var objectAnimationWorld: any ObjectAnimationWorldPort {
        scope.objectAnimationWorld
    }

    var objectBehaviors: any ObjectBehaviorPort {
        scope.objectBehaviors
    }

    var packages: any PackagePort {
        scope.packages
    }

    var perception: any PerceptionPort {
        scope.perception
    }

    var perkActivation: any PerkActivationPort {
        scope.perkActivation
    }

    var perks: any PerkPort {
        scope.perks
    }

    var player: any PlayerPort {
        scope.player
    }

    var playerBeastForm: PlayerBeastForm {
        scope.playerBeastForm
    }

    var playerControlLocks: PlayerControlLocks {
        scope.playerControlLocks
    }

    var playerSettings: any PlayerSettingsPort {
        scope.playerSettings
    }

    var playerSettingsStore: PlayerSettingsStore {
        scope.playerSettingsStore
    }

    var progression: any ProgressionPort {
        scope.progression
    }

    var progressionWorld: any ProgressionWorldPort {
        scope.progressionWorld
    }

    var questNotices: any QuestNoticePort {
        scope.questNotices
    }

    func quitApplication() {
        scope.quitApplication()
    }

    func quitToMainMenu() {
        scope.quitToMainMenu()
    }

    var raceMenu: any RaceMenuPort {
        scope.raceMenu
    }

    var ragdoll: any RagdollPort {
        scope.ragdoll
    }

    var ragdollWorld: any RagdollWorldPort {
        scope.ragdollWorld
    }

    var renderControls: any WorldRenderControlsPort {
        scope.renderControls
    }

    var renderer: (any RendererPort)? {
        scope.renderer
    }

    func runCommand(_ action: GameInputAction) {
        scope.runCommand(action)
    }

    var runtimeState: any RuntimeStatePort {
        scope.runtimeState
    }

    var runtimeStateWorld: any RuntimeStateWorldPort {
        scope.runtimeStateWorld
    }

    var saveGames: any SaveGameWorldPort {
        scope.saveGames
    }

    var scenes: any ScenePort {
        scope.scenes
    }

    var scripts: any ScriptPort {
        scope.scripts
    }

    var sequenceDoors: any SequenceDoorPort {
        scope.sequenceDoors
    }

    var sessionStartTiming: SessionStartTiming {
        scope.sessionStartTiming
    }

    var animationClips: ActorClipLoader? {
        scope.animationClips
    }

    func showControlRefusal(_ refusal: PlayerControlRefusal) {
        scope.showControlRefusal(refusal)
    }

    var simulationClock: any SteppedWallClockPort {
        scope.simulationClock
    }

    var skillsMenu: any SkillsMenuPort {
        scope.skillsMenu
    }

    var soundMixTimings: SoundMixTimings {
        scope.soundMixTimings
    }

    var storyManager: any StoryManagerPort {
        scope.storyManager
    }

    var storyWorld: any StoryWorldPort {
        scope.storyWorld
    }

    var streamer: any CellStreamerPort {
        scope.streamer
    }

    var subtitles: any SubtitlePort {
        scope.subtitles
    }

    var swfMovies: any SWFMovieSourcePort {
        scope.swfMovies
    }

    var systemMenu: any SystemMenuPort {
        scope.systemMenu
    }

    var terrainLODConfigurationStore: TerrainLODConfigurationStore {
        scope.terrainLODConfigurationStore
    }

    var titleMenu: any TitleMenuPort {
        scope.titleMenu
    }

    var titleSequence: any TitleSequencePort {
        scope.titleSequence
    }

    var vehicleWorld: any VehicleWorldPort {
        scope.vehicleWorld
    }

    var vehicles: any VehiclePort {
        scope.vehicles
    }

    var worldData: WorldDataStores? {
        scope.worldData
    }

    var worldLoadReport: WorldLoadReport? {
        scope.worldLoadReport
    }

    var worldState: any WorldStateStorePort {
        scope.worldState
    }
}

extension SessionPorts {
    func takeStartedAudio(
        engine: WorldAudioEngine, sounds: WorldAudioSoundDirector,
        music: WorldMusicDirector, footsteps: WorldAudioFootstepDirector
    ) {
        guard let session = scope.gameSession else { return }
        session.worldAudio = engine
        session.soundDirector = sounds
        session.musicDirector = music
        session.footstepDirector = footsteps
    }
}

extension SessionPorts {
    var viewCamera: FreeFlyCamera? {
        scope.viewCamera
    }

    var uiScene: UIScene {
        get { scope.uiScene }
        set { scope.uiScene = newValue }
    }

    var audioEnabled: Bool {
        scope.audioEnabled
    }

    func handleMenuInput(_ event: MenuInputEvent) {
        scope.handleMenuInput(event)
    }

    func handleMenuPointer(_ event: MenuPointerEvent) {
        scope.handleMenuPointer(event)
    }
}
