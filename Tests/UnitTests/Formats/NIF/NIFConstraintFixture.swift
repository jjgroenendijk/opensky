// Synthetic bhkConstraint payload builders. Field order follows the Fallout 3
// and later branch of each nif.xml CInfo struct, which is the branch Skyrim SE
// streams take. No game bytes are fixtures (AGENTS.md legal boundary).

import Foundation
import simd

enum NIFConstraintFixture {
    /// nif.xml `bhkConstraintCInfo`: entity count (always 2), both entity
    /// pointers, priority.
    static func info(entityA: Int32, entityB: Int32, priority: UInt32 = 1) -> Data {
        var data = Data()
        data.appendUInt32(2)
        data.appendRef(entityA)
        data.appendRef(entityB)
        data.appendUInt32(priority)
        return data
    }

    /// nif.xml `bhkConstraintMotorCInfo`. `type` 0 writes the byte alone.
    static func motor(type: UInt8 = 0, enabled: Bool = false) -> Data {
        var data = Data([type])
        switch type {
        case 1:
            for value in [Float(-1000), 1000, 0.8, 1, 2, 1] {
                data.appendFloat32(value)
            }
            data.append(enabled ? 1 : 0)
        case 2:
            for value in [Float(-1000), 1000, 0.5, 3] {
                data.appendFloat32(value)
            }
            data.append(1)
            data.append(enabled ? 1 : 0)
        case 3:
            for value in [Float(-1000), 1000, 40, 5] {
                data.appendFloat32(value)
            }
            data.append(enabled ? 1 : 0)
        default:
            break
        }
        return data
    }

    static func ragdoll(
        entityA: Int32,
        entityB: Int32,
        pivotA: SIMD3<Float>,
        pivotB: SIMD3<Float>,
        angles: [Float] = [0.5, -0.4, 0.4, -0.3, 0.3],
        maxFriction: Float = 10,
        motor: Data = motor()
    ) -> Data {
        var data = info(entityA: entityA, entityB: entityB)
        data.append(ragdollFrame(pivot: pivotA, axis: SIMD3(1, 0, 0)))
        data.append(ragdollFrame(pivot: pivotB, axis: SIMD3(0, 1, 0)))
        angles.forEach { data.appendFloat32($0) }
        data.appendFloat32(maxFriction)
        data.append(motor)
        return data
    }

    /// Twist, plane, motor axis, pivot — an orthonormal triple plus the point.
    private static func ragdollFrame(pivot: SIMD3<Float>, axis: SIMD3<Float>) -> Data {
        var data = Data()
        data.appendVector4(SIMD4(axis, 0))
        data.appendVector4(SIMD4(orthogonal(to: axis), 0))
        data.appendVector4(SIMD4(simd_cross(axis, orthogonal(to: axis)), 0))
        data.appendVector4(SIMD4(pivot, 0))
        return data
    }

    static func hinge(
        entityA: Int32,
        entityB: Int32,
        pivotA: SIMD3<Float>,
        pivotB: SIMD3<Float>,
        axis: SIMD3<Float> = SIMD3(0, 0, 1)
    ) -> Data {
        var data = info(entityA: entityA, entityB: entityB)
        data.append(hingeFrame(pivot: pivotA, axis: axis))
        data.append(hingeFrame(pivot: pivotB, axis: axis))
        return data
    }

    static func limitedHinge(
        entityA: Int32,
        entityB: Int32,
        pivotA: SIMD3<Float>,
        pivotB: SIMD3<Float>,
        axis: SIMD3<Float> = SIMD3(0, 0, 1),
        minAngle: Float = -1,
        maxAngle: Float = 1,
        maxFriction: Float = 10,
        motor: Data = motor()
    ) -> Data {
        var data = info(entityA: entityA, entityB: entityB)
        data.append(hingeFrame(pivot: pivotA, axis: axis))
        data.append(hingeFrame(pivot: pivotB, axis: axis))
        data.appendFloat32(minAngle)
        data.appendFloat32(maxAngle)
        data.appendFloat32(maxFriction)
        data.append(motor)
        return data
    }

    /// Axis, both in-plane reference axes, pivot.
    private static func hingeFrame(pivot: SIMD3<Float>, axis: SIMD3<Float>) -> Data {
        var data = Data()
        data.appendVector4(SIMD4(axis, 0))
        data.appendVector4(SIMD4(orthogonal(to: axis), 0))
        data.appendVector4(SIMD4(simd_cross(axis, orthogonal(to: axis)), 0))
        data.appendVector4(SIMD4(pivot, 0))
        return data
    }

    static func ballAndSocket(
        entityA: Int32,
        entityB: Int32,
        pivotA: SIMD3<Float>,
        pivotB: SIMD3<Float>
    ) -> Data {
        var data = info(entityA: entityA, entityB: entityB)
        data.appendVector4(SIMD4(pivotA, 0))
        data.appendVector4(SIMD4(pivotB, 0))
        return data
    }

    static func stiffSpring(
        entityA: Int32,
        entityB: Int32,
        pivotA: SIMD3<Float>,
        pivotB: SIMD3<Float>,
        length: Float
    ) -> Data {
        var data = ballAndSocket(
            entityA: entityA, entityB: entityB, pivotA: pivotA, pivotB: pivotB
        )
        data.appendFloat32(length)
        return data
    }

    static func prismatic(
        entityA: Int32,
        entityB: Int32,
        pivotA: SIMD3<Float>,
        pivotB: SIMD3<Float>,
        sliding: SIMD3<Float> = SIMD3(1, 0, 0),
        minDistance: Float = 0,
        maxDistance: Float = 2,
        friction: Float = 0.5,
        motor: Data = motor()
    ) -> Data {
        var data = info(entityA: entityA, entityB: entityB)
        data.append(hingeFrame(pivot: pivotA, axis: sliding))
        data.append(hingeFrame(pivot: pivotB, axis: sliding))
        data.appendFloat32(minDistance)
        data.appendFloat32(maxDistance)
        data.appendFloat32(friction)
        data.append(motor)
        return data
    }

    /// `bhkMalleableConstraint`: outer constraint info, wrapped type, a
    /// repeated constraint info, the wrapped payload, then strength.
    static func malleable(
        entityA: Int32,
        entityB: Int32,
        wrappedType: UInt32,
        wrappedPayload: Data,
        strength: Float
    ) -> Data {
        var data = info(entityA: entityA, entityB: entityB)
        data.appendUInt32(wrappedType)
        data.append(info(entityA: entityA, entityB: entityB))
        data.append(wrappedPayload)
        data.appendFloat32(strength)
        return data
    }

    /// Any unit vector perpendicular to `axis`, for building an orthonormal
    /// frame the decoder can be checked against.
    private static func orthogonal(to axis: SIMD3<Float>) -> SIMD3<Float> {
        let candidate = abs(axis.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        return simd_normalize(simd_cross(axis, candidate))
    }
}
