// How running effects end early: a death, a keyword dispel, and an enchantment's recast.
// Rules: docs/formats/magic-records.md, docs/formats/enchantments.md.

import Foundation
@testable import OpenSkyActors
@testable import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyWorldConditions
@testable import OpenSkyWorldState
import Testing

@MainActor
struct ActiveEffectEndingTests {
    private static let shield: UInt32 = 0x30
    private static let ward: UInt32 = 0x31
    private static let lasting: UInt32 = 0x32
    private static let keyword: UInt32 = 0x950

    private static func keywords(_ ids: [UInt32]) -> Data {
        var list = Data()
        for id in ids {
            list.appendUInt32(id)
        }
        var count = Data()
        count.appendUInt32(UInt32(ids.count))
        return ESMFixture.field("KWSZ", count) + ESMFixture.field("KWDA", list)
    }

    private static func runtime() throws -> ActiveEffectRuntime {
        let records = ActiveEffectFixture.effectRecords + [
            ActiveEffectFixture.magicEffect(
                formID: shield, editorID: "Shield", name: "Shield",
                data: ActiveEffectFixture.data(
                    flags: [.recover], primaryValue: ActorValueIndex.resistFire
                ),
                conditions: keywords([keyword])
            ),
            ActiveEffectFixture.magicEffect(
                formID: ward, editorID: "Ward", name: "Ward",
                data: ActiveEffectFixture.data(
                    flags: [.recover, .dispelWithKeywords],
                    primaryValue: ActorValueIndex.resistFrost
                ),
                conditions: keywords([keyword])
            ),
            ActiveEffectFixture.magicEffect(
                formID: lasting, editorID: "Lasting", name: "Lasting",
                data: ActiveEffectFixture.data(
                    flags: [.recover, .noDeathDispel], primaryValue: ActorValueIndex.resistFire
                )
            )
        ]
        let store = WorldStateStore()
        let values = ActorValueRuntime(store: store, baselines: ActorValueBaselineFixture.flat())
        let file = try ActiveEffectFixture.plugin(records: records)
        return ActiveEffectRuntime(
            values: values, effects: MagicEffectStore(plugins: [("Base.esm", file)]),
            conditions: ConditionContext(functions: .standard)
        )
    }

    private static func entry(_ effect: UInt32) -> MagicItemEffect {
        ActiveEffectFixture.entry(effect, magnitude: 10, duration: 30)
    }

    @Test func aDeathEndsEveryEffectWithoutNoDeathDispel() throws {
        var runtime = try Self.runtime()
        ActiveEffectFixture.apply(&runtime, [Self.entry(Self.shield), Self.entry(Self.lasting)])
        #expect(runtime.dispelOnDeath(of: .player) == 1)
        #expect(runtime.active(on: .player).count == 1)
    }

    @Test func dispelWithKeywordsEndsEffectsThatShareOne() throws {
        var runtime = try Self.runtime()
        ActiveEffectFixture.apply(&runtime, [Self.entry(Self.shield), Self.entry(Self.lasting)])
        ActiveEffectFixture.apply(&runtime, [Self.entry(Self.ward)])
        #expect(runtime.active(on: .player).count == 2)
        #expect(runtime.tally.dispelled == 1)
    }

    private static let enchantment = ActiveEffectSource(
        kind: .enchantment, record: .plugin(name: "base.esm", objectID: 0x600)
    )

    private static func strike(_ runtime: inout ActiveEffectRuntime) -> [ActiveEffect] {
        runtime.apply(
            [entry(shield)],
            fromPlugin: "Base.esm",
            source: enchantment,
            on: .player
        )
    }

    @Test func anExtendingEnchantmentRestartsItsEffect() throws {
        var runtime = try Self.runtime()
        runtime.application.enchantmentRecast = true
        _ = Self.strike(&runtime)
        runtime.elapse(seconds: 10, over: [.player])
        let again = Self.strike(&runtime)
        #expect(runtime.active(on: .player).count == 1)
        #expect(again.first?.elapsed == 0)
    }

    @Test func aPlainEnchantmentReplacesItsEffect() throws {
        var runtime = try Self.runtime()
        runtime.application.enchantmentRecast = false
        _ = Self.strike(&runtime)
        _ = Self.strike(&runtime)
        #expect(runtime.active(on: .player).count == 1)
        #expect(runtime.tally.dispelled == 1)
    }

    @Test func anyOtherSourceStacks() throws {
        var runtime = try Self.runtime()
        _ = Self.strike(&runtime)
        _ = Self.strike(&runtime)
        #expect(runtime.active(on: .player).count == 2)
    }
}
