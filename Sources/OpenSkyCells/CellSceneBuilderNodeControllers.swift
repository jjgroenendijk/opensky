// Placed meshes with free-running node controllers in a cell build: a reference that no
// object graph or door sequence animates, whose mesh has an active controller on a named
// node, draws its own node-skinned copy.
// See docs/engine/object-animation.md#node-controllers.

import Foundation
import OpenSkyActorPresentation
import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyRenderCore
import OpenSkyRendering

nonisolated extension CellSceneBuilder {
    /// Block types that can move a node on its own clock. A mesh without one is not parsed.
    static let nodeControllerMarkers = [
        "NiTransformController", "BSLagBoneController"
    ].map { Data($0.utf8) }

    /// The rig of a mesh, read once per mesh. Nil for a mesh without a playing controller.
    /// A mesh that names a behaviour graph plays only its lag bones: its keyed controllers
    /// are a baked preview the graph replaces, such as the forge's 33-second smithing idle.
    func nodeControllerRig(modelPath: String) -> NodeControllerRig? {
        guard let fileSystem, let key = try? meshes.meshKey(for: modelPath) else { return nil }
        if let known = nodeControllerRigs[key] {
            return known
        }
        var rig: NodeControllerRig?
        if
            let data = try? fileSystem.contents(forPath: key),
            Self.nodeControllerMarkers.contains(where: { data.range(of: $0) != nil })
        {
            let lagOnly = meshes.behaviorProjectPath(forPath: modelPath) != nil
            rig = (try? NIFFile(data: data)).flatMap {
                try? NodeControllerRig(file: $0, lagOnly: lagOnly)
            }
        }
        nodeControllerRigs[key] = .some(rig)
        return rig
    }

    /// Gives each instance whose mesh plays node controllers its own posed model and a playback.
    func animatedNodes(
        _ instances: inout [ResolvedInstance]
    ) -> [(mesh: CellNodeAnimation, playback: any RenderAnimation)] {
        var result: [(mesh: CellNodeAnimation, playback: any RenderAnimation)] = []
        for (index, instance) in instances.enumerated()
            where instance.animated == nil && !instance.isSequenceDoor
        {
            guard
                let rig = nodeControllerRig(modelPath: instance.modelPath),
                let copy = posedCopy(of: instance, skeleton: rig.skeleton)
            else { continue }
            instances[index] = copy.instance
            let mesh = CellNodeAnimation(
                reference: instance.formID, rig: rig, pose: copy.pose, placement: instance.transform
            )
            result.append((mesh, copy.playback))
        }
        return result
    }
}
