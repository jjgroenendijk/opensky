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
    var terrainLODOverrideActive: Bool { get }
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
    var weatherOverrideActive: Bool { get }
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

/// One playing audio source as the World > Audio panel shows it.
nonisolated struct AudioSourceStatsSnapshot: Equatable {
    /// VFS path of the playing file.
    let name: String
    let categoryName: String
    /// False for a non-positional source (music beds routed to a category
    /// submix): its position and distance are not meaningful.
    let isPositional: Bool
    /// World position in native Skyrim units. Zero when not positional.
    let worldPosition: SIMD3<Float>
    /// Listener distance in meters (the attenuation model's unit). Zero when
    /// not positional.
    let distanceMeters: Float
    /// Fade multiplier in [0, 1] currently folded into the gain. 1 = not faded.
    let fadeGain: Float
    /// True while a gain ramp is in flight on this source.
    let isFading: Bool
    /// master x category x source x fade gain, before distance attenuation.
    let effectiveGain: Float
}

/// Published state of the world audio graph, read at 2 Hz by the panel. Only
/// this Equatable value crosses from the engine to the readout.
nonisolated struct AudioStatsSnapshot: Equatable {
    let enabled: Bool
    let engineRunning: Bool
    /// Output device format line, or the failure reason when not running.
    let outputDescription: String
    let sources: [AudioSourceStatsSnapshot]
    let sourceCap: Int

    /// Reported by providers with no live audio engine.
    static let empty = AudioStatsSnapshot(
        enabled: false, engineRunning: false, outputDescription: "no engine",
        sources: [], sourceCap: 0
    )
}

@MainActor
protocol AudioControlProviding: AnyObject {
    var audioEnabled: Bool { get set }
    var audioMasterVolume: Float { get set }
    func audioVolume(for category: AudioCategory) -> Float
    func setAudioVolume(_ volume: Float, for category: AudioCategory)
    /// VFS paths the World > Audio picker offers (vanilla: the 269 `.xwm`
    /// music files — sound effects are `.wav` and wait on a PCM reader).
    var selectableAudioFileNames: [String] { get }
    /// Streams the picked file as a positional source placed a fixed offset in
    /// front of the camera, so panning/attenuation are audible immediately.
    /// Returns nil on success or a short failure description for the readout.
    func playAudioFile(named name: String) -> String?
    func stopAllAudioSources()
    var audioStatsSnapshot: AudioStatsSnapshot { get }

    // World SFX + ambience director controls (M9.2.2). The director lives
    // beside the audio engine; these no-op when audio is not enabled.

    /// Use-key activation plays the activator's SNDR. Off still lets ambience
    /// run; the toggles are independent.
    var sfxEnabled: Bool { get set }
    /// Per-cell ambient bed starts/stops with the center cell. Off still lets
    /// one-shot SFX run.
    var ambienceEnabled: Bool { get set }
    /// Force-stops the current ambience bed; the next cell change restarts it.
    /// Verification helper for A/B inspection.
    func stopAmbience()
    /// Most recent SFX file path the director played (or failed to play).
    var lastSFXDescription: String? { get }
    /// Most recent SFX failure reason; nil when the last trigger succeeded.
    var lastSFXError: String? { get }
    /// FormIDs of the SNDR/SOUN records in the current ambient bed, joined for
    /// the readout. "none" when the bed is empty.
    var currentAmbienceDescription: String { get }
}
