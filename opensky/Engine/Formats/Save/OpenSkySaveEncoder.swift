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
    /// no `CLOK` chunk, which decodes as the vanilla-start clock. `scripts` is
    /// defaulted empty for the same reason, and an empty list writes no `PSCR`
    /// chunk at all, so a session with no VM produces the same bytes it always
    /// did. `timers` behaves the same way and writes no `PTMR` chunk when it
    /// is empty.
    static func encode(
        snapshot: WorldStateSnapshot,
        fingerprint: [SavePluginFingerprint],
        metadata: SaveCreationMetadata,
        clock: GameClock? = nil,
        scripts: [PapyrusInstanceState] = [],
        timers: [PapyrusTimerState] = []
    ) -> Data {
        var writer = BinaryWriter()
        writeHeader(metadata: metadata, into: &writer)
        writeFingerprint(fingerprint, into: &writer)
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.allocator, into: &writer) { payload in
            payload.writeUInt64(snapshot.nextGeneratedSequence)
        }
        // Only entries with at least one RDLT-carried component go in RDLT: a
        // reference whose sole delta is its inventory belongs entirely to the
        // INVN chunk, and writing it here as a zero-component entry would make
        // an older build restore a dirty reference with nothing in it.
        let deltaEntries = snapshot.entries.filter { !savedKinds(of: $0.delta).isEmpty }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.referenceDeltas, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: deltaEntries.count))
            for entry in deltaEntries {
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
        if !scripts.isEmpty {
            writeChunk(tag: OpenSkySaveFormat.ChunkTag.papyrusScripts, into: &writer) { payload in
                payload.writeUInt32(UInt32(clamping: scripts.count))
                for state in scripts {
                    writeScriptInstance(state, into: &payload)
                }
            }
        }
        if !timers.isEmpty {
            writeChunk(tag: OpenSkySaveFormat.ChunkTag.papyrusTimers, into: &writer) { payload in
                payload.writeUInt32(UInt32(clamping: timers.count))
                for state in timers {
                    writeTimer(state, into: &payload)
                }
            }
        }
        writeInventories(snapshot.entries, into: &writer)
        writeSpawnedReferences(snapshot.entries, into: &writer)
        writeQuestStates(snapshot.entries, into: &writer)
        writeQuestAliases(snapshot.entries, into: &writer)
        writeQuestLocationAliases(snapshot.entries, into: &writer)
        writeActorValues(snapshot.entries, into: &writer)
        writeActorValueOverrides(snapshot.entries, into: &writer)
        writeDeaths(snapshot.entries, into: &writer)
        writeCombatStates(snapshot.entries, into: &writer)
        writeDialogueStates(snapshot.entries, into: &writer)
        writeActiveEffects(snapshot.entries, into: &writer)
        writeSpellbooks(snapshot.entries, into: &writer)
        writeEnchantedItems(snapshot.entries, into: &writer)
        writePerks(snapshot.entries, into: &writer)
        writePlayerProgress(snapshot.entries, into: &writer)
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
    static func writeChunk(
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

    static func writeKey(_ key: ReferenceKey, into writer: inout BinaryWriter) {
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

    static func writeCell(_ cell: CellSceneLocation?, into writer: inout BinaryWriter) {
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
        case .inventory, .spawn, .quest, .questAliases, .actorValues, .death,
             .combat, .dialogue, .activeEffects, .spellbook, .enchantedItems, .perks,
             .playerProgress:
            // Unreachable: `savedKinds(of:)` drops every kind without an RDLT
            // tag, and none of these has one — they travel in the INVN, SPWN,
            // QSTS, QALS, AVAL, DETH, CBTS, DLGS, AEFF, SPLB, ECHG, PRKS and
            // PLVL chunks. The cases exist so that adding a component kind is a
            // compile error here rather than a silently unwritten component.
            break
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
        writeKey(state.key.reference, into: &writer)
        writeString(state.key.scriptName, into: &writer)
        writeString(state.activeState, into: &writer)
        writer.writeUInt8(state.hasFiredOnInit ? 1 : 0)
        writer.writeUInt32(UInt32(clamping: state.variables.count))
        for variable in state.variables {
            writeString(variable.declaringScript, into: &writer)
            writeString(variable.name, into: &writer)
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
            writeString(text, into: &writer)
        }
    }

    // MARK: - Papyrus update timers

    /// One `PTMR` entry: the instance the timer belongs to, which slot of the
    /// four it occupies, its registered interval, and the delay still to run.
    /// Both doubles go out as their IEEE bit pattern for the same reason
    /// script floats do — the byte shape is exact and deterministic.
    ///
    /// The slot goes out as its enum raw value, which is a declared on-disk
    /// number rather than a source-order accident (see
    /// `PapyrusUpdateTimerSlot`), so no separate tag table is needed here.
    /// Order is the caller's, which is `PapyrusWorldRuntime.timerStates()`
    /// sorted by instance key then slot, so re-encoding an unchanged runtime
    /// produces identical bytes.
    private static func writeTimer(
        _ state: PapyrusTimerState,
        into writer: inout BinaryWriter
    ) {
        writeKey(state.key.reference, into: &writer)
        writeString(state.key.scriptName, into: &writer)
        writer.writeUInt8(UInt8(clamping: state.slot.rawValue))
        writer.writeUInt64(state.interval.bitPattern)
        writer.writeUInt64(state.remaining.bitPattern)
    }

    // MARK: - Strings

    /// UInt16 byte length + UTF-8 bytes. Strings longer than `UInt16.max`
    /// bytes are cut back to the last whole UTF-8 scalar that fits, so the
    /// decoder still sees valid text.
    static func writeString(_ string: String, into writer: inout BinaryWriter) {
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
