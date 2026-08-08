// NAVI, the navmesh info map: one record for the whole plugin, listing every
// NAVM it defines, where each one lives, and which of them link to which. It
// is what makes cross-navmesh resolution possible without walking every cell
// in the file first (16.2, issue #200).
//
// NAVI fields:
//   EDID  zstring  editor ID
//   NVER  uint32   version (0x0C in Skyrim.esm)
//   NVMI  struct   one per navmesh, repeated; layout below
//   NVPP  struct   precomputed preferred pathing
//   NVSI  FormID[] navmeshes deleted by this plugin
//
// NVMI, variable size. Counts are uint32 and precede their arrays:
//   00 FormID  the NAVM this entry describes
//   04 uint32  flags — bit 5 is-island, bit 6 not-edited
//   08 float32[3] approximate centre of the navmesh, in game units
//   14 float32 preferred-pathing percentage
//   18 uint32 count + count * FormID   navmeshes linked by a shared edge
//      uint32 count + count * FormID   the preferred subset of those
//      uint32 count + count * 8 bytes  door links: uint32 CRC hash of
//                                      "PathingDoor" then the DOOR REFR
//      uint8  has-island-data; when non-zero the island block follows:
//               float32[3] bounds minimum, float32[3] bounds maximum,
//               uint32 count + count * 3 uint16 triangle vertex indices,
//               uint32 count + count * float32[3] vertices
//      the same "pathing cell" struct NVNM ends its header with: a constant
//      CRC marker, the parent worldspace, then either the parent CELL FormID
//      or int16 grid Y and int16 grid X
//
// NVPP: uint32 path count, then that many (uint32 FormID count + that many
// NAVM FormIDs); then uint32 road-marker count, then that many (FormID navmesh
// + uint32 index).
//
// Skipped: the island block's own bounds, triangles and vertices — a coarse
// summary mesh nothing consumes — decoded only far enough to reach the pathing
// cell behind it, with `hasIslandData` retained so the census can tally it.
// NVPP is skipped the same way, tallied as `precomputedPathCount` and
// `roadMarkerCount` and otherwise dropped: preferred pathing is a routing
// preference, not a connectivity fact, and 16.2 does not read it.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/NAVI"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NAVI
//   UESP "Skyrim Mod:Mod File Format/NVMI Field"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NVMI_Field
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(NAVI, ...)` at line
//     5672; the island-data and parent unions are `wbNAVIIslandDataDecider`
//     and `wbNAVIParentDecider` in Core/wbDefinitionsCommon.pas, lines 5329
//     and 5350.
// Layout documented in docs/formats/navmesh.md.

import Foundation
import simd

/// One NVMI entry: the index's view of a single NAVM.
nonisolated struct NavmeshInfo: Sendable {
    struct Flags: OptionSet, Equatable, Sendable {
        let rawValue: UInt32

        /// The navmesh is an island: reachable only through its edge links.
        static let isIsland = Flags(rawValue: 1 << 5)
        /// Untouched since generation.
        static let notEdited = Flags(rawValue: 1 << 6)
    }

    let navmesh: FormID
    let flags: Flags
    /// Approximate centre, in game units. Coarse by design — the index exists
    /// to pick candidates, not to path through them.
    let approximateLocation: SIMD3<Float>
    let preferredPercent: Float
    /// Navmeshes sharing an edge with this one.
    let edgeLinks: [FormID]
    /// The subset of `edgeLinks` the generator marked preferred.
    let preferredEdgeLinks: [FormID]
    /// DOOR REFRs reachable from this navmesh.
    let doors: [FormID]
    /// Whether the skipped island block was present.
    let hasIslandData: Bool
    let location: NavmeshLocation

    init(field: ESMField) throws {
        guard field.type == "NVMI" else {
            throw ESMError.malformed("expected NVMI field, got \(field.type)")
        }
        var reader = BinaryReader(field.data)
        navmesh = try FormID(reader.readUInt32())
        flags = try Flags(rawValue: reader.readUInt32())
        approximateLocation = try NavmeshDecoding.readVector3(&reader)
        preferredPercent = try reader.readFloat32()
        edgeLinks = try Self.readFormIDs(&reader, of: "edge link")
        preferredEdgeLinks = try Self.readFormIDs(&reader, of: "preferred edge link")
        doors = try Self.readDoors(&reader)
        hasIslandData = try reader.readUInt8() != 0
        if hasIslandData {
            try Self.skipIslandData(&reader)
        }
        location = try NavmeshDecoding.readLocation(&reader)
    }

    private static func readFormIDs(
        _ reader: inout BinaryReader,
        of what: String
    ) throws -> [FormID] {
        let count = try NavmeshDecoding.readCount(&reader, elementSize: 4, of: what)
        var ids: [FormID] = []
        ids.reserveCapacity(count)
        for _ in 0 ..< count {
            try ids.append(FormID(reader.readUInt32()))
        }
        return ids
    }

    /// Door links: each is a constant CRC marker followed by the REFR.
    private static func readDoors(_ reader: inout BinaryReader) throws -> [FormID] {
        let count = try NavmeshDecoding.readCount(&reader, elementSize: 8, of: "door link")
        var doors: [FormID] = []
        doors.reserveCapacity(count)
        for _ in 0 ..< count {
            _ = try reader.readUInt32() // CRC hash of "PathingDoor", a constant
            try doors.append(FormID(reader.readUInt32()))
        }
        return doors
    }

    /// Consumes the island summary mesh without keeping it. Reading it is the
    /// only way to reach the pathing cell that follows.
    private static func skipIslandData(_ reader: inout BinaryReader) throws {
        _ = try reader.read(count: 24) // bounds minimum and maximum
        let triangles = try NavmeshDecoding.readCount(
            &reader,
            elementSize: 6,
            of: "island triangle"
        )
        _ = try reader.read(count: triangles * 6)
        let vertices = try NavmeshDecoding.readCount(&reader, elementSize: 12, of: "island vertex")
        _ = try reader.read(count: vertices * 12)
    }
}

nonisolated struct NavmeshInfoMap: Sendable {
    let editorID: String?
    /// NVER; 0x0C in `Skyrim.esm`.
    let version: UInt32
    let infos: [NavmeshInfo]
    /// NVSI — navmeshes this plugin deletes from its masters.
    let deletedNavmeshes: [FormID]
    /// NVPP tallies; the paths themselves are skipped.
    let precomputedPathCount: Int
    let roadMarkerCount: Int
    /// NVMI entries that failed to decode. A malformed entry is skipped rather
    /// than failing the whole map: one bad index entry must not cost the engine
    /// every other navmesh in the plugin.
    let malformedInfoCount: Int

    init(record: ESMRecord) throws {
        guard record.type == "NAVI" else {
            throw ESMError.malformed("expected NAVI record, got \(record.type)")
        }
        var editorID: String?
        var version: UInt32 = 0
        var infos: [NavmeshInfo] = []
        var deleted: [FormID] = []
        var pathing = (paths: 0, markers: 0)
        var malformed = 0
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "NVER":
                version = try reader.readUInt32()
            case "NVMI":
                if let info = try? NavmeshInfo(field: field) {
                    infos.append(info)
                } else {
                    malformed += 1
                }
            case "NVPP":
                pathing = try Self.tallyPreferredPathing(&reader)
            case "NVSI":
                deleted = try Self.readDeleted(&reader)
            default:
                break
            }
        }
        self.editorID = editorID
        self.version = version
        self.infos = infos
        deletedNavmeshes = deleted
        precomputedPathCount = pathing.paths
        roadMarkerCount = pathing.markers
        malformedInfoCount = malformed
    }

    /// NVPP, consumed for its two counts.
    private static func tallyPreferredPathing(
        _ reader: inout BinaryReader
    ) throws -> (paths: Int, markers: Int) {
        let paths = try NavmeshDecoding.readCount(&reader, elementSize: 4, of: "preferred path")
        for _ in 0 ..< paths {
            let ids = try NavmeshDecoding.readCount(&reader, elementSize: 4, of: "path navmesh")
            _ = try reader.read(count: ids * 4)
        }
        let markers = try NavmeshDecoding.readCount(&reader, elementSize: 8, of: "road marker")
        _ = try reader.read(count: markers * 8)
        return (paths, markers)
    }

    /// NVSI is a bare FormID array with no leading count: it fills the field.
    private static func readDeleted(_ reader: inout BinaryReader) throws -> [FormID] {
        var ids: [FormID] = []
        ids.reserveCapacity(reader.bytesRemaining / 4)
        while reader.bytesRemaining >= 4 {
            try ids.append(FormID(reader.readUInt32()))
        }
        return ids
    }
}
