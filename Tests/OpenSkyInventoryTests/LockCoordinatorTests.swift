// Synthetic locks: the use-key gate, a carried key, the prompt, a forced unlock,
// and a full lockpicking session through the coordinator.

import Foundation
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

/// Records skill uses and answers perks from a table. Notices and prompt refreshes
/// come back as commands, so the fake does not record them.
@MainActor
final class FakeLockWorld: LockWorld {
    var lockpickingSkill: Float = 0
    var playerLevel = 1
    var perks: [PerkEntryPoint: Float] = [:]
    var filter: Float = 0
    private(set) var filtered: [ReferenceKey] = []
    private(set) var uses: [SkillUseEvent] = []

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

    func lockables() -> [PlacedInteraction] {
        placed
    }

    func itemName(_ item: FormID) -> String {
        "Key \(item)"
    }

    func activationFilter(of reference: ReferenceKey) -> Float {
        filtered.append(reference)
        return filter
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
        world: FakeLockWorld = FakeLockWorld()
    ) throws -> Rig {
        let harness = try Items.harness(entries: [Items.entry(formID: door, base: doorBase)])
        let locks = LockCoordinator(world: world)
        locks.wire(items: harness.runtime)
        locks.lockpickItem = Fixture.lockpick
        if picks > 0 {
            _ = try harness.runtime.inventory.add(Fixture.lockpick, count: picks, to: .player)
        }
        return Rig(locks: locks, harness: harness)
    }

    @Test func aLockedDoorIsRefusedAndLabelledUnlock() throws {
        let rig = try Self.coordinator()
        let locks = rig.locks
        let target = Self.door(level: .adept)
        #expect(locks.gate(target).value == .locked(level: 50, key: Self.key))
        let labelled = locks.labelled(target.interaction)
        #expect(labelled.actionLabel == LockTexts.vanilla.unlock)
        #expect(labelled.name == "Fixture Door (Adept)")
        withExtendedLifetime(rig) {}
    }

    @Test func aFilterActivationPerkBlocksBeforeTheLock() throws {
        let world = FakeLockWorld()
        let rig = try Self.coordinator(world: world)
        world.filter = 1
        #expect(rig.locks.gate(Self.door(level: .adept)).value == .filteredByPerk)
        #expect(world.filtered.count == 1)
        world.filter = 0
        let refusal = rig.locks.gate(Self.door(level: .adept)).value
        #expect(refusal == .locked(level: 50, key: Self.key))
        withExtendedLifetime(rig) {}
    }

    @Test func aCarriedKeyUnlocksAndTheDoorStaysOpen() throws {
        let world = FakeLockWorld()
        let rig = try Self.coordinator(world: world)
        let locks = rig.locks
        let harness = rig.harness
        _ = try harness.runtime.inventory.add(Self.key, count: 1, to: .player)
        let target = Self.door(level: .requiresKey)
        #expect(locks.gate(target) == InventoryResult(nil, commands: [
            .refreshInteractionTarget, .showNotice("Unlocked with Key \(Self.key).")
        ]))
        let state = locks.lock(of: target.interaction)?.state
        #expect(state?.isLocked == false)
        #expect(state?.level == 255)
        _ = try harness.runtime.inventory.remove(Self.key, count: 1, from: .player)
        #expect(locks.gate(target).value == nil)
        withExtendedLifetime(rig) {}
    }

    @Test func aWrongKeyDoesNotOpen() throws {
        let rig = try Self.coordinator()
        let locks = rig.locks
        let harness = rig.harness
        _ = try harness.runtime.inventory.add(Fixture.gold, count: 1, to: .player)
        #expect(locks.gate(Self.door(level: .novice)).value != nil)
        withExtendedLifetime(rig) {}
    }

    @Test func aDoorWithoutXLOCPassesUntouched() throws {
        let rig = try Self.coordinator()
        let locks = rig.locks
        let harness = rig.harness
        let open = Items.interaction(reference: Self.door, base: Self.doorBase, action: .open)
        let target = InteractionTarget(interaction: open, hitPosition: .zero, distance: 1)
        #expect(locks.gate(target).value == nil)
        #expect(locks.labelled(open) == open)
        let key = Items.entry(formID: Self.door, base: Self.doorBase).key
        #expect(harness.store.component(ReferenceLockState.self, for: key) == nil)
        withExtendedLifetime(rig) {}
    }

    @Test func setLockedRelocksWithTheSameLevelAndKey() throws {
        let rig = try Self.coordinator()
        let locks = rig.locks
        let target = Self.door(level: .expert)
        #expect(locks.setLocked(target.interaction, locked: false).commands == [
            .refreshInteractionTarget
        ])
        #expect(locks.gate(target).value == nil)
        _ = locks.setLocked(target.interaction, locked: true)
        #expect(locks.gate(target).value == .locked(level: 75, key: Self.key))
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
        let recorder = StoryEventRecorder()
        locks.storyEvents = recorder
        let target = Self.door(level: .novice)
        try locks.beginLockpicking(target)
        let center = try #require(locks.session?.sweetSpotCenter)
        let start = try #require(locks.session?.pickAngle)
        _ = locks.stepLockpicking(
            0.1,
            input: LockpickingInput(pickDelta: center - start, turning: false)
        )
        var step = InventoryResult<[LockpickingEvent]>([])
        for _ in 0 ..< 20 where step.value.isEmpty {
            step = locks.stepLockpicking(
                0.1,
                input: LockpickingInput(pickDelta: 0, turning: true)
            )
        }
        #expect(step == InventoryResult([.opened], commands: [.refreshInteractionTarget]))
        #expect(locks.gate(target).value == nil)
        #expect(world.uses.map(\.action) == [.lockpick])
        #expect(world.uses.first?.amount == 2)
        #expect(locks.lastOutcome?.opened == true)
        #expect(recorder.events("LOCK").map(\.actor1) == [.player])
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
        _ = locks.stepLockpicking(0.01, input: LockpickingInput(pickDelta: away, turning: false))
        var step = InventoryResult<[LockpickingEvent]>([])
        for _ in 0 ..< 200 where step.value.isEmpty {
            step = locks.stepLockpicking(
                0.05,
                input: LockpickingInput(pickDelta: 0, turning: true)
            )
        }
        #expect(step == InventoryResult(
            [.pickBroke, .outOfPicks], commands: [.showNotice(LockTexts.vanilla.outOfLockpicks)]
        ))
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
        _ = locks.stepLockpicking(
            0.1,
            input: LockpickingInput(pickDelta: center - start, turning: false)
        )
        for _ in 0 ..< 20 {
            _ = locks.stepLockpicking(0.1, input: LockpickingInput(pickDelta: 0, turning: true))
        }
        #expect(harness.runtime.inventory.count(of: Self.key, in: .player) == 1)
        #expect(locks.lastOutcome?.keyRewarded == true)
        withExtendedLifetime(rig) {}
    }
}
