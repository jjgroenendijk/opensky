// A cached collision model decodes to exactly what the NIF load builds.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
import simd
import Testing

struct CollisionCacheCodecTests {
    private func bytes(_ values: [some Any]) -> Data {
        values.withUnsafeBytes { unsafe Data($0) }
    }

    private var dynamics: NIFRigidBodyDynamics {
        NIFRigidBodyDynamics(
            mass: 3, inertiaTensor: matrix_identity_float3x3, centerOfMass: SIMD3(1, 2, 3),
            linearVelocity: .zero, angularVelocity: .zero, linearDamping: 0.1, angularDamping: 0.05,
            timeFactor: 1, gravityFactor: 1, friction: 0.5, rollingFrictionMultiplier: 0,
            restitution: 0.3, maxLinearVelocity: 100, maxAngularVelocity: 30,
            penetrationDepth: 0.15,
            rawMotionSystem: 7, rawDeactivatorType: 1, rawSolverDeactivation: 2, rawQualityType: 3
        )
    }

    private var collisionModel: NIFCollisionModel {
        let filter = NIFCollisionFilter(layer: 1, flags: 0x40, group: 9)
        let shapes: [NIFCollisionShape] = [
            NIFCollisionShape(
                transform: MatrixMath.translation(SIMD3(0, 0, 1)),
                geometry: .triangleSoup(
                    vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
                    indices: [0, 1, 2]
                ),
                material: 0xDEAD_BEEF
            ),
            NIFCollisionShape(transform: matrix_identity_float4x4, geometry: .convexVertices(
                vertices: [SIMD3(0, 0, 0), SIMD3(1, 1, 1)], hullIndices: [0, 1, 0]
            )),
            NIFCollisionShape(
                transform: matrix_identity_float4x4,
                geometry: .box(halfExtents: SIMD3(1, 2, 3))
            ),
            NIFCollisionShape(transform: matrix_identity_float4x4, geometry: .sphere(radius: 4)),
            NIFCollisionShape(transform: matrix_identity_float4x4, geometry: .capsule(
                first: SIMD3(0, 0, 0), second: SIMD3(0, 0, 5), radius: 1
            ))
        ]
        let body = NIFCollisionBody(
            targetBlock: 3, targetName: "Rock", bodyBlock: 4, carrier: .collisionObject,
            collisionObjectFlags: 0x81, worldFilter: filter, rigidBodyFilter: filter,
            entityResponse: 1,
            rigidBodyResponse: 1, dynamics: dynamics, constraints: [], bodyFlags: 2,
            transform: MatrixMath.translation(SIMD3(7, 8, 9)), shapes: shapes
        )
        return NIFCollisionModel(
            bodies: [body], unsupportedReachableBlocks: ["bhkMultiSphereShape": 2],
            decodeFailures: [NIFCollisionFailure(block: 11, message: "bad ref")]
        )
    }

    @Test func aCollisionModelDecodesToTheSameBodiesAndShapes() throws {
        let model = collisionModel
        let payload = try #require(CollisionCacheCodec.encode(model))
        let decoded = try CollisionCacheCodec.decode(payload)
        #expect(decoded.unsupportedReachableBlocks == model.unsupportedReachableBlocks)
        #expect(decoded.decodeFailures == model.decodeFailures)
        #expect(decoded.shapeCount == model.shapeCount)
        #expect(decoded.triangleCount == model.triangleCount)
        #expect(decoded.bounds == model.bounds)
        let left = try #require(decoded.bodies.first)
        let right = try #require(model.bodies.first)
        #expect(left.targetName == right.targetName)
        #expect(left.worldFilter == right.worldFilter)
        #expect(left.bodyFlags == right.bodyFlags)
        #expect(left.transform == right.transform)
        #expect(bytes([left.dynamics]) == bytes([right.dynamics]))
        #expect(left.shapes.map(\.material) == right.shapes.map(\.material))
        #expect(String(describing: left.shapes.map(\.geometry)) ==
            String(describing: right.shapes.map(\.geometry)))
    }

    @Test func aCollisionModelWithJointsIsNotCached() throws {
        let model = collisionModel
        let body = try #require(model.bodies.first)
        let joint = NIFCollisionConstraint(
            block: 1,
            entityA: 4,
            entityB: 4,
            priority: 1,
            data: .ballAndSocket(NIFBallAndSocketConstraint(pivotA: .zero, pivotB: .zero))
        )
        let jointed = NIFCollisionBody(
            targetBlock: body.targetBlock, targetName: body.targetName, bodyBlock: body.bodyBlock,
            carrier: body.carrier, collisionObjectFlags: 0, worldFilter: body.worldFilter,
            rigidBodyFilter: body.rigidBodyFilter, entityResponse: 1, rigidBodyResponse: 1,
            dynamics: body.dynamics, constraints: [joint], bodyFlags: 0, transform: body.transform,
            shapes: body.shapes
        )
        let withJoint = NIFCollisionModel(
            bodies: [jointed],
            unsupportedReachableBlocks: [:],
            decodeFailures: []
        )
        #expect(CollisionCacheCodec.encode(withJoint) == nil)
    }
}
