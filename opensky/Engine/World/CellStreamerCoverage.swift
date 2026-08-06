// Distant-LOD request + coverage-transition handling for CellStreamer. Split
// out of CellStreamer.swift for the strict file-length limit; the behaviour is
// unchanged and documented in docs/engine/distant-lod.md (ring build) and
// docs/engine/cell-streaming.md (coverage transition).

import Foundation
import OSLog

extension CellStreamer {
    /// Requests the distant ring for the current center once the near grid has
    /// settled.
    func requestDistantLODIfNeeded() {
        // Cell + LOD work share one serial cache-confined queue. Let every
        // desired full cell reach resident/void/failed first so first-time
        // loading 100+ distant assets cannot starve the near grid.
        let resolved = core.resident.union(core.void).union(core.failed)
        guard resolved.isSuperset(of: grid.desiredCells) else { return }
        guard requestedLODCenter != grid.center else { return }
        if runner.enqueueDistantLOD(center: grid.center, hiddenCells: core.resident) {
            requestedLODCenter = grid.center
        }
    }

    func integrateDistantLOD(_ entries: [DistantLODBuildResult]) -> Bool {
        var changed = false
        for entry in entries {
            switch entry.result {
            case let .success(scene) where entry.center == grid.center:
                if coverageTransitionActive {
                    commitCoverageTransition(distantLOD: scene)
                } else {
                    let old = composition.setDistantLOD(scene)
                    if let old {
                        evictUnused(old.assets)
                    }
                }
                changed = true
            case let .success(scene):
                if let scene {
                    evictUnused(scene.assets)
                }
            case let .failure(error):
                let reason = String(describing: error)
                Self.logger.warning(
                    "[WARNING] distant LOD build failed: \(reason, privacy: .public)"
                )
            }
        }
        return changed
    }

    func discardStagedCells(outside desiredCells: Set<CellCoordinate>) {
        let stale = stagedCells.keys.filter { !desiredCells.contains($0) }
        for coordinate in stale {
            guard let scene = stagedCells.removeValue(forKey: coordinate) else { continue }
            evictUnused(scene.assets)
        }
    }

    func commitCoverageTransition(distantLOD: DistantLODScene?) {
        var departed = CellAssets()
        for coordinate in composition.coordinates where !core.resident.contains(coordinate) {
            guard let scene = composition.removeCell(at: coordinate) else { continue }
            emitCellDetached(scene)
            departed.meshKeys.formUnion(scene.assets.meshKeys)
            departed.textureKeys.formUnion(scene.assets.textureKeys)
        }
        // Deterministic promotion order so script instantiation is reproducible.
        let promoted = stagedCells.keys.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        for coordinate in promoted where core.resident.contains(coordinate) {
            guard let scene = stagedCells[coordinate] else { continue }
            let replaced = composition.setCell(scene, at: coordinate)
            // A staged cell that replaced a composed scene at the same
            // coordinate never left the world, so it is not a first attach.
            emitCellAttached(scene, firstIntegration: replaced == nil)
            if let replaced {
                departed.meshKeys.formUnion(replaced.assets.meshKeys)
                departed.textureKeys.formUnion(replaced.assets.textureKeys)
            }
        }
        stagedCells.removeAll(keepingCapacity: true)
        if let oldLOD = composition.setDistantLOD(distantLOD) {
            departed.meshKeys.formUnion(oldLOD.assets.meshKeys)
            departed.textureKeys.formUnion(oldLOD.assets.textureKeys)
        }
        coverageTransitionActive = false
        evictUnused(departed)
    }
}
