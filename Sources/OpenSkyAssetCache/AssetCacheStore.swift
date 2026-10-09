// The cache folder on disk. Each entry is one file named by its kind and source,
// written atomically through a temporary file and a rename, so a crash leaves
// either the old entry or the new one, never half of one. A hit refreshes the
// file's modification date when it is over an hour old; that date orders the
// least-recently-used removal.

import Foundation
import Synchronization

/// What one lookup asks for: a kind of asset from one source, built by one
/// converter version for one texture output.
nonisolated public struct AssetCacheRequest: Hashable, Sendable {
    public let kind: AssetCacheKind
    public let source: AssetSourceStamp
    public let converterVersion: UInt32
    public let output: UInt8

    public init(
        kind: AssetCacheKind, source: AssetSourceStamp, converterVersion: UInt32,
        output: UInt8 = 0
    ) {
        self.kind = kind
        self.source = source
        self.converterVersion = converterVersion
        self.output = output
    }

    var header: AssetCacheEntryHeader {
        AssetCacheEntryHeader(
            kind: kind, source: source, converterVersion: converterVersion, output: output
        )
    }
}

/// Why an entry exists but must not be used.
nonisolated public enum AssetCacheStaleness: Equatable, Sendable {
    case sourceChanged
    case converterChanged(built: UInt32)
    /// Only textures have outputs, so meshes and collision never read as this.
    case outputChanged(built: UInt8)
}

nonisolated public struct AssetCacheHit: Sendable {
    /// The whole entry file. `payload` is a slice of it.
    public let file: Data
    public let payloadRange: Range<Int>
    public let url: URL

    /// A slice: its indices start at `payloadRange.lowerBound`, not at zero.
    public var payload: Data {
        file[payloadRange]
    }
}

nonisolated public enum AssetCacheLookup: Sendable {
    case hit(AssetCacheHit)
    case miss
    case stale(AssetCacheStaleness)
    /// The file exists but is not a whole entry, or cannot be read.
    case unreadable(reason: String)
}

nonisolated public enum AssetCacheEntryState: Equatable, Sendable {
    case current
    /// Built from another source, converter, or texture output, or broken.
    case stale
    case missing
}

nonisolated public struct AssetCacheKindUsage: Equatable, Sendable {
    public var entryCount = 0
    public var bytes: UInt64 = 0

    public init(entryCount: Int = 0, bytes: UInt64 = 0) {
        self.entryCount = entryCount
        self.bytes = bytes
    }
}

nonisolated public struct AssetCacheUsage: Equatable, Sendable {
    public let entryCount: Int
    public let bytes: UInt64
    public let kinds: [AssetCacheKind: AssetCacheKindUsage]

    public init(
        entryCount: Int,
        bytes: UInt64,
        kinds: [AssetCacheKind: AssetCacheKindUsage] = [:]
    ) {
        self.entryCount = entryCount
        self.bytes = bytes
        self.kinds = kinds
    }
}

nonisolated public final class AssetCacheStore: Sendable {
    static let entryExtension = "osac"
    static let temporaryFolder = "tmp"

    public let root: URL
    private let limit: Mutex<UInt64>

    /// Creates the folder when needed and removes leftovers of interrupted writes.
    /// The player sets no limit; the space check before a conversion guards the disk.
    public static let noLimit = UInt64.max

    public init(root: URL, limitBytes: UInt64) throws {
        self.root = root
        limit = Mutex(limitBytes)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let temporary = root.appending(path: Self.temporaryFolder, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: temporary)
        for kind in AssetCacheKind.retired {
            try? FileManager.default.removeItem(
                at: root.appending(path: kind.folderName, directoryHint: .isDirectory)
            )
        }
    }

    public var limitBytes: UInt64 {
        get { limit.withLock { $0 } }
        set { limit.withLock { $0 = newValue } }
    }

    public func entryURL(kind: AssetCacheKind, source: AssetSourceStamp) -> URL {
        let name = String(
            format: "%016llx",
            AssetContentHash.of(source.origin + "\u{0}" + source.path)
        )
        return root.appending(path: kind.folderName, directoryHint: .isDirectory)
            .appending(path: String(name.prefix(2)), directoryHint: .isDirectory)
            .appending(path: "\(name).\(Self.entryExtension)")
    }

    /// A hit refreshes an old use date unless `touching` is false.
    public func lookup(_ request: AssetCacheRequest, touching: Bool = true) -> AssetCacheLookup {
        let url = entryURL(kind: request.kind, source: request.source)
        let file: Data
        switch AssetCacheFileRead.read(url, touching: touching) {
        case let .success(bytes):
            file = bytes
        case let .failure(error) where error.code == .ENOENT:
            return .miss
        case let .failure(error):
            return .unreadable(reason: String(describing: error))
        }
        let header: AssetCacheEntryHeader
        let range: Range<Int>
        do {
            (header, range) = try AssetCacheEntryCodec.decode(file)
        } catch {
            return .unreadable(reason: String(describing: error))
        }
        if let staleness = Self.staleness(of: header, for: request) {
            return .stale(staleness)
        }
        return .hit(AssetCacheHit(file: file, payloadRange: range, url: url))
    }

    /// Like `lookup`, but reads only the header and the payload's first bytes, as many as
    /// `payloadHead` asks for after seeing them. The hit's file holds just those bytes.
    public func lookupHead(
        _ request: AssetCacheRequest, payloadHead: (Data) -> Int?
    ) -> AssetCacheLookup {
        let url = entryURL(kind: request.kind, source: request.source)
        var wanted = Self.headReadSize
        while true {
            let read: (bytes: Data, size: Int)
            switch AssetCacheFileRead.readHead(url, count: wanted, touching: true) {
            case let .success(head):
                read = head
            case let .failure(error) where error.code == .ENOENT:
                return .miss
            case let .failure(error):
                return .unreadable(reason: String(describing: error))
            }
            let header: AssetCacheEntryHeader
            let range: Range<Int>
            do {
                (header, range) = try AssetCacheEntryCodec.decodeHead(read.bytes)
            } catch {
                return .unreadable(reason: String(describing: error))
            }
            guard range.upperBound == read.size else {
                return .unreadable(reason: String(describing: AssetCacheEntryError.truncated))
            }
            if let staleness = Self.staleness(of: header, for: request) {
                return .stale(staleness)
            }
            let available = read.bytes[range.lowerBound ..< min(range.upperBound, read.bytes.count)]
            let needed = range.lowerBound + (payloadHead(available) ?? range.count)
            guard needed > read.bytes.count, wanted < read.size else {
                return .hit(AssetCacheHit(
                    file: read.bytes,
                    payloadRange: range.lowerBound ..< min(range.upperBound, read.bytes.count),
                    url: url
                ))
            }
            wanted = min(needed, read.size)
        }
    }

    /// One read holds the header and a model's layout block for almost every entry.
    static let headReadSize = 64 * 1024

    /// Writes the entry atomically, then removes the oldest entries over the limit.
    /// A bulk build passes `enforcingLimit: false` and enforces it once at the end.
    public func store(
        _ payload: Data,
        for request: AssetCacheRequest,
        enforcingLimit: Bool = true
    ) throws {
        let url = entryURL(kind: request.kind, source: request.source)
        try writeAtomically(
            AssetCacheEntryCodec.encode(header: request.header, payload: payload),
            to: url
        )
        if enforcingLimit {
            enforceLimit()
        }
    }

    /// True when a whole, current entry exists. Reads only the header.
    public func isCurrent(_ request: AssetCacheRequest) -> Bool {
        entryState(request) == .current
    }

    /// Whether the entry for `request` is current, stale or broken, or missing. Reads only the
    /// header.
    public func entryState(_ request: AssetCacheRequest) -> AssetCacheEntryState {
        let url = entryURL(kind: request.kind, source: request.source)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .missing }
        defer { try? handle.close() }
        guard
            let prefix = try? handle.read(upToCount: AssetCacheEntryCodec.maximumHeaderSize),
            let size = try? handle.seekToEnd(),
            let (header, payloadEnd) = try? AssetCacheEntryCodec.decodeHeader(prefix),
            payloadEnd == Int(size), Self.staleness(of: header, for: request) == nil
        else { return .stale }
        return .current
    }

    /// Deletes one entry, so the next build makes it again.
    public func remove(kind: AssetCacheKind, source: AssetSourceStamp) {
        try? FileManager.default.removeItem(at: entryURL(kind: kind, source: source))
    }

    public func clear() throws {
        for kind in AssetCacheKind.allCases {
            let folder = root.appending(path: kind.folderName, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: folder)
            }
        }
    }

    public func usage() -> AssetCacheUsage {
        let entries = entryFiles()
        var kinds: [AssetCacheKind: AssetCacheKindUsage] = [:]
        for entry in entries {
            kinds[entry.kind, default: AssetCacheKindUsage()].entryCount += 1
            kinds[entry.kind, default: AssetCacheKindUsage()].bytes += entry.bytes
        }
        return AssetCacheUsage(
            entryCount: entries.count,
            bytes: entries.reduce(0) { $0 + $1.bytes },
            kinds: kinds
        )
    }

    /// Removes least-recently-used entries until the cache fits its limit.
    /// Returns how many entries it removed.
    @discardableResult
    public func enforceLimit() -> Int {
        let entries = entryFiles()
        var total = entries.reduce(0) { $0 + $1.bytes }
        let limit = limitBytes
        guard total > limit else { return 0 }
        var removed = 0
        for entry in entries.sorted(by: { $0.lastUse < $1.lastUse }) where total > limit {
            guard (try? FileManager.default.removeItem(at: entry.url)) != nil else { continue }
            total -= min(total, entry.bytes)
            removed += 1
        }
        return removed
    }

    static func staleness(
        of header: AssetCacheEntryHeader, for request: AssetCacheRequest
    ) -> AssetCacheStaleness? {
        if header.kind != request.kind || !header.source.matches(request.source) {
            return .sourceChanged
        }
        if header.converterVersion != request.converterVersion {
            return .converterChanged(built: header.converterVersion)
        }
        if request.kind == .texture, header.output != request.output {
            return .outputChanged(built: header.output)
        }
        return nil
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        let temporaryFolder = root.appending(
            path: Self.temporaryFolder,
            directoryHint: .isDirectory
        )
        try manager.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        try manager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = temporaryFolder.appending(path: UUID().uuidString)
        try data.write(to: temporary)
        guard rename(temporary.path(percentEncoded: false), url.path(percentEncoded: false)) == 0
        else {
            let code = errno
            try? manager.removeItem(at: temporary)
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)]
            )
        }
    }

    private struct EntryFile {
        let kind: AssetCacheKind
        let url: URL
        let bytes: UInt64
        let lastUse: Date
    }

    private func entryFiles() -> [EntryFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        var result: [EntryFile] = []
        for kind in AssetCacheKind.allCases {
            let folder = root.appending(path: kind.folderName, directoryHint: .isDirectory)
            guard
                let walker = FileManager.default.enumerator(
                    at: folder,
                    includingPropertiesForKeys: keys
                )
            else {
                continue
            }
            for case let url as URL in walker where url.pathExtension == Self.entryExtension {
                guard
                    let values = try? url.resourceValues(forKeys: Set(keys)),
                    values.isRegularFile == true
                else {
                    continue
                }
                result.append(EntryFile(
                    kind: kind, url: url, bytes: UInt64(values.fileSize ?? 0),
                    lastUse: values.contentModificationDate ?? .distantPast
                ))
            }
        }
        return result
    }
}
