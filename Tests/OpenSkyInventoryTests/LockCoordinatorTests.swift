// Synthetic locks: the use-key gate, a carried key, the prompt, a forced unlock,
// and a full lockpicking session through the coordinator.

import FeaturesTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

/// Records skill uses and answers perks from a table.
@MainActor
final class FakeLockWorld: LockWorld {
    var lockpickingSkill: Float = 0
    var perks: [PerkEntryPoint: Float] = [:]
    private(set) var uses: [SkillUseEvent] = []
    private(set) var changes = 0

    func perkValue(
        _ value: Float, at entryPoint: PerkEntryPoint, lock: ReferenceKey, level: UInt8
    ) -> Float {
        perks[entryPoint] ?? value
    }

    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        uses.append(use)
        return use.amount
    }

    var placed: [PlacedInteraction] = []

    func lockStateChanged() {
        changes += 1
    }

    func lockables() -> [PlacedInteraction] {
        placed
    }

    func itemName(_ item: FormID) -> String {
        "Key \(item)"
    }
}

@MainActor
struct LockCoordinatorTests {
    private typealias Fixture = InventoryBaselineFixture
    private typealias Items = WorldItemRuntimeTests

    static let door = FormID(0x0000_0900)
    static let doorBase = FormID(0x0000_5100)
    static let key = FormID(0x0000_5200)

    static func door(level: LockLevel, key: FormID? = key) -> InteractionTarget {
        let interaction = PlacedInteraction(
            reference: door,
            base: doorBase,
            position: .zero,
            name: "Fixture Door",
            action: .open,
            actionLabel: InteractionAction.open.defaultLabel,
            sounds: nil,
            lock: LockData(level: level, key: key)
        )
        return InteractionTarget(interaction: interaction, hitPosition: .zero, distance: 1)
    }

    /// Holds the harness, because the item runtime keeps its references weakly.
    struct Rig {
        let locks: LockCoordinator
        let harness: WorldItemRuntimeTests.Harness
    }

    static func coordinator(
        picks: Int32 = 0,
        world: FakeLockWorld? = nil
    ) throws -> Rig {
        let harness = try Items.harness(entries: [Items.entry(formID: door, base: doorBase)])
        let locks = LockCoordinator()
        locks.wire(items: harness.runtime)
        locks.lockpickItem = Fixture.lockpick
        locks.world = world
        if picks > 0 {
            _ = try harness.runtime.inventory.add(Fixture.lockpick, count: picks, to: .player)
        }
        return Rig(locks: locks, harness: harness)
    }

    @Test func aLockedDoorIsRefusedAndLabelledUnlock() throws {
        let rig = try Self.coordinator()
        let locks = rig.locks
        let target = Self.door(level: .adept)
        #expect(locks.gate(target) == .locked(level: 50, key: Self.key))
        let labelled = locks.labelled(target.interaction)
        #expect(labelled.actionLabel == LockCore.unlockLabel)
        #expect(labelled.name == "Fixture Door (Adept)")
        withExtendedLifetime(rig) {}
    }

    @Test func aCarriedKeyUnlocksAndTheDoorStaysOpen() throws {
        let rig = try Self.coordinator()
        let locks = rig.locks
        let harness = rig.harness
        _ = try harness.runtime.inventory.add(Self.key, count: 1, to: .player)
        let target = Self.door(level: .requiresKey)
        #expect(locks.gate(target) == nil)
        let state = locks.lock(of: target.interaction)?.state
        #expect(state?.isLocked == false)
        #expect(state?.level == 255)
        _ = try harness.runtime.inventory.remove(Self.key, count: 1, from: .player)
        #expect(locks.gate(target) == nil)
        withExtendedLifetime(rig) {}
    }

    @Test func aWrongKeyDoesNotOpen() throws {
        let rig = try Self.coordinator()
        let locks = rig.locks
        let harness = rig.harness
        _ = try harness.runtime.inventory.add(Fixture.gold, count: 1, to: .player)
        #expect(locks.gate(Self.door(level: .novice)) != nil)
        withExtendedLifetime(rig) {}
    }

    @Test func aDoorWithoutXLOCPassesUntouched() throws {
        let rig = try Self.coordinator()
        let locks = rig.locks
        let harness = rig.harness
        let open = Items.interaction(reference: Self.door, base: Self.doorBase, action: .open)
        let target = InteractionTarget(interaction: open, hitPosition: .zero, distance: 1)
        #expect(locks.gate(target) == nil)
        #expect(locks.labelled(open) == open)
        let key = Items.entry(formID: Self.door, base: Self.doorBase).key
        #expect(harness.store.component(ReferenceLockState.self, for: key) == nil)
        withExtendedLifetime(rig) {}
    }

    @Test func setLockedRelocksWithTheSameLevelAndKey() throws {
        let rig = try Self.coordinator()
        let locks = rig.locks
        let target = Self.door(level: .expert)
        locks.setLocked(target.interaction, locked: false)
        #expect(locks.gate(target) == nil)
        locks.setLocked(target.interaction, locked: true)
        #expect(locks.gate(target) == .locked(level: 75, key: Self.key))
        withExtendedLifetime(rig) {}
    }

    @Test func pickingNeedsALockpickAndAPickableLock() throws {
        let rig = try Self.coordinator()
        let locks = rig.locks
        #expect(throws: LockpickingRefusal.noLockpicks) {
            try locks.beginLockpicking(Self.door(level: .novice))
        }
        let stocked = try Self.coordinator(picks: 2)
        #expect(throws: LockpickingRefusal.requiresKey) {
            try stocked.locks.beginLockpicking(Self.door(level: .requiresKey))
        }
        withExtendedLifetime((rig, stocked)) {}
    }

    @Test func anOpenedLockUnlocksAndReportsSkillUse() throws {
        let world = FakeLockWorld()
        let rig = try Self.coordinator(picks: 2, world: world)
        let locks = rig.locks
        let target = Self.door(level: .novice)
        try locks.beginLockpicking(target)
        let center = try #require(locks.session?.sweetSpotCenter)
        let start = try #require(locks.session?.pickAngle)
        locks.stepLockpicking(
            0.1,
            input: LockpickingInput(pickDelta: center - start, turning: false)
        )
        var events: [LockpickingEvent] = []
        for _ in 0 ..< 20 where events.isEmpty {
            events = locks.stepLockpicking(
                0.1,
                input: LockpickingInput(pickDelta: 0, turning: true)
            )
        }
        #expect(events == [.opened])
        #expect(locks.gate(target) == nil)
        #expect(world.uses.map(\.action) == [.lockpick])
        #expect(world.uses.first?.amount == 2)
        #expect(locks.lastOutcome?.opened == true)
        locks.closeLockpicking()
        #expect(locks.session == nil)
        withExtendedLifetime(rig) {}
    }

    @Test func aBrokenPickLeavesTheInventory() throws {
        let world = FakeLockWorld()
        let rig = try Self.coordinator(picks: 1, world: world)
        let locks = rig.locks
        let harness = rig.harness
        try locks.beginLockpicking(Self.door(level: .master))
        let center = try #require(locks.session?.sweetSpotCenter)
        let start = try #require(locks.session?.pickAngle)
        let away: Float = center > 0 ? -90 - start : 90 - start
        locks.stepLockpicking(0.01, input: LockpickingInput(pickDelta: away, turning: false))
        var events: [LockpickingEvent] = []
        for _ in 0 ..< 200 where events.isEmpty {
            events = locks.stepLockpicking(
                0.05,
                input: LockpickingInput(pickDelta: 0, turning: true)
            )
        }
        #expect(events == [.pickBroke, .outOfPicks])
        #expect(harness.runtime.inventory.count(of: Fixture.lockpick, in: .player) == 0)
        #expect(world.uses.first?.amount == 0.25)
        #expect(locks.lastOutcome?.opened == false)
        #expect(locks.lastOutcome?.picksBroken == 1)
        withExtendedLifetime(rig) {}
    }

    @Test func waxKeyHandsOverTheKeyOnSuccess() throws {
        let world = FakeLockWorld()
        world.perks[LockpickingEntryPoint.keyReward] = 100
        let rig = try Self.coordinator(picks: 1, world: world)
        let locks = rig.locks
        let harness = rig.harness
        try locks.beginLockpicking(Self.door(level: .novice))
        let center = try #require(locks.session?.sweetSpotCenter)
        let start = try #require(locks.session?.pickAngle)
        locks.stepLockpicking(
            0.1,
            input: LockpickingInput(pickDelta: center - start, turning: false)
        )
        for _ in 0 ..< 20 {
            locks.stepLockpicking(0.1, input: LockpickingInput(pickDelta: 0, turning: true))
        }
        #expect(harness.runtime.inventory.count(of: Self.key, in: .player) == 1)
        #expect(locks.lastOutcome?.keyRewarded == true)
        withExtendedLifetime(rig) {}
    }
}
