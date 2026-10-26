// An armour addon's graph moves the bones of its actor that share its bone names, such as
// a worn tail's bones. See docs/engine/effect-graphs.md#armour-addon-poses.

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM

/// The sub-graph bones that move actor bones: a bone matches when its name and its
/// parent's name both match, so the local pose means the same in both rigs.
struct SubGraphBoneMap {
    let actorBoneCount: Int
    let pairs: [(graph: Int, actor: Int)]

    init(graph: BehaviorSkeleton, actor: BehaviorSkeleton) {
        actorBoneCount = actor.boneNames.count
        let actorIndex = Dictionary(
            actor.boneNames.enumerated().map { ($1.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        pairs = graph.boneNames.indices.compactMap { index in
            guard
                let parent = Self.parentName(of: index, in: graph),
                let match = actorIndex[graph.boneNames[index].lowercased()],
                Self.parentName(of: match, in: actor) == parent
            else { return nil }
            return (index, match)
        }
    }

    /// Nil for a root, which has no frame to share.
    private static func parentName(of index: Int, in skeleton: BehaviorSkeleton) -> String? {
        guard
            skeleton.parentIndices.indices.contains(index),
            skeleton.boneNames.indices.contains(skeleton.parentIndices[index])
        else { return nil }
        return skeleton.boneNames[skeleton.parentIndices[index]].lowercased()
    }
}

extension EffectGraphCoordinator {
    /// Hands each actor the bones its armour addon graphs posed; an actor whose addon
    /// graphs ended gets its own pose back.
    func poseArmorAddons() {
        var overlays: [ReferenceKey: (pose: PlayerPoseBuffer, bones: [Int: HKABonePose])] = [:]
        for id in running.keys.sorted() {
            guard
                case let .armorAddon(actor, _) = id, let entry = running[id],
                !entry.bones.isEmpty, let rig = entry.actorRig
            else { continue }
            let map = boneMap(of: entry, on: rig)
            var overlay = overlays[actor]?.bones ?? [:]
            for (graph, actorBone) in map.pairs where entry.bones.indices.contains(graph) {
                overlay[actorBone] = entry.bones[graph]
            }
            overlays[actor] = (rig.pose, overlay)
        }
        for (actor, pose) in overlaidPoses where overlays[actor]?.pose !== pose {
            pose.setOverlay([:])
        }
        for (pose, bones) in overlays.values {
            pose.setOverlay(bones)
        }
        overlaidPoses = overlays.mapValues(\.pose)
    }

    private func boneMap(of entry: Running, on rig: SubGraphActorRig) -> SubGraphBoneMap {
        if let map = entry.boneMap, map.actorBoneCount == rig.skeleton.boneNames.count {
            return map
        }
        let map = SubGraphBoneMap(graph: entry.instance.skeleton, actor: rig.skeleton)
        entry.boneMap = map
        return map
    }
}
