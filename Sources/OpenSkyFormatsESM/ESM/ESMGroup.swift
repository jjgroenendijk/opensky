// Plugin GRUP container: 24-byte header whose stored size INCLUDES the header
// itself (unlike records/fields). The 4-byte label's meaning depends on the
// group type: record type for top groups, parent FormID for children groups,
// grid coordinates for exterior blocks, block number for interior blocks.
// Labels are unreliable in CK-ignored groups (UESP note) — traversal never
// depends on them, only on sizes.
//
// Reference: UESP "Skyrim Mod:Mod File Format" — Groups.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ESMGroup: Sendable {
    /// Group types 0-9 (SSE). Raw value = on-disk int32.
    public enum Kind: Int32, Sendable {
        case top = 0
        case worldChildren
        case interiorCellBlock
        case interiorCellSubBlock
        case exteriorCellBlock
        case exteriorCellSubBlock
        case cellChildren
        case topicChildren
        case cellPersistentChildren
        case cellTemporaryChildren
    }

    public struct Header: Sendable {
        public static let size = 24

        /// Raw label bytes; interpret via the typed accessors on ESMGroup.
        public let label: UInt32
        public let groupType: Int32
        public let timestamp: UInt16
        public let versionControl: UInt16

        /// Reads label onward — caller has consumed the GRUP tag + groupSize.
        public init(reader: inout BinaryReader) throws {
            label = try reader.readUInt32()
            groupType = try Int32(bitPattern: reader.readUInt32())
            timestamp = try reader.readUInt16()
            versionControl = try reader.readUInt16()
            _ = try reader.readUInt32() // unknown, varies by group type
        }
    }

    public enum Child: Sendable {
        case record(ESMRecord)
        case group(ESMGroup)
    }

    public let header: Header
    /// Absolute range of the group's contents (children) in `file`.
    public let contentRange: Range<Int>
    private let file: Data

    public init(header: Header, contentRange: Range<Int>, file: Data) {
        self.header = header
        self.contentRange = contentRange
        self.file = file
    }

    /// Nil for group types this engine does not know (future/modded).
    public var kind: Kind? {
        Kind(rawValue: header.groupType)
    }

    /// Top group: the record type it holds.
    public var recordType: FourCC? {
        kind == .top ? FourCC(rawValue: header.label) : nil
    }

    /// Children groups: FormID of the parent WRLD/CELL/DIAL record.
    public var parentFormID: UInt32? {
        switch kind {
        case .worldChildren, .cellChildren, .topicChildren,
             .cellPersistentChildren, .cellTemporaryChildren:
            header.label
        default:
            nil
        }
    }

    /// Exterior cell (sub-)block: grid coordinates. The label stores Y in the
    /// low int16 and X in the high int16 (reversed, per spec).
    public var grid: (x: Int16, y: Int16)? {
        switch kind {
        case .exteriorCellBlock, .exteriorCellSubBlock:
            (
                x: Int16(truncatingIfNeeded: header.label >> 16),
                y: Int16(truncatingIfNeeded: header.label)
            )
        default:
            nil
        }
    }

    /// Interior cell (sub-)block: block number.
    public var blockNumber: Int32? {
        switch kind {
        case .interiorCellBlock, .interiorCellSubBlock:
            Int32(bitPattern: header.label)
        default:
            nil
        }
    }

    /// Parses direct children (headers only; payloads stay lazy).
    public func children() throws -> [Child] {
        try Self.parseChildren(in: file, range: contentRange)
    }

    /// Walks a sibling sequence of records and groups filling `range`.
    /// Every child must lie fully inside the range; both header kinds are 24
    /// bytes, and each child advances the cursor by at least that much, so the
    /// walk always terminates.
    public static func parseChildren(in file: Data, range: Range<Int>) throws -> [Child] {
        var children: [Child] = []
        var offset = range.lowerBound
        while offset < range.upperBound {
            guard range.upperBound - offset >= Header.size else {
                throw ESMError.malformed("truncated child header at offset \(offset)")
            }
            var reader = BinaryReader(file, offset: offset)
            let tag = try reader.readFourCC()
            if tag == "GRUP" {
                let groupSize = try Int(reader.readUInt32())
                let header = try Header(reader: &reader)
                guard groupSize >= Header.size, offset + groupSize <= range.upperBound else {
                    throw ESMError.malformed("group size out of bounds at offset \(offset)")
                }
                let content = (offset + Header.size) ..< (offset + groupSize)
                children.append(.group(ESMGroup(header: header, contentRange: content, file: file)))
                offset += groupSize
            } else {
                reader.seek(to: offset)
                let header = try ESMRecord.Header(reader: &reader)
                let dataStart = offset + ESMRecord.Header.size
                let dataEnd = dataStart + Int(header.dataSize)
                guard dataEnd <= range.upperBound else {
                    throw ESMError.malformed("record data out of bounds at offset \(offset)")
                }
                children.append(.record(ESMRecord(
                    header: header,
                    dataRange: dataStart ..< dataEnd,
                    file: file
                )))
                offset = dataEnd
            }
        }
        return children
    }
}
