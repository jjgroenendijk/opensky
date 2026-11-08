// Leveled locks (`XLOC` flag 0x04): the band they show at a player level, and the
// coordinator using that band while the stored level stays authored.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
@testable import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct LeveledLockTests {
    @Test(arguments: [
        (UInt8(1), 1, UInt8(1)), (1, 10, 1), (1, 11, 25), (1, 25, 50), (1, 31, 75),
        (25, 21, 75), (75, 11, 100), (100, 50, 100), (255, 50, 255), (0, 5, 0)
    ])
    func aLeveledLockRisesOneBandPerTenPlayerLevels(authored: UInt8, level: Int, shown: UInt8) {
        #expect(LockCore.leveledLevel(authored: authored, playerLevel: level) == shown)
    }

    static func leveledDoor(_ level: LockLevel) -> InteractionTarget {
        let interaction = PlacedInteraction(
            reference: LockCoordinatorTests.door,
            base: LockCoordinatorTests.doorBase,
            position: .zero,
            name: "Fixture Door",
            action: .open,
            actionLabel: InteractionAction.open.defaultLabel,
            sounds: nil,
            lock: LockData(level: level, key: nil, flags: 0x04)
        )
        return InteractionTarget(interaction: interaction, hitPosition: .zero, distance: 1)
    }

    @Test func theGateAndThePromptUseTheShownBand() throws {
        let world = FakeLockWorld()
        world.playerLevel = 22
        let rig = try LockCoordinatorTests.coordinator(picks: 1, world: world)
        let target = Self.leveledDoor(.novice)
        #expect(rig.locks.gate(target).value == .locked(level: 50, key: nil))
        #expect(rig.locks.labelled(target.interaction).name == "Fixture Door (Adept)")
        let lock = try #require(rig.locks.lock(of: target.interaction))
        #expect(lock.isLeveled && lock.state.level == 1 && lock.shownLevel == 50)
        try rig.locks.beginLockpicking(target)
        #expect(rig.locks.session?.parameters.difficulty == .adept)
        world.playerLevel = 1
        #expect(rig.locks.labelled(target.interaction).name == "Fixture Door (Novice)")
        withExtendedLifetime(rig) {}
    }

    @Test func aLevelSetByScriptNoLongerScales() throws {
        let world = FakeLockWorld()
        world.playerLevel = 40
        let rig = try LockCoordinatorTests.coordinator(world: world)
        let target = Self.leveledDoor(.novice)
        let entry = try #require(
            rig.harness.runtime.references?.referenceEntry(formID: target.interaction.reference)
        )
        rig.harness.runtime.store.set(
            ReferenceLockState(isLocked: true, level: 25, key: nil), for: entry.key, in: nil
        )
        let lock = try #require(rig.locks.lock(of: target.interaction))
        #expect(!lock.isLeveled && lock.shownLevel == 25)
        withExtendedLifetime(rig) {}
    }
}
