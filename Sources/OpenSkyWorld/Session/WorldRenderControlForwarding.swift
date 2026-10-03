// Lets the app's provider object stand in for its `WorldRenderControls`, so
// the panel registry keeps one provider value without a forward per member.
// `refocusGameView()` stays with the provider, which owns the view.

import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering

public protocol WorldRenderControlForwarding: ShadowControlProviding, TerrainLODControlProviding,
    WeatherControlProviding, AnimationControlProviding, ParticleControlProviding,
    PrecipitationControlProviding, GrassControlProviding, RenderDebugControlProviding,
    CameraControlProviding, FrameStatsProviding, SceneStatsProviding, TriggerControlProviding,
    PhysicsControlProviding
{
    var renderControls: WorldRenderControls { get }
}

extension WorldRenderControlForwarding {
    public var sunShadowsEnabled: Bool {
        get { renderControls.sunShadowsEnabled }
        set { renderControls.sunShadowsEnabled = newValue }
    }

    public var shadowQuality: ShadowQuality {
        get { renderControls.shadowQuality }
        set { renderControls.shadowQuality = newValue }
    }

    public var shadowDrawStats: ShadowDrawStats {
        renderControls.shadowDrawStats
    }

    public var shadowUpdateMS: Double {
        renderControls.shadowUpdateMS
    }

    public var shadowsActive: Bool {
        renderControls.shadowsActive
    }

    public var terrainLODConfigurationSnapshot: TerrainLODConfigurationSnapshot {
        renderControls.terrainLODConfigurationSnapshot
    }

    public var terrainLODOverrideActive: Bool {
        renderControls.terrainLODOverrideActive
    }

    public var weatherEnabled: Bool {
        get { renderControls.weatherEnabled }
        set { renderControls.weatherEnabled = newValue }
    }

    public var selectableWeatherNames: [String] {
        renderControls.selectableWeatherNames
    }

    public var currentWeatherName: String? {
        renderControls.currentWeatherName
    }

    public var weatherOverrideActive: Bool {
        renderControls.weatherOverrideActive
    }

    public var weatherTransitionFraction: Float {
        renderControls.weatherTransitionFraction
    }

    public var weatherTransitionsPaused: Bool {
        get { renderControls.weatherTransitionsPaused }
        set { renderControls.weatherTransitionsPaused = newValue }
    }

    public var windState: WindState {
        renderControls.windState
    }

    public var timeOfDay: Float {
        get { renderControls.timeOfDay }
        set { renderControls.timeOfDay = newValue }
    }

    public var actorAnimationsEnabled: Bool {
        get { renderControls.actorAnimationsEnabled }
        set { renderControls.actorAnimationsEnabled = newValue }
    }

    public var animationSnapshot: AnimationControlSnapshot {
        renderControls.animationSnapshot
    }

    public var particlesEnabled: Bool {
        get { renderControls.particlesEnabled }
        set { renderControls.particlesEnabled = newValue }
    }

    public var particlesFrozen: Bool {
        get { renderControls.particlesFrozen }
        set { renderControls.particlesFrozen = newValue }
    }

    public var particleEmissionScale: Float {
        get { renderControls.particleEmissionScale }
        set { renderControls.particleEmissionScale = newValue }
    }

    public var particleSnapshot: ParticleControlSnapshot {
        renderControls.particleSnapshot
    }

    public var precipitationEnabled: Bool {
        get { renderControls.precipitationEnabled }
        set { renderControls.precipitationEnabled = newValue }
    }

    public var precipitationSnapshot: PrecipitationRuntimeSnapshot {
        renderControls.precipitationSnapshot
    }

    public var precipitationTuning: PrecipitationTuning {
        renderControls.precipitationTuning
    }

    public var weatherVolumetricLighting: String? {
        renderControls.weatherVolumetricLighting
    }

    public var grassEnabled: Bool {
        get { renderControls.grassEnabled }
        set { renderControls.grassEnabled = newValue }
    }

    public var grassDensityScale: Float {
        get { renderControls.grassDensityScale }
        set { renderControls.grassDensityScale = newValue }
    }

    public var grassDrawDistance: Float {
        get { renderControls.grassDrawDistance }
        set { renderControls.grassDrawDistance = newValue }
    }

    public var grassWindScale: Float {
        get { renderControls.grassWindScale }
        set { renderControls.grassWindScale = newValue }
    }

    public var grassSnapshot: GrassControlSnapshot {
        renderControls.grassSnapshot
    }

    public var renderDebugMode: RenderDebugMode {
        get { renderControls.renderDebugMode }
        set { renderControls.renderDebugMode = newValue }
    }

    public var renderDebugLayers: RenderLayer {
        get { renderControls.renderDebugLayers }
        set { renderControls.renderDebugLayers = newValue }
    }

    public var renderDebugSnapshot: RenderDebugControlSnapshot {
        renderControls.renderDebugSnapshot
    }

    public var cameraPose: CameraPoseSnapshot {
        renderControls.cameraPose
    }

    public var movementMode: CameraMovementMode {
        get { renderControls.movementMode }
        set { renderControls.movementMode = newValue }
    }

    public var movementConfiguration: PlayerMovementConfiguration {
        renderControls.movementConfiguration
    }

    public var frameStatsSnapshot: FrameStatsSnapshot {
        renderControls.frameStatsSnapshot
    }

    public var sceneStatsSnapshot: SceneStatsSnapshot {
        renderControls.sceneStatsSnapshot
    }

    public var triggerStatsSnapshot: TriggerStatsSnapshot {
        renderControls.triggerStatsSnapshot
    }

    public var dynamicBodyStatsSnapshot: DynamicBodyStatsSnapshot {
        renderControls.dynamicBodyStatsSnapshot
    }

    public func applyTerrainLODConfiguration(_ configuration: TerrainLODConfiguration) -> Bool {
        renderControls.applyTerrainLODConfiguration(configuration)
    }

    public func resetTerrainLODConfiguration() {
        renderControls.resetTerrainLODConfiguration()
    }

    public func forceWeather(named name: String?) {
        renderControls.forceWeather(named: name)
    }

    public func forceWeather(_ preset: WeatherPreset) {
        renderControls.forceWeather(preset)
    }

    public func clearTriggerLog() {
        renderControls.clearTriggerLog()
    }

    public func setPhysicsFrozen(_ frozen: Bool) {
        renderControls.setPhysicsFrozen(frozen)
    }

    public func resetDynamicBodies() {
        renderControls.resetDynamicBodies()
    }
}
