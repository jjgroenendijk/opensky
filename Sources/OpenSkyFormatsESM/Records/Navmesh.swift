// NAVM record: the walkable surface an actor paths across, one per interior cell
// and per exterior cell square. Its NVNM payload, decoded by `NavmeshGeometry`,
// often passes 64 KB and arrives through the `XXXX` size extension.
// Layout documented in docs/formats/navmesh.md.

import Foundation
import OpenSkyFormatsCore

/// Where a navmesh sits in the world. Interiors name their CELL directly;
/// exteriors name a worldspace and the cell square inside it, because an
/// exterior navmesh is authored per grid square rather than per CELL record.
nonisolated public enum NavmeshLocation: Hashable, Sendable {
    case interior(cell: FormID)
    case exterior(world: FormID, x: Int32, y: Int32)
}

nonisolated public struct Navmesh: Sendable {
    public let formID: FormID
    public let editorID: String?
    /// NVNM. Required: a NAVM without geometry is structurally unusable, so
    /// its absence is a decode error rather than an empty mesh.
    public let geometry: NavmeshGeometry
    /// ONAM — base objects whose placed references cut into the mesh.
    public let baseObjects: [FormID]
    /// PNAM/NNAM — vertex indices preferred, and refused, as connections to
    /// neighbor meshes.
    public let preferredConnectors: [UInt16]
    public let nonConnectors: [UInt16]
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        guard record.type == "NAVM" else {
            throw ESMError.malformed("expected NAVM record, got \(record.type)")
        }
        var rest = try RecordFields(record: record, type: "NAVM")
        let recordID = rest.formID
        formID = recordID
        var editorID: String?
        var geometry: NavmeshGeometry?
        try rest.readEach { field in
            switch field.type {
            case "EDID":
                var reader = BinaryReader(field.data)
                editorID = try reader.readZString()
            case "NVNM":
                geometry = try NavmeshGeometry(data: field.data)
            default:
                return false
            }
            return true
        }
        baseObjects = rest.formIDArray("ONAM")
        preferredConnectors = rest.read("PNAM", Self.vertexIndices) ?? []
        nonConnectors = rest.read("NNAM", Self.vertexIndices) ?? []
        skipped = rest.finish()
        guard let geometry else {
            throw ESMError.malformed("NAVM \(FormID(record.formID)) has no NVNM field")
        }
        self.editorID = editorID
        self.geometry = geometry
    }

    private static func vertexIndices(_ reader: inout BinaryReader) throws -> [UInt16] {
        var indices: [UInt16] = []
        while reader.bytesRemaining >= 2 {
            try indices.append(reader.readUInt16())
        }
        return indices
    }
}
