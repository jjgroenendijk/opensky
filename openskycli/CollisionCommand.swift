// `collision`: production NIF collision sweep for every unique model path in
// one exterior cell. Engine owns discovery/decoding/acceptance; CLI owns only
// option parsing and stable diagnostics.

import Foundation

enum CollisionCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let worldspace = try scanner.option("--worldspace")
            ?? FirstRenderCell.worldspaceEditorID
        let gridX = try int32(scanner.option("--x"), name: "--x") ?? FirstRenderCell.gridX
        let gridY = try int32(scanner.option("--y"), name: "--y") ?? FirstRenderCell.gridY
        try scanner.finish()

        let result = try NIFCollisionSweep.run(
            file: context.loadSkyrimESM(),
            fileSystem: context.makeFileSystem(),
            worldspaceEditorID: worldspace,
            gridX: gridX,
            gridY: gridY
        )
        print("[INFO] collision sweep \(worldspace) (\(gridX),\(gridY)): "
            + "\(result.modelPaths.count) unique models")
        for report in result.reports {
            printReport(report)
        }
        print("[INFO] \(result.collisionBearingModelCount) collision-bearing models; "
            + (result.passesAcceptance ? "acceptance passed" : "acceptance failed"))
        guard result.passesAcceptance else {
            throw CLIError.failure("collision sweep found missing or unsupported geometry")
        }
    }

    private static func int32(_ value: String?, name: String) throws -> Int32? {
        guard let value else { return nil }
        guard let parsed = Int32(value) else {
            throw CLIError.usage("\(name) expects an integer, got \(value)")
        }
        return parsed
    }

    private static func printReport(_ report: NIFCollisionAssetReport) {
        print("model \(report.path)")
        if let failure = report.loadFailure {
            print("  load failure: \(failure)")
            return
        }
        print("  roots \(report.collisionRootCount), bodies \(report.bodyCount), "
            + "shapes \(report.shapeCount), triangles \(report.triangleCount), "
            + "filtered bodies \(report.filteredBodyCount)")
        print("  unsupported: \(histogram(report.unsupportedReachableBlocks))")
        print("  decode failures: \(report.decodeFailures.count)")
        for failure in report.decodeFailures {
            print("    block \(failure.block): \(failure.message)")
        }
        print("  collision bounds: \(bounds(report.collisionBounds))")
        print("  render bounds: \(bounds(report.renderBounds))")
    }

    private static func histogram(_ values: [String: Int]) -> String {
        guard !values.isEmpty else { return "none" }
        return values.sorted(by: { $0.key < $1.key })
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
    }

    private static func bounds(_ value: ModelBounds?) -> String {
        guard let value else { return "none" }
        return "min (\(format(value.min.x)), \(format(value.min.y)), \(format(value.min.z))) "
            + "max (\(format(value.max.x)), \(format(value.max.y)), \(format(value.max.z)))"
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.3f", value)
    }
}
