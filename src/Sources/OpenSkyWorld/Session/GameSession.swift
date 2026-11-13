// The simulation half of a frame: player, camera policy, game clock, weather, audio and
// per-frame hooks. It owns the renderer and drives it through `RenderFrameDriver`: each
// frame it fills one `RenderFrameInput`, which is all the game state the renderer reads.
// The work lives in the `GameSession+*.swift` extensions.

public import MetalKit
import OpenSkyActorPresentation
import OpenSkyAudio
import OpenSkyCamera
import OpenSkyFormatsCore
public import OpenSkyGameData
import OpenSkyPhysics
public import OpenSkyPlayer
public import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyRenderResources
import OpenSkyTerrain
public import OpenSkyWeather
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

public final class GameSession: RenderFrameDriver {
    public let renderer: Renderer
    public let audio = SessionAudio()
    public let sky = SessionSky()
    public let rigs = SessionRigs()
    public let motion = SessionMotion()

    /// Live view pose, seeded from the renderer's framing camera, advanced each frame from `input`.
    public var freeFlyCamera: FreeFlyCamera
    /// Fly is the default dev mode. Toggle POV cycles fly -> first-person walk -> third person.
    public var movementMode = CameraMovementMode.fly
    /// Rings of full-detail cells the streamer keeps, from `uGridsToLoad`.
    public var loadedGridRadius = CellGridManager.defaultRadius
    /// Where physics, NPCs, vehicles, and scripts have moved references. Published
    /// once per frame by their ticks; empty without them.
    public var instancePoses = RenderInstancePoses()
    /// The post-process values and running modifiers the composite pass applies.
    public var imageSpace = ImageSpaceState()
    /// The HUD, menus, and dev overlays the UI pass draws. Default empty -> zero draws.
    public var uiScene = UIScene.empty
    /// Menu-mode pause gate. True freezes the per-frame time advance while the frame and
    /// UI still draw. Clocks keep their marks fresh while paused, so resume has no jump.
    public var worldSimPaused = false
    /// Slows animation, particles, and the world sim, not the camera. A kill cam sets it below 1.
    public var worldTimeScale: Float = 1
    /// A Slow Time effect's share of normal speed for the world, on top of `worldTimeScale`.
    public var magicTimeScale: Float = 1
    /// The player's own share while Slow Time runs; the camera and the player's steps take it.
    public var playerTimeScale: Float = 1
    /// The bow zoom's share of normal speed for the world and the player (Steady Hand).
    public var bowZoomTimeScale: Float = 1
    /// The bow zoom's share of the view's half-angle tangent; 1 is no zoom.
    public var bowZoomViewShare: Float = 1

    /// The view's vertical field of view, with the bow zoom applied.
    public var viewFOVYRadians: Float {
        MatrixMath.zoomedFieldOfView(rigSteps.sessionFOVYRadians, share: bowZoomViewShare)
    }

    /// What the world sim, animation, and particles run at.
    public var effectiveWorldTimeScale: Float {
        worldTimeScale * magicTimeScale * bowZoomTimeScale
    }

    public var walkController: WalkController
    /// Behavior-graph locomotion bridge (docs/engine/walk-mode.md).
    public var locomotion: LocomotionBridge
    /// Returns a cell the player left long ago to its plugin state; nil until wired.
    public var cellReset: CellResetCoordinator?

    /// Game clock, its pause-aware delta source and the TimeScale seam. `timeOfDay` is a
    /// projection of it (GameSession+GameClock.swift).
    public var gameTime: RendererGameTime
    /// Data-driven weather runtime; nil -> procedural sky + camera lighting.
    public var weather: WeatherSystem?
    /// Free-fly input, drained once per live frame; nil (offscreen/tests) ->
    /// the camera stays on its seeded pose.
    public let input: CameraInputState?
    /// Steps after the camera advances, with the live free-fly position. Cell
    /// streaming may call `setScene` here, still between frames. Empty in
    /// offscreen runs and tests.
    public let frameSteps = FrameSchedule<FrameStep, SIMD3<Float>>()
    /// World simulation steps, once per drawn frame after the game clock
    /// advances. The delta is seconds from `worldSimClock`, zero when paused.
    public let worldTick = FrameSchedule<WorldTickStep, Float>()
    /// Off-main loader drains, before `worldTick` each frame, paused or not.
    /// The one point where loaded assets enter the simulation.
    public let assetDrains = FrameSchedule<AssetDrain, Void>()
    /// CPU wall time of the world-simulation callback, which currently owns
    /// the per-frame Papyrus VM advance. Exactly zero when no step is registered.
    public var lastScriptUpdateMS = 0.0
    /// Wall-clock delta source for the world simulation tick (the Papyrus VM),
    /// paused in menu mode.
    public var worldSimClock = FrameSimClock()
    /// Counts only the time the world spends paused by a menu, for `WaitMenuMode`.
    public var menuTimeClock = FrameSimClock()
    /// Wall-clock delta source for camera movement, paused in menu mode.
    public var cameraClock = FrameSimClock()
    /// The clamped delta `advanceCamera` last ran with. Dynamic bodies step on it, so they
    /// cannot drift from the player capsule in menu mode or after a stall.
    public var lastCameraDelta: Float = 0
    /// CPU wall time of the last live frame's camera, frame steps, clock, world
    /// tick, and weather: everything before the renderer encodes.
    public var lastSimulationMS = 0.0

    /// Takes over `renderer`: the player starts at its view pose, and the session
    /// drives its frames from now on.
    public init(
        renderer: Renderer,
        input: CameraInputState? = nil,
        timeOfDay: Float = RenderFrameInput.defaultTimeOfDay,
        movementConfiguration: PlayerMovementConfiguration = .synthetic
    ) {
        self.renderer = renderer
        freeFlyCamera = renderer.frameInput.view
        (walkController, locomotion) = GameSession.MovementSteps.makeMovement(
            freeFlyCamera,
            movementConfiguration
        )
        gameTime = RendererGameTime(clock: GameClock(hour: timeOfDay))
        self.input = input
        renderer.frameDriver = self
    }

    /// `scene` nil -> synthetic DemoScene; `camera` nil -> its demo camera; `input` nil ->
    /// static pose (offscreen, tests); `shaderLibrary` nil -> bundled `default.metallib`.
    /// The app passes a cell scene, `SceneCamera.framing(bounds:)` and `CameraInputState`.
    public convenience init(
        view: MTKView,
        scene: RenderScene? = nil,
        camera: SceneCamera? = nil,
        input: CameraInputState? = nil,
        timeOfDay: Float = RenderFrameInput.defaultTimeOfDay,
        movementConfiguration: PlayerMovementConfiguration = .synthetic,
        shaderLibrary: any MTLLibrary? = nil,
        pipelineCache: PipelineCache? = nil,
        wallClock: any WallClock = MediaWallClock()
    ) throws {
        try self.init(
            renderer: Renderer(
                rendering: view,
                scene: scene,
                camera: camera,
                shaderLibrary: shaderLibrary,
                pipelineCache: pipelineCache,
                wallClock: wallClock
            ),
            input: input,
            timeOfDay: timeOfDay,
            movementConfiguration: movementConfiguration
        )
    }

    // MARK: - RenderFrameDriver

    public func prepareLiveFrame() -> RenderFrameInput {
        let started = Stopwatch()
        movementSteps.advanceCamera()
        // Streaming may setScene synchronously before this frame encodes.
        frameSteps(freeFlyCamera.position)
        clockSteps.advanceGameClockFromWallClock()
        clockSteps.updateWorldSimFromWallClock()
        weatherSteps.updateWeatherFromWallClock()
        lastSimulationMS = started.milliseconds
        return frameInput
    }

    public func finishLiveFrame() {
        audioSteps.updateAudioFromWallClock()
    }

    public func prepareOffscreenFrame(deltaTime: Float, advancesWorld: Bool) -> RenderFrameInput {
        let delta = worldSimPaused ? 0 : deltaTime
        if advancesWorld {
            clockSteps.updateWorldSim(deltaTime: delta)
        }
        // Offscreen the game clock never advances, so forced weather never rerolls.
        weatherSteps.updateWeather(deltaTime: advancesWorld ? delta : 0)
        return frameInput
    }

    public func finishOffscreenFrame(deltaTime: Float) {
        audioSteps.updateAudio(deltaTime: deltaTime)
    }

    public func didReplaceCamera(_ camera: SceneCamera) {
        movementSteps.reseedMovement(camera: camera)
    }

    /// Everything the renderer draws this frame, read after every system has run.
    public var frameInput: RenderFrameInput {
        var input = RenderFrameInput(view: freeFlyCamera)
        input.movementMode = movementMode
        input.fovYRadians = viewFOVYRadians
        input.horizontalFOVRadians = rigs.cinematicCameraState.pose?.horizontalFieldOfView
        input.timeOfDay = timeOfDay
        input.wind = wind
        input.weather = sky.currentResolvedWeather
        input.celestial = sky.celestialSky
        input.precipitationTuning = sky.precipitationTuning
        input.interiorFog = sky.interiorFogOverride
        input.imageSpace = imageSpace
        input.instancePoses = instancePoses
        input.rigs = RenderRigs(
            body: rigs.playerBody, arms: rigs.playerFirstPersonRig, visibility: rigVisibility
        )
        input.ui = uiScene
        input.isPaused = worldSimPaused
        input.timeScale = effectiveWorldTimeScale
        input.roofAbove = motion.collisionQuery.map { query in
            { PrecipitationRoofOcclusion.isOccluded(above: $0, query: query) }
        }
        return input
    }

    /// Fractional hour of day in [0, 24), projected from the game clock.
    /// Setting it scrubs the clock's hour and keeps the date — the same
    /// observable meaning every pre-clock call site relied on.
    public var timeOfDay: Float {
        get { gameTime.clock.hourOfDay }
        set { gameTime.clock.setHour(newValue) }
    }

    /// Published wind for precipitation, grass, particles and audio. Calm with no weather.
    public var wind: WindState {
        sky.weatherEnabled ? weather?.currentWind ?? .calm : .calm
    }

    /// What this frame draws and casts, from `PlayerRigVisibility`.
    var rigVisibility: PlayerRigVisibility {
        PlayerRigVisibility.resolve(
            mode: movementMode,
            hasBody: rigs.playerBody != nil,
            hasArms: rigs.playerFirstPersonRig != nil,
            armsEnabled: rigs.firstPersonArmsEnabled,
            dialogueCamera: dialogueCameraSteps.isDialogueCameraEngaged,
            framesPlayer: dialogueCameraSteps.isDialogueCameraFramingPlayer
        )
    }
}

extension PlayerBody: RenderRig {
    /// The player's contribution to the per-frame animation pass. Mirrors what
    /// `RenderScene.updateAnimations` does for cell-owned actors, including the
    /// Actor animation switch.
    public func publishAnimation(enabled: Bool) -> Int {
        enabled ? animation.update(at: 0) : animation.resetToBindPose()
    }
}

extension PlayerFirstPersonRig: RenderRig {
    /// The arms' contribution to the per-frame animation pass, mirroring
    /// `PlayerBody.publishAnimation`.
    public func publishAnimation(enabled: Bool) -> Int {
        enabled ? animation.update(at: 0) : animation.resetToBindPose()
    }
}

extension GameSession {
    public var weatherSteps: WeatherSteps {
        WeatherSteps(session: self)
    }

    var movementSteps: MovementSteps {
        MovementSteps(session: self)
    }

    var audioSteps: AudioSteps {
        AudioSteps(session: self)
    }

    public var dialogueCameraSteps: DialogueCameraSteps {
        DialogueCameraSteps(session: self)
    }

    var cinematicSteps: CinematicSteps {
        CinematicSteps(session: self)
    }

    public var rigSteps: RigSteps {
        RigSteps(session: self)
    }

    public var clockSteps: ClockSteps {
        ClockSteps(session: self)
    }

    /// The weather, sky, and image-space steps of a frame.
    public struct WeatherSteps {
        let session: GameSession
    }

    /// The camera and player movement of a frame, on foot, mounted, or walked by a package.
    struct MovementSteps {
        let session: GameSession
    }

    /// The listener, the sound mix, and the footstep routing of a frame.
    struct AudioSteps {
        let session: GameSession
    }

    /// The conversation camera override and its overlay.
    public struct DialogueCameraSteps {
        let session: GameSession
    }

    /// The kill-cam pose and its shake.
    struct CinematicSteps {
        let session: GameSession
    }

    /// The player's body and first-person arms, and their poses.
    public struct RigSteps {
        let session: GameSession
    }

    /// The game clock and the world simulation tick.
    public struct ClockSteps {
        let session: GameSession
    }
}
