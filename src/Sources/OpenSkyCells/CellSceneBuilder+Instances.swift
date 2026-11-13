// The model and behaviour each placed reference draws with, sorted for instancing.

import Foundation
import Metal
import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyTerrain
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

nonisolated extension CellSceneBuilder.CellInstanceResolver {
    func enableParents(
        _ resolved: EffectiveReferences,
        pool: EnableParentPool
    ) -> ActorEnableParents {
        ActorEnableParents(
            references: owner.referenceBuilder.states.entriesByFormID(resolved.entries),
            pool: pool
        )
    }

    /// Decodes the meshes of the placed models in parallel before the serial build.
    nonisolated private func predecodeModels(
        of refs: [PlacedReference],
        skipping lights: [UInt32: LightRecord]
    ) {
        let statIndex = owner.modelIndex.statIndexBuildingIfNeeded()
        let modelBaseIndex = owner.modelIndex.modelBaseIndexBuildingIfNeeded()
        owner.meshes.predecode(paths: refs.lazy.compactMap { ref -> String? in
            guard lights[ref.base.rawValue] == nil else { return nil }
            let resolved = owner.modelIndex.resolveBase(
                formID: ref.base.rawValue, statIndex: statIndex, modelBaseIndex: modelBaseIndex
            )
            return resolved?.isEditorMarker == false ? resolved?.modelPath : nil
        })
    }

    /// Skips unknown bases, markers, and failed meshes. Sorted by
    /// (mesh path, FormID) so shared models sit together for instancing.
    nonisolated public func resolveInstances(
        refs: [PlacedReference],
        counts: inout BuildCounts
    ) -> [ResolvedInstance] {
        guard !refs.isEmpty else { return [] }
        let statIndex = owner.modelIndex.statIndexBuildingIfNeeded()
        let modelBaseIndex = owner.modelIndex.modelBaseIndexBuildingIfNeeded()
        let lightIndex = owner.interiorLighting.lightIndexBuildingIfNeeded()
        predecodeModels(of: refs, skipping: lightIndex)
        defer { owner.meshes.dropPredecoded() }
        let doors = owner.objectBuilder.animated.sequenceDoors(in: refs)
        var instances: [ResolvedInstance] = []
        for ref in refs where lightIndex[ref.base.rawValue] == nil {
            let id = ref.formID.description
            guard
                let resolved = owner.modelIndex.resolveBase(
                    formID: ref.base.rawValue, statIndex: statIndex, modelBaseIndex: modelBaseIndex
                )
            else {
                counts.unsupportedBases += 1
                let base = ref.base.description
                CellSceneBuilder.logger.info(
                    """
                    REFR \(id, privacy: .public): base \(base, privacy: .public) \
                    type not supported, skipped
                    """
                )
                continue
            }
            guard let modelPath = resolved.modelPath, !resolved.isEditorMarker else {
                counts.markers += 1
                let base = resolved.formID.description
                let type = resolved.recordType.description
                CellSceneBuilder.logger.info(
                    """
                    REFR \(id, privacy: .public): marker \(type, privacy: .public) \
                    \(base, privacy: .public), skipped
                    """
                )
                continue
            }
            let surface = owner.objectBuilder.surface(for: resolved)
            if
                var instance = loadInstance(
                    ref: ref, model: (modelPath, surface),
                    behavior: owner.objectBuilder.animated.objectBehavior(
                        recordType: resolved.recordType, modelPath: modelPath
                    ),
                    counts: &counts
                )
            {
                instance.isSequenceDoor = doors[ref.formID] != nil
                instance.sequenceDoorKind = doors[ref.formID]?.kind ?? .door
                instance.treeMotion = resolved.treeData.map(TreeMotion.init)
                instances.append(instance)
            }
        }
        return instances.sorted { ($0.sortKey, $0.formID) < ($1.sortKey, $1.formID) }
    }

    /// Nil when the mesh fails to load or holds only editor-marker geometry.
    nonisolated private func loadInstance(
        ref: PlacedReference,
        model: (path: String, surface: ModelSurfaceOverride),
        behavior: BehaviorProjectAsset?,
        counts: inout BuildCounts
    ) -> ResolvedInstance? {
        let (modelPath, surface) = model
        do {
            let animated = behavior.flatMap { asset in
                attempt {
                    try owner.meshes.animatedObjectModel(
                        path: modelPath,
                        bones: Set(owner.objectBuilder.animated.objectPoseRig(
                            modelPath: modelPath,
                            asset: asset
                        )?
                            .skeleton
                            .boneNames ?? asset.skeleton.boneNames),
                        reference: ref.formID.rawValue,
                        surface: surface
                    )
                }
            }
            return try ResolvedInstance(
                sortKey: attempt { try VirtualFileSystem.normalize(modelPath) } ?? modelPath,
                formID: ref.formID.rawValue,
                modelPath: modelPath,
                model: animated ?? owner.meshes.model(path: modelPath, surface: surface),
                surface: surface,
                transform: MatrixMath.placement(
                    position: ref.placement.position,
                    rotation: ref.placement.rotation,
                    scale: ref.scale
                ),
                animated: animated == nil ? nil : behavior,
                emittance: owner.interiorLighting.emittanceSource(of: ref)
            )
        } catch MeshLibraryError.editorMarkerOnly {
            counts.markers += 1
        } catch {
            counts.modelFailures += 1
            let id = ref.formID.description
            let reason = String(describing: error)
            CellSceneBuilder.logger.warning(
                """
                REFR \(id, privacy: .public): model \(modelPath, privacy: .public) \
                failed (\(reason, privacy: .public)), skipped
                """
            )
        }
        return nil
    }
}
