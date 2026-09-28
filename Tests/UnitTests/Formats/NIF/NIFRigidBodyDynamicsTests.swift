// Inertial-tail decode over synthetic bhkRigidBodyCInfo2010 payloads.
// Layouts: NifTools nif.xml; docs/formats/nif-collision.md.

import Foundation
@testable import opensky
import simd
import Testing

struct NIFRigidBodyDynamicsTests {
    private let scale = NIFCollisionModel.havokToEngineScale

    @Test func decodesInertialTail() throws {
        var dynamics = NIFCollisionFixture.Dynamics()
        dynamics.mass = 12.5
        dynamics.center = SIMD3(0.25, 0.5, 1)
        dynamics.linearVelocity = SIMD3(1, 2, 3)
        dynamics.angularVelocity = SIMD3(4, 5, 6)
        dynamics.linearDamping = 0.1
        dynamics.angularDamping = 0.05
        dynamics.friction = 0.3
        dynamics.rollingFrictionMultiplier = 0.2
        dynamics.restitution = 0.4
        dynamics.maxLinearVelocity = 104.4
        dynamics.maxAngularVelocity = 31.57
        dynamics.penetrationDepth = 0.15
        dynamics.timeFactor = 1
        dynamics.gravityFactor = 2
        dynamics.deactivatorType = 2
        dynamics.solverDeactivation = 3
        dynamics.qualityType = 4

        let body = try #require(model(dynamics: dynamics, motionSystem: 4).bodies.first)
        let decoded = body.dynamics
        #expect(decoded.mass == 12.5)
        #expect(near(decoded.centerOfMass.x, 0.25 * scale))
        #expect(near(decoded.centerOfMass.z, scale))
        #expect(decoded.linearVelocity == SIMD3(1, 2, 3))
        #expect(decoded.angularVelocity == SIMD3(4, 5, 6))
        #expect(decoded.linearDamping == 0.1)
        #expect(decoded.angularDamping == 0.05)
        #expect(decoded.friction == 0.3)
        #expect(decoded.rollingFrictionMultiplier == 0.2)
        #expect(decoded.restitution == 0.4)
        #expect(decoded.maxLinearVelocity == 104.4)
        #expect(decoded.maxAngularVelocity == 31.57)
        #expect(decoded.penetrationDepth == 0.15)
        #expect(decoded.gravityFactor == 2)
        #expect(decoded.motionSystem == .boxInertia)
        #expect(decoded.deactivatorType == .spatial)
        #expect(decoded.solverDeactivation == .medium)
        #expect(decoded.qualityType == .moving)
        #expect(body.motionSystem == 4)
    }

    /// nif.xml stores `hkMatrix3` in rows; the decoder transposes so the
    /// result multiplies column vectors, like every other rotation here.
    @Test func transposesInertiaTensorOnRead() throws {
        var dynamics = NIFCollisionFixture.Dynamics()
        dynamics.inertiaRows = [SIMD3(1, 2, 3), SIMD3(4, 5, 6), SIMD3(7, 8, 9)]
        let body = try #require(model(dynamics: dynamics).bodies.first)
        let tensor = body.dynamics.inertiaTensor
        #expect(tensor.columns.0 == SIMD3(1, 4, 7))
        #expect(tensor.columns.1 == SIMD3(2, 5, 8))
        #expect(tensor.columns.2 == SIMD3(3, 6, 9))
    }

    @Test(arguments: [
        (UInt8(1), Float(10), true),
        (UInt8(4), Float(10), true),
        (UInt8(7), Float(10), false),
        (UInt8(6), Float(10), false),
        (UInt8(1), Float(0), false),
        (UInt8(200), Float(10), false)
    ])
    func simulationEligibilityNeedsMotionSystemAndMass(
        motionSystem: UInt8,
        mass: Float,
        expected: Bool
    ) throws {
        var dynamics = NIFCollisionFixture.Dynamics()
        dynamics.mass = mass
        let decoded = try #require(
            model(dynamics: dynamics, motionSystem: motionSystem).bodies.first
        )
        #expect(decoded.dynamics.isSimulated == expected)
    }

    /// An unknown motion byte is preserved rather than clamped, so a modded
    /// value is visible to the census instead of silently becoming static.
    @Test func preservesUnknownMotionSystemByte() throws {
        let body = try #require(model(motionSystem: 200).bodies.first)
        #expect(body.dynamics.rawMotionSystem == 200)
        #expect(body.dynamics.motionSystem == nil)
    }

    @Test func readsBodyFlags() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3, bodyFlags: 1)),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1))
        ]))
        #expect(try #require(file.collisionModel().bodies.first).bodyFlags == 1)
    }

    // MARK: - Support

    private func model(
        dynamics: NIFCollisionFixture.Dynamics = NIFCollisionFixture.Dynamics(),
        motionSystem: UInt8 = 7
    ) throws -> NIFCollisionModel {
        try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(
                shape: 3,
                motionSystem: motionSystem,
                dynamics: dynamics
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1))
        ])).collisionModel()
    }

    private func near(_ lhs: Float, _ rhs: Float, tolerance: Float = 1e-3) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
