// Main-app Environment verification-surface layout coverage. Controls added
// across M7 must remain present with nonzero geometry as the panel grows.

import AppKit
@testable import opensky
import Testing

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
