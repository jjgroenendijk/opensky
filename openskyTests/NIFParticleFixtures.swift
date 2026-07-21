// Synthetic byte builders for NIF particle-system parser tests. Fixtures are
// built in code — never extracted game files (AGENTS.md "Legal & IP boundary").
// Layouts follow NifTools nif.xml (NiParticleSystem, NiPSysData, NiPSysEmitter
// and concrete emitter/modifier blocks); see docs/formats/nif-particles.md.

import Foundation
import simd

enum NIFParticleFixture {
    /// BSStripPSysData tail appended after the NiPSysData body.
    struct StripTail {
        let maxPointCount: UInt16
        let startCap: Float
        let endCap: Float
        let zPrepass: Bool
    }

    /// NiPSysData payload, Bethesda-20.2 layout. Under BS202 the geometry
    /// arrays carry no length, so only presence bytes + scalars are emitted.
    static func psysData(
        maxParticles: UInt16,
        hasRadii: Bool = false,
        hasSizes: Bool = false,
        hasRotations: Bool = false,
        hasRotationAngles: Bool = false,
        hasRotationAxes: Bool = false,
        hasTextureIndices: Bool = false,
        subtextureOffsets: [SIMD4<Float>] = [],
        hasRotationSpeeds: Bool = false,
        stripTail: StripTail? = nil
    ) -> Data {
        var out = Data()
        // NiGeometryData (BS202, NiPSysData variant).
        out.appendUInt32(0) // Group ID
        out.appendUInt16(maxParticles) // BS Max Vertices
        out.append(contentsOf: [0, 0]) // Keep + Compress Flags
        out.append(1) // Has Vertices
        out.appendUInt16(0) // BS Data Flags
        out.appendUInt32(0) // Material CRC
        out.append(0) // Has Normals
        out.append(Data(count: 16)) // Bounding Sphere
        out.append(0) // Has Vertex Colors
        out.appendUInt16(0) // Consistency Flags
        out.appendUInt32(0xFFFF_FFFF) // Additional Data ref
        // NiParticlesData (BS202).
        out.append(hasRadii ? 1 : 0)
        out.appendUInt16(0) // Num Active
        out.append(hasSizes ? 1 : 0)
        out.append(hasRotations ? 1 : 0)
        out.append(hasRotationAngles ? 1 : 0)
        out.append(hasRotationAxes ? 1 : 0)
        out.append(hasTextureIndices ? 1 : 0)
        out.appendUInt32(UInt32(subtextureOffsets.count))
        for offset in subtextureOffsets {
            out.appendFloat32(offset.x)
            out.appendFloat32(offset.y)
            out.appendFloat32(offset.z)
            out.appendFloat32(offset.w)
        }
        out.appendFloat32(1) // Aspect Ratio
        out.appendUInt16(0) // Aspect Flags
        out.append(Data(count: 12)) // Speed-to-Aspect trio
        // NiPSysData (BS202).
        out.append(hasRotationSpeeds ? 1 : 0)
        if let tail = stripTail {
            out.appendUInt16(tail.maxPointCount)
            out.appendFloat32(tail.startCap)
            out.appendFloat32(tail.endCap)
            out.append(tail.zPrepass ? 1 : 0)
        }
        return out
    }

    /// NiParticleSystem payload, BS stream 100 (SSE) layout.
    static func particleSystemSSE(
        prefix: Data = NIFFixture.avObjectPrefix(),
        skinRef: Int32 = -1,
        shaderPropertyRef: Int32 = -1,
        alphaPropertyRef: Int32 = -1,
        dataRef: Int32,
        worldSpace: Bool = true,
        modifierRefs: [Int32] = []
    ) -> Data {
        var out = prefix
        out.append(Data(count: 16)) // NiBound
        out.appendUInt32(UInt32(bitPattern: skinRef))
        out.appendUInt32(UInt32(bitPattern: shaderPropertyRef))
        out.appendUInt32(UInt32(bitPattern: alphaPropertyRef))
        out.appendUInt64(0) // BSVertexDesc
        out.append(Data(count: 8)) // Far/Near cull shorts
        out.appendUInt32(UInt32(bitPattern: dataRef))
        out.append(worldSpace ? 1 : 0)
        appendRefs(&out, modifierRefs)
        return out
    }

    /// NiParticleSystem payload, BS stream 83 (Skyrim LE) layout.
    static func particleSystemLE(
        prefix: Data = NIFFixture.avObjectPrefix(),
        dataRef: Int32,
        skinInstanceRef: Int32 = -1,
        materialNames: [Int32] = [],
        shaderPropertyRef: Int32 = -1,
        alphaPropertyRef: Int32 = -1,
        worldSpace: Bool = true,
        modifierRefs: [Int32] = []
    ) -> Data {
        var out = prefix
        out.appendUInt32(UInt32(bitPattern: dataRef))
        out.appendUInt32(UInt32(bitPattern: skinInstanceRef))
        // MaterialData: count, name+extra pairs, active index, needs-update.
        out.appendUInt32(UInt32(materialNames.count))
        for name in materialNames {
            out.appendUInt32(UInt32(bitPattern: name)) // Material Name
            out.appendUInt32(0xFFFF_FFFF) // Material Extra Data
        }
        out.appendUInt32(0xFFFF_FFFF) // Active Material
        out.append(0) // Material Needs Update
        out.appendUInt32(UInt32(bitPattern: shaderPropertyRef))
        out.appendUInt32(UInt32(bitPattern: alphaPropertyRef))
        out.append(Data(count: 8)) // Far/Near cull shorts
        out.append(worldSpace ? 1 : 0)
        appendRefs(&out, modifierRefs)
        return out
    }

    /// NiPSysModifier base run shared by every modifier + emitter payload.
    static func modifierBase(
        nameIndex: UInt32 = 0xFFFF_FFFF,
        order: UInt32 = 0,
        targetRef: Int32 = -1,
        active: Bool = true
    ) -> Data {
        var out = Data()
        out.appendUInt32(nameIndex)
        out.appendUInt32(order)
        out.appendUInt32(UInt32(bitPattern: targetRef))
        out.append(active ? 1 : 0)
        return out
    }

    /// NiPSysEmitter birth-parameter run, appended after modifierBase.
    static func emitterBase(
        speed: Float = 0,
        speedVariation: Float = 0,
        declination: Float = 0,
        declinationVariation: Float = 0,
        planarAngle: Float = 0,
        planarAngleVariation: Float = 0,
        initialColor: SIMD4<Float> = SIMD4(1, 1, 1, 1),
        initialRadius: Float = 1,
        radiusVariation: Float = 0,
        lifeSpan: Float = 1,
        lifeSpanVariation: Float = 0
    ) -> Data {
        var out = Data()
        for value in [
            speed, speedVariation, declination, declinationVariation,
            planarAngle, planarAngleVariation
        ] {
            out.appendFloat32(value)
        }
        out.appendFloat32(initialColor.x)
        out.appendFloat32(initialColor.y)
        out.appendFloat32(initialColor.z)
        out.appendFloat32(initialColor.w)
        out.appendFloat32(initialRadius)
        out.appendFloat32(radiusVariation)
        out.appendFloat32(lifeSpan)
        out.appendFloat32(lifeSpanVariation)
        return out
    }

    static func boxEmitter(
        base: Data,
        emitter: Data,
        emitterObjectRef: Int32 = -1,
        width: Float,
        height: Float,
        depth: Float
    ) -> Data {
        var out = base + emitter
        out.appendUInt32(UInt32(bitPattern: emitterObjectRef))
        out.appendFloat32(width)
        out.appendFloat32(height)
        out.appendFloat32(depth)
        return out
    }

    static func sphereEmitter(
        base: Data,
        emitter: Data,
        emitterObjectRef: Int32 = -1,
        radius: Float
    ) -> Data {
        var out = base + emitter
        out.appendUInt32(UInt32(bitPattern: emitterObjectRef))
        out.appendFloat32(radius)
        return out
    }

    static func meshEmitter(
        base: Data,
        emitter: Data,
        meshRefs: [Int32],
        velocityType: UInt32 = 0
    ) -> Data {
        var out = base + emitter
        out.appendUInt32(UInt32(meshRefs.count))
        for ref in meshRefs {
            out.appendUInt32(UInt32(bitPattern: ref))
        }
        out.appendUInt32(velocityType)
        out.appendUInt32(0) // Emission Type
        out.append(Data(count: 12)) // Emission Axis (Vector3)
        return out
    }

    static func gravityModifier(
        base: Data,
        axis: SIMD3<Float>,
        strength: Float
    ) -> Data {
        var out = base
        out.appendUInt32(0xFFFF_FFFF) // Gravity Object ptr
        out.appendFloat32(axis.x)
        out.appendFloat32(axis.y)
        out.appendFloat32(axis.z)
        out.appendFloat32(0) // Decay
        out.appendFloat32(strength)
        out.appendUInt32(0) // Force Type
        out.appendFloat32(0) // Turbulence
        out.appendFloat32(1) // Turbulence Scale
        out.append(0) // World Aligned
        return out
    }

    static func scaleModifier(base: Data, scales: [Float]) -> Data {
        var out = base
        out.appendUInt32(UInt32(scales.count))
        for scale in scales {
            out.appendFloat32(scale)
        }
        return out
    }

    static func lodModifier(
        base: Data,
        beginDistance: Float,
        endDistance: Float,
        endEmitScale: Float,
        endSize: Float
    ) -> Data {
        var out = base
        out.appendFloat32(beginDistance)
        out.appendFloat32(endDistance)
        out.appendFloat32(endEmitScale)
        out.appendFloat32(endSize)
        return out
    }

    private static func appendRefs(_ out: inout Data, _ refs: [Int32]) {
        out.appendUInt32(UInt32(refs.count))
        for ref in refs {
            out.appendUInt32(UInt32(bitPattern: ref))
        }
    }
}
