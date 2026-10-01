// AEFF chunk: active effects, merged into the `RDLT` deltas by `ReferenceKey`.
// Bad floats and empty effects are normalized by the state types. An unknown
// source kind or mode throws: this build wrote both closed enums itself.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyWorldState

/// One actor's saved active effects, before they are merged back into the
/// delta.
nonisolated public struct SaveActiveEffectEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let state: ActiveEffectState
}

nonisolated public enum OpenSkySaveActiveEffectDecoder: Sendable {
    public static func decodeActiveEffects(_ payload: Data) throws -> [SaveActiveEffectEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("AEFF entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumActiveEffectEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.activeEffects
        )
        var entries: [SaveActiveEffectEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    // MARK: - Private

    private static func decodeEntry(_ reader: inout SaveReader) throws -> SaveActiveEffectEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let count = try reader.uint32("AEFF effect count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumActiveEffectSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.activeEffects
        )
        var effects: [ActiveEffect] = []
        effects.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try effects.append(decodeEffect(&reader))
        }
        return SaveActiveEffectEntry(
            key: key,
            cell: cell,
            state: ActiveEffectState(effects: effects)
        )
    }

    private static func decodeEffect(_ reader: inout SaveReader) throws -> ActiveEffect {
        let sequence = try reader.uint64("AEFF effect sequence")
        let rawKind = try reader.uint32("AEFF source kind")
        guard let kind = ActiveEffectSourceKind(rawValue: rawKind) else {
            throw OpenSkySaveError.invalidValue(context: "AEFF source kind \(rawKind) is unknown")
        }
        let record = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let effect = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let caster = try decodeOptionalKey(&reader)
        let rawMode = try reader.uint32("AEFF mode")
        guard let mode = ActiveEffectMode(rawValue: rawMode) else {
            throw OpenSkySaveError.invalidValue(context: "AEFF mode \(rawMode) is unknown")
        }
        let isDetrimental = try reader.uint8("AEFF detrimental flag") != 0
        let duration = try reader.float32("AEFF duration")
        let elapsed = try reader.float32("AEFF elapsed")
        let paidSeconds = try reader.uint32("AEFF paid seconds")
        let stackKeyword = try decodeOptionalKey(&reader)
        return try ActiveEffect(
            sequence: sequence,
            source: ActiveEffectSource(kind: kind, record: record),
            effect: effect,
            caster: caster,
            mode: mode,
            isDetrimental: isDetrimental,
            duration: duration,
            elapsed: elapsed,
            paidSeconds: paidSeconds,
            values: decodeValues(&reader),
            stackKeyword: stackKeyword
        )
    }

    private static func decodeValues(_ reader: inout SaveReader) throws -> [ActiveEffectValue] {
        let count = try reader.uint32("AEFF value count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.activeEffectValueRecordSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.activeEffects
        )
        var values: [ActiveEffectValue] = []
        values.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let index = try Int32(bitPattern: reader.uint32("AEFF actor value index"))
            let magnitude = try reader.float32("AEFF magnitude")
            let applied = try reader.float32("AEFF applied modifier")
            values.append(ActiveEffectValue(index: index, magnitude: magnitude, applied: applied))
        }
        return values
    }

    private static func decodeOptionalKey(_ reader: inout SaveReader) throws -> ReferenceKey? {
        let present = try reader.uint8("AEFF optional key tag")
        guard present != 0 else { return nil }
        return try OpenSkySaveEntryDecoder.decodeKey(&reader)
    }
}

nonisolated extension SaveActiveEffectEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        state.isEmpty ? nil : state.erased
    }
}
