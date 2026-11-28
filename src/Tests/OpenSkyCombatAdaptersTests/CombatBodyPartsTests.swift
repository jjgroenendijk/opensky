// The struck part of a hit: the race's BPTD part whose posed node lies nearest the
// hit point. Rules: docs/formats/body-parts.md#in-the-game.

import Foundation
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkySessionTesting
import simd
import Testing

@MainActor
struct CombatBodyPartsTests {
    private let host = CombatHost()
    private let records = FakeCombatRecords()

    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let raceID: UInt32 = 0x200
    private static let partsID: UInt32 = 0x300

    /// `BPND` with the damage multiplier, then the flags, part type, health percent,
    /// actor value, and to-hit chance bytes, padded to 84.
    private static func nodeData(multiplier: Float, bytes: [UInt8]) -> Data {
        var data = Data()
        data.appendFloat32(multiplier)
        data.append(contentsOf: bytes + [40])
        return data + Data(count: 84 - data.count)
    }

    init() throws {
        var raceData = Data(count: 0x20)
        raceData.appendUInt32(0)
        raceData.append(Data(count: 128 - raceData.count))
        var link = Data()
        link.appendUInt32(Self.partsID)
        let file = try ESMFixture.plugin(records: [
            ESMFixture.record(
                "RACE",
                formID: Self.raceID,
                data: ESMFixture.field("DATA", raceData)
                    + ESMFixture.field("GNAM", link)
            ),
            ESMFixture.record(
                "BPTD",
                formID: Self.partsID,
                data:
                ESMFixture.field("BPNN", ESMFixture.zstring("NPC Spine"))
                    + ESMFixture.field("BPND", Self.nodeData(
                        multiplier: 1, bytes: [0, 0, 5, 0xFF, 100]
                    ))
                    + ESMFixture.field("BPNN", ESMFixture.zstring("NPC Head"))
                    + ESMFixture.field("BPND", Self.nodeData(
                        multiplier: 2, bytes: [0x48, 1, 10, 25, 100]
                    ))
                    + ESMFixture.field("BPNN", ESMFixture.zstring("NPC Tail"))
                    + ESMFixture.field("BPND", Self.nodeData(
                        multiplier: 1, bytes: [0, 5, 5, 0xFF, 0]
                    ))
            )
        ])
        let race = try Race(
            record: ESMFixture.firstRecord(type: "RACE", in: file),
            localized: false
        )
        host.combatRecords = records
        records.actorValueBaselines = FakeCombatRecords.baselines(
            race: race,
            pluginName: "base.esm"
        )
        records.presentationRecords = PresentationRecordStore(plugins: [("base.esm", file)])
        host.fakeEffects.recordsValue = EffectRecordStore(plugins: [])
        host.fakeMenuWorld.raceOfResult = FormID(Self.raceID)
        host.fakeEffectsWorld.effectBonesResult = [
            "npc spine": Self.bone(at: SIMD3(0, 0, 60)),
            "NPC Head": Self.bone(at: SIMD3(0, 0, 120)),
            "NPC Tail": Self.bone(at: SIMD3(0, -40, 40))
        ]
    }

    private static func bone(at position: SIMD3<Float>) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(position, 1)
        return matrix
    }

    @Test func theNearestNodeGivesThePartAndItsValues() throws {
        let combat = CombatWorldAdapter(game: host)
        let head = try #require(combat.struckBodyPart(
            of: Self.actor, at: SIMD3(0, 0, 110), from: nil
        ))
        #expect(head.partType == 1)
        #expect(head.node == "NPC Head")
        #expect(head.damageMultiplier == 2)
        #expect(head.healthPercent == 10)
        #expect(head.actorValue == 25)
        #expect(head.explodable == ExplodablePart(
            node: "NPC Head", chance: 40, isChanceAbsolute: true
        ))
        let torso = combat.struckBodyPart(of: Self.actor, at: SIMD3(0, 0, 70), from: nil)
        #expect(torso?.partType == 0)
        #expect(torso?.actorValue == nil)
        #expect(torso?.explodable == nil)
        #expect(combat.struckBodyPart(of: Self.actor, at: SIMD3(0, -40, 40), from: nil) == nil)
    }

    @Test func withoutActorValuesALimbTakesNothingAndNoDecalNeedsAStore() throws {
        let combat = CombatWorldAdapter(game: host)
        #expect(combat.baseActorValue(at: 24, of: Self.actor) == nil)
        combat.damageActorValue(at: 25, by: 10, of: Self.actor)
        let file = try ESMFixture.plugin(records: [
            ESMFixture.record("IPCT", formID: 0x300, data: Data())
        ])
        let impact = try Impact(record: ESMFixture.firstRecord(type: "IPCT", in: file))
        combat.run([.placeBloodDecal(impact, at: .zero, normal: SIMD3(0, 0, 1))])
        #expect(host.fakeEffects.placeImpactDecalCalls.isEmpty)
    }

    @Test func theGroundHitFollowsTheLandUnderTheRay() throws {
        let combat = CombatWorldAdapter(game: host)
        host.fakeStreamer.collision.sampleTerrainResult = TerrainGroundSample(
            height: 0,
            normal: SIMD3(0, 0, 1)
        )
        let hit = try #require(combat.groundHit(
            from: SIMD3(0, 0, 40), along: SIMD3(0, 0, -1), within: 512
        ))
        #expect(abs(hit.position.z) < 0.1)
        #expect(abs(hit.distance - 40) < 0.1)
    }

    @Test func withNoPointTheAttackersTorsoAims() {
        let combat = CombatWorldAdapter(game: host)
        // The attacker shares the race, so its torso stands at the spine node.
        #expect(combat.struckBodyPart(of: Self.actor, at: nil, from: Self.actor)?.partType == 0)
        host.fakeMenuWorld.raceOfResult = nil
        #expect(combat.struckBodyPart(of: Self.actor, at: nil, from: .player) == nil)
    }
}
