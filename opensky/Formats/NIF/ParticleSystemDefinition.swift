// Engine-facing particle-system value types: the clean, on-disk-decoupled
// result of decoding a NiParticleSystem / BSStripParticleSystem leaf and its
// modifier chain. Static decode only (milestone 7.3.1): capacity, emitter
// shapes, modifier identities + a few salient params, and the shader/alpha
// property block refs (kept as raw indices — the shader property blocks are
// owned by another subsystem and wired later, milestone 7.3.2 does playback).
//
// Reference: NifTools nif.xml (NiParticleSystem, NiPSysData, NiPSysEmitter and
// concrete emitter/modifier blocks).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-particles.md.

import Foundation
import simd

/// One particle system collected from the scene graph, in model space.
nonisolated struct ParticleSystemDefinition: Equatable {
    /// NiObjectNET name; nil when unnamed or the string index is junk.
    let name: String?
    /// Accumulated parent transform times the system's own local transform.
    let worldTransform: float4x4
    /// nif.xml World Space: true = particles birth into world space, false =
    /// object space. Governs how playback (7.3.2) treats worldTransform.
    let worldSpace: Bool
    /// NiPSysData "BS Max Vertices" — max simultaneous particles (capacity).
    /// 0 when the data block ref is absent.
    let maxParticles: Int
    let emitters: [ParticleEmitter]
    let modifiers: [ParticleModifier]
    /// NiPSysData subtexture atlas offsets (UV quads), empty when unused.
    let subtextureOffsets: [SIMD4<Float>]
    /// BSShaderProperty block index; -1 = none. Not resolved here.
    let shaderPropertyRef: Int32
    /// NiAlphaProperty block index; -1 = none. Not resolved here.
    let alphaPropertyRef: Int32
}

/// A NiPSysEmitter leaf: shared birth parameters plus the emission volume.
nonisolated struct ParticleEmitter: Equatable {
    let name: String?
    /// nif.xml NiPSysModifierOrder — position in the modifier chain.
    let order: UInt32
    let active: Bool
    let speed: Float
    let speedVariation: Float
    let declination: Float
    let declinationVariation: Float
    let planarAngle: Float
    let planarAngleVariation: Float
    /// RGBA birth color in [0, 1].
    let initialColor: SIMD4<Float>
    let initialRadius: Float
    let radiusVariation: Float
    let lifeSpan: Float
    let lifeSpanVariation: Float
    let shape: Shape

    /// Emission volume + its type-specific parameters.
    enum Shape: Equatable {
        case box(width: Float, height: Float, depth: Float)
        case cylinder(radius: Float, height: Float)
        case sphere(radius: Float)
        /// Emitter mesh block refs + nif.xml VelocityType. Mesh sampling
        /// itself is deferred; only the refs + mode are recorded.
        case mesh(meshRefs: [Int32], initialVelocityType: UInt32)
    }
}

/// A non-emitter NiPSysModifier leaf: shared identity plus the concrete kind.
nonisolated struct ParticleModifier: Equatable {
    let name: String?
    let order: UInt32
    let active: Bool
    let kind: Kind

    /// Concrete modifier type. Unknown/unsupported types are carried by name
    /// so the caller can note + skip them without the decode throwing.
    enum Kind: Equatable {
        case ageDeath
        case spawn
        case gravity(axis: SIMD3<Float>, strength: Float)
        case rotation
        case position
        case boundUpdate
        case drag
        case simpleColor
        case scale(scales: [Float])
        case wind(strength: Float)
        case inheritVelocity
        case subTex
        case lod(beginDistance: Float, endDistance: Float, endEmitScale: Float, endSize: Float)
        /// Any modifier type this decoder does not model.
        case unsupported(typeName: String)
    }
}
