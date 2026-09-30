// A `GameFileSource` over bytes held in memory. Tests fill it with synthetic
// data built in code, never with extracted game files.

import Foundation
import OpenSkyGameData

nonisolated public struct InMemoryFileSource: GameFileSource {
    /// Canonical key to bytes. Every file counts as one archive entry.
    public private(set) var files: [String: Data] = [:]
    public static let archiveName = "memory"

    public init(files: [String: Data] = [:]) {
        for (path, data) in files {
            self[path] = data
        }
    }

    /// Reads or writes a file by any spelling of its path. An invalid path is ignored.
    public subscript(path: String) -> Data? {
        get { (try? VirtualFileSystem.normalize(path)).flatMap { files[$0] } }
        set {
            guard let key = try? VirtualFileSystem.normalize(path) else { return }
            files[key] = newValue
        }
    }

    public func exists(_ path: String) -> Bool {
        self[path] != nil
    }

    public func contents(forPath path: String) throws -> Data {
        let key = try VirtualFileSystem.normalize(path)
        guard let data = files[key] else { throw VFSError.fileNotFound(path: key) }
        return data
    }

    public func archiveEntries() -> [VFSEntry] {
        files.keys.sorted().map { VFSEntry(path: $0, archive: Self.archiveName) }
    }

    public func fileNames(inDirectory directory: String) -> [String] {
        guard let key = try? VirtualFileSystem.normalize(directory) else { return [] }
        let prefix = key + "\\"
        return files.keys.filter {
            $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("\\")
        }.sorted()
    }
}
