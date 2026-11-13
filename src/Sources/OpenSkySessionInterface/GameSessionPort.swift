public import OpenSkyAudio
public import OpenSkyBehavior
public import OpenSkyGameData
import OpenSkyPhysics
public import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyWorldInterface
public import OpenSkyWorldState
public import simd

/// What the world adapters use of `GameSession`.
public protocol GameSessionPort: AnyObject {
    associatedtype Audio: SessionAudioPort
    var audio: Audio { get }
    associatedtype Sky: SessionSkyPort
    var sky: Sky { get }
    associatedtype Rigs: SessionRigsPort
    var rigs: Rigs { get }
    associatedtype Motion: SessionMotionPort
    var motion: Motion { get }
    func knockPlayer(_ velocity: SIMD3<Float>)
    associatedtype WalkController: WalkPort
    associatedtype CellResetCoordinator: CellResetPort
    associatedtype LocomotionBridge: LocomotionBridgePort
    associatedtype WeatherSystem: WeatherSystemPort
    func applyGraphicsSettings(_ store: PlayerSettingsStore)
    var cellReset: CellResetCoordinator? { get }
    func clearScriptScreenEffects()
    var currentTimescale: Float { get }
    /// The player view a dialogue camera override stands in for, if one is held.
    var dialogueRestorePose: FreeFlyCamera? { get }
    var frameSteps: FrameSchedule<FrameStep, SIMD3<Float>> { get }
    var freeFlyCamera: FreeFlyCamera { get set }
    var gameClock: GameClock { get set }
    var gameTime: RendererGameTime { get set }
    var imageSpace: ImageSpaceState { get set }
    var instancePoses: RenderInstancePoses { get set }
    var isCinematicCameraEngaged: Bool { get }
    var lastScriptUpdateMS: Double { get set }
    var lastSimulationMS: Double { get set }
    var locomotion: LocomotionBridge { get }
    var movementMode: CameraMovementMode { get set }
    func placePlayerFeet(at feet: SIMD3<Float>)
    var playerEyePosition: SIMD3<Float> { get }
    var renderer: Renderer { get }
    func reseedMovement(camera newCamera: SceneCamera)
    func seatPlayer(at root: float4x4, head: SIMD3<Float>?)
    var sessionFOVYRadians: Float { get }
    func setCinematicCamera(_ pose: CinematicCameraPose?, shakeOffset: SIMD3<Float>)
    func setDialogueCameraFocus(_ focus: DialogueCameraFocus?)
    func setFirstPersonFOVY(radians: Float)
    func setMovementMode(_ mode: CameraMovementMode)
    @discardableResult func settlePlayerOnGround() -> Bool
    var timeOfDay: Float { get set }
    var uiScene: UIScene { get set }
    func updateWeather(deltaTime: Float)
    var viewFOVYRadians: Float { get }
    var walkController: WalkController { get }
    var weather: WeatherSystem? { get }
    var worldTimeScale: Float { get set }

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

    public var playerAnimation: Rigs.PlayerBody.SkinnedPosePlayback? {
        rigs.playerBody?.animation
    }

    public var playerBody: Rigs.PlayerBody? {
        rigs.playerBody
    }

    public var soundDirector: Audio.WorldAudioSoundDirector? {
        get { audio.soundDirector }
        set { audio.soundDirector = newValue }
    }

    public var animationEvents: Audio.AnimationEventCoordinator? {
        audio.animationEvents
    }

    public var worldAudio: WorldAudioEngine? {
        get { audio.worldAudio }
        set { audio.worldAudio = newValue }
    }
}
