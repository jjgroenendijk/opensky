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
        if let hit = cache[key] { return hit }

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

    /// Normalizes a MODL-style path and prepends the "meshes\\" root when the
    /// record omitted it. Rejects empty/escaping paths as not-found.
    private func meshKey(for path: String) throws -> String {
        guard let normalized = try? VirtualFileSystem.normalize(path) else {
            throw MeshLibraryError.fileNotFound(path: path)
        }
        return normalized.hasPrefix("meshes\\") ? normalized : "meshes\\" + normalized
    }
}
