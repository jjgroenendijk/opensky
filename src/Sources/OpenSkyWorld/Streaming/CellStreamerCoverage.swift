// Distant-LOD request + coverage-transition handling for CellStreamer. Split
// out of CellStreamer.swift for the strict file-length limit; the behaviour is
// unchanged and documented in docs/engine/distant-lod.md (ring build) and
// docs/engine/cell-streaming.md (coverage transition).

import Foundation
public import OpenSkyCells
public import OpenSkyFormatsCore
public import OpenSkyTerrain

extension CellStreamer.CoverageSteps {
    /// Drops unloaded cells and schedules eviction of assets no resident cell needs. Only
    /// the departed keys minus the resident union go, so in-flight builds keep theirs.
    /// Eviction runs on the build queue (docs/engine/cell-streaming.md).
    public func unload(_ coordinates: [CellCoordinate]) {
        var departed = CellAssets()
        for coordinate in coordinates {
            guard let removed = streamer.composition.removeCell(at: coordinate) else { continue }
            streamer.triggers.emitCellDetached(removed)
            departed.meshKeys.formUnion(removed.assets.meshKeys)
            departed.textureKeys.formUnion(removed.assets.textureKeys)
        }
        evictUnused(departed)
    }

    /// Every desired near cell is loaded, empty, or failed.
    public var nearGridResolved: Bool {
        streamer.core.resident.union(streamer.core.void).union(streamer.core.failed)
            .isSuperset(of: streamer.grid.desiredCells)
    }

    /// The start area can show without holes: an interior is in, or the near grid
    /// resolved and the distant ring of its center was integrated or failed. A quick
    /// first ring also waits for its large references, so they never swap in view.
    public var startAreaReady: Bool {
        streamer.interiorScene != nil
            ||
            (nearGridResolved && streamer.settledLODCenter == streamer.grid
                .center && !awaitsLargeReferences)
    }

    private var awaitsLargeReferences: Bool {
        streamer.composition.distantLOD?.largeReferencesPending == true
            && streamer.largeReferenceSettledCenter != streamer.grid.center
    }

    /// Requests the distant ring for the current center once the near grid has
    /// settled.
    public func requestDistantLODIfNeeded() {
        // The first ring may start beside the near grid, so the start area does
        // not wait for both builds in a row. It hides the whole desired grid.
        if
            streamer.requestedLODCenter == nil, streamer.settledLODCenter == nil,
            streamer.runner.startDistantLODPrebuild(
                center: streamer.grid.center,
                hiddenCells: streamer.grid.desiredCells
            )
        {
            streamer.requestedLODCenter = streamer.grid.center
            return
        }
        // Cell + LOD work share one serial cache-confined queue. Let every
        // desired full cell reach resident/void/failed first so first-time
        // loading 100+ distant assets cannot starve the near grid.
        // The quick first ring has no large references, so it is built once more.
        let addsLargeReferences = streamer.composition.distantLOD?.largeReferencesPending == true
            && streamer.largeReferenceRequestCenter != streamer.grid.center
        guard
            nearGridResolved,
            streamer.requestedLODCenter != streamer.grid.center || addsLargeReferences
        else { return }
        if streamer.runner.enqueueDistantLOD(
            center: streamer.grid.center, hiddenCells: streamer.core.resident,
            state: streamer.stateSource()
        ) {
            streamer.requestedLODCenter = streamer.grid.center
            streamer.largeReferenceRequestCenter = addsLargeReferences ? streamer.grid.center : nil
        }
    }

    public func integrateDistantLOD(_ entries: [DistantLODBuildResult]) -> Bool {
        var changed = false
        for entry in entries {
            if entry.center == streamer.grid.center {
                streamer.settledLODCenter = entry.center
            }
            if entry.center == streamer.largeReferenceRequestCenter {
                streamer.largeReferenceSettledCenter = entry.center
            }
            switch entry.result {
            case let .success(scene) where entry.center == streamer.grid.center:
                if streamer.coverageTransitionActive {
                    commitCoverageTransition(distantLOD: scene)
                } else {
                    let old = streamer.composition.setDistantLOD(scene)
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
                CellStreamer.logger.warning(
                    "[WARNING] distant LOD build failed: \(reason, privacy: .public)"
                )
            }
        }
        return changed
    }

    public func discardStagedCells(outside desiredCells: Set<CellCoordinate>) {
        let stale = streamer.stagedCells.keys.filter { !desiredCells.contains($0) }
        for coordinate in stale {
            guard let scene = streamer.stagedCells.removeValue(forKey: coordinate) else { continue }
            evictUnused(scene.assets)
        }
    }

    public func commitCoverageTransition(distantLOD: DistantLODScene?) {
        var departed = CellAssets()
        for coordinate in streamer.composition.coordinates
            where !streamer.core.resident.contains(coordinate)
        {
            guard let scene = streamer.composition.removeCell(at: coordinate) else { continue }
            streamer.triggers.emitCellDetached(scene)
            departed.meshKeys.formUnion(scene.assets.meshKeys)
            departed.textureKeys.formUnion(scene.assets.textureKeys)
        }
        // Deterministic promotion order so script instantiation is reproducible.
        let promoted = streamer.stagedCells.keys.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        for coordinate in promoted where streamer.core.resident.contains(coordinate) {
            guard let scene = streamer.stagedCells[coordinate] else { continue }
            let replaced = streamer.composition.setCell(scene, at: coordinate)
            // A staged cell that replaced a composed scene at the same
            // coordinate never left the world, so it is not a first attach.
            streamer.triggers.emitCellAttached(scene, firstIntegration: replaced == nil)
            if let replaced {
                departed.meshKeys.formUnion(replaced.assets.meshKeys)
                departed.textureKeys.formUnion(replaced.assets.textureKeys)
            }
        }
        streamer.stagedCells.removeAll(keepingCapacity: true)
        if let oldLOD = streamer.composition.setDistantLOD(distantLOD) {
            departed.meshKeys.formUnion(oldLOD.assets.meshKeys)
            departed.textureKeys.formUnion(oldLOD.assets.textureKeys)
        }
        streamer.coverageTransitionActive = false
        evictUnused(departed)
    }
}

extension CellStreamer.CoverageSteps {
    /// Drops `candidates` keys nothing resident needs. An interior scene and staged cells
    /// count as resident, because they are drawing outside the composition.
    public func evictUnused(_ candidates: CellAssets) {
        var candidates = candidates
        let departedProps = streamer.props.takeDepartedActorProps()
        candidates.meshKeys.formUnion(departedProps.meshKeys)
        candidates.textureKeys.formUnion(departedProps.textureKeys)
        var resident = streamer.composition.residentAssets()
        let props = streamer.props.actorPropAssets
        resident.meshKeys.formUnion(props.meshKeys)
        resident.textureKeys.formUnion(props.textureKeys)
        if let interiorScene = streamer.interiorScene {
            resident.meshKeys.formUnion(interiorScene.assets.meshKeys)
            resident.textureKeys.formUnion(interiorScene.assets.textureKeys)
        }
        for scene in streamer.stagedCells.values {
            resident.meshKeys.formUnion(scene.assets.meshKeys)
            resident.textureKeys.formUnion(scene.assets.textureKeys)
        }
        streamer.runner.enqueueEviction(
            droppingMeshKeys: candidates.meshKeys.subtracting(resident.meshKeys),
            droppingTextureKeys: candidates.textureKeys.subtracting(resident.textureKeys)
        )
    }
}
