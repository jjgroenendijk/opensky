// The render placements, particles, bounds, and summary of a scene.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
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

nonisolated extension CellSceneBuilder.CellSceneRenderParts {
    nonisolated private func makeParticlePlaybacks(
        instances: [ResolvedInstance]
    ) -> [(reference: UInt32, playbacks: [ParticlePlayback])] {
        var result: [(reference: UInt32, playbacks: [ParticlePlayback])] = []
        for instance in instances {
            do {
                try result.append((instance.formID, owner.meshes.particlePlaybacks(
                    path: instance.modelPath,
                    surface: instance.surface,
                    placementTransform: instance.transform,
                    formID: instance.formID,
                    emittance: instance.emittance
                )))
            } catch {
                let reason = String(describing: error)
                let source = instance.modelPath
                let message = "particle playback \(source) failed: \(reason)"
                CellSceneBuilder.logger.warning("\(message, privacy: .public)")
            }
        }
        return result
    }

    /// Every particle system of the cell; a node animation keeps its own reference's.
    nonisolated func particlePlaybacks(
        instances: [ResolvedInstance], nodes: inout [(
            mesh: CellNodeAnimation,
            playback: any RenderAnimation
        )]
    ) -> [ParticlePlayback] {
        let particlesByReference = makeParticlePlaybacks(instances: instances)
        let byReference = Dictionary(
            particlesByReference.map { ($0.reference, $0.playbacks) },
            uniquingKeysWith: +
        )
        for index in nodes.indices {
            nodes[index].mesh.particles = byReference[nodes[index].mesh.reference] ?? []
        }
        return particlesByReference.flatMap(\.playbacks)
    }

    nonisolated func renderPlacements(
        _ instances: [ResolvedInstance],
        simulated: Set<UInt32>
    ) -> [RenderPlacement] {
        instances.filter { !$0.model.meshes.isEmpty }.map { instance in
            var placement = RenderPlacement(
                model: instance.model,
                transform: instance.transform,
                bounds: owner.meshes.bounds(forPath: instance.modelPath, surface: instance.surface)?
                    .transformed(by: instance.transform),
                referenceFormID: simulated.contains(instance.formID) ? instance.formID : 0
            )
            placement.emittance = instance.emittance
            placement.treeMotion = instance.treeMotion
            return placement
        }
    }

    /// Nil when nothing drew.
    nonisolated func unionedBounds(
        placements: [RenderPlacement],
        geometry: CellGeometryBuild
    ) -> ModelBounds? {
        var bounds: ModelBounds?
        let worlds = placements.compactMap(\.bounds)
            + [geometry.terrain?.bounds, geometry.water?.item.bounds].compactMap(\.self)
        for world in worlds {
            bounds = bounds.map { $0.union(world) } ?? world
        }
        return bounds
    }

    nonisolated func drainTouchedAssets() -> CellAssets {
        CellAssets(
            meshKeys: owner.meshes.drainTouchedKeys()
                .union(owner.collisionModels?.drainTouchedKeys() ?? []),
            textureKeys: owner.textures.drainTouchedKeys()
        )
    }

    nonisolated func makeSummary(
        cell: (found: FoundCell, grid: (x: Int32, y: Int32)),
        instanceCount: Int,
        geometry: CellGeometryBuild,
        counts: BuildCounts
    ) -> CellLoadSummary {
        let (found, grid) = cell
        let actors = geometry.actors
        var summary = CellLoadSummary(
            cellName: found.cell.editorID ?? "cell \(FormID(found.formID).description)",
            gridX: grid.x,
            gridY: grid.y,
            totalRefCount: counts.totalRefs,
            drawnRefCount: instanceCount,
            unsupportedBaseSkipCount: counts.unsupportedBases,
            markerSkipCount: counts.markers,
            modelFailureSkipCount: counts.modelFailures,
            malformedRefSkipCount: counts.malformedRefs,
            modelCount: owner.meshes.loadedCount,
            textureCount: owner.textures.loadedCount,
            missingTextureCount: owner.textures.missingCount,
            terrainQuadrantCount: geometry.terrain?.quadrantCount ?? 0,
            terrainLayerCount: geometry.terrain?.layerCount ?? 0,
            terrainLayerSkipCount: geometry.terrain?.layerSkipCount ?? 0,
            grassPlacementCount: geometry.grass?.placements.count ?? 0,
            grassTypeCount: geometry.grass?.typeCount ?? 0,
            grassTypeSkipCount: geometry.grass?.typeSkipCount ?? 0,
            waterPlaneCount: geometry.water == nil ? 0 : 1,
            pointLightCount: geometry.pointLights.count
        )
        summary.runtimeDisabledSkipCount = counts.runtimeDisabled
        summary.runtimeDeletedSkipCount = counts.runtimeDeleted
        summary.disabledSkipCount = counts.baselineDisabled
        summary.unresolvedEnableParentCount = counts.unresolvedEnableParents
        summary.spawnedRefCount = counts.spawnedRefs
        summary.spawnedUnaddressableSkipCount = counts.unaddressableSpawns
        summary.actorCount = actors.counts.discovered
        summary.actorDrawnCount = actors.counts.rendered
        summary.actorDisabledSkipCount = actors.counts.disabledSkips
        summary.actorFailureCount = actors.counts.failures
        summary.actorFailureReasons = actors.counts.failureReasons
        summary.actorBuildDurationMS = actors.durationMS
        summary.actorAnimatedCount = actors.counts.animated
        summary.actorAnimationFailureCount = actors.counts.animationFailures
        summary.actorAnimationFailureReasons = actors.counts.animationFailureReasons
        summary.actorAppearanceSkipReasons = actors.counts.appearanceSkipReasons
        summary.skippedRecords = owner.skippedRecords
        CellSceneBuilder.logger.info("\(summary.summaryLine, privacy: .public)")
        return summary
    }
}
