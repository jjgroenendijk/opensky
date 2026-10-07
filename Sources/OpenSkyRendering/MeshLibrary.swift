// Model cache keyed by normalized mesh path: parse and upload a NIF once, share the
// `RenderModel`. Failures are typed, so a scene build skips one reference. Confined to
// the streamer's one serial build queue, so it needs no lock; main only gets finished
// `CellScene` values. See docs/engine/cell-streaming.md.

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import simd

nonisolated public enum MeshLibraryError: Error, Equatable {
    /// VFS could not resolve the mesh path (missing loose file + archive entry).
    case fileNotFound(path: String)
    /// NIF container/scene-graph parse or GPU upload failed.
    case parseFailed(path: String, reason: String)
    /// Parsed fine but flattened to zero drawable meshes (unsupported/empty) —
    /// nothing to place, so the ref is dropped rather than drawn invisible.
    case emptyModel(path: String)
    /// Every shape is an editor marker, which the game does not draw.
    case editorMarkerOnly(path: String)
}

nonisolated public final class MeshLibrary {
    public let fileSystem: any GameFileSource
    public let device: MTLDevice
    public let textures: TextureLibrary
    private var cache: [String: RenderModel] = [:]
    /// Per-path count of shapes the flattener dropped (unsupported or empty), so
    /// scene build can report skips without re-parsing.
    private var skippedShapes: [String: Int] = [:]
    /// Model-space AABB per loaded path — captured at parse time because the
    /// vertex data is gone from the CPU after upload (see ModelBounds).
    public var modelBounds: [String: ModelBounds] = [:]
    /// Texture keys captured when each cached model was first uploaded.
    private var modelTextureKeys: [String: Set<String>] = [:]
    /// Immutable particle definitions decoded beside each normal model. A
    /// placed ref gets fresh playback state while sharing cached texture/GPU
    /// resources through TextureLibrary.
    public var particleDefinitions: [String: [ParticleSystemDefinition]] = [:]
    /// Mesh keys resolved since the last drain, so a cell build can record its
    /// mesh working set (for eviction keep-sets). Build-queue confined.
    private var touchedKeys: Set<String> = []
    // Internal rather than private: the actor-facing loaders live in
    // MeshLibraryActors.swift (split for the type-body length cap) and a Swift
    // extension in another file cannot reach `private` members. Still
    // build-queue confined; nothing outside this type writes them.
    public var cachedCharacterSkeleton: NIFSkeleton?
    public var triedCharacterSkeleton = false
    public var actorSkeletons: [String: NIFSkeleton] = [:]

    /// Distinct mesh paths successfully parsed + uploaded.
    public private(set) var loadedCount = 0
    /// Books each parse and upload to `LoadPhase.mesh` when a benchmark attaches one.
    public var loadPhases: LoadPhaseRecorder?
    /// Converted models. The converter stores only models that need no skeleton
    /// and have no particles, so a hit equals the direct decode.
    public var assetCache: AssetCacheReader?

    public init(fileSystem: any GameFileSource, device: MTLDevice, textures: TextureLibrary) {
        self.fileSystem = fileSystem
        self.device = device
        self.textures = textures
    }

    /// Loads (or returns the cached) RenderModel for a MODL-style path such as
    /// "meshes\\clutter\\cup.nif". Separator- and case-insensitive: normalized
    /// via VirtualFileSystem.normalize. Records may omit the "meshes\\" root,
    /// so it is prepended when absent. Same normalized key -> identical
    /// RenderModel instance (shared across every placing ref).
    public func model(path: String) throws -> RenderModel {
        try loadModel(path: path, terrainLODClipMask: nil)
    }

    /// A model with `surface` laid over it, cached apart from the plain model.
    /// An empty surface is the plain model.
    public func model(path: String, surface: ModelSurfaceOverride) throws -> RenderModel {
        try loadModel(path: path, terrainLODClipMask: nil, surface: surface.isEmpty ? nil : surface)
    }

    /// Loads one terrain LOD variant with geometry clipped to exact visible
    /// cells. Variants cache independently from full BTR models.
    public func model(
        path: String,
        terrainLODClipMask: TerrainLODClipMask
    ) throws -> RenderModel {
        try loadModel(path: path, terrainLODClipMask: terrainLODClipMask)
    }

    /// Records the textures the model asked for, so a cache hit can mark them touched.
    private func makeRenderModel(_ model: Model, key: String) throws -> RenderModel {
        textures.beginKeyCapture()
        do {
            let render = try RenderModel(
                device: device, model: model, textureProvider: textures.provider
            )
            modelTextureKeys[key] = textures.endKeyCapture()
            return render
        } catch {
            _ = textures.endKeyCapture()
            throw MeshLibraryError.parseFailed(path: key, reason: String(describing: error))
        }
    }

    public func loadModel(
        path: String,
        terrainLODClipMask: TerrainLODClipMask?,
        actorSkeleton: ActorSkeletonAsset? = nil,
        explicitActorSkeleton: Bool = false,
        attachmentBone: String? = nil,
        surface: ModelSurfaceOverride? = nil
    ) throws -> RenderModel {
        let pathKey = try meshKey(for: path)
        let key = cacheKey(
            path: pathKey,
            terrainLODClipMask: terrainLODClipMask,
            actorSkeletonKey: explicitActorSkeleton ? actorSkeleton?.pathKey ?? "none" : nil,
            attachmentBone: attachmentBone,
            surface: surface
        )
        touchedKeys.insert(key)
        if let hit = cache[key] {
            textures.markTouched(modelTextureKeys[key] ?? [])
            return hit
        }

        return try loadPhases.measure(.mesh) {
            let plain = terrainLODClipMask == nil && surface == nil && attachmentBone == nil
                && !explicitActorSkeleton
            if plain, let ready = readyModel(key: key, pathKey: pathKey) {
                return ready
            }
            let decoded = try decode(
                pathKey: pathKey,
                actorSkeleton: actorSkeleton,
                explicitActorSkeleton: explicitActorSkeleton
            )
            let decodedParticles = decoded.particles
            var model = terrainLODClipMask
                .map { TerrainLODClipper.clipped(decoded.model, to: $0) } ?? decoded.model
            if let surface {
                model = surface.applied(to: model)
            }
            if let attachmentBone {
                model = RigidAttachment.skinned(
                    model,
                    to: attachmentBone,
                    restTransform: actorSkeleton?.skeleton
                        .transform(forBoneNamed: attachmentBone) ?? matrix_identity_float4x4
                )
            }
            guard !model.meshes.isEmpty else {
                throw model.editorMarkerShapeCount > 0
                    ? MeshLibraryError.editorMarkerOnly(path: key)
                    : MeshLibraryError.emptyModel(path: key)
            }

            let render = try makeRenderModel(model, key: key)
            cache[key] = render
            particleDefinitions[key] = decodedParticles
            skippedShapes[key] = model.skippedShapeCount
            modelBounds[key] = ModelBounds.containing(model: model)
            loadedCount += 1
            return render
        }
    }

    /// A cached model whose mesh bytes the fast loader reads straight into GPU buffers.
    /// Nil sends the load down the decode path.
    private func readyModel(key: String, pathKey: String) -> RenderModel? {
        guard
            let loader = textures.fastMeshLoader,
            let entry = assetCache?.modelLayout(forPath: pathKey), entry.value.isReady,
            let meshes = try? loader.enqueue(entry, label: pathKey)
        else { return nil }
        let layout = entry.value
        textures.beginKeyCapture()
        let render = RenderModel(
            meshes: meshes, materials: layout.materials, textureProvider: textures.provider
        )
        modelTextureKeys[key] = textures.endKeyCapture()
        cache[key] = render
        particleDefinitions[key] = []
        skippedShapes[key] = layout.skippedShapeCount
        modelBounds[key] = layout.bounds
        loadedCount += 1
        return render
    }

    /// Uploads a LAND terrain patch: the quadrant mesh and its splat-weight stream (two
    /// float4 per vertex, `TerrainVertexLayout`). Not cached: each patch is unique.
    public func terrainMesh(
        _ mesh: Mesh,
        weights: [SIMD4<Float>]
    ) throws -> (mesh: RenderMesh, weightsBuffer: MTLBuffer) {
        try loadPhases.measure(.mesh) { try uploadTerrain(mesh, weights: weights) }
    }

    private func uploadTerrain(
        _ mesh: Mesh,
        weights: [SIMD4<Float>]
    ) throws -> (mesh: RenderMesh, weightsBuffer: MTLBuffer) {
        let render = try RenderMesh(device: device, mesh: mesh)
        // Weight stream must cover every vertex the descriptor will fetch.
        guard
            weights.count == mesh.positions.count * 2,
            let buffer = device.makeBuffer(
                bytes: weights,
                length: weights.count * MemoryLayout<SIMD4<Float>>.stride,
                options: .storageModeShared
            ) else { throw RenderMeshError.bufferAllocationFailed }
        buffer.label = "\(mesh.name ?? "terrain").weights"
        return (render, buffer)
    }

    /// Uploads small engine-built geometry that needs only the shared static
    /// vertex stream. Callers cache reusable meshes at their semantic level.
    public func renderMesh(_ mesh: Mesh) throws -> RenderMesh {
        try RenderMesh(device: device, mesh: mesh)
    }

    /// Uploads + caches engine-generated model geometry under a semantic key.
    /// Tree LOD uses this for one crossed-quad model per LST atlas type, then
    /// instances it for every BTT reference. Generated keys join normal
    /// touched-key eviction + texture liveness accounting.
    public func generatedModel(key: String, model: Model) throws -> RenderModel {
        let cacheKey = "generated|\(key)"
        touchedKeys.insert(cacheKey)
        if let hit = cache[cacheKey] {
            textures.markTouched(modelTextureKeys[cacheKey] ?? [])
            return hit
        }

        textures.beginKeyCapture()
        let render: RenderModel
        do {
            render = try RenderModel(
                device: device,
                model: model,
                textureProvider: textures.provider
            )
        } catch {
            _ = textures.endKeyCapture()
            throw MeshLibraryError.parseFailed(
                path: cacheKey,
                reason: String(describing: error)
            )
        }
        modelTextureKeys[cacheKey] = textures.endKeyCapture()
        cache[cacheKey] = render
        skippedShapes[cacheKey] = model.skippedShapeCount
        modelBounds[cacheKey] = ModelBounds.containing(model: model)
        loadedCount += 1
        return render
    }

    /// Shapes dropped during flatten for an already-loaded path (nil if the
    /// path was never successfully loaded).
    public func skippedShapeCount(forPath path: String) -> Int? {
        guard let key = try? meshKey(for: path) else { return nil }
        return skippedShapes[key]
    }

    /// Total shapes dropped across every loaded model.
    public var totalSkippedShapeCount: Int {
        skippedShapes.values.reduce(0, +)
    }

    /// Model-space bounds for an already-loaded path (nil if the path never
    /// loaded or the model carried no vertex positions).
    public func bounds(forPath path: String) -> ModelBounds? {
        bounds(forPath: path, terrainLODClipMask: nil)
    }

    public func bounds(forPath path: String, surface: ModelSurfaceOverride) -> ModelBounds? {
        guard let pathKey = try? meshKey(for: path) else { return nil }
        let key = cacheKey(path: pathKey, terrainLODClipMask: nil, surface: surface)
        return modelBounds[key]
    }

    public func bounds(
        forPath path: String,
        terrainLODClipMask: TerrainLODClipMask?
    ) -> ModelBounds? {
        guard let pathKey = try? meshKey(for: path) else { return nil }
        let key = cacheKey(path: pathKey, terrainLODClipMask: terrainLODClipMask)
        return modelBounds[key]
    }

    // MARK: - Eviction (streaming unload)

    /// Returns and clears the mesh keys touched since the last drain -- one
    /// cell's mesh working set, recorded onto its CellScene so unload can
    /// compute which models are still needed. Build-queue confined.
    public func drainTouchedKeys() -> Set<String> {
        let out = touchedKeys
        touchedKeys.removeAll(keepingCapacity: true)
        return out
    }

    /// Drops the cached models in `keys`: those a departing cell used and no resident
    /// cell needs. A drop-set, so a concurrent build's models survive. The retire list
    /// frees GPU buffers later. Runs on the build queue. Returns the freed count.
    @discardableResult
    public func evict(dropping keys: Set<String>) -> Int {
        var freed = 0
        for key in keys {
            if cache.removeValue(forKey: key) != nil {
                freed += 1
            }
            skippedShapes.removeValue(forKey: key)
            modelBounds.removeValue(forKey: key)
            modelTextureKeys.removeValue(forKey: key)
            particleDefinitions.removeValue(forKey: key)
        }
        return freed
    }

    /// Normalizes a MODL-style path and prepends the "meshes\\" root when the
    /// record omitted it. Rejects empty/escaping paths as not-found.
    public func meshKey(for path: String) throws -> String {
        guard let normalized = try? VirtualFileSystem.normalize(path) else {
            throw MeshLibraryError.fileNotFound(path: path)
        }
        return normalized.hasPrefix("meshes\\") ? normalized : "meshes\\" + normalized
    }

    public func cacheKey(
        path: String,
        terrainLODClipMask: TerrainLODClipMask?,
        actorSkeletonKey: String? = nil,
        attachmentBone: String? = nil,
        surface: ModelSurfaceOverride? = nil
    ) -> String {
        var key = path
        if let terrainLODClipMask {
            key += "|terrain-lod:" + terrainLODClipMask.cacheKey
        }
        if let actorSkeletonKey {
            key += "|actor-skeleton:" + actorSkeletonKey
        }
        if let attachmentBone {
            key += "|attach:" + attachmentBone
        }
        if let surface, !surface.isEmpty {
            key += "|" + surface.cacheKey
        }
        return key
    }
}

nonisolated extension MeshLibrary {
    /// The NIF behind one normalized key, flattened. Skeleton choice: an
    /// explicit actor skeleton when the caller supplied one, otherwise the
    /// shared character rig for skinned character meshes, otherwise none.
    private func decode(
        pathKey: String,
        actorSkeleton: ActorSkeletonAsset?,
        explicitActorSkeleton: Bool
    ) throws -> (model: Model, particles: [ParticleSystemDefinition]) {
        if
            !explicitActorSkeleton,
            let model = assetCache?.value(forPath: pathKey, decoder: .model)
        {
            return (model, [])
        }
        guard let data = try? fileSystem.contents(forPath: pathKey) else {
            throw MeshLibraryError.fileNotFound(path: pathKey)
        }
        do {
            let file = try NIFFile(data: data)
            let skeleton: NIFSkeleton?
            if explicitActorSkeleton {
                skeleton = actorSkeleton?.skeleton
            } else {
                let usesCharacterSkeleton = pathKey.hasPrefix("meshes\\actors\\character\\")
                    && file.blocks.contains { $0.typeName == "NiSkinData" }
                skeleton = usesCharacterSkeleton ? characterSkeleton() : nil
            }
            return try (file.model(skeleton: skeleton), file.particleSystems())
        } catch let error as MeshLibraryError {
            throw error
        } catch {
            throw MeshLibraryError.parseFailed(path: pathKey, reason: String(describing: error))
        }
    }
}
