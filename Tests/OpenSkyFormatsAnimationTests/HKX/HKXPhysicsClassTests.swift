// Member-value tests for the ragdoll and shape classes. Each test writes distinct
// values at the offsets in docs/formats/hkx-physics.md and reads them back. All
// values are invented.

import Foundation
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

/// Decodes the object of `className` at offset 0. Other objects and array data
/// go at 0x400 and above.
func decodeHKXObject<Decoded>(
    _ className: String,
    _ decoder: (HKXPointerTarget, HKXObjectGraph) -> Decoded?,
    extra: [(className: String, offset: Int)] = [],
    writes: (inout HKBNodeFixture) -> Void
) throws -> Decoded {
    var fixture = HKBNodeFixture(payloadSize: 0x1000)
    let target = fixture.addObject(className, at: 0)
    for object in extra {
        _ = fixture.addObject(object.className, at: object.offset)
    }
    writes(&fixture)
    return try #require(decoder(target, fixture.buildGraph()))
}

extension HKBNodeFixture {
    /// Writes an `hkTransform` with a quarter turn about z and `translation`.
    mutating func setQuarterTurn(at offset: Int, translation: SIMD3<Float>) {
        setVector4(SIMD4(0, 1, 0, 0), at: offset)
        setVector4(SIMD4(-1, 0, 0, 0), at: offset + 16)
        setVector4(SIMD4(0, 0, 1, 0), at: offset + 32)
        setVector4(SIMD4(translation, 1), at: offset + 48)
    }
}

@Suite(.tags(.parser))
struct HKXPhysicsClassTests {
    @Test func halfIsTheUpperHalfOfAFloat() {
        #expect(HKHalf.value(0x3F80) == 1)
        #expect(HKHalf.value(0x3F00) == 0.5)
        #expect(HKHalf.value(0) == 0)
    }

    @Test func rigidBodyReadsShapeMaterialAndMotion() throws {
        let body = try decodeHKXObject(
            HKPRigidBody.className, HKPRigidBody.decode,
            extra: [(HKPCapsuleShape.className, 0x400)]
        ) {
            $0.setPointer(at: 0x20, to: 0x400)
            $0.setUInt32(0x0000_0F2A, at: 0x4C)
            $0.setString("Ragdoll_Spine", at: 0xB0, storage: 0x600)
            $0.setUInt8(1, at: 0xD0)
            $0.setFloat(0.8, at: 0xD4)
            $0.setFloat(0.1, at: 0xD8)
            $0.setUInt8(2, at: 0x160)
            $0.setQuarterTurn(at: 0x170, translation: SIMD3(1, 2, 3))
            $0.setVector4(SIMD4(0, 0, 0.5, 0), at: 0x1F0)
            $0.setInt16(0x3F00, at: 0x214)
            $0.setInt16(0x3E80, at: 0x216)
            $0.setVector4(SIMD4(1, 1, 1, 0.25), at: 0x220)
            $0.setInt16(0x3F80, at: 0x282)
        }
        #expect(body.name == "Ragdoll_Spine")
        #expect(body.shape == HKXPointerTarget(
            sectionIndex: HKBNodeFixture.dataSection, dataOffset: 0x400
        ))
        #expect(body.collisionFilterInfo == 0xF2A)
        #expect(body.responseType == 1 && body.motionType == 2)
        #expect(body.friction == 0.8 && body.restitution == 0.1)
        #expect(body.transform.translation == SIMD3(1, 2, 3))
        #expect(body.transform.isRigid)
        #expect(body.centerOfMassLocal == SIMD3(0, 0, 0.5))
        #expect(body.mass == 4)
        #expect([body.linearDamping, body.angularDamping, body.gravityFactor] == [0.5, 0.25, 1])
    }

    @Test func constraintInstanceNamesItsBodiesAndData() throws {
        let instance = try decodeHKXObject(
            HKPConstraintInstance.className, HKPConstraintInstance.decode,
            extra: [
                (HKPRagdollConstraintData.className, 0x400),
                (HKPRigidBody.className, 0x800), (HKPRigidBody.className, 0xB00)
            ]
        ) {
            $0.setPointer(at: 0x18, to: 0x400)
            $0.setPointer(at: 0x28, to: 0x800)
            $0.setPointer(at: 0x30, to: 0xB00)
            $0.setUInt8(1, at: 0x38)
            $0.setString("NPC Spine", at: 0x50, storage: 0x300)
        }
        #expect(instance.name == "NPC Spine" && instance.priority == 1)
        #expect(instance.data?.dataOffset == 0x400)
        #expect(instance.entityA?.dataOffset == 0x800)
        #expect(instance.entityB?.dataOffset == 0xB00)
        #expect(instance.references.count == 3)
    }

    @Test func ragdollConstraintReadsFramesLimitsAndMotors() throws {
        let data = try decodeHKXObject(
            HKPRagdollConstraintData.className, HKPRagdollConstraintData.decode,
            extra: [(HKPPositionConstraintMotor.className, 0x400)]
        ) {
            $0.setQuarterTurn(at: 0x30, translation: SIMD3(0, 0, 1))
            $0.setQuarterTurn(at: 0x70, translation: SIMD3(0, 0, -1))
            $0.setPointer(at: 0x108, to: 0x400)
            $0.setFloat(3, at: 0x128)
            $0.setUInt8(1, at: 0x12E)
            $0.setFloat(-0.5, at: 0x134)
            $0.setFloat(0.5, at: 0x138)
            $0.setUInt8(1, at: 0x142)
            $0.setFloat(-1, at: 0x148)
            $0.setFloat(1, at: 0x14C)
            $0.setFloat(-0.2, at: 0x15C)
            $0.setFloat(0.2, at: 0x160)
        }
        #expect(data.frames.transformA.translation == SIMD3(0, 0, 1))
        #expect(data.frames.transformB.translation == SIMD3(0, 0, -1))
        #expect(data.motors.map { $0?.dataOffset } == [nil, 0x400, nil])
        #expect(data.maxFrictionTorque == 3)
        #expect(data.twistLimit == HKPAngleLimit(isEnabled: true, minAngle: -0.5, maxAngle: 0.5))
        #expect(data.coneLimit == HKPAngleLimit(isEnabled: true, minAngle: -1, maxAngle: 1))
        #expect(data.planesLimit == HKPAngleLimit(isEnabled: false, minAngle: -0.2, maxAngle: 0.2))
    }

    @Test func limitedHingeAndMotorReadTheirMembers() throws {
        let hinge = try decodeHKXObject(
            HKPLimitedHingeConstraintData.className, HKPLimitedHingeConstraintData.decode,
            extra: [(HKPPositionConstraintMotor.className, 0x400)]
        ) {
            $0.setQuarterTurn(at: 0x30, translation: SIMD3(1, 0, 0))
            $0.setPointer(at: 0xD0, to: 0x400)
            $0.setFloat(2, at: 0xE0)
            $0.setUInt8(1, at: 0xE6)
            $0.setFloat(-1.5, at: 0xE8)
            $0.setFloat(0.25, at: 0xEC)
        }
        #expect(hinge.motor?.dataOffset == 0x400)
        #expect(hinge.maxFrictionTorque == 2)
        #expect(hinge.angleLimit == HKPAngleLimit(isEnabled: true, minAngle: -1.5, maxAngle: 0.25))

        let motor = try decodeHKXObject(
            HKPPositionConstraintMotor.className, HKPPositionConstraintMotor.decode
        ) {
            for (index, value) in [-50, 50, 0.8, 1, 2, 0.5].enumerated() {
                $0.setFloat(Float(value), at: 0x18 + index * 4)
            }
        }
        #expect([motor.minForce, motor.maxForce, motor.tau, motor.damping] == [-50, 50, 0.8, 1])
        #expect(motor.proportionalRecoveryVelocity == 2 && motor.constantRecoveryVelocity == 0.5)
    }

    @Test func ragdollInstanceAndSystemListTheirBodies() throws {
        let ragdoll = try decodeHKXObject(
            HKARagdollInstance.className, HKARagdollInstance.decode,
            extra: [(HKPRigidBody.className, 0x400), (HKASkeleton.className, 0x800)]
        ) {
            $0.setPointerArray(at: 0x10, dataOffset: 0x200, targets: [0x400])
            $0.setArray(at: 0x30, count: 2, dataOffset: 0x300)
            $0.setInt32(0, at: 0x300)
            $0.setInt32(-1, at: 0x304)
            $0.setPointer(at: 0x40, to: 0x800)
        }
        #expect(ragdoll.rigidBodies.map { $0?.dataOffset } == [0x400])
        #expect(ragdoll.boneToRigidBodyMap == [0, -1])
        #expect(ragdoll.skeleton?.dataOffset == 0x800)

        let system = try decodeHKXObject(
            HKPPhysicsSystem.className, HKPPhysicsSystem.decode,
            extra: [(HKPRigidBody.className, 0x400)]
        ) {
            $0.setPointerArray(at: 0x10, dataOffset: 0x200, targets: [0x400])
            $0.setString("Default Physics System", at: 0x50, storage: 0x300)
            $0.setBool(true, at: 0x60)
        }
        #expect(system.name == "Default Physics System" && system.isActive)
        #expect(system.rigidBodies.count == 1 && system.constraints.isEmpty)

        let data = try decodeHKXObject(
            HKPPhysicsData.className, HKPPhysicsData.decode,
            extra: [(HKPPhysicsSystem.className, 0x400)]
        ) { $0.setPointerArray(at: 0x18, dataOffset: 0x200, targets: [0x400]) }
        #expect(data.systems.map { $0?.dataOffset } == [0x400])
    }

    @Test func skeletonMapperReadsSimpleAndChainMappings() throws {
        let mapper = try decodeHKXObject(
            HKASkeletonMapper.className, HKASkeletonMapper.decode,
            extra: [(HKASkeleton.className, 0x800), (HKASkeleton.className, 0xA00)]
        ) {
            $0.setPointer(at: 0x10, to: 0x800)
            $0.setPointer(at: 0x18, to: 0xA00)
            $0.setArray(at: 0x20, count: 1, dataOffset: 0x400)
            $0.setInt16(3, at: 0x400)
            $0.setInt16(7, at: 0x402)
            $0.setVector4(SIMD4(1, 2, 3, 0), at: 0x410)
            $0.setVector4(SIMD4(0, 0, 0, 1), at: 0x420)
            $0.setVector4(SIMD4(1, 1, 1, 0), at: 0x430)
            $0.setArray(at: 0x30, count: 1, dataOffset: 0x500)
            for (index, bone) in [1, 4, 2, 5].enumerated() {
                $0.setInt16(Int16(bone), at: 0x500 + index * 2)
            }
            $0.setArray(at: 0x40, count: 1, dataOffset: 0x600)
            $0.setInt16(9, at: 0x600)
            $0.setBool(true, at: 0x80)
            $0.setInt32(1, at: 0x84)
        }
        let simple = try #require(mapper.simpleMappings.first)
        #expect(simple.boneA == 3 && simple.boneB == 7)
        #expect(simple.aFromBTransform.translation == SIMD3(1, 2, 3))
        #expect(simple.aFromBTransform.isValid)
        #expect(mapper.chainMappings == [
            HKASkeletonMapper.ChainMapping(startBoneA: 1, endBoneA: 4, startBoneB: 2, endBoneB: 5)
        ])
        #expect(mapper.unmappedBones == [9])
        #expect(mapper.keepUnmappedLocal && mapper.mappingType == 1)
        #expect(mapper.skeletonA?.dataOffset == 0x800 && mapper.skeletonB?.dataOffset == 0xA00)
    }
}
