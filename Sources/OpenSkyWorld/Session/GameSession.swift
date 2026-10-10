// The simulation half of a frame: player, camera policy, game clock, weather, audio and
// per-frame hooks. It drives the renderer through `RenderFrameDriver` and holds it
// unowned, because the renderer owns it. The work lives in the `Renderer+*.swift`
// extensions, through `Renderer+Session.swift`.

import OpenSkyAudio
import OpenSkyRendering
import OpenSkyWorldState
import simd

public final class GameSession: RenderFrameDriver {
    public unowned let renderer: Renderer

    public var walkController: WalkController
    /// Current resident terrain lookup, wired by GameViewController. nil in
    /// renderer-only tests/offscreen paths -> walk mode has no ground.
    public var terrainSampler: WalkController.GroundSampler?
    /// Behavior-graph locomotion bridge (docs/engine/walk-mode.md).
    public var locomotion: LocomotionBridge
    /// Orbit framing and collision zoom for `.thirdPerson`. Pure math; holds no pose.
    public var thirdPersonCamera = ThirdPersonCamera()
    /// The conversation camera's focus, framing and saved player pose. An override on top
    /// of `movementMode`, never a mode (Renderer+DialogueCamera.swift).
    public var dialogueCameraState = RendererDialogueCameraState()
    /// The kill-cam pose and camera shake, applied over the dialogue camera.
    public var cinematicCameraState = RendererCinematicCameraState()
    /// The player's rendered body, attached once the app has assembled it and
    /// deliberately not part of the scene: it survives every cell swap
    /// (Renderer+PlayerBody.swift). nil in offscreen/CLI paths and until the
    /// assembly succeeds. Set through `setPlayerBody`, which also sizes the
    /// rings and manages residency; assigning it directly would draw from
    /// buffers the GPU has not been told about.
    public var playerBody: PlayerBody?
    /// The player's first-person arms, held like `playerBody`. Set through
    /// `setPlayerFirstPersonRig`.
    public var playerFirstPersonRig: PlayerFirstPersonRig?
    /// First-person field of view and the arms' depth policy. Holds no pose.
    public var firstPersonCamera = FirstPersonCamera()
    /// Toggle for the arms, so a capture can tell an arm fault from a world fault.
    public var firstPersonArmsEnabled = true
    /// Game clock, its pause-aware delta source and the TimeScale seam. `timeOfDay` is a
    /// projection of it (Renderer+GameClock.swift).
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
    /// CLI paths stay silent). Ticked by Renderer+Audio.swift.
    public var worldAudio: WorldAudioEngine?
    /// Region sound director, ticked from the pause-aware audio hook. Nil until audio is on.
    public var soundDirector: WorldAudioSoundDirector?
    /// Music director, ticked from the pause-aware audio hook. Nil until audio is on.
    public var musicDirector: WorldMusicDirector?
    /// Footstep director, fed from the pause-aware audio hook with the bridge's graph
    /// events. A paused frame fires nothing. Nil until audio is on.
    public var footstepDirector: WorldAudioFootstepDirector?
    /// Wall-clock delta source for the audio tick, paused in menu mode.
    public var audioClock = FrameSimClock()
    /// Free-fly input, drained once per live frame; nil (offscreen/tests) ->
    /// the camera stays on its seeded pose.
    public let input: CameraInputState?
    /// Main-thread per-frame hook, invoked after the camera advances with the
    /// live free-fly position. Cell streaming drives its per-frame `update`
    /// here (and may call `setScene` back synchronously -- safe, same thread,
    /// still between frames), and the HUD refreshes beside it. No handlers
    /// (offscreen/tests) leaves the loop unchanged.
    public let onFrame = CallbackFanOut<SIMD3<Float>>()
    /// World simulation tick, invoked once per drawn frame after the game clock
    /// advances. The delta is seconds, already gated by `worldSimClock`, so a
    /// paused frame delivers zero.
    public var onWorldUpdate: ((Float) -> Void)?
    /// Drains of the off-main asset loaders, run before `onWorldUpdate` each frame,
    /// paused or not. The one point where loaded assets enter the simulation.
    public let assetDrains = CallbackFanOut<Void>()
    /// CPU wall time of the world-simulation callback, which currently owns
    /// the per-frame Papyrus VM advance. Exactly zero when no callback is set.
    public var lastScriptUpdateMS = 0.0
    /// Wall-clock delta source for the world simulation tick (the Papyrus VM),
    /// paused in menu mode.
    public var worldSimClock = FrameSimClock()
    /// Wall-clock delta source for camera movement, paused in menu mode.
    public var cameraClock = FrameSimClock()
    /// The clamped delta `advanceCamera` last ran with. Dynamic bodies step on it, so they
    /// cannot drift from the player capsule in menu mode or after a stall.
    public var lastCameraDelta: Float = 0
    /// CPU wall time of the last per-frame audio update (listener pose + engine
    /// tick + music director). Exactly zero on a frame that did no audio work,
    /// which is every frame while no `WorldAudioEngine` is attached.
    public var lastAudioUpdateMS = 0.0

    /// Seeds the walk controller from the renderer's camera pose.
    public init(
        renderer: Renderer,
        input: CameraInputState?,
        timeOfDay: Float,
        movementConfiguration: PlayerMovementConfiguration
    ) {
        self.renderer = renderer
        (walkController, locomotion) = Renderer.makeMovement(
            renderer.freeFlyCamera,
            movementConfiguration
        )
        gameTime = RendererGameTime(clock: GameClock(hour: timeOfDay))
        self.input = input
    }

    // MARK: - RenderFrameDriver

    public func prepareLiveFrame() {
        renderer.advanceCamera()
        // Streaming may setScene synchronously before this frame encodes.
        onFrame(renderer.freeFlyCamera.position)
        renderer.advanceGameClockFromWallClock()
        renderer.updateWorldSimFromWallClock()
        renderer.updateWeatherFromWallClock()
    }

    public func finishLiveFrame() {
        renderer.updateAudioFromWallClock()
    }

    public func updateWorldSim(deltaTime: Float) {
        renderer.updateWorldSim(deltaTime: deltaTime)
    }

    public func updateWeather(deltaTime: Float) {
        renderer.updateWeather(deltaTime: deltaTime)
    }

    public func updateAudio(deltaTime: Float) {
        renderer.updateAudio(deltaTime: deltaTime)
    }

    public func didReplaceCamera(_ camera: SceneCamera) {
        renderer.reseedMovement(camera: camera)
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

    public var projectionFOVYRadians: Float {
        renderer.sessionFOVYRadians
    }

    /// What this frame draws and casts, from `PlayerRigVisibility`.
    public var rigVisibility: PlayerRigVisibility {
        PlayerRigVisibility.resolve(
            mode: renderer.movementMode,
            hasBody: playerBody != nil,
            hasArms: playerFirstPersonRig != nil,
            armsEnabled: firstPersonArmsEnabled,
            dialogueCamera: renderer.isDialogueCameraEngaged
        )
    }

    public var playerBodyRig: (any RenderRig)? {
        playerBody
    }

    public var firstPersonRig: (any RenderRig)? {
        playerFirstPersonRig
    }
}

extension PlayerBody: RenderRig {
    /// The player's contribution to the per-frame animation pass. Mirrors what
    /// `RenderScene.updateAnimations` does for cell-owned actors, including the
    /// `World > Environment` animation A/B toggle.
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
