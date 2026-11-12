// The extra data a mesh carries for the cell build, read once per path.

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyFormatsCore
public import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRenderResources
import simd

/// What a mesh carries besides its shapes: the behaviour project it names, its
/// furniture markers, its add-on nodes, and the bone a rigid part rides.
nonisolated public final class MeshExtraData {
    let fileSystem: any GameFileSource
    /// The behaviour project each object mesh names; nil inside means none.
    var behaviorProjects: [String: String?] = [:]
    /// The furniture markers of each furniture mesh read so far.
    var furnitureMarkerSets: [String: [NIFFurnitureMarker]] = [:]
    var addOnNodeSets: [String: [NIFAddOnNode]] = [:]

    init(fileSystem: any GameFileSource) {
        self.fileSystem = fileSystem
    }

    static func meshKey(for path: String) throws -> String {
        guard let normalized = attempt({ try VirtualFileSystem.normalize(path) }) else {
            throw MeshLibraryError.fileNotFound(path: path)
        }
        return normalized.hasPrefix("meshes\\") ? normalized : "meshes\\" + normalized
    }

    func meshKey(for path: String) throws -> String {
        try Self.meshKey(for: path)
    }

    /// The behaviour project an object mesh names, or nil. Each path is read once.
    public func behaviorProjectPath(forPath path: String) -> String? {
        guard let pathKey = attempt({ try meshKey(for: path) }) else { return nil }
        if let known = behaviorProjects[pathKey] {
            return known
        }
        let project = attempt { try fileSystem.contents(forPath: pathKey) }
            .flatMap { element in attempt { try NIFFile(data: element) } }
            .flatMap(NIFBehaviorGraphExtraData.projectPath(in:))
        behaviorProjects[pathKey] = .some(project)
        return project
    }

    /// The furniture markers a mesh holds. Each path is read once.
    public func furnitureMarkers(forPath path: String) -> [NIFFurnitureMarker] {
        guard let pathKey = attempt({ try meshKey(for: path) }) else { return [] }
        if let known = furnitureMarkerSets[pathKey] {
            return known
        }
        let markers = attempt { try fileSystem.contents(forPath: pathKey) }
            .flatMap { element in attempt { try NIFFile(data: element) } }
            .map(NIFFurnitureMarker.markers(in:)) ?? []
        furnitureMarkerSets[pathKey] = markers
        return markers
    }

    /// The add-on nodes a mesh holds. Each path is read once.
    public func addOnNodes(forPath path: String) -> [NIFAddOnNode] {
        guard let pathKey = attempt({ try meshKey(for: path) }) else { return [] }
        if let known = addOnNodeSets[pathKey] {
            return known
        }
        let nodes = attempt { try fileSystem.contents(forPath: pathKey) }
            .flatMap { element in attempt { try NIFFile(data: element).addOnNodes() } } ?? []
        addOnNodeSets[pathKey] = nodes
        return nodes
    }

    /// The bone a rigid mesh names to ride, or nil for a skinned mesh.
    static func parentBone(of file: NIFFile?) -> String? {
        file.flatMap { file in
            file.blocks.contains { $0.typeName.hasSuffix("SkinInstance") }
                ? nil : NIFStringExtraData.parentBone(in: file)
        }
    }

    static func riding(
        _ model: Model, bone: String, skeleton: ActorSkeletonAsset?
    ) -> Model {
        RigidAttachment.skinned(
            model,
            to: bone,
            restTransform: skeleton?.skeleton.transform(forBoneNamed: bone)
                ?? matrix_identity_float4x4,
            actorHasBone: { skeleton?.skeleton.transform(forBoneNamed: $0) != nil }
        )
    }
}
