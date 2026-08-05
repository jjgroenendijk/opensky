// `collision`: production NIF collision sweep for every unique model path in
// one exterior cell. Engine owns discovery/decoding/acceptance; CLI owns only
// option parsing and stable diagnostics.

import Foundation
import Metal

enum CollisionCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let worldspace = try scanner.option("--worldspace")
            ?? FirstRenderCell.worldspaceEditorID
        let gridX = try int32(scanner.option("--x"), name: "--x") ?? FirstRenderCell.gridX
        let gridY = try int32(scanner.option("--y"), name: "--y") ?? FirstRenderCell.gridY
        let radius = try gridRadius(scanner.option("--radius"))
        try scanner.finish()

        let esm = try context.loadSkyrimESM()
        let materials = MaterialTypeIndex(file: esm)
        let result = try NIFCollisionSweep.run(
            file: esm,
            fileSystem: context.makeFileSystem(),
            worldspaceEditorID: worldspace,
            gridX: gridX,
            gridY: gridY
        )
        print("[INFO] collision sweep \(worldspace) (\(gridX),\(gridY)): "
            + "\(result.modelPaths.count) unique models")
        for report in result.reports {
            printReport(report, materials: materials)
        }
        print("[INFO] \(result.collisionBearingModelCount) collision-bearing models; "
            + (result.passesAcceptance ? "acceptance passed" : "acceptance failed"))
        guard result.passesAcceptance else {
            throw CLIError.failure("collision sweep found missing or unsupported geometry")
        }

        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }
        let builder = try RenderCommand.makeBuilder(context: context, device: device)
        try printGrid(CellCollisionGridProbe.run(
            builder: builder,
            worldspaceEditorID: worldspace,
            center: CellCoordinate(x: gridX, y: gridY),
            radius: radius
        ))
    }

    private static func printGrid(_ grid: CellCollisionGridResult) throws {
        for entry in grid.entries {
            let label = "cell (\(entry.coordinate.x),\(entry.coordinate.y))"
            guard let collision = entry.collision else {
                print("\(label): void")
                continue
            }
            let stats = collision.stats
            print(String(
                format: "\(label): %d shapes, %d triangles, %.2f ms, %.1f KiB",
                stats.shapeCount,
                stats.triangleCount,
                collision.buildDurationMS,
                Double(stats.estimatedBytes) / 1024
            ))
        }
        let stats = grid.stats
        print("[INFO] collision grid: \(grid.entries.count) cells (\(grid.voidCellCount) void), "
            + "\(stats.shapeCount) shapes, \(stats.triangleCount) triangles, "
            + "\(stats.filteredBodyCount) filtered bodies, "
            + "\(stats.loadFailureCount) load failures")
        guard grid.passesAcceptance else {
            throw CLIError.failure("collision grid found load, decode, or unsupported failures")
        }
    }

    private static func int32(_ value: String?, name: String) throws -> Int32? {
        guard let value else { return nil }
        guard let parsed = Int32(value) else {
            throw CLIError.usage("\(name) expects an integer, got \(value)")
        }
        return parsed
    }

    private static func gridRadius(_ value: String?) throws -> Int32 {
        guard let value else { return 0 }
        guard let radius = Int32(value), (0 ... 10).contains(radius) else {
            throw CLIError.usage("--radius expects an integer (0-10), got \(value)")
        }
        return radius
    }

    private static func printReport(
        _ report: NIFCollisionAssetReport,
        materials: MaterialTypeIndex
    ) {
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
        print("  materials: \(materialSummary(report.shapeMaterials, in: materials))")
        print("  collision bounds: \(bounds(report.collisionBounds))")
        print("  render bounds: \(bounds(report.renderBounds))")
    }

    /// Each Havok material the model's shapes name, resolved to the MATT it
    /// hashes to (issue #358). A value no MATT hashes to prints raw, so an
    /// unresolvable surface is visible rather than silently absent.
    private static func materialSummary(
        _ counts: [UInt32: Int],
        in materials: MaterialTypeIndex
    ) -> String {
        guard !counts.isEmpty else { return "none" }
        return counts.sorted { $0.key < $1.key }
            .map { value, count in
                let name = materials.material(forHavokMaterial: value)
                    .map(materials.describe) ?? "unresolved \(value)"
                return "\(name) \(count)"
            }
            .joined(separator: ", ")
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
