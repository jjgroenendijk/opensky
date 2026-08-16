// The general actor-value store (issue #468, roadmap item 19.5): reads of an
// untouched value, the base-and-modifiers round trips, the record-derived
// baselines, and the resistance query with its cap.
//
// Records are synthetic and built in code (ESMFixture) — never extracted game
// files (AGENTS.md "Legal & IP boundary"). Layouts: UESP "Skyrim Mod:Mod File
// Format" RACE, CLAS and NPC_ pages; see docs/formats/actors.md.

import Foundation
@testable import opensky
import Testing

@MainActor
struct ActorValueGeneralStoreTests {
    private static let sneak: Int32 = 15
    private static let speedMult = ActorValueIndex.speedMult
    private static let carryWeight = ActorValueIndex.carryWeight
    private static let resistFire = ActorValueIndex.resistFire
    private static let resistMagic = ActorValueIndex.resistMagic
    private static let resistDisease = ActorValueIndex.resistDisease
    private static let damageResist = ActorValueIndex.damageResist
    /// One past the end of the vanilla table.
    private static let outsideTable: Int32 = 164

    private let actorKey = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BAC)

    private func runtime(
        general: [Int32: Float] = [:]
    ) -> (ActorValueRuntime, WorldStateStore) {
        let store = WorldStateStore()
        let baselines = ActorValueBaselineResolver(
            fallback: ActorValueBaseline(
                maximums: ActorValues(repeating: 100),
                regenPercentPerSecond: .zero,
                general: general
            )
        )
        return (ActorValueRuntime(store: store, baselines: baselines), store)
    }

    private func holder() -> ActorValueHolder {
        ActorValueHolder(key: actorKey, subject: .actor(base: FormID(0x0001_3BAC)))
    }

    // MARK: - Defaults

    /// Every index the vanilla table carries answers, and an index outside it
    /// is the only miss left.
    @Test func everyVanillaIndexReadsAndOnlyTheRestMisses() {
        let (runtime, store) = self.runtime()
        let holder = holder()
        for index in Int32(0) ..< 164 {
            #expect(runtime.value(at: index, on: holder) != nil)
        }
        #expect(runtime.value(at: Self.outsideTable, on: holder) == nil)
        #expect(runtime.value(at: ActorValueIdentity.noneIndex, on: holder) == nil)
        // Reading stores nothing: an actor nobody touched is still clean.
        #expect(store.dirtyCount == 0)
    }

    /// A skill reads the documented floor, everything else reads zero, and the
    /// three primaries still come off the typed triple.
    @Test func untouchedValuesReadTheirDocumentedDefaults() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        #expect(runtime.value(at: Self.sneak, on: holder) == 15)
        #expect(runtime.value(at: Self.resistFire, on: holder) == 0)
        #expect(runtime.value(at: 24, on: holder) == 100)
        #expect(runtime.baseValue(at: 24, on: holder) == 100)
    }

    /// A record-authored baseline wins over the table default, and is what the
    /// base value reports until something writes one.
    @Test func aRecordBaselineWinsOverTheTableDefault() {
        let (runtime, _) = self.runtime(general: [Self.sneak: 25, Self.speedMult: 100])
        let holder = holder()
        #expect(runtime.value(at: Self.sneak, on: holder) == 25)
        #expect(runtime.baseValue(at: Self.sneak, on: holder) == 25)
        #expect(runtime.value(at: Self.speedMult, on: holder) == 100)
    }

    // MARK: - Round trips

    @Test func setDamageAndRestoreRoundTripOnANonPrimaryValue() {
        let (runtime, store) = self.runtime()
        let holder = holder()
        #expect(runtime.setValue(at: Self.resistFire, to: 60, on: holder))
        #expect(runtime.value(at: Self.resistFire, on: holder) == 60)
        #expect(store.dirtyCount == 1)

        #expect(runtime.damage(at: Self.resistFire, by: 25, on: holder))
        #expect(runtime.value(at: Self.resistFire, on: holder) == 35)
        // Damage moves the damage modifier, never the base.
        #expect(runtime.baseValue(at: Self.resistFire, on: holder) == 60)

        // Restoring more than was taken stops at the base rather than climbing
        // past it.
        #expect(runtime.restore(at: Self.resistFire, by: 500, on: holder))
        #expect(runtime.value(at: Self.resistFire, on: holder) == 60)
        #expect(runtime.entry(at: Self.resistFire, on: holder) == ActorValueEntry(base: 60))
    }

    @Test func damageFloorsAtZeroAndModifiersStack() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.setValue(at: Self.resistFire, to: 30, on: holder)
        runtime.addModifier(20, to: .temporary, at: Self.resistFire, on: holder)
        runtime.addModifier(10, to: .permanent, at: Self.resistFire, on: holder)
        #expect(runtime.value(at: Self.resistFire, on: holder) == 60)
        // Damage stops at zero rather than making the value negative.
        runtime.damage(at: Self.resistFire, by: 500, on: holder)
        #expect(runtime.value(at: Self.resistFire, on: holder) == 0)
        // The base and the two other modifiers survived it.
        let entry = runtime.entry(at: Self.resistFire, on: holder)
        #expect(entry?.base == 30)
        #expect(entry?.temporary == 20)
        #expect(entry?.permanent == 10)
        #expect(entry?.damage == -60)
    }

    /// A value moved back to its baseline is dropped rather than kept at its
    /// default, so an actor nothing happened to stops being dirty in the sense
    /// the save cares about.
    @Test func aValueBackAtItsBaselineIsDropped() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        runtime.setValue(at: Self.resistFire, to: 20, on: holder)
        #expect(runtime.state(of: holder).general.count == 1)
        runtime.setValue(at: Self.resistFire, to: 0, on: holder)
        #expect(runtime.state(of: holder).general.isEmpty)
    }

    /// The primaries keep the typed fast path: an index-addressed damage on
    /// health is the same write `damage(_:by:on:)` makes, and they have no
    /// modifier slots.
    @Test func thePrimariesRouteToTheTypedPath() {
        let (runtime, _) = self.runtime()
        let holder = holder()
        #expect(runtime.damage(at: 24, by: 40, on: holder))
        #expect(runtime.current(of: holder).health == 60)
        #expect(runtime.value(at: 24, on: holder) == 60)
        #expect(runtime.state(of: holder).general.isEmpty)
        #expect(!runtime.addModifier(5, to: .temporary, at: 24, on: holder))
        #expect(runtime.entry(at: 24, on: holder) == nil)
    }

    @Test func anIndexOutsideTheTableWritesNothing() {
        let (runtime, store) = self.runtime()
        let holder = holder()
        #expect(!runtime.setValue(at: Self.outsideTable, to: 50, on: holder))
        #expect(!runtime.damage(at: Self.outsideTable, by: 5, on: holder))
        #expect(store.dirtyCount == 0)
    }

    // MARK: - Resistances

    /// "The cap only applies to you; followers and enemies with 100%
    /// resistance are truly immune."
    /// (<https://en.uesp.net/wiki/Skyrim:Resist_Magic>)
    @Test func thePlayerCapAppliesToThePlayerAlone() {
        let (runtime, _) = self.runtime()
        let bandit = holder()
        runtime.setValue(at: Self.resistFire, to: 100, on: bandit)
        #expect(runtime.resistanceFraction(at: Self.resistFire, on: bandit) == 1)

        runtime.setValue(at: Self.resistFire, to: 100, on: .player)
        #expect(runtime.resistanceFraction(at: Self.resistFire, on: .player) == 0.85)
        // Under the cap the value passes through unchanged.
        runtime.setValue(at: Self.resistFire, to: 40, on: .player)
        #expect(runtime.resistanceFraction(at: Self.resistFire, on: .player) == 0.4)
    }

    /// "Resist Disease 100% provides disease immunity."
    /// (<https://en.uesp.net/wiki/Skyrim:Resist_Disease>) — not capped at 85.
    @Test func resistDiseaseIsNotCappedAtTheEightyFivePercentLine() {
        let (runtime, _) = self.runtime()
        runtime.setValue(at: Self.resistDisease, to: 100, on: .player)
        #expect(runtime.resistanceFraction(at: Self.resistDisease, on: .player) == 1)
    }

    /// `Damage Resist` is an armor rating, not a percentage, so the percentage
    /// query refuses it rather than reading 40 armor as 40% resistance.
    @Test func damageResistIsNotAPercentageResistance() {
        let (runtime, _) = self.runtime()
        runtime.setValue(at: Self.damageResist, to: 40, on: .player)
        #expect(runtime.resistanceFraction(at: Self.damageResist, on: .player) == nil)
        #expect(runtime.resistanceFraction(at: Self.sneak, on: .player) == nil)
    }

    /// UESP's own worked example: "a 100-point Fire Damage spell would deal
    /// only 15 points of damage with Resist Magic 85%; Resist Fire 85% would
    /// then reduce the 15 points by a further 85% to 2.25 points of final
    /// damage" (<https://en.uesp.net/wiki/Skyrim:Resist_Magic>).
    @Test func resistMagicAppliesBeforeTheElementalResistance() {
        let (runtime, _) = self.runtime()
        runtime.setValue(at: Self.resistMagic, to: 85, on: .player)
        runtime.setValue(at: Self.resistFire, to: 85, on: .player)
        let damage = 100 * runtime.magicDamageMultiplier(element: Self.resistFire, on: .player)
        #expect(abs(damage - 2.25) < 0.0001)
        // An effect that names Resist Magic as its own resistance pays it once,
        // not twice.
        let magicOnly = 100 * runtime.magicDamageMultiplier(element: Self.resistMagic, on: .player)
        #expect(abs(magicOnly - 15) < 0.0001)
        // An effect that names no resistance still pays Resist Magic.
        let unnamed = 100 * runtime.magicDamageMultiplier(element: nil, on: .player)
        #expect(abs(unnamed - 15) < 0.0001)
    }

    @Test func anActorThatResistsNothingTakesFullDamage() {
        let (runtime, _) = self.runtime()
        #expect(runtime.magicDamageMultiplier(element: Self.resistFire, on: holder()) == 1)
    }
}
