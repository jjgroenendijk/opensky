// Scripted cross-cell streaming benchmark (todo 3.2 verification). Drives a
// deterministic east-then-north camera path through the same CellStreamer,
// Renderer, serial builder, scene swaps, and cache eviction used by the app.
// One reused offscreen target + 100 Hz pacing keep the verifier bounded while
// physical-footprint, settlement, unload, and duplicate-build gates make the
// milestone claims repeatable from openskycli.

import Foundation
import simd

nonisolated enum CellStreamingFlyBenchmarkError: LocalizedError {
    case memoryMeasurementFailed
    case footprintExceeded(megabytes: Double, cap: Double)
    case footprintDidNotPlateau(initial: Double, final: Double)
    case sceneSwapFailed(any Error)
    case cellBuildFailed(count: Int)
    case unexpectedBuildSet(expected: Int, actual: Int)
    case duplicateBuilds([CellCoordinate: Int])
    case collisionBuildExceeded(p95: Double, maximum: Double, budget: Double)
    case actorBuildExceeded(p95: Double, maximum: Double, budget: Double)
    case actorAccountingMismatch(coordinate: CellCoordinate, discovered: Int, explained: Int)
    case actorFailureUnexplained(coordinate: CellCoordinate, failures: Int, reasons: Int)
    case noCellsUnloaded

    var errorDescription: String? {
        switch self {
        case .memoryMeasurementFailed:
            "cannot read task_vm_info.phys_footprint"
        case let .footprintExceeded(megabytes, cap):
            String(format: "physical footprint %.0f MB exceeded %.0f MB cap", megabytes, cap)
        case let .footprintDidNotPlateau(initial, final):
            String(format: "physical footprint did not plateau: %.0f -> %.0f MB", initial, final)
        case let .sceneSwapFailed(error):
            "scene swap failed: \(String(describing: error))"
        case let .cellBuildFailed(count):
            "streaming ended with \(count) failed cell builds"
        case let .unexpectedBuildSet(expected, actual):
            "fly path built \(actual) unique cells; expected \(expected)"
        case let .duplicateBuilds(counts):
            "duplicate cell builds: \(Self.describe(counts))"
        case let .collisionBuildExceeded(p95, maximum, budget):
            String(
                format: "collision build p95 %.2f ms / max %.2f ms exceeded %.2f ms budget",
                p95, maximum, budget
            )
        case let .actorBuildExceeded(p95, maximum, budget):
            String(
                format: "actor build p95 %.2f ms / max %.2f ms exceeded %.2f ms budget",
                p95, maximum, budget
            )
        case let .actorAccountingMismatch(coordinate, discovered, explained):
            "cell (\(coordinate.x),\(coordinate.y)) actor accounting not exact: "
                + "\(discovered) discovered vs \(explained) explained"
        case let .actorFailureUnexplained(coordinate, failures, reasons):
            "cell (\(coordinate.x),\(coordinate.y)) has \(failures) failed actors "
                + "but only \(reasons) reasons — unexplained failure"
        case .noCellsUnloaded:
            "cross-cell path did not unload any initially resident cells"
        }
    }

    private static func describe(_ counts: [CellCoordinate: Int]) -> String {
        counts
            .sorted { ($0.key.x, $0.key.y) < ($1.key.x, $1.key.y) }
            .map { "(\($0.key.x),\($0.key.y))=\($0.value)" }
            .joined(separator: ", ")
    }
}

/// Deterministic path: launch center -> one cell east -> one cell north.
/// Each leg samples a linear camera flight; every waypoint then waits for its
/// full 5x5 grid to settle before continuing.
nonisolated enum CellStreamingFlyPath {
    static func waypoints(start: CellCoordinate) -> [CellCoordinate] {
        [
            start,
            CellCoordinate(x: start.x + 1, y: start.y),
            CellCoordinate(x: start.x + 1, y: start.y + 1)
        ]
    }

    static func positions(
        from start: CellCoordinate,
        to end: CellCoordinate,
        samples: Int
    ) -> [SIMD3<Float>] {
        let startPosition = CellGridManager.cellCenter(of: start)
        let endPosition = CellGridManager.cellCenter(of: end)
        let count = max(samples, 1)
        return (1 ... count).map { sample in
            let progress = Float(sample) / Float(count)
            return simd_mix(startPosition, endPosition, SIMD3<Float>(repeating: progress))
        }
    }

    static func expectedCells(start: CellCoordinate, radius: Int32) -> Set<CellCoordinate> {
        waypoints(start: start).reduce(into: Set<CellCoordinate>()) { result, waypoint in
            let manager = CellGridManager(
                initialPosition: CellGridManager.cellCenter(of: waypoint),
                radius: radius
            )
            result.formUnion(manager.desiredCells)
        }
    }
}

/// Per-cell actor accounting surfaced to the CLI: the 5.6 acceptance probe
/// reports discovered/rendered/intentional-skip/failure counts for each
/// touched cell, failures carrying their reasons.
nonisolated struct ActorCellReport: Equatable {
    let coordinate: CellCoordinate
    let discovered: Int
    let rendered: Int
    let disabledSkips: Int
    let failures: Int
    let failureReasons: [String]
}

nonisolated struct CellStreamingFlyBenchmarkResult {
    let render: OffscreenBenchResult
    let settledFootprintsMB: [Double]
    let peakFootprintMB: Double
    let uniqueBuildCount: Int
    let unloadedCellCount: Int
    let finalResidentCellCount: Int
    let finalVoidCellCount: Int
    let footprintCapMB: Double
    let collisionBuildAverageMS: Double
    let collisionBuildP95MS: Double
    let collisionBuildMaximumMS: Double
    let collisionBuildBudgetMS: Double
    let collisionShapeCount: Int
    let collisionTriangleCount: Int
    let actorBuildAverageMS: Double
    let actorBuildP95MS: Double
    let actorBuildMaximumMS: Double
    let actorBuildBudgetMS: Double
    let actorDiscoveredCount: Int
    let actorRenderedCount: Int
    let actorDisabledSkipCount: Int
    let actorFailureCount: Int
    /// One entry per touched cell, sorted by coordinate for stable output.
    let actorCellReports: [ActorCellReport]
}

nonisolated struct CellStreamingFlyBenchmarkConfiguration {
    let start: CellCoordinate
    let size: (width: Int, height: Int)
    let maxFrames: Int
    let footprintCapMB: Double
    let collisionBuildBudgetMS: Double
    let actorBuildBudgetMS: Double
    var samplesPerLeg = 60
}

@MainActor
enum CellStreamingFlyBenchmark {
    private final class SceneSwapErrorBox {
        var error: (any Error)?
    }

    static func run(
        renderer: Renderer,
        provider: any CellSceneProvider,
        configuration: CellStreamingFlyBenchmarkConfiguration
    ) throws -> CellStreamingFlyBenchmarkResult {
        let driver = Driver(
            renderer: renderer,
            provider: provider,
            configuration: configuration
        )
        let render = try renderer.pumpOffscreen(
            width: configuration.size.width,
            height: configuration.size.height,
            maxFrames: configuration.maxFrames,
            minimumFrameInterval: 0.01
        ) {
            try driver.step()
        }
        return try driver.result(render: render)
    }

    private final class Driver {
        private let renderer: Renderer
        private let runner: SerialCellBuildRunner
        private let streamer: CellStreamer
        private let swapError: SceneSwapErrorBox
        private let configuration: CellStreamingFlyBenchmarkConfiguration
        private let segments: [[SIMD3<Float>]]
        private var legIndex = -1 // -1 = launch-grid settlement
        private var sampleIndex = 0
        private var moving = false
        private var settledFootprints: [Double] = []
        private var peakFootprint = 0.0
        private var initialResidents = Set<CellCoordinate>()
        private var currentPosition: SIMD3<Float>

        init(
            renderer: Renderer,
            provider: any CellSceneProvider,
            configuration: CellStreamingFlyBenchmarkConfiguration
        ) {
            self.renderer = renderer
            self.configuration = configuration
            runner = SerialCellBuildRunner(provider: provider)
            swapError = SceneSwapErrorBox()
            streamer = CellStreamer(
                center: configuration.start,
                runner: runner
            ) { [renderer, swapError] scene, camera in
                do {
                    try renderer.setScene(scene, camera: camera)
                } catch {
                    swapError.error = error
                }
            }
            let waypoints = CellStreamingFlyPath.waypoints(start: configuration.start)
            segments = zip(waypoints, waypoints.dropFirst()).map { from, to in
                CellStreamingFlyPath.positions(
                    from: from,
                    to: to,
                    samples: configuration.samplesPerLeg
                )
            }
            currentPosition = CellGridManager.cellCenter(of: configuration.start)
        }

        func step() throws -> Bool {
            _ = try sampleFootprint()
            if let error = swapError.error {
                throw CellStreamingFlyBenchmarkError.sceneSwapFailed(error)
            }
            if moving {
                moveOneSample()
                _ = try sampleFootprint()
                return false
            }
            streamer.update(cameraPosition: currentPosition)
            let footprint = try sampleFootprint()
            guard isSettled(streamer) else { return false }
            settledFootprints.append(footprint)
            if legIndex == -1 {
                initialResidents = streamer.residentCoordinates
            }
            legIndex += 1
            guard legIndex < segments.count else { return true }
            sampleIndex = 0
            moving = true
            return false
        }

        private func sampleFootprint() throws -> Double {
            let footprint = try checkedFootprint(capMB: configuration.footprintCapMB)
            peakFootprint = max(peakFootprint, footprint)
            return footprint
        }

        func result(render: OffscreenBenchResult) throws -> CellStreamingFlyBenchmarkResult {
            try validateCompletion()
            let counts = try validatedBuildCounts()
            let collision = try validatedCollisionBuildMetrics(
                runner: runner,
                configuration: configuration,
                expectedCount: counts.count
            )
            let actors = try validatedActorBuildMetrics(
                runner: runner,
                configuration: configuration
            )
            let unloaded = initialResidents.subtracting(streamer.residentCoordinates).count
            guard unloaded > 0 else {
                throw CellStreamingFlyBenchmarkError.noCellsUnloaded
            }
            try validatePlateau()
            return CellStreamingFlyBenchmarkResult(
                render: render,
                settledFootprintsMB: settledFootprints,
                peakFootprintMB: peakFootprint,
                uniqueBuildCount: counts.count,
                unloadedCellCount: unloaded,
                finalResidentCellCount: streamer.residentCellCount,
                finalVoidCellCount: streamer.voidCellCount,
                footprintCapMB: configuration.footprintCapMB,
                collisionBuildAverageMS: collision.average,
                collisionBuildP95MS: collision.p95,
                collisionBuildMaximumMS: collision.maximum,
                collisionBuildBudgetMS: configuration.collisionBuildBudgetMS,
                collisionShapeCount: collision.shapes,
                collisionTriangleCount: collision.triangles,
                actorBuildAverageMS: actors.average,
                actorBuildP95MS: actors.p95,
                actorBuildMaximumMS: actors.maximum,
                actorBuildBudgetMS: configuration.actorBuildBudgetMS,
                actorDiscoveredCount: actors.discovered,
                actorRenderedCount: actors.rendered,
                actorDisabledSkipCount: actors.disabledSkips,
                actorFailureCount: actors.failures,
                actorCellReports: actors.cellReports
            )
        }

        private func moveOneSample() {
            currentPosition = segments[legIndex][sampleIndex]
            renderer.freeFlyCamera.position.x = currentPosition.x
            renderer.freeFlyCamera.position.y = currentPosition.y
            streamer.update(cameraPosition: currentPosition)
            sampleIndex += 1
            if sampleIndex == segments[legIndex].count {
                moving = false
            }
        }

        private func validateCompletion() throws {
            if let error = swapError.error {
                throw CellStreamingFlyBenchmarkError.sceneSwapFailed(error)
            }
            guard streamer.failedCellCount == 0 else {
                throw CellStreamingFlyBenchmarkError.cellBuildFailed(
                    count: streamer.failedCellCount
                )
            }
        }

        private func validatedBuildCounts() throws -> [CellCoordinate: Int] {
            let counts = runner.buildCountsSnapshot()
            let expected = CellStreamingFlyPath.expectedCells(
                start: configuration.start,
                radius: CellGridManager.defaultRadius
            )
            guard Set(counts.keys) == expected else {
                throw CellStreamingFlyBenchmarkError.unexpectedBuildSet(
                    expected: expected.count,
                    actual: counts.count
                )
            }
            let duplicates = counts.filter { $0.value != 1 }
            guard duplicates.isEmpty else {
                throw CellStreamingFlyBenchmarkError.duplicateBuilds(duplicates)
            }
            return counts
        }

        private func validatePlateau() throws {
            guard
                let initial = settledFootprints.first,
                let final = settledFootprints.last,
                final >= initial * 1.6
            else { return }
            throw CellStreamingFlyBenchmarkError.footprintDidNotPlateau(
                initial: initial,
                final: final
            )
        }
    }

    /// Metric validation lives in CellStreamingFlyBenchmarkMetrics.swift
    /// (file + type length limits); Driver hands in runner + configuration.
    private static func isSettled(_ streamer: CellStreamer) -> Bool {
        streamer.resolvedCellCount == streamer.desiredCellCount
            && streamer.inFlightCellCount == 0
            && streamer.pendingCompletionCount == 0
            && streamer.queuedRequestCount == 0
    }

    private static func checkedFootprint(capMB: Double) throws -> Double {
        guard let footprint = MemoryFootprint.physFootprintMB() else {
            throw CellStreamingFlyBenchmarkError.memoryMeasurementFailed
        }
        guard footprint < capMB else {
            throw CellStreamingFlyBenchmarkError.footprintExceeded(
                megabytes: footprint,
                cap: capMB
            )
        }
        return footprint
    }
}
