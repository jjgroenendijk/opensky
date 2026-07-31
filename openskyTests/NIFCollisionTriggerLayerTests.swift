// SkyrimLayer 12 (trigger) recognition over synthetic in-code NIF payloads
// only. Layouts: NifTools nif.xml; docs/formats/nif-collision.md.

@testable import opensky
import simd
import Testing

struct NIFCollisionTriggerLayerTests {
    @Test(arguments: [
        (UInt8(12), true),
        (UInt8(15), false),
        (UInt8(1), false)
    ])
    func onlySkyrimLayerTwelveMarksATriggerVolume(layer: UInt8, expected: Bool) throws {
        let body = try decodedBody(worldLayer: layer, rigidLayer: layer)
        #expect(body.isTriggerVolume == expected)
        #expect(body.worldFilter.isTriggerVolume == expected)
        #expect(body.rigidBodyFilter.isTriggerVolume == expected)
        // A trigger body is never also player-solid, so trigger routing and
        // solid collision stay disjoint. Layer 15 fails both tests, which is
        // why "not player-solid" cannot stand in for "is a trigger".
        #expect(!(body.isTriggerVolume && body.isPlayerSolid))
    }

    @Test func eitherDuplicateFilterNamingLayerTwelveMarksATrigger() throws {
        let worldOnly = try decodedBody(worldLayer: 12, rigidLayer: 1)
        let rigidOnly = try decodedBody(worldLayer: 1, rigidLayer: 12)
        let neither = try decodedBody(worldLayer: 1, rigidLayer: 1)
        #expect(worldOnly.isTriggerVolume)
        #expect(rigidOnly.isTriggerVolume)
        #expect(!neither.isTriggerVolume)
        #expect(neither.isPlayerSolid)
    }

    private func decodedBody(worldLayer: UInt8, rigidLayer: UInt8) throws -> NIFCollisionBody {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(
                shape: 3,
                worldLayer: worldLayer,
                rigidLayer: rigidLayer
            )),
            .init("bhkBoxShape", NIFCollisionFixture.box(SIMD3(repeating: 1)))
        ]))
        return try #require(file.collisionModel().bodies.first)
    }
}
