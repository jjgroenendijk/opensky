// The archetype effects read projectile and enchantment records through the records port.

import Foundation
import OpenSkyEngineTesting
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyMagicAdapters
@testable import OpenSkyMagicInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct MagicRecordsTests {
    private let host = MagicHost()
    private var adapter: MagicWorldAdapter {
        MagicWorldAdapter(game: host)
    }

    private static let target = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let projectile: UInt32 = 0x0800

    private static let fireball = payload(projectile: FormID(projectile))

    private static func payload(projectile: FormID?) -> SpellPayload {
        SpellPayload(
            spell: .plugin(name: "base.esm", objectID: 0x600), sourcePlugin: "base.esm",
            caster: .player,
            entries: [], isHostile: true, ignoresResistance: false, projectile: projectile,
            name: "Fireball"
        )
    }

    /// PROJ DATA of the full 0x50 bytes, so the decoder reads the impact force at 0x34.
    private static func projectileStore(impactForce: Float) throws -> ItemDefinitionStore {
        var data = Data()
        data.appendUInt16(0)
        data.appendUInt16(0x01)
        data.appendUInt32(Float(0).bitPattern)
        data.appendUInt32(Float(3000).bitPattern)
        data.appendUInt32(Float(4000).bitPattern)
        data.append(Data(count: 0x34 - data.count))
        data.appendUInt32(impactForce.bitPattern)
        data.append(Data(count: 0x50 - data.count))
        let record = ESMFixture.record(
            "PROJ", formID: projectile, data: ESMFixture.field("DATA", data)
        )
        return try ItemDefinitionStore(file: ESMFixture.plugin(records: [record]))
    }

    private static func knockSettings(multiplier: Float) throws -> GameSettingStore {
        let file = try GameSettingFixture.plugin(
            editorID: "fProjectileKnockMultBiped", value: multiplier, formID: 0x0900
        )
        return GameSettingStore(plugins: [("base.esm", file)])
    }

    @Test func aProjectileWithForceKnocksEachTargetAway() throws {
        host.fakeCombat.items = try Self.projectileStore(impactForce: 10)
        let records = FakeWorldRecords()
        records.gameSettings = try Self.knockSettings(multiplier: 2)
        host.worldRecords = records
        adapter.knock([Self.target], awayFrom: .player, by: Self.fireball)
        let calls = host.fakeEffectsWorld.knockDownActorCalls
        #expect(calls.map(\.actor) == [Self.target])
        #expect(calls.first?.source == .player)
        #expect(abs((calls.first?.magnitude ?? 0) - 20) < 0.001)
    }

    @Test func noKnockWithoutTheSettingOrTheProjectile() throws {
        host.fakeCombat.items = try Self.projectileStore(impactForce: 10)
        host.worldRecords = FakeWorldRecords()
        adapter.knock([Self.target], awayFrom: .player, by: Self.fireball)
        adapter.knock([Self.target], awayFrom: .player, by: Self.payload(projectile: nil))
        let missing = Self.payload(projectile: FormID(0x0801))
        adapter.knock([Self.target], awayFrom: .player, by: missing)
        #expect(host.fakeEffectsWorld.knockDownActorCalls.isEmpty)
    }

    @Test func anEnchantmentWithAnUnloadedRestrictionListFitsEveryItem() throws {
        let record = EnchantmentFixture.record(
            formID: 0x42, editorID: "TestEnchWorn", name: "Worn",
            enit: EnchantmentFixture.enit(
                cost: 60, flags: 1, amount: 1500, wornRestrictions: 0x0A00
            ),
            effects: [.init(0x50, magnitude: 25)]
        )
        let file = try SpellStoreFixture.plugin(records: SpellStoreFixture.effectRecords + [record])
        let index = RecordIndex(plugins: [("base.esm", file)], recordTypes: ["MGEF", "ENCH"])
        let base = try #require(
            EnchantmentStore(index: index).resolve(FormID(0x42), fromPlugin: "base.esm")
        )
        #expect(base.data?.wornRestrictions != nil)
        #expect(adapter.enchantment(base, fits: FormID(0x500)))
        let records = FakeWorldRecords()
        records.formListStore = FormListStore(plugins: [])
        records.locationKeywords = KeywordStore(plugins: [])
        host.worldRecords = records
        #expect(adapter.enchantment(base, fits: FormID(0x500)))
    }
}
