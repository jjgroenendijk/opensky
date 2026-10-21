// Everything the renderer reads from the game for one frame, in one value. The
// simulation fills it once per frame, after every system has run, and the renderer
// reads only it, so no game value can change half way through an encode.

import OpenSkyPhysics
import simd

public struct RenderFrameInput {
    /// The pose every pass draws from: the player's view, or an override standing in for it.
    public var view: FreeFlyCamera
    public var movementMode = CameraMovementMode.fly
    public var fovYRadians = FirstPersonCamera.defaultFOVYRadians
    /// A camera mesh's horizontal view; the renderer turns it into `fovYRadians`
    /// for the drawable's aspect. Nil keeps `fovYRadians`.
    public var horizontalFOVRadians: Float?
    /// Fractional hour of day in [0, 24).
    public var timeOfDay = RenderFrameInput.defaultTimeOfDay
    /// Wind for precipitation, grass and particles. Calm when no weather is active.
    public var wind = WindState.calm
    /// This frame's resolved weather (exterior only); nil keeps the procedural sky.
    public var weather: ResolvedWeather?
    /// How the weather's rain or snow falls; nil keeps the current tuning.
    public var precipitationTuning: PrecipitationTuning?
    /// A script's fog for the loaded interior; ignored once the scene's lighting changes.
    public var interiorFog: InteriorFogOverride?
    /// The post-process values and running modifiers the composite pass applies.
    public var imageSpace = ImageSpaceState()
    public var instancePoses = RenderInstancePoses()
    public var rigs = RenderRigs()
    /// Resolved to a draw list against the framebuffer size each frame.
    public var ui = UIScene.empty
    /// Menu mode: the frame and UI still draw, but no clock advances.
    public var isPaused = false
    /// Slows animation, particles, and the world sim, not the camera. A kill cam sets it below 1.
    public var timeScale: Float = 1
    /// Static collision near the camera, for precipitation under roofs. nil outside a world.
    public var collisionQuery: CapsuleWorldCollider.CandidateQuery?

    /// The hour of day a frame without a game session is lit at.
    public static let defaultTimeOfDay: Float = 13

    public init(view: FreeFlyCamera) {
        self.view = view
    }
}

/// The player rigs the renderer draws outside the scene, because they survive scene swaps.
public struct RenderRigs {
    public var body: (any RenderRig)?
    public var arms: (any RenderRig)?
    public var visibility = PlayerRigVisibility.resolve(
        mode: .fly, hasBody: false, hasArms: false, armsEnabled: false, dialogueCamera: false
    )

    public init() {}

    public init(body: (any RenderRig)?, arms: (any RenderRig)?, visibility: PlayerRigVisibility) {
        (self.body, self.arms, self.visibility) = (body, arms, visibility)
    }

    var all: [any RenderRig] {
        [body, arms].compactMap(\.self)
    }
}

/// Where moved references are drawn, by REFR FormID. Each change takes a new
/// `revision`, so the renderer merges the maps only on a frame that changed them.
public struct RenderInstancePoses {
    /// How far simulated bodies moved since their cells were built.
    public var dynamicDeltas: [UInt32: float4x4] = [:] {
        didSet { revision = Self.nextRevision() }
    }

    public var npcDeltas: [UInt32: float4x4] = [:] {
        didSet { revision = Self.nextRevision() }
    }

    /// Where carts and their riders are now, as placements without scale.
    public var vehiclePoses: [UInt32: float4x4] = [:] {
        didSet { revision = Self.nextRevision() }
    }

    /// Where scripted moves (`TranslateTo`) have carried references, as placements without scale.
    public var scriptedPoses: [UInt32: float4x4] = [:] {
        didSet { revision = Self.nextRevision() }
    }

    public private(set) var revision = 0

    private static var lastRevision = 0

    public init() {}

    private static func nextRevision() -> Int {
        lastRevision += 1
        return lastRevision
    }
}
