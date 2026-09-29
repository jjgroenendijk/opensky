// The engine's view of a renderer: a `Renderer` built through `init(view:)`
// carries a `GameSession` as its frame driver, and the simulation state the
// session owns reads and writes through the renderer here. So a caller keeps
// writing `renderer.walkController` or `renderer.gameClock`, while the
// rendering layer itself never sees a walk controller or a clock.

import MetalKit
import OpenSkyAudio
import OpenSkyRendering

extension Renderer {
    /// `scene` nil -> synthetic DemoScene; `camera` nil -> its demo camera;
    /// `input` nil -> static seeded pose (offscreen/tests). The app passes a
    /// built cell scene + `SceneCamera.framing(bounds:)` + a shared
    /// `CameraInputState` for free-fly (todo 2.8). `shaderLibrary` nil -> the
    /// bundled `default.metallib`, as in `init(rendering:)`.
    public convenience init(
        view: MTKView,
        scene: RenderScene? = nil,
        camera: SceneCamera? = nil,
        input: CameraInputState? = nil,
        timeOfDay: Float = Renderer.defaultTimeOfDay,
        movementConfiguration: PlayerMovementConfiguration = .synthetic,
        shaderLibrary: MTLLibrary? = nil
    ) throws {
        try self.init(
            rendering: view, scene: scene, camera: camera, shaderLibrary: shaderLibrary
        )
        frameDriver = GameSession(
            renderer: self,
            input: input,
            timeOfDay: timeOfDay,
            movementConfiguration: movementConfiguration
        )
    }

    /// The session that drives this renderer's frames.
    public var session: GameSession {
        guard let session = frameDriver as? GameSession else {
            preconditionFailure("A Renderer built through init(view:) carries a GameSession")
        }
        return session
    }

    public var input: CameraInputState? {
        session.input
    }

    /// Main-thread per-frame hook, invoked after the camera advances with the
    /// live free-fly position (`GameSession.prepareLiveFrame`).
    public var onFrame: CallbackFanOut<SIMD3<Float>> {
        session.onFrame
    }

    public var walkController: WalkController {
        get { session.walkController }
        _modify { yield &session.walkController }
    }

    public var terrainSampler: WalkController.GroundSampler? {
        get { session.terrainSampler }
        _modify { yield &session.terrainSampler }
    }

    public var locomotion: LocomotionBridge {
        get { session.locomotion }
        _modify { yield &session.locomotion }
    }

    public var thirdPersonCamera: ThirdPersonCamera {
        get { session.thirdPersonCamera }
        _modify { yield &session.thirdPersonCamera }
    }

    public var dialogueCameraState: RendererDialogueCameraState {
        get { session.dialogueCameraState }
        _modify { yield &session.dialogueCameraState }
    }

    public var playerBody: PlayerBody? {
        get { session.playerBody }
        _modify { yield &session.playerBody }
    }

    public var playerFirstPersonRig: PlayerFirstPersonRig? {
        get { session.playerFirstPersonRig }
        _modify { yield &session.playerFirstPersonRig }
    }

    public var firstPersonCamera: FirstPersonCamera {
        get { session.firstPersonCamera }
        _modify { yield &session.firstPersonCamera }
    }

    public var firstPersonArmsEnabled: Bool {
        get { session.firstPersonArmsEnabled }
        _modify { yield &session.firstPersonArmsEnabled }
    }

    public var gameTime: RendererGameTime {
        get { session.gameTime }
        _modify { yield &session.gameTime }
    }

    public var weather: WeatherSystem? {
        get { session.weather }
        _modify { yield &session.weather }
    }

    public var weatherEnabled: Bool {
        get { session.weatherEnabled }
        _modify { yield &session.weatherEnabled }
    }

    public var weatherClock: FrameSimClock {
        get { session.weatherClock }
        _modify { yield &session.weatherClock }
    }

    public var worldAudio: WorldAudioEngine? {
        get { session.worldAudio }
        _modify { yield &session.worldAudio }
    }

    public var musicDirector: WorldMusicDirector? {
        get { session.musicDirector }
        _modify { yield &session.musicDirector }
    }

    public var footstepDirector: WorldAudioFootstepDirector? {
        get { session.footstepDirector }
        _modify { yield &session.footstepDirector }
    }

    public var audioClock: FrameSimClock {
        get { session.audioClock }
        _modify { yield &session.audioClock }
    }

    public var onWorldUpdate: ((Float) -> Void)? {
        get { session.onWorldUpdate }
        _modify { yield &session.onWorldUpdate }
    }

    public var lastScriptUpdateMS: Double {
        get { session.lastScriptUpdateMS }
        _modify { yield &session.lastScriptUpdateMS }
    }

    public var worldSimClock: FrameSimClock {
        get { session.worldSimClock }
        _modify { yield &session.worldSimClock }
    }

    public var cameraClock: FrameSimClock {
        get { session.cameraClock }
        _modify { yield &session.cameraClock }
    }

    public var lastCameraDelta: Float {
        get { session.lastCameraDelta }
        _modify { yield &session.lastCameraDelta }
    }

    public var lastAudioUpdateMS: Double {
        get { session.lastAudioUpdateMS }
        _modify { yield &session.lastAudioUpdateMS }
    }
}
