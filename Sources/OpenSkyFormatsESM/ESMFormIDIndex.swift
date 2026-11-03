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
        /// WRLD whose world children group holds the record; 0 when none.
        let world: UInt32
    }

    /// The groups a walk is inside.
    private struct Owners: Sendable {
        var cell: UInt32 = 0
        var world: UInt32 = 0

        func entering(_ group: ESMGroup) -> Self {
            var owners = self
            switch group.kind {
            case .cellPersistentChildren, .cellTemporaryChildren: owners.cell = group.header.label
            case .worldChildren: owners.world = group.header.label
            default: break
            }
            return owners
        }
    }

    private let data: Data
    /// Sorted by FormID; only the first record of a duplicated FormID is kept.
    private let entries: [Entry]

    /// A group to walk on one core, with the groups around it.
    private struct Unit: Sendable {
        let group: ESMGroup
        let owners: Owners
    }

    /// A group larger than this splits into its subgroups, so the world and cell
    /// groups of a master spread over the cores.
    private static let splitBytes = 4 << 20

    public init(file: ESMFile) {
        self.init(file: file, splitBytes: Self.splitBytes)
    }

    /// `splitBytes` is a parameter so a test can split a small plugin.
    init(file: ESMFile, splitBytes: Int) {
        data = file.data
        var units: [Unit] = []
        var found: [Entry] = []
        for group in file.topGroups {
            Self.split(
                group: group, owners: Owners(), limit: splitBytes, units: &units, into: &found
            )
        }
        let inParallel = LoadOptimisations.isOn(.parallelFormIDIndex)
        found += ParallelDecode.mapInOrder(units, chunkSize: 1, inParallel: inParallel) { unit in
            var entries: [Entry] = []
            Self.collect(group: unit.group, owners: unit.owners, into: &entries)
            return entries
        }.flatMap(\.self)
        // A record's offset grows with its place in the file, so it orders duplicates.
        let sorted = found.sorted { lhs, rhs in
            lhs.formID == rhs.formID ? lhs.offset < rhs.offset : lhs.formID < rhs.formID
        }
        var unique: [Entry] = []
        unique.reserveCapacity(sorted.count)
        for entry in sorted where entry.formID != unique.last?.formID {
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

    /// The WRLD whose world children group holds the record: an exterior CELL, or a
    /// reference placed in one.
    public func worldFormID(containing formID: UInt32) -> UInt32? {
        guard let world = entry(for: formID)?.world, world != 0 else { return nil }
        return world
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

    /// Keeps a small group whole as one unit; a large one gives its own records
    /// to `found` and splits its subgroups further.
    private static func split(
        group: ESMGroup, owners: Owners, limit: Int, units: inout [Unit], into found: inout [Entry]
    ) {
        guard group.contentRange.count > limit else {
            units.append(Unit(group: group, owners: owners))
            return
        }
        guard let children = try? group.children() else { return }
        let owners = owners.entering(group)
        for child in children {
            switch child {
            case let .record(record): append(record, owners: owners, to: &found)
            case let .group(sub):
                split(group: sub, owners: owners, limit: limit, units: &units, into: &found)
            }
        }
    }

    /// A malformed group is skipped, as in `ESMWalk`.
    private static func collect(group: ESMGroup, owners: Owners, into found: inout [Entry]) {
        guard let children = try? group.children() else { return }
        let owners = owners.entering(group)
        for child in children {
            switch child {
            case let .record(record): append(record, owners: owners, to: &found)
            case let .group(sub): collect(group: sub, owners: owners, into: &found)
            }
        }
    }

    private static func append(_ record: ESMRecord, owners: Owners, to found: inout [Entry]) {
        let offset = record.dataRange.lowerBound - ESMRecord.Header.size
        guard let stored = UInt32(exactly: offset) else { return }
        found.append(Entry(
            formID: record.formID, offset: stored, cell: owners.cell, world: owners.world
        ))
    }
}
