// The health a spell takes before it lands: its harmful Health value modifiers count,
// and a helpful one does not.

import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import Testing

@MainActor
struct SpellHealthDamageTests {
    private static let harm: UInt32 = 0x80
    private static let heal: UInt32 = 0x81

    private static func coordinator() throws -> MagicCoordinator {
        let file = try ActiveEffectFixture.plugin(records: [
            SpellbookFixture.magicEffect(
                formID: harm, editorID: "FireDamage",
                data: ActiveEffectFixture.data(flags: [.hostile, .detrimental])
            ),
            SpellbookFixture.magicEffect(
                formID: heal, editorID: "RestoreHealth", data: ActiveEffectFixture.data()
            )
        ])
        var data = MagicSessionData()
        data.effects = MagicEffectsData(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)]),
            pluginName: ActiveEffectFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        return MagicCoordinator(world: FakeMagicWorld(), data: data)
    }

    private static func spell(_ entries: [(UInt32, Float)]) -> SpellPayload {
        SpellPayload(
            spell: .plugin(name: "base.esm", objectID: 0x610),
            sourcePlugin: ActiveEffectFixture.pluginName, caster: .player,
            entries: entries.map {
                MagicItemEffect(effect: FormID($0.0), magnitude: $0.1, area: 0, duration: 0)
            },
            isHostile: true, ignoresResistance: false, projectile: nil, name: "Firebolt"
        )
    }

    @Test func onlyHarmfulHealthEffectsCount() throws {
        let coordinator = try Self.coordinator()
        #expect(coordinator.healthDamage(of: Self.spell([(Self.harm, 40), (Self.harm, 5)])) == 45)
        #expect(coordinator.healthDamage(of: Self.spell([(Self.heal, 40)])) == 0)
        #expect(coordinator.healthDamage(of: Self.spell([(Self.harm, -.infinity)])) == 0)
    }
}
