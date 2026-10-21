// Soul trap: the soul an actor's level and keywords give, the smallest gem that holds
// it, and a death under the effect filling the player's gem. Rules: UESP "Skyrim:Souls"
// and "Skyrim:Soul Trap (effect)", cited at `SoulTrap`.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import Testing

@MainActor
struct SoulTrapTests {
    private typealias Gems = SoulGemFixture
    private static let victim = ReferenceKey.plugin(name: "base.esm", objectID: 0x0900)

    private static func candidates(_ items: [FormID]) throws -> [SoulGemCandidate] {
        let store = try Gems.resolver().items
        return try items.map { item in
            try SoulGemCandidate(
                item: item,
                gem: #require(store.soulGems[item.rawValue]),
                copy: .plain
            )
        }
    }

    @Test func aCreaturesLevelSetsItsSoulAndAnNPCsIsBlack() {
        let settings = SoulTrapSettings.vanilla
        #expect(SoulTrap.soul(level: 3, isNPC: false, settings: settings).size == .petty)
        #expect(SoulTrap.soul(level: 4, isNPC: false, settings: settings).size == .lesser)
        #expect(SoulTrap.soul(level: 27, isNPC: false, settings: settings).size == .common)
        #expect(SoulTrap.soul(level: 38, isNPC: false, settings: settings).size == .grand)
        #expect(SoulTrap.soul(level: 1, isNPC: true, settings: settings)
            == TrappedSoul(size: .grand, isBlack: true))
    }

    @Test func theSmallestEmptyGemThatHoldsTheSoulIsChosen() throws {
        let all = try Self.candidates([Gems.black, Gems.grand, Gems.common, Gems.petty])
        let lesser = TrappedSoul(size: .lesser, isBlack: false)
        #expect(SoulTrap.gem(for: lesser, among: all)?.item == Gems.common)
        let grand = TrappedSoul(size: .grand, isBlack: false)
        #expect(SoulTrap.gem(for: grand, among: all)?.item == Gems.grand)
        let black = TrappedSoul(size: .grand, isBlack: true)
        #expect(SoulTrap.gem(for: black, among: all)?.item == Gems.black)
        let whiteOnly = try Self.candidates([Gems.grand])
        let filled = try Self.candidates([Gems.grandFilled])
        #expect(SoulTrap.gem(for: black, among: whiteOnly) == nil)
        #expect(SoulTrap.gem(for: grand, among: filled) == nil)
    }

    private struct Session {
        let coordinator: MagicCoordinator
        let world: FakeMagicWorld
        let inventory: FakeInventory
    }

    private func session(_ gems: [FormID]) throws -> Session {
        let world = FakeMagicWorld()
        let inventory = try FakeInventory(baselines: Gems.resolver())
        for gem in gems {
            try inventory.add(gem, count: 1, to: .player)
        }
        world.inventory = inventory
        world.holders[Self.victim] = ActorValueHolder(
            key: Self.victim, subject: .actor(base: FormID(0x0F01)), cell: nil
        )
        let coordinator = MagicCoordinator(world: world)
        let file = try ActiveEffectFixture.plugin(
            records: ActiveEffectFixture.effectRecords + ActiveEffectFixture.archetypeRecords
        )
        coordinator.wireEffects(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)]),
            pluginName: ActiveEffectFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        let holder = try #require(world.holders[Self.victim])
        coordinator.withEffects { runtime in
            runtime.apply(
                [MagicItemEffect(
                    effect: FormID(ActiveEffectFixture.Archetype.soulTrap), magnitude: 0, area: 0,
                    duration: 60, conditions: ConditionList()
                )],
                fromPlugin: ActiveEffectFixture.pluginName,
                source: ActiveEffectSource(
                    kind: .spell,
                    record: .plugin(name: "base.esm", objectID: 0x600)
                ),
                caster: .player,
                on: holder
            )
        }
        return Session(coordinator: coordinator, world: world, inventory: inventory)
    }

    /// A level 1 creature's petty soul goes into the petty gem, which keeps it per copy.
    @Test func aDeathUnderTheEffectFillsTheSmallestGem() throws {
        let trap = try session([Gems.common, Gems.petty])
        let outcome = trap.coordinator.noteDeath(of: Self.victim)
        #expect(outcome == .trapped(TrappedSoul(size: .petty, isBlack: false), gem: Gems.petty))
        #expect(trap.inventory.copies(of: Gems.petty, in: .player) == [ItemCopy(soul: 1)])
        #expect(trap.inventory.copies(of: Gems.common, in: .player) == [.plain])
        #expect(trap.world.notifications == ["Soul captured!"])
    }

    /// A black gem links its filled record, so the trap swaps the item as the game does.
    @Test func anNPCsSoulFillsABlackGemAndSwapsItsRecord() throws {
        let trap = try session([Gems.grand, Gems.black])
        trap.world.npcs = [Self.victim]
        trap.coordinator.noteDeath(of: Self.victim)
        #expect(trap.inventory.count(of: Gems.black, in: .player) == 0)
        #expect(trap.inventory.count(of: Gems.blackFilled, in: .player) == 1)
        #expect(trap.inventory.count(of: Gems.grand, in: .player) == 1)
    }

    @Test func noGemLargeEnoughFillsNothing() throws {
        let trap = try session([Gems.grand])
        trap.world.npcs = [Self.victim]
        #expect(trap.coordinator.noteDeath(of: Self.victim)
            == .noGem(TrappedSoul(size: .grand, isBlack: true)))
        #expect(trap.world.notifications == ["No soul gem large enough"])
        #expect(trap.coordinator.noteDeath(of: .plugin(name: "base.esm", objectID: 0x0901)) == nil)
    }
}
