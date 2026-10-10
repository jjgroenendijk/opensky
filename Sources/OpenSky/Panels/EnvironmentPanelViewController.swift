// World > Environment: a composition of self-contained sections (shadows,
// animation, weather, particles, precipitation, water, terrain, grass, distant LOD). Each
// section reaches the renderer through its own narrow provider protocol.

import AppKit
import OpenSkyWorld

final class EnvironmentPanelViewController: InspectorPanelViewController {
    let shadowSection = ShadowSection()
    let animationSection = AnimationSection()
    let weatherSection = WeatherSection()
    let particlesSection = ParticlesSection()
    let precipitationSection = PrecipitationSection()
    let waterSection = WaterSection()
    let terrainSection = TerrainSection()
    let grassSection = GrassSection()
    let terrainLODSection = TerrainLODSection()

    /// Live shadow + terrain-LOD bridge. Weak: the game controller owns this
    /// panel's parent and the renderer, so the panel must not retain back.
    weak var provider: (any ShadowControlProviding & TerrainLODControlProviding)? {
        didSet {
            shadowSection.provider = provider
            terrainLODSection.provider = provider
            refocusAction = { [weak provider] in provider?.refocusGameView() }
        }
    }

    weak var weatherProvider: (any WeatherControlProviding)? {
        didSet { weatherSection.provider = weatherProvider }
    }

    weak var animationProvider: (any AnimationControlProviding)? {
        didSet { animationSection.provider = animationProvider }
    }

    weak var particleProvider: (any ParticleControlProviding)? {
        didSet { particlesSection.provider = particleProvider }
    }

    weak var precipitationProvider: (any PrecipitationControlProviding)? {
        didSet { precipitationSection.provider = precipitationProvider }
    }

    weak var waterProvider: (any WaterControlProviding)? {
        didSet { waterSection.provider = waterProvider }
    }

    weak var terrainProvider: (any TerrainShadingControlProviding)? {
        didSet { terrainSection.provider = terrainProvider }
    }

    weak var grassProvider: (any GrassControlProviding)? {
        didSet { grassSection.provider = grassProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [
            shadowSection, animationSection, weatherSection, particlesSection,
            precipitationSection, waterSection, terrainSection, grassSection, terrainLODSection
        ]
    }

    /// Control forwards for the verification-surface tests. Sections own the
    /// controls; these keep the existing test + wiring API stable.
    var sunShadowsEnabledControl: NSButton {
        shadowSection.enabledControl
    }

    var animationsEnabledControl: NSButton {
        animationSection.enabledControl
    }

    var weatherEnabledControl: NSButton {
        weatherSection.enabledControl
    }

    var clearWeatherControl: NSButton {
        weatherSection.clearControl
    }

    var rainWeatherControl: NSButton {
        weatherSection.rainControl
    }

    var snowWeatherControl: NSButton {
        weatherSection.snowControl
    }

    var weatherTransitionsPausedControl: NSButton {
        weatherSection.transitionsPausedControl
    }

    var precipitationEnabledControl: NSButton {
        precipitationSection.enabledControl
    }

    var waterDepthControl: NSButton {
        waterSection.depthControl
    }

    var grassEnabledControl: NSButton {
        grassSection.enabledControl
    }

    var grassDensityControl: NSSlider {
        grassSection.densityControl
    }

    var grassDistanceControl: NSSlider {
        grassSection.distanceControl
    }

    var grassWindControl: NSSlider {
        grassSection.windControl
    }
}
