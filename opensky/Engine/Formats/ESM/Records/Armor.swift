// ARMO record decoded into engine types: the appearance subset for skinning.
// An ARMO is one equippable piece (armor, jewelry, clothing, shield); its
// visible parts come from the armatures it references, one ARMA per MODL. The
// item's own ground/inventory display models (MOD2/MOD4 world-model paths) are
// skipped.
//
// M19.3 adds EITM, the ENCH link that makes a piece enchanted, decoded the way
// WEAP decodes its own. There is no armor-side charge field to go with it:
// xEdit builds both records' link from `wbEnchantment`, and only WEAP asks for
// the capacity variant that adds EAMT (`wbEnchantment(True)`), so an enchanted
// piece of armor has an effect and no charge.
//
// M12.1.1 adds the inventory-facing half so ARMO can join the item definition
// index alongside the six carryable families: DATA (the shared 8-byte gold
// value + weight struct, `ItemValue`), the KSIZ/KWDA keyword array, and DNAM,
// the base armor rating stored as rating * 100.
//
// MODL in ARMO is a 4-byte FormID pointing at an ARMA record (NOT a model
// path — unlike STAT/MODL), repeated once per armature. Size-guard on 4 bytes
// so any non-armature MODL variant is skipped rather than misread.
//
// Reference: UESP "Skyrim Mod:Mod File Format/ARMO"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ARMO
// DATA/DNAM cross-check: xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas
//   `wbRecord(ARMO, ...)` line 4136.

import Foundation

nonisolated struct Armor {
    let formID: FormID
    let editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    let name: LString?
    /// RNAM — race the piece fits / filters against (0x19 DefaultRace usually).
    let race: FormID?
    /// BOD2/BODT biped slots + armor type; nil when absent.
    let bodyTemplate: BodyTemplate?
    /// MODL armature list: ARMA FormIDs that supply the worn geometry.
    let armatures: [FormID]
    /// DATA — gold value and carry weight.
    let itemValue: ItemValue
    /// KSIZ/KWDA keyword array (material, vendor and set keywords).
    let keywords: KeywordList
    /// DNAM — base armor rating * 100; only the low 16 bits are meaningful.
    let armorRating: UInt32
    /// EITM — ENCH applied while the piece is worn; nil when unenchanted.
    let enchantment: FormID?

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "ARMO" else {
            throw ESMError.malformed("expected ARMO record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var race: FormID?
        var bodyTemplate: BodyTemplate?
        var armatures: [FormID] = []
        var keywords = KeywordList()
        var payload = ArmorInventoryFields()
        for field in try record.fields() {
            if try keywords.decode(field: field) {
                continue
            }
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "RNAM":
                race = try FormID(reader.readUInt32())
            case "BOD2":
                bodyTemplate = try BodyTemplate(bod2: field)
            case "BODT":
                bodyTemplate = try BodyTemplate(bodt: field)
            case "MODL":
                guard field.data.count == 4 else { break }
                try armatures.append(FormID(reader.readUInt32()))
            default:
                // Inventory fields live in their own decoder so this switch
                // stays inside the strict-lint complexity cap.
                try payload.decode(field: field)
            }
        }
        self.editorID = editorID
        self.name = name
        self.race = race
        self.bodyTemplate = bodyTemplate
        self.armatures = armatures
        itemValue = payload.itemValue
        self.keywords = keywords
        armorRating = payload.armorRating
        enchantment = payload.enchantment
    }

    /// DATA (shared 8-byte value + weight), DNAM (armor rating * 100) and
    /// EITM (the ENCH link).
    private struct ArmorInventoryFields {
        var itemValue = ItemValue.zero
        var armorRating: UInt32 = 0
        var enchantment: FormID?

        mutating func decode(field: ESMField) throws {
            switch field.type {
            case "DATA":
                itemValue = try ItemValue(field: field)
            case "DNAM":
                guard field.data.count >= 4 else { return }
                var reader = BinaryReader(field.data)
                armorRating = try reader.readUInt32()
            case "EITM":
                enchantment = try InventoryItemFields.optionalFormID(field)
            default:
                break
            }
        }
    }
}
