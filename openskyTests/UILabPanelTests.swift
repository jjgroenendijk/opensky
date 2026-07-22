// Main-app UI Lab verification-surface coverage (M8.1.1): the panel's controls
// keep visible geometry as the surface grows, provider state round-trips
// through the controls, and the live readout renders the UIDrawStats numbers.

import AppKit
@testable import opensky
import Testing

@MainActor
private final class FakeUILabProvider: UILabControlProviding {
    var uiOverlayEnabled = true
    var uiSampleShown = false
    var uiScale: Float = 1
    var stats = UIDrawStats()
    var refocusCount = 0

    var uiSnapshot: UILabControlSnapshot {
        UILabControlSnapshot(
            overlayEnabled: uiOverlayEnabled,
            sampleShown: uiSampleShown,
            scale: uiScale,
            stats: stats
        )
    }

    func refocusGameView() {
        refocusCount += 1
    }
}

struct UILabPanelTests {
    @Test @MainActor
    func controlsHaveVisibleFrames() throws {
        let panel = UILabPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        let controls: [NSView] = [
            panel.overlayEnabledControl,
            panel.sampleControl,
            panel.scaleControl
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
    func controlsReflectProviderState() {
        let panel = UILabPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeUILabProvider()
        fake.uiOverlayEnabled = false
        fake.uiSampleShown = true
        fake.uiScale = 2
        panel.provider = fake
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(panel.overlayEnabledControl.state == .off)
        #expect(panel.sampleControl.state == .on)
        #expect(panel.scaleControl.titleOfSelectedItem == "200%")
    }

    @Test @MainActor
    func controlChangesDriveProvider() {
        let panel = UILabPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeUILabProvider()
        panel.provider = fake

        panel.overlayEnabledControl.state = .off
        panel.overlayEnabledControl.sendAction(
            panel.overlayEnabledControl.action, to: panel.overlayEnabledControl.target
        )
        #expect(fake.uiOverlayEnabled == false)

        panel.sampleControl.state = .on
        panel.sampleControl.sendAction(
            panel.sampleControl.action, to: panel.sampleControl.target
        )
        #expect(fake.uiSampleShown == true)

        panel.scaleControl.selectItem(withTitle: "150%")
        panel.scaleControl.sendAction(panel.scaleControl.action, to: panel.scaleControl.target)
        #expect(fake.uiScale == 1.5)

        // Each control interaction hands focus back to the game view.
        #expect(fake.refocusCount == 3)
    }

    @Test @MainActor
    func statsReadoutRendersDrawStats() {
        let panel = UILabPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeUILabProvider()
        fake.stats = UIDrawStats(
            drawCalls: 1, quads: 12, glyphs: 34, dropped: 2, atlasWidth: 256, atlasHeight: 128
        )
        panel.provider = fake
        panel.refreshStats()

        let readout = panel.statsReadout
        #expect(!readout.isEmpty)
        for token in ["12", "34", "2", "256", "128"] {
            #expect(readout.contains(token), "missing \(token) in: \(readout)")
        }
    }
}
