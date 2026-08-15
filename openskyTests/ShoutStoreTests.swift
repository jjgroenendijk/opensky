// ShoutStore link resolution and the shout-family text dump (issue #467).
// Synthetic plugins only; nothing here reads the game install.

import Foundation
@testable import opensky
import Testing

struct ShoutStoreTests {
    private enum Form {
        static let word1: UInt32 = 0x0A01
        static let word2: UInt32 = 0x0A02
        static let spell1: UInt32 = 0x0B01
        static let spell2: UInt32 = 0x0B02
        static let shout: UInt32 = 0x0C01
        static let leveledSpell: UInt32 = 0x0D01
        static let equipSlot: UInt32 = 0x0E01
        static let rightHand: UInt32 = 0x0E10
        static let leftHand: UInt32 = 0x0E11
    }

    @Test
    func theStoreJoinsEachShoutWordAgainstItsWordAndSpell() throws {
        let store = try ShoutStore(plugins: [("Base.esm", plugin())])

        #expect(store.shouts.count == 1)
        #expect(store.words.count == 2)
        let shout = try #require(store.shout(editorID: "FireBreath"))
        #expect(shout.displayName == "Fire Breath")
        #expect(shout.words.count == 3)
        #expect(shout.words[0].word?.editorID == "FireBreathWord1")
        #expect(shout.words[0].wordName == "Y3")
        #expect(shout.words[0].spell?.editorID == "FireBreathSpell1")
        #expect(shout.words[0].spellName == "Fire Breath I")
        #expect(shout.words[1].wordName == "Toor")
        // The third entry is the all-zero placeholder a shorter shout stores.
        #expect(shout.words[2].wordName == "NULL")
        #expect(shout.words[2].spellName == "NULL")
    }

    /// A word or spell link that names nothing in the load order stays visible
    /// as its raw FormID rather than disappearing from the join.
    @Test
    func adanglingWordLinkRemainsVisible() throws {
        let store = try ShoutStore(plugins: [("Base.esm", plugin(danglingWord: true))])
        let shout = try #require(store.shout(editorID: "FireBreath"))

        #expect(shout.words[0].word == nil)
        #expect(shout.words[0].wordName.hasPrefix("[UNRESOLVED]"))
    }

    @Test
    func theShoutDumpNamesItsWordsAndSpellsInsteadOfPrintingHex() throws {
        let file = try plugin()
        let dump = try dumpText(of: "SHOU", in: file)

        #expect(dump.contains("decoded SHOU: editorID FireBreath"))
        #expect(dump.contains("Y3 — spell Fire Breath I"))
        #expect(dump.contains("Toor — spell Fire Breath II"))
        #expect(!dump.contains("spell 00000B01"))
    }

    @Test
    func theWordLeveledSpellAndEquipSlotDumpsDecodeToo() throws {
        let file = try plugin()

        let word = try dumpText(of: "WOOP", in: file)
        #expect(word.contains("decoded WOOP: editorID FireBreathWord1"))
        #expect(word.contains("translation \"Yol\""))

        let list = try dumpText(of: "LVSP", in: file)
        #expect(list.contains("decoded LVSP: editorID LSpellFire"))
        #expect(list.contains("level 1 — Fire Breath I"))

        let slot = try dumpText(of: "EQUP", in: file)
        #expect(slot.contains("decoded EQUP: editorID BothHands"))
        #expect(slot.contains("parents [LeftHand, RightHand]"))
        #expect(slot.contains("use all parents true"))
        #expect(slot.contains("hands both"))
    }

    /// Without a magic context the summaries still decode; the links print as
    /// raw FormIDs rather than being dropped.
    @Test
    func theDumpStillDecodesWithoutAMagicContext() throws {
        let file = try plugin()
        let record = try SpellStoreFixture.firstRecord(type: "SHOU", in: file)

        let dump = RecordTextDump.dump(record: record, localized: false)

        #expect(dump.contains("decoded SHOU: editorID FireBreath"))
        #expect(dump.contains("00000A01 — spell 00000B01"))
    }

    private func dumpText(of type: String, in file: ESMFile) throws -> String {
        let index = RecordIndex(
            plugins: [("Base.esm", file)],
            recordTypes: RecordIndex.referenceRecordTypes
        )
        let effects = MagicEffectStore(index: index)
        let spells = SpellStore(index: index, effects: effects)
        return try RecordTextDump.dump(
            record: SpellStoreFixture.firstRecord(type: type, in: file),
            localized: false,
            magicInspectorContext: RecordTextDump.MagicInspectorContext(
                keywordStore: KeywordStore(index: index),
                formListStore: FormListStore(index: index),
                magicEffectStore: effects,
                spellStore: spells,
                enchantmentStore: EnchantmentStore(index: index, effects: effects),
                shoutStore: ShoutStore(index: index, spells: spells),
                equipSlotStore: EquipSlotStore(index: index),
                sourcePlugin: "Base.esm"
            )
        )
    }

    private func plugin(danglingWord: Bool = false) throws -> ESMFile {
        var records = SpellStoreFixture.effectRecords
        records.append(spell(Form.spell1, "FireBreathSpell1", "Fire Breath I"))
        records.append(spell(Form.spell2, "FireBreathSpell2", "Fire Breath II"))
        records.append(word(Form.word1, "FireBreathWord1", full: "Y3", translation: "Yol"))
        records.append(word(Form.word2, "FireBreathWord2", full: "Toor", translation: "Toor"))
        records.append(shoutRecord(firstWord: danglingWord ? 0xDEAD : Form.word1))
        records.append(leveledSpellRecord())
        records.append(equipSlotRecords())
        return try SpellStoreFixture.plugin(records: records)
    }

    private func spell(_ formID: UInt32, _ editorID: String, _ name: String) -> Data {
        ESMFixture.record(
            "SPEL",
            formID: formID,
            data: SpellStoreFixture.spellFields(
                editorID: editorID,
                name: name,
                spit: SpellFixture.spit(),
                effects: [SpellStoreFixture.EffectSpec(0x50, magnitude: 10)]
            )
        )
    }

    private func word(
        _ formID: UInt32,
        _ editorID: String,
        full: String,
        translation: String
    ) -> Data {
        ESMFixture.record(
            "WOOP",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("FULL", ESMFixture.zstring(full))
                + ESMFixture.field("TNAM", ESMFixture.zstring(translation))
        )
    }

    private func shoutRecord(firstWord: UInt32) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("FireBreath"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Fire Breath"))
        fields += ESMFixture.field("DESC", ESMFixture.zstring("Your voice is fire."))
        for entry in [
            ShoutFixture.WordSpec(word: firstWord, spell: Form.spell1, recovery: 20),
            ShoutFixture.WordSpec(word: Form.word2, spell: Form.spell2, recovery: 45),
            ShoutFixture.WordSpec(word: 0, spell: 0, recovery: 0)
        ] {
            fields += ESMFixture.field("SNAM", ShoutFixture.wordEntry(entry))
        }
        return ESMFixture.record("SHOU", formID: Form.shout, data: fields)
    }

    private func leveledSpellRecord() -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("LSpellFire"))
        fields += ESMFixture.field("LVLD", Data([0]))
        fields += ESMFixture.field("LVLF", Data([0x01]))
        fields += ESMFixture.field("LLCT", Data([2]))
        fields += ESMFixture.field(
            "LVLO", ShoutFixture.leveledEntry(level: 1, reference: Form.spell1)
        )
        fields += ESMFixture.field(
            "LVLO", ShoutFixture.leveledEntry(level: 20, reference: Form.spell2)
        )
        return ESMFixture.record("LVSP", formID: Form.leveledSpell, data: fields)
    }

    private func equipSlotRecords() -> Data {
        // BothHands first, so the dump test's "first EQUP in the group" is
        // the composite rather than a leaf.
        ESMFixture.record(
            "EQUP",
            formID: Form.equipSlot,
            data: EquipSlotFixture.fields(
                editorID: "BothHands",
                parents: [Form.leftHand, Form.rightHand],
                usesAllParents: true
            )
        )
            + ESMFixture.record(
                "EQUP",
                formID: Form.rightHand,
                data: EquipSlotFixture.fields(
                    editorID: "RightHand", parents: [], usesAllParents: false
                )
            )
            + ESMFixture.record(
                "EQUP",
                formID: Form.leftHand,
                data: EquipSlotFixture.fields(
                    editorID: "LeftHand", parents: [], usesAllParents: false
                )
            )
    }
}
