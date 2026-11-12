// Writer for the OpenSky native save container. `encode` never throws. A string over
// 64 KiB is truncated at a UTF-8 boundary rather than failing the save.

public import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkySaveInterface
public import OpenSkyScriptingInterface
public import OpenSkyWorldState

nonisolated public enum OpenSkySaveEncoder: Sendable {
    /// Serializes a snapshot, its fingerprint and header metadata, byte-deterministic:
    /// key order, ascending tags, no clock or hash seed. Only the header depends on
    /// `metadata`. A nil `clock`, `summary`, `thumbnail`, or `playerPlace`, or empty
    /// `scripts`/`timers`,
    /// writes no chunk.
    public static func encode(
        snapshot: WorldStateSnapshot,
        fingerprint: [SavePluginFingerprint],
        metadata: SaveCreationMetadata,
        clock: GameClock? = nil,
        scripts: [PapyrusInstanceState] = [],
        timers: [PapyrusTimerState] = [],
        summary: SaveSummary? = nil,
        thumbnail: SaveThumbnail? = nil,
        playerPlace: SavePlayerPlace? = nil
    ) -> Data {
        var writer = BinaryWriter()
        writeHeader(metadata: metadata, into: &writer)
        writeFingerprint(fingerprint, into: &writer)
        if let summary {
            OpenSkySaveSummaryCodec.write(summary, into: &writer)
        }
        if let thumbnail {
            OpenSkySaveSummaryCodec.write(thumbnail, into: &writer)
        }
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.allocator) { payload in
            payload.writeUInt64(snapshot.nextGeneratedSequence)
        }
        // Only entries with at least one RDLT-carried component go in RDLT: a
        // reference whose sole delta is its inventory belongs entirely to the
        // INVN chunk, and writing it here as a zero-component entry would make
        // an older build restore a dirty reference with nothing in it.
        let deltaEntries = snapshot.entries.filter { !savedKinds(of: $0.delta).isEmpty }
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.referenceDeltas) { payload in
            payload.writeUInt32(UInt32(clamping: deltaEntries.count))
            for entry in deltaEntries {
                writeEntry(entry, into: &payload)
            }
        }
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.globalValues) { payload in
            payload.writeUInt32(UInt32(clamping: snapshot.globals.count))
            for entry in snapshot.globals {
                payload.writeKey(entry.key)
                payload.writeUInt8(entry.value.type.saveTag)
                payload.writeFloat32(entry.value.value)
            }
        }
        if let clock {
            writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.clock) { payload in
                payload.writeUInt64(clock.totalGameSeconds.bitPattern)
            }
        }
        if !scripts.isEmpty {
            writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.papyrusScripts) { payload in
                payload.writeUInt32(UInt32(clamping: scripts.count))
                for state in scripts {
                    writeScriptInstance(state, into: &payload)
                }
            }
        }
        if !timers.isEmpty {
            writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.papyrusTimers) { payload in
                payload.writeUInt32(UInt32(clamping: timers.count))
                for state in timers {
                    writeTimer(state, into: &payload)
                }
            }
        }
        if let playerPlace {
            OpenSkySavePlayerPlaceWriter.writePlayerPlace(playerPlace, into: &writer)
        }
        writeComponentChunks(snapshot.entries, into: &writer)
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
        block.writeString(metadata.appVersion)
        writer.writeUInt32(UInt32(clamping: block.count))
        writer.write(block.data)
    }

    private static func writeFingerprint(
        _ fingerprint: [SavePluginFingerprint],
        into writer: inout BinaryWriter
    ) {
        writer.writeUInt32(UInt32(clamping: fingerprint.count))
        for plugin in fingerprint {
            writer.writeString(plugin.name)
            writer.writeUInt32(plugin.hedrVersion.bitPattern)
            writer.writeUInt32(UInt32(bitPattern: plugin.recordCount))
            writer.writeUInt32(plugin.nextObjectID)
        }
    }

    // MARK: - Entries

    private static func writeEntry(
        _ entry: WorldStateSnapshotEntry,
        into writer: inout BinaryWriter
    ) {
        writer.writeKey(entry.key)
        writer.writeCell(entry.delta.cell)
        let kinds = savedKinds(of: entry.delta)
        writer.writeUInt8(UInt8(clamping: kinds.count))
        for (kind, tag) in kinds {
            guard let value = entry.delta[kind] else { continue }
            writer.writeUInt8(tag)
            writeComponent(value, into: &writer)
        }
    }

    /// The delta's components that travel in `RDLT`, paired with their on-disk
    /// tags and sorted by tag — the strictly ascending order the decoder
    /// requires, independent of the enum's declaration order. A kind with no
    /// tag (`.inventory`) is carried by its own chunk and drops out here.
    private static func savedKinds(
        of delta: ReferenceStateDelta
    ) -> [(kind: WorldStateComponentKind, tag: UInt8)] {
        delta.sortedKinds
            .compactMap { kind in kind.saveTag.map { (kind: kind, tag: $0) } }
            .sorted { $0.tag < $1.tag }
    }

    private static func writeComponent(
        _ value: WorldStateComponentValue,
        into writer: inout BinaryWriter
    ) {
        // Only the four RDLT kinds reach this: `savedKinds(of:)` drops every
        // kind without an RDLT tag, and those travel in their own chunks.
        if let state = value.value(as: ReferenceEnableState.self) {
            writer.writeUInt8(state.isEnabled ? 1 : 0)
        } else if let state = value.value(as: ReferenceTransformOverride.self) {
            for component in [state.position, state.rotation] {
                writer.writeFloat32(component.x)
                writer.writeFloat32(component.y)
                writer.writeFloat32(component.z)
            }
            writer.writeFloat32(state.scale)
        } else if let state = value.value(as: ReferenceActivationState.self) {
            writer.writeUInt32(state.activationCount)
            writer.writeUInt8(state.isOpen ? 1 : 0)
            writer.writeUInt8(state.lastActivator == nil ? 0 : 1)
            if let activator = state.lastActivator {
                writer.writeKey(activator)
            }
        } else if let state = value.value(as: ReferenceDeletionState.self) {
            writer.writeUInt8(state.isDeleted ? 1 : 0)
        }
    }

    // MARK: - Papyrus script instances

    /// One `PSCR` instance: the reference the script is attached to, its
    /// script name, its active state, whether `OnInit` already fired, then its
    /// variables. Order is the caller's, which is
    /// `PapyrusWorldRuntime.instanceStates()` sorted by `PapyrusInstanceKey`
    /// with variables sorted by `(declaringScript, name)`, so re-encoding an
    /// unchanged runtime produces identical bytes.
    private static func writeScriptInstance(
        _ state: PapyrusInstanceState,
        into writer: inout BinaryWriter
    ) {
        writer.writeKey(state.key.reference)
        writer.writeString(state.key.scriptName)
        writer.writeString(state.activeState)
        writer.writeUInt8(state.hasFiredOnInit ? 1 : 0)
        writer.writeUInt32(UInt32(clamping: state.variables.count))
        for variable in state.variables {
            writer.writeString(variable.declaringScript)
            writer.writeString(variable.name)
            writeScriptValue(variable.value, into: &writer)
        }
    }

    /// A tag byte plus the value's payload. Floats go out as their IEEE
    /// bit pattern rather than through a decimal conversion, so the byte shape
    /// is exact and deterministic. `.object` and `.array` are written as the
    /// `none` tag: `instanceStates()` already snapshots them that way, and
    /// writing a runtime handle that means nothing after a reload would be
    /// worse than writing the type's default.
    private static func writeScriptValue(
        _ value: PapyrusValue,
        into writer: inout BinaryWriter
    ) {
        switch value {
        case .none, .object, .array:
            writer.writeUInt8(OpenSkySaveFormat.ValueTag.none)
        case let .boolean(flag):
            writer.writeUInt8(OpenSkySaveFormat.ValueTag.boolean)
            writer.writeUInt8(flag ? 1 : 0)
        case let .integer(number):
            writer.writeUInt8(OpenSkySaveFormat.ValueTag.integer)
            writer.writeUInt32(UInt32(bitPattern: number))
        case let .float(number):
            writer.writeUInt8(OpenSkySaveFormat.ValueTag.float)
            writer.writeUInt32(number.bitPattern)
        case let .string(text):
            writer.writeUInt8(OpenSkySaveFormat.ValueTag.string)
            writer.writeString(text)
        }
    }

    // MARK: - Papyrus update timers

    /// One `PTMR` entry: instance, slot, interval and remaining delay. Doubles go out as
    /// IEEE bits; the slot as its declared raw value (`PapyrusUpdateTimerSlot`). Callers
    /// pass `timerStates()` sorted by key then slot, so bytes repeat.
    private static func writeTimer(
        _ state: PapyrusTimerState,
        into writer: inout BinaryWriter
    ) {
        writer.writeKey(state.key.reference)
        writer.writeString(state.key.scriptName)
        writer.writeUInt8(UInt8(clamping: state.slot.rawValue))
        writer.writeUInt64(state.interval.bitPattern)
        writer.writeUInt64(state.remaining.bitPattern)
    }
}
