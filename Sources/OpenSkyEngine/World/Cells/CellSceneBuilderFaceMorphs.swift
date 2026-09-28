// FaceGen expression TRI association for assembled actors. HDPT EDID matches
// the baked FaceGen BSDynamicTriShape name; NAM0=1 supplies its TRI path.
// Vertex count is the final guard before an actor-local buffer is attached.

import Foundation

nonisolated private struct FaceMorphAssociationState {
    var bindings: [ObjectIdentifier: FaceMorphBuffer] = [:]
    var pairedPaths: [String] = []
    var misses: [FaceMorphAssociationMiss] = []
}

nonisolated extension CellSceneBuilder {
    func makeFaceMorphPlayback(
        assembly: ActorAssembly<ActorRenderAsset>
    ) -> FaceMorphPlayback? {
        guard let resolver = actorVisualResolver, let fileSystem else { return nil }
        let parts = resolver.expressionHeadParts(for: assembly.visual.appearance)
        let faceModels = assembly.models.filter {
            if case .faceGenHead = $0.role {
                return true
            }
            return false
        }
        guard !faceModels.isEmpty else { return nil }
        var state = FaceMorphAssociationState()
        for part in parts {
            associate(
                part,
                faceModels: faceModels,
                fileSystem: fileSystem,
                state: &state
            )
        }
        let faceBounds = faceModels.compactMap {
            $0.asset.bounds?.transformed(by: assembly.transform)
        }.reduce(nil) { result, bounds in
            result.map { $0.union(bounds) } ?? bounds
        }
        return FaceMorphPlayback(
            actor: assembly.actor,
            bindings: state.bindings,
            pairedPaths: state.pairedPaths.sorted(),
            misses: state.misses,
            worldBounds: faceBounds
        )
    }

    private func associate(
        _ part: HeadPart,
        faceModels: [AssembledActorModel<ActorRenderAsset>],
        fileSystem: VirtualFileSystem,
        state: inout FaceMorphAssociationState
    ) {
        guard let name = part.editorID, let path = part.expressionMorphPath else {
            state.misses.append(FaceMorphAssociationMiss(
                headPart: part.formID, reason: "missing EDID or expression NAM1"
            ))
            return
        }
        let resourcePath = path.lowercased().hasPrefix("meshes\\")
            ? path : "meshes\\\(path)"
        let meshes = faceModels.flatMap(\.asset.model.meshes).filter {
            $0.name?.caseInsensitiveCompare(name) == .orderedSame
        }
        guard !meshes.isEmpty else {
            state.misses.append(FaceMorphAssociationMiss(
                headPart: part.formID, reason: "no FaceGen shape named \(name)"
            ))
            return
        }
        let tri: TRIFile
        do {
            tri = try TRIFile(data: fileSystem.contents(forPath: resourcePath))
        } catch {
            state.misses.append(FaceMorphAssociationMiss(
                headPart: part.formID,
                reason: "invalid expression TRI \(resourcePath): \(error)"
            ))
            return
        }
        var paired = false
        for mesh in meshes where mesh.isSkinned {
            let key = ObjectIdentifier(mesh)
            guard state.bindings[key] == nil else { continue }
            do {
                state.bindings[key] = try FaceMorphBuffer(
                    device: self.meshes.device,
                    tri: tri,
                    mesh: mesh
                )
                paired = true
            } catch {
                state.misses.append(FaceMorphAssociationMiss(
                    headPart: part.formID,
                    reason: "vertex count mismatch for \(name): "
                        + "TRI \(tri.baseVertices.count), mesh \(mesh.vertexCount)"
                ))
            }
        }
        if paired {
            state.pairedPaths.append(resourcePath)
        } else if !meshes.contains(where: \.isSkinned) {
            state.misses.append(FaceMorphAssociationMiss(
                headPart: part.formID, reason: "FaceGen shape \(name) is not skinned"
            ))
        }
    }
}
