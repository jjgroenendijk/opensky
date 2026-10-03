// The sidebar seam over a synthetic lock: the lock list, selection, forced relock,
// the key override, and the readout text.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
@testable import OpenSkyWorldInterface
import Testing

@MainActor
struct LockControlTests {
    private typealias Locks = LockCoordinatorTests

    @Test func snapshotListsTheLoadedLocks() throws {
        let world = FakeLockWorld()
        world.placed = [Locks.door(level: .adept).interaction]
        let rig = try Locks.coordinator(world: world)
        let snapshot = rig.locks.lockSnapshot
        #expect(snapshot.locks == [LockReadoutRow(
            reference: Locks.door, name: "Fixture Door", difficulty: "Adept",
            key: "Key \(Locks.key)", isLocked: true
        )])
        #expect(LockReadout.text(for: snapshot).contains(
            "  Fixture Door: Adept, key Key \(Locks.key), locked"
        ))
        withExtendedLifetime(rig) {}
    }

    @Test func theSelectedLockUnlocksAndRelocks() throws {
        let world = FakeLockWorld()
        world.placed = [Locks.door(level: .novice).interaction]
        let rig = try Locks.coordinator(world: world)
        let locks = rig.locks
        #expect(locks.setSelectedLockLocked(false) == "No lock selected.")
        locks.selectLock(Locks.door)
        locks.setSelectedLockLocked(false)
        #expect(locks.lockSnapshot.selectedRow?.isLocked == false)
        locks.setSelectedLockLocked(true)
        #expect(locks.lockSnapshot.selectedRow?.isLocked == true)
        withExtendedLifetime(rig) {}
    }

    @Test func theKeyOverrideOpensWithoutTheKey() throws {
        let world = FakeLockWorld()
        let rig = try Locks.coordinator(world: world)
        let locks = rig.locks
        let target = Locks.door(level: .requiresKey)
        #expect(locks.gate(target) != nil)
        locks.setPlayerCarriesEveryKey(true)
        #expect(locks.gate(target) == nil)
        #expect(world.changes > 0)
        withExtendedLifetime(rig) {}
    }

    @Test func outcomeTextNamesPicksAndExperience() {
        let outcome = LockpickingOutcome(
            difficulty: .expert, opened: true, picksBroken: 2,
            experience: 3.25, keyRewarded: false
        )
        #expect(LockReadout.outcomeText(outcome) == "opened Expert, picks broken 2, XP 3.3")
        #expect(LockReadout.outcomeText(nil) == "none")
    }
}
