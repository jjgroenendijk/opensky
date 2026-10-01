// Shared streaming test doubles. `ManualCellBuildRunner` started life inside
// CellStreamerTests.swift and is used by every streaming suite, so it lives
// here at file scope, away from that file's size cap.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
@testable import OpenSkyWorldState

/// Test build runner: the test stages completions and controls their order,
/// standing in for the serial DispatchQueue without any async timing.
nonisolated public final class ManualCellBuildRunner: CellBuildRunning {
    public private(set) var enqueued: [CellCoordinate] = []
    public private(set) var evictedMeshKeys: [Set<String>] = []
    public private(set) var evictedTextureKeys: [Set<String>] = []
    public private(set) var enqueuedDoorTransitions: [FormID] = []
    /// World-state snapshots handed to each build, in enqueue order, so a test
    /// can assert what state a build ran against (issue #160).
    public private(set) var enqueuedStates: [WorldStateSnapshot] = []
    public private(set) var enqueuedDoorTransitionStates: [WorldStateSnapshot] = []
    /// Distant-LOD centers the streamer asked for, in request order.
    public private(set) var enqueuedLODCenters: [CellCoordinate] = []
    private var ready: [CellBuildResult] = []
    private var readyDoorTransitions: [DoorTransitionBuildResult] = []
    private var readyLOD: [DistantLODBuildResult] = []

    public init() {}

    public func enqueue(_ coordinate: CellCoordinate, state: WorldStateSnapshot) {
        enqueued.append(coordinate)
        enqueuedStates.append(state)
    }

    public func complete(_ coordinate: CellCoordinate, with result: Result<CellScene, any Error>) {
        ready.append(CellBuildResult(coordinate: coordinate, result: result))
    }

    public func drainCompleted() -> [CellBuildResult] {
        let out = ready
        ready.removeAll(keepingCapacity: true)
        return out
    }

    public func enqueueEviction(
        droppingMeshKeys meshKeys: Set<String>,
        droppingTextureKeys textureKeys: Set<String>
    ) {
        evictedMeshKeys.append(meshKeys)
        evictedTextureKeys.append(textureKeys)
    }

    public func enqueueDoorTransition(from sourceDoor: FormID, state: WorldStateSnapshot) {
        enqueuedDoorTransitions.append(sourceDoor)
        enqueuedDoorTransitionStates.append(state)
    }

    public func completeDoorTransition(
        from sourceDoor: FormID,
        with result: Result<DoorTransition, any Error>
    ) {
        readyDoorTransitions.append(DoorTransitionBuildResult(
            sourceDoor: sourceDoor, result: result
        ))
    }

    public func drainCompletedDoorTransitions() -> [DoorTransitionBuildResult] {
        let out = readyDoorTransitions
        readyDoorTransitions.removeAll(keepingCapacity: true)
        return out
    }

    // MARK: - Distant LOD

    /// Accepting LOD requests is what lets a test reach the coverage
    /// transition, where recenter builds stage offscreen instead of composing.
    @discardableResult
    public func enqueueDistantLOD(
        center: CellCoordinate,
        hiddenCells _: Set<CellCoordinate>
    ) -> Bool {
        enqueuedLODCenters.append(center)
        return true
    }

    public func completeDistantLOD(_ center: CellCoordinate, with scene: DistantLODScene) {
        readyLOD.append(DistantLODBuildResult(center: center, result: .success(scene)))
    }

    public func drainCompletedDistantLOD() -> [DistantLODBuildResult] {
        let out = readyLOD
        readyLOD.removeAll(keepingCapacity: true)
        return out
    }
}
