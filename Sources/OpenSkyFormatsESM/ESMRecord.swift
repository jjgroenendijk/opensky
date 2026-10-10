// Plugin record: 24-byte header plus fields. A compressed record (flag
// 0x00040000) stores a UInt32 decompressed size, then a zlib stream. Fields
// are read on demand. Layout: docs/formats/esm.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum ESMError: Error, Equatable, Sendable {
    /// File does not start with a TES4 header record.
    case missingTES4
    /// Structural damage: truncated headers, sizes past the container end, ...
    case malformed(String)
}

nonisolated public struct ESMRecord: Sendable {
    /// Record flag bits OpenSky interprets. Many bits are per-record-type
    /// overloads (see UESP table); only globally-meaningful ones live here.
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// TES4: ESM file, pinned to the top of the load order.
        public static let esm = Flags(rawValue: 1 << 0)
        public static let deleted = Flags(rawValue: 1 << 5)
        /// TES4: strings live in .strings/.dlstrings/.ilstrings tables.
        public static let localized = Flags(rawValue: 1 << 7)
        /// TES4: ESL (light) file, loaded into the 0xFE FormID space.
        public static let esl = Flags(rawValue: 1 << 9)
        /// REFR/ACHR: the reference stays in memory when its cell unloads (UESP 0x400).
        public static let persistent = Flags(rawValue: 1 << 10)
        /// REFR/ACHR: placed reference starts disabled until a script or
        /// quest enables it (UESP record-header flag 0x800).
        public static let initiallyDisabled = Flags(rawValue: 1 << 11)
        public static let ignored = Flags(rawValue: 1 << 12)
        /// GLOB: the global is constant and the Creation Kit refuses to let a
        /// script write it (UESP GLOB record-header flag 0x40).
        public static let constantGlobal = Flags(rawValue: 1 << 6)
        /// Data is uint32 decompressedSize + zlib stream.
        public static let compressed = Flags(rawValue: 1 << 18)
        /// ACTI, DOOR, FURN, STAT: an editor-only marker the game does not draw.
        public static let marker = Flags(rawValue: 1 << 23)
    }

    /// The record types whose header bit 23 means `Is Marker` (xEdit dev-4.1.6).
    public static let markerFlagTypes: Set<FourCC> = ["ACTI", "DOOR", "FURN", "STAT"]

    /// 24-byte SSE record header (Oblivion's is 20 — not supported).
    public struct Header: Sendable {
        public static let size = 24

        public let type: FourCC
        public let dataSize: UInt32
        public let flags: Flags
        public let formID: UInt32
        public let timestamp: UInt16
        public let versionControl: UInt16
        /// Internal form version: 43 = Skyrim LE, 44 = SSE.
        public let version: UInt16
        public let unknown: UInt16

        public init(reader: inout BinaryReader) throws {
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

    public let header: Header
    /// Absolute range of the (possibly compressed) data payload in `file`.
    public let dataRange: Range<Int>
    /// The whole plugin file (memory-mapped); payloads stay untouched until
    /// `fieldData()` is called.
    private let file: Data

    public init(header: Header, dataRange: Range<Int>, file: Data) {
        self.header = header
        self.dataRange = dataRange
        self.file = file
    }

    public var type: FourCC {
        header.type
    }

    public var formID: UInt32 {
        header.formID
    }

    public var flags: Flags {
        header.flags
    }

    public var isCompressed: Bool {
        header.flags.contains(.compressed)
    }

    public var isDeleted: Bool {
        header.flags.contains(.deleted)
    }

    public var isInitiallyDisabled: Bool {
        header.flags.contains(.initiallyDisabled)
    }

    /// A base object placed only as an editor marker, such as `XMarkerHeading`.
    public var isEditorMarker: Bool {
        Self.markerFlagTypes.contains(type) && header.flags.contains(.marker)
    }

    /// Field bytes, zlib-decompressed when the record is compressed.
    public func fieldData() throws -> Data {
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
    public func fields() throws -> [ESMField] {
        try ESMField.parseAll(fieldData())
    }
}
