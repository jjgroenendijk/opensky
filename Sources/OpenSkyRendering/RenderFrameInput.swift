// Everything the renderer reads from the game for one frame, in one value. The
// simulation fills it once per frame, after every system has run, and the renderer
// reads only it, so no game value can change half way through an encode.

public import OpenSkyRenderCore
public import simd

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
    /// The sun path, moons, stars, and aurora; nil keeps the fixed camera sun.
    public var celestial: CelestialSky?
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
    /// Whether a roof covers a point, for precipitation under roofs. nil outside a world.
    public var roofAbove: PrecipitationRoofCheck?

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
        didSet { revision = revisions.next() }
    }

    public var npcDeltas: [UInt32: float4x4] = [:] {
        didSet { revision = revisions.next() }
    }

    /// Where carts and their riders are now, as placements without scale.
    public var vehiclePoses: [UInt32: float4x4] = [:] {
        didSet { revision = revisions.next() }
    }

    /// Where scripted moves (`TranslateTo`) have carried references, as placements without scale.
    public var scriptedPoses: [UInt32: float4x4] = [:] {
        didSet { revision = revisions.next() }
    }

    /// How far each reference has faded out, 0 to 1. Read every frame, so it takes no revision.
    public var fades: [UInt32: Float] = [:]

    public private(set) var revision = PoseRevision.unchanged

    /// Shared by the copies of one value, so a change in any copy takes a new count.
    private let revisions = PoseRevisionSource()

    public init() {}
}

/// One state of a `RenderInstancePoses`. Its source belongs to the value and its copies,
/// so two values never share a revision after a change, with no process-wide counter.
public struct PoseRevision: Equatable {
    fileprivate let source: PoseRevisionSource?
    fileprivate let count: Int

    /// A value nothing changed yet.
    public static let unchanged = PoseRevision(source: nil, count: 0)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source === rhs.source && lhs.count == rhs.count
    }
}

private final class PoseRevisionSource {
    private var last = 0

    func next() -> PoseRevision {
        last += 1
        return PoseRevision(source: self, count: last)
    }
}
