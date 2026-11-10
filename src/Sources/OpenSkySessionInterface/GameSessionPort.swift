public import OpenSkyAudio
public import OpenSkyBehavior
public import OpenSkyGameData
public import OpenSkyPhysics
public import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyWorldInterface
public import OpenSkyWorldState
public import simd

/// What the world adapters use of `GameSession`.
public protocol GameSessionPort: AnyObject {
    func knockPlayer(_ velocity: SIMD3<Float>)
    associatedtype WalkController: WalkPort
    associatedtype AnimationEventCoordinator: AnimationEventPort
    associatedtype CellResetCoordinator: CellResetPort
    associatedtype LocomotionBridge: LocomotionBridgePort
    associatedtype PlayerBody: PlayerBodyPort
    associatedtype PlayerFirstPersonRig: PlayerFirstPersonRigPort
    associatedtype WeatherSystem: WeatherSystemPort
    associatedtype WorldAudioFootstepDirector: WorldAudioFootstepDirectorPort
    associatedtype WorldAudioSoundDirector: WorldAudioSoundDirectorPort
    var animationEvents: AnimationEventCoordinator? { get }
    func applyGraphicsSettings(_ store: PlayerSettingsStore)
    var celestialSky: CelestialSky? { get }
    var cellReset: CellResetCoordinator? { get }
    var cinematicCameraState: RendererCinematicCameraState { get set }
    func clearScriptScreenEffects()
    var collisionQuery: CapsuleWorldCollider.CandidateQuery? { get }
    var currentResolvedWeather: ResolvedWeather? { get }
    var currentTimescale: Float { get }
    /// The player view a dialogue camera override stands in for, if one is held.
    var dialogueRestorePose: FreeFlyCamera? { get }
    var firstPersonArmsEnabled: Bool { get set }
    var firstPersonCamera: FirstPersonCamera { get set }
    var footstepDirector: WorldAudioFootstepDirector? { get set }
    var frameSteps: FrameSchedule<FrameStep, SIMD3<Float>> { get }
    var freeFlyCamera: FreeFlyCamera { get set }
    var gameClock: GameClock { get set }
    var gameTime: RendererGameTime { get set }
    var imageSpace: ImageSpaceState { get set }
    var instancePoses: RenderInstancePoses { get set }
    var interiorFogOverride: InteriorFogOverride? { get set }
    var isCinematicCameraEngaged: Bool { get }
    var lastAudioUpdateMS: Double { get set }
    var lastScriptUpdateMS: Double { get set }
    var lastSimulationMS: Double { get set }
    var locomotion: LocomotionBridge { get }
    var movementMode: CameraMovementMode { get set }
    func placePlayerFeet(at feet: SIMD3<Float>)
    var playerBody: PlayerBody? { get }
    var playerEyePosition: SIMD3<Float> { get }
    var playerFirstPersonRig: PlayerFirstPersonRig? { get }
    var playerSeat: float4x4? { get set }
    var playerWalkIgnoresStatics: Bool { get set }
    var playerWalkPath: [SIMD3<Float>] { get set }
    var renderer: Renderer { get }
    func reseedMovement(camera newCamera: SceneCamera)
    var scriptParticles: ScriptParticleGeometry { get set }
    func seatPlayer(at root: float4x4, head: SIMD3<Float>?)
    var sessionFOVYRadians: Float { get }
    func setCinematicCamera(_ pose: CinematicCameraPose?, shakeOffset: SIMD3<Float>)
    func setDialogueCameraFocus(_ focus: DialogueCameraFocus?)
    func setFirstPersonFOVY(radians: Float)
    func setMovementMode(_ mode: CameraMovementMode)
    @discardableResult func settlePlayerOnGround() -> Bool
    var soundDirector: WorldAudioSoundDirector? { get set }
    var soundMixInputs: (() -> SoundMixInputs)? { get set }
    var soundRumble: ((SoundRumble) -> Void)? { get set }
    var terrainSampler: ((SIMD2<Float>) -> TerrainGroundSample?)? { get }
    var timeOfDay: Float { get set }
    var uiScene: UIScene { get set }
    func updateWeather(deltaTime: Float)
    var viewFOVYRadians: Float { get }
    var walkController: WalkController { get }
    var weather: WeatherSystem? { get }
    var worldAudio: WorldAudioEngine? { get set }
    var worldTimeScale: Float { get set }
    var imageSpaceLinks: ImageSpaceLinks? { get }

    var bowZoomTimeScale: Float { get }
    var bowZoomViewShare: Float { get }
    var worldSimPaused: Bool { get set }
}

/// The default arguments a protocol requirement cannot carry.
extension GameSessionPort {
    public func setCinematicCamera(_ pose: CinematicCameraPose?) {
        setCinematicCamera(pose, shakeOffset: .zero)
    }
}

extension GameSessionPort {
    public var playerGraph: BehaviorGraphInstance? {
        locomotion.graph
    }

    public var playerAnimation: PlayerBody.SkinnedPosePlayback? {
        playerBody?.animation
    }
}
