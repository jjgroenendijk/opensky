// The base-override store (issue #496, roadmap item 20.3): what an explicit
// base write means, how it survives re-derivation, and how it interacts with
// damage, regeneration and the modifier slots.
//
// The rule under test, stated once: an override is stored as a *delta* on top
// of the re-derived baseline. The records stay authoritative for what a value
// is; the override says only what the session did to it. So a level change or a
// reordered load order moves every actor value, and no re-derivation can clobber
// a trained or script-set one.
//
// Baselines are synthetic (`ActorValueBaselineResolver`'s fallback) rather than
// record-derived, because the precedence rule is about the *relationship*
// between a derived number and a stored one and not about where the derived one
// came from. Record derivation itself is `ActorValueDerivationTests`.

import Foundation
@testable import opensky
import Testing

@MainActor
struct ActorValueOverrideTests {
    private static let health = ActorValueIdentity.index(of: .health)
    private static let sneak: Int32 = 15
    private static let resistFire = ActorValueIndex.resistFire
    private static let outsideTable: Int32 = 164

    private let actorKey = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BAC)

    private func runtime(
        maximums: ActorValues = ActorValues(repeating: 100),
        general: [Int32: Float] = [:]
    ) -> (ActorValueRuntime, WorldStateStore) {
        let store = WorldStateStore()
        let baselines = ActorValueBaselineResolver(
            fallback: ActorValueBaseline(
                maximums: maximums,
                regenPercentPerSecond: .zero,
                general: general
            )
        )
        return (ActorValueRuntime(store: store, baselines: baselines), store)
    }

    private func holder() -> ActorValueHolder {
        ActorValueHolder(key: actorKey, subject: .actor(base: FormID(0x0001_3BAC)))
    }

    // MARK: - The precedence rule

    /// The heart of item 20.3: an override is a delta, so a re-derived baseline
    /// moves the value and the session's own contribution rides on top.
    ///
    /// Driven by two runtimes over one store, which is exactly what a changed
    /// load order looks like from the store's side: the same saved state read
    /// against records that now say something else.
    @Test func aBaseOverrideRidesOnTopOfARederivedBaseline() {
        let store = WorldStateStore()
        let holder = holder()
        let before = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(fallback: ActorValueBaseline(
                maximums: ActorValues(repeating: 100),
                regenPercentPerSecond: .zero,
                general: [Self.sneak: 20]
            ))
        )
        #expect(before.incrementBase(at: Self.sneak, by: 5, on: holder))
        #expect(before.setBase(at: Self.health, to: 150, on: holder))
        #expect(before.baseValue(at: Self.sneak, on: holder) == 25)
        #expect(before.baseValue(at: Self.health, on: holder) == 150)

        // The records now author a higher skill and a higher maximum — a level
        // gained, or a plugin that rebalanced the race.
        let after = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(fallback: ActorValueBaseline(
                maximums: ActorValues(health: 130, magicka: 100, stamina: 100),
                regenPercentPerSecond: .zero,
                general: [Self.sneak: 30]
            ))
        )
        // Neither number was clobbered and neither was pinned: the trained five
        // points still sit on top of what the records now say.
        #expect(after.baseValue(at: Self.sneak, on: holder) == 35)
        #expect(after.baseValue(at: Self.health, on: holder) == 180)
        #expect(after.maximums(of: holder).health == 180)
    }

    /// A value written back to exactly its baseline stores nothing, so an actor
    /// nothing happened to stops being dirty in the sense the save cares about.
    @Test func anOverrideBackAtZeroIsDropped() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.setBase(at: Self.health, to: 150, on: holder)
        #expect(runtime.state(of: holder).overrides.count == 1)
        runtime.setBase(at: Self.health, to: 100, on: holder)
        #expect(runtime.state(of: holder).overrides.isEmpty)
    }

    @Test func anIndexOutsideTheTableWritesNothing() {
        let (runtime, store) = self.runtime()
        let holder = holder()
        #expect(!runtime.setBase(at: Self.outsideTable, to: 50, on: holder))
        #expect(!runtime.incrementBase(at: Self.outsideTable, by: 5, on: holder))
        #expect(!runtime.forceValue(at: Self.outsideTable, to: 5, on: holder))
        #expect(!runtime.addModifier(5, to: .permanent, at: Self.outsideTable, on: holder))
        #expect(store.dirtyCount == 0)
    }

    // MARK: - Primaries

    /// The documented `ModActorValue` case: "if an actor has 100 Health,
    /// ModActorValue by -10 will lower the health total to 90/90, whereas
    /// DamageActorValue by 10 will result in 90/100 Health"
    /// (<https://ck.uesp.net/wiki/ModActorValue_-_Actor>).
    @Test func modifyingAPrimaryMovesTheMaximumAndTheCurrentValueTogether() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        #expect(runtime.addModifier(-10, to: .permanent, at: Self.health, on: holder))
        #expect(runtime.maximums(of: holder).health == 90)
        #expect(runtime.current(of: holder).health == 90)

        // And the other half of the same sentence, from a full actor.
        let (damaged, _) = self.runtime()
        damaged.damage(at: Self.health, by: 10, on: holder)
        #expect(damaged.maximums(of: holder).health == 100)
        #expect(damaged.current(of: holder).health == 90)
    }

    /// Damage a primary is carrying survives a change to its maximum: it is not
    /// healed by a buff and not doubled by one.
    @Test func damageSurvivesAMaximumChange() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.damage(at: Self.health, by: 10, on: holder)
        #expect(runtime.current(of: holder).health == 90)

        runtime.addModifier(-10, to: .permanent, at: Self.health, on: holder)
        #expect(runtime.maximums(of: holder).health == 90)
        #expect(runtime.current(of: holder).health == 80)

        // Removing the same modifier puts both numbers back exactly.
        runtime.addModifier(10, to: .permanent, at: Self.health, on: holder)
        #expect(runtime.maximums(of: holder).health == 100)
        #expect(runtime.current(of: holder).health == 90)
        #expect(runtime.state(of: holder).overrides.isEmpty)
    }

    /// `GetBaseActorValue` reports the base and `GetActorValuePercentage`
    /// divides by the maximum, so a fortified actor at full health reads 1.
    @Test func aPrimarySeparatesItsBaseItsMaximumAndItsFraction() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.setBase(at: Self.health, to: 120, on: holder)
        runtime.addModifier(30, to: .temporary, at: Self.health, on: holder)
        #expect(runtime.baseValue(at: Self.health, on: holder) == 120)
        #expect(runtime.maximums(of: holder).health == 150)
        // The base write moved the ceiling by 20 and the fortify by 30, and the
        // current value came along both times.
        #expect(runtime.current(of: holder).health == 150)
        #expect(runtime.fraction(at: Self.health, on: holder) == 1)
        #expect(runtime.fractions(of: holder).health == 1)
    }

    /// A restore stops at the *effective* maximum, so a fortify is usable
    /// headroom rather than a number the bar can never reach.
    @Test func restoringAPrimaryStopsAtTheFortifiedMaximum() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.damage(at: Self.health, by: 60, on: holder)
        runtime.addModifier(50, to: .temporary, at: Self.health, on: holder)
        #expect(runtime.current(of: holder).health == 90)
        runtime.restore(at: Self.health, by: 1000, on: holder)
        #expect(runtime.current(of: holder).health == 150)
    }

    /// A maximum driven to zero empties the bar, which is the death latch's
    /// input — and a maximum can never go negative.
    @Test func aPrimaryMaximumFloorsAtZeroAndEmptiesTheBar() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.addModifier(-500, to: .permanent, at: Self.health, on: holder)
        #expect(runtime.maximums(of: holder).health == 0)
        #expect(runtime.current(of: holder).health == 0)
        #expect(runtime.hasZeroHealth(holder))
    }

    /// Regeneration fills toward the fortified maximum and carries the override
    /// table through every write, so a buff is not dropped on the next frame.
    @Test func regenerationFillsTowardTheOverriddenMaximum() {
        let (runtime, _) = self.runtime(
            maximums: ActorValues(repeating: 100)
        )
        let holder = ActorValueHolder(
            key: actorKey,
            subject: .actor(base: FormID(0x0001_3BAC))
        )
        let regenerating = ActorValueRuntime(
            store: runtime.store,
            baselines: ActorValueBaselineResolver(fallback: ActorValueBaseline(
                maximums: ActorValues(repeating: 100),
                regenPercentPerSecond: ActorValues(repeating: 600)
            ))
        )
        regenerating.setBase(at: Self.health, to: 200, on: holder)
        regenerating.damage(at: Self.health, by: 100, on: holder)
        #expect(regenerating.current(of: holder).health == 100)
        for _ in 0 ..< 10 {
            regenerating.stepRegeneration(over: [holder])
        }
        #expect(regenerating.current(of: holder).health == 200)
        #expect(regenerating.state(of: holder).overrides.count == 1)
    }

    /// A refill fills to the fortified maximum and keeps the buff, rather than
    /// stripping the override on its way past.
    @Test func aRefillKeepsTheOverrideTable() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.setBase(at: Self.health, to: 150, on: holder)
        runtime.damage(at: Self.health, by: 100, on: holder)
        runtime.restoreAll(on: holder)
        #expect(runtime.current(of: holder).health == 150)
        #expect(runtime.baseValue(at: Self.health, on: holder) == 150)
    }

    // MARK: - Force

    /// `ForceActorValue`'s worked example, transcribed:
    /// "If an actor has a base health of 125 and you force their health to 0,
    /// then the permanent modifier will be set to -125, and their current
    /// health will become 0. If you then set the base health to 150, they will
    /// still have a permanent modifier of -125, so their current health will
    /// instantly become 25 (150 - 125)."
    /// (<https://ck.uesp.net/wiki/ForceActorValue_-_Actor>)
    @Test func forcingAPrimaryMovesThePermanentModifierAsDocumented() {
        let (runtime, _) = self.runtime(
            maximums: ActorValues(health: 125, magicka: 100, stamina: 100)
        )
        let holder = holder()
        #expect(runtime.forceValue(at: Self.health, to: 0, on: holder))
        #expect(runtime.entry(at: Self.health, on: holder)?.permanent == -125)
        #expect(runtime.current(of: holder).health == 0)

        #expect(runtime.setBase(at: Self.health, to: 150, on: holder))
        #expect(runtime.entry(at: Self.health, on: holder)?.permanent == -125)
        #expect(runtime.baseValue(at: Self.health, on: holder) == 150)
        #expect(runtime.current(of: holder).health == 25)
    }

    /// The same function on a non-primary, where the current value is the sum
    /// rather than a stored number.
    @Test func forcingANonPrimaryLandsExactlyOnTheValueAsked() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.setBase(at: Self.resistFire, to: 40, on: holder)
        runtime.addModifier(-15, to: .damage, at: Self.resistFire, on: holder)
        #expect(runtime.forceValue(at: Self.resistFire, to: 10, on: holder))
        #expect(runtime.value(at: Self.resistFire, on: holder) == 10)
        // The base is untouched — only the permanent modifier moved.
        #expect(runtime.baseValue(at: Self.resistFire, on: holder) == 40)
    }

    // MARK: - Skills

    /// The API item 20.5 advances a skill through, and the guard that keeps it
    /// from landing on something that is not a skill.
    @Test func advancingASkillRaisesItsBaseAndRejectsEverythingElse() {
        let (runtime, _) = self.runtime(general: [Self.sneak: 20])
        let holder = holder()
        #expect(runtime.advanceSkill(at: Self.sneak, by: 1, on: holder))
        #expect(runtime.advanceSkill(at: Self.sneak, by: 1, on: holder))
        #expect(runtime.baseValue(at: Self.sneak, on: holder) == 22)
        #expect(runtime.value(at: Self.sneak, on: holder) == 22)

        #expect(!runtime.advanceSkill(at: Self.health, by: 1, on: holder))
        #expect(!runtime.advanceSkill(at: Self.resistFire, by: 1, on: holder))
        #expect(runtime.state(of: holder).overrides.count == 1)
    }

    /// An increment composes with a magic effect's temporary modifier instead
    /// of overwriting it, which is what keeps training and buffs independent.
    @Test func aSkillIncrementLeavesTheModifiersAlone() {
        let (runtime, _) = self.runtime(general: [Self.sneak: 20])
        let holder = holder()
        runtime.addModifier(10, to: .temporary, at: Self.sneak, on: holder)
        runtime.incrementBase(at: Self.sneak, by: 5, on: holder)
        let entry = runtime.entry(at: Self.sneak, on: holder)
        #expect(entry?.base == 25)
        #expect(entry?.temporary == 10)
        #expect(runtime.value(at: Self.sneak, on: holder) == 35)
    }

    // MARK: - Snapshots

    /// A condition's snapshot answers the same numbers the live runtime does,
    /// including for an overridden primary — the two read paths must not
    /// disagree about the same actor.
    @Test func aSnapshotAnswersWhatTheRuntimeAnswers() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.setBase(at: Self.health, to: 150, on: holder)
        runtime.addModifier(20, to: .temporary, at: Self.resistFire, on: holder)
        runtime.damage(at: Self.health, by: 30, on: holder)

        let state = ActorConditionState(
            current: runtime.current(of: holder),
            maximums: runtime.maximums(of: holder),
            general: runtime.resolvedEntries(of: holder),
            generalBaseline: runtime.baseline(of: holder).basesByIndex
        )
        #expect(state.value(at: Self.health) == runtime.value(at: Self.health, on: holder))
        #expect(
            state.baseValue(at: Self.health) == runtime.baseValue(at: Self.health, on: holder)
        )
        #expect(state.fraction(at: Self.health) == runtime.fraction(at: Self.health, on: holder))
        #expect(
            state.value(at: Self.resistFire) == runtime.value(at: Self.resistFire, on: holder)
        )
        #expect(state.value(at: Self.outsideTable) == nil)
    }
}
