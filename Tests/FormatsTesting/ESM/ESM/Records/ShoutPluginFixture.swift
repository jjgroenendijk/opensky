// One synthetic plugin with the shout family of records, shared by the
// `ShoutStore` suites and the record-dump suites.

import Foundation
@testable import OpenSkyFormatsESM

public enum ShoutPluginFixture {
    public enum Form {
        public static let word1: UInt32 = 0x0A01
        public static let word2: UInt32 = 0x0A02
        public static let spell1: UInt32 = 0x0B01
        public static let spell2: UInt32 = 0x0B02
        public static let shout: UInt32 = 0x0C01
        public static let leveledSpell: UInt32 = 0x0D01
        public static let equipSlot: UInt32 = 0x0E01
        public static let rightHand: UInt32 = 0x0E10
        public static let leftHand: UInt32 = 0x0E11
    }

    /// Two words, two spells, one shout over them, a leveled spell, and three
    /// equip slots. `danglingWord` points the first word entry at nothing.
    public static func plugin(danglingWord: Bool = false) throws -> ESMFile {
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

    private static func spell(_ formID: UInt32, _ editorID: String, _ name: String) -> Data {
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

    private static func word(
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

    private static func shoutRecord(firstWord: UInt32) -> Data {
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

    private static func leveledSpellRecord() -> Data {
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

    private static func equipSlotRecords() -> Data {
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
