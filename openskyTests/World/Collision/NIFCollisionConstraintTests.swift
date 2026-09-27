// bhkConstraint decode over synthetic payloads, including the two-bone
// skeleton shape a ragdoll carrier takes.
// Layouts: NifTools nif.xml; docs/formats/nif-collision.md.

import Foundation
@testable import opensky
import simd
import Testing

struct NIFCollisionConstraintTests {
    private let scale = NIFCollisionModel.havokToEngineScale

    @Test func decodesRagdollConstraintAcrossSkeletonBones() throws {
        let model = try skeleton(constraint: (
            "bhkRagdollConstraint",
            NIFConstraintFixture.ragdoll(
                entityA: 4,
                entityB: 6,
                pivotA: SIMD3(0, 0, 1),
                pivotB: SIMD3(0, 0, -1),
                motor: NIFConstraintFixture.motor(type: 1, enabled: true)
            )
        ))

        #expect(model.decodeFailures.isEmpty)
        #expect(model.unsupportedReachableBlocks.isEmpty)
        #expect(model.bodies.count == 2)
        #expect(model.bodies.allSatisfy { $0.carrier == .blendCollisionObject })
        #expect(model.bodies.compactMap(\.targetName).sorted() == ["NPC Head", "NPC Spine"])
        // Both bodies name the same joint, so the model view de-duplicates it.
        #expect(model.bodies.allSatisfy { $0.constraints.count == 1 })
        #expect(model.constraints.count == 1)

        let constraint = try #require(model.constraints.first)
        #expect(constraint.type == .ragdoll)
        #expect(constraint.priority == 1)
        let names = model.boneNames(of: constraint)
        #expect(names.a == "NPC Spine")
        #expect(names.b == "NPC Head")

        guard case let .ragdoll(ragdoll) = constraint.data else {
            Issue.record("expected a ragdoll joint, got \(constraint.data)")
            return
        }
        #expect(near(ragdoll.frameA.pivot.z, scale))
        #expect(near(ragdoll.frameB.pivot.z, -scale))
        #expect(ragdoll.frameA.twist == SIMD3(1, 0, 0))
        #expect(ragdoll.frameB.twist == SIMD3(0, 1, 0))
        #expect(ragdoll.coneMaxAngle == 0.5)
        #expect(ragdoll.twistMaxAngle == 0.3)
        #expect(ragdoll.maxFriction == 10)
        guard case let .position(motor) = ragdoll.motor else {
            Issue.record("expected a position motor, got \(ragdoll.motor)")
            return
        }
        #expect(motor.isEnabled)
        #expect(motor.maxForce == 1000)
        #expect(motor.tau == 0.8)
    }

    @Test func decodesHingeAndLimitedHinge() throws {
        let hingeModel = try skeleton(constraint: (
            "bhkHingeConstraint",
            NIFConstraintFixture.hinge(
                entityA: 4,
                entityB: 6,
                pivotA: SIMD3(1, 0, 0),
                pivotB: .zero
            )
        ))
        guard
            case let .hinge(hinge) = try #require(hingeModel.constraints.first).data
        else {
            Issue.record("expected a hinge joint")
            return
        }
        #expect(hinge.frameA.axis == SIMD3(0, 0, 1))
        #expect(near(hinge.frameA.pivot.x, scale))
        #expect(near(simd_length(hinge.frameA.perpAxis1), 1))

        let limitedModel = try skeleton(constraint: (
            "bhkLimitedHingeConstraint",
            NIFConstraintFixture.limitedHinge(
                entityA: 4,
                entityB: 6,
                pivotA: .zero,
                pivotB: SIMD3(0, 2, 0),
                minAngle: -0.75,
                maxAngle: 1.25,
                motor: NIFConstraintFixture.motor(type: 3, enabled: true)
            )
        ))
        guard
            case let .limitedHinge(limited) = try #require(limitedModel.constraints.first).data
        else {
            Issue.record("expected a limited hinge joint")
            return
        }
        #expect(limited.minAngle == -0.75)
        #expect(limited.maxAngle == 1.25)
        #expect(near(limited.frameB.pivot.y, 2 * scale))
        guard case let .springDamper(motor) = limited.motor else {
            Issue.record("expected a spring damper motor, got \(limited.motor)")
            return
        }
        #expect(motor.springConstant == 40)
        #expect(motor.isEnabled)
    }

    @Test func decodesPointConstraintsInEngineUnits() throws {
        let ball = try skeleton(constraint: (
            "bhkBallAndSocketConstraint",
            NIFConstraintFixture.ballAndSocket(
                entityA: 4, entityB: 6, pivotA: SIMD3(1, 0, 0), pivotB: SIMD3(0, 1, 0)
            )
        ))
        guard case let .ballAndSocket(joint) = try #require(ball.constraints.first).data else {
            Issue.record("expected a ball and socket joint")
            return
        }
        #expect(near(joint.pivotA.x, scale))
        #expect(near(joint.pivotB.y, scale))

        let spring = try skeleton(constraint: (
            "bhkStiffSpringConstraint",
            NIFConstraintFixture.stiffSpring(
                entityA: 4, entityB: 6, pivotA: .zero, pivotB: .zero, length: 3
            )
        ))
        guard case let .stiffSpring(joint) = try #require(spring.constraints.first).data else {
            Issue.record("expected a stiff spring joint")
            return
        }
        #expect(near(joint.length, 3 * scale))
    }

    @Test func decodesPrismaticRail() throws {
        let model = try skeleton(constraint: (
            "bhkPrismaticConstraint",
            NIFConstraintFixture.prismatic(
                entityA: 4, entityB: 6, pivotA: .zero, pivotB: .zero,
                minDistance: 0, maxDistance: 2
            )
        ))
        guard case let .prismatic(joint) = try #require(model.constraints.first).data else {
            Issue.record("expected a prismatic joint")
            return
        }
        #expect(joint.frameA.sliding == SIMD3(1, 0, 0))
        #expect(near(joint.maxDistance, 2 * scale))
        #expect(joint.friction == 0.5)
    }

    @Test func unwrapsMalleableConstraint() throws {
        let wrapped = NIFConstraintFixture.limitedHinge(
            entityA: 4, entityB: 6, pivotA: .zero, pivotB: .zero, maxAngle: 0.5
        )
        // The wrapped payload follows the repeated constraint info, so the
        // fixture supplies it without its own leading info block.
        let payload = wrapped.dropFirst(16)
        let model = try skeleton(constraint: (
            "bhkMalleableConstraint",
            NIFConstraintFixture.malleable(
                entityA: 4,
                entityB: 6,
                wrappedType: 2,
                wrappedPayload: Data(payload),
                strength: 0.25
            )
        ))
        let constraint = try #require(model.constraints.first)
        #expect(constraint.type == .malleable)
        guard case let .malleable(strength, _) = constraint.data else {
            Issue.record("expected a malleable joint")
            return
        }
        #expect(strength == 0.25)
        guard case let .limitedHinge(inner) = constraint.data.unwrapped else {
            Issue.record("expected a limited hinge under the wrapper")
            return
        }
        #expect(inner.maxAngle == 0.5)
    }

    // MARK: - Malformed input

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

    // MARK: - Support

    /// Two bones, each carrying a `bhkBlendCollisionObject` over a rigid body,
    /// both naming the same joint — the shape a vanilla character skeleton
    /// takes. Block 8 is the joint when `constraint` is supplied.
    private func skeleton(
        constraint: (type: String, data: Data)?,
        constraintRef: Int32 = 8
    ) throws -> NIFCollisionModel {
        var blocks: [NIFFixture.Block] = [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 0),
                children: [1, 2]
            )),
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 1, collisionRef: 3)
            )),
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 2, collisionRef: 5)
            )),
            .init("bhkBlendCollisionObject", NIFCollisionFixture.blendCollisionObject(
                target: 1, body: 4
            )),
            .init("bhkRigidBodyT", NIFCollisionFixture.rigidBody(
                shape: 7, constraints: [constraintRef]
            )),
            .init("bhkBlendCollisionObject", NIFCollisionFixture.blendCollisionObject(
                target: 2, body: 6
            )),
            .init("bhkRigidBodyT", NIFCollisionFixture.rigidBody(
                shape: 7, constraints: [constraintRef]
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 0.25))
        ]
        if let constraint {
            blocks.append(.init(constraint.type, constraint.data))
        }
        let file = try NIFFile(data: NIFFixture.file(
            blocks: blocks,
            strings: ["NPC Root", "NPC Spine", "NPC Head"]
        ))
        return file.collisionModel()
    }

    private func near(_ lhs: Float, _ rhs: Float, tolerance: Float = 1e-3) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
