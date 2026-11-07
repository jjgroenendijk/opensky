// Build-queue-confined decoded collision cache. Keys match MeshLibrary's
// canonical mesh keys, so one streaming eviction drop-set releases render +
// collision caches without a second residency graph.

import Foundation
public import OpenSkyAssetCache
import OpenSkyFormatsCore
public import OpenSkyFormatsMesh
public import OpenSkyGameData

nonisolated public enum NIFCollisionLibraryError: Error, Equatable {
    case fileNotFound(path: String)
    case parseFailed(path: String, reason: String)
}

nonisolated public final class NIFCollisionLibrary {
    private let fileSystem: any GameFileSource
    private var cache: [String: NIFCollisionModel] = [:]
    private var touchedKeys: Set<String> = []
    /// Converted collision models, read before the NIF when current.
    public var assetCache: AssetCacheReader?
    /// Off reads and parses every model serially on the build thread.
    public var decodesInParallel = true
    /// Models `predecode(paths:)` made for the current build; a load takes its entry.
    private var predecoded: [String: NIFCollisionModel] = [:]

    public init(fileSystem: any GameFileSource) {
        self.fileSystem = fileSystem
    }

    public func model(path: String) throws -> NIFCollisionModel {
        let key = try meshKey(for: path)
        touchedKeys.insert(key)
        if let cached = cache[key] {
            return cached
        }
        if let ready = predecoded.removeValue(forKey: key) {
            cache[key] = ready
            return ready
        }
        if let converted = assetCache?.value(forPath: key, decoder: .collision) {
            cache[key] = converted
            return converted
        }
        let data: Data
        do {
            data = try fileSystem.contents(forPath: key)
        } catch {
            throw NIFCollisionLibraryError.fileNotFound(path: key)
        }
        do {
            let model = try NIFFile(data: data).collisionModel()
            cache[key] = model
            return model
        } catch {
            throw NIFCollisionLibraryError.parseFailed(
                path: key,
                reason: String(describing: error)
            )
        }
    }

    /// Reads and parses the models of `paths` that are not loaded yet on every core
    /// (docs/decisions/concurrency.md). A failure is left to the serial load, which throws it.
    public func predecode(paths: some Sequence<String>) {
        guard decodesInParallel else { return }
        let keys = Set(paths.compactMap { try? meshKey(for: $0) })
            .filter { cache[$0] == nil && predecoded[$0] == nil }
        guard keys.count >= ParallelDecode.minimumParallelItems else { return }
        let (cacheReader, files) = (assetCache, fileSystem.untimed)
        predecoded = ParallelDecode.map(keys) { key -> NIFCollisionModel? in
            if let converted = cacheReader?.value(forPath: key, decoder: .collision) {
                return converted
            }
            return (try? files.contents(forPath: key))
                .flatMap { try? NIFFile(data: $0).collisionModel() }
        }
    }

    /// Frees decodes no load asked for.
    public func dropPredecoded() {
        predecoded.removeAll()
    }

    public func drainTouchedKeys() -> Set<String> {
        let result = touchedKeys
        touchedKeys.removeAll(keepingCapacity: true)
        return result
    }

    @discardableResult
    public func evict(dropping keys: Set<String>) -> Int {
        keys.reduce(into: 0) { count, key in
            if cache.removeValue(forKey: key) != nil {
                count += 1
            }
        }
    }

    public var loadedCount: Int {
        cache.count
    }

    public func canonicalKey(for path: String) -> String {
        (try? meshKey(for: path)) ?? path
    }

    private func meshKey(for path: String) throws -> String {
        guard let normalized = try? VirtualFileSystem.normalize(path) else {
            throw NIFCollisionLibraryError.fileNotFound(path: path)
        }
        return normalized.hasPrefix("meshes\\") ? normalized : "meshes\\" + normalized
    }
}
