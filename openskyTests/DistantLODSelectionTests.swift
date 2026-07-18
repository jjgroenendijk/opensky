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

    @Test func selectsAnchoredCoarseningRingsOutsideLoadedGrid() throws {
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
            let maxX = block.origin.x + block.level
            let maxY = block.origin.y + block.level
            #expect(!grid.desiredCells.contains {
                $0.x >= block.origin.x && $0.x < maxX
                    && $0.y >= block.origin.y && $0.y < maxY
            })
        }
    }
}
