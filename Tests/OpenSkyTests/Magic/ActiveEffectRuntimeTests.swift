// The active-effect runtime (issue #469, roadmap item 19.6): instant
// application and the two timed behaviours the Recover flag selects, including
// the exact reversal a held modifier makes on expiry. Condition gating, the
// stacking rules and dispel are `ActiveEffectStackingTests`.
//
// Records are synthetic and built in code (`ActiveEffectFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import OpenSkyActors
@testable import OpenSkyActorsInterface
@testable import OpenSkyEngine
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct ActiveEffectRuntimeTests {
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

    // MARK: - Instant

    /// The whole point of the milestone: drinking a restore-health potion moves
    /// the player's health and stores nothing.
    @Test func instantRestoreMovesHealthAndStoresNoEffect() throws {
        var (runtime, _) = try runtime()
        runtime.values.damage(.health, by: 40, on: .player)
        #expect(runtime.values.current(of: .player).health == 60)

        let stored = apply(&runtime, [entry(ActiveEffectFixture.restoreHealth, magnitude: 25)])
        #expect(stored.isEmpty)
        #expect(runtime.values.current(of: .player).health == 85)
        #expect(runtime.active(on: .player).isEmpty)
        #expect(runtime.tally.instantApplications == 1)
    }

    /// A detrimental instant effect routes through damage rather than restore.
    @Test func instantDetrimentalEffectDamages() throws {
        var (runtime, _) = try runtime()
        apply(&runtime, [entry(ActiveEffectFixture.damageHealth, magnitude: 30)])
        #expect(runtime.values.current(of: .player).health == 70)
    }

    /// Restoring never lifts a value above its maximum.
    @Test func instantRestoreIsCappedAtTheMaximum() throws {
        var (runtime, _) = try runtime()
        runtime.values.damage(.health, by: 5, on: .player)
        apply(&runtime, [entry(ActiveEffectFixture.restoreHealth, magnitude: 500)])
        #expect(runtime.values.current(of: .player).health == 100)
    }

    // MARK: - Held modifiers

    /// Recover set: the magnitude is held in the temporary slot for the whole
    /// duration and handed back exactly on expiry.
    @Test func heldModifierAppliesOnceAndReversesOnExpiry() throws {
        var (runtime, store) = try runtime()
        let index = ActorValueIndex.resistFire
        let stored = apply(&runtime, [
            entry(ActiveEffectFixture.fortifyResistFire, magnitude: 20, duration: 2)
        ])
        #expect(stored.count == 1)
        #expect(runtime.values.entry(at: index, on: .player)?.temporary == 20)
        #expect(runtime.values.value(at: index, on: .player) == 20)

        // One second in, the effect is still running and the value is unchanged.
        step(&runtime, seconds: 1)
        #expect(runtime.active(on: .player).count == 1)
        #expect(runtime.values.entry(at: index, on: .player)?.temporary == 20)

        step(&runtime, seconds: 1)
        #expect(runtime.active(on: .player).isEmpty)
        #expect(runtime.values.entry(at: index, on: .player)?.temporary == 0)
        #expect(runtime.tally.expired == 1)
        // The component is dropped once it empties, so the actor stops being
        // dirty for this slot.
        #expect(store.component(ActiveEffectState.self, for: ReferenceKey.player) == nil)
    }

    /// A dual value modifier holds both slots and hands both back.
    @Test func dualValueModifierHoldsAndReleasesBothValues() throws {
        var (runtime, _) = try runtime()
        apply(&runtime, [entry(ActiveEffectFixture.dualResist, magnitude: 10, duration: 1)])
        #expect(runtime.values.entry(at: ActorValueIndex.resistFire, on: .player)?
            .temporary == 10)
        #expect(runtime.values.entry(at: ActorValueIndex.resistFrost, on: .player)?
            .temporary == 5)

        step(&runtime, seconds: 1)
        #expect(runtime.values.entry(at: ActorValueIndex.resistFire, on: .player)?
            .temporary == 0)
        #expect(runtime.values.entry(at: ActorValueIndex.resistFrost, on: .player)?
            .temporary == 0)
    }

    // MARK: - Per-second effects

    /// Recover clear: the magnitude is paid once per completed second, so a
    /// three-second effect of magnitude two takes six points and takes none of
    /// them back.
    @Test func perSecondEffectPaysOncePerWholeSecondAndNeverReverses() throws {
        var (runtime, _) = try runtime()
        apply(&runtime, [entry(ActiveEffectFixture.damageHealth, magnitude: 2, duration: 3)])
        #expect(runtime.values.current(of: .player).health == 100)

        step(&runtime, seconds: 1)
        #expect(runtime.values.current(of: .player).health == 98)
        step(&runtime, seconds: 2)
        #expect(runtime.values.current(of: .player).health == 94)
        #expect(runtime.active(on: .player).isEmpty)
        #expect(runtime.tally.secondsPaid == 3)
    }

    /// A partial step pays nothing: the documented rule is per second, and a
    /// sixtieth of a second is not one.
    @Test func partialStepPaysNothing() throws {
        var (runtime, _) = try runtime()
        apply(&runtime, [entry(ActiveEffectFixture.damageHealth, magnitude: 2, duration: 3)])
        runtime.step(over: [.player])
        #expect(runtime.values.current(of: .player).health == 100)
        #expect(runtime.tally.secondsPaid == 0)
    }

    // MARK: - Held modifiers on a primary (issue #511)

    /// A Fortify Health potion raises the maximum and the current value
    /// together, and expiry puts both numbers back.
    @Test func fortifyHealthRaisesTheMaximumAndExpiryPutsItBack() throws {
        var (runtime, _) = try runtime()
        apply(&runtime, [entry(ActiveEffectFixture.fortifyHealth, magnitude: 25, duration: 2)])
        #expect(runtime.values.maximums(of: .player).health == 125)
        #expect(runtime.values.current(of: .player).health == 125)
        // The HUD reads the fraction, so a full fortified bar is still full.
        #expect(runtime.values.fractions(of: .player).health == 1)

        step(&runtime, seconds: 2)
        #expect(runtime.active(on: .player).isEmpty)
        #expect(runtime.values.maximums(of: .player).health == 100)
        #expect(runtime.values.current(of: .player).health == 100)
    }

    /// Damage taken under the fortify survives its expiry: 125 maximum, 60
    /// taken, expiry reads 40 of 100 rather than healing or double-charging.
    @Test func damageTakenWhileFortifiedSurvivesExpiry() throws {
        var (runtime, _) = try runtime()
        apply(&runtime, [entry(ActiveEffectFixture.fortifyHealth, magnitude: 25, duration: 1)])
        runtime.values.damage(.health, by: 60, on: .player)
        #expect(runtime.values.current(of: .player).health == 65)

        step(&runtime, seconds: 1)
        #expect(runtime.values.maximums(of: .player).health == 100)
        #expect(runtime.values.current(of: .player).health == 40)
        #expect(!runtime.values.hasZeroHealth(.player))
    }

    /// An expiry that would empty the bar leaves one point instead, so the
    /// death latch never trips on a timer: "the target is left with at least 1
    /// health point when the effect expires" (UESP, Fortify Health).
    @Test func anExpiryNeverEmptiesTheBar() throws {
        var (runtime, _) = try runtime()
        apply(&runtime, [entry(ActiveEffectFixture.fortifyHealth, magnitude: 25, duration: 1)])
        runtime.values.damage(.health, by: 115, on: .player)
        #expect(runtime.values.current(of: .player).health == 10)

        step(&runtime, seconds: 1)
        #expect(runtime.values.maximums(of: .player).health == 100)
        #expect(runtime.values.current(of: .player).health == ActiveEffectRuntime.expiryFloor)
        #expect(!runtime.values.hasZeroHealth(.player))
    }

    /// An actor already at zero stays there: the floor protects the living, it
    /// does not revive the dead.
    @Test func anExpiryDoesNotReviveAnEmptyBar() throws {
        var (runtime, _) = try runtime()
        apply(&runtime, [entry(ActiveEffectFixture.fortifyHealth, magnitude: 25, duration: 1)])
        runtime.values.damage(.health, by: 500, on: .player)

        step(&runtime, seconds: 1)
        #expect(runtime.values.current(of: .player).health == 0)
    }

    // MARK: - Helpers

    /// Advances `seconds` in whole fixed steps.
    private func step(_ runtime: inout ActiveEffectRuntime, seconds: Int) {
        let steps = Int((Double(seconds) / ActiveEffectRuntime.fixedStepSeconds).rounded())
        for _ in 0 ..< steps {
            runtime.step(over: [.player])
        }
    }
}
