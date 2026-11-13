// Morphs of a head built from its parts: each part's race, chargen, and expression TRI
// in one buffer per skinned mesh. The race and chargen weights are fixed; the
// expression weights move. See docs/engine/head-part-assembly.md.

import Foundation
import OpenSkyActorPresentation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyWorldInterface

nonisolated struct AssembledHeadMorphs {
    var bindings: [ObjectIdentifier: FaceMorphBuffer] = [:]
    var pairedPaths: [String] = []
    var misses: [FaceMorphAssociationMiss] = []
}

nonisolated extension CellSceneBuilder.CellMorphBuilder {
    /// Every head part mesh with a TRI of its own vertex count gets one buffer.
    func assembledHeadMorphs(
        assembly: ActorAssembly<ActorRenderAsset>, face: PlayerAppearanceOverride
    ) -> AssembledHeadMorphs {
        var result = AssembledHeadMorphs()
        guard
            let records = owner.actorVisualResolver?.headParts,
            let fileSystem = owner.fileSystem else { return result }
        var fixed = ChargenMorphs.weights(morphs: face.faceMorphs, parts: face.faceParts)
        if let race = raceMorphTarget(face.race) {
            fixed[race] = 1
        }
        for model in assembly.models {
            guard case let .headPart(part) = model.role, let record = records[part.formID.rawValue]
            else { continue }
            let files = record.morphPaths.compactMap { morph -> (String, TRIFile)? in
                let path = Self.meshKey(morph.path)
                guard case let .success(tri) = faceMorphFile(path, fileSystem: fileSystem) else {
                    result.misses.append(FaceMorphAssociationMiss(
                        headPart: part.formID, reason: "invalid TRI \(path)"
                    ))
                    return nil
                }
                return (path, tri)
            }
            for mesh in model.asset.model.meshes where mesh.isSkinned {
                let fitting = files.filter { $0.1.baseVertices.count == mesh.vertexCount }
                guard
                    !fitting.isEmpty,
                    let buffer = attempt({
                        try FaceMorphBuffer(
                            device: owner.meshes.device, tris: fitting.map(\.1), mesh: mesh,
                            fixedWeights: fixed
                        )
                    })
                else { continue }
                result.bindings[ObjectIdentifier(mesh)] = buffer
                result.pairedPaths += fitting.map(\.0)
            }
        }
        result.pairedPaths = Array(Set(result.pairedPaths)).sorted()
        return result
    }

    /// The race TRI target: the race's morph race (`NAM8`) by editor ID, else its own.
    func raceMorphTarget(_ race: FormID) -> String? {
        guard let races = owner.actorVisualResolver?.races, let record = races[race.rawValue] else {
            return nil
        }
        let morph = record.details.morphRace.flatMap { races[$0.rawValue] } ?? record
        return morph.editorID
    }

    static func meshKey(_ path: String) -> String {
        path.lowercased().hasPrefix("meshes\\") ? path : "meshes\\\(path)"
    }
}
