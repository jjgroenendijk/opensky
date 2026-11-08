// The particle modifiers with parameters: their layouts, their placement by the
// scene walk, their controllers, and the maths the simulation uses.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFParticleParameterTests {
    private typealias Fixture = NIFParticleParameterFixture

    @Test func readsEveryParameterModifierToItsLastByte() throws {
        #expect(try kind(NIFRotationModifier.typeName, Fixture.rotation(
            speed: 2, angle: 0.5, randomSign: true
        )) == .rotation(ParticleRotation(
            speed: 2, speedVariation: 0, angle: 0.5, angleVariation: 0, randomSpeedSign: true,
            randomAxis: true, axis: SIMD3(1, 0, 0)
        )))
        #expect(try kind(NIFSpawnModifier.typeName, Fixture.spawn(
            generations: 2, maximum: 3, lifeSpan: 0.5
        )) == .spawn(ParticleSpawn(
            generations: 2, percentage: 1, minimumCount: 1, maximumCount: 3, speedVariation: 0,
            directionVariation: 0, lifeSpan: 0.5, lifeSpanVariation: 0
        )))
        #expect(try kind(NIFDragModifier.typeName, Fixture.drag(
            objectRef: -1, percentage: 0.1, range: 5
        )) == .drag(ParticleDrag(
            position: .zero, axis: SIMD3(0, 0, 1), percentage: 0.1, range: 5, rangeFalloff: 0
        )))
        #expect(try kind(NIFInheritVelocityModifier.typeName, Fixture.inheritVelocity(
            chance: 50, multiplier: 0.5
        )) == .inheritVelocity(ParticleInheritVelocity(chance: 50, multiplier: 0.5, variation: 0)))
        #expect(try kind(NIFSubTexModifier.typeName, Fixture.subTex(frames: SIMD4(0, 3, 1, 8)))
            == .subTex(ParticleSubTexture(
                startFrame: 0, startFrameFudge: 0, endFrame: 3, loopStartFrame: 1,
                loopStartFrameFudge: 0, frameCount: 8, frameCountFudge: 0
            )))
        #expect(try kind("NiPSysBoundUpdateModifier", Fixture.boundUpdate(skip: 3))
            == .boundUpdate(skip: 3))
        #expect(try kind(NIFAgeDeathModifier.typeName, Fixture.ageDeath(
            spawnsOnDeath: true, spawnRef: 4
        )) == .ageDeath(spawn: nil))
        #expect(try kind(NIFGravityModifier.typeName, Fixture.sphericalGravity(
            objectRef: -1, strength: 3, decay: 0
        )) == .gravity(ParticleGravity(
            position: .zero, axis: SIMD3(0, 0, 1), decay: 0, strength: 3, force: .spherical
        )))
    }

    @Test func theWalkPlacesGravityAndResolvesTheDeathSpawn() throws {
        let system = NIFParticleFixture.particleSystemSSE(
            prefix: NIFFixture.avObjectPrefix(nameIndex: 0), dataRef: 3, modifierRefs: [4, 5]
        )
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(children: [1, 2])),
                NIFFixture.Block("NiParticleSystem", system),
                NIFFixture.Block("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(translation: SIMD3(0, 0, 50))
                )),
                NIFFixture.Block("NiPSysData", NIFParticleFixture.psysData(maxParticles: 8)),
                NIFFixture.Block(NIFGravityModifier.typeName, Fixture.sphericalGravity(
                    objectRef: 2, strength: 4, decay: 0
                )),
                NIFFixture.Block(NIFAgeDeathModifier.typeName, Fixture.ageDeath(
                    spawnsOnDeath: true, spawnRef: 6
                )),
                NIFFixture.Block(NIFSpawnModifier.typeName, Fixture.spawn(
                    generations: 0, maximum: 2, lifeSpan: 1
                ))
            ],
            strings: ["Sparks"]
        ))
        let modifiers = try #require(file.particleSystems().first).modifiers
        guard case let .gravity(gravity) = modifiers.first?.kind else {
            Issue.record("expected gravity, got \(String(describing: modifiers.first?.kind))")
            return
        }
        #expect(gravity.position == SIMD3(0, 0, 50))
        #expect(gravity.acceleration(at: .zero) == SIMD3(0, 0, 4))
        guard case let .ageDeath(spawn?) = modifiers.last?.kind else {
            Issue.record("expected a death spawn, got \(String(describing: modifiers.last?.kind))")
            return
        }
        #expect(spawn.maximumCount == 2)
    }

    @Test func controllersSetGravityStrengthAndRotationSpeed() {
        let timing = ControllerTiming(
            cycle: .clamp, frequency: 1, phase: 0, startTime: 0, stopTime: 1
        )
        let gravity = ParticleGravity(
            position: .zero, axis: SIMD3(0, 0, -1), decay: 0, strength: 1, force: .planar
        )
        let rotation = ParticleRotation(
            speed: 1, speedVariation: 0, angle: 0, angleVariation: 0, randomSpeedSign: false,
            randomAxis: false, axis: SIMD3(1, 0, 0)
        )
        let controllers = [
            ParticleModifierController(
                parameter: .gravityStrength, modifierName: "Pull", timing: timing,
                floatKeys: [NIFKey(time: 0, value: 6)]
            ),
            ParticleModifierController(
                parameter: .initialRotationSpeed, modifierName: "Spin", timing: timing,
                floatKeys: [NIFKey(time: 0, value: 3)]
            )
        ]
        let pulled = ParticleModifier(name: "Pull", order: 0, active: true, kind: .gravity(gravity))
            .controlled(by: controllers, at: 0)
        let spun = ParticleModifier(name: "Spin", order: 0, active: true, kind: .rotation(rotation))
            .controlled(by: controllers, at: 0)
        #expect(pulled.kind == .gravity(ParticleGravity(
            position: .zero, axis: SIMD3(0, 0, -1), decay: 0, strength: 6, force: .planar
        )))
        guard case let .rotation(controlled) = spun.kind else {
            Issue.record("expected rotation")
            return
        }
        #expect(controlled.speed == 3)
    }

    @Test func gravityKeepsAWorldAlignedAxisAndFadesWithDecay() {
        var turn = float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)))
        turn.columns.3 = SIMD4(0, 0, 10, 1)
        let local = ParticleGravity(
            position: .zero, axis: SIMD3(0, 0, -1), decay: 0, strength: 1, force: .planar
        )
        var aligned = local
        aligned.worldAligned = true
        #expect(simd_distance(local.transformed(by: turn).axis, SIMD3(0, 1, 0)) < 1e-5)
        #expect(aligned.transformed(by: turn).axis == SIMD3(0, 0, -1))
        let sphere = ParticleGravity(
            position: .zero, axis: .zero, decay: 0.5, strength: 2, force: .spherical
        )
        let pull = sphere.acceleration(at: SIMD3(2, 0, 0))
        #expect(abs(pull.x + 2 * exp(-1)) < 1e-5)
    }

    @Test func dragSlowsOnlyInsideItsRange() {
        let drag = ParticleDrag(
            position: .zero, axis: SIMD3(0, 0, 1), percentage: 0.1, range: 5, rangeFalloff: 0
        )
        #expect(abs(drag.retained(at: SIMD3(100, 0, 2), deltaTime: 1 / 30) - 0.9) < 1e-5)
        #expect(drag.retained(at: SIMD3(0, 0, 8), deltaTime: 1 / 30) == 1)
    }

    @Test func subTextureFramesLoopBackToTheLoopStart() {
        let subTexture = ParticleSubTexture(
            startFrame: 0, startFrameFudge: 0, endFrame: 3, loopStartFrame: 1,
            loopStartFrameFudge: 0, frameCount: 8, frameCountFudge: 0
        )
        let frames = [0, 0.25, 0.5, 0.75].map {
            subTexture.frame(at: $0, start: 0, loopStart: 1, frames: 8, frameTotal: 4)
        }
        #expect(frames == [0, 2, 1, 3])
    }

    private func kind(_ typeName: String, _ data: Data) throws -> ParticleModifier.Kind {
        var headerReader = BinaryReader(NIFFixture.header(bsVersion: 100))
        let header = try NIFHeader(reader: &headerReader)
        let decode = try #require(NIFBlockDecoders.decoder(for: typeName))
        var reader = BinaryReader(data)
        _ = try decode(&reader, header)
        #expect(reader.bytesRemaining == 0)
        return try NIFParticleModifierDecoder.modifier(
            typeName: typeName,
            data: data,
            header: header
        )
        .kind
    }
}
