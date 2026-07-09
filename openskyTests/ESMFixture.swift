// Synthetic Skyrim SE plugin builder shared by ESM parser tests. Fixtures are
// built in code — never extracted game files (AGENTS.md "Legal & IP boundary").
// Layouts follow UESP "Skyrim Mod:Mod File Format"; see docs/formats/esm.md.

import Compression
import Foundation

enum ESMFixture {
    static func field(_ type: String, _ data: Data) -> Data {
        var out = Data(type.utf8)
        out.appendUInt16(UInt16(data.count))
        out.append(data)
        return out
    }

    /// XXXX size-extension pair: uint32 real size, then `type` with stored
    /// size 0 and `data.count` payload bytes.
    static func longField(_ type: String, _ data: Data) -> Data {
        var out = Data("XXXX".utf8)
        out.appendUInt16(4)
        out.appendUInt32(UInt32(data.count))
        out.append(Data(type.utf8))
        out.appendUInt16(0)
        out.append(data)
        return out
    }

    static func record(
        _ type: String,
        formID: UInt32 = 0,
        flags: UInt32 = 0,
        version: UInt16 = 44,
        data: Data
    ) -> Data {
        var out = Data(type.utf8)
        out.appendUInt32(UInt32(data.count))
        out.appendUInt32(flags)
        out.appendUInt32(formID)
        out.appendUInt16(0) // timestamp
        out.appendUInt16(0) // version control
        out.appendUInt16(version)
        out.appendUInt16(0) // unknown
        out.append(data)
        return out
    }

    /// Record with flag 0x40000: uint32 decompressedSize + zlib stream.
    static func compressedRecord(_ type: String, formID: UInt32 = 0, fieldData: Data) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(fieldData.count))
        data.append(zlibStream(fieldData))
        return record(type, formID: formID, flags: 0x0004_0000, data: data)
    }

    static func group(label: Data, groupType: Int32, contents: Data) -> Data {
        var out = Data("GRUP".utf8)
        out.appendUInt32(UInt32(24 + contents.count)) // size includes header
        out.append(label)
        out.appendUInt32(UInt32(bitPattern: groupType))
        out.appendUInt16(0) // timestamp
        out.appendUInt16(0) // version control
        out.appendUInt32(0) // unknown
        out.append(contents)
        return out
    }

    static func topGroup(_ recordType: String, contents: Data) -> Data {
        group(label: Data(recordType.utf8), groupType: 0, contents: contents)
    }

    /// Children group (world/cell/topic) labeled with the parent FormID.
    static func childGroup(parent: UInt32, groupType: Int32, contents: Data) -> Data {
        var label = Data()
        label.appendUInt32(parent)
        return group(label: label, groupType: groupType, contents: contents)
    }

    /// Exterior cell (sub-)block: label is int16 Y then int16 X (reversed).
    static func exteriorBlock(x: Int16, y: Int16, groupType: Int32, contents: Data) -> Data {
        var label = Data()
        label.appendUInt16(UInt16(bitPattern: y))
        label.appendUInt16(UInt16(bitPattern: x))
        return group(label: label, groupType: groupType, contents: contents)
    }

    /// TES4 header record: HEDR (version 1.71) plus optional author,
    /// description, and MAST/DATA master pairs.
    static func tes4(
        flags: UInt32 = 1,
        author: String? = nil,
        description: String? = nil,
        masters: [String] = []
    ) -> Data {
        var hedr = Data()
        hedr.appendUInt32(Float(1.71).bitPattern)
        hedr.appendUInt32(0) // record count
        hedr.appendUInt32(0x800) // next object ID
        var fields = field("HEDR", hedr)
        if let author {
            fields += field("CNAM", zstring(author))
        }
        if let description {
            fields += field("SNAM", zstring(description))
        }
        for master in masters {
            fields += field("MAST", zstring(master))
            var data = Data()
            data.appendUInt32(0) // DATA: uint64, always 0
            data.appendUInt32(0)
            fields += field("DATA", data)
        }
        return record("TES4", flags: flags, data: fields)
    }

    /// Null-terminated windows-1252 string (ASCII subset used in fixtures).
    static func zstring(_ string: String) -> Data {
        Data(string.utf8) + Data([0])
    }

    /// Full RFC 1950 zlib stream: 2-byte header, deflate payload, adler32.
    static func zlibStream(_ payload: Data) -> Data {
        let capacity = payload.count + 256
        var deflate = Data(count: capacity)
        let written = deflate.withUnsafeMutableBytes { destination in
            payload.withUnsafeBytes { source -> Int in
                guard
                    let destinationBase = destination.baseAddress,
                    let sourceBase = source.baseAddress
                else { return 0 }
                return compression_encode_buffer(
                    destinationBase.assumingMemoryBound(to: UInt8.self),
                    capacity,
                    sourceBase.assumingMemoryBound(to: UInt8.self),
                    payload.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        var out = Data([0x78, 0x9C])
        // Empty input makes the encoder report failure; emit the canonical
        // empty deflate stream (one final stored block) instead.
        out.append(written > 0 ? deflate.prefix(written) : Data([0x03, 0x00]))
        var s1: UInt32 = 1
        var s2: UInt32 = 0
        for byte in payload {
            s1 = (s1 + UInt32(byte)) % 65521
            s2 = (s2 + s1) % 65521
        }
        Swift.withUnsafeBytes(of: ((s2 << 16) | s1).bigEndian) { out.append(contentsOf: $0) }
        return out
    }
}
