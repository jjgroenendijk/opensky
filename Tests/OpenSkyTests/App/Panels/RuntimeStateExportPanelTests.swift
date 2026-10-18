// World > Runtime State > Save & Load: the Skyrim export button and its readout.

import AppKit
@testable import OpenSky
import OpenSkySave
import Testing

struct RuntimeStateExportPanelTests {
    @Test @MainActor
    func exportButtonStartsTheExportAndShowsTheReport() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let section = panel.saveSection
        let identifier = section.exportControl.accessibilityIdentifier()
        #expect(identifier == "RuntimeStateExportSkyrimControl")
        let state = FakeRuntimeStateProvider()
        section.provider = state
        #expect(!section.exportControl.isEnabled, "no export provider yet")
        let export = FakeSkyrimExport()
        section.exportProvider = export
        Self.send(section.exportControl)
        #expect(export.starts == 1)
        section.refreshReadout()
        #expect(section.readout.contains("Export: OpenSky Export 1.ess"))
        #expect(section.readout.contains("3 written, 1 left out"))
        withExtendedLifetime(state) {}
    }

    @MainActor
    private static func send(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }
}

@MainActor
private final class FakeSkyrimExport: SkyrimExportControlProviding {
    var starts = 0
    var lastSkyrimExport = SkyrimExportOutcome.none

    func startSkyrimExport() {
        starts += 1
        lastSkyrimExport = .exported("OpenSky Export 1.ess", ["3 written, 1 left out"])
    }
}
