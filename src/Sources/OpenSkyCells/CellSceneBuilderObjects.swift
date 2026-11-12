// Animated objects in a cell build: activators and doors whose mesh names a
// behaviour project. The build decodes the set and poses the object's own
// model through a buffer the main-actor coordinator fills.
// See docs/engine/object-animation.md.

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyObjectAnimation
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyWorldInterface

nonisolated extension CellObjectBuilder {
    /// Base types whose meshes vanilla animates with a behaviour graph.
    static let animatedObjectTypes: Set<FourCC> = ["ACTI", "DOOR", "FURN", "CONT", "MSTT"]

    /// The behaviour set of a base that can animate and whose mesh names one.
    func objectBehavior(recordType: FourCC, modelPath: String) -> BehaviorProjectAsset? {
        guard
            Self.animatedObjectTypes.contains(recordType),
            let fileSystem = owner.fileSystem,
            let project = owner.meshes.extraData.behaviorProjectPath(forPath: modelPath)
        else { return nil }
        if let known = owner.objectBehaviorAssets[project] {
            return known
        }
        var asset: BehaviorProjectAsset?
        do {
            asset = try BehaviorProjectAsset.load(fileSystem: fileSystem, projectPath: project)
        } catch {
            let reason = String(describing: error)
            CellSceneBuilder.logger.warning(
                """
                [WARNING] object behaviour \(project, privacy: .public) did not load: \
                \(reason, privacy: .public)
                """
            )
        }
        owner.objectBehaviorAssets[project] = .some(asset)
        return asset
    }

    /// The graph's bones merged with the billboards and lag bones of the mesh. Nil when
    /// the mesh has none, so the object poses on the graph's own skeleton.
    func objectPoseRig(modelPath: String, asset: BehaviorProjectAsset) -> EffectPoseRig? {
        guard
            let nodes = nodeControllerRig(modelPath: modelPath),
            let rig = EffectPoseRig(nodes: nodes, graph: asset.skeleton), rig.addsNodes
        else { return nil }
        return rig
    }

    /// A pose buffer and playback for each animated instance.
    func animatedObjects(
        _ instances: [ResolvedInstance]
    ) -> [(object: CellAnimatedObject, playback: any RenderAnimation)] {
        instances.compactMap { instance in
            guard let asset = instance.animated else { return nil }
            let nodes = objectPoseRig(modelPath: instance.modelPath, asset: asset)
            return Self.animatedObject(instance, asset: asset, nodes: nodes)
        }
    }

    /// The object and the playback that publishes its pose, through one shared buffer.
    static func animatedObject(
        _ instance: ResolvedInstance, asset: BehaviorProjectAsset, nodes: EffectPoseRig?
    ) -> (object: CellAnimatedObject, playback: any RenderAnimation) {
        let playback = SkinnedPosePlayback(
            skeleton: nodes?.skeleton ?? asset.skeleton, models: [instance.model]
        )
        let parts = instance.model.meshes.compactMap { mesh in
            mesh.skinning.map { TrapContactPart(skinning: $0, bounds: mesh.localBounds) }
        }
        let object = CellAnimatedObject(
            reference: instance.formID, asset: asset, pose: playback.pose,
            contactShape: TrapContactShape(boneNames: asset.skeleton.boneNames, parts: parts),
            nodes: nodes, placement: instance.transform
        )
        return (object, playback)
    }
}

nonisolated extension CellSceneBuilder {
    var objectBuilder: CellObjectBuilder {
        CellObjectBuilder(owner: self)
    }
}
