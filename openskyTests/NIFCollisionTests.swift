// bhk collision decode tests over synthetic in-code NIF payloads only.
// Layouts: NifTools nif.xml; docs/formats/nif-collision.md.

import Foundation
@testable import opensky
import simd
import Testing

struct NIFCollisionTests {
    private let scale = NIFCollisionModel.havokToEngineScale

    @Test func decodesRigidBodyMetadataAndRigidBodyTTransform() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(
                    translation: SIMD3(10, 20, 30),
                    collisionRef: 1
                )
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(
                flags: 0x89,
                body: 2
            )),
            .init("bhkRigidBodyT", NIFCollisionFixture.rigidBody(
                shape: 3,
                worldLayer: 12,
                rigidLayer: 1,
                translation: SIMD3(1, 2, 3),
                motionSystem: 6
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 0.5))
        ]))

        let model = file.collisionModel()
        let body = try #require(model.bodies.first)
        #expect(model.decodeFailures.isEmpty)
        #expect(model.unsupportedReachableBlocks.isEmpty)
        #expect(body.collisionObjectFlags == 0x89)
        #expect(body.worldFilter == NIFCollisionFilter(layer: 12, flags: 0, group: 0))
        #expect(body.rigidBodyFilter == NIFCollisionFilter(layer: 1, flags: 0, group: 0))
        #expect(body.motionSystem == 6)
        #expect(!body.isPlayerSolid)
        #expect(near(body.transform.columns.3.x, 10 + scale))
        #expect(near(body.transform.columns.3.y, 20 + scale * 2))
        #expect(near(body.transform.columns.3.z, 30 + scale * 3))
    }

    @Test(arguments: [
        (UInt8(1), UInt8(0), UInt8(1), true),
        (UInt8(15), UInt8(0), UInt8(1), false),
        (UInt8(1), UInt8(0x40), UInt8(1), false),
        (UInt8(1), UInt8(0), UInt8(2), false)
    ])
    func filterAndResponseControlPlayerSolidity(
        layer: UInt8,
        flags: UInt8,
        response: UInt8,
        expected: Bool
    ) throws {
        let file = try simpleFile(
            bodyType: "bhkRigidBody",
            body: NIFCollisionFixture.rigidBody(
                shape: 3,
                rigidLayer: layer,
                rigidFlags: flags,
                rigidResponse: response
            ),
            shapeType: "bhkSphereShape",
            shape: NIFCollisionFixture.sphere(radius: 1)
        )
        #expect(try #require(file.collisionModel().bodies.first).isPlayerSolid == expected)
    }

    @Test func decodesPrimitiveListInEngineUnits() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init("bhkListShape", NIFCollisionFixture.list([4, 5, 6, 7])),
            .init("bhkConvexVerticesShape", NIFCollisionFixture.convexVertices(
                [
                    SIMD3(0, 0, 0), SIMD3(1, 0, 0),
                    SIMD3(0, 1, 0), SIMD3(0, 0, 1)
                ],
                normals: [
                    SIMD4(-1, 0, 0, 0), SIMD4(0, -1, 0, 0),
                    SIMD4(0, 0, -1, 0),
                    SIMD4(1, 1, 1, -1) / sqrtf(3)
                ]
            )),
            .init("bhkBoxShape", NIFCollisionFixture.box(SIMD3(1, 2, 3))),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 2)),
            .init("bhkCapsuleShape", NIFCollisionFixture.capsule(
                first: SIMD3(0, 0, -1),
                second: SIMD3(0, 0, 1),
                radius: 0.5
            ))
        ]))
        let shapes = try #require(file.collisionModel().bodies.first).shapes
        #expect(shapes.count == 4)

        guard case let .convexVertices(vertices, hullIndices) = shapes[0].geometry else {
            Issue.record("expected convex vertices")
            return
        }
        #expect(vertices.count == 4)
        #expect(near(vertices[1].x, scale))
        #expect(hullIndices.count == 12)
        guard case let .box(halfExtents) = shapes[1].geometry else {
            Issue.record("expected box")
            return
        }
        #expect(near(halfExtents.y, scale * 2))
        guard case let .sphere(radius) = shapes[2].geometry else {
            Issue.record("expected sphere")
            return
        }
        #expect(near(radius, scale * 2))
        guard case let .capsule(first, second, capsuleRadius) = shapes[3].geometry else {
            Issue.record("expected capsule")
            return
        }
        #expect(near(first.z, -scale))
        #expect(near(second.z, scale))
        #expect(near(capsuleRadius, scale * 0.5))
    }

    @Test func followsMoppAndBothTransformWrappers() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init("bhkListShape", NIFCollisionFixture.list([4, 6, 8])),
            .init("bhkTransformShape", NIFCollisionFixture.transformShape(
                child: 5,
                translation: SIMD3(1, 0, 0)
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1)),
            .init("bhkConvexTransformShape", NIFCollisionFixture.transformShape(
                child: 7,
                translation: SIMD3(0, 2, 0)
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1)),
            .init("bhkMoppBvTreeShape", NIFCollisionFixture.mopp(child: 9)),
            .init("bhkBoxShape", NIFCollisionFixture.box(SIMD3(repeating: 1)))
        ]))
        let shapes = try #require(file.collisionModel().bodies.first).shapes
        #expect(shapes.count == 3)
        #expect(near(shapes[0].transform.columns.3.x, scale))
        #expect(near(shapes[1].transform.columns.3.y, scale * 2))
        guard case .box = shapes[2].geometry else {
            Issue.record("MOPP child was not decoded")
            return
        }
    }

    @Test func decodesCompressedBigTrianglesChunksStripsAndFlatTriangles() throws {
        let file = try simpleFile(
            bodyType: "bhkRigidBody",
            body: NIFCollisionFixture.rigidBody(shape: 3),
            shapeType: "bhkCompressedMeshShape",
            shape: NIFCollisionFixture.compressedShape(dataRef: 4),
            extra: [.init(
                "bhkCompressedMeshShapeData",
                NIFCollisionFixture.compressedData()
            )]
        )
        let model = file.collisionModel()
        let shapes = try #require(model.bodies.first).shapes
        #expect(model.decodeFailures.isEmpty)
        #expect(shapes.count == 2)
        #expect(model.triangleCount == 4)
        guard case let .triangleSoup(vertices, indices) = shapes[1].geometry else {
            Issue.record("expected compressed chunk soup")
            return
        }
        #expect(vertices.count == 4)
        #expect(indices == [0, 1, 2, 1, 3, 2, 0, 2, 3])
        #expect(near(vertices[0].x, scale))
        #expect(near(vertices[0].y, scale * 2))
        #expect(near(vertices[0].z, scale * 3))
    }

    @Test func decodesPackedAndNiTriStripCollections() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init("bhkListShape", NIFCollisionFixture.list([4, 6])),
            .init("bhkPackedNiTriStripsShape", NIFCollisionFixture.packedShape(dataRef: 5)),
            .init("hkPackedNiTriStripsData", NIFCollisionFixture.packedData()),
            .init("bhkNiTriStripsShape", NIFCollisionFixture.niTriStripsShape(dataRef: 7)),
            .init("NiTriStripsData", NIFCollisionFixture.niTriStripsData())
        ]))
        let model = file.collisionModel()
        #expect(model.decodeFailures.isEmpty)
        #expect(model.unsupportedReachableBlocks.isEmpty)
        #expect(model.shapeCount == 2)
        #expect(model.triangleCount == 3)
    }

    @Test func reportsUnknownReachableShapeWithoutCrashingSiblingBody() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init("bhkFutureShape", Data())
        ]))
        let model = file.collisionModel()
        #expect(model.bodies.count == 1)
        #expect(model.bodies[0].shapes.isEmpty)
        #expect(model.unsupportedReachableBlocks == ["bhkFutureShape": 1])
        #expect(model.decodeFailures.isEmpty)
    }

    @Test func malformedRootDoesNotDiscardValidSiblingRoot() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init("bhkListShape", NIFCollisionFixture.list([3])),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 5)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 6)),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1))
        ]))

        let model = file.collisionModel()
        #expect(model.bodies.count == 1)
        #expect(model.shapeCount == 1)
        #expect(model.decodeFailures.count == 1)
        #expect(model.decodeFailures[0].block == 1)
        #expect(model.decodeFailures[0].message.contains("cycle"))
    }

    private func simpleFile(
        bodyType: String,
        body: Data,
        shapeType: String,
        shape: Data,
        extra: [NIFFixture.Block] = []
    ) throws -> NIFFile {
        try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init(bodyType, body),
            .init(shapeType, shape)
        ] + extra))
    }

    private func near(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
