// Skyrim SE localized string table reader. A plugin with the TES4 localized
// flag (0x80) stores a uint32 string ID where a zstring would sit, and the text
// lives in Strings/<plugin>_<language>.{strings,dlstrings,ilstrings}.
// Layout and sources: docs/formats/strings.md.

import Foundation

nonisolated public enum StringTableError: Error, Equatable, Sendable {
    case malformed(String)
    /// Directory or entry points outside the data block.
    case entryOutOfRange(id: UInt32)
}

/// One parsed table. Directory is decoded eagerly (small); string bytes are
/// located and decoded per lookup, so a table over a mapped file stays cheap.
nonisolated public struct StringTable: Sendable {
    /// Entry framing differs by file extension; the header is identical.
    nonisolated public enum Kind: Sendable {
        /// Bare zstring entries (most UI text).
        case strings
        /// uint32 byte length (terminator included) + zstring. Book text,
        /// descriptions (DL) and dialogue/info text (IL) use this framing.
        case dlstrings
        case ilstrings

        public init?(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "strings": self = .strings
            case "dlstrings": self = .dlstrings
            case "ilstrings": self = .ilstrings
            default: return nil
            }
        }

        public var isLengthPrefixed: Bool {
            self != .strings
        }
    }

    public let kind: Kind
    private let dataBlock: Data
    /// String ID -> byte offset into `dataBlock`. Duplicate IDs keep the
    /// first occurrence (mirrors first-wins lookup in xEdit).
    private let offsets: [UInt32: UInt32]

    public var count: Int {
        offsets.count
    }

    public var isEmpty: Bool {
        offsets.isEmpty
    }

    public init(data: Data, kind: Kind) throws {
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
            if offsets[id] == nil {
                offsets[id] = offset
            }
        }

        dataBlock = data.subdata(
            in: (data.startIndex + dataStart) ..< (data.startIndex + dataStart + dataSize)
        )
        self.offsets = offsets
    }

    /// Looks up one string by ID. Unknown ID -> nil; entry that cannot be
    /// framed -> throws. Decoding itself never fails (`GameText`).
    public func string(id: UInt32) throws -> String? {
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
            if framed.last == 0 {
                framed = framed.dropLast()
            }
            bytes = framed
        } else {
            guard let zstring = try? reader.readZStringData() else {
                throw StringTableError.entryOutOfRange(id: id)
            }
            bytes = zstring
        }
        return GameText.decode(bytes)
    }
}
