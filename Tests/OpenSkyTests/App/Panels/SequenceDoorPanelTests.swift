// World > World > Animated Doors with the provider fake: pinned ids and the open and
// close buttons driving the fake.

import AppKit
@testable import OpenSky
import Testing

@MainActor
struct SequenceDoorPanelTests {
    private func section(_ provider: FakeWorldProviders) -> SequenceDoorSection {
        let panel = WorldPanelViewController()
        panel.loadViewIfNeeded()
        panel.sequenceDoorProvider = provider
        return panel.sequenceDoorSection
    }

    private func tap(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    @Test func accessibilityIdentifiersArePinned() {
        let doors = section(FakeWorldProviders())
        #expect(doors.sectionIdentifier == "sequenceDoors")
        #expect(doors.doorControl.accessibilityIdentifier() == "SequenceDoorDoorControl")
        #expect(doors.openControl.accessibilityIdentifier() == "SequenceDoorOpenControl")
        #expect(doors.closeControl.accessibilityIdentifier() == "SequenceDoorCloseControl")
    }

    @Test func openAndCloseDriveTheDoor() {
        let provider = FakeWorldProviders()
        let doors = section(provider)
        doors.refreshReadout()
        #expect(doors.doorControl.itemTitles == ["00000C00 Gate01.nif"])
        #expect(doors.readout.contains("State: closed"))
        tap(doors.openControl)
        #expect(provider.locksTraps.doorOpen)
        #expect(doors.readout.contains("State: open"))
        #expect(doors.readout.contains("Last: Opened 00000C00"))
        tap(doors.closeControl)
        #expect(!provider.locksTraps.doorOpen)
        #expect(doors.readout.contains("State: closed"))
    }
}
