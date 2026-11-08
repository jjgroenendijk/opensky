// Plugin container walk: one TES4 header record, then top-level GRUPs. The
// file is memory-mapped and only group extents are indexed, because
// Skyrim.esm is about 250 MB. Layout: docs/formats/esm.md.

public import Foundation
public import OpenSkyFormatsCore

/// The plugin file a load read: a saved index stays valid while all three match.
nonisolated public struct ESMFileStamp: Hashable, Sendable {
    public let name: String
    public let size: UInt64
    /// Seconds since 1970.
    public let modified: Int64

    public init(name: String, size: UInt64, modified: Int64) {
        self.name = name
        self.size = size
        self.modified = modified
    }

    init?(url: URL) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard
            let values = attemptIfPresent({ try url.resourceValues(forKeys: keys) }),
            let size = values.fileSize, let modified = values.contentModificationDate
        else { return nil }
        self.init(
            name: url.lastPathComponent, size: UInt64(size),
            modified: Int64(modified.timeIntervalSince1970.rounded(.down))
        )
    }
}

nonisolated public struct ESMFile: Sendable {
    /// TES4 plugin-info record (HEDR, masters, description).
    public let tes4: ESMRecord
    /// Top-level groups in file order (~118 in Skyrim.esm).
    public let topGroups: [ESMGroup]
    /// The whole plugin, so an index can reparse a record at a stored offset.
    public let data: Data
    /// Nil for a plugin built in memory, such as a test fixture.
    public private(set) var stamp: ESMFileStamp?

    /// Memory-maps the plugin and starts reading it ahead, because the record
    /// indexes walk all of it; nothing beyond top-level headers is parsed here.
    public init(url: URL) throws {
        // `mappedIfSafe` may copy external-volume files into anonymous RAM.
        // Game installs are commonly on USB volumes, so mapping is mandatory.
        FileReadAhead.start(url)
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
        stamp = ESMFileStamp(url: url)
    }

    public init(data: Data) throws {
        self.data = data
        let children = try ESMGroup.parseChildren(in: data, range: 0 ..< data.count)
        guard case let .record(first)? = children.first, first.type == "TES4" else {
            throw ESMError.missingTES4
        }
        tes4 = first
        topGroups = try children.dropFirst().map { child in
            guard case let .group(group) = child else {
                throw ESMError.malformed("record outside any group at top level")
            }
            return group
        }
    }

    /// First top group holding `recordType` records (e.g. "WRLD").
    public func topGroup(of recordType: FourCC) -> ESMGroup? {
        topGroups.first { $0.recordType == recordType }
    }
}
