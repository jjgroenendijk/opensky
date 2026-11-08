// Material property block decode tests: BSLightingShaderProperty,
// BSShaderTextureSet (+ VFS path normalization), NiAlphaProperty. Synthetic
// in-code payloads only (NIFFixture); layouts per NifTools nif.xml;
// docs/formats/nif.md.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFMaterialBlockTests {
    private func header(strings: [String] = []) throws -> NIFHeader {
        var reader = BinaryReader(NIFFixture.header(strings: strings))
        return try NIFHeader(reader: &reader)
    }

    @Test func decodesLightingShaderProperty() throws {
        let payload = NIFFixture.bsLightingShaderProperty(
            shaderType: 0,
            nameIndex: 0,
            shaderFlags1: 0x8040_0301,
            shaderFlags2: 0x8031, // Double_Sided (0x10) set
            uvOffset: SIMD2(0.25, -0.5),
            uvScale: SIMD2(2, 4),
            textureSetRef: 7,
            emissiveColor: SIMD3(0.1, 0.2, 0.3),
            emissiveMultiple: 4,
            alpha: 0.75,
            glossiness: 128,
            specularColor: SIMD3(0.5, 0.25, 1),
            specularStrength: 2.5,
            tail: Self.floats([0.4, 10])
        )
        let property = try NIFLightingShaderProperty(
            data: payload,
            header: header(strings: ["MyMaterial"])
        )
        #expect(property.shaderType == 0)
        #expect(property.name == "MyMaterial")
        #expect(property.shaderFlags1 == 0x8040_0301)
        #expect(property.shaderFlags2 == 0x8031)
        #expect(property.isDoubleSided)
        #expect(property.uvOffset == SIMD2(0.25, -0.5))
        #expect(property.uvScale == SIMD2(2, 4))
        #expect(property.textureSetRef == 7)
        #expect(property.alpha == 0.75)
        #expect(property.glossiness == 128)
        #expect(property.specularColor == SIMD3(0.5, 0.25, 1))
        #expect(property.specularStrength == 2.5)
        #expect(property.emissiveColor == SIMD3(0.1, 0.2, 0.3))
        #expect(property.emissiveMultiple == 4)
        #expect(property.lightingEffect1 == 0.4)
        #expect(property.lightingEffect2 == 10)
    }

    private static func floats(_ values: [Float]) -> Data {
        var out = Data()
        for value in values {
            out.appendFloat32(value)
        }
        return out
    }

    private static func tail(shaderType: UInt32, _ values: [Float]) throws
        -> NIFLightingShaderProperty.Tail
    {
        let payload = NIFFixture.bsLightingShaderProperty(
            shaderType: shaderType, tail: floats([0.3, 2] + values)
        )
        var reader = BinaryReader(NIFFixture.header())
        return try NIFLightingShaderProperty(data: payload, header: NIFHeader(reader: &reader)).tail
    }

    @Test func readsTheTailOfEachShaderType() throws {
        #expect(try Self.tail(shaderType: 1, [0.7]).environmentMapScale == 0.7)
        #expect(try Self.tail(shaderType: 5, [0.8, 0.7, 0.6]).tintColor == SIMD3(0.8, 0.7, 0.6))
        #expect(try Self.tail(shaderType: 6, [0.6, 0.5, 0.4]).tintColor == SIMD3(0.6, 0.5, 0.4))
        let eye = try Self.tail(shaderType: 16, [1.3, -2.4, 7.6, 3.8, 2.4, 7.6, 3.8])
        #expect(eye.environmentMapScale == 1.3)
        let layer = try Self.tail(shaderType: 11, [3, 0.5, 2, 4, 0.8])
        #expect(layer.innerLayerThickness == 3)
        #expect(layer.refractionScale == 0.5)
        #expect(layer.innerLayerScale == SIMD2(2, 4))
        #expect(layer.environmentStrength == 0.8)
    }

    @Test func aShortTailKeepsTheDefaults() throws {
        #expect(try Self.tail(shaderType: 5, []).tintColor == nil)
        let layer = try Self.tail(shaderType: 11, [3])
        #expect(layer.innerLayerThickness == 3)
        #expect(layer.refractionScale == 0.25)
        #expect(layer.innerLayerScale == SIMD2(1, 1))
        let bare = NIFFixture.bsLightingShaderProperty(shaderType: 1, tail: Data())
        let property = try NIFLightingShaderProperty(data: bare, header: header())
        #expect(property.lightingEffect1 == 0.3)
        #expect(property.tail.environmentMapScale == 1)
    }

    @Test func nonSkyrimStreamIsUnsupportedForShaderProperty() throws {
        var reader = BinaryReader(NIFFixture.header(bsVersion: 90))
        let header = try NIFHeader(reader: &reader)
        #expect(throws: NIFError.self) {
            try NIFLightingShaderProperty(
                data: NIFFixture.bsLightingShaderProperty(),
                header: header
            )
        }
    }

    @Test func decodesTextureSetSlots() throws {
        let set = try NIFShaderTextureSet(
            data: NIFFixture.bsShaderTextureSet(paths: [
                "textures\\architecture\\farmhouse\\FarmHouse01.dds",
                "Textures/architecture/farmhouse/farmhouse01_n.DDS",
                "", "", "textures\\cubemaps\\chrome.dds", ""
            ]),
            header: header()
        )
        #expect(set.paths.count == 6)
        #expect(set.diffusePath == "textures/architecture/farmhouse/farmhouse01.dds")
        #expect(set.normalPath == "textures/architecture/farmhouse/farmhouse01_n.dds")
    }

    @Test func normalizesTexturePathVariants() {
        #expect(NIFShaderTextureSet.vfsKey(for: "FarmHouse01.dds")
            == "textures/farmhouse01.dds")
        #expect(NIFShaderTextureSet.vfsKey(for: "data\\textures\\a\\b.dds")
            == "textures/a/b.dds")
        #expect(NIFShaderTextureSet.vfsKey(for: "\\textures\\a.dds")
            == "textures/a.dds")
        #expect(NIFShaderTextureSet.vfsKey(for: "") == nil)
        #expect(NIFShaderTextureSet.vfsKey(for: "  ") == nil)
    }

    @Test func truncatesExporterAbsolutePathsAtLastTexturesComponent() {
        // Observed in vanilla (probe 2026-07-10): shipping meshes carry
        // exporter-absolute paths; the game resolves them from the last
        // `textures/` component.
        #expect(NIFShaderTextureSet.vfsKey(
            for: "Textures\\SkyrimHD\\build\\PC\\data\\textures\\clutter\\carrot.dds"
        ) == "textures/clutter/carrot.dds")
        // Component boundary required: no mid-word truncation.
        #expect(NIFShaderTextureSet.vfsKey(for: "mytextures\\foo.dds")
            == "textures/mytextures/foo.dds")
    }

    @Test func oversizedTextureCountIsMalformed() throws {
        var payload = Data()
        payload.appendUInt32(0xFFFF)
        #expect(throws: NIFError.self) {
            try NIFShaderTextureSet(data: payload, header: header())
        }
    }

    @Test func decodesAlphaPropertyBits() throws {
        // Blend on, src DEST_COLOR (4), dst INV_DEST_COLOR (5), test on,
        // func GREATER (4), no-sorter on: 1 | 4<<1 | 5<<5 | 0x200 | 4<<10 | 0x2000.
        let flags: UInt16 = 1 | 4 << 1 | 5 << 5 | 0x200 | 4 << 10 | 0x2000
        let property = try NIFAlphaProperty(
            data: NIFFixture.niAlphaProperty(nameIndex: 0, flags: flags, threshold: 128),
            header: header(strings: ["AlphaProp"])
        )
        #expect(property.name == "AlphaProp")
        #expect(property.blendEnabled)
        #expect(property.sourceBlendMode == 4)
        #expect(property.destinationBlendMode == 5)
        #expect(property.testEnabled)
        #expect(property.testFunction == 4)
        #expect(property.noSorter)
        #expect(abs(property.testThreshold - 128.0 / 255) < 1e-6)
    }

    @Test func alphaPropertyDefaultsDecodeAsTestOnly() throws {
        // nif.xml default 4844 = 0x12EC: blend off, test on.
        let property = try NIFAlphaProperty(
            data: NIFFixture.niAlphaProperty(flags: 4844, threshold: 64),
            header: header()
        )
        #expect(!property.blendEnabled)
        #expect(property.testEnabled)
    }
}
