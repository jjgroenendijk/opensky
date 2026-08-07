// Actor-value runtime tests (issue #194): the component's clamping invariants,
// the damage/restore API, and fixed-step regeneration.
//
// Everything here runs over a bare `WorldStateStore` and a fallback baseline
// resolver, with no plugin data at all — the runtime deliberately knows nothing
// about records, so its tests need none.

import Foundation
@testable import opensky
import Testing

@MainActor
struct ActorValueRuntimeTests {
    private let actorKey = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BAC)

    private func runtime(
        maximums: ActorValues = ActorValues(health: 100, magicka: 80, stamina: 60),
        regen: ActorValues = .zero
    ) -> (ActorValueRuntime, WorldStateStore) {
        let store = WorldStateStore()
        let baselines = ActorValueBaselineResolver(
            fallback: ActorValueBaseline(maximums: maximums, regenPercentPerSecond: regen)
        )
        return (ActorValueRuntime(store: store, baselines: baselines), store)
    }

    private func holder() -> ActorValueHolder {
        ActorValueHolder(key: actorKey, subject: .actor(base: FormID(0x0001_3BAC)))
    }

    // MARK: - Baseline

    /// An untouched actor reads a full baseline and stores nothing, exactly as
    /// an untouched container reads its CNTO list.
    @Test func anUntouchedActorReadsAFullBaselineWithoutStoringOne() {
        let (runtime, store) = self.runtime()
        let holder = holder()
        #expect(runtime.current(of: holder) == ActorValues(health: 100, magicka: 80, stamina: 60))
        #expect(!runtime.hasRuntimeState(holder))
        #expect(store.dirtyCount == 0)
    }

    /// The first mutation materializes the baseline, so a 20-point hit on a
    /// 100-health actor stores 80 rather than a -20 delta.
    @Test func theFirstMutationMaterializesTheBaseline() {
        let (runtime, store) = self.runtime()
        let holder = holder()
        let state = runtime.damage(.health, by: 20, on: holder)
        #expect(state.current.health == 80)
        #expect(state.current.magicka == 80)
        #expect(runtime.hasRuntimeState(holder))
        #expect(store.dirtyCount == 1)
    }

    // MARK: - Damage and restore

    @Test func damageFloorsAtZeroAndSetsTheZeroHealthFlag() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.damage(.health, by: 40, on: holder)
        #expect(!runtime.hasZeroHealth(holder))
        let state = runtime.damage(.health, by: 500, on: holder)
        #expect(state.current.health == 0)
        #expect(state.hasZeroHealth)
        #expect(runtime.hasZeroHealth(holder))
    }

    @Test func restoreCapsAtTheDerivedMaximum() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.damage(.stamina, by: 50, on: holder)
        let state = runtime.restore(.stamina, by: 1000, on: holder)
        #expect(state.current.stamina == 60)
    }

    /// A negative or non-finite amount changes nothing rather than healing: a
    /// negative weapon damage must not become a heal.
    @Test func nonPositiveAmountsChangeNothing() {
        let (runtime, store) = self.runtime()
        let holder = holder()
        for amount in [Float(0), -25, .nan, .infinity] {
            runtime.damage(.health, by: amount, on: holder)
            runtime.restore(.health, by: amount, on: holder)
        }
        #expect(store.dirtyCount == 0)
        #expect(runtime.current(of: holder).health == 100)
    }

    @Test func setClampsIntoRange() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        #expect(runtime.set(.magicka, to: 500, on: holder).current.magicka == 80)
        #expect(runtime.set(.magicka, to: -5, on: holder).current.magicka == 0)
        #expect(runtime.set(.magicka, to: .nan, on: holder).current.magicka == 0)
    }

    @Test func restoreAllRefillsEverything() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.damage(.health, by: 90, on: holder)
        runtime.damage(.magicka, by: 90, on: holder)
        let state = runtime.restoreAll(on: holder)
        #expect(state.current == ActorValues(health: 100, magicka: 80, stamina: 60))
    }

    /// Reset drops the component so the actor re-derives from records again,
    /// which is the component-level counterpart of a store reset.
    @Test func resetDropsTheRuntimeState() {
        let (runtime, store) = self.runtime()
        let holder = holder()
        runtime.damage(.health, by: 30, on: holder)
        #expect(runtime.reset(holder))
        #expect(!runtime.hasRuntimeState(holder))
        #expect(store.dirtyCount == 0)
        #expect(runtime.current(of: holder).health == 100)
        #expect(!runtime.reset(holder))
    }

    // MARK: - Fractions and the zero maximum

    @Test func fractionsAreCurrentOverMaximum() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.damage(.health, by: 25, on: holder)
        let fractions = runtime.fractions(of: holder)
        #expect(fractions.health == 0.75)
        #expect(fractions.magicka == 1)
    }

    /// An actor with no maximum reads empty rather than full, which is the one
    /// reading a player must not be given.
    @Test func aZeroMaximumReadsEmpty() {
        let (runtime, _) = self.runtime(maximums: .zero)
        let holder = holder()
        #expect(runtime.current(of: holder) == .zero)
        #expect(runtime.fractions(of: holder) == .zero)
        #expect(runtime.hasZeroHealth(holder))
    }

    // MARK: - Regeneration

    /// "Health Regen: The percentage of total Health that is regenerated each
    /// second" (<https://ck.uesp.net/wiki/Race>), so one second of 5%/s on a
    /// 60-stamina actor restores 3.
    @Test func regenerationRestoresThePercentPerSecond() {
        let (runtime, _) = self.runtime(regen: ActorValues(health: 0, magicka: 0, stamina: 5))
        let holder = holder()
        runtime.damage(.stamina, by: 30, on: holder)
        for _ in 0 ..< 60 {
            runtime.stepRegeneration(over: [holder])
        }
        #expect(abs(runtime.current(of: holder).stamina - 33) < 0.001)
    }

    @Test func regenerationCapsAtTheMaximum() {
        let (runtime, _) = self.runtime(regen: ActorValues(repeating: 100))
        let holder = holder()
        runtime.damage(.magicka, by: 5, on: holder)
        for _ in 0 ..< 600 {
            runtime.stepRegeneration(over: [holder])
        }
        #expect(runtime.current(of: holder).magicka == 80)
    }

    /// Health does not regenerate at zero: whether a dead actor comes back is
    /// item 15.6's decision, not this layer's.
    @Test func healthDoesNotRegenerateAtZero() {
        let (runtime, _) = self.runtime(regen: ActorValues(repeating: 50))
        let holder = holder()
        runtime.damage(.health, by: 1000, on: holder)
        runtime.damage(.magicka, by: 40, on: holder)
        for _ in 0 ..< 60 {
            runtime.stepRegeneration(over: [holder])
        }
        #expect(runtime.current(of: holder).health == 0)
        #expect(runtime.current(of: holder).magicka > 40)
    }

    /// A zero regen rate writes nothing at all, so a full session of ticks
    /// leaves the store clean.
    @Test func aZeroRateWritesNothing() {
        let (runtime, store) = self.runtime()
        for _ in 0 ..< 100 {
            runtime.stepRegeneration(over: [holder()])
        }
        #expect(store.dirtyCount == 0)
    }

    // MARK: - Fixed step and the menu-pause rule

    /// The established menu-pause rule reaches this layer as delta 0: it
    /// advances nothing, regenerates nothing, and is safe every frame.
    @Test func aZeroDeltaAdvancesNothing() {
        let (runtime, store) = self.runtime(regen: ActorValues(repeating: 100))
        var accumulator = 0.0
        let holder = holder()
        runtime.damage(.stamina, by: 30, on: holder)
        let before = runtime.current(of: holder)
        for _ in 0 ..< 1000 {
            #expect(runtime.advance(delta: 0, accumulator: &accumulator, over: [holder]) == 0)
        }
        #expect(accumulator == 0)
        #expect(runtime.current(of: holder) == before)
        #expect(store.dirtyCount == 1)
    }

    /// A negative or non-finite delta is treated the same way rather than run
    /// backwards.
    @Test func aNegativeOrNonFiniteDeltaAdvancesNothing() {
        let (runtime, _) = self.runtime(regen: ActorValues(repeating: 100))
        var accumulator = 0.0
        for delta in [Float(-1), .nan, .infinity] {
            #expect(runtime.advance(delta: delta, accumulator: &accumulator, over: []) == 0)
        }
        #expect(accumulator == 0)
    }

    @Test func advanceRunsWholeStepsAndCarriesTheRemainder() {
        let (runtime, _) = self.runtime(regen: ActorValues(repeating: 100))
        var accumulator = 0.0
        let holder = holder()
        // A quarter of a fixed step, four times, is one whole step.
        let quarter = Float(ActorValueRuntime.fixedStepSeconds / 4)
        for _ in 0 ..< 3 {
            #expect(runtime.advance(
                delta: quarter, accumulator: &accumulator, over: [holder]
            ) == 0)
        }
        #expect(runtime.advance(delta: quarter, accumulator: &accumulator, over: [holder]) == 1)
    }

    /// A multi-second stall cannot spend minutes regenerating in one frame.
    @Test func advanceCapsTheStepsPerCall() {
        let (runtime, _) = self.runtime(regen: ActorValues(repeating: 100))
        var accumulator = 0.0
        let steps = runtime.advance(delta: 30, accumulator: &accumulator, over: [holder()])
        #expect(steps == ActorValueRuntime.maximumStepsPerAdvance)
        #expect(accumulator
            <= ActorValueRuntime.fixedStepSeconds
            * Double(ActorValueRuntime.maximumStepsPerAdvance))
    }

    /// Regeneration is deterministic across collection order: the runtime sorts
    /// by `ReferenceKey`, so the same set of actors ends in the same state.
    @Test func regenerationIsDeterministicAcrossHolderOrder() {
        let holders = (1 ... 4).map { index in
            ActorValueHolder(
                key: .plugin(name: "skyrim.esm", objectID: UInt32(index)),
                subject: .actor(base: FormID(UInt32(index)))
            )
        }
        var snapshots: [WorldStateSnapshot] = []
        for order in [holders, holders.reversed()] {
            let (runtime, store) = self.runtime(regen: ActorValues(repeating: 2))
            for holder in order {
                runtime.damage(.health, by: 40, on: holder)
            }
            for _ in 0 ..< 30 {
                runtime.stepRegeneration(over: Array(order))
            }
            snapshots.append(store.snapshot())
        }
        #expect(snapshots[0].entries == snapshots[1].entries)
    }
}

struct ActorValueComponentTests {
    /// The type's one invariant: every value is finite and not negative.
    @Test func initNormalizesNegativeAndNonFiniteValues() {
        let state = ActorValueState(current: ActorValues(health: -5, magicka: .nan, stamina: 3))
        #expect(state.current == ActorValues(health: 0, magicka: 0, stamina: 3))
        #expect(state.hasZeroHealth)
    }

    @Test func clampedPullsEveryValueInsideItsMaximum() {
        let state = ActorValueState(current: ActorValues(repeating: 500))
            .clamped(to: ActorValues(health: 100, magicka: 0, stamina: 250))
        #expect(state.current == ActorValues(health: 100, magicka: 0, stamina: 250))
    }

    @Test func erasureRoundTripsThroughTheComponentValue() {
        let state = ActorValueState(current: ActorValues(health: 7, magicka: 8, stamina: 9))
        #expect(ActorValueState(erased: state.erased) == state)
        #expect(ActorValueState.componentKind == .actorValues)
        #expect(state.erased.kind == .actorValues)
        #expect(ActorValueState(erased: ReferenceEnableState.enabled.erased) == nil)
    }
}
