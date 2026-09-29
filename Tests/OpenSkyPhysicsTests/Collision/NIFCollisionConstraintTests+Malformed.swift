// Malformed bhkConstraint input: each fault costs only the joint or body it
// touches. Layouts: docs/formats/nif-collision.md.

import FormatsMeshTesting
import Foundation
@testable import OpenSkyFormatsMesh
import Testing

extension NIFCollisionConstraintTests {
    @Test func unknownConstraintClassIsTalliedAndBodiesSurvive() throws {
        let model = try skeleton(constraint: ("bhkBreakableConstraint", Data(count: 64)))
        #expect(model.bodies.count == 2)
        #expect(model.constraints.isEmpty)
        #expect(model.unsupportedReachableBlocks["bhkBreakableConstraint"] == 2)
        #expect(model.decodeFailures.count == 2)
    }

    @Test func truncatedConstraintCostsOnlyTheJoint() throws {
        let model = try skeleton(constraint: ("bhkRagdollConstraint", Data(count: 24)))
        #expect(model.bodies.count == 2)
        #expect(model.shapeCount == 2)
        #expect(model.constraints.isEmpty)
        #expect(model.decodeFailures.count == 2)
        // Malformed bytes in a class the decoder does read are a failure, not
        // a gap in coverage, so the unsupported tally stays clean.
        #expect(model.unsupportedReachableBlocks.isEmpty)
    }

    @Test func constraintCountPastBlockEndCostsOnlyItsBody() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1),
                children: [3]
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(
                shape: 5,
                constraintCountOverride: 4096
            )),
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 4)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(
                target: 3, body: 6
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 5))
        ]))
        let model = file.collisionModel()
        #expect(model.bodies.count == 1)
        #expect(model.decodeFailures.count == 1)
    }

    @Test func constraintRefPastTheBlockTableIsReportedNotFatal() throws {
        let model = try skeleton(constraint: nil, constraintRef: 99)
        #expect(model.bodies.count == 2)
        #expect(model.constraints.isEmpty)
        #expect(model.decodeFailures.count == 2)
    }
}
