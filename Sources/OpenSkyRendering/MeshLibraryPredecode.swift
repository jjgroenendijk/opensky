// Decodes a cell build's uncached meshes on every core before the serial loads
// ask for them (docs/decisions/concurrency.md). Archive reads stay on the build
// queue, so the file source and the phase recorder see one thread. Only the
// pure decode fans out, and the GPU upload stays serial in `loadModel`.

import Foundation
import OpenSkyAssetCache
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import Synchronization

/// A mesh decoded ahead of its load, or the error its load will throw.
typealias PredecodedMesh = Result<
    (model: Model, particles: [ParticleSystemDefinition]),
    MeshLibraryError
>

nonisolated extension MeshLibrary {
    /// Fewer meshes than this decode serially: the fan-out costs more than it saves.
    static let minimumParallelDecodes = 4

    /// Decodes the plain variant of each path that is not loaded yet. The fast mesh
    /// loader reads plain models straight into GPU buffers, so it skips this.
    public func predecode(paths: some Sequence<String>) {
        guard textures.fastMeshLoader == nil else { return }
        var seen = Set<String>()
        let pathKeys = paths.compactMap { path -> String? in
            guard
                let pathKey = try? meshKey(for: path), seen.insert(pathKey).inserted,
                predecoded[pathKey] == nil,
                !isLoaded(pathKey: pathKey)
            else { return nil }
            return pathKey
        }
        guard pathKeys.count >= Self.minimumParallelDecodes else { return }
        let cache = assetCache
        var results = Self.decodeInParallel(pathKeys) { pathKey in
            cache?.value(forPath: pathKey, decoder: .model).map { .success(($0, [])) }
        }
        let misses = pathKeys.filter { results[$0] == nil }
        // Reads stay serial; the parse of what they read fans out again.
        let sources = misses.map { (pathKey: $0, data: try? fileSystem.contents(forPath: $0)) }
        let skeleton = sources.contains { $0.pathKey.hasPrefix(Self.characterMeshPrefix) }
            ? characterSkeleton() : nil
        let parsed = Self.decodeInParallel(sources.indices) { index in
            let source = sources[index]
            guard let data = source.data
            else { return .failure(.fileNotFound(path: source.pathKey)) }
            return Self.parse(data, pathKey: source.pathKey, characterSkeleton: skeleton)
        }
        for (index, result) in parsed {
            results[sources[index].pathKey] = result
        }
        predecoded.merge(results) { _, new in new }
    }

    /// Frees decodes that no load asked for, such as a mesh whose reference failed later.
    public func dropPredecoded() {
        predecoded.removeAll()
    }

    /// Takes the decode `predecode` left for this path, if any.
    func takePredecoded(pathKey: String) -> PredecodedMesh? {
        predecoded.removeValue(forKey: pathKey)
    }

    /// The NIF decode of `loadModel`, without the asset cache. Character meshes with
    /// skin data bind to the shared character skeleton.
    static func parse(
        _ data: Data,
        pathKey: String,
        characterSkeleton: NIFSkeleton?
    ) -> PredecodedMesh {
        do {
            let file = try NIFFile(data: data)
            let usesCharacterSkeleton = pathKey.hasPrefix(characterMeshPrefix)
                && file.blocks.contains { $0.typeName == "NiSkinData" }
            let skeleton = usesCharacterSkeleton ? characterSkeleton : nil
            return try .success((file.model(skeleton: skeleton), file.particleSystems()))
        } catch {
            return .failure(.parseFailed(path: pathKey, reason: String(describing: error)))
        }
    }

    static let characterMeshPrefix = "meshes\\actors\\character\\"

    private static func decodeInParallel<Key: Hashable & Sendable>(
        _ keys: some Collection<Key>,
        _ decode: @Sendable (Key) -> PredecodedMesh?
    ) -> [Key: PredecodedMesh] {
        let keys = Array(keys)
        let results = Mutex<[Key: PredecodedMesh]>([:])
        DispatchQueue.concurrentPerform(iterations: keys.count) { index in
            guard let result = decode(keys[index]) else { return }
            results.withLock { $0[keys[index]] = result }
        }
        return results.withLock { $0 }
    }
}
