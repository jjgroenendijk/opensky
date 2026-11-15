// Synthetic byte builders for the particle modifiers with parameters. Each block
// starts with an unnamed `NiPSysModifier` header. Layouts follow NifTools nif.xml;
// see docs/formats/nif-particles.md#parameter-modifiers.

public import Foundation
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

    public static func inheritVelocity(
        chance: Float, multiplier: Float, objectRef: Int32 = -1
    ) -> Data {
        var out = NIFParticleFixture.modifierBase()
        out.appendUInt32(UInt32(bitPattern: objectRef)) // Inherit Object
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

    /// nif.xml `BSProceduralLightningController` aimed at the block at `targetRef`, with
    /// the given bolt fields. `interpolators` fills the nine interpolator refs from the
    /// first (generation) on; the rest stay empty.
    public static func lightningController(
        targetRef: Int32, subdivisions: UInt16, branches: UInt16, length: Float, width: Float = 16,
        interpolators: [Int32] = [], flags: UInt16 = 0x8
    ) -> Data {
        var out = Data()
        out.appendUInt32(0xFFFF_FFFF) // Next Controller
        out.appendUInt16(flags)
        for value: Float in [1, 0, 0, 1] { // Frequency, phase, start, stop
            out.appendFloat32(value)
        }
        out.appendUInt32(UInt32(bitPattern: targetRef))
        for slot in 0 ..< 9 {
            out
                .appendUInt32(UInt32(bitPattern: slot < interpolators
                        .count ? interpolators[slot] : -1))
        }
        out.appendUInt16(subdivisions)
        out.appendUInt16(branches)
        out.appendUInt16(0) // Branch variation
        for value in [length, 0, width, 0.75, 20] { // Length var, child mult, arc offset
            out.appendFloat32(value)
        }
        out.append(contentsOf: [1, 1, 1]) // Fade main, fade children, animate arc
        out.appendUInt32(0xFFFF_FFFF) // Shader property
        return out
    }

    /// A lightning node with its hidden shape, as the vanilla bolts have it: block 1 is
    /// the node the controller (block 3) targets, block 2 the shape, block 4 its effect
    /// shader. `extraBlocks` start at block 5.
    public static func lightningFile(
        controller: Data, extraBlocks: [NIFFixture.Block] = [], strings: [String] = []
    ) -> Data {
        NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(children: [1])),
                NIFFixture.Block("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(controllerRef: 3), children: [2]
                )),
                NIFFixture.Block("BSTriShape", NIFFixture.bsTriShape(
                    prefix: NIFFixture.avObjectPrefix(flags: 0xF, translation: [0, 0, 10]),
                    shaderPropertyRef: 4, attributes: 0, strideDwords: 0
                )),
                NIFFixture.Block("BSProceduralLightningController", controller),
                NIFFixture.Block(
                    "BSEffectShaderProperty", NIFParticleFixture.effectShaderProperty()
                )
            ] + extraBlocks,
            strings: strings,
            roots: [0]
        )
    }

    /// `NiBoolInterpolator` holding one value and no key data.
    public static func boolInterpolator(_ value: Bool) -> Data {
        Data([value ? 1 : 0, 0xFF, 0xFF, 0xFF, 0xFF])
    }

    /// `NiFloatInterpolator` holding one value and no key data.
    public static func floatInterpolator(_ value: Float) -> Data {
        var out = Data()
        out.appendFloat32(value)
        out.appendUInt32(0xFFFF_FFFF)
        return out
    }

    /// nif.xml `NiControllerSequence` whose links all feed `controller`; each link names
    /// its interpolator block and the string index of its interpolator ID.
    public static func sequence(
        name: UInt32, timing: (cycle: UInt32, stop: Float), controller: UInt32,
        links: [(interpolator: UInt32, id: UInt32)]
    ) -> Data {
        var out = Data()
        out.appendUInt32(name)
        out.appendUInt32(UInt32(links.count))
        out.appendUInt32(1)
        for link in links {
            out.appendUInt32(link.interpolator)
            out.appendUInt32(controller)
            out.append(0)
            for string in [
                0xFFFF_FFFF,
                0xFFFF_FFFF,
                0xFFFF_FFFF,
                0xFFFF_FFFF,
                link.id
            ] as [UInt32] {
                out.appendUInt32(string)
            }
        }
        out.appendFloat32(1)
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt32(timing.cycle)
        out.appendFloat32(1)
        out.appendFloat32(0)
        out.appendFloat32(timing.stop)
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt16(0)
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
