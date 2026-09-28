import Foundation
@testable import opensky
import Testing

struct DistantLODSelectionTests {
    private func settings() throws -> LODSettings {
        var data = Data()
        data.appendUInt16(UInt16(bitPattern: Int16(-96)))
        data.appendUInt16(UInt16(bitPattern: Int16(-96)))
        data.appendUInt32(256)
        data.appendUInt32(4)
        data.appendUInt32(32)
        return try LODSettings(data: data)
    }

    @Test func partitionsEveryCellAcrossAnchoredCoarseningRings() throws {
        let center = CellCoordinate(x: 6, y: -2)
        let grid = CellGridManager(initialPosition: CellGridManager.cellCenter(of: center))
        let settings = try settings()
        let blocks = DistantLODSelection.blocks(
            worldspace: "Tamriel",
            settings: settings,
            center: center,
            hiddenCells: grid.desiredCells
        )

        #expect(!blocks.isEmpty)
        #expect(Set(blocks.map(\.level)) == [4, 8, 16, 32])
        #expect(blocks.filter { $0.kind == .objects }.allSatisfy { $0.level <= 16 })
        #expect(blocks.filter { $0.level == 32 }.allSatisfy { $0.kind == .terrain })
        for block in blocks {
            #expect((block.origin.x - settings.origin.x) % block.level == 0)
            #expect((block.origin.y - settings.origin.y) % block.level == 0)
            #expect(block.path == block.path.lowercased())
            if block.kind == .objects {
                #expect(block.clipMask == nil)
            }
        }

        let terrain = blocks.filter { $0.kind == .terrain }
        #expect(Set(terrain.compactMap(\.clipMask).map(\.level)) == [4, 8, 16, 32])
        let outer = try #require(
            DistantLODSelection.bands(settings: settings, configuration: .fallback).last
        ).outerRadius
        for x in center.x - outer ... center.x + outer {
            for y in center.y - outer ... center.y + outer {
                let cell = CellCoordinate(x: x, y: y)
                let owners = terrain.count { $0.coversTerrain(cell) }
                #expect(owners == (grid.desiredCells.contains(cell) ? 0 : 1))
            }
        }
    }

    @Test func mapsWorldDistancesToContiguousPowerOfTwoBands() throws {
        let configuration = TerrainLODConfiguration(
            level0Distance: 12288,
            level1Distance: 32768,
            maximumDistance: 131_072,
            treeLoadDistance: 65536
        )
        let bands = try DistantLODSelection.bands(
            settings: settings(),
            configuration: configuration
        )

        #expect(bands == [
            DistantLODBand(level: 4, innerRadius: 2, outerRadius: 3),
            DistantLODBand(level: 8, innerRadius: 3, outerRadius: 8),
            DistantLODBand(level: 16, innerRadius: 8, outerRadius: 16),
            DistantLODBand(level: 32, innerRadius: 16, outerRadius: 32)
        ])
    }
}
