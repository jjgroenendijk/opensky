// Writer for the OpenSky native save container (issue #161).
//
// Encoding is total: every input this engine can produce has a byte
// representation, so `encode` does not throw. The one lossy edge is a string
// longer than 64 KiB, which is truncated at a UTF-8 boundary rather than
// failing the save — a plugin file name or app version that long is already
// nonsense, and losing a save over it would be worse than losing the tail.

import Foundation

nonisolated enum OpenSkySaveEncoder {
    /// Serializes a snapshot, its load-order fingerprint and header metadata.
    ///
    /// Byte-for-byte deterministic given equal arguments: entries are written
    /// in the snapshot's `ReferenceKey` order, components in ascending on-disk
    /// tag order, and nothing consults the clock or a hash seed. Only the
    /// header region depends on `metadata`, so two saves of the same state
    /// taken at different times share an identical tail.
    /// `clock` is optional so pre-clock call sites keep compiling; nil writes
    /// no `CLOK` chunk, which decodes as the vanilla-start clock.
    static func encode(
        snapshot: WorldStateSnapshot,
        fingerprint: [SavePluginFingerprint],
        metadata: SaveCreationMetadata,
        clock: GameClock? = nil
    ) -> Data {
        var writer = BinaryWriter()
        writeHeader(metadata: metadata, into: &writer)
        writeFingerprint(fingerprint, into: &writer)
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.allocator, into: &writer) { payload in
            payload.writeUInt64(snapshot.nextGeneratedSequence)
        }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.referenceDeltas, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: snapshot.entries.count))
            for entry in snapshot.entries {
                writeEntry(entry, into: &payload)
            }
        }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.globalValues, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: snapshot.globals.count))
            for entry in snapshot.globals {
                writeKey(entry.key, into: &payload)
                payload.writeUInt8(entry.value.type.saveTag)
                payload.writeFloat32(entry.value.value)
            }
        }
        if let clock {
            writeChunk(tag: OpenSkySaveFormat.ChunkTag.clock, into: &writer) { payload in
                payload.writeUInt64(clock.totalGameSeconds.bitPattern)
            }
        }
        return writer.data
    }

    // MARK: - Header

    private static func writeHeader(
        metadata: SaveCreationMetadata,
        into writer: inout BinaryWriter
    ) {
        writer.write(OpenSkySaveFormat.magic)
        writer.writeUInt32(OpenSkySaveFormat.currentVersion)
        var block = BinaryWriter()
        block.writeUInt64(metadata.creationTimestamp)
        writeString(metadata.appVersion, into: &block)
        writer.writeUInt32(UInt32(clamping: block.count))
        writer.write(block.data)
    }

    private static func writeFingerprint(
        _ fingerprint: [SavePluginFingerprint],
        into writer: inout BinaryWriter
    ) {
        writer.writeUInt32(UInt32(clamping: fingerprint.count))
        for plugin in fingerprint {
            writeString(plugin.name, into: &writer)
            writer.writeUInt32(plugin.hedrVersion.bitPattern)
            writer.writeUInt32(UInt32(bitPattern: plugin.recordCount))
            writer.writeUInt32(plugin.nextObjectID)
        }
    }

    /// Writes `tag` plus the length-prefixed bytes `body` produces, so a
    /// decoder that does not know the tag can skip exactly the right amount.
    private static func writeChunk(
        tag: String,
        into writer: inout BinaryWriter,
        body: (inout BinaryWriter) -> Void
    ) {
        var payload = BinaryWriter()
        body(&payload)
        writer.write(Data(tag.utf8))
        writer.writeUInt32(UInt32(clamping: payload.count))
        writer.write(payload.data)
    }

    // MARK: - Entries

    private static func writeEntry(
        _ entry: WorldStateSnapshotEntry,
        into writer: inout BinaryWriter
    ) {
        writeKey(entry.key, into: &writer)
        writeCell(entry.delta.cell, into: &writer)
        // Sorted by on-disk tag, which is the strictly ascending order the
        // decoder requires, independent of the enum's declaration order.
        let kinds = entry.delta.sortedKinds.sorted { $0.saveTag < $1.saveTag }
        writer.writeUInt8(UInt8(clamping: kinds.count))
        for kind in kinds {
            guard let value = entry.delta[kind] else { continue }
            writer.writeUInt8(kind.saveTag)
            writeComponent(value, into: &writer)
        }
    }

    private static func writeKey(_ key: ReferenceKey, into writer: inout BinaryWriter) {
        switch key {
        case let .plugin(name, objectID):
            writer.writeUInt8(OpenSkySaveFormat.KeyTag.plugin)
            writeString(name, into: &writer)
            writer.writeUInt32(objectID)
        case let .generated(sequence):
            writer.writeUInt8(OpenSkySaveFormat.KeyTag.generated)
            writer.writeUInt64(sequence)
        }
    }

    private static func writeCell(_ cell: CellSceneLocation?, into writer: inout BinaryWriter) {
        switch cell {
        case .none:
            writer.writeUInt8(OpenSkySaveFormat.CellTag.absent)
        case let .exterior(coordinate):
            writer.writeUInt8(OpenSkySaveFormat.CellTag.exterior)
            writer.writeUInt32(UInt32(bitPattern: coordinate.x))
            writer.writeUInt32(UInt32(bitPattern: coordinate.y))
        case let .interior(formID):
            writer.writeUInt8(OpenSkySaveFormat.CellTag.interior)
            writer.writeUInt32(formID.rawValue)
        }
    }

    private static func writeComponent(
        _ value: WorldStateComponentValue,
        into writer: inout BinaryWriter
    ) {
        switch value {
        case let .enableState(state):
            writer.writeUInt8(state.isEnabled ? 1 : 0)
        case let .transform(state):
            for component in [state.position, state.rotation] {
                writer.writeFloat32(component.x)
                writer.writeFloat32(component.y)
                writer.writeFloat32(component.z)
            }
            writer.writeFloat32(state.scale)
        case let .activation(state):
            writer.writeUInt32(state.activationCount)
            writer.writeUInt8(state.isOpen ? 1 : 0)
            writer.writeUInt8(state.lastActivator == nil ? 0 : 1)
            if let activator = state.lastActivator {
                writeKey(activator, into: &writer)
            }
        case let .deletion(state):
            writer.writeUInt8(state.isDeleted ? 1 : 0)
        }
    }

    // MARK: - Strings

    /// UInt16 byte length + UTF-8 bytes. Strings longer than `UInt16.max`
    /// bytes are cut back to the last whole UTF-8 scalar that fits, so the
    /// decoder still sees valid text.
    private static func writeString(_ string: String, into writer: inout BinaryWriter) {
        let bytes = truncatedUTF8(string)
        writer.writeUInt16(UInt16(clamping: bytes.count))
        writer.write(bytes)
    }

    private static func truncatedUTF8(_ string: String) -> Data {
        let bytes = Data(string.utf8)
        let limit = Int(UInt16.max)
        guard bytes.count > limit else { return bytes }
        var end = limit
        // 0b10xxxxxx is a UTF-8 continuation byte: back up until the cut lands
        // on a scalar boundary.
        while end > 0, bytes[bytes.startIndex + end] & 0xC0 == 0x80 {
            end -= 1
        }
        return Data(bytes.prefix(end))
    }
}
