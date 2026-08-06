// Plugin GRUP container: 24-byte header whose stored size INCLUDES the header
// itself (unlike records/fields). The 4-byte label's meaning depends on the
// group type: record type for top groups, parent FormID for children groups,
// grid coordinates for exterior blocks, block number for interior blocks.
// Labels are unreliable in CK-ignored groups (UESP note) — traversal never
// depends on them, only on sizes.
//
// Reference: UESP "Skyrim Mod:Mod File Format" — Groups.

import Foundation

nonisolated struct ESMGroup {
    /// Group types 0-9 (SSE). Raw value = on-disk int32.
    enum Kind: Int32 {
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

    struct Header {
        static let size = 24

        /// Raw label bytes; interpret via the typed accessors on ESMGroup.
        let label: UInt32
        let groupType: Int32
        let timestamp: UInt16
        let versionControl: UInt16

        /// Reads label onward — caller has consumed the GRUP tag + groupSize.
        init(reader: inout BinaryReader) throws {
            label = try reader.readUInt32()
            groupType = try Int32(bitPattern: reader.readUInt32())
            timestamp = try reader.readUInt16()
            versionControl = try reader.readUInt16()
            _ = try reader.readUInt32() // unknown, varies by group type
        }
    }

    enum Child {
        case record(ESMRecord)
        case group(ESMGroup)
    }

    let header: Header
    /// Absolute range of the group's contents (children) in `file`.
    let contentRange: Range<Int>
    private let file: Data

    init(header: Header, contentRange: Range<Int>, file: Data) {
        self.header = header
        self.contentRange = contentRange
        self.file = file
    }

    /// Nil for group types this engine does not know (future/modded).
    var kind: Kind? {
        Kind(rawValue: header.groupType)
    }

    /// Top group: the record type it holds.
    var recordType: FourCC? {
        kind == .top ? FourCC(rawValue: header.label) : nil
    }

    /// Children groups: FormID of the parent WRLD/CELL/DIAL record.
    var parentFormID: UInt32? {
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
    var grid: (x: Int16, y: Int16)? {
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
    var blockNumber: Int32? {
        switch kind {
        case .interiorCellBlock, .interiorCellSubBlock:
            Int32(bitPattern: header.label)
        default:
            nil
        }
    }

    /// Parses direct children (headers only; payloads stay lazy).
    func children() throws -> [Child] {
        try Self.parseChildren(in: file, range: contentRange)
    }

    /// Walks a sibling sequence of records and groups filling `range`.
    /// Every child must lie fully inside the range; both header kinds are 24
    /// bytes, and each child advances the cursor by at least that much, so the
    /// walk always terminates.
    static func parseChildren(in file: Data, range: Range<Int>) throws -> [Child] {
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
