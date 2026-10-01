// ARMO record: one equippable piece. Its visible parts come from the ARMA
// records it lists; here MODL is a 4-byte ARMA FormID, not a model path.
// Armor has an EITM enchantment but no charge field, unlike WEAP.
// Layout and sources: docs/formats/armor.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Armor: Sendable {
    public let formID: FormID
    public let editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    public let name: LString?
    /// RNAM — race the piece fits / filters against (0x19 DefaultRace usually).
    public let race: FormID?
    /// BOD2/BODT biped slots + armor type; nil when absent.
    public let bodyTemplate: BodyTemplate?
    /// MODL armature list: ARMA FormIDs that supply the worn geometry.
    public let armatures: [FormID]
    /// DATA — gold value and carry weight.
    public let itemValue: ItemValue
    /// KSIZ/KWDA keyword array (material, vendor and set keywords).
    public let keywords: KeywordList
    /// DNAM — base armor rating * 100; only the low 16 bits are meaningful.
    public let armorRating: UInt32
    /// EITM — ENCH applied while the piece is worn; nil when unenchanted.
    public let enchantment: FormID?

    public init(record: ESMRecord, localized: Bool) throws {
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
