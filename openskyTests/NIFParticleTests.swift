// NIF particle-system decode tests over synthetic in-code payloads
// (NIFParticleFixture). Covers end-to-end scene-graph decode via
// particleSystems(), both BS stream 83 + 100 NiParticleSystem layouts, NiPSysData
// capacity/flags, every emitter shape, modifier identification incl. unknown ->
// .unsupported, and defensive rejection of truncated + out-of-range input.
// Layouts per NifTools nif.xml; docs/formats/nif-particles.md.

import Foundation
@testable import opensky
import simd
import Testing

struct NIFParticleTests {
    private func header(bsVersion: UInt32 = 100) throws -> NIFHeader {
        var reader = BinaryReader(NIFFixture.header(bsVersion: bsVersion))
        return try NIFHeader(reader: &reader)
    }

    // MARK: End-to-end scene-graph decode

    /// Builds root node -> SSE particle system with a box emitter and four
    /// modifiers (age-death, gravity, scale, LOD).
    private func fullSystemFile() -> Data {
        let boxEmitter = NIFParticleFixture.boxEmitter(
            base: NIFParticleFixture.modifierBase(nameIndex: 1, order: 0),
            emitter: NIFParticleFixture.emitterBase(
                speed: 25, initialColor: SIMD4(0.5, 0.6, 0.7, 1), initialRadius: 3,
                lifeSpan: 2.5
            ),
            width: 10, height: 20, depth: 30
        )
        let gravity = NIFParticleFixture.gravityModifier(
            base: NIFParticleFixture.modifierBase(order: 4),
            axis: SIMD3(0, 0, -1), strength: 9.8
        )
        let scale = NIFParticleFixture.scaleModifier(
            base: NIFParticleFixture.modifierBase(), scales: [0.1, 0.5, 1.0]
        )
        let lod = NIFParticleFixture.lodModifier(
            base: NIFParticleFixture.modifierBase(),
            beginDistance: 0.1, endDistance: 0.7, endEmitScale: 0.2, endSize: 1
        )
        let system = NIFParticleFixture.particleSystemSSE(
            prefix: NIFFixture.avObjectPrefix(nameIndex: 0, translation: SIMD3(5, 0, 0)),
            shaderPropertyRef: 8, alphaPropertyRef: 9,
            dataRef: 2, worldSpace: true, modifierRefs: [3, 4, 5, 6, 7]
        )
        return NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(translation: SIMD3(0, 100, 0)),
                    children: [1]
                )),
                NIFFixture.Block("NiParticleSystem", system),
                NIFFixture.Block("NiPSysData", NIFParticleFixture.psysData(
                    maxParticles: 128, hasRadii: true, hasRotationSpeeds: true
                )),
                NIFFixture.Block("NiPSysBoxEmitter", boxEmitter),
                NIFFixture.Block("NiPSysAgeDeathModifier", NIFParticleFixture.modifierBase()),
                NIFFixture.Block("NiPSysGravityModifier", gravity),
                NIFFixture.Block("BSPSysScaleModifier", scale),
                NIFFixture.Block("BSPSysLODModifier", lod),
                NIFFixture.Block(
                    "BSEffectShaderProperty",
                    NIFParticleFixture.effectShaderProperty(
                        flags1: 0x4000_0000, // Soft_Effect
                        flags2: 0x10, // Double_Sided, ZBuffer_Write clear
                        sourceTexture: "textures/effects/synthfire.dds",
                        softFalloffDepth: 10
                    )
                ),
                NIFFixture.Block(
                    "NiAlphaProperty",
                    NIFParticleFixture.alphaProperty(flags: 0x0001, threshold: 128)
                )
            ],
            strings: ["Fire", "BoxEmitter"],
            roots: [0]
        )
    }

    /// Full system decoded through particleSystems(): name, capacity, refs,
    /// world transform, emitter shape, and the modifier chain round-trip.
    @Test func decodesFullSystemEndToEnd() throws {
        let file = try NIFFile(data: fullSystemFile())
        let systems = try file.particleSystems()
        try #require(systems.count == 1)
        let decoded = systems[0]
        #expect(decoded.name == "Fire")
        #expect(decoded.worldSpace)
        #expect(decoded.maxParticles == 128)
        #expect(decoded.shaderPropertyRef == 8)
        #expect(decoded.alphaPropertyRef == 9)

        // Shader + alpha refs resolve to typed engine values.
        let shader = try #require(decoded.effectShader)
        #expect(shader.isSoftEffect)
        #expect(shader.isDoubleSided)
        #expect(shader.isZBufferWriteDisabled)
        #expect(shader.sourceTexture == "textures/effects/synthfire.dds")
        #expect(shader.softFalloffDepth == 10)
        let alpha = try #require(decoded.alphaProperty)
        #expect(alpha.blendEnabled)
        #expect(!alpha.testEnabled)
        // Parent node translate (0,100,0) composed with local (5,0,0).
        #expect(decoded.worldTransform.columns.3.x == 5)
        #expect(decoded.worldTransform.columns.3.y == 100)

        try #require(decoded.emitters.count == 1)
        let emitter = decoded.emitters[0]
        #expect(emitter.name == "BoxEmitter")
        #expect(emitter.speed == 25)
        #expect(emitter.initialRadius == 3)
        #expect(emitter.lifeSpan == 2.5)
        #expect(emitter.initialColor == SIMD4(0.5, 0.6, 0.7, 1))
        #expect(emitter.shape == .box(width: 10, height: 20, depth: 30))

        // Four non-emitter modifiers, in chain order.
        try #require(decoded.modifiers.count == 4)
        #expect(decoded.modifiers[0].kind == .ageDeath)
        #expect(decoded.modifiers[1].kind == .gravity(axis: SIMD3(0, 0, -1), strength: 9.8))
        #expect(decoded.modifiers[1].order == 4)
        #expect(decoded.modifiers[2].kind == .scale(scales: [0.1, 0.5, 1.0]))
        #expect(decoded.modifiers[3].kind == .lod(
            beginDistance: 0.1, endDistance: 0.7, endEmitScale: 0.2, endSize: 1
        ))
    }

    /// Same system but with an unknown modifier type in the chain: it must be
    /// carried as .unsupported, not throw.
    @Test func unknownModifierBecomesUnsupported() throws {
        let system = NIFParticleFixture.particleSystemSSE(
            dataRef: 2, modifierRefs: [3]
        )
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(children: [1])),
                NIFFixture.Block("NiParticleSystem", system),
                NIFFixture.Block("NiPSysData", NIFParticleFixture.psysData(maxParticles: 4)),
                NIFFixture.Block(
                    "NiPSysColliderManager",
                    NIFParticleFixture.modifierBase() + Data(count: 4)
                )
            ],
            roots: [0]
        ))

        let systems = try file.particleSystems()
        try #require(systems.count == 1)
        try #require(systems[0].modifiers.count == 1)
        #expect(systems[0].modifiers[0].kind == .unsupported(typeName: "NiPSysColliderManager"))
    }

    /// A shader ref that is not a BSEffectShaderProperty (lit particle
    /// shapes carry BSLightingShaderProperty) resolves to nil, not an error.
    @Test func nonEffectShaderRefResolvesNil() throws {
        let system = NIFParticleFixture.particleSystemSSE(
            shaderPropertyRef: 2, dataRef: -1
        )
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(children: [1])),
                NIFFixture.Block("NiParticleSystem", system),
                NIFFixture.Block("BSLightingShaderProperty", Data(count: 4))
            ],
            roots: [0]
        ))
        let systems = try file.particleSystems()
        try #require(systems.count == 1)
        #expect(systems[0].effectShader == nil)
        #expect(systems[0].shaderPropertyRef == 2)
    }

    // MARK: Emitter shapes

    @Test func decodesSphereEmitter() throws {
        let payload = NIFParticleFixture.sphereEmitter(
            base: NIFParticleFixture.modifierBase(),
            emitter: NIFParticleFixture.emitterBase(),
            radius: 7.5
        )
        let emitter = try NIFParticleModifierDecoder.emitter(
            typeName: "NiPSysSphereEmitter", data: payload, header: header()
        )
        #expect(emitter.shape == .sphere(radius: 7.5))
    }

    @Test func decodesMeshEmitter() throws {
        let payload = NIFParticleFixture.meshEmitter(
            base: NIFParticleFixture.modifierBase(),
            emitter: NIFParticleFixture.emitterBase(),
            meshRefs: [5, 6], velocityType: 2
        )
        let emitter = try NIFParticleModifierDecoder.emitter(
            typeName: "NiPSysMeshEmitter", data: payload, header: header()
        )
        #expect(emitter.shape == .mesh(meshRefs: [5, 6], initialVelocityType: 2))
    }

    // MARK: NiPSysData

    @Test func decodesPSysDataFlagsAndSubtextures() throws {
        let offsets = [SIMD4<Float>(0, 0, 0.5, 0.5), SIMD4(0.5, 0, 1, 0.5)]
        let payload = NIFParticleFixture.psysData(
            maxParticles: 512,
            hasRadii: true, hasSizes: true, hasRotations: true,
            hasRotationAngles: true, hasRotationAxes: true,
            hasTextureIndices: true, subtextureOffsets: offsets,
            hasRotationSpeeds: true
        )
        let data = try NIFParticleData(data: payload, header: header())
        #expect(data.maxParticles == 512)
        #expect(data.hasRadii)
        #expect(data.hasSizes)
        #expect(data.hasRotations)
        #expect(data.hasRotationAngles)
        #expect(data.hasRotationAxes)
        #expect(data.hasTextureIndices)
        #expect(data.hasRotationSpeeds)
        #expect(data.subtextureOffsets == offsets)
        #expect(data.maxPointCount == nil)
    }

    @Test func decodesBSStripPSysDataTail() throws {
        let payload = NIFParticleFixture.psysData(
            maxParticles: 16,
            stripTail: NIFParticleFixture.StripTail(
                maxPointCount: 64, startCap: 1, endCap: 2, zPrepass: true
            )
        )
        let data = try NIFParticleData(data: payload, header: header(), isStrip: true)
        #expect(data.maxParticles == 16)
        #expect(data.maxPointCount == 64)
    }

    // MARK: Stream 83 layout

    /// Skyrim LE (BS stream 83) NiParticleSystem uses the classic NiGeometry
    /// rows (data + skin-instance + material-data) with no inline vertex desc.
    @Test func decodesStream83System() throws {
        let payload = NIFParticleFixture.particleSystemLE(
            dataRef: 2, skinInstanceRef: -1, materialNames: [3],
            shaderPropertyRef: 4, alphaPropertyRef: 5,
            worldSpace: false, modifierRefs: [6, 7]
        )
        let system = try NIFParticleSystem(data: payload, header: header(bsVersion: 83))
        #expect(system.dataRef == 2)
        #expect(system.shaderPropertyRef == 4)
        #expect(system.alphaPropertyRef == 5)
        #expect(!system.worldSpace)
        #expect(system.modifierRefs == [6, 7])
    }

    // MARK: Defensive parsing

    @Test func truncatedBlockThrows() throws {
        let full = NIFParticleFixture.particleSystemSSE(dataRef: 2, modifierRefs: [3])
        let truncated = full.prefix(full.count - 3) // drop into the modifier refs
        #expect(throws: (any Error).self) {
            _ = try NIFParticleSystem(data: Data(truncated), header: header())
        }
    }

    @Test func outOfRangeDataRefRejected() throws {
        // dataRef 9 has no matching block -> the walk rejects it.
        let system = NIFParticleFixture.particleSystemSSE(dataRef: 9)
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(children: [1])),
                NIFFixture.Block("NiParticleSystem", system)
            ],
            roots: [0]
        ))
        #expect(throws: NIFError.self) {
            _ = try file.particleSystems()
        }
    }

    @Test func outOfRangeModifierRefRejected() throws {
        let system = NIFParticleFixture.particleSystemSSE(dataRef: 2, modifierRefs: [9])
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(children: [1])),
                NIFFixture.Block("NiParticleSystem", system),
                NIFFixture.Block("NiPSysData", NIFParticleFixture.psysData(maxParticles: 4))
            ],
            roots: [0]
        ))
        #expect(throws: NIFError.self) {
            _ = try file.particleSystems()
        }
    }

    /// A file with no particle blocks yields an empty result, not an error.
    @Test func fileWithoutParticlesYieldsEmpty() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [NIFFixture.Block("NiNode", NIFFixture.niNode(children: []))],
            roots: [0]
        ))
        #expect(try file.particleSystems().isEmpty)
    }
}
