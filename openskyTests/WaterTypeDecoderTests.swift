// WATR decoder coverage over synthetic DNAM bytes only. Layout sources:
// UESP WATR + xEdit dev-4.1.6; see docs/formats/water.md.

import Foundation
@testable import opensky
import Testing

struct WaterTypeDecoderTests {
    @Test func decodesWaterColorsFromBothSSEVariants() throws {
        for size in [228, 232] {
            var dnam = Data(count: 40)
            dnam.append(contentsOf: [10, 20, 30, 0])
            dnam.append(contentsOf: [40, 50, 60, 0])
            dnam.append(contentsOf: [70, 80, 90, 0])
            dnam.append(Data(count: size - dnam.count))
            let fields = ESMFixture.field("EDID", ESMFixture.zstring("TestWater"))
                + ESMFixture.field("DNAM", dnam)
            let water = try WaterType(record: record(ESMFixture.record(
                "WATR", formID: 0x18, data: fields
            )))
            #expect(water.formID == FormID(0x18))
            #expect(water.editorID == "TestWater")
            let colors = try #require(water.colors)
            #expect(colors.shallow == SIMD3<Float>(10, 20, 30) / 255)
            #expect(colors.deep == SIMD3<Float>(40, 50, 60) / 255)
            #expect(colors.reflection == SIMD3<Float>(70, 80, 90) / 255)
        }
    }

    @Test func skipsUnknownDNAMVariant() throws {
        let fields = ESMFixture.field("DNAM", Data(count: 52))
        let water = try WaterType(record: record(ESMFixture.record("WATR", data: fields)))
        #expect(water.colors == nil)
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }
}
