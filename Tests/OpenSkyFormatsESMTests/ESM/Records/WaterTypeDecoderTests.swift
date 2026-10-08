// WATR decoder coverage over synthetic DNAM bytes only. Layout sources:
// UESP WATR + xEdit dev-4.1.6; see docs/formats/water.md.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
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
            let water = try WaterType(record: ESMFixture.parseRecord(ESMFixture.record(
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

    @Test func decodesSurfaceFieldsAtTheirOffsets() throws {
        var dnam = Data(count: 228)
        func put(_ value: Float, at offset: Int) {
            withUnsafeBytes(of: value.bitPattern.littleEndian) {
                dnam.replaceSubrange(offset ..< offset + 4, with: $0)
            }
        }
        let singles: [(Int, Float)] = [
            (16, 1021), (20, 0.8), (24, 0.1), (32, -10), (36, 150),
            (196, 0.42), (200, 2.89), (204, 4.65), (224, 3521)
        ]
        for (offset, value) in singles {
            put(value, at: offset)
        }
        for (base, values) in [
            (100, [233, 267, 252]),
            (112, [0.09, 0.04, 0.3]),
            (172, [1667, 4855, 580]),
            (184, [0.9, 0.92, 0.65])
        ] {
            for (index, value) in values.enumerated() {
                put(Float(value), at: base + index * 4)
            }
        }
        let water = try WaterType(record: ESMFixture.parseRecord(ESMFixture.record(
            "WATR", data: ESMFixture.field("DNAM", dnam)
        )))
        let surface = try #require(water.surface)
        #expect(surface.sunSpecularPower == 1021)
        #expect(surface.fresnelAmount == 0.1)
        #expect(surface.fogNear == -10)
        #expect(surface.fogFar == 150)
        #expect(surface.windDirections == SIMD3(233, 267, 252))
        #expect(surface.windSpeeds == SIMD3(0.09, 0.04, 0.3))
        #expect(surface.uvScales == SIMD3(1667, 4855, 580))
        #expect(surface.amplitudes == SIMD3(0.9, 0.92, 0.65))
        #expect(surface.sunSpecularMagnitude == 4.65)
        #expect(surface.sunSparklePower == 3521)
    }

    @Test func skipsUnknownDNAMVariant() throws {
        let fields = ESMFixture.field("DNAM", Data(count: 52))
        let water = try WaterType(record: ESMFixture.parseRecord(ESMFixture.record(
            "WATR",
            data: fields
        )))
        #expect(water.colors == nil)
        #expect(water.surface == nil)
    }
}
