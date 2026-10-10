// The world-object fields of ModelBase: FLOR and TREE produce, FURN workbench
// data, TACT voice type, and the interaction keyword.
// Layout and sources: docs/formats/world-records.md.

import Foundation
import OpenSkyFormatsCore

/// FURN WBDT byte 0. An unknown byte keeps its value.
nonisolated public enum WorkbenchType: Equatable, Sendable {
    case none
    case createObject
    case smithingWeapon
    case enchanting
    case enchantingExperiment
    case alchemy
    case alchemyExperiment
    case smithingArmor
    case unknown(UInt8)

    private static let known: [WorkbenchType] = [
        .none, .createObject, .smithingWeapon, .enchanting,
        .enchantingExperiment, .alchemy, .alchemyExperiment, .smithingArmor
    ]

    public init(rawValue: UInt8) {
        self = Int(rawValue) < Self.known.count ? Self.known[Int(rawValue)] : .unknown(rawValue)
    }

    public var rawValue: UInt8 {
        if case let .unknown(value) = self {
            return value
        }
        return UInt8(Self.known.firstIndex(of: self) ?? 0)
    }
}

/// FURN WBDT: what kind of station this is and the skill it trains.
nonisolated public struct Workbench: Equatable, Sendable {
    public let benchType: WorkbenchType
    /// Actor-value index, or -1 for none. Kept raw so an unknown index survives.
    public let skillIndex: Int8

    public init(benchType: WorkbenchType, skillIndex: Int8) {
        self.benchType = benchType
        self.skillIndex = skillIndex
    }

    /// The skill name for an index in xEdit's `wbSkillEnum` range (6-23), else nil.
    public var skillName: String? {
        guard (6 ... 23).contains(skillIndex) else { return nil }
        return ActorValueIdentity.vanillaNames[Int(skillIndex)]
    }
}

/// FLOR and TREE produce: what a harvest yields, its sound, and the chance per season.
nonisolated public struct HarvestProduce: Equatable, Sendable {
    /// PFIG. An item or a LVLI; nil when null.
    public let ingredient: FormID?
    /// SNAM, an SNDR.
    public let harvestSound: FormID?
    /// PFPC: percent chance in spring, summer, fall, winter. Nil when absent.
    public let seasonalChance: [UInt8]?

    public init(ingredient: FormID?, harvestSound: FormID?, seasonalChance: [UInt8]?) {
        self.ingredient = ingredient
        self.harvestSound = harvestSound
        self.seasonalChance = seasonalChance
    }
}

/// The world-object fields one ModelBase field pass collects.
nonisolated struct ModelBaseWorldFields {
    var keywords = KeywordList()
    var interactionKeyword: FormID?
    var workbench: Workbench?
    var voiceType: FormID?
    private var ingredient: FormID?
    private var harvestSound: FormID?
    private var seasonalChance: [UInt8]?
    private var hasProduce = false

    var produce: HarvestProduce? {
        guard hasProduce else { return nil }
        return HarvestProduce(
            ingredient: ingredient,
            harvestSound: harvestSound,
            seasonalChance: seasonalChance
        )
    }

    /// Returns false when `field` is not a world-object field of `recordType`.
    mutating func decode(field: ESMField, recordType: FourCC) throws -> Bool {
        if try keywords.decode(field: field) {
            return true
        }
        var reader = BinaryReader(field.data)
        switch (field.type, recordType) {
        case ("KNAM", "ACTI"), ("KNAM", "FURN"):
            interactionKeyword = try InventoryItemFields.optionalFormID(field)
        case ("WBDT", "FURN"):
            workbench = try Workbench(
                benchType: WorkbenchType(rawValue: reader.readUInt8()),
                skillIndex: Int8(bitPattern: reader.readUInt8())
            )
        case ("VNAM", "TACT"):
            voiceType = try InventoryItemFields.optionalFormID(field)
        case ("PFIG", "FLOR"), ("PFIG", "TREE"):
            ingredient = try Self.link(field)
            hasProduce = true
        case ("SNAM", "FLOR"), ("SNAM", "TREE"):
            harvestSound = try Self.link(field)
            hasProduce = true
        case ("PFPC", "FLOR"), ("PFPC", "TREE"):
            seasonalChance = try (0 ..< 4).map { _ in try reader.readUInt8() }
            hasProduce = true
        default:
            return false
        }
        return true
    }

    /// A link that must be 4 bytes; a short one is malformed, not null.
    private static func link(_ field: ESMField) throws -> FormID? {
        guard field.data.count >= 4 else {
            throw ESMError.malformed("\(field.type) has \(field.data.count) bytes, expected 4")
        }
        return try InventoryItemFields.optionalFormID(field)
    }
}
