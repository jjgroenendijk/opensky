// Summon Creature and Reanimate over synthetic MGEF records: the limit entry point 68
// sets, the end of the effect, and only the dead rising. Semantics: CK wiki "Magic
// Effect" and UESP "Skyrim:Conjuration".

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import Testing

@MainActor
struct SummonTests {
    private typealias Archetype = ActiveEffectFixture.Archetype
    private static let victim = ReferenceKey.plugin(name: "base.esm", objectID: 0x0900)

    private let world = FakeMagicWorld()

    private func makeCoordinator() throws -> MagicCoordinator {
        let file = try ActiveEffectFixture.plugin(
            records: ActiveEffectFixture.effectRecords + ActiveEffectFixture.archetypeRecords
        )
        world.holders[Self.victim] = ActorValueHolder(
            key: Self.victim, subject: .actor(base: FormID(0x0F01)), cell: nil
        )
        let coordinator = MagicCoordinator(world: world)
        coordinator.wireEffects(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)]),
            pluginName: ActiveEffectFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        return coordinator
    }

    @discardableResult
    private static func cast(
        _ formID: UInt32, on target: ReferenceKey, _ coordinator: MagicCoordinator
    ) -> [ActiveEffect] {
        guard let holder = coordinator.world.actorValueHolder(for: target) else { return [] }
        return coordinator.withEffects { runtime in
            runtime.apply(
                [MagicItemEffect(
                    effect: FormID(formID), magnitude: 10, area: 0, duration: 60,
                    conditions: ConditionList()
                )],
                fromPlugin: ActiveEffectFixture.pluginName,
                source: ActiveEffectSource(
                    kind: .spell, record: .plugin(name: "base.esm", objectID: 0x600)
                ),
                caster: .player,
                on: holder
            )
        } ?? []
    }

    @Test func aSummonAppearsAndGoesWhenItsEffectEnds() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.summon, on: .player, coordinator)
        #expect(world.summoned.map(\.base) == [FormID(Archetype.summonedActor)])
        #expect(coordinator.commanded.map(\.kind) == [.summoned])

        for _ in 0 ..< 610 {
            _ = coordinator.advanceEffects(delta: 0.1)
        }
        #expect(coordinator.commanded.isEmpty)
        #expect(world.releasedActors.map(\.actor) == [.generated(1)])
    }

    /// Without Twin Souls a second summon sends the first away and ends its effect.
    @Test func aSecondSummonReplacesTheFirst() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.summon, on: .player, coordinator)
        Self.cast(Archetype.summon, on: .player, coordinator)
        #expect(coordinator.commanded.map(\.actor) == [.generated(2)])
        #expect(world.releasedActors.map(\.actor) == [.generated(1)])
        #expect(coordinator.effects?.active(on: .player).count == 1)
    }

    @Test func twinSoulsKeepsTwo() throws {
        let coordinator = try makeCoordinator()
        world.perkValues[.modCommandedActorLimit] = 2
        Self.cast(Archetype.summon, on: .player, coordinator)
        Self.cast(Archetype.summon, on: .player, coordinator)
        #expect(coordinator.commandLimit(of: .player) == 2)
        #expect(coordinator.commanded.count == 2)
        #expect(world.releasedActors.isEmpty)
    }

    /// "If the target is dead": a living target keeps nothing.
    @Test func onlyTheDeadRise() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Archetype.reanimate, on: Self.victim, coordinator)
        #expect(coordinator.commanded.isEmpty)
        let victim = try #require(world.holders[Self.victim])
        #expect(coordinator.effects?.active(on: victim).isEmpty == true)

        world.dead = [Self.victim]
        Self.cast(Archetype.reanimate, on: Self.victim, coordinator)
        #expect(coordinator.commanded.map(\.kind) == [.reanimated])
        #expect(coordinator.commanded.first?.caster == .player)
    }
}
