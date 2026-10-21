// Synthetic byte builders for the particle modifiers with parameters. Each block
// starts with an unnamed `NiPSysModifier` header. Layouts follow NifTools nif.xml;
// see docs/formats/nif-particles.md#parameter-modifiers.

import Foundation
import simd

public enum NIFParticleParameterFixture: Sendable {
    public static func ageDeath(spawnsOnDeath: Bool, spawnRef: Int32) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.append(spawnsOnDeath ? 1 : 0)
        out.appendUInt32(UInt32(bitPattern: spawnRef))
        return out
    }

    /// Every dying particle spawns one to `maximum` children that live `lifeSpan` seconds.
    public static func spawn(generations: UInt16, maximum: UInt16, lifeSpan: Float) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.appendUInt16(generations)
        out.appendFloat32(1) // Percentage Spawned
        out.appendUInt16(1) // Min Num to Spawn
        out.appendUInt16(maximum)
        out.appendFloat32(0) // Spawn Speed Variation
        out.appendFloat32(0) // Spawn Dir Variation
        out.appendFloat32(lifeSpan)
        out.appendFloat32(0) // Life Span Variation
        return out
    }

    /// A spherical pull towards the origin of the object at `objectRef`.
    public static func sphericalGravity(objectRef: Int32, strength: Float, decay: Float) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.appendUInt32(UInt32(bitPattern: objectRef))
        appendVector(&out, SIMD3(0, 0, 1))
        out.appendFloat32(decay)
        out.appendFloat32(strength)
        out.appendUInt32(1) // Force Type: spherical
        out.appendFloat32(0) // Turbulence
        out.appendFloat32(1) // Turbulence Scale
        out.append(0) // World Aligned
        return out
    }

    /// A spin about the x axis, with a random axis flag set as in the vanilla meshes.
    public static func rotation(speed: Float, angle: Float, randomSign: Bool) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.appendFloat32(speed)
        out.appendFloat32(0) // Rotation Speed Variation
        out.appendFloat32(angle)
        out.appendFloat32(0) // Rotation Angle Variation
        out.append(randomSign ? 1 : 0)
        out.append(1) // Random Axis
        appendVector(&out, SIMD3(1, 0, 0))
        return out
    }

    /// Drag along the z axis of the object at `objectRef`, with no falloff.
    public static func drag(objectRef: Int32, percentage: Float, range: Float) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.appendUInt32(UInt32(bitPattern: objectRef))
        appendVector(&out, SIMD3(0, 0, 1))
        out.appendFloat32(percentage)
        out.appendFloat32(range)
        out.appendFloat32(0) // Range Falloff
        return out
    }

    public static func inheritVelocity(chance: Float, multiplier: Float) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.appendUInt32(0xFFFF_FFFF) // Inherit Object
        out.appendFloat32(chance)
        out.appendFloat32(multiplier)
        out.appendFloat32(0) // Velocity Variation
        return out
    }

    /// `frames` holds the start, end, and loop start frames and the frame count. No fudge.
    public static func subTex(frames: SIMD4<Float>) -> Data {
        var out = NIFParticleFixture.modifierBase()
        for value in [frames.x, 0, frames.y, frames.z, 0, frames.w, 0] {
            out.appendFloat32(value)
        }
        return out
    }

    public static func boundUpdate(skip: UInt16) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.appendUInt16(skip)
        return out
    }

    private static func appendVector(_ out: inout Data, _ value: SIMD3<Float>) {
        out.appendFloat32(value.x)
        out.appendFloat32(value.y)
        out.appendFloat32(value.z)
    }
}
