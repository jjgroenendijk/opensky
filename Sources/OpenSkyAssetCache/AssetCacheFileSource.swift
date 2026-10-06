// A file source that answers animation reads from the cache's loose copies, so
// the behavior and clip loaders need no change. Every other read goes to `base`.

import Foundation
import OpenSkyGameData

nonisolated public struct AssetCacheFileSource: GameFileSource {
    public let base: any GameFileSource
    public let reader: AssetCacheReader

    public init(base: any GameFileSource, reader: AssetCacheReader) {
        self.base = base
        self.reader = reader
    }

    public func exists(_ path: String) -> Bool {
        base.exists(path)
    }

    public func contents(forPath path: String) throws -> Data {
        if
            path.lowercased().hasSuffix(".hkx"),
            let loose = reader.value(forPath: path, decoder: .looseAnimation)
        {
            return loose
        }
        return try base.contents(forPath: path)
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
