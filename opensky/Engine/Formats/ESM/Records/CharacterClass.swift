// CLAS record decoded into engine types (issue #194, roadmap item 15.3): the
// attribute weights that spread an auto-calc actor's per-level points, plus the
// bleedout ratio 15.6 will read. The 18 skill weights and the trainer fields are
// skipped deliberately — skills are M18.
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

    let formID: FormID
    let editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    let name: LString?
    let attributeWeights: AttributeWeights
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
        var attributeWeights = AttributeWeights()
        var bleedoutDefault: Float = 0
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "DATA":
                (attributeWeights, bleedoutDefault) = Self.decodeDATA(field)
            default:
                break
            }
        }
        self.editorID = editorID
        self.name = name
        self.attributeWeights = attributeWeights
        self.bleedoutDefault = bleedoutDefault
    }

    /// DATA, 36 bytes: uint32 unknown, trainer skill + level, 18 skill
    /// weights, float bleedout default at 0x18, uint32 voice points, then the
    /// three attribute weight bytes at 0x20 and a flag byte (UESP CLAS).
    ///
    /// A short DATA yields zero weights rather than a thrown error: a class
    /// with no weights spreads no per-level points, which is exactly what an
    /// unreadable one should do, and refusing the record would take the whole
    /// actor down with it.
    private static func decodeDATA(_ field: ESMField) -> (AttributeWeights, Float) {
        guard field.data.count >= 0x23 else { return (AttributeWeights(), 0) }
        var reader = BinaryReader(field.data)
        reader.skip(0x18)
        let bleedout = (try? reader.readFloat32()) ?? 0
        reader.skip(4) // voice points
        var weights = AttributeWeights()
        weights.health = (try? reader.readUInt8()) ?? 0
        weights.magicka = (try? reader.readUInt8()) ?? 0
        weights.stamina = (try? reader.readUInt8()) ?? 0
        return (weights, bleedout)
    }
}

/// Cross-plugin CLAS index, built the way `ActorTemplateResolver` builds its
/// NPC_ index: raw-`UInt32` FormID keys within one plugin, undecodable records
/// dropped rather than fatal.
nonisolated struct CharacterClassIndex: Equatable {
    private(set) var classes: [UInt32: CharacterClass]

    init(classes: [UInt32: CharacterClass] = [:]) {
        self.classes = classes
    }

    static func build(from file: ESMFile, localized: Bool) -> CharacterClassIndex {
        var classes: [UInt32: CharacterClass] = [:]
        guard let top = file.topGroup(of: "CLAS"), let children = try? top.children() else {
            return CharacterClassIndex()
        }
        for case let .record(record) in children {
            guard record.type == "CLAS", !record.isDeleted else { continue }
            classes[record.formID] = try? CharacterClass(record: record, localized: localized)
        }
        return CharacterClassIndex(classes: classes)
    }

    subscript(id: FormID?) -> CharacterClass? {
        guard let id else { return nil }
        return classes[id.rawValue]
    }
}
