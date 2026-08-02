// RDLT chunk decoding for the OpenSky native save container (issue #161):
// reference keys, cell locations and component values.
//
// The payload arrives as its own `Data`, so the chunk's declared length is the
// bound on every read in here — a corrupt count inside the chunk can never
// walk into the next chunk's bytes.

import Foundation
import simd

nonisolated enum OpenSkySaveEntryDecoder {
    static func decodeEntries(_ payload: Data) throws -> [WorldStateSnapshotEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("RDLT entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.referenceDeltas
        )
        var entries: [WorldStateSnapshotEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// GVAR chunk: count, then key + declared-type tag + float32 value per
    /// overridden global (issue #165).
    static func decodeGlobals(_ payload: Data) throws -> [WorldStateGlobalSnapshotEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("GVAR entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumGlobalEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.globalValues
        )
        var entries: [WorldStateGlobalSnapshotEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try decodeKey(&reader)
            let tag = try reader.uint8("global value type")
            guard let type = Global.ValueType(saveTag: tag) else {
                throw OpenSkySaveError.invalidValue(context: "unknown global value type tag \(tag)")
            }
            let value = try reader.float32("global value")
            entries.append(WorldStateGlobalSnapshotEntry(
                key: key,
                value: GlobalValue(type: type, rawValue: value)
            ))
        }
        return entries
    }

    private static func decodeEntry(_ reader: inout SaveReader) throws -> WorldStateSnapshotEntry {
        let key = try decodeKey(&reader)
        let cell = try decodeCell(&reader)
        let components = try decodeComponents(&reader)
        return WorldStateSnapshotEntry(
            key: key,
            delta: ReferenceStateDelta(components: components, cell: cell)
        )
    }

    static func decodeKey(_ reader: inout SaveReader) throws -> ReferenceKey {
        let tag = try reader.uint8("reference key kind")
        switch tag {
        case OpenSkySaveFormat.KeyTag.plugin:
            let name = try reader.string("reference key plugin name")
            let objectID = try reader.uint32("reference key object ID")
            return .plugin(name: name, objectID: objectID)
        case OpenSkySaveFormat.KeyTag.generated:
            return try .generated(reader.uint64("reference key sequence"))
        default:
            throw OpenSkySaveError.invalidValue(context: "reference key kind tag \(tag)")
        }
    }

    /// Shared with the `INVN` decoder, which writes the same tagged cell.
    static func decodeCell(_ reader: inout SaveReader) throws -> CellSceneLocation? {
        let tag = try reader.uint8("cell kind")
        switch tag {
        case OpenSkySaveFormat.CellTag.absent:
            return nil
        case OpenSkySaveFormat.CellTag.exterior:
            let x = try Int32(bitPattern: reader.uint32("cell x"))
            let y = try Int32(bitPattern: reader.uint32("cell y"))
            return .exterior(CellCoordinate(x: x, y: y))
        case OpenSkySaveFormat.CellTag.interior:
            return try .interior(FormID(reader.uint32("cell form ID")))
        default:
            throw OpenSkySaveError.invalidValue(context: "cell kind tag \(tag)")
        }
    }

    /// Component kind tags must strictly ascend, which makes "one value per
    /// slot" checkable without a second pass and keeps the encoder's output
    /// the only accepted spelling of a given delta.
    private static func decodeComponents(
        _ reader: inout SaveReader
    ) throws -> [WorldStateComponentKind: WorldStateComponentValue] {
        let count = try reader.uint8("component count")
        var components: [WorldStateComponentKind: WorldStateComponentValue] = [:]
        var previousTag: Int = -1
        for _ in 0 ..< count {
            let tag = try reader.uint8("component kind")
            guard Int(tag) > previousTag else {
                throw OpenSkySaveError.invalidValue(
                    context: "component kind tag \(tag) is not after \(previousTag)"
                )
            }
            guard let kind = WorldStateComponentKind(saveTag: tag) else {
                throw OpenSkySaveError.invalidValue(context: "unknown component kind tag \(tag)")
            }
            previousTag = Int(tag)
            components[kind] = try decodeComponent(kind, &reader)
        }
        return components
    }

    private static func decodeComponent(
        _ kind: WorldStateComponentKind,
        _ reader: inout SaveReader
    ) throws -> WorldStateComponentValue {
        switch kind {
        case .enableState:
            try .enableState(ReferenceEnableState(isEnabled: reader.bool("enable state")))
        case .transform:
            try .transform(decodeTransform(&reader))
        case .activation:
            try .activation(decodeActivation(&reader))
        case .deletion:
            try .deletion(ReferenceDeletionState(isDeleted: reader.bool("deletion state")))
        case .inventory, .spawn, .quest, .questAliases:
            // Unreachable: none of these kinds has an RDLT tag, so `init?(saveTag:)`
            // never produces these cases and tags past 3 are rejected as
            // unknown. They are spelled out rather than defaulted so that a
            // component kind added later fails to compile here instead of
            // decoding as something else.
            throw OpenSkySaveError.invalidValue(
                context: "\(kind) is carried by its own chunk, not by RDLT"
            )
        }
    }

    private static func decodeTransform(
        _ reader: inout SaveReader
    ) throws -> ReferenceTransformOverride {
        let position = try vector(&reader, "transform position")
        let rotation = try vector(&reader, "transform rotation")
        let scale = try reader.float32("transform scale")
        return ReferenceTransformOverride(position: position, rotation: rotation, scale: scale)
    }

    private static func decodeActivation(
        _ reader: inout SaveReader
    ) throws -> ReferenceActivationState {
        let activationCount = try reader.uint32("activation count")
        let isOpen = try reader.bool("activation open flag")
        let hasActivator = try reader.bool("activation last-activator flag")
        let activator = try hasActivator ? decodeKey(&reader) : nil
        return ReferenceActivationState(
            activationCount: activationCount,
            isOpen: isOpen,
            lastActivator: activator
        )
    }

    private static func vector(
        _ reader: inout SaveReader,
        _ context: String
    ) throws -> SIMD3<Float> {
        let x = try reader.float32("\(context) x")
        let y = try reader.float32("\(context) y")
        let z = try reader.float32("\(context) z")
        return SIMD3(x, y, z)
    }
}
