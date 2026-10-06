// Serves files from a folder of loose copies first and from `base` otherwise,
// the way loose files under `Data/` win over the archives. A benchmark uses it
// to time loose files apart from archive reads without writing to the install.

import Foundation

nonisolated public struct FolderOverlayFileSource: GameFileSource {
    public let base: any GameFileSource
    public let folder: URL

    public init(base: any GameFileSource, folder: URL) {
        self.base = base
        self.folder = folder
    }

    /// `textures\a.dds` -> `<folder>/textures/a.dds`.
    public func looseURL(forPath path: String) throws -> URL {
        let key = try VirtualFileSystem.normalize(path)
        return folder.appending(path: key.replacingOccurrences(of: "\\", with: "/"))
    }

    public func exists(_ path: String) -> Bool {
        base.exists(path)
    }

    public func contents(forPath path: String) throws -> Data {
        let url = try looseURL(forPath: path)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return try base.contents(forPath: path)
        }
        return try Data(contentsOf: url)
    }

    public func archiveEntries() -> [VFSEntry] {
        base.archiveEntries()
    }

    public func fileNames(inDirectory directory: String) -> [String] {
        base.fileNames(inDirectory: directory)
    }

    public func provenance(forPath path: String) -> GameFileProvenance? {
        base.provenance(forPath: path)
    }
}
