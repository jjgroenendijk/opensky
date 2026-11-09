// The perks a running magic effect applies, from its MGEF "Perk to Apply" link.
// Records are synthetic and built in code.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyMagicInterface
import Testing

@MainActor
struct ActiveEffectPerksTests {
    private static let linked: UInt32 = 0x30
    private static let unlinked: UInt32 = 0x31
    private static let perk: UInt32 = 0x800
    /// The word of MGEF DATA that holds "Perk to Apply" (docs/formats/magic-records.md).
    private static let perkWord = 34

    private static func effectData(perk: UInt32) -> Data {
        var data = ActiveEffectFixture.data()
        var link = Data()
        link.appendUInt32(perk)
        data.replaceSubrange(perkWord * 4 ..< perkWord * 4 + 4, with: link)
        return data
    }

    private static func stores() throws -> (MagicEffectStore, PerkStore) {
        let name = ActiveEffectFixture.pluginName
        let effects = try ActiveEffectFixture.plugin(records: [
            ActiveEffectFixture.magicEffect(
                formID: linked, editorID: "RestedEffect", name: "Rested",
                data: effectData(perk: perk)
            ),
            ActiveEffectFixture.magicEffect(
                formID: unlinked, editorID: "PlainEffect", name: "Plain",
                data: ActiveEffectFixture.data()
            )
        ])
        let perks = try PerkFixture.plugin(perks: [
            PerkFixture.perkRecord(
                formID: perk, fields: PerkFixture.fields(editorID: "Rested", name: "Rested")
            )
        ])
        return (MagicEffectStore(plugins: [(name, effects)]), PerkStore(plugins: [(name, perks)]))
    }

    private static func active(_ formID: UInt32, sequence: UInt64) -> ActiveEffect {
        let name = ActiveEffectFixture.pluginName
        return ActiveEffect(
            sequence: sequence,
            source: ActiveEffectSource(kind: .spell, record: .plugin(name: name, objectID: 0x600)),
            effect: ReferenceKey(resolved: ResolvedFormID(plugin: name, objectID: formID)),
            mode: .modifier,
            isDetrimental: false,
            duration: 10,
            values: []
        )
    }

    @Test func onlyAnEffectWithAPerkLinkAppliesItsPerk() throws {
        let (effects, perks) = try Self.stores()
        let granted = ActiveEffectPerks.perks(
            of: [Self.active(Self.linked, sequence: 1), Self.active(Self.unlinked, sequence: 2)],
            effects: effects, perks: perks
        )
        let name = ActiveEffectFixture.pluginName
        #expect(granted == [ReferenceKey(resolved: ResolvedFormID(
            plugin: name,
            objectID: Self.perk
        ))])
    }

    @Test func noRunningEffectAppliesNoPerk() throws {
        let (effects, perks) = try Self.stores()
        #expect(ActiveEffectPerks.perks(of: [], effects: effects, perks: perks).isEmpty)
    }
}
