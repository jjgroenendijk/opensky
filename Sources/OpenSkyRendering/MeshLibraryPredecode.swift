// Decodes a cell build's uncached meshes on every core before the serial loads
// ask for them (docs/decisions/concurrency.md). Workers read, look up, and parse;
// the cache writes and the GPU buffer upload stay serial in `loadModel`.

import Foundation
import OpenSkyAssetCache
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRenderResources

/// A mesh decoded ahead of its load, or the error its load will throw.
typealias PredecodedMesh = Result<
    (model: Model, particles: [ParticleSystemDefinition]),
    MeshLibraryError
>

nonisolated extension MeshLibrary {
    /// Decodes the plain variant of each path that is not loaded yet, then prepares the
    /// textures those models name. With fast mesh loading on, a model whose cached
    /// layout is ready keeps only the layout: its bytes go straight into GPU buffers.
    public func predecode(paths: some Sequence<String>) {
        guard decodesInParallel else { return }
        var seen = Set<String>()
        let pathKeys = paths.compactMap { path -> String? in
            guard
                let pathKey = try? meshKey(for: path), seen.insert(pathKey).inserted,
                predecoded[pathKey] == nil, prelaid[pathKey] == nil,
                !isLoaded(pathKey: pathKey)
            else { return nil }
            return pathKey
        }
        guard pathKeys.count >= ParallelDecode.minimumParallelItems else { return }
        loadPhases.measure(.mesh) { predecode(pathKeys: pathKeys) }
    }

    private func predecode(pathKeys: [String]) {
        let cache = assetCache
        var layouts: [String: AssetCacheEntryRead<ReadyModelLayout>] = [:]
        if textures.fastMeshLoader != nil, let cache {
            layouts = ParallelDecode.map(pathKeys) { pathKey in
                cache.modelLayout(forPath: pathKey).flatMap { $0.value.isReady ? $0 : nil }
            }
        }
        let decodeKeys = pathKeys.filter { layouts[$0] == nil }
        var results = ParallelDecode.map(decodeKeys) { pathKey -> PredecodedMesh? in
            cache?.value(forPath: pathKey, decoder: .model).map { .success(($0, [])) }
        }
        let misses = decodeKeys.filter { results[$0] == nil }
        let skeleton = misses.contains { $0.hasPrefix(Self.characterMeshPrefix) }
            ? characterSkeleton() : nil
        // Workers read the archives too; the phase of this fan-out holds their time.
        let files = fileSystem.untimed
        let parsed = ParallelDecode.map(misses) { pathKey -> PredecodedMesh? in
            guard let data = try? files.contents(forPath: pathKey)
            else { return .failure(.fileNotFound(path: pathKey)) }
            return Self.parse(data, pathKey: pathKey, characterSkeleton: skeleton)
        }
        results.merge(parsed) { _, new in new }
        predecoded.merge(results) { _, new in new }
        prelaid.merge(layouts) { _, new in new }
        let materials = layouts.values.flatMap(\.value.materials)
            + results.values.flatMap { (try? $0.get().model.materials) ?? [] }
        textures.prefetch(materials: materials)
    }

    /// Frees decodes that no load asked for, such as a mesh whose reference failed later.
    public func dropPredecoded() {
        predecoded.removeAll()
        prelaid.removeAll()
        textures.dropPrefetched()
    }

    /// Reads and parses the NIF files of `paths` on every core, for actor parts: their
    /// decode needs the actor's skeleton, so only the file parse can run ahead.
    public func preparse(paths: some Sequence<String>) {
        guard decodesInParallel else { return }
        let keys = Set(paths.compactMap { try? meshKey(for: $0) })
            .filter { preparsed[$0] == nil && !actorDecodedPaths.contains($0) }
        guard keys.count >= ParallelDecode.minimumParallelItems else { return }
        let files = fileSystem.untimed
        let parsed = loadPhases.measure(.mesh) {
            ParallelDecode.map(keys) { key in
                (try? files.contents(forPath: key)).flatMap { try? NIFFile(data: $0) }
            }
        }
        preparsed.merge(parsed) { _, new in new }
    }

    /// Frees the files `preparse` read; several actors may share one, so loads keep them.
    public func dropPreparsed() {
        preparsed.removeAll()
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
}
