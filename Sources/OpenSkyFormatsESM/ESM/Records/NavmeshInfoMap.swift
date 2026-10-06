// NAVI record, the navmesh info map: one per plugin, listing every NAVM, where it
// lives, and which navmeshes link to which. It resolves links across navmeshes
// without walking every cell first.
// Layout documented in docs/formats/navmesh.md.

import Foundation
import OpenSkyFormatsCore
import simd

/// One NVMI entry: the index's view of a single NAVM.
nonisolated public struct NavmeshInfo: Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// The navmesh is an island: reachable only through its edge links.
        public static let isIsland = Flags(rawValue: 1 << 5)
        /// Untouched since generation.
        public static let notEdited = Flags(rawValue: 1 << 6)
    }

    public let navmesh: FormID
    public let flags: Flags
    /// Approximate centre, in game units. Coarse by design — the index exists
    /// to pick candidates, not to path through them.
    public let approximateLocation: SIMD3<Float>
    public let preferredPercent: Float
    /// Navmeshes sharing an edge with this one.
    public let edgeLinks: [FormID]
    /// The subset of `edgeLinks` the generator marked preferred.
    public let preferredEdgeLinks: [FormID]
    /// DOOR REFRs reachable from this navmesh.
    public let doors: [FormID]
    /// Whether the skipped island block was present.
    public let hasIslandData: Bool
    public let location: NavmeshLocation

    public init(field: ESMField) throws {
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

nonisolated public struct NavmeshInfoMap: Sendable {
    public let editorID: String?
    /// NVER; 0x0C in `Skyrim.esm`.
    public let version: UInt32
    public let infos: [NavmeshInfo]
    /// NVSI — navmeshes this plugin deletes from its masters.
    public let deletedNavmeshes: [FormID]
    /// NVPP tallies; the paths themselves are skipped.
    public let precomputedPathCount: Int
    public let roadMarkerCount: Int
    /// NVMI entries that failed to decode. A malformed entry is skipped rather
    /// than failing the whole map: one bad index entry must not cost the engine
    /// every other navmesh in the plugin.
    public let malformedInfoCount: Int
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        guard record.type == "NAVI" else {
            throw ESMError.malformed("expected NAVI record, got \(record.type)")
        }
        var editorID: String?
        var version: UInt32 = 0
        var infos: [NavmeshInfo] = []
        var deleted: [FormID] = []
        var pathing = (paths: 0, markers: 0)
        var malformed = 0
        var skipped = FieldTally()
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
                skipped.note(.unknownField(field.type))
            }
        }
        self.skipped = skipped
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
