// NIF (NetImmerse/Gamebryo) file header for Skyrim SE meshes: version line,
// binary version, endianness, Bethesda stream header, block type table,
// per-block type indices + sizes, string table, groups. The size array (since
// 20.2.0.5) is what lets the container layer walk blocks it cannot decode.
//
// Reference: NifTools nif.xml (structs Header, BSStreamHeader, ExportString,
// SizedString; condexpr token BSSTREAMHEADER).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif.md.

import Foundation

nonisolated enum NIFError: Error, Equatable {
    /// Input violates the documented layout.
    case malformed(String)
    /// Valid NIF, but a variant OpenSky does not read (wrong version/endian).
    case unsupported(String)
}

nonisolated struct NIFHeader {
    /// Skyrim SE (and LE, FO3/NV) mesh version 20.2.0.7, one hex byte per
    /// version component. Only version with the block-size array we rely on.
    static let supportedVersion: UInt32 = 0x1402_0007

    /// BSStreamHeader — Bethesda export info. Present for 20.2.0.7 when
    /// user version >= 3 (nif.xml BSSTREAMHEADER condition). Skyrim LE
    /// streams 83, SSE streams 100.
    struct BSStream {
        let version: UInt32
        let author: String
        let processScript: String
        let exportScript: String
    }

    /// Newline-terminated text line, e.g. "Gamebryo File Format, Version
    /// 20.2.0.7". Informational; the binary `version` field is authoritative.
    let versionLine: String
    let version: UInt32
    /// 12 for Skyrim LE + SSE, 11 for FO3/NV.
    let userVersion: UInt32
    let blockCount: Int
    let bsStream: BSStream?
    /// Distinct block type names used by this file, e.g. "BSTriShape".
    let blockTypes: [String]
    /// Per block: index into `blockTypes`. PhysX flag bit already masked off.
    let blockTypeIndices: [Int]
    /// Per block: on-disk byte size, the skip distance for unknown types.
    let blockSizes: [Int]
    /// Shared string table; blocks refer to names by index into this.
    let strings: [String]
    let groups: [UInt32]
    /// Offset of the first block's bytes (= reader position after the header).
    let blockDataOffset: Int

    init(reader: inout BinaryReader) throws {
        versionLine = try Self.readVersionLine(&reader)
        version = try reader.readUInt32()
        guard version == Self.supportedVersion else {
            throw NIFError.unsupported(
                "NIF version 0x\(String(version, radix: 16)) (only 20.2.0.7 supported)"
            )
        }
        let endian = try reader.readUInt8()
        guard endian == 1 else { // 1 = ENDIAN_LITTLE
            throw NIFError.unsupported("big-endian NIF")
        }
        userVersion = try reader.readUInt32()
        blockCount = try Int(reader.readUInt32())

        // nif.xml BSSTREAMHEADER: for version 20.2.0.7 the condition reduces
        // to user version >= 3.
        bsStream = userVersion >= 3 ? try Self.readBSStream(&reader) : nil

        let blockTypeCount = try Int(reader.readUInt16())
        var blockTypes: [String] = []
        for _ in 0 ..< blockTypeCount {
            try blockTypes.append(Self.readSizedString(&reader))
        }
        self.blockTypes = blockTypes

        var blockTypeIndices: [Int] = []
        for block in 0 ..< blockCount {
            // Upper bit flags PhysX block types (nif.xml BlockTypeIndex).
            let index = try Int(reader.readUInt16() & 0x7FFF)
            guard index < blockTypes.count else {
                throw NIFError.malformed(
                    "block \(block) type index \(index) out of range (\(blockTypes.count) types)"
                )
            }
            blockTypeIndices.append(index)
        }
        self.blockTypeIndices = blockTypeIndices

        var blockSizes: [Int] = []
        for _ in 0 ..< blockCount {
            try blockSizes.append(Int(reader.readUInt32()))
        }
        self.blockSizes = blockSizes

        let stringCount = try Int(reader.readUInt32())
        _ = try reader.readUInt32() // max string length (write-time hint)
        var strings: [String] = []
        for _ in 0 ..< stringCount {
            try strings.append(Self.readSizedString(&reader))
        }
        self.strings = strings

        let groupCount = try Int(reader.readUInt32())
        var groups: [UInt32] = []
        for _ in 0 ..< groupCount {
            try groups.append(reader.readUInt32())
        }
        self.groups = groups

        blockDataOffset = reader.offset
    }

    /// HeaderString: bytes up to a newline (0x0A), capped so a non-NIF blob
    /// cannot make us scan megabytes for one.
    private static func readVersionLine(_ reader: inout BinaryReader) throws -> String {
        var bytes = Data()
        for _ in 0 ..< 128 {
            let byte = try reader.readUInt8()
            if byte == 0x0A {
                return GameText.decodeLossy(bytes)
            }
            bytes.append(byte)
        }
        throw NIFError.malformed("header version line missing newline terminator")
    }

    private static func readBSStream(_ reader: inout BinaryReader) throws -> BSStream {
        let version = try reader.readUInt32()
        let author = try readExportString(&reader)
        // nif.xml: FO4+ streams insert an extra uint and drop fields; reject
        // rather than misparse (Skyrim streams are 83/100).
        guard version <= 130 else {
            throw NIFError.unsupported("BS stream \(version) (Skyrim streams 83/100)")
        }
        let processScript = try readExportString(&reader)
        let exportScript = try readExportString(&reader)
        if version >= 103 { // "Max Filepath", FO4-era streams only
            _ = try readExportString(&reader)
        }
        return BSStream(
            version: version,
            author: author,
            processScript: processScript,
            exportScript: exportScript
        )
    }

    /// ExportString: byte length (null terminator included), then bytes.
    /// Same framing as BSA's bzstring.
    private static func readExportString(_ reader: inout BinaryReader) throws -> String {
        try reader.readBZString()
    }

    /// SizedString: uint32 length, then bytes, no terminator. Lossy decode:
    /// vanilla string tables carry exporter garbage (uninitialized memory),
    /// and a junk name must not reject the whole mesh.
    private static func readSizedString(_ reader: inout BinaryReader) throws -> String {
        let length = try Int(reader.readUInt32())
        let bytes = try reader.read(count: length)
        return GameText.decodeLossy(bytes)
    }
}
