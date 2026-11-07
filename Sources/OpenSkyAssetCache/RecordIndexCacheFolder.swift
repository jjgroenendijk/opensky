// Saved FormID indexes beside the asset cache, one file per plugin state. A plugin
// that changes, such as a mod update, has another size or time, so it gets a new
// file, and the old one stays unused (docs/engine/asset-cache.md#saved-formid-indexes).

public import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated public struct RecordIndexCacheFolder: FormIDIndexStore {
    static let folderName = "records"
    public let folder: URL

    /// `cacheRoot` is the asset cache folder.
    public init(cacheRoot: URL) {
        folder = cacheRoot.appending(path: Self.folderName, directoryHint: .isDirectory)
    }

    public func savedIndex(for stamp: ESMFileStamp) -> Data? {
        attemptIfPresent { try Data(contentsOf: file(for: stamp)) }
    }

    /// A failed write only costs the next session a walk, so it is not reported.
    public func save(_ index: Data, for stamp: ESMFileStamp) {
        let target = file(for: stamp)
        let temporary = folder.appending(path: target.lastPathComponent + ".tmp")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try index.write(to: temporary)
            guard unsafe rename(temporary.path, target.path) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }

    func file(for stamp: ESMFileStamp) -> URL {
        let key = "\(stamp.name.lowercased())|\(stamp.size)|\(stamp.modified)"
        let hash = unsafe String(format: "%016llx", AssetContentHash.of(key))
        return folder.appending(path: "\(hash).osri")
    }
}
