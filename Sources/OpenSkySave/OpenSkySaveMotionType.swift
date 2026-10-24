// RMOT chunk: the motion types scripts set with `SetMotionType`. Merged into the
// `RDLT` deltas by key. Layout: docs/formats/opensky-save.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One saved motion type, before it is merged back into the delta.
nonisolated public struct SaveMotionTypeEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let motionType: ReferenceMotionType
}

nonisolated extension OpenSkySaveEncoder {
    /// Every reference a script set a motion type on, in snapshot order. None writes no chunk.
    public static func writeMotionTypes(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry in
            entry.delta.component(ReferenceMotionType.self).map { (entry, $0) }
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.motionTypes, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (entry, motionType) in saved {
                writeKey(entry.key, into: &payload)
                writeCell(entry.delta.cell, into: &payload)
                payload.writeUInt8(motionType.rawValue)
            }
        }
    }
}

nonisolated public enum OpenSkySaveMotionTypeDecoder: Sendable {
    public static func decodeMotionTypes(_ payload: Data) throws -> [SaveMotionTypeEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("RMOT entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumMotionTypeEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.motionTypes
        )
        var entries: [SaveMotionTypeEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
            let raw = try reader.uint8("RMOT motion type")
            guard let motionType = ReferenceMotionType(rawValue: raw) else {
                throw OpenSkySaveError.invalidValue(context: "RMOT motion type \(raw)")
            }
            entries.append(SaveMotionTypeEntry(key: key, cell: cell, motionType: motionType))
        }
        return entries
    }
}

nonisolated extension OpenSkySaveDecoder {
    /// The chunks that say where a reference is and how it moves. False for any other tag.
    static func applyPlacement(tag: String, payload: Data, to body: inout Body) throws -> Bool {
        switch tag {
        case OpenSkySaveFormat.ChunkTag.relocations:
            body.relocations = try OpenSkySaveRelocationDecoder.decodeRelocations(payload)
        case OpenSkySaveFormat.ChunkTag.motionTypes:
            body.motionTypes = try OpenSkySaveMotionTypeDecoder.decodeMotionTypes(payload)
        default:
            return false
        }
        return true
    }
}

nonisolated extension SaveMotionTypeEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        motionType.erased
    }
}
