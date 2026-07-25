// Narrow live-renderer seams consumed by World > Environment controls.

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
