// Reason-tagged production fly-gate failures.

import Foundation

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
    case actorAnimationAccountingMismatch(
        coordinate: CellCoordinate, rendered: Int, explained: Int
    )
    case actorAnimationFailureUnexplained(
        coordinate: CellCoordinate, failures: Int, reasons: Int
    )
    case animationUpdateExceeded(average: Double, p95: Double, budget: Double)
    case shadowUpdateExceeded(average: Double, p95: Double, budget: Double)
    case weatherUnavailable
    case rainWeatherUnavailable
    case noWeatherRendered
    case noActorAnimationUpdated
    case noParticlesRendered
    case noPrecipitationRendered
    case noShadowsRendered
    case noGrassRendered
    case grassBudgetExceeded(dropped: Int)
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
        case let .actorAnimationAccountingMismatch(coordinate, rendered, explained):
            "cell (\(coordinate.x),\(coordinate.y)) animation accounting not exact: "
                + "\(rendered) rendered vs \(explained) explained"
        case let .actorAnimationFailureUnexplained(coordinate, failures, reasons):
            "cell (\(coordinate.x),\(coordinate.y)) has \(failures) static actors "
                + "but only \(reasons) reasons"
        case let .animationUpdateExceeded(average, p95, budget):
            String(
                format: "animation update avg %.2f ms / p95 %.2f ms exceeded %.2f ms budget",
                average, p95, budget
            )
        case let .shadowUpdateExceeded(average, p95, budget):
            String(
                format: "shadow update avg %.2f ms / p95 %.2f ms exceeded %.2f ms budget",
                average, p95, budget
            )
        case .weatherUnavailable: "fly path has no data-driven weather runtime"
        case .rainWeatherUnavailable: "fly path weather store has no rainy acceptance preset"
        case .noWeatherRendered: "fly path rendered no selected weather"
        case .noActorAnimationUpdated: "fly path updated no animated actor bones"
        case .noParticlesRendered: "fly path rendered no live world particles"
        case .noPrecipitationRendered: "fly path rendered no live rain particles"
        case .noShadowsRendered: "fly path rendered no sun-shadow casters"
        case .noGrassRendered: "fly path rendered no grass instances"
        case let .grassBudgetExceeded(dropped):
            "grass per-frame budget dropped up to \(dropped) mesh instances"
        case .noCellsUnloaded: "cross-cell path did not unload any initially resident cells"
        }
    }

    private static func describe(_ counts: [CellCoordinate: Int]) -> String {
        counts
            .sorted { ($0.key.x, $0.key.y) < ($1.key.x, $1.key.y) }
            .map { "(\($0.key.x),\($0.key.y))=\($0.value)" }
            .joined(separator: ", ")
    }
}
