// Build-queue-confined decoded collision cache. Keys match MeshLibrary's
// canonical mesh keys, so one streaming eviction drop-set releases render +
// collision caches without a second residency graph.

import Foundation

nonisolated enum NIFCollisionLibraryError: Error, Equatable {
    case fileNotFound(path: String)
    case parseFailed(path: String, reason: String)
}

nonisolated final class NIFCollisionLibrary {
    private let fileSystem: VirtualFileSystem
    private var cache: [String: NIFCollisionModel] = [:]
    private var touchedKeys: Set<String> = []

    init(fileSystem: VirtualFileSystem) {
        self.fileSystem = fileSystem
    }

    func model(path: String) throws -> NIFCollisionModel {
        let key = try meshKey(for: path)
        touchedKeys.insert(key)
        if let cached = cache[key] {
            return cached
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

    func drainTouchedKeys() -> Set<String> {
        let result = touchedKeys
        touchedKeys.removeAll(keepingCapacity: true)
        return result
    }

    @discardableResult
    func evict(dropping keys: Set<String>) -> Int {
        keys.reduce(into: 0) { count, key in
            if cache.removeValue(forKey: key) != nil {
                count += 1
            }
        }
    }

    var loadedCount: Int {
        cache.count
    }

    private func meshKey(for path: String) throws -> String {
        guard let normalized = try? VirtualFileSystem.normalize(path) else {
            throw NIFCollisionLibraryError.fileNotFound(path: path)
        }
        return normalized.hasPrefix("meshes\\") ? normalized : "meshes\\" + normalized
    }
}
