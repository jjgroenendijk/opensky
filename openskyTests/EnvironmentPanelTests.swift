// Main-app Environment verification-surface layout coverage. Controls added
// across M7 must remain present with nonzero geometry as the panel grows.

import AppKit
@testable import opensky
import Testing

/// Conforms to both protocols the panel's `provider` requires, so assigning it
/// exercises the real wiring — including the refocus fan-out to sections.
@MainActor
private final class FakeShadowProvider: ShadowControlProviding, TerrainLODControlProviding {
    var sunShadowsEnabled = true
    var shadowQuality: ShadowQuality = .high
    var shadowDrawStats = ShadowDrawStats()
    var shadowUpdateMS: Double = 0
    var shadowsActive = true
    var refocusCount = 0

    func refocusGameView() {
        refocusCount += 1
    }

    var terrainLODConfigurationSnapshot = TerrainLODConfigurationSnapshot(
        configuration: .fallback, source: "test"
    )

    func applyTerrainLODConfiguration(_: TerrainLODConfiguration) -> Bool {
        true
    }

    func resetTerrainLODConfiguration() {}
}

@MainActor
private final class FakeGrassProvider: GrassControlProviding {
    var grassEnabled = true
    var grassDensityScale: Float = 1
    var grassDrawDistance: Float = GrassRenderPolicy.defaultDrawDistance
    var grassWindScale: Float = 1
    var grassSnapshot = GrassControlSnapshot(
        sceneInstances: 0, drawnInstances: 0, drawCalls: 0, distanceCulledInstances: 0,
        densityCulledInstances: 0, frustumCulledInstances: 0, budgetDroppedInstances: 0
    )
}

struct EnvironmentPanelTests {
    @Test @MainActor
    func weatherAndPrecipitationControlsHaveVisibleFrames() throws {
        let panel = EnvironmentPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        let controls = [
            panel.sunShadowsEnabledControl,
            panel.animationsEnabledControl,
            panel.weatherEnabledControl,
            panel.clearWeatherControl,
            panel.rainWeatherControl,
            panel.snowWeatherControl,
            panel.weatherTransitionsPausedControl,
            panel.precipitationEnabledControl,
            panel.grassEnabledControl,
            panel.grassDensityControl,
            panel.grassDistanceControl,
            panel.grassWindControl
        ]
        for control in controls {
            #expect(!control.isHidden, "\(control.identifier?.rawValue ?? "control") hidden")
            #expect(
                control.frame.height > 0,
                "\(control.identifier?.rawValue ?? "control") frame=\(control.frame)"
            )
            let documentFrame = control.convert(control.bounds, to: scrollView.documentView)
            #expect(
                scrollView.documentView?.bounds.intersects(documentFrame) == true,
                "\(control.identifier?.rawValue ?? "control") outside document: \(documentFrame)"
            )
        }
        let document = try #require(scrollView.documentView)
        #expect(document.frame.height > 0)
    }

    /// The sun-shadow A/B is a checkbox, not a hidden `H` keystroke: it must
    /// show the live state and drive it back (docs/tools/app-ui.md).
    @Test @MainActor
    func sunShadowsCheckboxRoundTripsProviderState() {
        let panel = EnvironmentPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeShadowProvider()
        fake.sunShadowsEnabled = false
        panel.provider = fake

        #expect(panel.sunShadowsEnabledControl.state == .off)

        let control = panel.sunShadowsEnabledControl
        control.state = .on
        control.sendAction(control.action, to: control.target)
        #expect(fake.sunShadowsEnabled == true)
        #expect(fake.refocusCount == 1, "control interaction must hand focus back to the world")
    }

    @Test @MainActor
    func grassSectionRoundTripsProviderState() {
        let panel = EnvironmentPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeGrassProvider()
        fake.grassEnabled = false
        panel.grassProvider = fake

        // Provider state syncs onto the forwarded control...
        #expect(panel.grassEnabledControl.state == .off)

        // ...and a control interaction drives the provider back.
        panel.grassEnabledControl.state = .on
        panel.grassEnabledControl.sendAction(
            panel.grassEnabledControl.action, to: panel.grassEnabledControl.target
        )
        #expect(fake.grassEnabled == true)
    }
}
