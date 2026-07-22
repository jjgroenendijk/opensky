// Scripted cross-cell streaming benchmark (todo 3.2 verification). Drives a
// deterministic east-then-north camera path through the same CellStreamer,
// Renderer, serial builder, scene swaps, and cache eviction used by the app.
// One reused offscreen target + 100 Hz pacing keep the verifier bounded while
// physical-footprint, settlement, unload, and duplicate-build gates make the
// milestone claims repeatable from openskycli.

import Foundation
import simd

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
    let animated: Int
    let animationFailures: Int
    let animationFailureReasons: [String]
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
    let actorAnimatedCount: Int
    let actorAnimationFailureCount: Int
    let animationUpdateBudgetMS: Double
    let shadowUpdateBudgetMS: Double
    let weatherName: String
    let windSpeed: Float
    let animationUpdatedBoneCount: Int
    let particleSystemCount: Int
    let particleLiveCount: Int
    let rainLiveCount: Int
    /// Peak sun-shadow culling/draw accounting across streamed frames.
    let shadowDrawStats: ShadowDrawStats
    /// Peak per-field grass accounting sampled across rendered fly frames.
    let grassDrawStats: GrassDrawStats
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
    let animationUpdateBudgetMS: Double
    let shadowUpdateBudgetMS: Double
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
        guard let weather = (provider as? WeatherProviding)?.weatherSystem else {
            throw CellStreamingFlyBenchmarkError.weatherUnavailable
        }
        guard let rain = weather.store.weather(for: .rain) else {
            throw CellStreamingFlyBenchmarkError.rainWeatherUnavailable
        }
        renderer.weather = weather
        renderer.timeOfDay = 13
        weather.forceWeather(rain.formID, transition: .instant)
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
        private var environmentEvidence = LivingEnvironmentFlyEvidence()
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
            environmentEvidence.capture(renderer)
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
            environmentEvidence.capture(renderer)
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
            try validateUpdateBudgets(render)
            let environment = try environmentEvidence.validated(
                animatedActorCount: actors.animated
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
                actorAnimatedCount: actors.animated,
                actorAnimationFailureCount: actors.animationFailures,
                animationUpdateBudgetMS: configuration.animationUpdateBudgetMS,
                shadowUpdateBudgetMS: configuration.shadowUpdateBudgetMS,
                weatherName: environment.weatherName ?? "selected rain",
                windSpeed: environment.windSpeed,
                animationUpdatedBoneCount: environment.animationUpdatedBoneCount,
                particleSystemCount: environment.particleSystemCount,
                particleLiveCount: environment.particleLiveCount,
                rainLiveCount: environment.rainLiveCount,
                shadowDrawStats: environment.shadowDrawStats,
                grassDrawStats: environment.grassDrawStats,
                actorCellReports: actors.cellReports
            )
        }

        /// Per-frame CPU update gates: animation (sample/compose/palette) then
        /// shadow (cascade fit + caster culling + encode) must each hold avg AND
        /// p95 within budget, mirroring the collision/actor build-latency gates.
        private func validateUpdateBudgets(_ render: OffscreenBenchResult) throws {
            guard
                render.animationAverageMS <= configuration.animationUpdateBudgetMS,
                render.animationPercentileMS(95) <= configuration.animationUpdateBudgetMS
            else {
                throw CellStreamingFlyBenchmarkError.animationUpdateExceeded(
                    average: render.animationAverageMS,
                    p95: render.animationPercentileMS(95),
                    budget: configuration.animationUpdateBudgetMS
                )
            }
            guard
                render.shadowAverageMS <= configuration.shadowUpdateBudgetMS,
                render.shadowPercentileMS(95) <= configuration.shadowUpdateBudgetMS
            else {
                throw CellStreamingFlyBenchmarkError.shadowUpdateExceeded(
                    average: render.shadowAverageMS,
                    p95: render.shadowPercentileMS(95),
                    budget: configuration.shadowUpdateBudgetMS
                )
            }
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
}

@MainActor
private func isSettled(_ streamer: CellStreamer) -> Bool {
    streamer.resolvedCellCount == streamer.desiredCellCount
        && streamer.inFlightCellCount == 0
        && streamer.pendingCompletionCount == 0
        && streamer.queuedRequestCount == 0
}

private func checkedFootprint(capMB: Double) throws -> Double {
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
