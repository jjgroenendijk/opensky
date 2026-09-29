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

    public init(record: ESMRecord) throws {
        guard record.type == "NAVM" else {
            throw ESMError.malformed("expected NAVM record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var geometry: NavmeshGeometry?
        for field in try record.fields() {
            switch field.type {
            case "EDID":
                var reader = BinaryReader(field.data)
                editorID = try reader.readZString()
            case "NVNM":
                geometry = try NavmeshGeometry(data: field.data)
            // Skipped: ONAM, PNAM, NNAM; path finding does not read them.
            default:
                break
            }
        }
        guard let geometry else {
            throw ESMError.malformed("NAVM \(FormID(record.formID)) has no NVNM field")
        }
        self.editorID = editorID
        self.geometry = geometry
    }
}
