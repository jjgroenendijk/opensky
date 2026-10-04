// An idle prop drawn on one live actor, outside the actor's cell build. Starting
// or ending an idle then changes only this actor's draw list, not its cell.
// See docs/engine/idle-runtime.md.

import OpenSkyFormatsCore
import OpenSkyRendering
import simd

/// Poses a prop's skinned meshes with the pose of the actor it rides, so the
/// prop follows the bone that `MeshLibrary.loadActorAttachment` bound it to.
nonisolated public final class ActorPropPlayback: SharedPoseAnimation {
    public let actor: ActorAnimationPlayback
    private let meshes: [RenderMesh]

    public init(actor: ActorAnimationPlayback, model: RenderModel) {
        self.actor = actor
        meshes = model.meshes.filter(\.isSkinned)
    }

    @discardableResult
    public func update(at time: Float) -> Int {
        guard let pose = actor.skeletonPose(at: time) else { return 0 }
        var updatedMeshes = Set<ObjectIdentifier>()
        return apply(pose, updating: &updatedMeshes)
    }

    public var actorFormID: UInt32 {
        actor.actorFormID
    }

    public var sharedClipKey: ObjectIdentifier {
        actor.sharedClipKey
    }

    public func sampleSharedPose(at time: Float) -> SkeletonPose? {
        actor.sampleSharedPose(at: time)
    }

    public func apply(
        _ pose: SkeletonPose,
        updating updatedMeshes: inout Set<ObjectIdentifier>
    ) -> Int {
        meshes.applySkinningPose(pose, updating: &updatedMeshes)
    }

    @discardableResult
    public func resetToBindPose() -> Int {
        meshes.resetSkinningPoses()
    }
}

nonisolated extension [RenderMesh] {
    /// Poses each skinned mesh once per frame; a mesh in `updatedMeshes` is skipped.
    func applySkinningPose(
        _ pose: SkeletonPose,
        updating updatedMeshes: inout Set<ObjectIdentifier>
    ) -> Int {
        reduce(0) { count, mesh in
            guard updatedMeshes.insert(ObjectIdentifier(mesh)).inserted else { return count }
            return count + mesh.updateSkinningPose(pose)
        }
    }

    func resetSkinningPoses() -> Int {
        reduce(0) { $0 + $1.resetSkinningPose() }
    }
}

nonisolated extension RenderScene {
    /// `model` drawn where `actor`'s build drew the actor, and posed with it.
    public static func actorProp(_ model: RenderModel, on actor: ActorAnimationPlayback) -> Self {
        RenderScene(
            instances: [RenderPlacement(
                model: model,
                transform: actor.transform,
                layer: .actors,
                owner: actor.actorFormID
            )],
            animations: [ActorPropPlayback(actor: actor, model: model)]
        )
    }
}
