// Scripted cross-cell streaming benchmark: a fixed east-then-north camera path through
// the app's streamer, renderer and eviction. One offscreen target and 100 Hz pacing keep
// it bounded; footprint, settlement, unload and duplicate-build gates make it repeatable.

import Foundation
import OpenSkyCells
import OpenSkyDiagnostics
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyTerrain
import OpenSkyWeather
import simd

/// Deterministic path: launch center -> one cell east -> one cell north.
/// Each leg samples a linear camera flight; every waypoint then waits for its
/// full 5x5 grid to settle before continuing.
nonisolated public enum CellStreamingFlyPath: Sendable {
    public static func waypoints(start: CellCoordinate) -> [CellCoordinate] {
        [
            start,
            CellCoordinate(x: start.x + 1, y: start.y),
            CellCoordinate(x: start.x + 1, y: start.y + 1)
        ]
    }

    public static func positions(
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

    public static func expectedCells(start: CellCoordinate, radius: Int32) -> Set<CellCoordinate> {
        waypoints(start: start).reduce(into: Set<CellCoordinate>()) { result, waypoint in
            let manager = CellGridManager(
                initialPosition: CellGridManager.cellCenter(of: waypoint),
                radius: radius
            )
            result.formUnion(manager.desiredCells)
        }
    }
}

nonisolated public struct CellStreamingFlyBenchmarkResult: Sendable {
    public let render: OffscreenBenchResult
    public let actorAnimatedCount: Int
    public let animationUpdateBudgetMS: Double
    public let shadowUpdateBudgetMS: Double
    public let audioUpdateBudgetMS: Double
    public let scriptUpdateBudgetMS: Double
    public let weatherName: String
    public let animationUpdatedBoneCount: Int
    public let particleSystemCount: Int
    public let particleLiveCount: Int
    public let rainLiveCount: Int
    /// Peak sun-shadow culling/draw accounting across streamed frames.
    public let shadowDrawStats: ShadowDrawStats
    /// Peak per-field grass accounting sampled across rendered fly frames.
    public let grassDrawStats: GrassDrawStats
    /// Cells the fly built actors for.
    public let actorCellCount: Int
}

nonisolated public struct CellStreamingFlyBenchmarkConfiguration: Sendable {
    public let start: CellCoordinate
    public let size: (width: Int, height: Int)
    public let maxFrames: Int
    public let footprintCapMB: Double
    public let collisionBuildBudgetMS: Double
    public let actorBuildBudgetMS: Double
    public let animationUpdateBudgetMS: Double
    public let shadowUpdateBudgetMS: Double
    public let audioUpdateBudgetMS: Double
    public let scriptUpdateBudgetMS: Double
    public var samplesPerLeg = 60

    public init(
        start: CellCoordinate,
        size: (width: Int, height: Int),
        maxFrames: Int,
        footprintCapMB: Double,
        collisionBuildBudgetMS: Double,
        actorBuildBudgetMS: Double,
        animationUpdateBudgetMS: Double,
        shadowUpdateBudgetMS: Double,
        audioUpdateBudgetMS: Double,
        scriptUpdateBudgetMS: Double,
        samplesPerLeg: Int = 60
    ) {
        self.start = start
        self.size = size
        self.maxFrames = maxFrames
        self.footprintCapMB = footprintCapMB
        self.collisionBuildBudgetMS = collisionBuildBudgetMS
        self.actorBuildBudgetMS = actorBuildBudgetMS
        self.animationUpdateBudgetMS = animationUpdateBudgetMS
        self.shadowUpdateBudgetMS = shadowUpdateBudgetMS
        self.audioUpdateBudgetMS = audioUpdateBudgetMS
        self.scriptUpdateBudgetMS = scriptUpdateBudgetMS
        self.samplesPerLeg = samplesPerLeg
    }
}

@MainActor
public enum CellStreamingFlyBenchmark {
    private final class SceneSwapErrorBox {
        var error: (any Error)?
    }

    public static func run(
        gameSession: GameSession,
        provider: sending any CellSceneProvider,
        lodPrebuild: DistantLODPrebuild? = nil,
        weather: WeatherSystem?,
        configuration: CellStreamingFlyBenchmarkConfiguration
    ) throws -> CellStreamingFlyBenchmarkResult {
        let renderer = gameSession.renderer
        guard let weather else {
            throw CellStreamingFlyBenchmarkError.weatherUnavailable
        }
        guard let rain = weather.store.weather(for: .rain) else {
            throw CellStreamingFlyBenchmarkError.rainWeatherUnavailable
        }
        gameSession.weather = weather
        gameSession.timeOfDay = 13
        weather.forceWeather(rain.formID, transition: .instant)
        let driver = Driver(
            gameSession: gameSession,
            provider: provider,
            lodPrebuild: lodPrebuild,
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
        private let gameSession: GameSession

        private let runner: SerialCellBuildRunner
        private let streamer: CellStreamer
        private let swapError: SceneSwapErrorBox
        private let configuration: CellStreamingFlyBenchmarkConfiguration
        private let segments: [[SIMD3<Float>]]
        private var legIndex = -1 // -1 = launch-grid settlement
        private var sampleIndex = 0
        private var moving = false
        private var settledFootprints: [Double] = []
        private var environmentEvidence = LivingEnvironmentFlyEvidence()
        private var initialResidents = Set<CellCoordinate>()
        private var currentPosition: SIMD3<Float>

        init(
            gameSession: GameSession,
            provider: sending any CellSceneProvider,
            lodPrebuild: DistantLODPrebuild?,
            configuration: CellStreamingFlyBenchmarkConfiguration
        ) {
            self.gameSession = gameSession
            self.configuration = configuration
            let renderer = gameSession.renderer
            runner = SerialCellBuildRunner(provider: provider, lodPrebuild: lodPrebuild)
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
            environmentEvidence.capture(gameSession)
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

        private func validateUnloads() throws {
            guard !initialResidents.subtracting(streamer.residentCoordinates).isEmpty else {
                throw CellStreamingFlyBenchmarkError.noCellsUnloaded
            }
        }

        private func sampleFootprint() throws -> Double {
            try checkedFootprint(capMB: configuration.footprintCapMB)
        }

        func result(render: OffscreenBenchResult) throws -> CellStreamingFlyBenchmarkResult {
            environmentEvidence.capture(gameSession)
            try validateCompletion()
            let counts = try validatedBuildCounts()
            try validateCollisionBuildMetrics(
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
            try validateUnloads()
            try validatePlateau()
            return CellStreamingFlyBenchmarkResult(
                render: render,
                actorAnimatedCount: actors.animated,
                animationUpdateBudgetMS: configuration.animationUpdateBudgetMS,
                shadowUpdateBudgetMS: configuration.shadowUpdateBudgetMS,
                audioUpdateBudgetMS: configuration.audioUpdateBudgetMS,
                scriptUpdateBudgetMS: configuration.scriptUpdateBudgetMS,
                weatherName: environment.weatherName ?? "selected rain",
                animationUpdatedBoneCount: environment.animationUpdatedBoneCount,
                particleSystemCount: environment.particleSystemCount,
                particleLiveCount: environment.particleLiveCount,
                rainLiveCount: environment.rainLiveCount,
                shadowDrawStats: environment.shadowDrawStats,
                grassDrawStats: environment.grassDrawStats,
                actorCellCount: actors.cellCount
            )
        }

        /// Per-frame CPU update gates: animation (sample/compose/palette), then
        /// shadow (cascade fit + caster culling + encode), audio (listener pose
        /// + engine tick + music director), and script VM must each hold avg
        /// AND p95 within budget, mirroring the build-latency gates.
        private func validateUpdateBudgets(_ render: OffscreenBenchResult) throws {
            try validatedFlyUpdateBudgets(render: render, configuration: configuration)
        }

        private func moveOneSample() {
            currentPosition = segments[legIndex][sampleIndex]
            gameSession.freeFlyCamera.position.x = currentPosition.x
            gameSession.freeFlyCamera.position.y = currentPosition.y
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

/// The distant ring counts too, as on the start screen, so every run measures
/// the same scene swaps however fast its cells build.
@MainActor
private func isSettled(_ streamer: CellStreamer) -> Bool {
    streamer.startAreaReady
        && streamer.resolvedCellCount == streamer.desiredCellCount
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
