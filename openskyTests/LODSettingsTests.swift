import Foundation
@testable import opensky
import Testing

struct LODSettingsTests {
    private func bytes(
        originX: Int16 = -96,
        originY: Int16 = -96,
        stride: Int32 = 256,
        minimum: Int32 = 4,
        maximum: Int32 = 32
    ) -> Data {
        var data = Data()
        data.appendUInt16(UInt16(bitPattern: originX))
        data.appendUInt16(UInt16(bitPattern: originY))
        data.appendUInt32(UInt32(bitPattern: stride))
        data.appendUInt32(UInt32(bitPattern: minimum))
        data.appendUInt32(UInt32(bitPattern: maximum))
        return data
    }

    @Test func decodesSkyrimLayoutAndLevels() throws {
        let settings = try LODSettings(data: bytes())
        #expect(settings.origin == CellCoordinate(x: -96, y: -96))
        #expect(settings.stride == 256)
        #expect(settings.levels == [4, 8, 16, 32])
    }

    @Test func anchorsNegativeCellsWithFloorDivision() throws {
        let settings = try LODSettings(data: bytes(originX: 0, originY: 0))
        #expect(
            settings.blockOrigin(containing: CellCoordinate(x: -1, y: -9), level: 8)
                == CellCoordinate(x: -8, y: -16)
        )
    }

    @Test func rejectsWrongSizeAndInvalidRanges() {
        #expect(throws: LODSettingsError.invalidSize(15)) {
            try LODSettings(data: Data(count: 15))
        }
        #expect(throws: LODSettingsError.invalidStride(0)) {
            try LODSettings(data: bytes(stride: 0))
        }
        #expect(throws: LODSettingsError.invalidLevelRange(min: 8, max: 4)) {
            try LODSettings(data: bytes(minimum: 8, maximum: 4))
        }
    }
}
