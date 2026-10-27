// The simulation half of a frame: player, camera policy, game clock, weather, audio and
// per-frame hooks. It owns the renderer and drives it through `RenderFrameDriver`: each
// frame it fills one `RenderFrameInput`, which is all the game state the renderer reads.
// The work lives in the `GameSession+*.swift` extensions.

import MetalKit
import OpenSkyActorPresentation
import OpenSkyAudio
import OpenSkyCamera
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyWeather
import OpenSkyWorldState
import simd

public final class GameSession: RenderFrameDriver {
    public let renderer: Renderer

    /// Live view pose, seeded from the renderer's framing camera, advanced each frame from `input`.
    public var freeFlyCamera: FreeFlyCamera
    /// Fly is the default dev mode. `G` cycles fly -> first-person walk -> third person.
    public var movementMode = CameraMovementMode.fly
    /// Resident static collision broadphase, wired beside terrain by
    /// GameViewController. Empty in renderer-only paths. Walk mode, the
    /// cameras and precipitation all query it.
    public var collisionQuery: CapsuleWorldCollider.CandidateQuery?
    /// Where physics, NPCs, vehicles, and scripts have moved references. Published
    /// once per frame by their ticks; empty without them.
    public var instancePoses = RenderInstancePoses()
    /// A script's fog for the loaded interior; ignored once the scene's lighting changes.
    public var interiorFogOverride: InteriorFogOverride?
    /// This frame's resolved weather (exterior only). nil -> no weather active.
    public internal(set) var currentResolvedWeather: ResolvedWeather?
    /// The weather's rain or snow particles; nil until the weather links are wired.
    public internal(set) var precipitationTuning: PrecipitationTuning?
    /// The precipitation a script applied with `ShaderParticleGeometry.Apply`.
    public var scriptParticles = ScriptParticleGeometry()
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
        MatrixMath.zoomedFieldOfView(sessionFOVYRadians, share: bowZoomViewShare)
    }

    /// What the world sim, animation, and particles run at.
    public var effectiveWorldTimeScale: Float {
        worldTimeScale * magicTimeScale * bowZoomTimeScale
    }

    public var walkController: WalkController
    /// Current resident terrain lookup, wired by GameViewController. nil in
    /// renderer-only tests/offscreen paths -> walk mode has no ground.
    public var terrainSampler: WalkController.GroundSampler?
    /// Behavior-graph locomotion bridge (docs/engine/walk-mode.md).
    public var locomotion: LocomotionBridge
    /// The player's breath under water (docs/engine/walk-mode.md).
    public var breath = PlayerBreath()
    /// Returns a cell the player left long ago to its plugin state; nil until wired.
    public var cellReset: CellResetCoordinator?
    /// Orbit framing and collision zoom for `.thirdPerson`. Pure math; holds no pose.
    public var thirdPersonCamera = ThirdPersonCamera()
    /// The conversation camera's focus, framing and saved player pose. An override on top
    /// of `movementMode`, never a mode (GameSession+DialogueCamera.swift).
    public var dialogueCameraState = RendererDialogueCameraState()
    /// The kill-cam pose and camera shake, applied over the dialogue camera.
    public var cinematicCameraState = RendererCinematicCameraState()
    /// The player's rendered body, attached once the app has assembled it and
    /// deliberately not part of the scene: it survives every cell swap
    /// (GameSession+PlayerBody.swift). nil in offscreen/CLI paths and until the
    /// assembly succeeds. Set through `setPlayerBody`, which also sizes the
    /// rings and manages residency; assigning it directly would draw from
    /// buffers the GPU has not been told about.
    public var playerBody: PlayerBody?
    /// The vehicle pose the player rides at, where the body's root goes; nil on foot.
    public var playerSeat: float4x4? {
        didSet {
            if playerSeat == nil {
                seatedHead = nil
            }
        }
    }

    /// The seat idle's last `head` bone, in the seat's space. A seat idle that ended, or
    /// one still loading, keeps the eye there.
    var seatedHead: SIMD3<Float>?
    /// The player's mount; while one is under the player it moves instead of the
    /// player (docs/engine/riding.md).
    public weak var playerMount: (any PlayerMountDriving)?
    /// The furniture the player sits in; a move key asks it to stand the player up.
    public weak var playerFurniture: (any PlayerFurnitureDriving)?
    /// The waypoints a package walks the player along, empty without a walk
    /// (`PlayerPackageWalk`).
    public var playerWalkPath: [SIMD3<Float>] = []
    /// A straight package walk ignores static collision, as an NPC's straight leg does.
    public var playerWalkIgnoresStatics = false
    /// Called once when the player reaches the last waypoint of `playerWalkPath`.
    public var onPlayerWalkArrived: (() -> Void)?
    /// Paralysis: the player can look around but not move, jump, or attack.
    public var isPlayerParalysed = false
    /// The player's first-person arms, held like `playerBody`. Set through
    /// `setPlayerFirstPersonRig`.
    public var playerFirstPersonRig: PlayerFirstPersonRig?
    /// First-person field of view and the arms' depth policy. Holds no pose.
    public var firstPersonCamera = FirstPersonCamera()
    /// Toggle for the arms, so a capture can tell an arm fault from a world fault.
    public var firstPersonArmsEnabled = true
    /// Game clock, its pause-aware delta source and the TimeScale seam. `timeOfDay` is a
    /// projection of it (GameSession+GameClock.swift).
    public var gameTime: RendererGameTime
    /// Data-driven weather runtime; nil -> procedural sky + camera lighting.
    public var weather: WeatherSystem?
    /// Data-driven sky/fog/light/wind + precipitation-input A/B.
    public var weatherEnabled = true
    /// Wall-clock delta source for the weather runtime, paused in menu mode.
    public var weatherClock = FrameSimClock()
    /// Where the baseline image space comes from; nil leaves the frame ungraded.
    public var imageSpaceLinks: ImageSpaceLinks?
    /// World audio playback graph; nil until the app wires one (offscreen and
    /// CLI paths stay silent). Ticked by GameSession+Audio.swift.
    public var worldAudio: WorldAudioEngine?
    /// Region sound director, ticked from the pause-aware audio hook. Nil until audio is on.
    public var soundDirector: WorldAudioSoundDirector?
    /// Music director, ticked from the pause-aware audio hook. Nil until audio is on.
    public var musicDirector: WorldMusicDirector?
    /// Footstep director, fed from the pause-aware audio hook with the bridge's graph
    /// events. A paused frame fires nothing. Nil until audio is on.
    public var footstepDirector: WorldAudioFootstepDirector?
    /// Sounds, camera shake, and head tracking that clip annotations ask for. Nil until
    /// the app wires one.
    public var animationEvents: AnimationEventCoordinator?
    /// Wall-clock delta source for the audio tick, paused in menu mode.
    public var audioClock = FrameSimClock()
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
    /// CPU wall time of the last per-frame audio update (listener pose + engine
    /// tick + music director). Exactly zero on a frame that did no audio work,
    /// which is every frame while no `WorldAudioEngine` is attached.
    public var lastAudioUpdateMS = 0.0
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
        (walkController, locomotion) = Self.makeMovement(freeFlyCamera, movementConfiguration)
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
        shaderLibrary: MTLLibrary? = nil,
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
        let started = DispatchTime.now().uptimeNanoseconds
        advanceCamera()
        // Streaming may setScene synchronously before this frame encodes.
        frameSteps(freeFlyCamera.position)
        advanceGameClockFromWallClock()
        updateWorldSimFromWallClock()
        updateWeatherFromWallClock()
        lastSimulationMS = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
        return frameInput
    }

    public func finishLiveFrame() {
        updateAudioFromWallClock()
    }

    public func prepareOffscreenFrame(deltaTime: Float, advancesWorld: Bool) -> RenderFrameInput {
        let delta = worldSimPaused ? 0 : deltaTime
        if advancesWorld {
            updateWorldSim(deltaTime: delta)
        }
        // Offscreen the game clock never advances, so forced weather never rerolls.
        updateWeather(deltaTime: advancesWorld ? delta : 0)
        return frameInput
    }

    public func finishOffscreenFrame(deltaTime: Float) {
        updateAudio(deltaTime: deltaTime)
    }

    public func didReplaceCamera(_ camera: SceneCamera) {
        reseedMovement(camera: camera)
    }

    /// Everything the renderer draws this frame, read after every system has run.
    public var frameInput: RenderFrameInput {
        var input = RenderFrameInput(view: freeFlyCamera)
        input.movementMode = movementMode
        input.fovYRadians = viewFOVYRadians
        input.horizontalFOVRadians = cinematicCameraState.pose?.horizontalFieldOfView
        input.timeOfDay = timeOfDay
        input.wind = wind
        input.weather = currentResolvedWeather
        input.precipitationTuning = precipitationTuning
        input.interiorFog = interiorFogOverride
        input.imageSpace = imageSpace
        input.instancePoses = instancePoses
        input.rigs = RenderRigs(
            body: playerBody, arms: playerFirstPersonRig, visibility: rigVisibility
        )
        input.ui = uiScene
        input.isPaused = worldSimPaused
        input.timeScale = effectiveWorldTimeScale
        input.collisionQuery = collisionQuery
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
        weatherEnabled ? weather?.currentWind ?? .calm : .calm
    }

    /// What this frame draws and casts, from `PlayerRigVisibility`.
    public var rigVisibility: PlayerRigVisibility {
        PlayerRigVisibility.resolve(
            mode: movementMode,
            hasBody: playerBody != nil,
            hasArms: playerFirstPersonRig != nil,
            armsEnabled: firstPersonArmsEnabled,
            dialogueCamera: isDialogueCameraEngaged,
            framesPlayer: isDialogueCameraFramingPlayer
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
