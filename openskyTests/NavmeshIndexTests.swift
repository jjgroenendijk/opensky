// NAVI decode and the NavmeshIndex store over synthetic in-code plugins:
// NVMI entries keyed by navmesh and grouped by location, NVSI deletions, the
// island block skipped without derailing the entry behind it, and the
// skip-and-log policy for deleted or malformed records.

import Foundation
@testable import opensky
import simd
import Testing

struct NavmeshIndexTests {
    @Test func decodesInfoEntriesAndVersion() throws {
        let record = try NavmeshFixture.record(NavmeshFixture.naviRecord(
            infos: NavmeshFixture.info(
                navmesh: 0x100,
                location: SIMD3(10, 20, 30),
                edgeLinks: [0x200, 0x300],
                preferredEdgeLinks: [0x200],
                doors: [0x400],
                world: 0x3C,
                grid: (x: 6, y: -2)
            ) + NavmeshFixture.info(navmesh: 0x200, cell: 0x50)
        ))
        let map = try NavmeshInfoMap(record: record)

        #expect(map.version == 0x0C)
        #expect(map.editorID == "TestNavi")
        #expect(map.infos.count == 2)
        #expect(map.malformedInfoCount == 0)
        let first = map.infos[0]
        #expect(first.navmesh == FormID(0x100))
        #expect(first.approximateLocation == SIMD3(10, 20, 30))
        #expect(first.edgeLinks == [FormID(0x200), FormID(0x300)])
        #expect(first.preferredEdgeLinks == [FormID(0x200)])
        #expect(first.doors == [FormID(0x400)])
        #expect(first.location == .exterior(world: FormID(0x3C), x: 6, y: -2))
        #expect(map.infos[1].location == .interior(cell: FormID(0x50)))
    }

    /// The island summary block sits between the door links and the pathing
    /// cell, so getting the location right proves it was consumed exactly.
    @Test func skipsIslandDataAndStillReadsTheLocation() throws {
        let record = try NavmeshFixture.record(NavmeshFixture.naviRecord(
            infos: NavmeshFixture.info(
                navmesh: 0x100, flags: 0x20, island: true, cell: 0x77
            )
        ))
        let map = try NavmeshInfoMap(record: record)

        let info = try #require(map.infos.first)
        #expect(info.hasIslandData)
        #expect(info.flags.contains(.isIsland))
        #expect(info.location == .interior(cell: FormID(0x77)))
    }

    @Test func decodesDeletedNavmeshList() throws {
        let record = try NavmeshFixture.record(NavmeshFixture.naviRecord(
            infos: NavmeshFixture.info(navmesh: 0x100),
            deleted: [0x900, 0x901]
        ))
        let map = try NavmeshInfoMap(record: record)

        #expect(map.deletedNavmeshes == [FormID(0x900), FormID(0x901)])
    }

    /// One unusable NVMI must not cost the plugin its other navmeshes.
    @Test func countsMalformedInfoEntriesAndKeepsTheRest() throws {
        let truncated = ESMFixture.field("NVMI", Data([1, 2, 3, 4]))
        let record = try NavmeshFixture.record(NavmeshFixture.naviRecord(
            infos: NavmeshFixture.info(navmesh: 0x100) + truncated
        ))
        let map = try NavmeshInfoMap(record: record)

        #expect(map.infos.count == 1)
        #expect(map.malformedInfoCount == 1)
    }

    @Test func throwsOnWrongRecordType() throws {
        let record = try NavmeshFixture.record(ESMFixture.record(
            "NAVM", formID: 0x10, data: Data()
        ))

        #expect(throws: ESMError.self) { try NavmeshInfoMap(record: record) }
    }

    // MARK: - Store

    @Test func indexesByFormIDAndLocation() throws {
        let file = try ESMFile(data: NavmeshFixture.plugin(
            naviRecords: NavmeshFixture.naviRecord(
                infos: NavmeshFixture.info(
                    navmesh: 0x100, edgeLinks: [0x200], world: 0x3C, grid: (x: 6, y: -2)
                ) + NavmeshFixture.info(
                    navmesh: 0x101, world: 0x3C, grid: (x: 6, y: -2)
                ) + NavmeshFixture.info(navmesh: 0x200, cell: 0x50),
                deleted: [0x900]
            )
        ))
        let index = NavmeshIndex(file: file)

        #expect(index.count == 3)
        #expect(!index.isEmpty)
        #expect(try #require(index.info(FormID(0x100))).navmesh == FormID(0x100))
        #expect(index.edgeLinks(from: FormID(0x100)) == [FormID(0x200)])
        // An exterior square can hold more than one navmesh; record order wins.
        #expect(index.navmeshes(at: .exterior(world: FormID(0x3C), x: 6, y: -2))
            == [FormID(0x100), FormID(0x101)])
        #expect(index.navmeshes(at: .interior(cell: FormID(0x50))) == [FormID(0x200)])
        #expect(index.navmeshes(at: .interior(cell: FormID(0x51))).isEmpty)
        #expect(index.deletedNavmeshes == [0x900])
        // An unknown navmesh links nowhere rather than trapping.
        #expect(index.edgeLinks(from: FormID(0xDEAD)).isEmpty)
    }

    @Test func skipsDeletedNaviRecord() throws {
        let file = try ESMFile(data: NavmeshFixture.plugin(
            naviRecords: NavmeshFixture.naviRecord(
                recordFlags: ESMRecord.Flags.deleted.rawValue,
                infos: NavmeshFixture.info(navmesh: 0x100)
            )
        ))
        let index = NavmeshIndex(file: file)

        #expect(index.isEmpty)
        #expect(index.locations.isEmpty)
    }

    @Test func emptyWithoutANaviGroup() throws {
        let index = try NavmeshIndex(file: ESMFile(data: ESMFixture.tes4()))

        #expect(index.isEmpty)
        #expect(NavmeshIndex.empty.isEmpty)
    }

    // MARK: - Cell-children walk

    @Test func collectsNavmeshesFromCellChildren() throws {
        let group = try NavmeshFixture.cellChildren(temporary:
            NavmeshFixture.navmRecord(formID: 0x100, geometry: NavmeshFixture.twoTriangleMesh())
                + NavmeshFixture.navmRecord(
                    formID: 0x101, geometry: NavmeshFixture.twoTriangleMesh()
                ))
        let navmeshes = CellSceneBuilder.collectNavmeshes(in: group)

        #expect(navmeshes.map(\.formID) == [FormID(0x100), FormID(0x101)])
        #expect(navmeshes[0].geometry.triangles.count == 2)
    }

    /// A deleted NAVM lays down no surface, and a malformed one must not cost
    /// the cell the navmeshes beside it.
    @Test func skipsDeletedAndMalformedNavmeshRecords() throws {
        let group = try NavmeshFixture.cellChildren(temporary:
            NavmeshFixture.navmRecord(
                formID: 0x100,
                flags: ESMRecord.Flags.deleted.rawValue,
                geometry: NavmeshFixture.twoTriangleMesh()
            )
                + ESMFixture.record("NAVM", formID: 0x101, data: Data())
                + NavmeshFixture.navmRecord(
                    formID: 0x102, geometry: NavmeshFixture.twoTriangleMesh()
                ))
        let navmeshes = CellSceneBuilder.collectNavmeshes(in: group)

        #expect(navmeshes.map(\.formID) == [FormID(0x102)])
    }

    @Test func collectsNothingWithoutAChildrenGroup() {
        #expect(CellSceneBuilder.collectNavmeshes(in: nil).isEmpty)
    }
}
