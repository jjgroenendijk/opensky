// Sequence doors in a cell build: a door that is not a load door, runs no behaviour
// graph, and whose mesh has `Open` and `Close` sequences draws its own node-skinned
// copy. See docs/engine/object-animation.md#sequence-doors.

import OpenSkyActorPresentation
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyRendering

nonisolated extension CellSceneBuilder {
    struct SequenceDoorBase {
        let ref: PlacedReference
        let modelPath: String
        let rig: SequenceDoorRig
    }

    /// The references in `refs` that are sequence doors, with their rigs.
    func sequenceDoors(in refs: [PlacedReference]) -> [FormID: SequenceDoorBase] {
        let bases = modelBaseIndexBuildingIfNeeded()
        var doors: [FormID: SequenceDoorBase] = [:]
        for ref in refs where ref.teleportDestination == nil {
            guard
                let base = bases[ref.base.rawValue], base.recordType == "DOOR",
                let path = base.modelPath,
                meshes.behaviorProjectPath(forPath: path) == nil,
                let rig = sequenceDoorRig(modelPath: path)
            else { continue }
            doors[ref.formID] = SequenceDoorBase(ref: ref, modelPath: path, rig: rig)
        }
        return doors
    }

    /// The rig of a door mesh, read once per mesh. Nil for a mesh without both sequences.
    func sequenceDoorRig(modelPath: String) -> SequenceDoorRig? {
        guard let fileSystem, let key = try? meshes.meshKey(for: modelPath) else { return nil }
        if let known = sequenceDoorRigs[key] {
            return known
        }
        let rig = (try? NIFFile(data: fileSystem.contents(forPath: key)))
            .flatMap { try? SequenceDoorRig(file: $0) }
        sequenceDoorRigs[key] = .some(rig)
        return rig
    }

    /// Gives each sequence door in `instances` its own posed model and a playback.
    func animatedDoors(
        _ instances: inout [ResolvedInstance]
    ) -> [(door: CellSequenceDoor, playback: any RenderAnimation)] {
        var result: [(door: CellSequenceDoor, playback: any RenderAnimation)] = []
        for (index, instance) in instances.enumerated() where instance.isSequenceDoor {
            guard
                let rig = sequenceDoorRig(modelPath: instance.modelPath),
                let model = try? meshes.animatedObjectModel(
                    path: instance.modelPath, bones: Set(rig.skeleton.boneNames),
                    reference: instance.formID, surface: instance.surface
                )
            else { continue }
            var posed = ResolvedInstance(
                sortKey: instance.sortKey, formID: instance.formID,
                modelPath: instance.modelPath, model: model, surface: instance.surface,
                transform: instance.transform, emittance: instance.emittance
            )
            posed.isSequenceDoor = true
            instances[index] = posed
            let pose = PlayerPoseBuffer()
            let playback = PlayerAnimationPlayback(
                skeleton: rig.skeleton, pose: pose, models: [model]
            )
            let door = CellSequenceDoor(
                reference: instance.formID, modelPath: instance.modelPath, rig: rig, pose: pose
            )
            result.append((door, playback))
        }
        return result
    }
}
