// Bomb, collider, and recycle bound modifiers, and the modifier parameter
// controllers, over synthetic particle systems (docs/formats/nif-particles.md).

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFParticleForceTests {
    @Test func placesForceModifiersAtTheirObjects() throws {
        let system = try #require(NIFFile(data: forceFile()).particleSystems().first)
        let kinds = system.modifiers.map(\.kind)
        let bomb = try #require(kinds.compactMap { kind -> ParticleBomb? in
            if case let .bomb(bomb) = kind {
                return bomb
            }
            return nil
        }.first)
        #expect(bomb.position == SIMD3(0, 0, 10))
        #expect(bomb.symmetry == .spherical)
        #expect(simd_distance(bomb.acceleration(at: SIMD3(0, 0, 12)), SIMD3(0, 0, 1)) < 1e-5)

        let bound = kinds.compactMap { kind -> ParticleRecycleBound? in
            if case let .recycleBound(bound) = kind {
                return bound
            }
            return nil
        }.first
        #expect(bound == ParticleRecycleBound(minimum: SIMD3(-1, -1, 9), size: SIMD3(2, 2, 2)))
        #expect(bound?.wrapped(SIMD3(0, 0, 12)) == SIMD3(0, 0, 10))

        let colliders = kinds.compactMap { kind -> [ParticleCollider]? in
            if case let .colliders(list) = kind {
                return list
            }
            return nil
        }.first
        #expect(colliders?.count == 2)
        #expect(colliders?.last?.diesOnCollide == true)
    }

    @Test func planarColliderBouncesAndSphereKills() {
        let plane = ParticleCollider(
            bounce: 0.5, diesOnCollide: false,
            shape: .plane(center: .zero, halfX: SIMD3(1, 0, 0), halfY: SIMD3(0, 1, 0))
        )
        let hit = plane.hit(from: SIMD3(0, 0, 1), to: SIMD3(0, 0, -1), velocity: SIMD3(0, 0, -2))
        #expect(hit == .bounces(position: .zero, velocity: SIMD3(0, 0, 1)))
        #expect(plane.hit(from: SIMD3(5, 0, 1), to: SIMD3(5, 0, -1), velocity: .zero) == .none)

        let sphere = ParticleCollider(
            bounce: 0, diesOnCollide: true, shape: .sphere(center: .zero, radius: 1)
        )
        #expect(sphere.hit(from: SIMD3(2, 0, 0), to: SIMD3(0.5, 0, 0), velocity: .zero) == .dies)
    }

    @Test func bombDecayAndSymmetry() {
        func bomb(_ decay: ParticleBomb.Decay, _ symmetry: ParticleBomb.Symmetry) -> ParticleBomb {
            ParticleBomb(
                position: .zero, axis: SIMD3(0, 0, 2), decay: 2, deltaV: 4,
                decayType: decay, symmetry: symmetry
            )
        }
        #expect(bomb(.none, .spherical).acceleration(at: SIMD3(8, 0, 0)) == SIMD3(4, 0, 0))
        #expect(bomb(.linear, .spherical).acceleration(at: SIMD3(3, 0, 0)) == .zero)
        let planar = bomb(.exponential, .planar).acceleration(at: SIMD3(5, 0, -2))
        #expect(simd_distance(planar, SIMD3(0, 0, -4 * exp(-1))) < 1e-5)
        let cylinder = bomb(.none, .cylindrical).acceleration(at: SIMD3(0, 3, 7))
        #expect(cylinder == SIMD3(0, 4, 0))
    }

    @Test func modifierParameterControllerDrivesTheEmitter() throws {
        var speed = NIFBlockFixture.interpolatedController(stop: 2, interpolator: 6)
        speed.append(NIFBlockFixture.uint32(1)) // modifier name "Emit"
        var interpolator = NIFBlockFixture.floats([-Float.greatestFiniteMagnitude])
        interpolator.appendRef(7)
        let file = NIFParticleFixture.controlledSystemFile(
            emitterType: "NiPSysEmitterSpeedCtlr",
            emitter: speed,
            updateTail: NIFBlockFixture.timeController().dropFirst(4),
            extraBlocks: [
                .init("NiFloatInterpolator", interpolator),
                .init("NiFloatData", NIFBlockFixture.keyGroup([(0, [10]), (2, [30])]))
            ],
            strings: ["Smoke", "Emit"]
        )
        let system = try #require(NIFFile(data: file).particleSystems().first)
        #expect(system.updatesSimulation)
        let controller = try #require(system.modifierControllers.first)
        #expect(controller.parameter == .emitterSpeed)
        #expect(controller.value(at: 1) == 20)
        let emitter = try #require(system.emitters.first)
        #expect(emitter.controlled(by: system.modifierControllers, at: 1).speed == 20)
    }

    @Test func meshParticleDataReadsItsPool() throws {
        var data = NIFParticleFixture.psysData(maxParticles: 4)
        data.append(NIFBlockFixture.uint32(16))
        data.append(1)
        data.append(NIFBlockFixture.uint32(1))
        data.append(NIFBlockFixture.uint32(0))
        data.appendRef(9)
        let file = try NIFFile(data: NIFFixture.file(blocks: [.init("NiMeshPSysData", data)]))
        let decoded = try #require(
            NIFBlockDecoders.decode(file.blocks[0], header: file.header) as? NIFMeshParticleData
        )
        #expect(decoded.defaultPoolSize == 16)
        #expect(decoded.fillsPoolsOnLoad)
        #expect(decoded.particleMeshesRef == 9)
    }

    /// Blocks: root 0, system 1, data 2, bomb 3, collider manager 4, recycle bound 5,
    /// object node 6 at z 10, planar collider 7, spherical collider 8.
    private func forceFile() -> Data {
        let system = NIFParticleFixture.particleSystemSSE(dataRef: 2, modifierRefs: [3, 4, 5])
        return NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 6])),
            .init("NiParticleSystem", system),
            .init("NiPSysData", NIFParticleFixture.psysData(maxParticles: 8)),
            .init("NiPSysBombModifier", NIFBlockFixture.bombModifier(
                object: 6, axis: SIMD3(0, 0, 1), push: SIMD2(4, 2), types: SIMD2(1, 0)
            )),
            .init("NiPSysColliderManager", NIFBlockFixture.colliderManager(collider: 7)),
            .init("BSPSysRecycleBoundModifier", NIFBlockFixture.recycleBound(
                offset: SIMD3(-1, -1, -1), extent: SIMD3(2, 2, 2), object: 6
            )),
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(
                translation: SIMD3(0, 0, 10)
            ))),
            .init("NiPSysPlanarCollider", NIFBlockFixture.collider(
                bounce: 0.5, dies: false, refs: SIMD3(4, 8, -1),
                shape: [2, 2, 1, 0, 0, 0, 1, 0]
            )),
            .init("NiPSysSphericalCollider", NIFBlockFixture.collider(
                bounce: 0, dies: true, refs: SIMD3(4, -1, 6), shape: [3]
            ))
        ])
    }
}
