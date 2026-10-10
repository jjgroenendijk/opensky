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
    /// The fields no game system reads yet: models, sounds, links, scripts.
    public let details: ArmorDetails
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        var rest = try RecordFields(record: record, type: "ARMO", localized: localized)
        formID = rest.formID

        var editorID: String?
        var name: LString?
        var race: FormID?
        var bodyTemplate: BodyTemplate?
        var armatures: [FormID] = []
        var keywords = KeywordList()
        var payload = ArmorInventoryFields()
        try rest.readEach { field in
            if try keywords.decode(field: field) {
                return true
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
                guard field.data.count == 4 else { return true }
                try armatures.append(FormID(reader.readUInt32()))
            default:
                // Inventory fields live in their own decoder so this switch
                // stays inside the strict-lint complexity cap.
                return try payload.decode(field: field)
            }
            return true
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
        details = ArmorDetails(&rest)
        skipped = rest.finish()
    }

    /// DATA (shared 8-byte value + weight), DNAM (armor rating * 100) and
    /// EITM (the ENCH link).
    private struct ArmorInventoryFields {
        var itemValue = ItemValue.zero
        var armorRating: UInt32 = 0
        var enchantment: FormID?

        mutating func decode(field: ESMField) throws -> Bool {
            switch field.type {
            case "DATA":
                itemValue = try ItemValue(field: field)
            case "DNAM":
                guard field.data.count >= 4 else { return true }
                var reader = BinaryReader(field.data)
                armorRating = try reader.readUInt32()
            case "EITM":
                enchantment = try InventoryItemFields.optionalFormID(field)
            default:
                return false
            }
            return true
        }
    }
}

/// ARMO fields beyond what equipping and rendering read. xEdit dev-4.1.6 names
/// each one; docs/formats/armor.md.
nonisolated public struct ArmorDetails: Equatable, Sendable {
    public let bounds: ObjectBounds?
    /// DESC — inventory description.
    public let description: LString?
    /// MOD2 group with ICON/MICO — the male ground model and its icons.
    public let maleWorldModel: ModelData?
    public let maleIconPath: String?
    public let maleMessageIconPath: String?
    /// MOD4 group with ICO2/MIC2 — the female ground model and its icons.
    public let femaleWorldModel: ModelData?
    public let femaleIconPath: String?
    public let femaleMessageIconPath: String?
    /// TNAM — the ARMO this one copies its look and stats from.
    public let template: FormID?
    /// YNAM/ZNAM — pickup and drop sounds.
    public let pickupSound: FormID?
    public let dropSound: FormID?
    /// BMCT — ragdoll constraint template path.
    public let ragdollConstraintTemplate: String?
    public let equipType: FormID?
    /// BIDS — the IPDS a shield bash plays.
    public let bashImpactDataSet: FormID?
    /// BAMT — the MATT a block hits instead of the armor's own.
    public let alternateBlockMaterial: FormID?
    public let destructible: Destructible?
    public let scriptData: ScriptData

    init(_ fields: inout RecordFields) {
        bounds = fields.bounds()
        description = fields.lstring("DESC")
        maleWorldModel = fields.model(path: "MOD2", hashes: "MO2T", alternates: "MO2S")
        maleIconPath = fields.zstring("ICON")
        maleMessageIconPath = fields.zstring("MICO")
        femaleWorldModel = fields.model(path: "MOD4", hashes: "MO4T", alternates: "MO4S")
        femaleIconPath = fields.zstring("ICO2")
        femaleMessageIconPath = fields.zstring("MIC2")
        template = fields.formID("TNAM")
        pickupSound = fields.formID("YNAM")
        dropSound = fields.formID("ZNAM")
        ragdollConstraintTemplate = fields.zstring("BMCT")
        equipType = fields.formID("ETYP")
        bashImpactDataSet = fields.formID("BIDS")
        alternateBlockMaterial = fields.formID("BAMT")
        destructible = fields.destructible()
        scriptData = fields.scriptData()
    }
}
