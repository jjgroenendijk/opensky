// Every bhk shape kind keeps the Havok material it names (issue #358), and the
// two block kinds that store several materials split into one shape per
// material. Synthetic in-code payloads only; layouts from NifTools nif.xml.

import Foundation
@testable import opensky
import simd
import Testing

struct NIFCollisionMaterialTests {
    /// `SKY_HAV_MAT_SNOW` and `SKY_HAV_MAT_STONE` from nif.xml — two values a
    /// footstep would resolve to different sounds.
    private static let snow: UInt32 = 398_949_039
    private static let stone: UInt32 = 3_741_512_247

    @Test func primitiveShapesKeepTheirMaterial() throws {
        let shapes = try [
            ("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1, material: Self.snow)),
            (
                "bhkBoxShape",
                NIFCollisionFixture.box(SIMD3(repeating: 1), material: Self.snow)
            ),
            (
                "bhkCapsuleShape",
                NIFCollisionFixture.capsule(
                    first: .zero,
                    second: SIMD3(0, 0, 1),
                    radius: 1,
                    material: Self.snow
                )
            ),
            (
                "bhkConvexVerticesShape",
                NIFCollisionFixture.convexVertices(
                    [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)],
                    material: Self.snow
                )
            )
        ].map { try Self.shape(type: $0.0, payload: $0.1) }

        #expect(shapes.allSatisfy { $0.material == Self.snow })
    }

    @Test func geometryStillDecodesAroundTheMaterialField() throws {
        let shape = try Self.shape(
            type: "bhkBoxShape",
            payload: NIFCollisionFixture.box(SIMD3(1, 2, 3), material: Self.stone)
        )

        guard case let .box(halfExtents) = shape.geometry else {
            Issue.record("expected a box")
            return
        }
        let scale = NIFCollisionModel.havokToEngineScale
        #expect(abs(halfExtents.x - scale) < 0.01)
        #expect(abs(halfExtents.y - scale * 2) < 0.01)
        #expect(abs(halfExtents.z - scale * 3) < 0.01)
    }

    @Test func triStripShapeCarriesItsMaterialToEveryStripsBlock() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init(
                "bhkNiTriStripsShape",
                NIFCollisionFixture.niTriStripsShape(dataRef: 4, material: Self.stone)
            ),
            .init("NiTriStripsData", NIFCollisionFixture.niTriStripsData())
        ]))

        let shapes = try #require(file.collisionModel().bodies.first).shapes
        #expect(shapes.map(\.material) == [Self.stone])
    }

    @Test func packedStripsTakeTheirMaterialFromTheSubShape() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init("bhkPackedNiTriStripsShape", NIFCollisionFixture.packedShape(dataRef: 4)),
            .init("hkPackedNiTriStripsData", NIFCollisionFixture.packedData(material: Self.snow))
        ]))

        let shapes = try #require(file.collisionModel().bodies.first).shapes
        #expect(shapes.map(\.material) == [Self.snow])
        #expect(file.collisionModel().triangleCount == 1)
    }

    /// The compressed mesh is the interesting one: its big triangles and its
    /// chunk index the same table, so a mesh whose two halves are different
    /// surfaces has to come out as two shapes with two materials, not one.
    @Test func compressedMeshSplitsBigTrianglesFromChunksByMaterial() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init("bhkCompressedMeshShape", NIFCollisionFixture.compressedShape(dataRef: 4)),
            .init("bhkCompressedMeshShapeData", NIFCollisionFixture.compressedData(
                materials: [Self.snow, Self.stone],
                bigTriangleMaterialIndex: 0,
                chunkMaterialIndex: 1
            ))
        ]))

        let model = file.collisionModel()
        let shapes = try #require(model.bodies.first).shapes
        #expect(model.decodeFailures.isEmpty)
        #expect(shapes.map(\.material) == [Self.snow, Self.stone])
        #expect(model.triangleCount == 4)
    }

    /// A material index past the end of the table is malformed data; the
    /// geometry still has to survive it, because a surface with no material
    /// still stops the player.
    @Test func anOutOfRangeMaterialIndexLeavesGeometryIntact() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init("bhkCompressedMeshShape", NIFCollisionFixture.compressedShape(dataRef: 4)),
            .init("bhkCompressedMeshShapeData", NIFCollisionFixture.compressedData(
                materials: [Self.snow],
                bigTriangleMaterialIndex: 9,
                chunkMaterialIndex: 9
            ))
        ]))

        let model = file.collisionModel()
        #expect(model.decodeFailures.isEmpty)
        #expect(try #require(model.bodies.first).shapes.allSatisfy { $0.material == nil })
        #expect(model.triangleCount == 4)
    }

    private static func shape(type: String, payload: Data) throws -> NIFCollisionShape {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init(type, payload)
        ]))
        return try #require(file.collisionModel().bodies.first?.shapes.first)
    }
}
