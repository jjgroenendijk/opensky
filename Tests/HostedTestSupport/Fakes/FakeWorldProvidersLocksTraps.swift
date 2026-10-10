// The lock and trap half of the world-provider fake: one locked door and one
// pressure plate whose state the controls flip.

@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory
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
    var lastLock = "No lock action yet."
    var lastTrap = "No trap action yet."
    var objectAnimationEnabled = true
    var objectEvents: [String] = []
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
            lastText: locksTraps.lastLock
        )
    }

    func selectLock(_ reference: FormID?) {
        locksTraps.selectedLock = reference
    }

    func setSelectedLockLocked(_ locked: Bool) -> String {
        guard locksTraps.selectedLock == Self.lockedDoor else { return "No lock selected." }
        locksTraps.doorLocked = locked
        locksTraps.lastLock = locked ? "Locked Cellar Door." : "Unlocked Cellar Door."
        return locksTraps.lastLock
    }

    func setPlayerCarriesEveryKey(_ enabled: Bool) {
        locksTraps.carriesEveryKey = enabled
    }

    func pickSelectedLock() -> String {
        locksTraps.picked += 1
        return "Picking Cellar Door (Adept)."
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
