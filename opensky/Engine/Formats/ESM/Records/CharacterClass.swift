// CLAS record decoded into engine types (issue #194, roadmap item 15.3): the
// attribute weights that spread an auto-calc actor's per-level points, plus the
// bleedout ratio 15.6 will read, plus the 18 skill weights that spread an
// actor's per-level skill points (issue #468, roadmap item 19.5). The trainer
// fields are skipped deliberately — nothing trains yet.
//
// Named `CharacterClass` rather than `Class`, which is a Swift keyword-adjacent
// name that reads badly at every use site; the record type stays "CLAS".
//
// Reference: UESP "Skyrim Mod:Mod File Format/CLAS"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS
// Layout documented in docs/formats/actors.md.

import Foundation

nonisolated struct CharacterClass: Equatable {
    /// DATA 0x20 / 0x21 / 0x22: "Each byte provides the weight assigned to
    /// that attribute. The weights are used to distribute the fixed 10
    /// attribute points per level among the three attributes." (UESP CLAS)
    struct AttributeWeights: Equatable {
        var health: UInt8 = 0
        var magicka: UInt8 = 0
        var stamina: UInt8 = 0

        var sum: Int {
            Int(health) + Int(magicka) + Int(stamina)
        }
    }

    /// DATA 0x06 – 0x17: "Each byte provides the weight assigned to one skill.
    /// The skills are provided in actor value index order (skill at byte 06 is
    /// One-handed; at byte 17, Enchanting) ... The weights are used to
    /// distribute the fixed 8 skill points per level among the various skills.
    /// Skills with a weight of zero never increase." (UESP CLAS)
    struct SkillWeights: Equatable {
        /// Actor-value index of the first weight byte, `One-Handed`.
        static let firstActorValue: Int32 = 6
        /// How many weight bytes DATA carries, one per skill.
        static let count = 18

        /// One weight per skill, in actor-value index order from
        /// `firstActorValue`. Empty when DATA was too short to reach them.
        var weights: [UInt8] = []

        var sum: Int {
            weights.reduce(0) { $0 + Int($1) }
        }

        /// Weight of the skill at vanilla actor-value `index`, or nil when that
        /// index is not one of the eighteen skills.
        func weight(at index: Int32) -> UInt8? {
            let offset = Int(index - Self.firstActorValue)
            guard weights.indices.contains(offset) else { return nil }
            return weights[offset]
        }

        /// Every skill index this class weights, paired with its weight, in
        /// actor-value index order.
        var byActorValue: [(index: Int32, weight: Int)] {
            weights.enumerated().map { offset, weight in
                (index: Self.firstActorValue + Int32(offset), weight: Int(weight))
            }
        }
    }

    let formID: FormID
    let editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    let name: LString?
    let attributeWeights: AttributeWeights
    /// DATA 0x06, the per-skill weights (issue #468).
    let skillWeights: SkillWeights
    /// DATA 0x18, the health ratio below which an essential or protected actor
    /// enters bleedout (CK "Class"). Decoded here so 15.6 does not have to
    /// re-open the record; nothing in this issue reads it.
    let bleedoutDefault: Float

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "CLAS" else {
            throw ESMError.malformed("expected CLAS record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var data = DecodedData()
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "DATA":
                data = Self.decodeDATA(field)
            default:
                break
            }
        }
        self.editorID = editorID
        self.name = name
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

    /// DATA, 36 bytes: uint32 unknown, trainer skill + level, 18 skill
    /// weights, float bleedout default at 0x18, uint32 voice points, then the
    /// three attribute weight bytes at 0x20 and a flag byte (UESP CLAS).
    ///
    /// A short DATA yields zero weights rather than a thrown error: a class
    /// with no weights spreads no per-level points, which is exactly what an
    /// unreadable one should do, and refusing the record would take the whole
    /// actor down with it.
    private static func decodeDATA(_ field: ESMField) -> DecodedData {
        var decoded = DecodedData()
        decoded.skillWeights = decodeSkillWeights(field)
        guard field.data.count >= 0x23 else { return decoded }
        var reader = BinaryReader(field.data)
        reader.skip(0x18)
        decoded.bleedoutDefault = (try? reader.readFloat32()) ?? 0
        reader.skip(4) // voice points
        decoded.attributeWeights.health = (try? reader.readUInt8()) ?? 0
        decoded.attributeWeights.magicka = (try? reader.readUInt8()) ?? 0
        decoded.attributeWeights.stamina = (try? reader.readUInt8()) ?? 0
        return decoded
    }

    /// DATA 0x06: the eighteen skill weight bytes. A DATA too short to hold all
    /// eighteen yields none rather than a truncated list, because the mapping
    /// from position to actor value only holds for a complete block.
    private static func decodeSkillWeights(_ field: ESMField) -> SkillWeights {
        guard field.data.count >= 0x06 + SkillWeights.count else { return SkillWeights() }
        var reader = BinaryReader(field.data)
        reader.skip(0x06)
        var weights: [UInt8] = []
        weights.reserveCapacity(SkillWeights.count)
        for _ in 0 ..< SkillWeights.count {
            guard let weight = try? reader.readUInt8() else { return SkillWeights() }
            weights.append(weight)
        }
        return SkillWeights(weights: weights)
    }
}
