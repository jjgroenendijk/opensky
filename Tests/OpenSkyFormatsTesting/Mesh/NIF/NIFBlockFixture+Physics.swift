// Synthetic payloads for the particle force modifiers and the collision blocks
// beside the rigid body path. Layouts follow nif.xml; see
// docs/formats/nif-particles.md and docs/formats/nif-collision.md.

import Foundation
import simd

extension NIFBlockFixture {
    /// `NiPSysBombModifier`: `push` is the decay and delta V, `types` the decay and
    /// symmetry types.
    public static func bombModifier(
        object: Int32, axis: SIMD3<Float>, push: SIMD2<Float>, types: SIMD2<UInt32>
    ) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.appendRef(object)
        out.appendVector3(axis)
        out.append(floats([push.x, push.y]))
        out.appendUInt32(types.x)
        out.appendUInt32(types.y)
        return out
    }

    /// `NiPSysColliderManager`.
    public static func colliderManager(collider: Int32) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.appendRef(collider)
        return out
    }

    /// The `NiPSysCollider` fields, then `shape`: plane width, height, and axes, or a
    /// radius. `refs` are the manager, the next collider, and the collider object.
    public static func collider(
        bounce: Float,
        dies: Bool,
        refs: SIMD3<Int32>,
        shape: [Float]
    ) -> Data {
        var out = floats([bounce])
        out.append(contentsOf: [0, dies ? 1 : 0])
        out.appendRef(-1) // spawn modifier
        out.appendRef(refs.x)
        out.appendRef(refs.y)
        out.appendRef(refs.z)
        out.append(floats(shape))
        return out
    }

    /// `BSPSysRecycleBoundModifier`.
    public static func recycleBound(
        offset: SIMD3<Float>,
        extent: SIMD3<Float>,
        object: Int32
    ) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.appendVector3(offset)
        out.appendVector3(extent)
        out.appendRef(object)
        return out
    }

    /// `BSPSysHavokUpdateModifier`.
    public static func havokUpdate(meshes: [Int32], modifier: Int32) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.appendUInt32(UInt32(meshes.count))
        meshes.forEach { out.appendRef($0) }
        out.appendRef(modifier)
        return out
    }

    /// `bhkSimpleShapePhantom` with an identity rotation.
    public static func shapePhantom(
        shape: Int32, layer: UInt8, translation: SIMD3<Float>, w: Float = 1
    ) -> Data {
        var out = Data()
        out.appendRef(shape)
        out.appendFilter(layer: layer)
        out.append(Data(count: 28))
        out.appendMatrix(translation: translation, w: w)
        return out
    }

    /// `bhkCylinderShape`, in Havok units.
    public static func cylinder(first: SIMD3<Float>, second: SIMD3<Float>, radius: Float) -> Data {
        var out = uint32(0)
        out.append(Data(count: 12))
        out.appendVector4(SIMD4(first, 0))
        out.appendVector4(SIMD4(second, 0))
        out.append(floats([radius]))
        out.append(Data(count: 12))
        return out
    }

    /// `bhkPlaneShape`, in Havok units.
    public static func plane(
        normal: SIMD3<Float>, constant: Float, halfExtents: SIMD3<Float>, center: SIMD3<Float>
    ) -> Data {
        var out = uint32(0)
        out.append(Data(count: 12))
        out.appendVector3(normal)
        out.append(floats([constant]))
        out.appendVector4(SIMD4(halfExtents, 0))
        out.appendVector4(SIMD4(center, 0))
        return out
    }

    /// `bhkBallSocketConstraintChain`: two pivots per link, then the chained entities.
    public static func ballSocketChain(pivots: [SIMD3<Float>], entities: [Int32]) -> Data {
        var out = uint32(UInt32(pivots.count))
        pivots.forEach { out.appendVector4(SIMD4($0, 0)) }
        out.append(floats([0.8, 0.5, 0, 0.1]))
        out.appendUInt32(UInt32(entities.count))
        entities.forEach { out.appendRef($0) }
        out.append(NIFConstraintFixture.info(entityA: entities[0], entityB: entities[1]))
        return out
    }

    /// `bhkBreakableConstraint` wrapping a ball-and-socket (type 0) between two entities.
    public static func breakable(entityA: Int32, entityB: Int32, threshold: Float) -> Data {
        let info = NIFConstraintFixture.info(entityA: entityA, entityB: entityB)
        var out = info
        out.appendUInt32(0)
        out.append(info)
        out.appendVector4(SIMD4(1, 0, 0, 0))
        out.appendVector4(SIMD4(0, 1, 0, 0))
        out.append(floats([threshold]))
        out.append(1)
        return out
    }
}
