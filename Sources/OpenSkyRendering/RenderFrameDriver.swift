// The simulation side of a frame, as the renderer sees it.
//
// The renderer draws. Its driver moves the camera, advances the game clock,
// and runs the world, weather and audio. The renderer calls the driver at fixed
// points in the frame, so the order of the work never changes:
//
// Live frame (`draw(in:)`):
//   1. `prepareLiveFrame`: camera and player, the per-frame `onFrame` hook
//      (which may swap the scene), game clock, world simulation, weather.
//   2. The renderer's own step: animations, particles, precipitation.
//   3. `finishLiveFrame`: audio.
//
// Offscreen frame: the renderer calls `updateWorldSim`, `updateWeather` and
// `updateAudio` itself, with the offscreen delta, between the same steps.
//
// The renderer reads the rest of what it draws from the driver on demand, so a
// value is never a stale copy: the time of day, the wind, the projection's field
// of view, and the player's rigs.

import Metal

@MainActor
public protocol RenderFrameDriver: AnyObject {
    func prepareLiveFrame()
    func finishLiveFrame()
    func updateWorldSim(deltaTime: Float)
    func updateWeather(deltaTime: Float)
    func updateAudio(deltaTime: Float)
    /// Runs after `setScene` replaced the framing camera, so the player can be
    /// placed in the new scene.
    func didReplaceCamera(_ camera: SceneCamera)

    /// Fractional hour of day in [0, 24).
    var timeOfDay: Float { get set }
    var wind: WindState { get }
    var projectionFOVYRadians: Float { get }
    var rigVisibility: PlayerRigVisibility { get }
    var playerBodyRig: (any RenderRig)? { get }
    var firstPersonRig: (any RenderRig)? { get }
    /// CPU wall time of the last world-simulation and audio updates.
    var lastScriptUpdateMS: Double { get }
    var lastAudioUpdateMS: Double { get }
}

/// A rig the renderer draws outside the scene, because it survives scene swaps:
/// the player's body and first-person arms.
@MainActor
public protocol RenderRig: AnyObject {
    var render: RenderScene { get }
    var residencyAllocations: [MTLAllocation] { get }
    /// Publishes the rig's current pose to its palettes. Returns the number of
    /// bones updated.
    func publishAnimation(enabled: Bool) -> Int
}

/// What the renderer reads from its driver. With no driver attached (a renderer
/// built by `init(rendering:)` alone) the frame keeps the defaults: noon-ish
/// light, calm wind, the shared field of view, and no player rigs.
extension Renderer {
    /// The hour of day a renderer without a driver lights its frame at.
    public static let defaultTimeOfDay: Float = 13

    /// Fractional hour of day in [0, 24), projected from the game clock.
    public var timeOfDay: Float {
        get { frameDriver?.timeOfDay ?? Self.defaultTimeOfDay }
        set { frameDriver?.timeOfDay = newValue }
    }

    /// Published wind for precipitation, grass, particles and audio. Calm when
    /// no weather is active.
    public var currentWind: WindState {
        frameDriver?.wind ?? .calm
    }

    /// What this frame draws and casts (`PlayerRigVisibility`, issue #190).
    public var rigVisibility: PlayerRigVisibility {
        frameDriver?.rigVisibility ?? PlayerRigVisibility.resolve(
            mode: movementMode,
            hasBody: false,
            hasArms: false,
            armsEnabled: false,
            dialogueCamera: false
        )
    }
}
