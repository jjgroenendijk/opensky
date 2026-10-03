// World > Inventory & Equipment > Locks and World > World > Traps with the
// provider fake: pinned ids, visible frames, and each control driving the fake.

import AppKit
@testable import OpenSky
@testable import OpenSkyInventory
@testable import OpenSkyPhysics
import Testing

@MainActor
struct LockTrapPanelTests {
    private func tap(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    private func lockSection(_ provider: FakeWorldProviders) -> LockSection {
        let panel = InventoryEquipmentPanelViewController()
        panel.lockProvider = provider
        panel.loadViewIfNeeded()
        return panel.lockSection
    }

    private func trapPanel(_ provider: FakeWorldProviders) -> WorldPanelViewController {
        let panel = WorldPanelViewController()
        panel.loadViewIfNeeded()
        panel.trapProvider = provider
        return panel
    }

    @Test func accessibilityIdentifiersArePinned() {
        let provider = FakeWorldProviders()
        let locks = lockSection(provider)
        let traps = trapPanel(provider).trapSection
        #expect(locks.sectionIdentifier == "locks")
        #expect(traps.sectionIdentifier == "traps")
        let controls: [(NSView, String)] = [
            (locks.lockControl, "LockSelectControl"),
            (locks.unlockControl, "LockUnlockControl"),
            (locks.relockControl, "LockRelockControl"),
            (locks.pickControl, "LockPickControl"),
            (locks.carriesKeyControl, "LockCarriesKeyControl"),
            (traps.trapControl, "TrapSelectControl"),
            (traps.fireControl, "TrapFireControl"),
            (traps.disarmControl, "TrapDisarmControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }
    }

    @Test func trapControlsHaveVisibleFrames() throws {
        let panel = trapPanel(FakeWorldProviders())
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 900)
        panel.view.layoutSubtreeIfNeeded()
        let section = panel.trapSection
        for control in [section.trapControl, section.fireControl, section.disarmControl] {
            let name = control.accessibilityIdentifier()
            #expect(!control.isHidden, "\(name) hidden")
            #expect(control.frame.height > 0, "\(name) frame=\(control.frame)")
            let documentFrame = control.convert(control.bounds, to: scrollView.documentView)
            #expect(scrollView.documentView?.bounds.intersects(documentFrame) == true)
        }
    }

    @Test func lockControlsUnlockRelockAndPick() {
        let provider = FakeWorldProviders()
        let section = lockSection(provider)
        section.refreshReadout()
        #expect(section.lockControl.itemTitles == ["Cellar Door (00000900)"])
        #expect(section.readout.contains("Cellar Door: Adept, key Cellar Key, locked"))
        tap(section.unlockControl)
        #expect(provider.locksTraps.selectedLock == FakeWorldProviders.lockedDoor)
        #expect(section.readout.contains("Cellar Door: Adept, key Cellar Key, open"))
        tap(section.relockControl)
        #expect(section.readout.contains("Last: Locked Cellar Door."))
        tap(section.pickControl)
        #expect(provider.locksTraps.picked == 1)
        section.carriesKeyControl.state = .on
        tap(section.carriesKeyControl)
        #expect(provider.locksTraps.carriesEveryKey)
        #expect(section.readout.contains("Carries every key: yes"))
    }

    @Test func trapControlsFireAndDisarm() {
        let provider = FakeWorldProviders()
        let section = trapPanel(provider).trapSection
        section.refreshReadout()
        #expect(section.trapControl.itemTitles == ["Plate"])
        #expect(section.readout.contains("  Plate: pressureplate: Ready, inside 0"))
        tap(section.fireControl)
        #expect(provider.locksTraps.selectedTrap == FakeWorldProviders.plate)
        #expect(provider.locksTraps.fired == 1)
        #expect(section.readout.contains("Last: Stepped into and out of Plate."))
        tap(section.disarmControl)
        #expect(section.readout.contains("Selected: Plate: pressureplate: Disarmed, inside 0"))
    }
}
