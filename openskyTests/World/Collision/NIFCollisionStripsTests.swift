// The triangle-collection half of the bhk decode tests, split out of
// NIFCollisionTests.swift to keep both inside the strict type-body limit.
// Synthetic in-code payloads only; layouts: NifTools nif.xml and
// docs/formats/nif-collision.md.

import Foundation
@testable import opensky
import Testing

struct NIFCollisionStripsTests {
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

    /// Issue #376: the vanilla `bhkNiTriStripsShape` meshes carry every
    /// optional `NiGeometryData` array, so one wrong field width in the prefix
    /// only shows up here and not on the minimal fixture above.
    @Test func decodesNiTriStripsDataCarryingEveryOptionalArray() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init("bhkNiTriStripsShape", NIFCollisionFixture.niTriStripsShape(dataRef: 4)),
            .init("NiTriStripsData", NIFCollisionFixture.niTriStripsDataFullPrefix())
        ]))
        let model = file.collisionModel()
        #expect(model.decodeFailures.isEmpty)
        #expect(model.shapeCount == 1)
        #expect(model.triangleCount == 4)
        guard case let .triangleSoup(vertices, indices) = model.bodies[0].shapes[0].geometry else {
            Issue.record("expected a strips soup")
            return
        }
        #expect(vertices.count == 6)
        // Alternating winding within each strip, restarted per strip.
        #expect(indices == [0, 1, 2, 1, 3, 2, 1, 2, 4, 2, 4, 5])
    }
}
