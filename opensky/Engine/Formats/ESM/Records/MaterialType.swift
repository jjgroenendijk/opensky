// MATT material-type record (issue #358): the surface vocabulary the rest of
// the game is keyed by. A collision mesh names a material by hashing this
// record's name (`HavokMaterialHash`), a landscape texture names one through
// LTEX.MNAM, and an IPDS impact table pairs each of them with the impact to
// play there.
//
// References: UESP "Skyrim Mod:Mod File Format/MATT"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MATT
// Cross-checked against xEdit dev-4.1.6 wbDefinitionsTES5.pas:
//   wbRecord(MATT, 'Material Type', [
//     wbEDID,
//     wbFormIDCk(PNAM, 'Material Parent', [MATT, NULL]),
//     wbString(MNAM, 'Material Name'),
//     wbFloatColors(CNAM, 'Havok Display Color'),
//     wbFloat(BNAM, 'Buoyancy'),
//     wbInteger(FNAM, 'Flags', itU32, ...),
//     wbFormIDCk(HNAM, 'Havok Impact Data Set', [IPDS, NULL])
//   ]);
// Layout documented in docs/formats/material-type.md.

import Foundation

nonisolated struct MaterialType: Equatable, Sendable {
    let formID: FormID
    let editorID: String?
    /// MNAM — the Creation Kit material name. This is the string a NIF's Havok
    /// material value is the hash of, so a record without one can never be
    /// reached from a collision mesh.
    let materialName: String?
    /// PNAM — the material this one inherits from, or nil at the root of a
    /// chain. Vanilla uses it to say that stairs-of-stone are stone.
    let parent: FormID?
    /// HNAM — the impact data set to play on this material when the thing that
    /// struck it names none of its own. Footsteps do not read it: a footstep
    /// always carries its own IPDS through `FSTP.DATA`.
    let impactDataSet: FormID?

    /// The value a NIF collision shape stores to point at this record, or nil
    /// when the record carries no name to hash.
    var havokMaterial: UInt32? {
        materialName.map(HavokMaterialHash.value(ofMaterialName:))
    }

    init(record: ESMRecord) throws {
        guard record.type == "MATT" else {
            throw ESMError.malformed("expected MATT record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var materialName: String?
        var parent: FormID?
        var impactDataSet: FormID?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "MNAM":
                materialName = try reader.readZString()
            case "PNAM":
                parent = try Self.readLink(&reader, size: field.data.count)
            case "HNAM":
                impactDataSet = try Self.readLink(&reader, size: field.data.count)
            // Skipped: CNAM (Havok display colour, a Creation Kit affordance),
            // BNAM (buoyancy) and FNAM (stair/arrow flags). Nothing floats or
            // sticks arrows yet, and a field this decoder does not read cannot
            // go stale against the spec.
            default:
                break
            }
        }
        self.editorID = editorID
        self.materialName = materialName
        self.parent = parent
        self.impactDataSet = impactDataSet
    }

    /// Test seam: a material built from decoded values rather than a record.
    init(
        formID: FormID,
        editorID: String? = nil,
        materialName: String?,
        parent: FormID? = nil,
        impactDataSet: FormID? = nil
    ) {
        self.formID = formID
        self.editorID = editorID
        self.materialName = materialName
        self.parent = parent
        self.impactDataSet = impactDataSet
    }

    private static func readLink(
        _ reader: inout BinaryReader,
        size: Int
    ) throws -> FormID? {
        guard size == 4 else { return nil }
        let id = try FormID(reader.readUInt32())
        return id.isNull ? nil : id
    }
}
