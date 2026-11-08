// The archetypes that move actor values, over the real actor-value runtime:
// held flags, Absorb, and Accumulate Magnitude. Rules are cited at
// `MagicArchetypeRule`; records are synthetic (`ActiveEffectFixture`).

import Foundation
@testable import OpenSkyActorsInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct MagicArchetypeValueTests {
    private typealias Archetype = ActiveEffectFixture.Archetype

    private let npc = ActorValueHolder(
        key: .plugin(name: "base.esm", objectID: 0x800), subject: .generated
    )

    private func runtime() throws -> ActiveEffectRuntime {
        try ActiveEffectFixture.runtime(conditionRegistry: .magicTests).0
    }

    private func entry(_ formID: UInt32, magnitude: Float, duration: UInt32 = 0)
        -> MagicItemEffect
    {
        ActiveEffectFixture.entry(formID, magnitude: magnitude, duration: duration)
    }

    /// Paralysis "will also set the boolean actor value Paralyze to 1", and the
    /// value goes back when the effect ends.
    @Test func paralysisHoldsTheParalysisValueWhileItRuns() throws {
        var runtime = try runtime()
        ActiveEffectFixture.apply(
            &runtime, [entry(ActiveEffectFixture.paralyze, magnitude: 0, duration: 1)]
        )
        #expect(runtime.values.value(at: 53, on: .player) == 1)
        #expect(runtime.influence(on: .player).isParalysed)
        step(&runtime, seconds: 1)
        #expect(runtime.values.value(at: 53, on: .player) == 0)
    }

    /// Casting breaks invisibility, which hands the value back.
    @Test func breakingInvisibilityEndsTheEffect() throws {
        var runtime = try runtime()
        ActiveEffectFixture.apply(
            &runtime, [entry(Archetype.invisibility, magnitude: 0, duration: 30)]
        )
        #expect(runtime.values.value(at: 54, on: .player) == 1)
        #expect(runtime.breakInvisibility(on: .player) == 1)
        #expect(runtime.values.value(at: 54, on: .player) == 0)
    }

    /// "Does up to <MAG> damage to the target's attribute, and restores the
    /// caster's attribute by the amount of damage done."
    @Test func absorbMovesHealthFromTargetToCaster() throws {
        var runtime = try runtime()
        runtime.values.damage(.health, by: 50, on: .player)
        runtime.values.damage(.health, by: 90, on: npc)
        runtime.apply(
            [entry(Archetype.absorbHealth, magnitude: 20)],
            fromPlugin: ActiveEffectFixture.pluginName,
            source: ActiveEffectFixture.potionSource,
            caster: .player,
            on: npc
        )
        // Only 10 was there to take, so the caster gains 10.
        #expect(runtime.values.current(of: npc).health == 0)
        #expect(runtime.values.current(of: .player).health == 60)
    }

    /// A timed absorb pays each second, both ways.
    @Test func timedAbsorbPaysEverySecond() throws {
        var runtime = try runtime()
        runtime.values.damage(.health, by: 50, on: .player)
        runtime.apply(
            [entry(Archetype.absorbHealth, magnitude: 5, duration: 2)],
            fromPlugin: ActiveEffectFixture.pluginName,
            source: ActiveEffectFixture.potionSource,
            caster: .player,
            on: npc
        )
        step(&runtime, seconds: 2, over: [.player, npc])
        #expect(runtime.values.current(of: npc).health == 90)
        #expect(runtime.values.current(of: .player).health == 60)
    }

    /// Accumulate Magnitude "starts at 0 and increases over time".
    @Test func accumulateGrowsToItsMagnitude() throws {
        var runtime = try runtime()
        ActiveEffectFixture.apply(
            &runtime, [entry(Archetype.wardAccumulate, magnitude: 40, duration: 5)]
        )
        #expect(runtime.values.value(at: Archetype.wardPower, on: .player) == 0)
        step(&runtime, seconds: 1)
        let grown = try #require(runtime.values.value(at: Archetype.wardPower, on: .player))
        #expect(abs(grown - 40) < 0.01)
        step(&runtime, seconds: 4)
        #expect(runtime.values.value(at: Archetype.wardPower, on: .player) == 0)
    }

    // MARK: - Helpers

    private func step(
        _ runtime: inout ActiveEffectRuntime,
        seconds: Int,
        over holders: [ActorValueHolder] = [.player]
    ) {
        let steps = Int((Double(seconds) / ActiveEffectRuntime.fixedStepSeconds).rounded())
        for _ in 0 ..< steps {
            runtime.step(over: holders)
        }
    }
}
