// Lighting decoder tests use synthetic in-code records only. Layouts:
// UESP CELL/LGTM/LIGH pages + xEdit dev-4.1.6 wbDefinitionsTES5.pas.

import Foundation
@testable import opensky
import Testing

struct LightingRecordDecoderTests {
    @Test func lightingTemplateUsesDALCDirectionalAmbient() throws {
        var dalc = Data()
        appendColor(101, 102, 103, to: &dalc)
        appendColor(104, 105, 106, to: &dalc)
        appendColor(107, 108, 109, to: &dalc)
        appendColor(110, 111, 112, to: &dalc)
        appendColor(113, 114, 115, to: &dalc)
        appendColor(116, 117, 118, to: &dalc)
        appendColor(0, 0, 0, to: &dalc) // unused specular color
        dalc.appendFloat32(1) // unused Fresnel power
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("InteriorTemplate"))
            + ESMFixture.field("DATA", ESMFixture.cellLightingData(inherits: 0))
            + ESMFixture.field("DALC", dalc)
        let template = try LightingTemplate(
            record: record(ESMFixture.record("LGTM", formID: 0x6175D, data: fields))
        )

        #expect(template.editorID == "InteriorTemplate")
        #expect(template.values.directionalAmbient?.positiveX == color(101, 102, 103))
        #expect(template.values.directionalAmbient?.negativeZ == color(116, 117, 118))
    }

    @Test func resolverAppliesInheritancePerField() throws {
        let local = try #require(try CellLightingValues.decode(
            ESMFixture.cellLightingData(inherits: 0x0001 | 0x0010 | 0x0100),
            hasInheritFlags: true
        ))
        var templateData = ESMFixture.cellLightingData(inherits: 0)
        templateData.replaceSubrange(0 ..< 4, with: [200, 201, 202, 0])
        templateData.replaceSubrange(16 ..< 20, with: floatBytes(1600))
        templateData.replaceSubrange(36 ..< 40, with: floatBytes(3))
        let template = try #require(try CellLightingValues.decode(
            templateData,
            hasInheritFlags: false
        ))

        let resolved = try #require(CellSceneBuilder.resolvedLighting(
            cell: local,
            template: template
        ))
        #expect(resolved.ambientColor == color(200, 201, 202))
        #expect(resolved.directionalColor == local.directionalColor)
        #expect(resolved.fogFar == 1600)
        #expect(resolved.fogPower == 3)
        #expect(resolved.inherits.isEmpty)
    }

    @Test func lightDecodesExactDATAAndFNAM() throws {
        var data = Data()
        data.appendUInt32(UInt32(bitPattern: -1))
        data.appendUInt32(512)
        appendColor(128, 64, 32, to: &data)
        data.appendUInt32(LightRecord.Flags.inverseSquare.rawValue)
        data.appendFloat32(2)
        data.append(Data(count: 28))
        var fnam = Data()
        fnam.appendFloat32(0.5)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("WarmLight"))
            + ESMFixture.field("DATA", data)
            + ESMFixture.field("FNAM", fnam)
        let light = try LightRecord(
            record: record(ESMFixture.record("LIGH", formID: 0x1234, data: fields))
        )

        #expect(light.editorID == "WarmLight")
        #expect(light.time == -1)
        #expect(light.radius == 512)
        #expect(light.color == color(128, 64, 32))
        #expect(light.flags == .inverseSquare)
        #expect(light.falloffExponent == 2)
        #expect(light.fade == 0.5)
        #expect(light.isSupportedPointLight)
    }

    @Test func lightRejectsWrongDATASizeAndUnsupportedShapes() throws {
        let bad = ESMFixture.field("DATA", Data(count: 47))
        #expect(throws: (any Error).self) {
            _ = try LightRecord(record: record(ESMFixture.record("LIGH", data: bad)))
        }

        for flags: LightRecord.Flags in [.negative, .spotLight, .shadowSpotlight] {
            var data = Data(count: 48)
            data.replaceSubrange(12 ..< 16, with: uint32Bytes(flags.rawValue))
            let light = try LightRecord(
                record: record(ESMFixture.record(
                    "LIGH", data: ESMFixture.field("DATA", data)
                ))
            )
            #expect(!light.isSupportedPointLight)
        }
    }

    @Test func referenceDecodesLightOverrides() throws {
        var name = Data()
        name.appendUInt32(0x100)
        var radius = Data()
        radius.appendFloat32(384)
        var emittance = Data()
        emittance.appendUInt32(0x200)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", Data(count: 24))
            + ESMFixture.field("XRDS", radius)
            + ESMFixture.field("XEMI", emittance)
        let reference = try PlacedReference(
            record: record(ESMFixture.record("REFR", data: fields))
        )

        #expect(reference.lightRadius == 384)
        #expect(reference.emittance == FormID(0x200))
    }

    @Test func nearestPointLightsAreStableAndBounded() {
        let lights = (0 ..< 10).map { index in
            RenderPointLight(
                position: SIMD3(Float(9 - index), 0, 0),
                radius: 100,
                color: .one,
                falloffExponent: 1
            )
        }
        let scene = RenderScene(instances: [], pointLights: lights)
        let nearest = scene.nearestPointLights(to: .zero, limit: 8)

        #expect(nearest.count == 8)
        #expect(nearest.map(\.position.x) == [0, 1, 2, 3, 4, 5, 6, 7])
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    private func appendColor(
        _ red: UInt8,
        _ green: UInt8,
        _ blue: UInt8,
        to data: inout Data
    ) {
        data.append(contentsOf: [red, green, blue, 0])
    }

    private func color(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> SIMD3<Float> {
        SIMD3(Float(red) / 255, Float(green) / 255, Float(blue) / 255)
    }

    private func floatBytes(_ value: Float) -> Data {
        uint32Bytes(value.bitPattern)
    }

    private func uint32Bytes(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
