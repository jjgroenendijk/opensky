// The MGEF taper from docs/engine/magic.md, Tapering: the share after the duration,
// the payouts it gives, and the planner reading it from the record.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import Testing

@MainActor
struct EffectTaperTests {
    private let taper = EffectTaper(weight: 0.5, curve: 1, duration: 4)

    @Test func theShareFallsAlongTheCurve() {
        #expect(taper.share(after: 0) == 1)
        #expect(taper.share(after: 1) == 0.375)
        #expect(taper.share(after: 2) == 0.25)
        #expect(taper.share(after: 4) == 0)
        #expect(EffectTaper.none.share(after: 1) == 0)
        let growing = EffectTaper(weight: 1, curve: -1, duration: 4)
        #expect(growing.share(after: 2) == 2)
        #expect(EffectTaper(weight: .nan, curve: .infinity, duration: -3) == .none)
    }

    @Test func aTaperedEffectLivesLongerAndPaysLess() {
        let effect = ActiveEffect(
            sequence: 1,
            source: ActiveEffectSource(kind: .spell, record: .player),
            effect: .player,
            mode: .perSecond,
            isDetrimental: true,
            duration: 5,
            taper: taper,
            values: [ActiveEffectValue(index: 24, magnitude: 10)]
        )
        #expect(effect.lifetime == 9)
        #expect(effect.remaining == 9)
        #expect(effect.payoutShare(ofSecond: 5) == 1)
        #expect(effect.payoutShare(ofSecond: 6) == 0.375)
        var moved = effect
        for _ in 0 ..< 7 {
            moved = moved.advanced(by: 1)
        }
        #expect(moved.unpaidSeconds == 7)
        #expect(!moved.isExpired)
        #expect(moved.advanced(by: 3).isExpired)
    }

    @Test func thePlannerReadsTheTaperFromTheRecord() throws {
        let record = ActiveEffectFixture.magicEffect(
            formID: 0x30, editorID: "TaperedDamage", name: "Tapered Damage",
            data: ActiveEffectFixture.data(
                flags: [.detrimental], archetype: 0, primaryValue: 24,
                taperWeight: 0.5, taperCurve: 1, taperDuration: 4
            )
        )
        let file = try ActiveEffectFixture.plugin(records: [record])
        let store = MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)])
        let resolved = try #require(store.effect(
            ResolvedFormID(plugin: ActiveEffectFixture.pluginName, objectID: 0x30)
        ))
        let outcome = MagicEffectPlanner.plan(
            effect: resolved,
            entry: MagicItemEffect(
                effect: FormID(0x30), magnitude: 10, area: 0, duration: 0,
                conditions: ConditionList()
            )
        )
        guard case let .apply(application) = outcome else {
            Issue.record("expected an application, got \(outcome)")
            return
        }
        #expect(application.taper == taper)
        #expect(!application.isInstant)
    }
}
