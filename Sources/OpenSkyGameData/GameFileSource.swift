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
}
