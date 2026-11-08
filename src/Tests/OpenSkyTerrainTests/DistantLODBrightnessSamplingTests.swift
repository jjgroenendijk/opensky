// Where the terrain LOD brightness fit takes its cells from, and which cell each
// texel of a level-4 block's 4 x 4 mip belongs to.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyImageKernels
@testable import OpenSkyTerrain
import Testing

struct DistantLODBrightnessSamplingTests {
    @Test func originsSpreadOverTheWholeArea() throws {
        var data = Data()
        data.appendUInt16(UInt16(bitPattern: Int16(-64)))
        data.appendUInt16(UInt16(bitPattern: Int16(-64)))
        data.appendUInt32(128)
        data.appendUInt32(4)
        data.appendUInt32(32)
        let settings = try LODSettings(data: data)
        let origins = DistantLODSelection.brightnessSampleOrigins(settings: settings, maximum: 64)
        #expect(origins.count == 64)
        #expect(origins.allSatisfy { ($0.x + 64) % 4 == 0 && ($0.y + 64) % 4 == 0 })
        #expect(origins
            .allSatisfy { $0.x >= -64 && $0.x + 4 <= 64 && $0.y >= -64 && $0.y + 4 <= 64 })
        #expect(Set(origins.map(\.x)).count == 8)
        #expect((origins.map(\.x).max() ?? 0) > 40)
    }

    @Test func firstTexelRowIsTheNorthRow() {
        var rgba = [UInt8](repeating: 0, count: 64)
        rgba[0] = 255 // row 0, column 0
        rgba[(3 * 4 + 1) * 4] = 51 // row 3, column 1
        let image = DecodedImage(width: 4, height: 4, rgba: rgba)
        let colours = DistantLODBuilder.cellColours(image, blockOrigin: CellCoordinate(x: 8, y: -4))
        #expect(colours.count == 16)
        #expect(colours[CellCoordinate(x: 8, y: -1)]?.x == 1)
        #expect(colours[CellCoordinate(x: 9, y: -4)]?.x == 0.2)
    }
}
