// Static collision integration into exterior/interior CellScene. Synthetic
// ESM + NIF bytes only; no game content.

import Metal
@testable import opensky
import simd
import Testing

extension CellSceneBuilderTests {
    @Test(.enabled(if: Self.hasDevice)) func buildsPlacedStaticCollisionBesideScene() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        let device = try #require(Self.device)
        let builder = try makeBuilder(
            pluginData: plugin(
                temporaryRefs: refrRecord(
                    formID: 0x200,
                    base: 0x100,
                    position: SIMD3(100, 200, 300),
                    scale: 2
                ) + refrRecord(
                    formID: 0x201,
                    base: 0x100,
                    position: SIMD3(-100, -200, -300)
                ),
                statRecords: statRecord(formID: 0x100, modelPath: "arch\\solid.nif")
            ),
            device: device
        )
        let scene = try builder.buildScene(
            worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2
        )
        let collision = scene.staticCollision
        #expect(collision.stats.modelReferenceCount == 2)
        #expect(collision.stats.collisionModelReferenceCount == 2)
        #expect(collision.stats.shapeCount == 2)
        #expect(collision.stats.triangleCount == 0)
        #expect(collision.stats.loadFailureCount == 0)
        #expect(collision.indexNodeCount == 1)
        #expect(builder.collisionModels?.loadedCount == 1)
        let shape = try #require(collision.shapes.first(where: {
            $0.reference == FormID(0x200)
        }))
        let scale = NIFCollisionModel.havokToEngineScale
        #expect(abs(shape.bounds.min.x - (100 - 2 * scale)) < 0.01)
        #expect(abs(shape.bounds.max.z - (300 + 2 * scale)) < 0.01)
    }

    func collisionRenderNIF() -> Data {
        NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 2),
                children: [1]
            )),
            .init("BSTriShape", NIFFixture.bsTriShape(
                attributes: Self.staticAttributes,
                strideDwords: Self.staticStrideDwords,
                vertexRecords: [
                    SIMD3<Float>(0, 0, 0),
                    SIMD3<Float>(1, 0, 0),
                    SIMD3<Float>(0, 1, 1)
                ].map(vertexRecord(position:)),
                triangles: [0, 1, 2]
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 3)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 4)),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1))
        ])
    }
}
