// Real exterior cell selection and boundary direction for issue #401's
// env-gated dynamic-body probe. The test itself stays with its suite.

@testable import opensky
import simd

extension DynamicBodyRealDataTests {
    struct ExteriorPair {
        let sourceCoordinate: CellCoordinate
        let destinationCoordinate: CellCoordinate
        let source: CellScene
        let destination: CellScene
    }

    static func exteriorPair(builder: CellSceneBuilder) throws -> ExteriorPair {
        let center = CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY)
        for yOffset in -2 ... 2 {
            for xOffset in -2 ... 2 {
                let coordinate = CellCoordinate(
                    x: center.x + Int32(xOffset), y: center.y + Int32(yOffset)
                )
                guard
                    let source = try? builder.buildScene(
                        worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
                        gridX: coordinate.x,
                        gridY: coordinate.y
                    ),
                    !source.dynamicBodies.isEmpty
                else { continue }
                for neighbour in neighbours(of: coordinate, body: source.dynamicBodies[0]) {
                    guard
                        let destination = try? builder.buildScene(
                            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
                            gridX: neighbour.x,
                            gridY: neighbour.y
                        ) else { continue }
                    return ExteriorPair(
                        sourceCoordinate: coordinate,
                        destinationCoordinate: neighbour,
                        source: source,
                        destination: destination
                    )
                }
            }
        }
        throw CellSceneError.cellNotFound(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: center.x,
            gridY: center.y
        )
    }

    private static func neighbours(
        of cell: CellCoordinate,
        body: DynamicBodyPlacement
    ) -> [CellCoordinate] {
        let lowX = Float(cell.x) * TerrainMeshBuilder.cellSize
        let lowY = Float(cell.y) * TerrainMeshBuilder.cellSize
        let choices: [(distance: Float, cell: CellCoordinate)] = [
            (
                lowX + TerrainMeshBuilder.cellSize - body.originPosition.x,
                .init(x: cell.x + 1, y: cell.y)
            ),
            (body.originPosition.x - lowX, .init(x: cell.x - 1, y: cell.y)),
            (
                lowY + TerrainMeshBuilder.cellSize - body.originPosition.y,
                .init(x: cell.x, y: cell.y + 1)
            ),
            (body.originPosition.y - lowY, .init(x: cell.x, y: cell.y - 1))
        ]
        return choices.sorted { $0.distance < $1.distance }.map(\.cell)
    }

    static func direction(
        from source: CellCoordinate,
        to destination: CellCoordinate
    ) -> SIMD3<Float> {
        simd_normalize(SIMD3(
            Float(destination.x - source.x), Float(destination.y - source.y), 0
        ))
    }

    static func push(
        body key: ReferenceKey,
        direction: SIMD3<Float>,
        world: inout DynamicBodyWorld
    ) {
        guard let body = world.body(for: key) else { return }
        let capsule = PlayerCapsule.standard
        let reach = capsule.radius + body.definition.boundingRadius - 1
        let feet = body.position - direction * reach - SIMD3(0, 0, capsule.height / 2)
        world.push(capsule: capsule, feetPosition: feet, velocity: direction * 3000)
    }

    static func drawCount(reference: FormID, in scene: RenderScene) -> Int {
        (scene.opaque + scene.alphaTested).flatMap(\.instances)
            .count { $0.referenceFormID == reference.rawValue }
    }
}
