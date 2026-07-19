// M4.5 production acceptance: fixed-step walk controller + live streaming +
// door transitions over one observed real-install route. CLI owns printing;
// this shared driver owns behavior and gates.

import Foundation
import simd

nonisolated enum CellStreamingWalkBenchmarkError: LocalizedError {
    case sceneSwapFailed(any Error)
    case cellBuildFailed(Int)
    case doorBuildFailed(Int)
    case noStartGround(SIMD2<Float>)
    case routeTimedOut(String, SIMD3<Float>)
    case fallThrough(String, SIMD3<Float>)
    case unresolvedPenetration(String, SIMD3<Float>)
    case wrongDoor(expected: FormID, actual: FormID?)
    case wrongDestination(String)
    case stepNotClimbed(Float)
    case interiorNotCrossed(Float)

    var errorDescription: String? {
        switch self {
        case let .sceneSwapFailed(error):
            "walk-path scene swap failed: \(String(describing: error))"
        case let .cellBuildFailed(count):
            "walk path ended with \(count) failed cell builds"
        case let .doorBuildFailed(count):
            "walk path ended with \(count) failed door builds"
        case let .noStartGround(position):
            "walk path has no terrain at start \(position)"
        case let .routeTimedOut(phase, position):
            "walk path timed out during \(phase) at \(position)"
        case let .fallThrough(phase, position):
            "walk path fell through during \(phase) at \(position)"
        case let .unresolvedPenetration(phase, position):
            "walk path left unresolved penetration during \(phase) at \(position)"
        case let .wrongDoor(expected, actual):
            "walk path selected door \(actual?.description ?? "none"); expected \(expected)"
        case let .wrongDestination(reason):
            "walk path reached wrong destination: \(reason)"
        case let .stepNotClimbed(gain):
            String(format: "exterior stair gain %.2f did not reach acceptance threshold", gain)
        case let .interiorNotCrossed(distance):
            String(format: "interior floor crossing %.2f units was too short", distance)
        }
    }
}

nonisolated struct CellStreamingWalkBenchmarkConfiguration {
    let size: (width: Int, height: Int)
    let maxFrames: Int
    let worldspaceEditorID: String
}

nonisolated struct CellStreamingWalkBenchmarkResult {
    let render: OffscreenBenchResult
    let physicsRender: OffscreenBenchResult
    let routeFrameCount: Int
    let exteriorStepGain: Float
    let interiorDistance: Float
    let finalFeetPosition: SIMD3<Float>
}

@MainActor
enum CellStreamingWalkBenchmark {
    static func run(
        renderer: Renderer,
        provider: any CellSceneProvider,
        configuration: CellStreamingWalkBenchmarkConfiguration
    ) throws -> CellStreamingWalkBenchmarkResult {
        let driver = CellStreamingWalkDriver(
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
}
