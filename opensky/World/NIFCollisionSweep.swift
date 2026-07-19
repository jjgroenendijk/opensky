// Production collision probe over model paths resolved from one exterior
// cell. Reads through VirtualFileSystem; reports each asset independently so
// one malformed/modded NIF cannot hide coverage for sibling assets.

import Foundation

nonisolated struct NIFCollisionAssetReport {
    let path: String
    let collisionRootCount: Int
    let bodyCount: Int
    let shapeCount: Int
    let triangleCount: Int
    let filteredBodyCount: Int
    let unsupportedReachableBlocks: [String: Int]
    let decodeFailures: [NIFCollisionFailure]
    let collisionBounds: ModelBounds?
    let renderBounds: ModelBounds?
    let loadFailure: String?

    var passesAcceptance: Bool {
        loadFailure == nil
            && unsupportedReachableBlocks.isEmpty
            && decodeFailures.isEmpty
            && (collisionRootCount == 0 || shapeCount > 0)
    }
}

nonisolated struct NIFCollisionSweepResult {
    let modelPaths: [String]
    let reports: [NIFCollisionAssetReport]

    var passesAcceptance: Bool {
        !reports.isEmpty && reports.allSatisfy(\.passesAcceptance)
    }

    var collisionBearingModelCount: Int {
        reports.count(where: { $0.collisionRootCount > 0 })
    }
}

nonisolated enum NIFCollisionSweep {
    static func run(
        file: ESMFile,
        fileSystem: VirtualFileSystem,
        worldspaceEditorID: String,
        gridX: Int32,
        gridY: Int32
    ) throws -> NIFCollisionSweepResult {
        let paths = try ExteriorCellModelCatalog(file: file).modelPaths(
            worldspaceEditorID: worldspaceEditorID,
            gridX: gridX,
            gridY: gridY
        )
        return NIFCollisionSweepResult(
            modelPaths: paths,
            reports: paths.map { inspect(path: $0, fileSystem: fileSystem) }
        )
    }

    private static func inspect(
        path: String,
        fileSystem: VirtualFileSystem
    ) -> NIFCollisionAssetReport {
        do {
            let file = try NIFFile(data: fileSystem.contents(forPath: path))
            let collision = file.collisionModel()
            let renderBounds = try? ModelBounds.containing(model: file.model())
            return NIFCollisionAssetReport(
                path: path,
                collisionRootCount: file.blocks.count(where: {
                    $0.typeName == "bhkCollisionObject"
                }),
                bodyCount: collision.bodies.count,
                shapeCount: collision.shapeCount,
                triangleCount: collision.triangleCount,
                filteredBodyCount: collision.filteredBodyCount,
                unsupportedReachableBlocks: collision.unsupportedReachableBlocks,
                decodeFailures: collision.decodeFailures,
                collisionBounds: collision.bounds,
                renderBounds: renderBounds,
                loadFailure: nil
            )
        } catch {
            return NIFCollisionAssetReport(
                path: path,
                collisionRootCount: 0,
                bodyCount: 0,
                shapeCount: 0,
                triangleCount: 0,
                filteredBodyCount: 0,
                unsupportedReachableBlocks: [:],
                decodeFailures: [],
                collisionBounds: nil,
                renderBounds: nil,
                loadFailure: String(describing: error)
            )
        }
    }
}
