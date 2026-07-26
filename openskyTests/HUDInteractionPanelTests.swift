// World > HUD & Interaction acceptance-surface coverage. Uses only synthetic
// provider state; the real-install prompt/pixel gate lives in its env-gated
// acceptance test.

import AppKit
@testable import opensky
import simd
import Testing

struct HUDInteractionPanelTests {
    @MainActor
    private func makePanel(
        _ provider: FakeWorldProviders
    ) -> HUDInteractionPanelViewController {
        let panel = HUDInteractionPanelViewController()
        panel.provider = provider
        panel.loadViewIfNeeded()
        return panel
    }

    @Test @MainActor
    func controlsExposeStableIdentifiersAndRoundTripProviderState() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.elementsSection
        let controls: [(NSControl, String)] = [
            (section.layerControl, "HUDLayerEnabledControl"),
            (section.crosshairControl, "HUDCrosshairControl"),
            (section.metersControl, "HUDMetersControl"),
            (section.compassControl, "HUDCompassControl"),
            (section.markersControl, "HUDMarkersControl"),
            (section.promptControl, "HUDPromptControl"),
            (section.scaleControl, "HUDScaleControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }

        section.metersControl.state = .off
        send(section.metersControl)
        #expect(!provider.hudMetersEnabled)

        section.scaleControl.selectItem(withTitle: "150%")
        send(section.scaleControl)
        #expect(provider.hudScale == 1.5)
        #expect(provider.refocusCount == 2)

        section.performResetToDefaults()
        #expect(provider.hudMetersEnabled)
        #expect(provider.hudScale == 1)
    }

    @Test @MainActor
    func targetReadoutShowsLivePromptGeometryAndCompass() {
        let provider = FakeWorldProviders()
        provider.hudControlSnapshot = HUDControlSnapshot(
            isLoaded: true,
            loadError: nil,
            targetReference: FormID(0x123),
            targetBase: FormID(0x456),
            targetName: "Test Door",
            targetAction: "Open",
            targetDistance: 87.5,
            targetPosition: SIMD3<Float>(10, 20, 30),
            hitPosition: SIMD3<Float>(11, 21, 31),
            prompt: "Open Test Door",
            markerHeadings: [315],
            cameraHeading: 270,
            scale: 1,
            drawStats: SWFDrawStats(drawCalls: 12)
        )
        let panel = makePanel(provider)
        panel.targetSection.refreshReadout()
        let text = panel.targetSection.statsReadout

        #expect(text.contains("00000123"))
        #expect(text.contains("base 00000456"))
        #expect(text.contains("Open Test Door"))
        #expect(text.contains("87.5 units"))
        #expect(text.contains("camera 270.0°"))
        #expect(text.contains("markers 315.0°"))
        #expect(panel.targetSection.sectionIdentifier == "hudTarget")
    }

    @Test @MainActor
    func controlsRemainInsideTheScrollablePanel() throws {
        let panel = makePanel(FakeWorldProviders())
        let scroll = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        for control in [
            panel.elementsSection.layerControl,
            panel.elementsSection.scaleControl
        ] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            let frame = control.convert(control.bounds, to: scroll.documentView)
            #expect(scroll.documentView?.bounds.intersects(frame) == true)
        }
    }

    @MainActor
    private func send(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }
}
