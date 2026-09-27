// Every surface that names a perk: the PERK dump itself, and the three links
// that print a perk's name rather than a raw FormID — a spell's half-cost perk,
// a magic effect's perk to apply, and each box of an AVIF perk tree.

import Foundation
@testable import opensky
import Testing

struct PerkDumpTests {
    /// A dump names the perk a spell points at, which is one of the two links
    /// M19 decoded and deliberately left unresolved.
    @Test
    func spellDumpNamesItsHalfCostPerk() throws {
        let plugin = try PerkFixture.plugin(
            perks: [PerkFixture.perkRecord(
                formID: 0x80,
                fields: PerkFixture.fields(editorID: "DestructionNovice00", name: "Novice")
            )],
            spells: [PerkFixture.spellRecord(
                formID: 0x81,
                editorID: "Flames",
                name: "Flames",
                halfCostPerk: 0x80
            )]
        )
        let index = RecordIndex(
            plugins: [("Base.esm", plugin)],
            recordTypes: ["MGEF", "SPEL", "PERK"]
        )
        let record = try #require(index.records[
            ResolvedFormID(plugin: "Base.esm", objectID: 0x81)
        ]?.record)

        let dump = RecordTextDump.dump(
            record: record,
            localized: false,
            magicInspectorContext: context(index: index, perks: PerkStore(index: index))
        )

        #expect(dump.contains("half-cost perk Novice"))
    }

    /// Every AVIF perk-tree box now names the perk it grants, which is the
    /// link issue #494 left as a raw FormID.
    @Test
    func actorValueDumpNamesThePerkEachTreeNodeGrants() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("AVOneHanded"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("One-Handed"))
        fields += ESMFixture.field("CNAM", ActorValueInformationFixture.words([1]))
        fields += ESMFixture.field("AVSK", ActorValueInformationFixture.skillUse())
        fields += ActorValueInformationFixture.node(perk: 0, index: 0)
        fields += ActorValueInformationFixture.node(perk: 0x90, index: 1)
        let avif = ESMFixture.record("AVIF", formID: 0x91, data: fields)
        var data = ESMFixture.tes4()
        data += ESMFixture.topGroup("AVIF", contents: avif)
        data += ESMFixture.topGroup("PERK", contents: PerkFixture.perkRecord(
            formID: 0x90,
            fields: PerkFixture.fields(editorID: "Armsman00", name: "Armsman")
        ))
        let index = try RecordIndex(
            plugins: [("Base.esm", ESMFile(data: data))],
            recordTypes: ["AVIF", "PERK"]
        )
        let record = try #require(index.records[
            ResolvedFormID(plugin: "Base.esm", objectID: 0x91)
        ]?.record)

        let dump = RecordTextDump.dump(
            record: record,
            localized: false,
            magicInspectorContext: context(index: index, perks: PerkStore(index: index))
        )

        #expect(dump.contains("perk Armsman,"))
        #expect(dump.contains("#0 perk NULL"))
    }

    /// The other M19 link: the perk a magic effect applies.
    @Test
    func magicEffectDumpNamesThePerkItApplies() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("TestEffect"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Test Effect"))
        // MagicEffectFixture puts 0x20B in the DATA slot the perk link occupies.
        fields += ESMFixture.field("DATA", MagicEffectFixture.data())
        let plugin = try PerkFixture.plugin(
            perks: [PerkFixture.perkRecord(
                formID: 0x20B,
                fields: PerkFixture.fields(editorID: "PerkToApply", name: "Applied Perk")
            )],
            magicEffects: [ESMFixture.record("MGEF", formID: 0x82, data: fields)]
        )
        let index = RecordIndex(
            plugins: [("Base.esm", plugin)],
            recordTypes: ["MGEF", "SPEL", "PERK"]
        )
        let record = try #require(index.records[
            ResolvedFormID(plugin: "Base.esm", objectID: 0x82)
        ]?.record)

        let dump = RecordTextDump.dump(
            record: record,
            localized: false,
            magicInspectorContext: context(index: index, perks: PerkStore(index: index))
        )

        #expect(dump.contains("perk Applied Perk"))
    }

    /// A dump names the perk a spell and a magic effect point at, which is what
    /// closes the links M19 decoded and left unresolved.
    @Test
    func recordDumpNamesPerkLinksAndPerkEffects() throws {
        let plugin = try PerkFixture.plugin(perks: [PerkFixture.perkRecord(
            formID: 0x70,
            fields: PerkFixture.fields(
                editorID: "MagicPerk",
                name: "Apprentice Destruction",
                effects: [PerkFixture.entryPointEffect(
                    entryPoint: 38, // Mod Spell Cost
                    function: 3,
                    tabs: [(runOn: 0, conditions: [
                        DialogueFixture.condition(functionIndex: 448, comparisonValue: 1)
                    ])],
                    functionType: 1,
                    functionData: PerkFixture.float(0.5)
                )]
            )
        )])
        let index = RecordIndex(plugins: [("Base.esm", plugin)], recordTypes: ["PERK"])
        let store = PerkStore(index: index)
        let record = try PerkFixture.record(formID: 0x70, fields: PerkFixture.fields(
            editorID: "MagicPerk",
            name: "Apprentice Destruction",
            effects: [PerkFixture.entryPointEffect(
                entryPoint: 38,
                function: 3,
                tabs: [(runOn: 0, conditions: [
                    DialogueFixture.condition(functionIndex: 448, comparisonValue: 1)
                ])],
                functionType: 1,
                functionData: PerkFixture.float(0.5)
            )]
        ))

        let dump = RecordTextDump.dump(
            record: record,
            localized: false,
            magicInspectorContext: context(index: index, perks: store)
        )

        #expect(dump.contains("decoded PERK: editorID MagicPerk"))
        #expect(dump.contains("entry point Mod Spell Cost (38)"))
        #expect(dump.contains("function multiply value"))
        #expect(dump.contains("tab 0 (run on 0)"))
        #expect(dump.contains("0.5000"))
    }

    private func context(
        index: RecordIndex,
        perks: PerkStore
    ) -> RecordTextDump.MagicInspectorContext {
        RecordTextDump.MagicInspectorContext(
            keywordStore: KeywordStore(index: index),
            formListStore: FormListStore(index: index),
            magicEffectStore: MagicEffectStore(index: index),
            spellStore: SpellStore(index: index),
            enchantmentStore: EnchantmentStore(index: index),
            shoutStore: ShoutStore(index: index),
            equipSlotStore: EquipSlotStore(index: index),
            sourcePlugin: "Base.esm",
            perkStore: perks
        )
    }
}
