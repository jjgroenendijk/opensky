// MATT material type: the surface names that collision meshes (by name hash),
// LTEX.MNAM, and IPDS impact tables all key on.
// Layout and sources: docs/formats/material-type.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct MaterialType: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    /// MNAM — the Creation Kit material name. This is the string a NIF's Havok
    /// material value is the hash of, so a record without one can never be
    /// reached from a collision mesh.
    public let materialName: String?
    /// PNAM — the material this one inherits from, or nil at the root of a
    /// chain. Vanilla uses it to say that stairs-of-stone are stone.
    public let parent: FormID?
    /// HNAM — the impact data set to play on this material when the thing that
    /// struck it names none of its own. Footsteps do not read it: a footstep
    /// always carries its own IPDS through `FSTP.DATA`.
    public let impactDataSet: FormID?

    /// The value a NIF collision shape stores to point at this record, or nil
    /// when the record carries no name to hash.
    public var havokMaterial: UInt32? {
        materialName.map(HavokMaterialHash.value(ofMaterialName:))
    }

    public init(record: ESMRecord) throws {
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
    public init(
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
