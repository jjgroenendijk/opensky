// SerialCellBuildRunner: dedupes enqueues and routes eviction through the
// build queue. Uses a fake provider and a gate, so no Metal and no game data.
// `waitUntilIdle()` flushes the queue, so no test waits a fixed time.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import simd
import Testing

/// Fake provider: counts builds per coordinate, optionally blocking each build
/// on a gate so the test can hold one "in flight" while it enqueues again.
/// Records eviction drop-sets. Thread-safe (queue + main touch it).
nonisolated private final class FakeProvider: CellSceneProvider {
    private let lock = NSLock()
    private var builds: [CellCoordinate: Int] = [:]
    /// Snapshot each build ran against, so a test can assert the runner passes
    /// the caller's state through (issue #160).
    private var states: [CellCoordinate: WorldStateSnapshot] = [:]
    private var evictions: [(mesh: Set<String>, texture: Set<String>)] = []
    private let gate: DispatchSemaphore?
    private let started: DispatchSemaphore?
    private let collision: StaticCollisionSet
    private let summaryMutation: (@Sendable (inout CellLoadSummary) -> Void)?

    init(
        gate: DispatchSemaphore? = nil,
        started: DispatchSemaphore? = nil,
        collision: StaticCollisionSet = .empty,
        summaryMutation: (@Sendable (inout CellLoadSummary) -> Void)? = nil
    ) {
        self.gate = gate
        self.started = started
        self.collision = collision
        self.summaryMutation = summaryMutation
    }

    func buildCell(at coordinate: CellCoordinate, state: WorldStateSnapshot) throws -> CellScene {
        started?.signal()
        gate?.wait()
        lock.lock()
        builds[coordinate, default: 0] += 1
        states[coordinate] = state
        lock.unlock()
        var summary = CellLoadSummary(
            cellName: "fake", gridX: coordinate.x, gridY: coordinate.y,
            totalRefCount: 0, drawnRefCount: 0,
            unsupportedBaseSkipCount: 0, markerSkipCount: 0,
            modelFailureSkipCount: 0, malformedRefSkipCount: 0,
            modelCount: 0, textureCount: 0, missingTextureCount: 0
        )
        summaryMutation?(&summary)
        return CellScene(
            renderScene: RenderScene(instances: []),
            summary: summary,
            bounds: nil,
            staticCollision: collision
        )
    }

    func evict(
        droppingMeshKeys meshKeys: Set<String>,
        droppingTextureKeys textureKeys: Set<String>
    ) {
        lock.lock()
        evictions.append((meshKeys, textureKeys))
        lock.unlock()
    }

    func buildCount(_ coordinate: CellCoordinate) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return builds[coordinate, default: 0]
    }

    func buildState(_ coordinate: CellCoordinate) -> WorldStateSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return states[coordinate]
    }

    var evictionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return evictions.count
    }

    var lastEviction: (mesh: Set<String>, texture: Set<String>)? {
        lock.lock()
        defer { lock.unlock() }
        return evictions.last
    }
}

struct CellBuildRunnerTests {
    private func coordinate(_ x: Int32, _ y: Int32) -> CellCoordinate {
        CellCoordinate(x: x, y: y)
    }

    @Test
    func enqueueDedupesWhileACellIsInFlight() {
        let gate = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        let provider = FakeProvider(gate: gate, started: started)
        let runner = SerialCellBuildRunner(provider: provider)

        let cell = coordinate(6, -2)
        runner.enqueue(cell, state: .empty)
        // Ensure the build is running (in `pending`) before enqueuing again.
        #expect(started.wait(timeout: .now() + 5) == .success)
        runner.enqueue(cell, state: .empty) // deduped -- coordinate still pending
        runner.enqueue(cell, state: .empty) // deduped
        gate.signal() // release the single build

        runner.waitUntilIdle()
        #expect(provider.buildCount(cell) == 1, "enqueue did not dedupe")
    }

    @Test
    func reenqueueAfterCompletionBuildsAgain() {
        let provider = FakeProvider()
        let runner = SerialCellBuildRunner(provider: provider)
        let cell = coordinate(0, 0)

        runner.enqueue(cell, state: .empty)
        runner.waitUntilIdle()
        #expect(runner.drainCompleted().count == 1)
        // No longer pending -> a fresh enqueue rebuilds (e.g. after unload).
        runner.enqueue(cell, state: .empty)
        runner.waitUntilIdle()
        #expect(provider.buildCount(cell) == 2)
    }

    @Test
    func enqueueDedupesWhileCompletionWaitsForDrain() {
        let provider = FakeProvider()
        let runner = SerialCellBuildRunner(provider: provider)
        let cell = coordinate(2, 3)

        runner.enqueue(cell, state: .empty)
        runner.waitUntilIdle() // completion now buffered
        runner.enqueue(cell, state: .empty)
        runner.waitUntilIdle()

        #expect(provider.buildCount(cell) == 1)
        #expect(runner.drainCompleted().count == 1)
    }

    @Test
    func enqueueEvictionRoutesDropSetsToTheProvider() {
        let provider = FakeProvider()
        let runner = SerialCellBuildRunner(provider: provider)
        runner.enqueueEviction(droppingMeshKeys: ["m1"], droppingTextureKeys: ["t1", "t2"])
        runner.waitUntilIdle()
        #expect(provider.evictionCount == 1)
        #expect(provider.lastEviction?.mesh == ["m1"])
        #expect(provider.lastEviction?.texture == ["t1", "t2"])
    }

    @Test
    func emptyEvictionIsNotDispatched() {
        let provider = FakeProvider()
        let runner = SerialCellBuildRunner(provider: provider)
        runner.enqueueEviction(droppingMeshKeys: [], droppingTextureKeys: [])
        runner.waitUntilIdle()
        #expect(provider.evictionCount == 0)
    }

    @Test
    func collisionBuildMetricsAndEvictionUseFakeProviderQueue() {
        let shape = StaticCollisionShape(
            reference: FormID(1),
            transform: matrix_identity_float4x4,
            geometry: .triangleSoup(
                vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
                indices: [0, 1, 2]
            ),
            bounds: ModelBounds(min: SIMD3(0, 0, 0), max: SIMD3(1, 1, 0))
        )
        var stats = StaticCollisionStats()
        stats.shapeCount = 1
        stats.triangleCount = 1
        let collision = StaticCollisionSet(
            location: .exterior(coordinate(6, -2)),
            shapes: [shape],
            stats: stats,
            buildDurationMS: 4.25
        )
        let provider = FakeProvider(collision: collision)
        let runner = SerialCellBuildRunner(provider: provider)
        let cell = coordinate(6, -2)

        runner.enqueue(cell, state: .empty)
        runner.waitUntilIdle()
        #expect(runner.drainCompleted().count == 1)
        let metric = runner.buildMetricsSnapshot()[cell]
        #expect(metric?.collisionDurationMS == 4.25)
        #expect(metric?.collisionShapeCount == 1)
        #expect(metric?.collisionTriangleCount == 1)

        runner.enqueueEviction(
            droppingMeshKeys: ["meshes\\arch\\solid.nif"],
            droppingTextureKeys: []
        )
        runner.waitUntilIdle()
        #expect(provider.evictionCount == 1)
        #expect(provider.lastEviction?.mesh == ["meshes\\arch\\solid.nif"])
    }

    // MARK: - Actor accounting mirror (5.5 exact + 5.6 explained rules)

    @Test
    func actorMetricsMirrorSummaryIncludingFailureReasons() {
        let provider = FakeProvider { summary in
            summary.actorCount = 3
            summary.actorDrawnCount = 1
            summary.actorDisabledSkipCount = 1
            summary.actorFailureCount = 1
            summary.actorFailureReasons = ["ACHR 00000900: unresolved (test)"]
            summary.actorAnimationFailureCount = 1
            summary.actorAnimationFailureReasons = ["ACHR 00000800: unsupported skeleton (test)"]
            summary.actorBuildDurationMS = 2.5
        }
        let runner = SerialCellBuildRunner(provider: provider)
        let cell = coordinate(6, -2)

        runner.enqueue(cell, state: .empty)
        runner.waitUntilIdle()
        #expect(runner.drainCompleted().count == 1)
        let metric = runner.buildMetricsSnapshot()[cell]
        #expect(metric?.actorDiscoveredCount == 3)
        #expect(metric?.actorRenderedCount == 1)
        #expect(metric?.actorDisabledSkipCount == 1)
        #expect(metric?.actorFailureCount == 1)
        #expect(metric?.actorFailureReasons == ["ACHR 00000900: unresolved (test)"])
        #expect(metric?.actorAnimationFailureCount == 1)
        #expect(metric?.actorAnimationFailureReasons == [
            "ACHR 00000800: unsupported skeleton (test)"
        ])
        #expect(metric?.actorDurationMS == 2.5)
        #expect(metric?.actorAccountingIsExact == true)
        #expect(metric?.actorFailuresAreExplained == true)
        #expect(metric?.actorAnimationAccountingIsExact == true)
        #expect(metric?.actorAnimationFailuresAreExplained == true)
    }

    @Test
    func failureWithoutReasonIsUnexplained() {
        var metric = CellBuildMetric(
            totalDurationMS: 0, collisionDurationMS: 0,
            collisionShapeCount: 0, collisionTriangleCount: 0
        )
        metric.actorDiscoveredCount = 1
        metric.actorFailureCount = 1
        #expect(metric.actorAccountingIsExact)
        #expect(!metric.actorFailuresAreExplained)
    }

    @Test
    func staticFallbackWithoutReasonIsUnexplained() {
        var metric = CellBuildMetric(
            totalDurationMS: 0, collisionDurationMS: 0,
            collisionShapeCount: 0, collisionTriangleCount: 0
        )
        metric.actorRenderedCount = 1
        metric.actorAnimationFailureCount = 1
        #expect(metric.actorAnimationAccountingIsExact)
        #expect(!metric.actorAnimationFailuresAreExplained)
    }
}
