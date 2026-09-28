// Shared texture cache keyed by normalized VFS path + usage: load a DDS once,
// hand the same MTLTexture to every material that references it (todo 2.7
// asset caches). Bridges the VFS (bytes) and TextureLoader (upload) so scene
// build stays ignorant of both. Never throws — a nil key, a missing file, or
// a bad DDS all resolve to the loader's shared placeholder, cached so each
// distinct path logs at most once.
//
// Single-threaded by confinement, not locking: every touch (scene build) runs
// on the streamer's ONE serial build queue (SerialCellBuildRunner), never the
// main thread, so the dictionary needs no lock. Sibling MeshLibrary follows the
// same confinement rule; VFS itself is mutex-guarded. Decision:
// docs/engine/cell-streaming.md.

import Foundation
import Metal

nonisolated final class TextureLibrary {
    /// Cache identity: same path + usage -> same MTLTexture. A path may be
    /// sampled sRGB (color) and linear (data) by different materials, so
    /// usage is part of the key — two distinct GPU textures, one file.
    private struct CacheKey: Hashable {
        let path: String
        let usage: TextureUsage
    }

    /// Sentinel for the nil-key (untextured material) placeholder so it is
    /// created and logged once. Never collides: normalize rejects empty paths.
    private static let untexturedPath = ""

    /// Stable string form of a cache key, for the touched/keep sets that drive
    /// eviction (the private CacheKey type does not cross the module).
    private static func keyString(path: String, usage: TextureUsage) -> String {
        "\(usage)|\(path)"
    }

    private static func keyString(_ key: CacheKey) -> String {
        keyString(path: key.path, usage: key.usage)
    }

    private let fileSystem: VirtualFileSystem
    private let loader: TextureLoader
    private var cache: [CacheKey: MTLTexture] = [:]

    /// Keys resolved since the last drain, so a cell build can record exactly
    /// which textures it uses (for eviction keep-sets). Confined to the build
    /// queue like the cache; drained per build by CellSceneBuilder.
    private var touchedKeys: Set<String> = []
    /// Per-model capture active only during one RenderModel construction.
    private var capturedKeys: Set<String>?

    /// Distinct paths whose bytes were found and handed to the loader.
    private(set) var loadedCount = 0
    /// Distinct paths the VFS could not resolve (each fell back to placeholder).
    private(set) var missingCount = 0

    init(fileSystem: VirtualFileSystem, loader: TextureLoader) {
        self.fileSystem = fileSystem
        self.loader = loader
    }

    convenience init(fileSystem: VirtualFileSystem, device: MTLDevice) {
        self.init(fileSystem: fileSystem, loader: TextureLoader(device: device))
    }

    /// Resolves a material's texture key to a ready MTLTexture. nil key ->
    /// shared untextured placeholder (expected, not counted). Otherwise a
    /// cache hit returns the shared texture; a miss loads bytes via the VFS
    /// and uploads, or falls back to the loader's placeholder when the file
    /// is absent. First resolution of any key populates the cache, so both
    /// the counters and the once-only logging count distinct keys.
    func texture(key: String?, usage: TextureUsage) -> MTLTexture {
        guard let key else {
            return cachedPlaceholder(path: Self.untexturedPath, usage: usage, label: "(untextured)")
        }
        // Fall back to the raw key if normalize rejects it; contents(forPath:)
        // then throws and the miss branch logs + placeholders it once.
        let normalized = (try? VirtualFileSystem.normalize(key)) ?? key
        let cacheKey = CacheKey(path: normalized, usage: usage)
        recordTouch(Self.keyString(cacheKey))
        if let hit = cache[cacheKey] {
            return hit
        }

        let texture: MTLTexture
        if let data = try? fileSystem.contents(forPath: normalized) {
            texture = loader.texture(dds: data, usage: usage, label: normalized)
            loadedCount += 1
        } else {
            texture = loader.missingTexture(usage: usage, label: normalized)
            missingCount += 1
        }
        cache[cacheKey] = texture
        return texture
    }

    /// TextureProvider closure for RenderModel construction. Captures self —
    /// used synchronously during RenderModel.init, never stored or escaped.
    var provider: TextureProvider {
        { [self] key, usage in texture(key: key, usage: usage) }
    }

    /// Placeholder for a path with no bytes to upload (nil key). Cached so
    /// the loader logs the fallback once, not per untextured material.
    private func cachedPlaceholder(
        path: String,
        usage: TextureUsage,
        label: String
    ) -> MTLTexture {
        let cacheKey = CacheKey(path: path, usage: usage)
        recordTouch(Self.keyString(cacheKey))
        if let hit = cache[cacheKey] {
            return hit
        }
        let texture = loader.missingTexture(usage: usage, label: label)
        cache[cacheKey] = texture
        return texture
    }

    // MARK: - Eviction (streaming unload)

    /// Returns and clears the keys touched since the last drain -- one cell's
    /// texture working set, recorded onto its CellScene so unload can compute
    /// which textures are still needed. Confined to the build queue.
    func drainTouchedKeys() -> Set<String> {
        let out = touchedKeys
        touchedKeys.removeAll(keepingCapacity: true)
        return out
    }

    /// Captures texture keys resolved by one model upload. MeshLibrary stores
    /// the result so a later mesh-cache hit can reproduce texture liveness.
    func beginKeyCapture() {
        capturedKeys = []
    }

    func endKeyCapture() -> Set<String> {
        let out = capturedKeys ?? []
        capturedKeys = nil
        return out
    }

    func markTouched(_ keys: Set<String>) {
        touchedKeys.formUnion(keys)
    }

    private func recordTouch(_ key: String) {
        touchedKeys.insert(key)
        capturedKeys?.insert(key)
    }

    /// Drops the cached textures whose keys are in `keys` -- the set a departing
    /// cell used that no resident cell still needs (docs/engine/cell-streaming.md
    /// eviction). Drop-set (not keep-set) so a concurrent build's fresh
    /// textures are never evicted. GPU memory frees when the last reference
    /// dies (the composed scene dropped it on recompose; the renderer's retire
    /// list frees it once in-flight frames drain). Reloads on demand if the
    /// cell returns, so over-eviction only costs a reload, never correctness.
    /// Runs on the build queue (confinement). Returns freed entry count.
    @discardableResult
    func evict(dropping keys: Set<String>) -> Int {
        guard !keys.isEmpty else { return 0 }
        let before = cache.count
        cache = cache.filter { !keys.contains(Self.keyString($0.key)) }
        return before - cache.count
    }
}
