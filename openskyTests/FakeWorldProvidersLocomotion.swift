// The player-locomotion half of the world-provider fake (issue #188), in its
// own file so `FakeWorldProviders` stays inside the type-length cap.
//
// The panel that consumes this seam lands with the locomotion gate (#191); the
// fake exists now so the aggregate provider protocol stays satisfiable and the
// registry tests keep compiling.

@testable import opensky

/// The stored half of the fake's locomotion state, kept as one value so the
/// class body above stays inside the type-length cap.
struct FakeLocomotionState {
    var sneaking = false
    var jumpRequests = 0
    var status = LocomotionStatus()
    var forcedGait: LocomotionGait?
    var activeStates: [BehaviorActiveState] = []
    var firstPersonActiveStates: [BehaviorActiveState] = []
    var variables: [LocomotionVariableSnapshot] = []
    var tally: BehaviorTally?
    /// Event names the fake's graph declares. A raise of anything else is
    /// answered false, exactly as a real graph answers it.
    var declaredEvents = Set(LocomotionGraphNames.events)
    var raisedEvents: [String] = []
    var traceClearCount = 0
}

extension FakeWorldProviders {
    /// The inventory model the fake starts with, moved out of the class body
    /// for the same reason.
    static func makeInventoryMenuModel() -> InventoryMenuModel {
        InventoryMenuModel(
            allEntries: [
                InventoryMenuEntry(
                    item: FormID(0x0200), name: "IronSword", count: 1, weight: 9, value: 25,
                    isEquipped: false, family: .weapon
                ),
                InventoryMenuEntry(
                    item: FormID(0x0100), name: "Lockpick", count: 3, weight: 0, value: 5,
                    isEquipped: false, family: .miscellaneous
                )
            ],
            categories: InventoryMenuCategory.engineOrder,
            carriedWeight: 9,
            gold: 42
        )
    }

    var playerLocomotionSnapshot: PlayerLocomotionSnapshot {
        PlayerLocomotionSnapshot(
            rendererAvailable: true,
            walkModeActive: movementMode.isPlayerControlled,
            status: locomotion.status,
            bindings: [
                LocomotionBindingSnapshot(
                    id: "run", label: "Run", key: "Shift (hold)", isActive: false
                ),
                LocomotionBindingSnapshot(
                    id: "sneak", label: "Sneak", key: "C (toggle)", isActive: locomotion.sneaking
                )
            ],
            configuration: movementConfiguration,
            activeStates: locomotion.activeStates,
            firstPersonActiveStates: locomotion.firstPersonActiveStates,
            variables: locomotion.variables,
            forcedGait: locomotion.forcedGait,
            tally: locomotion.tally
        )
    }

    var isSneaking: Bool {
        get { locomotion.sneaking }
        set { locomotion.sneaking = newValue }
    }

    var forcedLocomotionGait: LocomotionGait? {
        get { locomotion.forcedGait }
        set { locomotion.forcedGait = newValue }
    }

    func requestJump() {
        locomotion.jumpRequests += 1
    }

    @discardableResult
    func raiseLocomotionEvent(named name: String) -> Bool {
        locomotion.raisedEvents.append(name)
        return locomotion.declaredEvents.contains(name)
    }

    func clearLocomotionTrace() {
        locomotion.traceClearCount += 1
        locomotion.status.clearMotionTrace()
    }
}

/// The first-person half of the fake's stored state (issue #190).
struct FakeFirstPersonState {
    var armsEnabled = true
    var fovYDegrees = FirstPersonCamera.defaultFOVYDegrees
    var snapshot = FirstPersonSnapshot.unavailable
}

extension FakeWorldProviders {
    var firstPersonSnapshot: FirstPersonSnapshot {
        firstPerson.snapshot
    }

    var firstPersonFOVYDegrees: Float {
        get { firstPerson.fovYDegrees }
        set { firstPerson.fovYDegrees = newValue }
    }

    var firstPersonArmsEnabled: Bool {
        get { firstPerson.armsEnabled }
        set { firstPerson.armsEnabled = newValue }
    }
}

/// The melee half of the fake's stored state (issue #195). Held beside the
/// locomotion state because the Melee section sits under the same destination
/// and both are driven by the same fake in the registry tests.
struct FakeMeleeState {
    var snapshot = MeleeCombatSnapshot.unavailable
    var isWeaponDrawn = false
    var attackRequests = 0
    var traceClearCount = 0
    var lastActionText = "No melee action yet."
}

extension FakeWorldProviders {
    var meleeCombatSnapshot: MeleeCombatSnapshot {
        melee.snapshot
    }

    var isWeaponDrawn: Bool {
        get { melee.isWeaponDrawn }
        set { melee.isWeaponDrawn = newValue }
    }

    @discardableResult
    func requestMeleeAttack() -> String {
        melee.attackRequests += 1
        melee.lastActionText = "Requested one swing."
        return melee.lastActionText
    }

    func clearMeleeTrace() {
        melee.traceClearCount += 1
        melee.lastActionText = "Cleared the hit trace."
    }
}

/// The archery half of the fake's stored state (issue #196). Beside the melee
/// state for the same reason: the Archery section sits under the same
/// destination and the same fake drives both in the registry tests.
struct FakeArcheryState {
    var snapshot = ArcherySnapshot.unavailable
    var spawnRequests = 0
    var despawnRequests = 0
    var stuckClearRequests = 0
    var traceClearCount = 0
    var lastActionText = "No shot taken yet."
}

extension FakeWorldProviders {
    var archerySnapshot: ArcherySnapshot {
        archery.snapshot
    }

    @discardableResult
    func spawnDevProjectile() -> String {
        archery.spawnRequests += 1
        archery.lastActionText = "Fired projectile #\(archery.spawnRequests)."
        return archery.lastActionText
    }

    func despawnProjectiles() {
        archery.despawnRequests += 1
        archery.lastActionText = "Despawned everything in flight."
    }

    func clearStuckProjectiles() {
        archery.stuckClearRequests += 1
        archery.lastActionText = "Pulled every stuck arrow back out."
    }

    func clearProjectileTrace() {
        archery.traceClearCount += 1
        archery.lastActionText = "Cleared the shot trace."
    }
}
