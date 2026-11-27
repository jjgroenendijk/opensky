import Foundation
@testable import OpenSkyCells
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
import Testing

struct LandDataFlagsTests {
    @Test func clearBitsDropTheirFieldGroups() throws {
        let land = try decodedLand(flags: 0x2)
        #expect(land.heightField != nil)
        #expect(!land.baseTextures.isEmpty)

        let read = land.applyingDataFlags
        #expect(read.heightField == nil)
        #expect(read.normals == nil)
        #expect(read.colors?.count == Land.vertexCount)
        #expect(read.baseTextures.isEmpty)
    }

    @Test func setBitsKeepEveryGroup() throws {
        let read = try decodedLand(flags: 0x7).applyingDataFlags
        #expect(read.heightField != nil)
        #expect(read.colors != nil)
        #expect(read.baseTextures.count == 1)
    }

    private func decodedLand(flags: UInt32) throws -> Land {
        var data = Data()
        data.appendUInt32(flags)
        var vhgt = Data()
        vhgt.appendFloat32(0)
        vhgt.append(contentsOf: [UInt8](repeating: 0, count: Land.vertexCount + 3))
        var btxt = Data()
        btxt.appendUInt32(0x300)
        btxt.append(contentsOf: [0, 0, 0, 0])
        let fields = ESMFixture.field("DATA", data)
            + ESMFixture.field("VHGT", vhgt)
            + ESMFixture.field("VCLR", Data(repeating: 255, count: Land.vertexCount * 3))
            + ESMFixture.field("BTXT", btxt)
        return try Land(record: ESMFixture.parseRecord(ESMFixture.record("LAND", data: fields)))
    }
}
