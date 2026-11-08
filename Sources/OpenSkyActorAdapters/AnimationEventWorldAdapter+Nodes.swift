// Where a named bone of an animation event's source is, for `SoundPlayAt`
// (docs/engine/animation-events.md).

import Foundation
import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyObjectAnimation
import OpenSkyPlayer
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension AnimationEventWorldAdapter {
    public func animationEventPosition(of source: ReferenceKey, node: String) -> SIMD3<Float>? {
        let world = source == .player
            ? playerBone(node)
            : actorBone(node, of: source) ?? objectNode(node, of: source)
        return world.map { SIMD3($0.columns.3.x, $0.columns.3.y, $0.columns.3.z) }
    }

    private func playerBone(_ name: String) -> float4x4? {
        guard
            let body = game.gameSession?.playerBody,
            let index = body.animation.skeleton.boneNames
                .firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
            let bones = try? SkeletonPoseMath.worldMatrices(
                skeleton: body.animation.skeleton, localPoses: body.animation.pose.bones
            ),
            bones.indices.contains(index)
        else { return nil }
        return body.transform * bones[index]
    }

    /// A node of an object's running behaviour graph, such as a trap's swinging blade.
    private func objectNode(_ name: String, of object: ReferenceKey) -> float4x4? {
        guard let formID = game.streamer?.referenceEntry(key: object)?.formID else { return nil }
        return game.objectBehaviors.worldBone(of: formID.rawValue, named: name)
    }

    private func actorBone(_ name: String, of actor: ReferenceKey) -> float4x4? {
        guard
            let streamer = game.streamer,
            let placed = streamer.referenceEntry(key: actor)?.placedActor,
            let pose = game.animatedPose(for: actor),
            let bone = pose.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })
        else { return nil }
        let moved = streamer.npcTransform(for: actor)
        let actorToWorld = MatrixMath.placement(
            position: moved?.position ?? placed.placement.position,
            rotation: moved?.rotation ?? placed.placement.rotation,
            scale: moved?.scale ?? placed.scale
        )
        return actorToWorld * bone.value
    }
}
