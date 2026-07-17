// Shared model cache keyed by normalized VFS mesh path: parse + upload a NIF
// once, hand the same RenderModel to every reference that places it (todo 2.7
// asset caches). Bridges the VFS (bytes), the NIF flattener, and RenderModel
// (GPU upload + material resolution via TextureLibrary). Failures surface as
// typed errors so scene build can log + skip one ref instead of aborting the
// whole cell (AGENTS.md mod-quirk rule).
//
// Single-threaded: scene build touches this at startup, so the dictionary
// needs no lock (TextureLibrary + VFS follow the same rule).

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
    /// Parsed fine but flattened to zero drawable meshes (all skinned/empty) —
    /// nothing to place, so the ref is dropped rather than drawn invisible.
    case emptyModel(path: String)
}

nonisolated final class MeshLibrary {
    private let fileSystem: VirtualFileSystem
    private let device: MTLDevice
    private let textures: TextureLibrary
    private var cache: [String: RenderModel] = [:]
    /// Per-path count of shapes the flattener dropped (skinned or empty), so
    /// scene build can report skips without re-parsing.
    private var skippedShapes: [String: Int] = [:]
    /// Model-space AABB per loaded path — captured at parse time because the
    /// vertex data is gone from the CPU after upload (see ModelBounds).
    private var modelBounds: [String: ModelBounds] = [:]

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
        let key = try meshKey(for: path)
        if let hit = cache[key] {
            return hit
        }

        guard let data = try? fileSystem.contents(forPath: key) else {
            throw MeshLibraryError.fileNotFound(path: key)
        }
        let model: Model
        do {
            model = try NIFFile(data: data).model()
        } catch {
            throw MeshLibraryError.parseFailed(path: key, reason: String(describing: error))
        }
        guard !model.meshes.isEmpty else { throw MeshLibraryError.emptyModel(path: key) }

        let render: RenderModel
        do {
            render = try RenderModel(
                device: device,
                model: model,
                textureProvider: textures.provider
            )
        } catch {
            throw MeshLibraryError.parseFailed(path: key, reason: String(describing: error))
        }
        cache[key] = render
        skippedShapes[key] = model.skippedShapeCount
        modelBounds[key] = ModelBounds.containing(model: model)
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
        guard let key = try? meshKey(for: path) else { return nil }
        return modelBounds[key]
    }

    /// Normalizes a MODL-style path and prepends the "meshes\\" root when the
    /// record omitted it. Rejects empty/escaping paths as not-found.
    private func meshKey(for path: String) throws -> String {
        guard let normalized = try? VirtualFileSystem.normalize(path) else {
            throw MeshLibraryError.fileNotFound(path: path)
        }
        return normalized.hasPrefix("meshes\\") ? normalized : "meshes\\" + normalized
    }
}
