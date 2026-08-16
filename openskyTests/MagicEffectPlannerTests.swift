// Archetype dispatch (issue #469, roadmap item 19.6): what each implemented
// archetype resolves to, and which reason every other entry is counted under.
//
// Records are synthetic and built in code (`ActiveEffectFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary"). Layouts: UESP
// "Skyrim Mod:Mod File Format/MGEF"; semantics: the Creation Kit wiki's Magic
// Effect page, cited at the planner.

import Foundation
@testable import opensky
import Testing

@MainActor
struct MagicEffectPlannerTests {
    private func store() throws -> MagicEffectStore {
        let file = try ActiveEffectFixture.plugin(records: ActiveEffectFixture.effectRecords)
        return MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)])
    }

    private func resolved(_ formID: UInt32) throws -> ResolvedMagicEffect {
        try #require(store().effect(
            ResolvedFormID(plugin: ActiveEffectFixture.pluginName, objectID: formID)
        ))
    }

    private func entry(
        _ formID: UInt32,
        magnitude: Float,
        duration: UInt32 = 0
    ) -> MagicItemEffect {
        MagicItemEffect(
            effect: FormID(formID),
            magnitude: magnitude,
            area: 0,
            duration: duration,
            conditions: ConditionList()
        )
    }

    /// A zero-duration value modifier is an instant application of the whole
    /// magnitude to the actor value the record names.
    @Test func valueModifierWithNoDurationPlansOneInstantValue() throws {
        let outcome = try MagicEffectPlanner.plan(
            effect: resolved(ActiveEffectFixture.restoreHealth),
            entry: entry(ActiveEffectFixture.restoreHealth, magnitude: 25)
        )
        guard case let .apply(application) = outcome else {
            Issue.record("expected an application, got \(outcome)")
            return
        }
        #expect(application.isInstant)
        #expect(application.isDetrimental == false)
        #expect(application.values.count == 1)
        #expect(application.values[0].index == 24)
        #expect(application.values[0].magnitude == 25)
    }

    /// The Detrimental flag decides direction, not the magnitude's sign — the
    /// record always authors a positive number.
    @Test func detrimentalFlagSurvivesPlanning() throws {
        let outcome = try MagicEffectPlanner.plan(
            effect: resolved(ActiveEffectFixture.damageHealth),
            entry: entry(ActiveEffectFixture.damageHealth, magnitude: 8)
        )
        guard case let .apply(application) = outcome else {
            Issue.record("expected an application, got \(outcome)")
            return
        }
        #expect(application.isDetrimental)
        #expect(application.values[0].magnitude == 8)
    }

    /// Recover set plus a duration is the held-modifier behaviour; Recover
    /// clear is the per-second one.
    @Test func recoverFlagSelectsTheMode() throws {
        let held = try MagicEffectPlanner.plan(
            effect: resolved(ActiveEffectFixture.fortifyResistFire),
            entry: entry(ActiveEffectFixture.fortifyResistFire, magnitude: 20, duration: 60)
        )
        let paid = try MagicEffectPlanner.plan(
            effect: resolved(ActiveEffectFixture.damageHealth),
            entry: entry(ActiveEffectFixture.damageHealth, magnitude: 2, duration: 10)
        )
        guard
            case let .apply(heldApplication) = held,
            case let .apply(paidApplication) = paid
        else {
            Issue.record("expected two applications")
            return
        }
        #expect(heldApplication.mode == .modifier)
        #expect(paidApplication.mode == .perSecond)
    }

    /// "The first value is modified by <MAG>, the second value is modified by
    /// <MAG> * AV Weight" — Creation Kit wiki, Effect Archetypes.
    @Test func dualValueModifierScalesTheSecondValueByItsWeight() throws {
        let outcome = try MagicEffectPlanner.plan(
            effect: resolved(ActiveEffectFixture.dualResist),
            entry: entry(ActiveEffectFixture.dualResist, magnitude: 10, duration: 30)
        )
        guard case let .apply(application) = outcome else {
            Issue.record("expected an application, got \(outcome)")
            return
        }
        #expect(application.values.count == 2)
        #expect(application.values[0].index == ActorValueIndex.resistFire)
        #expect(application.values[0].magnitude == 10)
        #expect(application.values[1].index == ActorValueIndex.resistFrost)
        #expect(application.values[1].magnitude == 5)
    }

    /// A Peak Value Modifier carries its no-stack keyword; nothing else does.
    @Test func peakValueModifierCarriesItsStackKeyword() throws {
        let peak = try MagicEffectPlanner.plan(
            effect: resolved(ActiveEffectFixture.peakResist),
            entry: entry(ActiveEffectFixture.peakResist, magnitude: 10, duration: 30),
            resolveKeyword: { link in
                ReferenceKey.plugin(
                    name: ActiveEffectFixture.pluginName.lowercased(),
                    objectID: link.objectID
                )
            }
        )
        let plain = try MagicEffectPlanner.plan(
            effect: resolved(ActiveEffectFixture.fortifyResistFire),
            entry: entry(ActiveEffectFixture.fortifyResistFire, magnitude: 10, duration: 30),
            resolveKeyword: { _ in ReferenceKey.plugin(name: "base.esm", objectID: 1) }
        )
        guard
            case let .apply(peakApplication) = peak,
            case let .apply(plainApplication) = plain
        else {
            Issue.record("expected two applications")
            return
        }
        #expect(peakApplication.stackKeyword != nil)
        #expect(plainApplication.stackKeyword == nil)
    }

    /// Every archetype this milestone does not implement is counted rather than
    /// approximated.
    @Test func unimplementedArchetypeIsCountedNotApplied() throws {
        let outcome = try MagicEffectPlanner.plan(
            effect: resolved(ActiveEffectFixture.paralyze),
            entry: entry(ActiveEffectFixture.paralyze, magnitude: 1, duration: 10)
        )
        #expect(outcome == .skip(.unimplementedArchetype(.paralysis)))
    }

    /// A held modifier on health has nowhere to go until the primaries get the
    /// base-plus-modifiers storage item 19.5 left them without.
    @Test func timedRecoverEffectOnAPrimaryIsCountedUnsupported() throws {
        let file = try ActiveEffectFixture.plugin(records: [
            ActiveEffectFixture.magicEffect(
                formID: 0x20, editorID: "FortifyHealth", name: "Fortify Health",
                data: ActiveEffectFixture.data(
                    flags: [.recover], archetype: 0, primaryValue: 24
                )
            )
        ])
        let store = MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)])
        let effect = try #require(store.effect(
            ResolvedFormID(plugin: ActiveEffectFixture.pluginName, objectID: 0x20)
        ))
        let outcome = MagicEffectPlanner.plan(
            effect: effect,
            entry: entry(0x20, magnitude: 25, duration: 60)
        )
        #expect(outcome == .skip(.unsupportedPrimaryModifier(24)))
    }

    /// A record naming no actor value acts on nothing and says so.
    @Test func effectNamingNoActorValueIsCounted() throws {
        let file = try ActiveEffectFixture.plugin(records: [
            ActiveEffectFixture.magicEffect(
                formID: 0x21, editorID: "NoValue", name: "No Value",
                data: ActiveEffectFixture.data(archetype: 0, primaryValue: -1)
            )
        ])
        let store = MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)])
        let effect = try #require(store.effect(
            ResolvedFormID(plugin: ActiveEffectFixture.pluginName, objectID: 0x21)
        ))
        let outcome = MagicEffectPlanner.plan(effect: effect, entry: entry(0x21, magnitude: 5))
        #expect(outcome == .skip(.unaddressableValue(-1)))
    }
}
