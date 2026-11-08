// Every field the particle block readers keep, read by name over synthetic blocks
// (docs/formats/nif-particles.md).

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFParticleFieldTests {
    /// A reader over `data` stored as one block, and the header that names its strings.
    private func reader(_ type: String, _ data: Data) throws -> (BinaryReader, NIFHeader) {
        let file = try NIFFile(data: NIFFixture.file(blocks: [.init(type, data)]))
        return (BinaryReader(file.blocks[0].data), file.header)
    }

    @Test func colliderKeepsItsSpawnAndManager() throws {
        var (data, _) = try reader("NiPSysSphericalCollider", NIFBlockFixture.collider(
            bounce: 0, dies: true, refs: SIMD3(4, -1, 6), shape: [3]
        ))
        let collider = try NIFParticleCollider(reader: &data, planar: false)
        #expect(!collider.spawnsOnCollide)
        #expect(collider.spawnModifierRef == -1)
        #expect(collider.managerRef == 4)
    }

    @Test func havokUpdateKeepsMeshesAndModifier() throws {
        var (data, header) = try reader("BSPSysHavokUpdateModifier", NIFBlockFixture.havokUpdate(
            meshes: [2, 3], modifier: 5
        ))
        let update = try NIFMeshUpdateModifier(reader: &data, header: header, havok: true)
        #expect(update.header.active)
        #expect(update.meshRefs == [2, 3])
        #expect(update.modifierRef == 5)
    }

    @Test func modifierHeaderKeepsItsTarget() throws {
        var body = NIFParticleFixture.modifierBase(order: 3, targetRef: 7)
        body.append(NIFParticleParameterFixture.inheritVelocity(chance: 0.5, multiplier: 2)
            .dropFirst(13))
        var (data, header) = try reader("BSPSysInheritVelocityModifier", body)
        let inherit = try NIFInheritVelocityModifier(reader: &data, header: header)
        #expect(inherit.header.targetRef == 7)
        #expect(inherit.header.order == 3)
        #expect(inherit.inheritObjectRef == -1)
        #expect(inherit.inherit.multiplier == 2)
    }

    @Test func rotationKeepsItsAxis() throws {
        var (data, header) = try reader(
            "NiPSysRotationModifier",
            NIFParticleParameterFixture.rotation(
                speed: 1, angle: 0, randomSign: false
            )
        )
        _ = try NIFParticleModifierHeader(reader: &data, header: header)
        let rotation = try NIFRotationModifier.body(&data)
        #expect(rotation.randomAxis)
        #expect(rotation.axis == SIMD3(1, 0, 0))
    }

    @Test func meshParticleDataKeepsItsGenerations() throws {
        var data = NIFParticleFixture.psysData(maxParticles: 2)
        data.append(NIFBlockFixture.uint32(8))
        data.append(0)
        data.append(NIFBlockFixture.uint32(2))
        data.append(NIFBlockFixture.uint32(0))
        data.append(NIFBlockFixture.uint32(1))
        data.appendRef(4)
        var (block, header) = try reader("NiMeshPSysData", data)
        let pool = try NIFMeshParticleData(reader: &block, header: header)
        #expect(pool.generations == [0, 1])
    }

    @Test func ballSocketChainKeepsItsSolverSettings() throws {
        var (data, _) = try reader("bhkBallSocketConstraintChain", NIFBlockFixture.ballSocketChain(
            pivots: [SIMD3(0, 0, 1), SIMD3(0, 0, -1)], entities: [1, 2]
        ))
        let chain = try NIFBallSocketChain(reader: &data)
        #expect(chain.tau == 0.8)
        #expect(chain.damping == 0.5)
        #expect(chain.constraintForceMixing == 0)
        #expect(chain.maxErrorDistance == 0.1)
    }
}
