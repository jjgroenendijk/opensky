// The lock and trap half of the world-provider fake: one locked door and one
// pressure plate whose state the controls flip.

@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory
import OpenSkyInventoryInterface
@testable import OpenSkyPhysics
@testable import OpenSkyWorld

struct FakeLockTrapState {
    var doorLocked = true
    var selectedLock: FormID?
    var carriesEveryKey = false
    var picked = 0
    var selectedTrap: ReferenceKey?
    var fired = 0
    var disarmed = false
    var lastLock = LockActionOutcome.idle
    var lastTrap = "No trap action yet."
    var objectAnimationEnabled = true
    var objectEvents: [String] = []
    var doorOpen = false
}

extension FakeWorldProviders {
    static let lockedDoor = FormID(0x0900)
    static let plate = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0A00)

    var lockSnapshot: LockControlSnapshot {
        LockControlSnapshot(
            isAvailable: true,
            locks: [LockReadoutRow(
                reference: Self.lockedDoor, name: "Cellar Door", difficulty: "Adept",
                key: "Cellar Key", isLocked: locksTraps.doorLocked
            )],
            selected: locksTraps.selectedLock,
            carriesEveryKey: locksTraps.carriesEveryKey,
            lockpicks: 3,
            lastOutcome: nil,
            lastAction: locksTraps.lastLock
        )
    }

    func selectLock(_ reference: FormID?) {
        locksTraps.selectedLock = reference
    }

    func setSelectedLockLocked(_ locked: Bool) -> LockActionOutcome {
        guard locksTraps.selectedLock == Self.lockedDoor else { return .noSelection }
        locksTraps.doorLocked = locked
        locksTraps.lastLock = .lockChanged(name: "Cellar Door", locked: locked)
        return locksTraps.lastLock
    }

    func setPlayerCarriesEveryKey(_ enabled: Bool) {
        locksTraps.carriesEveryKey = enabled
    }

    func pickSelectedLock() -> LockActionOutcome {
        locksTraps.picked += 1
        return .picking(name: "Cellar Door", difficulty: .adept)
    }

    var trapSnapshot: TrapControlSnapshot {
        let state = locksTraps.disarmed ? "Disarmed" : "Ready"
        return TrapControlSnapshot(
            isAvailable: true,
            triggers: [TrapTriggerRow(
                key: Self.plate, name: "Plate", scripts: ["pressureplate: \(state)"],
                occupants: 0, isEnabled: true
            )],
            selected: locksTraps.selectedTrap,
            chain: [],
            hazards: [],
            hazardHits: locksTraps.fired,
            lastText: locksTraps.lastTrap
        )
    }

    func selectTrap(_ key: ReferenceKey?) {
        locksTraps.selectedTrap = key
    }

    func fireSelectedTrap() -> String {
        locksTraps.fired += 1
        locksTraps.lastTrap = "Stepped into and out of Plate."
        return locksTraps.lastTrap
    }

    func disarmSelectedTrap() -> String {
        locksTraps.disarmed = true
        locksTraps.lastTrap = "Activated Plate: 1 script events."
        return locksTraps.lastTrap
    }
}

extension FakeWorldProviders {
    var objectAnimationEnabled: Bool {
        get { locksTraps.objectAnimationEnabled }
        set { locksTraps.objectAnimationEnabled = newValue }
    }

    var objectAnimationRows: [ObjectAnimationRow] {
        [ObjectAnimationRow(
            reference: 0x0B00, project: "meshes\\traps\\blade\\blade.hkx",
            events: ["Trip", "Reset"], activeState: "Idle"
        )]
    }

    func sendObjectAnimationEvent(_ event: String, to reference: UInt32) -> Bool {
        guard reference == 0x0B00, objectAnimationRows[0].events.contains(event) else {
            return false
        }
        locksTraps.objectEvents.append(event)
        return true
    }
}

extension FakeWorldProviders {
    var sequenceDoorRows: [SequenceDoorRow] {
        [SequenceDoorRow(
            reference: 0x0C00, modelPath: "Clutter\\Gate\\Gate01.nif",
            phase: locksTraps.doorOpen ? .open : .closed
        )]
    }

    func setSequenceDoorOpen(_ open: Bool, reference: UInt32) -> Bool {
        guard reference == 0x0C00 else { return false }
        locksTraps.doorOpen = open
        return true
    }
}
