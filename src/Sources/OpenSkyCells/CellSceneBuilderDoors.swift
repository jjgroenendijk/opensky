// Sequence doors in a cell build: a door or container that runs no behaviour graph and
// whose mesh has `Open` and `Close` sequences draws its own node-skinned copy.
// See docs/engine/object-animation.md#sequence-doors.

import OpenSkyActorPresentation
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyRenderCore
import OpenSkyRendering

nonisolated extension CellObjectBuilder {
    struct SequenceDoorBase {
        let ref: PlacedReference
        let modelPath: String
        let rig: SequenceDoorRig
        let kind: CellSequenceDoor.Kind
    }

    /// Base types whose meshes open and close with `Open` and `Close` sequences.
    static let sequenceDoorTypes: Set<FourCC> = ["DOOR", "CONT"]

    /// The references in `refs` that are sequence doors, with their rigs.
    func sequenceDoors(in refs: [PlacedReference]) -> [FormID: SequenceDoorBase] {
        let bases = owner.recordIndex.modelBaseIndexBuildingIfNeeded()
        var doors: [FormID: SequenceDoorBase] = [:]
        for ref in refs {
            guard
                let base = bases[ref.base.rawValue],
                Self.sequenceDoorTypes.contains(base.recordType),
                let path = base.modelPath,
                owner.meshes.behaviorProjectPath(forPath: path) == nil,
                let rig = sequenceDoorRig(modelPath: path)
            else { continue }
            let kind: CellSequenceDoor.Kind = base.recordType == "CONT" ? .containerLid
                : ref.teleportDestination == nil ? .door : .loadDoor
            doors[ref.formID] = SequenceDoorBase(ref: ref, modelPath: path, rig: rig, kind: kind)
        }
        return doors
    }

    /// The rig of a door mesh, read once per mesh. Nil for a mesh without both sequences.
    func sequenceDoorRig(modelPath: String) -> SequenceDoorRig? {
        guard
            let fileSystem = owner.fileSystem,
            let key = attempt({ try owner.meshes.meshKey(for: modelPath) }) else { return nil }
        if let known = owner.sequenceDoorRigs[key] {
            return known
        }
        let rig = attempt { try NIFFile(data: fileSystem.contents(forPath: key)) }
            .flatMap { element in attempt { try SequenceDoorRig(file: element) } }
        owner.sequenceDoorRigs[key] = .some(rig)
        return rig
    }

    /// Gives each sequence door in `instances` its own posed model and a playback.
    func animatedDoors(
        _ instances: inout [ResolvedInstance]
    ) -> [(door: CellSequenceDoor, playback: any RenderAnimation)] {
        var result: [(door: CellSequenceDoor, playback: any RenderAnimation)] = []
        for (index, instance) in instances.enumerated() where instance.isSequenceDoor {
            guard let rig = sequenceDoorRig(modelPath: instance.modelPath) else { continue }
            let nodes = nodeControllerRig(modelPath: instance.modelPath)
                .flatMap { NodeControllerRig(animation: $0.animation, lagOnly: true) }
                .flatMap { EffectPoseRig(nodes: $0, graph: rig.skeleton) }
                .flatMap { $0.addsNodes ? $0 : nil }
            guard let copy = posedCopy(of: instance, skeleton: nodes?.skeleton ?? rig.skeleton)
            else { continue }
            instances[index] = copy.instance
            let door = CellSequenceDoor(
                reference: instance.formID, rig: rig, pose: copy.pose,
                nodes: nodes, placement: instance.transform, kind: instance.sequenceDoorKind
            )
            result.append((door, copy.playback))
        }
        return result
    }
}
