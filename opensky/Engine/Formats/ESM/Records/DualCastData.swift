// DUAL record: the art a dual-cast spell swaps in. A magic effect names one
// through its DUAL link (MGEF DATA), and the record replaces the effect's
// projectile, explosion, shader, hit art and impact set for the dual-cast
// variant, plus flags saying which of those inherit the caster's scale.
//
// The vanilla masters author two of these — `doomSerpentDualCastData` and
// `FrostStormDualCastData` — and both were observed with a 24-byte DATA. This
// milestone decodes the record and stops there; nothing casts yet.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/DUAL"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DUAL
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas
//     `wbRecord(DUAL, 'Dual Cast Data', ...)` line 7543.
// Layout documented in docs/formats/magic-records.md.

import Foundation

nonisolated struct DualCastData: Equatable {
    /// DATA's uint32 inherit-scale flags, in the xEdit bit order.
    struct InheritScale: OptionSet, Equatable {
        let rawValue: UInt32

        static let hitEffectArt = InheritScale(rawValue: 0x01)
        static let projectile = InheritScale(rawValue: 0x02)
        static let explosion = InheritScale(rawValue: 0x04)
    }

    /// The five links plus the flag word, in DATA order.
    struct Art: Equatable {
        let projectile: FormID?
        let explosion: FormID?
        let effectShader: FormID?
        let hitEffectArt: FormID?
        let impactDataSet: FormID?
        let inheritScale: InheritScale
    }

    /// DATA is a fixed 24-byte struct: five FormIDs then a uint32 flag word.
    static let dataSize = 24

    let formID: FormID
    let editorID: String?
    let bounds: ObjectBounds?
    /// DATA. Nil when the field is absent or too short, so a malformed art
    /// block does not discard the record's identity.
    let art: Art?
    let skipped: ReferenceRecordTally

    init(record: ESMRecord) throws {
        guard record.type == "DUAL" else {
            throw ESMError.malformed("expected DUAL record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var bounds: ObjectBounds?
        var art: Art?
        var tally = ReferenceRecordTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "OBND": bounds = try ObjectBounds(field: field)
                case "DATA": art = try Self.art(field)
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID
        self.bounds = bounds
        self.art = art
        skipped = tally
    }

    private static func art(_ field: ESMField) throws -> Art {
        guard field.data.count >= dataSize else {
            throw ESMError.malformed(
                "DUAL DATA has \(field.data.count) bytes, expected \(dataSize)"
            )
        }
        var reader = BinaryReader(field.data)
        func link() throws -> FormID? {
            let id = try FormID(reader.readUInt32())
            return id.isNull ? nil : id
        }
        return try Art(
            projectile: link(),
            explosion: link(),
            effectShader: link(),
            hitEffectArt: link(),
            impactDataSet: link(),
            inheritScale: InheritScale(rawValue: reader.readUInt32())
        )
    }
}
