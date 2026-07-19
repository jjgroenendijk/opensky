// SerialCellBuildRunner behaviour (todo 3.2 memory safeguards): the serial
// executor dedupes enqueues (queue depth bounded by grid size -- defence
// against the 30 GB runaway) and routes eviction through the same queue so the
// libraries stay confined. Driven with a fake provider + a gate, no Metal, no
// game data.

import Foundation
@testable import opensky
import simd
import Testing

/// Fake provider: counts builds per coordinate, optionally blocking each build
/// on a gate so the test can hold one "in flight" while it enqueues again.
/// Records eviction drop-sets. Thread-safe (queue + main touch it).
nonisolated private final class FakeProvider: CellSceneProvider {
    private let lock = NSLock()
    private var builds: [CellCoordinate: Int] = [:]
    private var evictions: [(mesh: Set<String>, texture: Set<String>)] = []
    private let gate: DispatchSemaphore?
    private let started: DispatchSemaphore?
    private let collision: StaticCollisionSet

    init(
        gate: DispatchSemaphore? = nil,
        started: DispatchSemaphore? = nil,
        collision: StaticCollisionSet = .empty
    ) {
        self.gate = gate
        self.started = started
        self.collision = collision
    }

    func buildCell(at coordinate: CellCoordinate) throws -> CellScene {
        started?.signal()
        gate?.wait()
        lock.lock()
        builds[coordinate, default: 0] += 1
        lock.unlock()
        return CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "fake", gridX: coordinate.x, gridY: coordinate.y,
                totalRefCount: 0, drawnRefCount: 0,
                unsupportedBaseSkipCount: 0, markerSkipCount: 0,
                modelFailureSkipCount: 0, malformedRefSkipCount: 0,
                modelCount: 0, textureCount: 0, missingTextureCount: 0
            ),
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

    /// Waits (bounded) for `condition`, pumping the runloop-free deadline.
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return condition()
    }

    @Test
    func enqueueDedupesWhileACellIsInFlight() {
        let gate = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        let provider = FakeProvider(gate: gate, started: started)
        let runner = SerialCellBuildRunner(provider: provider)

        let cell = coordinate(6, -2)
        runner.enqueue(cell)
        // Ensure the build is running (in `pending`) before enqueuing again.
        #expect(started.wait(timeout: .now() + 5) == .success)
        runner.enqueue(cell) // deduped -- coordinate still pending
        runner.enqueue(cell) // deduped
        gate.signal() // release the single build

        #expect(waitUntil {
            runner.drainCompleted().isEmpty == false || provider.buildCount(cell) == 1
        })
        // Give any erroneous extra builds a chance to run, then assert one.
        Thread.sleep(forTimeInterval: 0.05)
        #expect(provider.buildCount(cell) == 1, "enqueue did not dedupe")
    }

    @Test
    func reenqueueAfterCompletionBuildsAgain() {
        let provider = FakeProvider()
        let runner = SerialCellBuildRunner(provider: provider)
        let cell = coordinate(0, 0)

        runner.enqueue(cell)
        #expect(waitUntil { runner.drainCompleted().isEmpty == false })
        // No longer pending -> a fresh enqueue rebuilds (e.g. after unload).
        runner.enqueue(cell)
        #expect(waitUntil { provider.buildCount(cell) == 2 })
    }

    @Test
    func enqueueDedupesWhileCompletionWaitsForDrain() {
        let provider = FakeProvider()
        let runner = SerialCellBuildRunner(provider: provider)
        let cell = coordinate(2, 3)

        runner.enqueue(cell)
        #expect(waitUntil { provider.buildCount(cell) == 1 })
        Thread.sleep(forTimeInterval: 0.05) // completion now buffered
        runner.enqueue(cell)
        Thread.sleep(forTimeInterval: 0.05)

        #expect(provider.buildCount(cell) == 1)
        #expect(runner.drainCompleted().count == 1)
    }

    @Test
    func enqueueEvictionRoutesDropSetsToTheProvider() {
        let provider = FakeProvider()
        let runner = SerialCellBuildRunner(provider: provider)
        runner.enqueueEviction(droppingMeshKeys: ["m1"], droppingTextureKeys: ["t1", "t2"])
        #expect(waitUntil { provider.evictionCount == 1 })
        #expect(provider.lastEviction?.mesh == ["m1"])
        #expect(provider.lastEviction?.texture == ["t1", "t2"])
    }

    @Test
    func emptyEvictionIsNotDispatched() {
        let provider = FakeProvider()
        let runner = SerialCellBuildRunner(provider: provider)
        runner.enqueueEviction(droppingMeshKeys: [], droppingTextureKeys: [])
        Thread.sleep(forTimeInterval: 0.05)
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

        runner.enqueue(cell)
        #expect(waitUntil { !runner.drainCompleted().isEmpty })
        let metric = runner.buildMetricsSnapshot()[cell]
        #expect(metric?.collisionDurationMS == 4.25)
        #expect(metric?.collisionShapeCount == 1)
        #expect(metric?.collisionTriangleCount == 1)

        runner.enqueueEviction(
            droppingMeshKeys: ["meshes\\arch\\solid.nif"],
            droppingTextureKeys: []
        )
        #expect(waitUntil { provider.evictionCount == 1 })
        #expect(provider.lastEviction?.mesh == ["meshes\\arch\\solid.nif"])
    }
}
