// Narrow live-renderer seams consumed by the World sidebar panels and the
// frame HUD. No AppKit here on purpose: the file compiles into both the app and
// the CLI target, so a protocol added here needs no project-membership change.

@MainActor
protocol ShadowControlProviding: AnyObject {
    /// Sun-shadow on/off, independent of the selected quality tier so an A/B
    /// flip does not discard the tier. Was the `H` key until it became a
    /// checkbox (no dev behaviour reachable only by an unadvertised keystroke —
    /// docs/tools/app-ui.md).
    var sunShadowsEnabled: Bool { get set }
    var shadowQuality: ShadowQuality { get set }
    var shadowDrawStats: ShadowDrawStats { get }
    var shadowUpdateMS: Double { get }
    var shadowsActive: Bool { get }
    func refocusGameView()
}

@MainActor
protocol TerrainLODControlProviding: AnyObject {
    var terrainLODConfigurationSnapshot: TerrainLODConfigurationSnapshot { get }
    func applyTerrainLODConfiguration(_ configuration: TerrainLODConfiguration) -> Bool
    func resetTerrainLODConfiguration()
}

@MainActor
protocol WeatherControlProviding: AnyObject {
    var weatherEnabled: Bool { get set }
    var selectableWeatherNames: [String] { get }
    func forceWeather(named name: String?)
    func forceWeather(_ preset: WeatherPreset)
    var currentWeatherName: String? { get }
    var weatherTransitionFraction: Float { get }
    var weatherTransitionsPaused: Bool { get set }
    var windState: WindState { get }
    var timeOfDay: Float { get set }
}

nonisolated struct AnimationControlSnapshot: Equatable {
    let playbackCount: Int
    let updatedBoneCount: Int
    let updateMS: Double
}

@MainActor
protocol AnimationControlProviding: AnyObject {
    var actorAnimationsEnabled: Bool { get set }
    var animationSnapshot: AnimationControlSnapshot { get }
}

nonisolated struct ParticleControlSnapshot: Equatable {
    let systemCount: Int
    let emitterCount: Int
    let liveCount: Int
}

@MainActor
protocol ParticleControlProviding: AnyObject {
    var particlesEnabled: Bool { get set }
    var particlesFrozen: Bool { get set }
    var particleEmissionScale: Float { get set }
    var particleSnapshot: ParticleControlSnapshot { get }
}

@MainActor
protocol PrecipitationControlProviding: AnyObject {
    var precipitationEnabled: Bool { get set }
    var precipitationSnapshot: PrecipitationRuntimeSnapshot { get }
}

nonisolated struct GrassControlSnapshot: Equatable {
    let sceneInstances: Int
    let drawnInstances: Int
    let drawCalls: Int
    let distanceCulledInstances: Int
    let densityCulledInstances: Int
    let frustumCulledInstances: Int
    let budgetDroppedInstances: Int
}

@MainActor
protocol GrassControlProviding: AnyObject {
    var grassEnabled: Bool { get set }
    var grassDensityScale: Float { get set }
    var grassDrawDistance: Float { get set }
    var grassWindScale: Float { get set }
    var grassSnapshot: GrassControlSnapshot { get }
}

/// Live camera pose, as one value so a panel and the HUD read the same frame's
/// numbers rather than each polling the parts separately.
nonisolated struct CameraPoseSnapshot: Equatable {
    /// World position in native Skyrim units (docs/decisions/coordinates.md).
    let position: SIMD3<Float>
    /// Heading in radians about world +Z.
    let yaw: Float
    /// Elevation in radians, positive looking up.
    let pitch: Float
    /// Exterior cell the position falls in, by floor division.
    let cell: CellCoordinate
    let movementMode: CameraMovementMode

    /// Reported by providers with no live renderer.
    static let unavailable = CameraPoseSnapshot(
        position: .zero, yaw: 0, pitch: 0, cell: CellCoordinate(x: 0, y: 0), movementMode: .fly
    )

    var yawDegrees: Float {
        yaw * 180 / .pi
    }

    var pitchDegrees: Float {
        pitch * 180 / .pi
    }
}

@MainActor
protocol CameraControlProviding: AnyObject {
    var cameraPose: CameraPoseSnapshot { get }
    /// Settable so fly/walk is reachable from the sidebar. The `G` key stays as
    /// an accelerator over the same renderer state, per docs/tools/app-ui.md:
    /// no dev behaviour reachable only by an unadvertised keystroke.
    var movementMode: CameraMovementMode { get set }
    /// One-line pose summary meant to be pasted into a bug report.
    var cameraPoseDescription: String { get }
}

extension CameraControlProviding {
    /// Default implementation so every consumer formats the pose identically;
    /// a conformer that overrode it would let two readouts of the same camera
    /// disagree.
    var cameraPoseDescription: String {
        let pose = cameraPose
        return String(
            format: "camera %@ | position %.1f, %.1f, %.1f | yaw %.1f deg | "
                + "pitch %.1f deg | cell %d, %d",
            pose.movementMode == .walk ? "walk" : "fly",
            pose.position.x, pose.position.y, pose.position.z,
            pose.yawDegrees, pose.pitchDegrees, pose.cell.x, pose.cell.y
        )
    }
}

@MainActor
protocol FrameStatsProviding: AnyObject {
    /// Latest closed live window; `FrameStatsSnapshot.empty` before the first
    /// one closes or with no live renderer.
    var frameStatsSnapshot: FrameStatsSnapshot { get }
}

/// Per-frame scene accounting plus the streaming and memory numbers that answer
/// "is this frame slow because of what is resident?".
nonisolated struct SceneStatsSnapshot: Equatable {
    let drawCalls: Int
    let drawnInstances: Int
    let culledInstances: Int
    let residentCellCount: Int
    /// Process physical footprint, or nil when the mach call fails.
    let memoryFootprintMB: Double?

    static let empty = SceneStatsSnapshot(
        drawCalls: 0, drawnInstances: 0, culledInstances: 0,
        residentCellCount: 0, memoryFootprintMB: nil
    )
}

@MainActor
protocol SceneStatsProviding: AnyObject {
    var sceneStatsSnapshot: SceneStatsSnapshot { get }
}
