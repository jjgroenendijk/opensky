// World > World > Worldspace with the provider fake: pinned ids, the readout, and
// the Go button driving the fake.

import AppKit
@testable import OpenSky
@testable import OpenSkyWorld
import Testing

@MainActor
struct WorldspacePanelTests {
    private func section(_ provider: FakeWorldProviders) -> WorldspaceSection {
        let panel = WorldPanelViewController()
        panel.loadViewIfNeeded()
        panel.worldspaceProvider = provider
        return panel.worldspaceSection
    }

    private func tap(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    @Test func accessibilityIdentifiersArePinned() {
        let worldspace = section(FakeWorldProviders())
        #expect(worldspace.sectionIdentifier == "worldspace")
        #expect(worldspace.worldspaceControl.accessibilityIdentifier() == "WorldspacePickControl")
        #expect(worldspace.xControl.accessibilityIdentifier() == "WorldspaceXControl")
        #expect(worldspace.yControl.accessibilityIdentifier() == "WorldspaceYControl")
        #expect(worldspace.goControl.accessibilityIdentifier() == "WorldspaceGoControl")
    }

    @Test func goMovesToTheChosenCell() {
        let provider = FakeWorldProviders()
        let worldspace = section(provider)
        worldspace.refreshReadout()
        #expect(worldspace.readout.contains("Worldspace: Tamriel"))
        #expect(worldspace.readout.contains("Cell: 6, -2"))
        #expect(worldspace.worldspaceControl.titleOfSelectedItem == "Tamriel")
        worldspace.worldspaceControl.selectItem(withTitle: "DLC2SolstheimWorld")
        worldspace.xControl.stringValue = "7"
        worldspace.yControl.stringValue = " 8"
        tap(worldspace.goControl)
        #expect(provider.menuCalls.calls.last == "worldspace.go(DLC2SolstheimWorld, 7, 8)")
        #expect(worldspace.readout.contains("Last: DLC2SolstheimWorld 7, 8"))
    }

    @Test func aBadNumberDoesNotMove() {
        let provider = FakeWorldProviders()
        let worldspace = section(provider)
        worldspace.xControl.stringValue = "7.5"
        worldspace.yControl.stringValue = "8"
        tap(worldspace.goControl)
        #expect(!provider.menuCalls.calls.contains { $0.hasPrefix("worldspace.go") })
        #expect(worldspace.readout.contains("Last: X and Y must be whole numbers"))
    }
}
