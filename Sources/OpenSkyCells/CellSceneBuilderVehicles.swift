// Carts in a cell build: a towed cart whose mesh has wheel nodes draws its own
// node-skinned copy, so its wheels can turn. See docs/engine/vehicles.md.

import OpenSkyActorPresentation
import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRenderCore
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
                let copy = posedCopy(of: instance, skeleton: rig.skeleton)
            else { continue }
            instances[index] = copy.instance
            let vehicle = CellAnimatedVehicle(reference: instance.formID, rig: rig, pose: copy.pose)
            result.append((vehicle, copy.playback))
        }
        return result
    }

    /// Swaps `instance` for its own node-skinned copy of its model, posed through a new buffer.
    func posedCopy(
        of instance: ResolvedInstance, skeleton: HKASkeleton
    ) -> PosedCopy? {
        guard let model = try? meshes.animatedObjectModel(
            path: instance.modelPath, bones: Set(skeleton.boneNames),
            reference: instance.formID, surface: instance.surface
        ) else { return nil }
        var posed = ResolvedInstance(
            sortKey: instance.sortKey, formID: instance.formID,
            modelPath: instance.modelPath, model: model, surface: instance.surface,
            transform: instance.transform, emittance: instance.emittance
        )
        posed.isSequenceDoor = instance.isSequenceDoor
        let pose = PlayerPoseBuffer()
        let playback = PlayerAnimationPlayback(skeleton: skeleton, pose: pose, models: [model])
        return PosedCopy(instance: posed, pose: pose, playback: playback)
    }

    /// The last steps of a cell build: hazards, the vehicles' moving collision, and
    /// the touched assets, which must be drained after everything else loaded.
    func finished(
        _ scene: CellScene, hazards: [CellHazard], collision: CellCollisionBuild
    ) -> CellScene {
        var scene = scene
        scene.hazards = hazards
        scene.vehicleCollision = collision.vehicles
        scene.doorCollision = collision.doors
        scene.assets = drainTouchedAssets()
        return scene
    }
}

/// A reference's own node-skinned copy, with the buffer its playback reads.
nonisolated struct PosedCopy {
    let instance: ResolvedInstance
    let pose: PlayerPoseBuffer
    let playback: any RenderAnimation
}
