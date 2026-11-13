// The build pipeline: dispatch, integrate, and recompose the resident cells.

import Foundation
import OpenSkyAudio
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyTerrain
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension CellStreamer.BuildSteps {
    /// Pushes the current exterior center cell's XCLR regions to the weather
    /// feed when they change. Only fires for a resident exterior center: the
    /// interior path returns before this (regions left unchanged — weather is
    /// exterior-only, so entering a building keeps the exterior region so the
    /// exit resumes seamlessly), and a center that has not streamed in yet is
    /// skipped so a brief loading gap never drops region weighting.
    func emitCenterRegionsIfChanged() {
        guard let scene = streamer.composition.cells[streamer.grid.center] else { return }
        let regions = scene.regions
        guard regions != streamer.events.lastEmittedRegions else { return }
        streamer.events.lastEmittedRegions = regions
        streamer.events.onCenterRegionsChanged?(regions)
    }

    /// At most one build per frame. First loads go before world-state
    /// rebuilds, so a new cell still arrives center-out. The world-state
    /// snapshot is taken here, the last main-thread moment before the build
    /// leaves for the serial runner.
    func dispatchNextBuild() {
        guard
            streamer.transitionInFlight == nil,
            streamer.interiorScene == nil,
            streamer.activeBuild == nil,
            streamer.pending.isEmpty
        else { return }
        if !streamer.requests.isEmpty {
            let coordinate = streamer.requests.removeFirst()
            streamer.activeBuild = coordinate
            streamer.runner.enqueue(coordinate, state: streamer.stateSource())
            return
        }
        dispatchNextRebuild()
    }

    /// Takes the first rebuild request the core still accepts. A request whose
    /// cell stopped being resident (unloaded, or its first build has not
    /// landed yet) is dropped here rather than dispatched; for the unloaded
    /// case that is the cancellation, and for the not-yet-resident case the
    /// integration of the first build re-queues it against the fresher state.
    func dispatchNextRebuild() {
        while !streamer.rebuildRequests.isEmpty {
            let coordinate = streamer.rebuildRequests.removeFirst()
            guard streamer.core.beginRebuild(coordinate) else { continue }
            streamer.activeBuild = coordinate
            streamer.runner.enqueue(coordinate, state: streamer.stateSource())
            return
        }
    }

    /// Drains completed builds, folding each into the core. Void / failed /
    /// stale outcomes are cheap (no recompose) and drained freely; the first
    /// drawable success becomes resident and stops the drain -- that is the
    /// per-frame budget of one recompose. Returns whether a cell was
    /// integrated (composition changed). Remaining successes wait for the
    /// next frame.
    func integrateOneBuild() -> Bool {
        while !streamer.pending.isEmpty {
            let entry = streamer.pending.removeFirst()
            streamer.requests.removeAll { $0 == entry.coordinate }
            switch entry.result {
            case let .success(scene):
                // A rebuild must not read as a fresh attach. `integrate` clears
                // `rebuilding`, so read it first.
                let isRebuild = streamer.core.rebuilding.contains(entry.coordinate)
                let decision = streamer.core.integrate(coordinate: entry.coordinate, kind: .success)
                if decision == .integrated {
                    streamer.runtimeStates.requeueRebuildIfStateMoved(
                        entry.coordinate,
                        scene: scene
                    )
                    if streamer.coverageTransitionActive {
                        if let replaced = streamer.stagedCells.updateValue(
                            scene,
                            forKey: entry.coordinate
                        ) {
                            streamer.coverage.evictUnused(replaced.assets)
                        }
                        // Staged offscreen: announced when the transition commits.
                        return false
                    }
                    if let replaced = streamer.composition.setCell(scene, at: entry.coordinate) {
                        streamer.coverage.evictUnused(replaced.assets)
                    }
                    streamer.triggers.emitCellAttached(scene, firstIntegration: !isRebuild)
                    return true
                }
                if decision == .discardedStale {
                    streamer.coverage.evictUnused(scene.assets)
                }
            // Stale success (unloaded mid-flight) -- drop, keep draining.
            case let .failure(error):
                let kind: CellStreamCore.BuildKind = Self.isVoid(error) ? .void : .failure
                let decision = streamer.core.integrate(coordinate: entry.coordinate, kind: kind)
                log(coordinate: entry.coordinate, decision: decision, error: error)
            }
        }
        return false
    }

    /// A void slot (no CELL at the grid position) throws `cellNotFound`;
    /// everything else is a genuine build failure.
    static func isVoid(_ error: any Error) -> Bool {
        guard let cellError = error as? CellSceneError else { return false }
        if case .cellNotFound = cellError {
            return true
        }
        return false
    }

    func log(
        coordinate: CellCoordinate,
        decision: CellStreamCore.IntegrationResult,
        error: any Error
    ) {
        let position = "(\(coordinate.x),\(coordinate.y))"
        switch decision {
        case .recordedVoid:
            CellStreamer.logger.debug("[INFO] cell \(position, privacy: .public) void, not retried")
        case .recordedFailed:
            let reason = String(describing: error)
            CellStreamer.logger.warning(
                """
                [WARNING] cell \(position, privacy: .public) build failed, \
                not retried: \(reason, privacy: .public)
                """
            )
        case .discardedStale, .integrated:
            break
        }
    }

    /// Recomposes the resident cells and hands the scene to the sink. The
    /// first recompose that has drawable bounds frames the camera; all later
    /// ones pass nil.
    func recomposeAndSink() {
        let scene = streamer.props.viewScene()
        var camera: SceneCamera?
        if !streamer.hasSeededCamera, let bounds = streamer.composition.composedBounds() {
            camera = SceneCamera.framing(bounds: bounds)
            streamer.hasSeededCamera = true
        }
        streamer.sink(scene, camera)
        streamer.coverage.logFootprint()
    }

    func resetExterior(at position: SIMD3<Float>) {
        var departed = CellAssets()
        for coordinate in streamer.composition.coordinates {
            guard let removed = streamer.composition.removeCell(at: coordinate) else { continue }
            streamer.triggers.emitCellDetached(removed)
            departed.meshKeys.formUnion(removed.assets.meshKeys)
            departed.textureKeys.formUnion(removed.assets.textureKeys)
        }
        let staged = Array(streamer.stagedCells.values)
        streamer.stagedCells.removeAll()
        if let lod = streamer.composition.setDistantLOD(nil) {
            departed.meshKeys.formUnion(lod.assets.meshKeys)
            departed.textureKeys.formUnion(lod.assets.textureKeys)
        }
        for scene in streamer.pending
            .compactMap({ element in attempt { try element.result.get() } }) + staged
        {
            departed.meshKeys.formUnion(scene.assets.meshKeys)
            departed.textureKeys.formUnion(scene.assets.textureKeys)
        }
        streamer.pending.removeAll()
        streamer.requests.removeAll()
        streamer.rebuildRequests.removeAll()
        streamer.cellMutationSequence.removeAll()
        streamer.core = CellStreamCore()
        streamer.requestedLODCenter = nil
        streamer.settledLODCenter = nil
        streamer.largeReferenceRequestCenter = nil
        streamer.largeReferenceSettledCenter = nil
        streamer.coverageTransitionActive = false
        streamer.events.lastEmittedRegions = nil
        streamer.grid = CellGridManager(initialPosition: position, radius: streamer.grid.radius)
        streamer.coverage.evictUnused(departed)
    }

    /// False for a result built in a worldspace the exterior has left. Its
    /// assets go back for eviction.
    func builtHere(_ entry: CellBuildResult) -> Bool {
        guard
            let worldspace = entry.worldspaceEditorID,
            worldspace != streamer.worldspaceEditorID
        else {
            return true
        }
        if case let .success(scene) = entry.result {
            streamer.coverage.evictUnused(scene.assets)
        }
        return false
    }

    func builtHere(_ entry: DistantLODBuildResult) -> Bool {
        guard
            let worldspace = entry.worldspaceEditorID,
            worldspace != streamer.worldspaceEditorID
        else {
            return true
        }
        if case let .success(scene?) = entry.result {
            streamer.coverage.evictUnused(scene.assets)
        }
        return false
    }
}
