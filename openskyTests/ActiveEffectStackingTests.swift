// The active-effect runtime, second half (issue #469, roadmap item 19.6):
// condition gating, the two stacking rules, dispel, `HasMagicEffect` and
// modifier re-establishment after a load.
//
// Split out of `ActiveEffectRuntimeTests` because that suite is at its size
// shape; the setup is the same, and the two halves cover different behaviour.
//
// Records are synthetic and built in code (`ActiveEffectFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct ActiveEffectStackingTests {
    private func runtime() throws -> (ActiveEffectRuntime, WorldStateStore) {
        let store = WorldStateStore()
        let baselines = ActorValueBaselineResolver(
            fallback: ActorValueBaseline(
                maximums: ActorValues(repeating: 100),
                regenPercentPerSecond: .zero
            )
        )
        let values = ActorValueRuntime(store: store, baselines: baselines)
        let file = try ActiveEffectFixture.plugin(records: ActiveEffectFixture.effectRecords)
        let effects = MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)])
        return (ActiveEffectRuntime(values: values, effects: effects), store)
    }

    private func entry(
        _ formID: UInt32,
        magnitude: Float,
        duration: UInt32 = 0,
        conditions: ConditionList = ConditionList()
    ) -> MagicItemEffect {
        MagicItemEffect(
            effect: FormID(formID),
            magnitude: magnitude,
            area: 0,
            duration: duration,
            conditions: conditions
        )
    }

    private var source: ActiveEffectSource {
        ActiveEffectSource(
            kind: .potion,
            record: .plugin(name: ActiveEffectFixture.pluginName.lowercased(), objectID: 0x500)
        )
    }

    @discardableResult
    private func apply(
        _ runtime: inout ActiveEffectRuntime,
        _ entries: [MagicItemEffect]
    ) -> [ActiveEffect] {
        runtime.apply(
            entries,
            fromPlugin: ActiveEffectFixture.pluginName,
            source: source,
            on: .player
        )
    }

    // MARK: - Conditions

    /// An entry whose CTDA list evaluates false applies nothing and is counted.
    @Test func conditionGatedEntryIsSkippedAndCounted() throws {
        var (runtime, _) = try runtime()
        let stored = apply(&runtime, [
            entry(
                ActiveEffectFixture.restoreHealth,
                magnitude: 25,
                conditions: falseConditionList()
            )
        ])
        #expect(stored.isEmpty)
        #expect(runtime.values.current(of: .player).health == 100)
        #expect(runtime.tally.conditionSkipped == 1)
    }

    /// An unconditioned entry applies, which is what an empty list means.
    @Test func unconditionedEntryApplies() throws {
        var (runtime, _) = try runtime()
        runtime.values.damage(.health, by: 30, on: .player)
        apply(&runtime, [entry(ActiveEffectFixture.restoreHealth, magnitude: 10)])
        #expect(runtime.values.current(of: .player).health == 80)
        #expect(runtime.tally.conditionSkipped == 0)
    }

    // MARK: - Stacking

    /// Two applications of the same effect without No Recast are two effects.
    @Test func sameEffectStacksTwiceByDefault() throws {
        var (runtime, _) = try runtime()
        let first = apply(&runtime, [
            entry(ActiveEffectFixture.fortifyResistFire, magnitude: 20, duration: 10)
        ])
        let second = apply(&runtime, [
            entry(ActiveEffectFixture.fortifyResistFire, magnitude: 20, duration: 10)
        ])
        #expect(runtime.active(on: .player).count == 2)
        #expect(first[0].sequence != second[0].sequence)
        #expect(runtime.values.entry(at: ActorValueIndex.resistFire, on: .player)?
            .temporary == 40)
    }

    /// "If there are two PVMs with the same keyword active at the same time,
    /// the one with the lower <mag> will be dispelled automatically" — Creation
    /// Kit wiki, Effect Archetypes.
    @Test func peakValueModifiersWithOneKeywordKeepOnlyTheStronger() throws {
        var (runtime, _) = try runtime()
        apply(&runtime, [entry(ActiveEffectFixture.peakResist, magnitude: 10, duration: 20)])
        apply(&runtime, [entry(ActiveEffectFixture.peakResist, magnitude: 25, duration: 20)])
        #expect(runtime.active(on: .player).count == 1)
        #expect(runtime.values.entry(at: ActorValueIndex.resistFire, on: .player)?
            .temporary == 25)

        // A weaker one arriving afterwards is refused rather than displacing it.
        apply(&runtime, [entry(ActiveEffectFixture.peakResist, magnitude: 5, duration: 20)])
        #expect(runtime.active(on: .player).count == 1)
        #expect(runtime.values.entry(at: ActorValueIndex.resistFire, on: .player)?
            .temporary == 25)
        #expect(runtime.tally.peakStackResolved == 2)
    }

    /// No Recast: the effect cannot be applied again while it is running.
    @Test func noRecastEffectRefusesASecondApplication() throws {
        let file = try ActiveEffectFixture.plugin(records: [
            ActiveEffectFixture.magicEffect(
                formID: 0x30, editorID: "NoRecast", name: "No Recast",
                data: ActiveEffectFixture.data(
                    flags: [.recover, .noRecast], archetype: 0,
                    primaryValue: ActorValueIndex.resistFire
                )
            )
        ])
        let store = WorldStateStore()
        let values = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 100),
                    regenPercentPerSecond: .zero
                )
            )
        )
        var runtime = ActiveEffectRuntime(
            values: values,
            effects: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)])
        )
        apply(&runtime, [entry(0x30, magnitude: 10, duration: 10)])
        apply(&runtime, [entry(0x30, magnitude: 10, duration: 10)])
        #expect(runtime.active(on: .player).count == 1)
        #expect(runtime.tally.recastRefused == 1)
    }

    // MARK: - Dispel and reload

    /// Dispelling hands the modifier slot back exactly as expiry does.
    @Test func dispelRemovesEffectsAndReleasesTheirModifiers() throws {
        var (runtime, _) = try runtime()
        apply(&runtime, [entry(ActiveEffectFixture.fortifyResistFire, magnitude: 20, duration: 60)])
        #expect(runtime.dispelAll(on: .player) == 1)
        #expect(runtime.active(on: .player).isEmpty)
        #expect(runtime.values.entry(at: ActorValueIndex.resistFire, on: .player)?
            .temporary == 0)
        #expect(runtime.tally.dispelled == 1)
    }

    /// `HasMagicEffect`'s shape answers off the component.
    @Test func hasMagicEffectAnswersWhileTheEffectRuns() throws {
        var (runtime, _) = try runtime()
        let key = ReferenceKey.plugin(
            name: ActiveEffectFixture.pluginName.lowercased(),
            objectID: ActiveEffectFixture.fortifyResistFire
        )
        #expect(runtime.hasMagicEffect(key, on: .player) == false)
        apply(&runtime, [entry(ActiveEffectFixture.fortifyResistFire, magnitude: 5, duration: 1)])
        #expect(runtime.hasMagicEffect(key, on: .player))
        step(&runtime, seconds: 1)
        #expect(runtime.hasMagicEffect(key, on: .player) == false)
    }

    /// A load restores the effect list but not the temporary modifier, which
    /// the runtime re-establishes from what each effect says it owns.
    @Test func reestablishRebuildsTheTemporarySlotAfterALoad() throws {
        var (runtime, store) = try runtime()
        apply(&runtime, [entry(ActiveEffectFixture.fortifyResistFire, magnitude: 20, duration: 60)])
        let effects = try #require(
            store.component(ActiveEffectState.self, for: ReferenceKey.player)
        )
        // The save drops the temporary modifier on purpose, so simulate the
        // reload by clearing it and keeping the effect list.
        store.set(ActorValueState(current: ActorValues(repeating: 100)), for: .player)
        store.set(effects, for: .player)
        #expect(runtime.values.entry(at: ActorValueIndex.resistFire, on: .player)?
            .temporary == 0)

        #expect(runtime.reestablishModifiers(on: .player) == 1)
        #expect(runtime.values.entry(at: ActorValueIndex.resistFire, on: .player)?
            .temporary == 20)
    }

    /// Regeneration rewrites the actor-value component sixty times a second and
    /// must not drop the general table an effect is holding a modifier in.
    @Test func regenerationDoesNotDropAHeldModifier() throws {
        let store = WorldStateStore()
        let values = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 100),
                    regenPercentPerSecond: ActorValues(repeating: 10)
                )
            )
        )
        let file = try ActiveEffectFixture.plugin(records: ActiveEffectFixture.effectRecords)
        var runtime = ActiveEffectRuntime(
            values: values,
            effects: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)])
        )
        values.damage(.health, by: 50, on: .player)
        apply(&runtime, [entry(ActiveEffectFixture.fortifyResistFire, magnitude: 20, duration: 60)])
        values.stepRegeneration(over: [.player])
        #expect(values.entry(at: ActorValueIndex.resistFire, on: .player)?.temporary == 20)
    }

    // MARK: - Helpers

    /// Advances `seconds` in whole fixed steps.
    private func step(_ runtime: inout ActiveEffectRuntime, seconds: Int) {
        let steps = Int((Double(seconds) / ActiveEffectRuntime.fixedStepSeconds).rounded())
        for _ in 0 ..< steps {
            runtime.step(over: [.player])
        }
    }

    /// One condition this engine cannot answer, which is a reason-tagged false
    /// and therefore a skipped entry.
    private func falseConditionList() -> ConditionList {
        var list = ConditionList()
        // `GetIsID(base) == 1` with no reference index behind the context: the
        // documented reason-tagged false, which is what a skipped entry is.
        _ = try? list.decode(field: ConditionEvaluatorFixture.field(
            comparisonValue: Float(1).bitPattern,
            functionIndex: 72,
            parameter1: 0x0000_0001
        ))
        return list
    }
}
