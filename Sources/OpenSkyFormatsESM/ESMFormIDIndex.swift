// FormID -> record offset over one plugin, built by one walk of the record
// headers. A lookup then reparses one 24-byte header instead of walking the
// whole file. Layout: docs/formats/esm.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ESMFormIDIndex: Sendable {
    private struct Entry: Sendable {
        let formID: UInt32
        let offset: UInt32
        /// CELL whose persistent or temporary children hold the record; 0 when none.
        let cell: UInt32
    }

    private let data: Data
    /// Sorted by FormID; only the first record of a duplicated FormID is kept.
    private let entries: [Entry]

    public init(file: ESMFile) {
        data = file.data
        var found: [Entry] = []
        for group in file.topGroups {
            Self.collect(group: group, cell: 0, into: &found)
        }
        let sorted = found.enumerated().sorted { lhs, rhs in
            lhs.element.formID == rhs.element.formID
                ? lhs.offset < rhs.offset
                : lhs.element.formID < rhs.element.formID
        }
        var unique: [Entry] = []
        unique.reserveCapacity(sorted.count)
        for (_, entry) in sorted where entry.formID != unique.last?.formID {
            unique.append(entry)
        }
        entries = unique
    }

    public var count: Int {
        entries.count
    }

    /// First record with this FormID in file order (0 is the null sentinel -> nil).
    public func record(withFormID formID: UInt32) -> ESMRecord? {
        guard formID != 0, let entry = entry(for: formID) else { return nil }
        let offset = Int(entry.offset)
        var reader = BinaryReader(data, offset: offset)
        guard let header = try? ESMRecord.Header(reader: &reader) else { return nil }
        let dataStart = offset + ESMRecord.Header.size
        return ESMRecord(
            header: header,
            dataRange: dataStart ..< dataStart + Int(header.dataSize),
            file: data
        )
    }

    /// The CELL whose persistent or temporary children group holds the record.
    public func cellFormID(containing formID: UInt32) -> UInt32? {
        guard let cell = entry(for: formID)?.cell, cell != 0 else { return nil }
        return cell
    }

    private func entry(for formID: UInt32) -> Entry? {
        var low = 0
        var high = entries.count
        while low < high {
            let middle = (low + high) / 2
            if entries[middle].formID < formID {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < entries.count && entries[low].formID == formID ? entries[low] : nil
    }

    /// A malformed group is skipped, as in `ESMWalk`.
    private static func collect(group: ESMGroup, cell: UInt32, into found: inout [Entry]) {
        guard let children = try? group.children() else { return }
        let owner = switch group.kind {
        case .cellPersistentChildren, .cellTemporaryChildren: group.header.label
        default: cell
        }
        for child in children {
            switch child {
            case let .record(record):
                let offset = record.dataRange.lowerBound - ESMRecord.Header.size
                guard let stored = UInt32(exactly: offset) else { continue }
                found.append(Entry(formID: record.formID, offset: stored, cell: owner))
            case let .group(sub):
                collect(group: sub, cell: owner, into: &found)
            }
        }
    }
}
