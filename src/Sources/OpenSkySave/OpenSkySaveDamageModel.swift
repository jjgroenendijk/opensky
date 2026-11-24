// RDMG chunk: the models destruction stages swapped in. Merged into the `RDLT` deltas
// by key. Layout: docs/formats/opensky-save.md.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldState

/// One saved damage model, before it is merged back into the delta.
nonisolated struct SaveDamageModelEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let model: ReferenceDamageModel
}

nonisolated enum OpenSkySaveDamageModelWriter {
    /// Every reference a destruction stage gave a model, in snapshot order. None writes
    /// no chunk.
    static func writeDamageModels(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry in
            entry.delta.component(ReferenceDamageModel.self).map { (entry, $0) }
        }
        guard !saved.isEmpty else { return }
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.damageModels) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (entry, model) in saved {
                payload.writeKey(entry.key)
                payload.writeCell(entry.delta.cell)
                payload.writeString(model.path ?? "")
                payload.writeUInt32(model.stage.map { UInt32(clamping: $0 + 1) } ?? 0)
            }
        }
    }
}

nonisolated enum OpenSkySaveDamageModelDecoder: Sendable {
    static func decodeDamageModels(_ payload: Data) throws -> [SaveDamageModelEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("RDMG entry count")
        try SaveCountCheck.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumDamageModelEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.damageModels
        )
        var entries: [SaveDamageModelEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
            let path = try reader.string("RDMG model path")
            let stage = try reader.uint32("RDMG damage stage")
            entries.append(SaveDamageModelEntry(
                key: key, cell: cell,
                model: ReferenceDamageModel(
                    path: path.isEmpty ? nil : path, stage: stage == 0 ? nil : Int(stage) - 1
                )
            ))
        }
        return entries
    }
}

nonisolated extension SaveDamageModelEntry: SaveDeltaComponentEntry {
    var deltaCell: CellSceneLocation? {
        cell
    }

    var deltaComponent: WorldStateComponentValue? {
        model.erased
    }
}
