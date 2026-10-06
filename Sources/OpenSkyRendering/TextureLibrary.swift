// Texture cache keyed by normalized VFS path and usage. A nil key, missing
// file, or bad DDS resolves to the loader's placeholder, logged once per path.
// Only the one serial cell-build queue touches it, so it needs no lock
// (docs/engine/cell-streaming.md).

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyGameData

nonisolated public final class TextureLibrary {
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

    private let fileSystem: any GameFileSource
    private let loader: TextureLoader
    private var cache: [CacheKey: MTLTexture] = [:]

    /// Keys resolved since the last drain, so a cell build can record exactly
    /// which textures it uses (for eviction keep-sets). Confined to the build
    /// queue like the cache; drained per build by CellSceneBuilder.
    private var touchedKeys: Set<String> = []
    /// Per-model capture active only during one RenderModel construction.
    private var capturedKeys: Set<String>?

    /// Distinct paths whose bytes were found and handed to the loader.
    public private(set) var loadedCount = 0
    /// Distinct paths the VFS could not resolve (each fell back to placeholder).
    public private(set) var missingCount = 0
    /// Books each upload to `LoadPhase.texture` when a benchmark attaches one.
    public var loadPhases: LoadPhaseRecorder?
    /// Converted textures, read before the archive when current.
    public var assetCache: AssetCacheReader?
    /// Reads cached textures inside `batchLoads` without the CPU, when set and on.
    public var fastLoader: FastTextureLoader?
    private var batchDepth = 0

    public init(fileSystem: any GameFileSource, loader: TextureLoader) {
        self.fileSystem = fileSystem
        self.loader = loader
    }

    public convenience init(fileSystem: any GameFileSource, device: MTLDevice) throws {
        try self.init(fileSystem: fileSystem, loader: TextureLoader(device: device))
    }

    /// Resolves a material's texture key to a ready MTLTexture. nil key ->
    /// shared untextured placeholder (expected, not counted). Otherwise a
    /// cache hit returns the shared texture; a miss loads bytes via the VFS
    /// and uploads, or falls back to the loader's placeholder when the file
    /// is absent. First resolution of any key populates the cache, so both
    /// the counters and the once-only logging count distinct keys.
    public func texture(key: String?, usage: TextureUsage) -> MTLTexture {
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

        let texture = loadPhases.measure(.texture) {
            load(path: normalized, usage: usage)
        }
        cache[cacheKey] = texture
        return texture
    }

    /// Uploads DDS bytes made at runtime under `key`, so a material that names the
    /// key finds them as if they came from an archive.
    public func register(dds: Data, key: String, usage: TextureUsage) {
        let normalized = (try? VirtualFileSystem.normalize(key)) ?? key
        cache[CacheKey(path: normalized, usage: usage)] = loader.texture(
            dds: dds, usage: usage, label: normalized
        )
    }

    /// Runs `body` as one batch: the fast loader queues every cached texture
    /// it loads, and the batch completes before this returns.
    public func batchLoads<Result>(_ body: () throws -> Result) rethrows -> Result {
        batchDepth += 1
        defer {
            batchDepth -= 1
            if batchDepth == 0 {
                fastLoader?.flush()
            }
        }
        return try body()
    }

    private func load(path: String, usage: TextureUsage) -> MTLTexture {
        if
            batchDepth > 0, let fastLoader, fastLoader.control.isEnabled,
            let entry = assetCache?.entry(forPath: path, decoder: .readyTexture)
        {
            loadedCount += 1
            if let texture = try? fastLoader.enqueue(entry, usage: usage, label: path) {
                return texture
            }
            return loader.texture(ready: entry.value, usage: usage, label: path)
        }
        if let ready = assetCache?.value(forPath: path, decoder: .readyTexture) {
            loadedCount += 1
            return loader.texture(ready: ready, usage: usage, label: path)
        }
        guard let data = try? fileSystem.contents(forPath: path) else {
            missingCount += 1
            return loader.missingTexture(usage: usage, label: path)
        }
        loadedCount += 1
        return loader.texture(dds: data, usage: usage, label: path)
    }

    /// TextureProvider closure for RenderModel construction. Captures self —
    /// used synchronously during RenderModel.init, never stored or escaped.
    public var provider: TextureProvider {
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
    public func drainTouchedKeys() -> Set<String> {
        let out = touchedKeys
        touchedKeys.removeAll(keepingCapacity: true)
        return out
    }

    /// Captures texture keys resolved by one model upload. MeshLibrary stores
    /// the result so a later mesh-cache hit can reproduce texture liveness.
    public func beginKeyCapture() {
        capturedKeys = []
    }

    public func endKeyCapture() -> Set<String> {
        let out = capturedKeys ?? []
        capturedKeys = nil
        return out
    }

    public func markTouched(_ keys: Set<String>) {
        touchedKeys.formUnion(keys)
    }

    private func recordTouch(_ key: String) {
        touchedKeys.insert(key)
        capturedKeys?.insert(key)
    }

    /// Drops the cached textures in `keys` and returns how many it freed. A
    /// drop-set, not a keep-set, so a concurrent build's new textures survive.
    /// See docs/engine/cell-streaming.md.
    @discardableResult
    public func evict(dropping keys: Set<String>) -> Int {
        guard !keys.isEmpty else { return 0 }
        let before = cache.count
        cache = cache.filter { !keys.contains(Self.keyString($0.key)) }
        return before - cache.count
    }
}
