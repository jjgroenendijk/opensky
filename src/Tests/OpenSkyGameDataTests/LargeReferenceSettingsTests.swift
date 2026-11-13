// The large reference size rule: half the bounds' diagonal times the scale, against
// `fLargeRefMinSize`. Synthetic bounds and settings only.

import Foundation
import OpenSkyEngineTesting
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct LargeReferenceSettingsTests {
    /// A cube 1,200 units wide: half its diagonal is about 1,039.
    static func cube() throws -> ObjectBounds {
        var data = Data()
        for value: Int16 in [-600, -600, -600, 600, 600, 600] {
            data.appendUInt16(UInt16(bitPattern: value))
        }
        return try ObjectBounds(field: ESMField(type: "OBND", data: data))
    }

    @Test func theSizeIsHalfTheDiagonalTimesTheScale() throws {
        let size = try LargeReferenceSettings.size(of: Self.cube(), scale: 2)
        #expect(abs(size - 1200 * Float(3).squareRoot()) < 0.5)
    }

    @Test func aReferenceIsLargeOnlyAboveTheMinimum() throws {
        let cube = try Self.cube()
        #expect(LargeReferenceSettings.vanilla.isLarge(cube, scale: 1))
        #expect(!LargeReferenceSettings.vanilla.isLarge(cube, scale: 0.9))
    }

    @Test func aPluginSetsTheMinimum() throws {
        let store = try GameSettingFixture.store(["fLargeRefMinSize": .float(2000)])
        let settings = LargeReferenceSettings.resolve(store: store)
        #expect(settings.minimumSize == 2000)
        #expect(try !settings.isLarge(Self.cube(), scale: 1))
    }
}
