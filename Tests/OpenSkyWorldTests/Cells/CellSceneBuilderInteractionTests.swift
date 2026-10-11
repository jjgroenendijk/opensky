// Scene-owned interaction metadata built from synthetic REFR/model-base
// records. No game data is embedded in these fixtures.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldInterface
import simd
import Testing

extension CellSceneBuilderTests {
    @Test(.enabled(if: Self.hasDevice))
    func resolvesInteractionNamesActionsAndOverride() throws {
        let cases: [(String, InteractionAction)] = [
            ("ACTI", .activate),
            ("CONT", .search),
            ("TREE", .harvest),
            ("FURN", .use),
            ("DOOR", .open),
            ("FLOR", .harvest),
            ("TACT", .talk)
        ]
        let voiceTypeField = ESMFixture.field("VNAM", Data([0xD5, 0x3A, 0x01, 0x00]))
        var refs = Data()
        var records: [String: Data] = [:]
        for (index, entry) in cases.enumerated() {
            let base = UInt32(0x300 + index)
            refs += refrRecord(formID: base + 0x100, base: base)
            records[entry.0, default: Data()] += modelBaseRecord(
                type: entry.0,
                formID: base,
                modelPath: nil,
                displayName: "\(entry.0) Name",
                activateTextOverride: entry.0 == "ACTI" ? "Mine" : nil,
                extraFields: entry.0 == "TACT" ? voiceTypeField : Data()
            )
        }
        let scene = try build(pluginData: plugin(
            temporaryRefs: refs,
            modelBaseRecords: records
        ))

        #expect(scene.interactions.count == cases.count)
        for (index, entry) in cases.enumerated() {
            let interaction = scene.interactions[FormID(UInt32(0x400 + index))]
            #expect(interaction?.name == "\(entry.0) Name")
            #expect(interaction?.action == entry.1)
        }
        #expect(scene.interactions[FormID(0x400)]?.actionLabel == "Mine")
        #expect(scene.interactions[FormID(0x404)]?.actionLabel == "Open")
        #expect(scene.interactions[FormID(0x405)]?.actionLabel == "Harvest")
        #expect(scene.interactions[FormID(0x406)]?.voiceType == FormID(0x0001_3AD5))
        #expect(scene.interactions[FormID(0x404)]?.voiceType == nil)
    }

    /// Each mesh marker is a seat in world space, with the record's keyword for its index.
    @Test(.enabled(if: Self.hasDevice))
    func furnitureSeatsTakeMarkersAndKeywords() throws {
        try writeLooseFile("meshes/furniture/block.nif", Self.furnitureNIF)
        let keyword = ESMFixture.field("ENAM", ESMFixture.u32(1))
            + ESMFixture.field("FNMK", ESMFixture.u32(0x900))
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(
                formID: 0x400, base: 0x300, position: [100, 0, 0], rotation: [0, 0, .pi / 2]
            ),
            modelBaseRecords: ["FURN": modelBaseRecord(
                type: "FURN", formID: 0x300, modelPath: "furniture\\block.nif",
                displayName: "Block", extraFields: keyword
            )]
        ))
        let seats = try #require(scene.interactions[FormID(0x400)]?.seats)
        #expect(seats.count == 2)
        #expect(seats[0].keyword == nil)
        #expect(seats[1].keyword == FormID(0x900))
        // A z turn of a quarter maps model +x onto world -y, as the cell build places meshes.
        #expect(simd_distance(seats[1].position, [100, -10, 0]) < 0.01)
        #expect(abs(seats[1].heading - (.pi / 2 + 1)) < 0.0001)
        #expect(seats[1].entryPoints == 2)
    }

    /// The actor uses the allowed side that faces it most; up only when no side is allowed.
    @Test func aSeatEntryIsTheAllowedSideFacingTheActor() {
        let seat = FurnitureSeat(
            position: .zero, heading: 0, animationType: 1, keyword: nil, entryPoints: 0b0110
        )
        #expect(seat.entry(from: [5, 0, 0]) == 4)
        #expect(seat.entry(from: [0, -5, 0]) == 2)
        #expect(seat.entry(from: [0, 5, 0]) == 4)
        let lift = FurnitureSeat(
            position: .zero, heading: 0, animationType: 1, keyword: nil, entryPoints: 16
        )
        #expect(lift.entry(from: [5, 0, 0]) == 16)
    }

    private static var furnitureNIF: Data {
        var block = Data()
        block.appendUInt32(0)
        block.appendUInt32(2)
        for (x, heading) in [(Float(0), Float(0)), (10, 1)] {
            block.appendFloat32(x)
            block.appendFloat32(0)
            block.appendFloat32(0)
            block.appendFloat32(heading)
            block.appendUInt16(1)
            block.appendUInt16(2)
        }
        return NIFFixture.file(
            blocks: [.init("BSFurnitureMarkerNode", block)], strings: ["FRN"]
        )
    }
}
