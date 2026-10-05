// The detail fields of ModelBase records and of REFR and ACHR over synthetic
// fields. See docs/formats/world-records.md and placed-references.md.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct PlacedDetailTests {
    private typealias Fixture = ESMFixture

    @Test func decodesFurnitureMarkersAndModelGroup() throws {
        let furniture = try ModelBase(record: Fixture.record("FURN", fields: [
            ("OBND", Data(count: 12)), ("MODL", Fixture.zstring("chair.nif")),
            ("MODT", Data(count: 12)), ("PNAM", Fixture.u8(1, 2, 3, 0)), ("FNAM", Fixture.u16(4)),
            ("MNAM", Fixture.u32(0)), ("ENAM", Fixture.u32(0)), ("NAM0", Fixture.u16(0, 0x02)),
            ("ENAM", Fixture.u32(1)), ("FNMK", Fixture.u32(0x10)),
            ("FNPR", Fixture.u16(1, 0x01)), ("XMRK", Fixture.zstring("marker.nif"))
        ]))
        let details = furniture.details
        #expect(furniture.modelPath == "chair.nif")
        #expect(details.model?.textureHashes?.count == 12)
        #expect(details.markerColor == SIMD4(1, 2, 3, 0))
        #expect(details.furnitureMarkers.map(\.index) == [0, 1])
        #expect(details.furnitureMarkers[0].disabledEntryPoints == 0x02)
        #expect(details.furnitureMarkers[1].keyword == FormID(0x10))
        #expect(details.markerEntryPoints.first?.type == 1)
        #expect(details.markerModelPath == "marker.nif")
        #expect(furniture.skipped.isEmpty, "\(furniture.skipped.ranked)")
    }

    @Test func decodesTreeWindAndMovableStaticFlags() throws {
        let tree = try ModelBase(record: Fixture.record("TREE", fields: [
            ("CNAM", Fixture.f32(Array(repeating: 0.5, count: 12) as [Float]))
        ]))
        #expect(tree.details.treeData?.leafFrequency == 0.5)
        let movable = try ModelBase(record: Fixture.record("MSTT", fields: [
            ("DATA", Fixture.u8(1)), ("SNAM", Fixture.u32(0x20))
        ]))
        #expect(movable.details.movableStaticFlags == 1)
        #expect(movable.sounds?.loop == FormID(0x20))
        #expect(movable.skipped.isEmpty)
    }

    @Test func separatesPatrolIdleFromRoomImageSpace() throws {
        let fields: [(String, Data)] = [
            ("XRMR", Fixture.u8(1, 0, 0, 0)), ("INAM", Fixture.u32(0x30)),
            ("XLRM", Fixture.u32(0x31)), ("XPRD", Fixture.f32(5)), ("XPPA", Data()),
            ("INAM", Fixture.u32(0x40)), ("SCHR", Data(count: 20)),
            ("PDTO", Fixture.u32(1) + Data("HELO".utf8)),
            ("XLIG", Fixture.f32(1, 2, 3, 4) + Fixture.u32(9)),
            ("XRGD", Fixture.u8(7, 0, 0, 0) + Fixture.f32(1, 2, 3, 0, 0, 0)),
            ("XAPR", Fixture.u32(0x50) + Fixture.f32(0.5)),
            ("XEZN", Fixture.u32(0x60)), ("ZZZZ", Data())
        ]
        let reference = try PlacedReferenceFixture.reference(
            fields.reduce(Data()) { $0 + Fixture.field($1.0, $1.1) }
        )
        let details = reference.details
        #expect(details.room?.imageSpace == FormID(0x30))
        #expect(details.room?.linkedRooms == [FormID(0x31)])
        #expect(details.patrols.first?.idle == FormID(0x40))
        #expect(details.patrols.first?.hasScriptMarker == true)
        #expect(details.patrols.first?.topics.first?.subtype == "HELO")
        #expect(details.lightData?.unknown == 9)
        #expect(details.ragdollBones.first?.position == SIMD3(1, 2, 3))
        #expect(details.activateParents.first?.delay == 0.5)
        #expect(details.links["XEZN"] == FormID(0x60))
        #expect(reference.skipped.counts[.unknownField("ZZZZ")] == 1)
        #expect(reference.skipped.total == 1)
    }

    @Test func actorReadsLinkedReferencesAndOwnershipIntoDetails() throws {
        let actor = try PlacedActor(record: Fixture.record("ACHR", fields: [
            ("NAME", Fixture.u32(0x10)), ("DATA", Data(count: 24)),
            ("XLKR", Fixture.u32(0x20, 0x21)), ("XOWN", Fixture.u32(0x22)),
            ("XLCM", Fixture.i32(2)), ("XHOR", Fixture.u32(0x23))
        ]))
        #expect(actor.details.linkedReferences.first?.ref == FormID(0x21))
        #expect(actor.details.links["XOWN"] == FormID(0x22))
        #expect(actor.details.levelModifier == 2)
        #expect(actor.details.links["XHOR"] == FormID(0x23))
        #expect(actor.skipped.isEmpty)
    }
}
