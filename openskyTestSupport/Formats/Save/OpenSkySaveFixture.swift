// Synthetic fixtures for the OpenSky native save container tests (issue #161).
//
// Everything here is built in code: a save is OpenSky's own format, so no game
// data is involved at all, and no test reads a file from the install.
//
// Two construction paths exist on purpose. `richSnapshot` feeds the real
// encoder for round-trip and determinism coverage, while the byte builders
// assemble files field by field so a corruption test can put an exact bad
// value at an exact offset instead of hunting for one in encoder output.

import Foundation
@testable import opensky
import simd

nonisolated enum OpenSkySaveFixture {
    // MARK: - Logical fixtures

    static let metadata = SaveCreationMetadata(
        creationTimestamp: 1_700_000_000,
        appVersion: "0.1.0-test"
    )

    static let fingerprint = [
        SavePluginFingerprint(
            name: "Skyrim.esm",
            hedrVersion: 1.71,
            recordCount: 1_234_567,
            nextObjectID: 0x0010_0000
        ),
        SavePluginFingerprint(
            name: "Dawnguard.esm",
            hedrVersion: 0.94,
            recordCount: -5,
            nextObjectID: 0x0000_0800
        )
    ]

    static let whiterun = CellSceneLocation.exterior(CellCoordinate(x: -12, y: -3))
    static let riverwood = CellSceneLocation.exterior(CellCoordinate(x: 6, y: 1))
    static let inn = CellSceneLocation.interior(FormID(0xDEAD_BEEF))

    static let activator = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x14)

    /// One entry per shape the format can encode: both key kinds, all three
    /// cell tags, every component kind, `lastActivator` present and absent,
    /// negative exterior coordinates and a non-ASCII plugin name.
    static func richSnapshot(nextGeneratedSequence: UInt64 = 77) -> WorldStateSnapshot {
        let entries = [
            entry(
                key: .plugin(name: "dawnguard.esm", objectID: 0x000A_BCDE),
                cell: whiterun,
                components: [
                    ReferenceEnableState.disabled.erased,
                    ReferenceTransformOverride(
                        position: SIMD3(-1.5, 2.25, 3e10),
                        rotation: SIMD3(0.5, -0.25, 0),
                        scale: 1.75
                    ).erased,
                    ReferenceActivationState(
                        activationCount: 9,
                        isOpen: true,
                        lastActivator: activator
                    ).erased,
                    ReferenceDeletionState.deleted.erased
                ]
            ),
            entry(
                key: .plugin(name: "skyrim.esm", objectID: 1),
                cell: inn,
                components: [ReferenceTransformOverride(position: .zero).erased]
            ),
            entry(
                key: .plugin(name: "vílja í skyrim.esp", objectID: 0x00FF_FFFF),
                cell: nil,
                components: [
                    ReferenceEnableState.enabled.erased,
                    ReferenceDeletionState.notDeleted.erased
                ]
            ),
            entry(
                key: .generated(42),
                cell: riverwood,
                components: [
                    ReferenceActivationState(activationCount: 1, isOpen: false).erased
                ]
            )
        ]
        return WorldStateSnapshot(
            entries: entries.sorted { $0.key < $1.key },
            nextGeneratedSequence: nextGeneratedSequence,
            sequence: 1234
        )
    }

    static func entry(
        key: ReferenceKey,
        cell: CellSceneLocation?,
        components: [WorldStateComponentValue]
    ) -> WorldStateSnapshotEntry {
        var delta = ReferenceStateDelta(cell: cell)
        for component in components {
            delta.set(component)
        }
        return WorldStateSnapshotEntry(key: key, delta: delta)
    }

    static func encodedRichSave() -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: richSnapshot(),
            fingerprint: fingerprint,
            metadata: metadata
        )
    }

    // MARK: - Byte builders

    /// Header + fingerprint + the given chunk bytes, with everything valid
    /// except what a caller deliberately breaks.
    static func file(
        chunks: [Data],
        plugins: [SavePluginFingerprint] = fingerprint,
        version: UInt32 = OpenSkySaveFormat.currentVersion
    ) -> Data {
        var writer = BinaryWriter()
        writer.write(OpenSkySaveFormat.magic)
        writer.writeUInt32(version)
        var block = BinaryWriter()
        block.writeUInt64(metadata.creationTimestamp)
        writeString(metadata.appVersion, into: &block)
        writer.writeUInt32(UInt32(block.count))
        writer.write(block.data)
        writer.writeUInt32(UInt32(plugins.count))
        for plugin in plugins {
            writeString(plugin.name, into: &writer)
            writer.writeUInt32(plugin.hedrVersion.bitPattern)
            writer.writeUInt32(UInt32(bitPattern: plugin.recordCount))
            writer.writeUInt32(plugin.nextObjectID)
        }
        for chunk in chunks {
            writer.write(chunk)
        }
        return writer.data
    }

    static func chunk(_ tag: String, _ payload: Data, declaredLength: UInt32? = nil) -> Data {
        var writer = BinaryWriter()
        writer.write(Data(tag.utf8))
        writer.writeUInt32(declaredLength ?? UInt32(payload.count))
        writer.write(payload)
        return writer.data
    }

    static func allocatorChunk(_ sequence: UInt64 = 1) -> Data {
        var writer = BinaryWriter()
        writer.writeUInt64(sequence)
        return chunk(OpenSkySaveFormat.ChunkTag.allocator, writer.data)
    }

    /// An `RDLT` payload whose declared entry count can differ from the bytes
    /// that follow it, which is exactly what a corrupt count looks like.
    static func entriesPayload(count: UInt32, entries: Data = Data()) -> Data {
        var writer = BinaryWriter()
        writer.writeUInt32(count)
        writer.write(entries)
        return writer.data
    }

    /// A single entry: plugin key, "no cell", then the caller's raw component
    /// bytes with the caller's own component count.
    static func entryBytes(componentCount: UInt8, components: Data) -> Data {
        var writer = BinaryWriter()
        writer.writeUInt8(OpenSkySaveFormat.KeyTag.plugin)
        writeString("skyrim.esm", into: &writer)
        writer.writeUInt32(0x0BAD)
        writer.writeUInt8(OpenSkySaveFormat.CellTag.absent)
        writer.writeUInt8(componentCount)
        writer.write(components)
        return writer.data
    }

    /// An `RDLT` chunk wrapped around a hand-built entry payload.
    static func deltasChunk(count: UInt32, entries: Data = Data()) -> Data {
        chunk(
            OpenSkySaveFormat.ChunkTag.referenceDeltas,
            entriesPayload(count: count, entries: entries)
        )
    }

    /// A single entry whose key and cell bytes are supplied raw, so a test can
    /// put an undefined discriminator in either position.
    static func rawEntry(
        key: Data,
        cell: Data,
        componentCount: UInt8,
        components: Data = Data()
    ) -> Data {
        var writer = BinaryWriter()
        writer.write(key)
        writer.write(cell)
        writer.writeUInt8(componentCount)
        writer.write(components)
        return writer.data
    }

    /// A well-formed plugin reference key.
    static func pluginKeyBytes(name: String = "skyrim.esm", objectID: UInt32 = 0x0BAD) -> Data {
        var writer = BinaryWriter()
        writer.writeUInt8(OpenSkySaveFormat.KeyTag.plugin)
        writeString(name, into: &writer)
        writer.writeUInt32(objectID)
        return writer.data
    }

    static func bytes(_ values: [UInt8]) -> Data {
        Data(values)
    }

    // MARK: - Layout arithmetic

    /// Length of the length-delimited metadata block, read from the file
    /// rather than assumed, so a test never hardcodes a header offset.
    static func metadataBlockLength(in data: Data) -> Int {
        let start = data.startIndex + 8
        var length = 0
        for offset in (0 ..< 4).reversed() {
            length = length << 8 | Int(data[start + offset])
        }
        return length
    }

    /// Offset of the fingerprint plugin count: magic, version, metadata length
    /// prefix and the metadata block itself.
    static func fingerprintOffset(in data: Data) -> Int {
        12 + metadataBlockLength(in: data)
    }

    /// On-disk size of one fingerprint plugin entry: name plus three stats.
    static func pluginEntrySize(_ plugin: SavePluginFingerprint) -> Int {
        2 + Data(plugin.name.utf8).count + 12
    }

    static func writeString(_ string: String, into writer: inout BinaryWriter) {
        let raw = Data(string.utf8)
        writer.writeUInt16(UInt16(raw.count))
        writer.write(raw)
    }

    // MARK: - Corruption helpers

    static func truncating(_ data: Data, to length: Int) -> Data {
        Data(data.prefix(length))
    }

    static func patching(_ data: Data, at offset: Int, with replacement: [UInt8]) -> Data {
        var copy = data
        copy.replaceSubrange(
            (copy.startIndex + offset) ..< (copy.startIndex + offset + replacement.count),
            with: replacement
        )
        return copy
    }

    static func inserting(_ inserted: Data, into data: Data, at offset: Int) -> Data {
        var copy = data
        copy.insert(contentsOf: inserted, at: copy.startIndex + offset)
        return copy
    }

    /// Offset of a chunk's four-byte tag inside an encoded file.
    static func offset(ofChunk tag: String, in data: Data) -> Int? {
        guard let range = data.range(of: Data(tag.utf8)) else { return nil }
        return range.lowerBound - data.startIndex
    }
}
