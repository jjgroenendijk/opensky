// Main-app UI Lab verification-surface coverage (M8.1.1 + M8.1.4): the panel's
// controls keep visible geometry as the surface grows, provider state
// round-trips through the controls (overlay, samples, scale, menu-mode
// push/pop/clear), and the live readouts render the UIDrawStats, menu-stack,
// and translation-provider numbers.

import AppKit
@testable import opensky
import Testing

@MainActor
private final class FakeUILabProvider: UILabControlProviding, SWFLabControlProviding {
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

    var pushCount = 0
    var popCount = 0
    var clearCount = 0
    var menuModeSnapshot = MenuModeControlSnapshot(
        isMenuMode: false, topMenuName: nil, stackDepth: 0, isWorldSimPaused: false
    )

    func pushPreviewMenu() {
        pushCount += 1
    }

    func popPreviewMenu() {
        popCount += 1
    }

    func clearPreviewMenus() {
        clearCount += 1
    }

    var uiLocalizedSampleShown = false
    var localizedLabelsSnapshot = LocalizedLabelsControlSnapshot(
        sampleShown: false, sampleKeyCount: 0, language: "english",
        installLoaded: false, installFileCount: 0, installKeyCount: 0
    )

    var swfMoviePaths: [String] = []
    var swfLayerEnabled = true
    func selectSWFMovie(path _: String?) {}
    var swfLabSnapshot = SWFLabControlSnapshot(
        selectedPath: nil, layerEnabled: true, loadError: nil, tally: nil,
        unresolvedFontNames: [], drawStats: SWFDrawStats(), installLoaded: false,
        runtime: nil
    )
    func startSWFRuntime() {}
    func advanceSWFRuntime(ticks _: Int) {}
    func stopSWFRuntime() {}
    func sendSWFRuntimeInput(_: SWFInputEvent) {}
    func callSWFRuntimeMovie(_: String) {}
    func clearSWFInvokeLog() {}
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
            panel.localizedSampleControl,
            panel.scaleControl,
            panel.menuPushControl,
            panel.menuPopControl,
            panel.menuClearControl
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
            drawCalls: 1, quads: 12, glyphs: 34, dropped: 2, atlasWidth: 256, atlasHeight: 128,
            atlasGlyphs: 77, atlasOccupancy: 0.5, atlasPackFailures: 9
        )
        panel.provider = fake
        panel.refreshStats()

        let readout = panel.statsReadout
        #expect(!readout.isEmpty)
        // Atlas occupancy + overflow (issue #127) are part of the contract: they
        // are how a user sees glyph cells come back when movies swap.
        for token in ["12", "34", "2", "256", "128", "77 glyphs", "50% full", "overflow: 9"] {
            #expect(readout.contains(token), "missing \(token) in: \(readout)")
        }
    }

    /// Accessibility ids are the UI-test contract (docs/tools/app-ui.md); pin
    /// them literally while make test-ui is blocked on this machine.
    @Test @MainActor
    func controlAccessibilityIdentifiersAreStable() {
        let panel = UILabPanelViewController()
        panel.loadViewIfNeeded()
        #expect(panel.overlayEnabledControl.accessibilityIdentifier() == "UIOverlayEnabledControl")
        #expect(panel.sampleControl.accessibilityIdentifier() == "UILabSampleControl")
        #expect(panel.localizedSampleControl.accessibilityIdentifier() == "UIStringsSampleControl")
        #expect(panel.scaleControl.accessibilityIdentifier() == "UIScaleControl")
        #expect(panel.menuPushControl.accessibilityIdentifier() == "UIMenuPushControl")
        #expect(panel.menuPopControl.accessibilityIdentifier() == "UIMenuPopControl")
        #expect(panel.menuClearControl.accessibilityIdentifier() == "UIMenuClearControl")
    }

    /// The SWF movie selector (M8.2.5) is a hosted child section: it must be
    /// adopted as a child view controller and appear in the scroll document
    /// under the standard collapsible header.
    @Test @MainActor
    func swfSectionIsHostedInsideThePanel() throws {
        let panel = UILabPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 900)
        panel.view.layoutSubtreeIfNeeded()

        #expect(panel.swfSection.parent === panel)
        let document = try #require(scrollView.documentView)
        #expect(
            Self.containsIdentifier("PanelSection-swfMovie", in: document),
            "SWF section header missing from the UI Lab document"
        )
        let sectionFrame = panel.swfSection.view.convert(
            panel.swfSection.view.bounds, to: document
        )
        #expect(document.bounds.intersects(sectionFrame), "SWF section outside document")
    }

    /// The AS2 runtime driver (M8.3.3) is hosted the same way, beside the
    /// selector rather than inside it.
    @Test @MainActor
    func swfRuntimeSectionIsHostedInsideThePanel() throws {
        let panel = UILabPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 1400)
        panel.view.layoutSubtreeIfNeeded()

        #expect(panel.swfRuntimeSection.parent === panel)
        let document = try #require(scrollView.documentView)
        #expect(
            Self.containsIdentifier("PanelSection-swfRuntime", in: document),
            "SWF runtime section header missing from the UI Lab document"
        )
        let sectionFrame = panel.swfRuntimeSection.view.convert(
            panel.swfRuntimeSection.view.bounds, to: document
        )
        #expect(document.bounds.intersects(sectionFrame), "SWF runtime section outside document")
    }

    @MainActor
    private static func containsIdentifier(_ identifier: String, in view: NSView) -> Bool {
        if view.accessibilityIdentifier() == identifier {
            return true
        }
        return view.subviews.contains { containsIdentifier(identifier, in: $0) }
    }

    /// The panel's ticker must reach the hosted section too, or its readout
    /// would freeze while the rest of the panel updates.
    @Test @MainActor
    func inspectingThePanelDrivesTheSWFSection() {
        let panel = UILabPanelViewController()
        panel.loadViewIfNeeded()
        panel.startInspecting()
        defer { panel.stopInspecting() }
        #expect(panel.swfSection.statsReadout == "SWF state unavailable.")
        #expect(panel.swfRuntimeSection.stateReadout == "SWF runtime unavailable.")
    }

    @Test @MainActor
    func swfProviderReachesTheHostedSection() {
        let panel = UILabPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeUILabProvider()
        panel.swfProvider = fake
        #expect(panel.swfSection.provider === fake)
        #expect(panel.swfRuntimeSection.provider === fake)
    }

    @Test @MainActor
    func menuButtonsDriveProvider() {
        let panel = UILabPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeUILabProvider()
        panel.provider = fake

        for control in [panel.menuPushControl, panel.menuPopControl, panel.menuClearControl] {
            control.sendAction(control.action, to: control.target)
        }
        #expect(fake.pushCount == 1)
        #expect(fake.popCount == 1)
        #expect(fake.clearCount == 1)
        // Each control interaction hands focus back to the game view.
        #expect(fake.refocusCount == 3)
    }

    @Test @MainActor
    func menuReadoutRendersSnapshot() {
        let panel = UILabPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeUILabProvider()
        fake.menuModeSnapshot = MenuModeControlSnapshot(
            isMenuMode: true, topMenuName: "UILabMenu2", stackDepth: 2, isWorldSimPaused: true
        )
        panel.provider = fake
        panel.refreshStats()

        let readout = panel.menuReadout
        for token in ["Menu mode: on", "Depth: 2", "UILabMenu2", "paused"] {
            #expect(readout.contains(token), "missing \(token) in: \(readout)")
        }
    }

    @Test @MainActor
    func localizedSampleControlRoundTrips() {
        let panel = UILabPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeUILabProvider()
        fake.uiLocalizedSampleShown = true
        panel.provider = fake
        panel.startInspecting()
        defer { panel.stopInspecting() }
        #expect(panel.localizedSampleControl.state == .on)

        panel.localizedSampleControl.state = .off
        panel.localizedSampleControl.sendAction(
            panel.localizedSampleControl.action, to: panel.localizedSampleControl.target
        )
        #expect(fake.uiLocalizedSampleShown == false)
    }

    @Test @MainActor
    func stringsReadoutRendersProviderCounts() {
        let panel = UILabPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeUILabProvider()
        fake.localizedLabelsSnapshot = LocalizedLabelsControlSnapshot(
            sampleShown: true, sampleKeyCount: 4, language: "english",
            installLoaded: true, installFileCount: 3, installKeyCount: 42
        )
        panel.provider = fake
        panel.refreshStats()

        let readout = panel.stringsReadout
        for token in ["Sample: on", "4 sample keys", "english", "3 files", "42 keys"] {
            #expect(readout.contains(token), "missing \(token) in: \(readout)")
        }
    }

    @Test @MainActor
    func stringsReadoutDegradesWithoutGameData() {
        let panel = UILabPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeUILabProvider()
        panel.provider = fake
        panel.refreshStats()
        #expect(panel.stringsReadout.contains("no game data"))
    }
}
