// Skyrim SE plugin (.esm/.esp/.esl) record: 24-byte header + field payload.
// Compressed records (flag 0x00040000) store uint32 decompressedSize followed
// by a zlib stream. Payload bytes are only read when fields are requested.
//
// Reference: UESP "Skyrim Mod:Mod File Format"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format
// Layout documented in docs/formats/esm.md.

import Foundation

nonisolated package enum ESMError: Error, Equatable {
    /// File does not start with a TES4 header record.
    case missingTES4
    /// Structural damage: truncated headers, sizes past the container end, ...
    case malformed(String)
}

nonisolated package struct ESMRecord {
    /// Record flag bits OpenSky interprets. Many bits are per-record-type
    /// overloads (see UESP table); only globally-meaningful ones live here.
    package struct Flags: OptionSet {
        package let rawValue: UInt32

        package init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// TES4: ESM file, pinned to the top of the load order.
        package static let esm = Flags(rawValue: 1 << 0)
        package static let deleted = Flags(rawValue: 1 << 5)
        /// TES4: strings live in .strings/.dlstrings/.ilstrings tables.
        package static let localized = Flags(rawValue: 1 << 7)
        /// TES4: ESL (light) file, loaded into the 0xFE FormID space.
        package static let esl = Flags(rawValue: 1 << 9)
        /// REFR/ACHR: placed reference starts disabled until a script or
        /// quest enables it (UESP record-header flag 0x800).
        package static let initiallyDisabled = Flags(rawValue: 1 << 11)
        package static let ignored = Flags(rawValue: 1 << 12)
        /// GLOB: the global is constant and the Creation Kit refuses to let a
        /// script write it (UESP GLOB record-header flag 0x40).
        package static let constantGlobal = Flags(rawValue: 1 << 6)
        /// Data is uint32 decompressedSize + zlib stream.
        package static let compressed = Flags(rawValue: 1 << 18)
    }

    /// 24-byte SSE record header (Oblivion's is 20 — not supported).
    package struct Header {
        package static let size = 24

        package let type: FourCC
        package let dataSize: UInt32
        package let flags: Flags
        package let formID: UInt32
        package let timestamp: UInt16
        package let versionControl: UInt16
        /// Internal form version: 43 = Skyrim LE, 44 = SSE.
        package let version: UInt16
        package let unknown: UInt16

        package init(reader: inout BinaryReader) throws {
            type = try reader.readFourCC()
            dataSize = try reader.readUInt32()
            flags = try Flags(rawValue: reader.readUInt32())
            formID = try reader.readUInt32()
            timestamp = try reader.readUInt16()
            versionControl = try reader.readUInt16()
            version = try reader.readUInt16()
            unknown = try reader.readUInt16()
        }
    }

    package let header: Header
    /// Absolute range of the (possibly compressed) data payload in `file`.
    package let dataRange: Range<Int>
    /// The whole plugin file (memory-mapped); payloads stay untouched until
    /// `fieldData()` is called.
    private let file: Data

    package init(header: Header, dataRange: Range<Int>, file: Data) {
        self.header = header
        self.dataRange = dataRange
        self.file = file
    }

    package var type: FourCC {
        header.type
    }

    package var formID: UInt32 {
        header.formID
    }

    package var flags: Flags {
        header.flags
    }

    package var isCompressed: Bool {
        header.flags.contains(.compressed)
    }

    package var isDeleted: Bool {
        header.flags.contains(.deleted)
    }

    package var isInitiallyDisabled: Bool {
        header.flags.contains(.initiallyDisabled)
    }

    /// Field bytes, zlib-decompressed when the record is compressed.
    package func fieldData() throws -> Data {
        var reader = BinaryReader(file, offset: dataRange.lowerBound)
        guard isCompressed else {
            return try reader.read(count: dataRange.count)
        }
        let decompressedSize = try Int(reader.readUInt32())
        let stream = try reader.read(count: dataRange.count - 4)
        return try Zlib.decompress(stream, decompressedSize: decompressedSize)
    }

    /// Parses all fields. XXXX size extensions are resolved into the extended
    /// field; the XXXX marker itself is not emitted.
    package func fields() throws -> [ESMField] {
        try ESMField.parseAll(fieldData())
    }
}
