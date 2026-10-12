// Carts in a cell build: a towed cart whose mesh has wheel nodes draws its own
// node-skinned copy, so its wheels can turn. See docs/engine/vehicles.md.

import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering

nonisolated extension CellSceneBuilder {
    /// Rigs the wheels of each follower in `instances`, replacing its model with its
    /// own copy. A model without wheel nodes stays as it is.
    func animatedVehicles(
        _ instances: inout [ResolvedInstance], followers: Set<UInt32>
    ) -> [(vehicle: CellAnimatedVehicle, playback: any RenderAnimation)] {
        guard !followers.isEmpty, let fileSystem else { return [] }
        var result: [(vehicle: CellAnimatedVehicle, playback: any RenderAnimation)] = []
        for (index, instance) in instances.enumerated()
            where followers.contains(instance.formID) && instance.animated == nil
        {
            guard
                let key = try? meshes.meshKey(for: instance.modelPath),
                let file = try? NIFFile(data: fileSystem.contents(forPath: key)),
                let rig = try? VehicleWheelRig(file: file),
                let model = try? meshes.animatedObjectModel(
                    path: instance.modelPath, bones: Set(rig.skeleton.boneNames),
                    reference: instance.formID, surface: instance.surface
                )
            else { continue }
            instances[index] = ResolvedInstance(
                sortKey: instance.sortKey, formID: instance.formID,
                modelPath: instance.modelPath, model: model, surface: instance.surface,
                transform: instance.transform
            )
            let pose = PlayerPoseBuffer()
            let playback = PlayerAnimationPlayback(
                skeleton: rig.skeleton,
                pose: pose,
                models: [model]
            )
            result.append((
                CellAnimatedVehicle(reference: instance.formID, rig: rig, pose: pose),
                playback
            ))
        }
        return result
    }
}
