// CLAS record: the attribute and skill weights that spread an auto-calc actor's
// per-level points, and the bleedout ratio. Trainer fields are skipped.
// Named `CharacterClass` because `Class` reads badly at every use site.
// Reference: UESP "Skyrim Mod:Mod File Format/CLAS".
// Layout documented in docs/formats/actors.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct CharacterClass: Equatable, Sendable {
    /// DATA 0x20 / 0x21 / 0x22: "Each byte provides the weight assigned to
    /// that attribute. The weights are used to distribute the fixed 10
    /// attribute points per level among the three attributes." (UESP CLAS)
    public struct AttributeWeights: Equatable, Sendable {
        public var health: UInt8 = 0
        public var magicka: UInt8 = 0
        public var stamina: UInt8 = 0

        public init(health: UInt8 = 0, magicka: UInt8 = 0, stamina: UInt8 = 0) {
            self.health = health
            self.magicka = magicka
            self.stamina = stamina
        }

        public var sum: Int {
            Int(health) + Int(magicka) + Int(stamina)
        }
    }

    /// DATA 0x06 – 0x17: "Each byte provides the weight assigned to one skill.
    /// The skills are provided in actor value index order (skill at byte 06 is
    /// One-handed; at byte 17, Enchanting) ... The weights are used to
    /// distribute the fixed 8 skill points per level among the various skills.
    /// Skills with a weight of zero never increase." (UESP CLAS)
    public struct SkillWeights: Equatable, Sendable {
        /// Actor-value index of the first weight byte, `One-Handed`.
        public static let firstActorValue: Int32 = 6
        /// How many weight bytes DATA carries, one per skill.
        public static let count = 18

        /// One weight per skill, in actor-value index order from
        /// `firstActorValue`. Empty when DATA was too short to reach them.
        public var weights: [UInt8] = []

        public init(weights: [UInt8] = []) {
            self.weights = weights
        }

        public var sum: Int {
            weights.reduce(0) { $0 + Int($1) }
        }

        /// Weight of the skill at vanilla actor-value `index`, or nil when that
        /// index is not one of the eighteen skills.
        public func weight(at index: Int32) -> UInt8? {
            let offset = Int(index - Self.firstActorValue)
            guard weights.indices.contains(offset) else { return nil }
            return weights[offset]
        }

        /// Every skill index this class weights, paired with its weight, in
        /// actor-value index order.
        public var byActorValue: [(index: Int32, weight: Int)] {
            weights.enumerated().map { offset, weight in
                (index: Self.firstActorValue + Int32(offset), weight: Int(weight))
            }
        }
    }

    public let formID: FormID
    public let editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    public let name: LString?
    public let attributeWeights: AttributeWeights
    /// DATA 0x06, the per-skill weights.
    public let skillWeights: SkillWeights
    /// DATA 0x18, the health ratio below which an essential or protected actor
    /// enters bleedout (CK "Class"). Decoded here so 15.6 does not have to
    /// re-open the record; nothing in this issue reads it.
    public let bleedoutDefault: Float
    /// DESC — class description.
    public let description: LString?
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "CLAS" else {
            throw ESMError.malformed("expected CLAS record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var data = DecodedData()
        var description: LString?
        var skipped = FieldTally()
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "DATA":
                data = try Self.decodeDATA(field)
            case "DESC":
                description = try LString(field: field, localized: localized)
            default:
                skipped.note(.unknownField(field.type))
            }
        }
        self.skipped = skipped
        self.editorID = editorID
        self.name = name
        self.description = description
        attributeWeights = data.attributeWeights
        skillWeights = data.skillWeights
        bleedoutDefault = data.bleedoutDefault
    }

    /// What one DATA field yields, gathered so the decoder can return more than
    /// the parameter cap's worth of loose values.
    private struct DecodedData {
        var attributeWeights = AttributeWeights()
        var skillWeights = SkillWeights()
        var bleedoutDefault: Float = 0
    }

    /// DATA, 36 bytes (UESP CLAS). A short DATA yields zero weights, not an
    /// error: a class with no weights spreads no points, and throwing would
    /// take the whole actor down.
    private static func decodeDATA(_ field: ESMField) throws -> DecodedData {
        var decoded = DecodedData()
        decoded.skillWeights = try decodeSkillWeights(field)
        guard field.data.count >= 0x23 else { return decoded }
        var reader = BinaryReader(field.data)
        reader.skip(0x18)
        decoded.bleedoutDefault = try reader.readFloat32()
        reader.skip(4) // voice points
        decoded.attributeWeights.health = try reader.readUInt8()
        decoded.attributeWeights.magicka = try reader.readUInt8()
        decoded.attributeWeights.stamina = try reader.readUInt8()
        return decoded
    }

    /// DATA 0x06: the eighteen skill weight bytes. A DATA too short to hold all
    /// eighteen yields none rather than a truncated list, because the mapping
    /// from position to actor value only holds for a complete block.
    private static func decodeSkillWeights(_ field: ESMField) throws -> SkillWeights {
        guard field.data.count >= 0x06 + SkillWeights.count else { return SkillWeights() }
        var reader = BinaryReader(field.data)
        reader.skip(0x06)
        var weights: [UInt8] = []
        weights.reserveCapacity(SkillWeights.count)
        for _ in 0 ..< SkillWeights.count {
            try weights.append(reader.readUInt8())
        }
        return SkillWeights(weights: weights)
    }
}
