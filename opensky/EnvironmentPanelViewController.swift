// World > Environment destination panel: the sidebar verification surface for
// world environment subsystems. Since issue #98 it is a thin composition of
// self-contained sections (shadows, animation, weather, particles, precipitation,
// grass, distant LOD) built on the shared panel framework (opensky/Shell). Each
// section talks to the live renderer through its own narrow provider protocol,
// never renderer internals. A section can graduate to its own destination when
// it outgrows a collapsible group (docs/tools/app-ui.md).

import AppKit

final class EnvironmentPanelViewController: InspectorPanelViewController {
    let shadowSection = ShadowSection()
    let animationSection = AnimationSection()
    let weatherSection = WeatherSection()
    let particlesSection = ParticlesSection()
    let precipitationSection = PrecipitationSection()
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

    weak var grassProvider: (any GrassControlProviding)? {
        didSet { grassSection.provider = grassProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [
            shadowSection, animationSection, weatherSection, particlesSection,
            precipitationSection, grassSection, terrainLODSection
        ]
    }

    /// Control forwards for the verification-surface tests. Sections own the
    /// controls; these keep the existing test + wiring API stable.
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
