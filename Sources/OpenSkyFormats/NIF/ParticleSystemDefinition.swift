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
nonisolated package struct ParticleSystemDefinition: Equatable {
    /// NiObjectNET name; nil when unnamed or the string index is junk.
    package let name: String?
    /// Accumulated parent transform times the system's own local transform.
    package let worldTransform: float4x4
    /// nif.xml World Space: true = particles birth into world space, false =
    /// object space. Governs how playback (7.3.2) treats worldTransform.
    package let worldSpace: Bool
    /// NiPSysData "BS Max Vertices" — max simultaneous particles (capacity).
    /// 0 when the data block ref is absent.
    package let maxParticles: Int
    package let emitters: [ParticleEmitter]
    package let modifiers: [ParticleModifier]
    /// NiPSysData subtexture atlas offsets (UV quads), empty when unused.
    package let subtextureOffsets: [SIMD4<Float>]
    /// BSShaderProperty block index; -1 = none. Kept raw so callers can spot
    /// systems whose shader is not a BSEffectShaderProperty.
    package let shaderPropertyRef: Int32
    /// NiAlphaProperty block index; -1 = none.
    package let alphaPropertyRef: Int32
    /// Resolved shader material when `shaderPropertyRef` points at a
    /// BSEffectShaderProperty; nil for none or other shader types
    /// (BSLightingShaderProperty on a particle shape is legitimate content).
    package let effectShader: NIFEffectShaderProperty?
    /// Resolved blend/test state when `alphaPropertyRef` points at a
    /// NiAlphaProperty.
    package let alphaProperty: NIFAlphaProperty?

    package init(
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
nonisolated package struct ParticleEmitter: Equatable {
    package let name: String?
    /// nif.xml NiPSysModifierOrder — position in the modifier chain.
    package let order: UInt32
    package let active: Bool
    package let speed: Float
    package let speedVariation: Float
    package let declination: Float
    package let declinationVariation: Float
    package let planarAngle: Float
    package let planarAngleVariation: Float
    /// RGBA birth color in [0, 1].
    package let initialColor: SIMD4<Float>
    package let initialRadius: Float
    package let radiusVariation: Float
    package let lifeSpan: Float
    package let lifeSpanVariation: Float
    package let shape: Shape

    package init(
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
    package enum Shape: Equatable {
        case box(width: Float, height: Float, depth: Float)
        case cylinder(radius: Float, height: Float)
        case sphere(radius: Float)
        /// Emitter mesh block refs + nif.xml VelocityType. Mesh sampling
        /// itself is deferred; only the refs + mode are recorded.
        case mesh(meshRefs: [Int32], initialVelocityType: UInt32)
    }
}

/// A non-emitter NiPSysModifier leaf: shared identity plus the concrete kind.
nonisolated package struct ParticleModifier: Equatable {
    package let name: String?
    package let order: UInt32
    package let active: Bool
    package let kind: Kind

    package init(name: String?, order: UInt32, active: Bool, kind: Kind) {
        self.name = name
        self.order = order
        self.active = active
        self.kind = kind
    }

    /// Concrete modifier type. Unknown/unsupported types are carried by name
    /// so the caller can note + skip them without the decode throwing.
    package enum Kind: Equatable {
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
