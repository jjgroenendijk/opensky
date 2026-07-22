// Synthetic GRAS + LTEX GNAM decoder tests. Fixtures contain authored bytes
// only, never extracted game data.

import Foundation
@testable import opensky
import Testing

struct GrassRecordTests {
    @Test func decodesFullGRASData() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("TestGrass"))
            + ESMFixture.field("MODL", ESMFixture.zstring("Landscape\\Grass\\Test.nif"))
            + ESMFixture.field("DATA", placementData(
                density: 73,
                minimumSlope: 4,
                maximumSlope: 62,
                unitsFromWater: 128,
                waterRule: 5,
                positionRange: 96,
                heightRange: 0.35,
                colorRange: 0.4,
                wavePeriod: 2.5,
                flags: 0x07
            ))
        let grass = try Grass(record: record(
            ESMFixture.record("GRAS", formID: 0x1234, data: fields)
        ))

        #expect(grass.formID == FormID(0x1234))
        #expect(grass.editorID == "TestGrass")
        #expect(grass.modelPath == "Landscape\\Grass\\Test.nif")
        let placement = try #require(grass.placement)
        #expect(placement.density == 73)
        #expect(placement.minimumSlopeDegrees == 4)
        #expect(placement.maximumSlopeDegrees == 62)
        #expect(placement.unitsFromWater == 128)
        #expect(placement.waterRule == .eitherAtMost)
        #expect(placement.positionRange == 96)
        #expect(placement.heightRange == 0.35)
        #expect(placement.colorRange == 0.4)
        #expect(placement.wavePeriod == 2.5)
        #expect(placement.flags == [.vertexLighting, .uniformScaling, .fitToSlope])
    }

    @Test func preservesUnknownWaterRuleAndUnknownFlagBits() throws {
        let data = placementData(waterRule: 99, flags: 0x84)
        let grass = try Grass(record: record(
            ESMFixture.record("GRAS", data: ESMFixture.field("DATA", data))
        ))
        #expect(grass.placement?.waterRule == .unknown(99))
        #expect(grass.placement?.flags.rawValue == 0x84)
    }

    @Test func missingDATAStaysRepresentable() throws {
        let grass = try Grass(record: record(ESMFixture.record(
            "GRAS",
            data: ESMFixture.field("EDID", ESMFixture.zstring("IncompleteGrass"))
        )))
        #expect(grass.editorID == "IncompleteGrass")
        #expect(grass.placement == nil)
    }

    @Test func rejectsWrongTypeAndMalformedDATA() {
        #expect(throws: (any Error).self) {
            _ = try Grass(record: record(ESMFixture.record("STAT", data: Data())))
        }
        #expect(throws: (any Error).self) {
            _ = try Grass(record: record(ESMFixture.record(
                "GRAS",
                data: ESMFixture.field("DATA", Data(count: 31))
            )))
        }
        #expect(throws: (any Error).self) {
            _ = try Grass(record: record(ESMFixture.record(
                "GRAS",
                data: ESMFixture.field("DATA", Data(count: 33))
            )))
        }
    }

    @Test func landTextureDecodesRepeatedGNAM() throws {
        var first = Data()
        first.appendUInt32(0x10)
        var second = Data()
        second.appendUInt32(0x20)
        let fields = ESMFixture.field("GNAM", first)
            + ESMFixture.field("GNAM", second)
        let texture = try LandTexture(record: record(
            ESMFixture.record("LTEX", data: fields)
        ))
        #expect(texture.grasses == [FormID(0x10), FormID(0x20)])
    }

    @Test func landTextureRejectsTruncatedGNAM() {
        #expect(throws: (any Error).self) {
            _ = try LandTexture(record: record(ESMFixture.record(
                "LTEX",
                data: ESMFixture.field("GNAM", Data(count: 3))
            )))
        }
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    private func placementData(
        density: UInt8 = 100,
        minimumSlope: UInt8 = 0,
        maximumSlope: UInt8 = 90,
        unitsFromWater: UInt16 = 0,
        waterRule: UInt32 = 0,
        positionRange: Float = 128,
        heightRange: Float = 0,
        colorRange: Float = 0,
        wavePeriod: Float = 1,
        flags: UInt8 = 0
    ) -> Data {
        var data = Data()
        data.append(density)
        data.append(minimumSlope)
        data.append(maximumSlope)
        data.append(0)
        data.appendUInt16(unitsFromWater)
        data.appendUInt16(0)
        data.appendUInt32(waterRule)
        data.appendFloat32(positionRange)
        data.appendFloat32(heightRange)
        data.appendFloat32(colorRange)
        data.appendFloat32(wavePeriod)
        data.append(flags)
        data.append(contentsOf: [0, 0, 0])
        return data
    }
}
