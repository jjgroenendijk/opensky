// Reader for the OpenSky native save container (issue #161): header,
// load-order fingerprint and the chunk loop. Entry payload decoding lives in
// OpenSkySaveDecoderEntries.swift.
//
// Two tolerance rules are implemented here and they point in opposite
// directions on purpose. An unknown *chunk* is skipped using its declared
// length, so a save written by a newer build still loads its world state in an
// older one. An unknown *component kind* inside a known chunk is an error
// (see the entry decoder), because a delta that lost components is a world
// that is quietly wrong rather than one that is merely missing a feature.

import Foundation

nonisolated enum OpenSkySaveDecoder {
    /// Parsed chunk payloads, with the defaults an absent chunk implies.
    private struct Body {
        var entries: [WorldStateSnapshotEntry] = []
        /// Absent `GVAR` chunk means no global was overridden, which is also
        /// what a save written before that chunk existed means.
        var globals: [WorldStateGlobalSnapshotEntry] = []
        /// Matches `GeneratedReferenceAllocator`'s starting position, so a
        /// file with no `GALC` chunk restores an allocator that has handed
        /// out nothing.
        var nextGeneratedSequence: UInt64 = 1
        /// Absent `CLOK` chunk (issue #164) means the vanilla-start clock,
        /// which is also what a save written before that chunk existed means.
        var clock: GameClock?
        /// Absent `PSCR` chunk (issue #171) means no script instance state was
        /// saved, so every script starts from its compiled defaults — which is
        /// also what a save written before that chunk existed means.
        var scripts: [PapyrusInstanceState] = []
        /// Absent `PTMR` chunk (issue #277) means no update timer was pending,
        /// which is also what a save written before that chunk existed means.
        var timers: [PapyrusTimerState] = []
    }

    static func decode(_ data: Data) throws -> OpenSkySaveFile {
        var reader = SaveReader(data)
        let magic = try reader.bytes(OpenSkySaveFormat.magic.count, "magic")
        guard magic == OpenSkySaveFormat.magic else {
            throw OpenSkySaveError.badMagic
        }
        let version = try reader.uint32("format version")
        guard version == OpenSkySaveFormat.currentVersion else {
            throw OpenSkySaveError.unsupportedVersion(found: version)
        }
        let metadata = try decodeMetadata(&reader)
        let fingerprint = try decodeFingerprint(&reader)
        let body = try decodeChunks(&reader)
        return OpenSkySaveFile(
            formatVersion: version,
            metadata: metadata,
            fingerprint: fingerprint,
            snapshot: WorldStateSnapshot(
                entries: body.entries,
                nextGeneratedSequence: body.nextGeneratedSequence,
                globals: body.globals,
                sequence: 0
            ),
            allocator: GeneratedReferenceAllocator(nextSequence: body.nextGeneratedSequence),
            clock: body.clock,
            scripts: body.scripts,
            timers: body.timers
        )
    }

    // MARK: - Header

    /// Metadata is length-delimited so unknown trailing fields a newer build
    /// added are skipped rather than mistaken for the fingerprint.
    private static func decodeMetadata(_ reader: inout SaveReader) throws -> SaveCreationMetadata {
        let length = try Int(reader.uint32("metadata length"))
        let block = try reader.bytes(length, "metadata")
        var blockReader = SaveReader(block)
        let timestamp = try blockReader.uint64("metadata creation timestamp")
        let appVersion = try blockReader.string("metadata app version")
        return SaveCreationMetadata(creationTimestamp: timestamp, appVersion: appVersion)
    }

    private static func decodeFingerprint(
        _ reader: inout SaveReader
    ) throws -> [SavePluginFingerprint] {
        let count = try reader.uint32("fingerprint plugin count")
        try validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumFingerprintEntrySize,
            remaining: reader.bytesRemaining,
            chunk: "fingerprint"
        )
        var plugins: [SavePluginFingerprint] = []
        plugins.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let name = try reader.string("plugin name")
            let hedrVersion = try Float(bitPattern: reader.uint32("plugin HEDR version"))
            let recordCount = try Int32(bitPattern: reader.uint32("plugin record count"))
            let nextObjectID = try reader.uint32("plugin next object ID")
            plugins.append(SavePluginFingerprint(
                name: name,
                hedrVersion: hedrVersion,
                recordCount: recordCount,
                nextObjectID: nextObjectID
            ))
        }
        return plugins
    }

    // MARK: - Chunks

    private static func decodeChunks(_ reader: inout SaveReader) throws -> Body {
        var body = Body()
        while !reader.isAtEnd {
            let tag = try tagName(reader.bytes(4, "chunk tag"))
            let length = try Int(reader.uint32("chunk length"))
            guard length <= reader.bytesRemaining else {
                throw OpenSkySaveError.chunkBoundsViolation(tag: tag)
            }
            let payload = try reader.bytes(length, "chunk payload")
            try apply(tag: tag, payload: payload, to: &body)
        }
        return body
    }

    /// Printable name for a four-byte chunk tag.
    ///
    /// A tag that is not valid UTF-8 is reported as hex rather than dropped:
    /// an unreadable tag is exactly the corruption whose error message needs to
    /// say what it saw, and an unknown tag is skipped by its length anyway.
    private static func tagName(_ bytes: Data) -> String {
        String(bytes: bytes, encoding: .utf8) ?? bytes.map { String(format: "%02X", $0) }.joined()
    }

    private static func apply(tag: String, payload: Data, to body: inout Body) throws {
        switch tag {
        case OpenSkySaveFormat.ChunkTag.allocator:
            guard payload.count == MemoryLayout<UInt64>.size else {
                throw OpenSkySaveError.invalidValue(
                    context: "GALC payload is \(payload.count) bytes, expected 8"
                )
            }
            var payloadReader = SaveReader(payload)
            body.nextGeneratedSequence = try payloadReader.uint64("GALC next generated sequence")
        case OpenSkySaveFormat.ChunkTag.referenceDeltas:
            body.entries = try OpenSkySaveEntryDecoder.decodeEntries(payload)
        case OpenSkySaveFormat.ChunkTag.globalValues:
            body.globals = try OpenSkySaveEntryDecoder.decodeGlobals(payload)
        case OpenSkySaveFormat.ChunkTag.clock:
            body.clock = try decodeClock(payload)
        case OpenSkySaveFormat.ChunkTag.papyrusScripts:
            body.scripts = try OpenSkySaveScriptDecoder.decodeScripts(payload)
        case OpenSkySaveFormat.ChunkTag.papyrusTimers:
            body.timers = try OpenSkySaveTimerDecoder.decodeTimers(payload)
        default:
            break // Unknown chunk: skipped by its declared length.
        }
    }

    /// `CLOK` payload: one `Float64` bit pattern of the clock's total game
    /// seconds. A non-finite or negative value is corruption, not a clock.
    private static func decodeClock(_ payload: Data) throws -> GameClock {
        guard payload.count == MemoryLayout<UInt64>.size else {
            throw OpenSkySaveError.invalidValue(
                context: "CLOK payload is \(payload.count) bytes, expected 8"
            )
        }
        var payloadReader = SaveReader(payload)
        let seconds = try Double(bitPattern: payloadReader.uint64("CLOK total game seconds"))
        guard seconds.isFinite, seconds >= 0 else {
            throw OpenSkySaveError.invalidValue(
                context: "CLOK total game seconds is \(seconds), expected a finite value >= 0"
            )
        }
        return GameClock(totalGameSeconds: seconds)
    }

    /// Rejects a declared element count that cannot possibly fit in the bytes
    /// left, before anything reserves storage for it. Without this a corrupt
    /// four-byte count is an out-of-memory crash rather than a thrown error.
    static func validate(
        count: UInt32,
        minimumElementSize: Int,
        remaining: Int,
        chunk: String
    ) throws {
        guard Int(count) <= remaining / minimumElementSize else {
            throw OpenSkySaveError.invalidCount(
                chunk: chunk,
                count: count,
                remaining: remaining
            )
        }
    }
}
