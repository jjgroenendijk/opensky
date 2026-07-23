// The destination registry is the single registration point for main-app
// sidebar destinations (issue #98). These tests pin the UI-test accessibility
// contract (literal ids) as unit assertions — machine-checkable while make
// test-ui is blocked — and verify every world-inspector factory builds a panel.

import AppKit
@testable import opensky
import Testing

@MainActor
private final class FakeWorldProviders: WorldControlProviders {
    var refocusCount = 0

    // ShadowControlProviding
    var shadowQuality: ShadowQuality = .high
    var shadowDrawStats = ShadowDrawStats()
    var shadowUpdateMS: Double = 0
    var shadowsActive = true
    func refocusGameView() {
        refocusCount += 1
    }

    /// TerrainLODControlProviding
    var terrainLODConfigurationSnapshot = TerrainLODConfigurationSnapshot(
        configuration: .fallback, source: "test"
    )
    func applyTerrainLODConfiguration(_: TerrainLODConfiguration) -> Bool {
        true
    }

    func resetTerrainLODConfiguration() {}

    // WeatherControlProviding
    var weatherEnabled = false
    var selectableWeatherNames: [String] = []
    func forceWeather(named _: String?) {}
    func forceWeather(_: WeatherPreset) {}
    var currentWeatherName: String?
    var weatherTransitionFraction: Float = 0
    var weatherTransitionsPaused = false
    var windState: WindState = .calm
    var timeOfDay: Float = 12

    // AnimationControlProviding
    var actorAnimationsEnabled = false
    var animationSnapshot = AnimationControlSnapshot(
        playbackCount: 0, updatedBoneCount: 0, updateMS: 0
    )

    // ParticleControlProviding
    var particlesEnabled = true
    var particlesFrozen = false
    var particleEmissionScale: Float = 1
    var particleSnapshot = ParticleControlSnapshot(systemCount: 0, emitterCount: 0, liveCount: 0)

    // PrecipitationControlProviding
    var precipitationEnabled = false
    var precipitationSnapshot = PrecipitationRuntimeSnapshot(
        state: .none, roofOccluded: false, rainLiveCount: 0, snowLiveCount: 0
    )

    // GrassControlProviding
    var grassEnabled = true
    var grassDensityScale: Float = 1
    var grassDrawDistance: Float = GrassRenderPolicy.defaultDrawDistance
    var grassWindScale: Float = 1
    var grassSnapshot = GrassControlSnapshot(
        sceneInstances: 0, drawnInstances: 0, drawCalls: 0, distanceCulledInstances: 0,
        densityCulledInstances: 0, frustumCulledInstances: 0, budgetDroppedInstances: 0
    )

    // UILabControlProviding
    var uiOverlayEnabled = true
    var uiSampleShown = false
    var uiScale: Float = 1
    var uiSnapshot = UILabControlSnapshot(
        overlayEnabled: true, sampleShown: false, scale: 1, stats: UIDrawStats()
    )
}

struct DestinationRegistryTests {
    @Test
    func idsAreUnique() {
        let ids = DestinationRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test
    func worldInspectorOrderAndIdentifiers() {
        let inspectors = DestinationRegistry.worldInspectors
        #expect(inspectors.map(\.id) == ["environment", "uiLab"])
        // Accessibility identifiers are the UI-test contract; pin them literally.
        #expect(
            inspectors.map(\.sidebarIdentifier)
                == ["WorldDestination-environment", "WorldDestination-uiLab"]
        )
    }

    @Test @MainActor
    func everyWorldInspectorFactoryBuildsAPanel() {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        for descriptor in DestinationRegistry.worldInspectors {
            guard case let .worldInspector(makePanel) = descriptor.content else {
                Issue.record("\(descriptor.id) is not a world inspector")
                continue
            }
            let panel = makePanel(context)
            panel.loadViewIfNeeded()
            #expect(panel.view.frame.width >= 0)
        }
    }
}
