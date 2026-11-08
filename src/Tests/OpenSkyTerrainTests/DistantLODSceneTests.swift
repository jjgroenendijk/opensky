// A built distant ring changed after the build: a brightness curve, water, and the
// full models of large and Is Full LOD references, which keep the ring's counts.

@testable import OpenSkyFormatsCore
@testable import OpenSkyRenderCore
@testable import OpenSkyRendering
@testable import OpenSkyTerrain
import Testing

struct DistantLODSceneTests {
    private func ring() -> DistantLODScene {
        var scene = DistantLODScene(
            renderScene: RenderScene(instances: []),
            assets: CellAssets(meshKeys: ["a.nif"], textureKeys: ["a.dds"]),
            blockCount: 4,
            missingBlockCount: 1,
            treeBlockCount: 2,
            largeReferenceCells: [CellCoordinate(x: 1, y: 2)],
            largeReferenceCount: 3,
            hiddenLargeReferenceSegments: 5
        )
        scene.generatedTerrainBlockCount = 2
        return scene
    }

    @Test func aBrightnessCurveKeepsTheCounts() {
        let curve = TerrainLODBrightness(gain: 2, exponent: 1.5)
        let scene = ring().with(terrainLODBrightness: curve)
        #expect(scene.renderScene.terrainLODBrightness == curve)
        #expect(scene.blockCount == 4)
        #expect(scene.missingBlockCount == 1)
        #expect(scene.treeBlockCount == 2)
        #expect(scene.largeReferenceCount == 3)
        #expect(scene.hiddenLargeReferenceSegments == 5)
        #expect(scene.generatedTerrainBlockCount == 2)
        #expect(scene.assets.meshKeys == ["a.nif"])
    }

    @Test func noWaterAndNoReferencesChangeNothing() {
        let scene = ring().adding(water: [])
        #expect(scene.renderScene.water.isEmpty)
        #expect(scene.largeReferenceCells == [CellCoordinate(x: 1, y: 2)])
        let none = CellAssets(meshKeys: ["b.nif"], textureKeys: [])
        #expect(ring().adding(largeReferences: [], assets: none).assets.meshKeys == ["a.nif"])
        #expect(ring().adding(fullLODReferences: [], assets: none).fullLODReferenceCount == 0)
    }
}
