// Skyrim SE localized string table reader. Plugins with the TES4 "localized"
// flag (0x80) keep display text out-of-band in per-language tables at
// Strings/<plugin>_<language>.{strings,dlstrings,ilstrings} (loose or in BSA);
// records store a uint32 string ID where an inline zstring would sit.
//
// Reference: UESP "Skyrim Mod:String Table File Format"
//   https://en.uesp.net/wiki/Skyrim_Mod:String_Table_File_Format
// Layout documented in docs/formats/strings.md.

import Foundation

nonisolated enum StringTableError: Error, Equatable {
    case malformed(String)
    /// Directory or entry points outside the data block.
    case entryOutOfRange(id: UInt32)
}

/// One parsed table. Directory is decoded eagerly (small); string bytes are
/// located and decoded per lookup, so a table over a mapped file stays cheap.
nonisolated struct StringTable {
    /// Entry framing differs by file extension; the header is identical.
    enum Kind {
        /// Bare zstring entries (most UI text).
        case strings
        /// uint32 byte length (terminator included) + zstring. Book text,
        /// descriptions (DL) and dialogue/info text (IL) use this framing.
        case dlstrings
        case ilstrings

        init?(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "strings": self = .strings
            case "dlstrings": self = .dlstrings
            case "ilstrings": self = .ilstrings
            default: return nil
            }
        }

        var isLengthPrefixed: Bool {
            self != .strings
        }
    }

    let kind: Kind
    private let dataBlock: Data
    /// String ID -> byte offset into `dataBlock`. Duplicate IDs keep the
    /// first occurrence (mirrors first-wins lookup in xEdit).
    private let offsets: [UInt32: UInt32]

    var count: Int {
        offsets.count
    }

    var isEmpty: Bool {
        offsets.isEmpty
    }

    var ids: [UInt32] {
        Array(offsets.keys)
    }

    init(data: Data, kind: Kind) throws {
        self.kind = kind
        var reader = BinaryReader(data)
        guard
            let entryCount = try? Int(reader.readUInt32()),
            let dataSize = try? Int(reader.readUInt32())
        else {
            throw StringTableError.malformed("file shorter than 8-byte header")
        }

        let directorySize = entryCount * 8
        let dataStart = 8 + directorySize
        // Lenient on trailing garbage, strict on truncation.
        guard dataStart + dataSize <= data.count else {
            throw StringTableError.malformed(
                "header claims \(entryCount) entries + \(dataSize) data bytes, "
                    + "file has \(data.count)"
            )
        }

        var offsets: [UInt32: UInt32] = [:]
        offsets.reserveCapacity(entryCount)
        for _ in 0 ..< entryCount {
            let id = try reader.readUInt32()
            let offset = try reader.readUInt32()
            guard Int(offset) < dataSize else {
                throw StringTableError.entryOutOfRange(id: id)
            }
            if offsets[id] == nil { offsets[id] = offset }
        }

        dataBlock = data.subdata(
            in: (data.startIndex + dataStart) ..< (data.startIndex + dataStart + dataSize)
        )
        self.offsets = offsets
    }

    /// Looks up one string by ID. Unknown ID -> nil; entry that cannot be
    /// framed or decoded -> throws.
    func string(id: UInt32) throws -> String? {
        guard let offset = offsets[id] else { return nil }
        var reader = BinaryReader(dataBlock, offset: Int(offset))

        let bytes: Data
        if kind.isLengthPrefixed {
            guard
                let length = try? Int(reader.readUInt32()),
                var framed = try? reader.read(count: length)
            else {
                throw StringTableError.entryOutOfRange(id: id)
            }
            // Length counts the null terminator; tolerate files without one.
            if framed.last == 0 { framed = framed.dropLast() }
            bytes = framed
        } else {
            guard let zstring = try? reader.readZStringData() else {
                throw StringTableError.entryOutOfRange(id: id)
            }
            bytes = zstring
        }
        return try Self.decode(bytes, id: id)
    }

    /// The format carries no encoding marker and the wild mixes UTF-8 with
    /// legacy codepages. Lenient policy: bytes that form valid UTF-8 are
    /// UTF-8 (accidental valid UTF-8 is rare), everything else decodes as
    /// windows-1252 like the rest of the engine's strings.
    private static func decode(_ bytes: Data, id: UInt32) throws -> String {
        if let utf8 = String(data: bytes, encoding: .utf8) { return utf8 }
        guard let cp1252 = String(data: bytes, encoding: .windowsCP1252) else {
            throw StringTableError.malformed("string \(id) is not decodable text")
        }
        return cp1252
    }
}
