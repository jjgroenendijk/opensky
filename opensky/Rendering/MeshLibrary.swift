// Shared model cache keyed by normalized VFS mesh path: parse + upload a NIF
// once, hand the same RenderModel to every reference that places it (todo 2.7
// asset caches). Bridges the VFS (bytes), the NIF flattener, and RenderModel
// (GPU upload + material resolution via TextureLibrary). Failures surface as
// typed errors so scene build can log + skip one ref instead of aborting the
// whole cell (AGENTS.md mod-quirk rule).
//
// Single-threaded by confinement, not locking: every touch (scene build) runs
// on the streamer's ONE serial build queue (SerialCellBuildRunner), never the
// main thread, so the dictionary needs no lock. Main only receives finished
// CellScene values. GPU uploads (RenderModel/RenderMesh) off that queue are
// safe. TextureLibrary + VFS follow the same confinement rule. Decision:
// docs/engine/cell-streaming.md.

import Foundation
import Metal
import simd

/// Axis-aligned bounds in model space, captured from CPU-side vertex data at
/// load time (vertices live only on the GPU afterwards). Scene build (todo
/// 2.7) pushes the 8 corners through each instance transform to accumulate a
/// world AABB for camera placement.
nonisolated struct ModelBounds: Equatable {
    let min: SIMD3<Float>
    let max: SIMD3<Float>

    /// The 8 corner points, for pushing through an affine transform.
    var corners: [SIMD3<Float>] {
        [min.x, max.x].flatMap { x in
            [min.y, max.y].flatMap { y in
                [min.z, max.z].map { z in SIMD3(x, y, z) }
            }
        }
    }

    func union(_ other: ModelBounds) -> ModelBounds {
        ModelBounds(min: simd_min(min, other.min), max: simd_max(max, other.max))
    }

    /// Nil for an empty point set.
    static func containing(_ points: [SIMD3<Float>]) -> ModelBounds? {
        guard let first = points.first else { return nil }
        var lower = first
        var upper = first
        for point in points.dropFirst() {
            lower = simd_min(lower, point)
            upper = simd_max(upper, point)
        }
        return ModelBounds(min: lower, max: upper)
    }

    /// Union of each mesh's local vertex AABB pushed through its
    /// mesh -> model transform. Nil when no mesh carries positions.
    static func containing(model: Model) -> ModelBounds? {
        var result: ModelBounds?
        for mesh in model.meshes {
            guard let local = containing(mesh.positions) else { continue }
            let inModelSpace = local.transformed(by: mesh.transform)
            result = result.map { $0.union(inModelSpace) } ?? inModelSpace
        }
        return result
    }

    /// AABB of this box under an affine transform: all 8 corners pushed
    /// through, re-boxed. Conservative under rotation — exact enough for
    /// camera framing.
    func transformed(by matrix: float4x4) -> ModelBounds {
        let moved = corners.map { corner in
            let out = matrix * SIMD4(corner, 1)
            return SIMD3(out.x, out.y, out.z)
        }
        // corners is never empty, so containing cannot return nil.
        return Self.containing(moved) ?? self
    }
}

nonisolated enum MeshLibraryError: Error, Equatable {
    /// VFS could not resolve the mesh path (missing loose file + archive entry).
    case fileNotFound(path: String)
    /// NIF container/scene-graph parse or GPU upload failed.
    case parseFailed(path: String, reason: String)
    /// Parsed fine but flattened to zero drawable meshes (unsupported/empty) —
    /// nothing to place, so the ref is dropped rather than drawn invisible.
    case emptyModel(path: String)
}

nonisolated final class MeshLibrary {
    private let fileSystem: VirtualFileSystem
    private let device: MTLDevice
    private let textures: TextureLibrary
    private var cache: [String: RenderModel] = [:]
    /// Per-path count of shapes the flattener dropped (unsupported or empty), so
    /// scene build can report skips without re-parsing.
    private var skippedShapes: [String: Int] = [:]
    /// Model-space AABB per loaded path — captured at parse time because the
    /// vertex data is gone from the CPU after upload (see ModelBounds).
    private var modelBounds: [String: ModelBounds] = [:]
    /// Texture keys captured when each cached model was first uploaded.
    private var modelTextureKeys: [String: Set<String>] = [:]
    /// Mesh keys resolved since the last drain, so a cell build can record its
    /// mesh working set (for eviction keep-sets). Build-queue confined.
    private var touchedKeys: Set<String> = []
    private var cachedCharacterSkeleton: NIFSkeleton?
    private var triedCharacterSkeleton = false
    private var actorSkeletons: [String: NIFSkeleton] = [:]

    /// Distinct mesh paths successfully parsed + uploaded.
    private(set) var loadedCount = 0

    init(fileSystem: VirtualFileSystem, device: MTLDevice, textures: TextureLibrary) {
        self.fileSystem = fileSystem
        self.device = device
        self.textures = textures
    }

    /// Loads (or returns the cached) RenderModel for a MODL-style path such as
    /// "meshes\\clutter\\cup.nif". Separator- and case-insensitive: normalized
    /// via VirtualFileSystem.normalize. Records may omit the "meshes\\" root,
    /// so it is prepended when absent. Same normalized key -> identical
    /// RenderModel instance (shared across every placing ref).
    func model(path: String) throws -> RenderModel {
        try loadModel(path: path, terrainLODClipMask: nil)
    }

    /// Loads one terrain LOD variant with geometry clipped to exact visible
    /// cells. Variants cache independently from full BTR models.
    func model(
        path: String,
        terrainLODClipMask: TerrainLODClipMask
    ) throws -> RenderModel {
        try loadModel(path: path, terrainLODClipMask: terrainLODClipMask)
    }

    private func loadModel(
        path: String,
        terrainLODClipMask: TerrainLODClipMask?,
        actorSkeleton: ActorSkeletonAsset? = nil,
        explicitActorSkeleton: Bool = false
    ) throws -> RenderModel {
        let pathKey = try meshKey(for: path)
        let key = cacheKey(
            path: pathKey,
            terrainLODClipMask: terrainLODClipMask,
            actorSkeletonKey: explicitActorSkeleton ? actorSkeleton?.pathKey ?? "none" : nil
        )
        touchedKeys.insert(key)
        if let hit = cache[key] {
            textures.markTouched(modelTextureKeys[key] ?? [])
            return hit
        }

        guard let data = try? fileSystem.contents(forPath: pathKey) else {
            throw MeshLibraryError.fileNotFound(path: pathKey)
        }
        let sourceModel: Model
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
            sourceModel = try file.model(skeleton: skeleton)
        } catch {
            throw MeshLibraryError.parseFailed(path: pathKey, reason: String(describing: error))
        }
        let model = terrainLODClipMask.map { TerrainLODClipper.clipped(sourceModel, to: $0) }
            ?? sourceModel
        guard !model.meshes.isEmpty else { throw MeshLibraryError.emptyModel(path: key) }

        let render: RenderModel
        textures.beginKeyCapture()
        do {
            render = try RenderModel(
                device: device,
                model: model,
                textureProvider: textures.provider
            )
        } catch {
            _ = textures.endKeyCapture()
            throw MeshLibraryError.parseFailed(path: key, reason: String(describing: error))
        }
        modelTextureKeys[key] = textures.endKeyCapture()
        cache[key] = render
        skippedShapes[key] = model.skippedShapeCount
        modelBounds[key] = ModelBounds.containing(model: model)
        loadedCount += 1
        return render
    }

    func loadActorSkeleton(path: String) -> Result<ActorSkeletonAsset, ActorAssetFailure> {
        let pathKey: String
        do {
            pathKey = try meshKey(for: path)
        } catch {
            return .failure(.missing)
        }
        if let skeleton = actorSkeletons[pathKey] {
            return .success(ActorSkeletonAsset(pathKey: pathKey, skeleton: skeleton))
        }
        guard let data = try? fileSystem.contents(forPath: pathKey) else {
            return .failure(.missing)
        }
        do {
            let skeleton = try NIFSkeleton(file: NIFFile(data: data))
            actorSkeletons[pathKey] = skeleton
            return .success(ActorSkeletonAsset(pathKey: pathKey, skeleton: skeleton))
        } catch {
            return .failure(.invalid)
        }
    }

    func loadActorModel(
        path: String,
        skeleton: ActorSkeletonAsset?
    ) -> Result<ActorRenderAsset, ActorAssetFailure> {
        do {
            let model = try loadModel(
                path: path,
                terrainLODClipMask: nil,
                actorSkeleton: skeleton,
                explicitActorSkeleton: true
            )
            let pathKey = try meshKey(for: path)
            let key = cacheKey(
                path: pathKey,
                terrainLODClipMask: nil,
                actorSkeletonKey: skeleton?.pathKey ?? "none"
            )
            return .success(ActorRenderAsset(model: model, bounds: modelBounds[key]))
        } catch MeshLibraryError.fileNotFound {
            return .failure(.missing)
        } catch {
            return .failure(.invalid)
        }
    }

    private func characterSkeleton() -> NIFSkeleton? {
        if triedCharacterSkeleton {
            return cachedCharacterSkeleton
        }
        triedCharacterSkeleton = true
        let path = "meshes\\actors\\character\\character assets\\skeleton.nif"
        guard
            let data = try? fileSystem.contents(forPath: path),
            let file = try? NIFFile(data: data),
            let skeleton = try? NIFSkeleton(file: file)
        else { return nil }
        cachedCharacterSkeleton = skeleton
        return skeleton
    }

    /// Uploads an engine-built terrain patch: the quadrant mesh plus its
    /// packed splat-weight stream (two float4 lanes per vertex,
    /// TerrainVertexLayout) — terrain from LAND (todo 3.1). Shares the
    /// library's device so terrain draws through the same residency set. Not
    /// cached: terrain patches are per-cell and unique, unlike shared NIFs.
    func terrainMesh(
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
    func renderMesh(_ mesh: Mesh) throws -> RenderMesh {
        try RenderMesh(device: device, mesh: mesh)
    }

    /// Uploads + caches engine-generated model geometry under a semantic key.
    /// Tree LOD uses this for one crossed-quad model per LST atlas type, then
    /// instances it for every BTT reference. Generated keys join normal
    /// touched-key eviction + texture liveness accounting.
    func generatedModel(key: String, model: Model) throws -> RenderModel {
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
    func skippedShapeCount(forPath path: String) -> Int? {
        guard let key = try? meshKey(for: path) else { return nil }
        return skippedShapes[key]
    }

    /// Total shapes dropped across every loaded model.
    var totalSkippedShapeCount: Int {
        skippedShapes.values.reduce(0, +)
    }

    /// Model-space bounds for an already-loaded path (nil if the path never
    /// loaded or the model carried no vertex positions).
    func bounds(forPath path: String) -> ModelBounds? {
        bounds(forPath: path, terrainLODClipMask: nil)
    }

    func bounds(
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
    func drainTouchedKeys() -> Set<String> {
        let out = touchedKeys
        touchedKeys.removeAll(keepingCapacity: true)
        return out
    }

    /// Drops the cached models (+ bounds/skip counts) whose keys are in `keys`
    /// -- the set a departing cell used that no resident cell still needs
    /// (docs/engine/cell-streaming.md eviction). Drop-set (not keep-set) so a
    /// concurrent build's fresh models are never evicted. The RenderModel
    /// deallocates once the last reference dies: no resident composed scene
    /// references a departed cell's meshes, and the renderer's retire list
    /// frees the GPU buffers when in-flight frames drain. Reloads on demand if
    /// the cell returns. Runs on the build queue. Returns freed model count.
    @discardableResult
    func evict(dropping keys: Set<String>) -> Int {
        var freed = 0
        for key in keys {
            if cache.removeValue(forKey: key) != nil {
                freed += 1
            }
            skippedShapes.removeValue(forKey: key)
            modelBounds.removeValue(forKey: key)
            modelTextureKeys.removeValue(forKey: key)
        }
        return freed
    }

    /// Normalizes a MODL-style path and prepends the "meshes\\" root when the
    /// record omitted it. Rejects empty/escaping paths as not-found.
    private func meshKey(for path: String) throws -> String {
        guard let normalized = try? VirtualFileSystem.normalize(path) else {
            throw MeshLibraryError.fileNotFound(path: path)
        }
        return normalized.hasPrefix("meshes\\") ? normalized : "meshes\\" + normalized
    }

    private func cacheKey(
        path: String,
        terrainLODClipMask: TerrainLODClipMask?,
        actorSkeletonKey: String? = nil
    ) -> String {
        var key = path
        if let terrainLODClipMask {
            key += "|terrain-lod:" + terrainLODClipMask.cacheKey
        }
        if let actorSkeletonKey {
            key += "|actor-skeleton:" + actorSkeletonKey
        }
        return key
    }
}
