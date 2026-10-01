import Metal
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

extension PlayerBodyFixture {
    /// The assembled player and one exterior cell of the install to stand in.
    struct Stage {
        let device: any MTLDevice
        let root: GameDataRoot
        let assembled: Assembled
        let scene: CellScene
        let bounds: (min: SIMD3<Float>, max: SIMD3<Float>)

        /// Where the locomotion drive starts on the real terrain.
        func terrainStart() throws -> SIMD3<Float> {
            let terrain = try #require(LocomotionRealTerrain.terrainField(root: root))
            return LocomotionRealTerrain.startPosition(on: terrain)
        }

        @MainActor
        func renderer() throws -> Renderer {
            try FirstPersonRenderRealDataTests.renderer(
                device: device, scene: scene, bounds: bounds
            )
        }
    }

    @MainActor
    static func stage(
        gridX: Int32 = FirstRenderCell.gridX,
        gridY: Int32 = FirstRenderCell.gridY
    ) throws -> Stage {
        let device = try #require(RealDataEnvironment.device)
        let root = try #require(RealDataEnvironment.dataRoot)
        let assembled = try assemble(device: device, root: root)
        let scene = try assembled.builder.buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID, gridX: gridX, gridY: gridY
        )
        let bounds = try #require(scene.bounds, "no cell bounds — nothing drew")
        return Stage(
            device: device, root: root, assembled: assembled, scene: scene, bounds: bounds
        )
    }
}
