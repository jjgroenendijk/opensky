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
            walkModeActive: movementMode == .walk,
            status: locomotion.status,
            bindings: [
                LocomotionBindingSnapshot(
                    id: "sneak", label: "Sneak", key: "C (toggle)", isActive: locomotion.sneaking
                )
            ],
            configuration: movementConfiguration
        )
    }

    var isSneaking: Bool {
        get { locomotion.sneaking }
        set { locomotion.sneaking = newValue }
    }

    func requestJump() {
        locomotion.jumpRequests += 1
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
