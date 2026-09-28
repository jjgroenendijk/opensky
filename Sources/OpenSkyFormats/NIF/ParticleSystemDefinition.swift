// Engine-facing particle-system value types: the clean, on-disk-decoupled
// result of decoding a NiParticleSystem / BSStripParticleSystem leaf and its
// modifier chain. Static decode only (milestone 7.3.1): capacity, emitter
// shapes, modifier identities + a few salient params, and the resolved
// effect-shader/alpha property blocks (milestone 7.3.2 does playback).
//
// Reference: NifTools nif.xml (NiParticleSystem, NiPSysData, NiPSysEmitter and
// concrete emitter/modifier blocks).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-particles.md.

import Foundation
import simd

/// One particle system collected from the scene graph, in model space.
nonisolated public struct ParticleSystemDefinition: Equatable, Sendable {
    /// NiObjectNET name; nil when unnamed or the string index is junk.
    public let name: String?
    /// Accumulated parent transform times the system's own local transform.
    public let worldTransform: float4x4
    /// nif.xml World Space: true = particles birth into world space, false =
    /// object space. Governs how playback (7.3.2) treats worldTransform.
    public let worldSpace: Bool
    /// NiPSysData "BS Max Vertices" — max simultaneous particles (capacity).
    /// 0 when the data block ref is absent.
    public let maxParticles: Int
    public let emitters: [ParticleEmitter]
    public let modifiers: [ParticleModifier]
    /// NiPSysData subtexture atlas offsets (UV quads), empty when unused.
    public let subtextureOffsets: [SIMD4<Float>]
    /// BSShaderProperty block index; -1 = none. Kept raw so callers can spot
    /// systems whose shader is not a BSEffectShaderProperty.
    public let shaderPropertyRef: Int32
    /// NiAlphaProperty block index; -1 = none.
    public let alphaPropertyRef: Int32
    /// Resolved shader material when `shaderPropertyRef` points at a
    /// BSEffectShaderProperty; nil for none or other shader types
    /// (BSLightingShaderProperty on a particle shape is legitimate content).
    public let effectShader: NIFEffectShaderProperty?
    /// Resolved blend/test state when `alphaPropertyRef` points at a
    /// NiAlphaProperty.
    public let alphaProperty: NIFAlphaProperty?

    public init(
        name: String?,
        worldTransform: float4x4,
        worldSpace: Bool,
        maxParticles: Int,
        emitters: [ParticleEmitter],
        modifiers: [ParticleModifier],
        subtextureOffsets: [SIMD4<Float>],
        shaderPropertyRef: Int32,
        alphaPropertyRef: Int32,
        effectShader: NIFEffectShaderProperty?,
        alphaProperty: NIFAlphaProperty?
    ) {
        self.name = name
        self.worldTransform = worldTransform
        self.worldSpace = worldSpace
        self.maxParticles = maxParticles
        self.emitters = emitters
        self.modifiers = modifiers
        self.subtextureOffsets = subtextureOffsets
        self.shaderPropertyRef = shaderPropertyRef
        self.alphaPropertyRef = alphaPropertyRef
        self.effectShader = effectShader
        self.alphaProperty = alphaProperty
    }
}

/// A NiPSysEmitter leaf: shared birth parameters plus the emission volume.
nonisolated public struct ParticleEmitter: Equatable, Sendable {
    public let name: String?
    /// nif.xml NiPSysModifierOrder — position in the modifier chain.
    public let order: UInt32
    public let active: Bool
    public let speed: Float
    public let speedVariation: Float
    public let declination: Float
    public let declinationVariation: Float
    public let planarAngle: Float
    public let planarAngleVariation: Float
    /// RGBA birth color in [0, 1].
    public let initialColor: SIMD4<Float>
    public let initialRadius: Float
    public let radiusVariation: Float
    public let lifeSpan: Float
    public let lifeSpanVariation: Float
    public let shape: Shape

    public init(
        name: String?,
        order: UInt32,
        active: Bool,
        speed: Float,
        speedVariation: Float,
        declination: Float,
        declinationVariation: Float,
        planarAngle: Float,
        planarAngleVariation: Float,
        initialColor: SIMD4<Float>,
        initialRadius: Float,
        radiusVariation: Float,
        lifeSpan: Float,
        lifeSpanVariation: Float,
        shape: Shape
    ) {
        self.name = name
        self.order = order
        self.active = active
        self.speed = speed
        self.speedVariation = speedVariation
        self.declination = declination
        self.declinationVariation = declinationVariation
        self.planarAngle = planarAngle
        self.planarAngleVariation = planarAngleVariation
        self.initialColor = initialColor
        self.initialRadius = initialRadius
        self.radiusVariation = radiusVariation
        self.lifeSpan = lifeSpan
        self.lifeSpanVariation = lifeSpanVariation
        self.shape = shape
    }

    /// Emission volume + its type-specific parameters.
    public enum Shape: Equatable, Sendable {
        case box(width: Float, height: Float, depth: Float)
        case cylinder(radius: Float, height: Float)
        case sphere(radius: Float)
        /// Emitter mesh block refs + nif.xml VelocityType. Mesh sampling
        /// itself is deferred; only the refs + mode are recorded.
        case mesh(meshRefs: [Int32], initialVelocityType: UInt32)
    }
}

/// A non-emitter NiPSysModifier leaf: shared identity plus the concrete kind.
nonisolated public struct ParticleModifier: Equatable, Sendable {
    public let name: String?
    public let order: UInt32
    public let active: Bool
    public let kind: Kind

    public init(name: String?, order: UInt32, active: Bool, kind: Kind) {
        self.name = name
        self.order = order
        self.active = active
        self.kind = kind
    }

    /// Concrete modifier type. Unknown/unsupported types are carried by name
    /// so the caller can note + skip them without the decode throwing.
    public enum Kind: Equatable, Sendable {
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
