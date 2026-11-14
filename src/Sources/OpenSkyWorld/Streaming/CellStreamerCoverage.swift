// Distant-LOD requests and the coverage swap of CellStreamer: docs/engine/distant-lod.md
// (ring build) and docs/engine/cell-streaming.md (distant LOD and coverage).

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
        var removedScenes: [CellScene] = []
        streamer.composition.batch { composition in
            removedScenes = coordinates.compactMap { composition.removeCell(at: $0) }
        }
        for removed in removedScenes {
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
    /// resolved and is drawn, and the distant ring of its center was integrated or
    /// failed. A quick first ring also waits for its large references, so they never
    /// swap in view.
    public var startAreaReady: Bool {
        streamer.interiorScene != nil
            || (
                nearGridResolved && streamer.stagedCells.isEmpty
                    && streamer.settledLODCenter == streamer.grid.center
                    && !awaitsLargeReferences
            )
    }

    /// A cell or a ring change waits off screen for the next ring.
    var isCoverageTransitionActive: Bool {
        guard streamer.liveLODHiddenCells != nil else { return false }
        return !streamer.stagedCells.isEmpty
            || !streamer.composition.coordinates.isSubset(of: streamer.grid.desiredCells)
    }

    /// The ring on screen, or the ring being built, leaves `coordinate` out, so the full
    /// cell there must keep drawing.
    /// Before the first ring draws, no LOD stands in for a cell, so nothing pins it.
    func isHiddenByAnyRing(_ coordinate: CellCoordinate) -> Bool {
        guard let live = streamer.liveLODHiddenCells else { return false }
        return live.contains(coordinate)
            || streamer.lodRequestHiddenCells?.contains(coordinate) == true
    }

    /// A built cell can draw at once when no ring draws LOD at its place: neither the
    /// ring on screen nor the one being built.
    func goesLiveAtOnce(_ coordinate: CellCoordinate) -> Bool {
        let live = streamer.liveLODHiddenCells?.contains(coordinate) ?? true
        let next = streamer.lodRequestHiddenCells?.contains(coordinate) ?? true
        return live && next
    }

    private var awaitsLargeReferences: Bool {
        streamer.composition.distantLOD?.largeReferencesPending == true
            && streamer.largeReferenceSettledCenter != streamer.grid.center
    }

    /// The cells the next ring leaves out: every drawn or waiting cell the grid wants.
    var wantedHiddenCells: Set<CellCoordinate> {
        streamer.composition.coordinates.intersection(streamer.grid.desiredCells)
            .union(streamer.stagedCells.keys)
    }

    /// Requests the distant ring that matches the cells the grid wants.
    public func requestDistantLODIfNeeded() {
        guard streamer.lodRequestHiddenCells == nil else { return }
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
            streamer.lodRequestHiddenCells = streamer.grid.desiredCells
            return
        }
        // The quick first ring has no large references, so it is built once more.
        let addsLargeReferences = streamer.composition.distantLOD?.largeReferencesPending == true
            && streamer.largeReferenceRequestCenter != streamer.grid.center
        guard needsRing(addsLargeReferences: addsLargeReferences) else { return }
        let hidden = wantedHiddenCells
        if streamer.runner.enqueueDistantLOD(
            center: streamer.grid.center, hiddenCells: hidden, state: streamer.stateSource()
        ) {
            streamer.requestedLODCenter = streamer.grid.center
            streamer.lodRequestHiddenCells = hidden
            streamer.lodRebuildWanted = false
            streamer.largeReferenceRequestCenter = addsLargeReferences ? streamer.grid.center : nil
        }
    }

    /// Cell and LOD builds share one serial queue. The first ring waits for the whole
    /// near grid, so its many first-load assets cannot starve the near cells. A later
    /// ring waits until no cell build is queued, unless a waiting cell is next to the
    /// player: that cell must not wait behind the rest of the grid.
    private func needsRing(addsLargeReferences: Bool) -> Bool {
        guard let liveHidden = streamer.liveLODHiddenCells else {
            return streamer.composition.distantLOD == nil && nearGridResolved
                && streamer.requestedLODCenter != streamer.grid.center
        }
        if streamer.lodRebuildWanted {
            return true
        }
        // The large references of the quick first ring come once the whole near grid is
        // in, so that ring leaves out every cell the start area draws.
        if addsLargeReferences {
            return nearGridResolved
        }
        let changed = wantedHiddenCells != liveHidden
            || streamer.liveLODCenter != streamer.grid.center
        guard changed else { return false }
        // A finished build not yet on screen is cell work too.
        let cellsIdle = streamer.requests.isEmpty && streamer.activeBuild == nil
            && streamer.pending.isEmpty
        return cellsIdle || waitingCellIsNextToThePlayer
    }

    private var waitingCellIsNextToThePlayer: Bool {
        let center = streamer.grid.center
        return streamer.stagedCells.keys.contains { cell in
            abs(Int64(cell.x) - Int64(center.x)) <= 1 && abs(Int64(cell.y) - Int64(center.y)) <= 1
        }
    }

    /// Swaps in each finished ring, whatever center it was built for: it still covers
    /// exactly the cells it leaves out, so a player that keeps moving still gets cells.
    public func integrateDistantLOD(_ entries: [DistantLODBuildResult]) -> Bool {
        var changed = false
        for entry in entries {
            streamer.lodRequestHiddenCells = nil
            if entry.center == streamer.grid.center {
                streamer.settledLODCenter = entry.center
            }
            if entry.center == streamer.largeReferenceRequestCenter {
                streamer.largeReferenceSettledCenter = entry.center
            }
            switch entry.result {
            case let .success(scene?):
                commitRing(scene, center: entry.center, hiddenCells: entry.hiddenCells)
            case .success(nil):
                commitRing(nil, center: entry.center, hiddenCells: nil)
            case let .failure(error):
                let reason = String(describing: error)
                CellStreamer.logger.warning(
                    "[WARNING] distant LOD build failed: \(reason, privacy: .public)"
                )
                // Without a ring, no LOD can draw over a full cell, so every cell shows.
                commitRing(nil, center: entry.center, hiddenCells: nil)
            }
            changed = true
        }
        return changed
    }

    /// Drops finished rings unseen, as inside an interior, so the next ring can start.
    func discardDistantLOD(_ entries: [DistantLODBuildResult]) {
        for entry in entries {
            streamer.lodRequestHiddenCells = nil
            if case let .success(scene?) = entry.result {
                evictUnused(scene.assets)
            }
        }
    }

    /// Drops waiting cells the grid no longer wants, except those the ring being
    /// built leaves out: they must draw when it arrives.
    public func discardStagedCells(outside desiredCells: Set<CellCoordinate>) {
        let stale = streamer.stagedCells.keys.filter {
            !desiredCells.contains($0) && streamer.lodRequestHiddenCells?.contains($0) != true
        }
        for coordinate in stale {
            guard let scene = streamer.stagedCells.removeValue(forKey: coordinate) else { continue }
            evictUnused(scene.assets)
        }
    }

    /// Swaps in a ring and exactly the cells it leaves out. With no ring
    /// (`hiddenCells` nil), every waiting cell shows and every unwanted cell goes. A drawn cell the
    /// ring covers goes
    /// off screen; if the grid still wants it, it waits for the next ring.
    func commitRing(
        _ distantLOD: DistantLODScene?,
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>?
    ) {
        let resident = streamer.core.resident
        // Without a ring, only the cells the grid no longer wants leave.
        let leaving = streamer.composition.coordinates.sorted(by: Self.gridOrder)
            .filter { !(hiddenCells?.contains($0) ?? resident.contains($0)) }
        // Deterministic promotion order so script instantiation is reproducible.
        let arriving = streamer.stagedCells.sorted { Self.gridOrder($0.key, $1.key) }
            .filter { hiddenCells?.contains($0.key) ?? true }
        for (coordinate, _) in arriving {
            streamer.stagedCells.removeValue(forKey: coordinate)
        }
        var detached: [(coordinate: CellCoordinate, scene: CellScene)] = []
        var attached: [(scene: CellScene, first: Bool)] = []
        var departed = CellAssets()
        streamer.composition.batch { composition in
            for coordinate in leaving {
                guard let scene = composition.removeCell(at: coordinate) else { continue }
                detached.append((coordinate, scene))
            }
            for (coordinate, scene) in arriving {
                let replaced = composition.setCell(scene, at: coordinate)
                // A waiting cell that replaced a drawn scene at the same coordinate
                // never left the world, so it is not a first attach.
                attached.append((scene, replaced == nil))
                if let replaced {
                    departed.meshKeys.formUnion(replaced.assets.meshKeys)
                    departed.textureKeys.formUnion(replaced.assets.textureKeys)
                }
            }
        }
        for (coordinate, scene) in detached {
            if resident.contains(coordinate) {
                streamer.stagedCells[coordinate] = scene
            } else {
                departed.meshKeys.formUnion(scene.assets.meshKeys)
                departed.textureKeys.formUnion(scene.assets.textureKeys)
            }
        }
        // The events go out once the composition is whole, so a listener reads it as drawn.
        for (_, scene) in detached {
            streamer.triggers.emitCellDetached(scene)
        }
        for (scene, first) in attached {
            streamer.triggers.queueCellAttached(scene, firstIntegration: first)
        }
        if let oldLOD = streamer.composition.setDistantLOD(distantLOD) {
            departed.meshKeys.formUnion(oldLOD.assets.meshKeys)
            departed.textureKeys.formUnion(oldLOD.assets.textureKeys)
        }
        streamer.ringSwapCount += 1
        streamer.liveLODHiddenCells = distantLOD == nil ? nil : hiddenCells
        streamer.liveLODCenter = distantLOD == nil ? nil : center
        evictUnused(departed)
    }

    private static func gridOrder(_ lhs: CellCoordinate, _ rhs: CellCoordinate) -> Bool {
        (lhs.x, lhs.y) < (rhs.x, rhs.y)
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
