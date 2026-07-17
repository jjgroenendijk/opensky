// Shared texture cache keyed by normalized VFS path + usage: load a DDS once,
// hand the same MTLTexture to every material that references it (todo 2.7
// asset caches). Bridges the VFS (bytes) and TextureLoader (upload) so scene
// build stays ignorant of both. Never throws — a nil key, a missing file, or
// a bad DDS all resolve to the loader's shared placeholder, cached so each
// distinct path logs at most once.
//
// Single-threaded: scene build touches this at startup, so the dictionary
// needs no lock (siblings follow the same rule; VFS itself is thread-safe).

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

    private let fileSystem: VirtualFileSystem
    private let loader: TextureLoader
    private var cache: [CacheKey: MTLTexture] = [:]

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
        if let hit = cache[cacheKey] {
            return hit
        }
        let texture = loader.missingTexture(usage: usage, label: label)
        cache[cacheKey] = texture
        return texture
    }
}
