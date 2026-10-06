// The read side of the game data root. `VirtualFileSystem` is the real source;
// a test passes an in-memory one instead of writing files to disk.

import Foundation

/// Resolves resource paths to bytes. Paths are case- and separator-insensitive,
/// as in `VirtualFileSystem.normalize(_:)` (docs/formats/vfs.md).
nonisolated public protocol GameFileSource: Sendable {
    func exists(_ path: String) -> Bool
    func contents(forPath path: String) throws -> Data
    /// Every archive-provided path, sorted by path.
    func archiveEntries() -> [VFSEntry]
    /// Canonical keys of files directly inside `directory`, sorted.
    func fileNames(inDirectory directory: String) -> [String]
    /// Which file provides `path` and its state, so a cache can tell when it changed.
    func provenance(forPath path: String) -> GameFileProvenance?
}

/// The file that provides one resource: an archive, or `loose` for a file under `Data/`.
nonisolated public struct GameFileProvenance: Equatable, Sendable {
    public static let looseOrigin = "loose"

    public let origin: String
    /// The resource's own size in bytes, as stored.
    public let size: UInt64
    /// Modification time of the providing file, in whole seconds since 1970.
    public let modified: Int64

    public init(origin: String, size: UInt64, modified: Int64) {
        self.origin = origin
        self.size = size
        self.modified = modified
    }
}

nonisolated extension GameFileSource {
    public func provenance(forPath _: String) -> GameFileProvenance? {
        nil
    }
}
