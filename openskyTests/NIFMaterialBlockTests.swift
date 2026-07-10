// Material property block decode tests: BSLightingShaderProperty,
// BSShaderTextureSet (+ VFS path normalization), NiAlphaProperty. Synthetic
// in-code payloads only (NIFFixture); layouts per NifTools nif.xml;
// docs/formats/nif.md.

import Foundation
@testable import opensky
import simd
import Testing

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
            alpha: 0.75,
            glossiness: 128,
            specularColor: SIMD3(0.5, 0.25, 1),
            specularStrength: 2.5
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
    }

    @Test func ignoresShaderTypeConditionalTail() throws {
        // Environment-map shader (type 1) appends a float tail the decoder
        // must never touch — truncated or huge tails both parse.
        let payload = NIFFixture.bsLightingShaderProperty(
            shaderType: 1,
            tail: Data(count: 12) // lighting effects + env map scale
        )
        let property = try NIFLightingShaderProperty(data: payload, header: header())
        #expect(property.shaderType == 1)
        #expect(!property.isDoubleSided)
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
        // Blend on, src SRC_ALPHA (4), dst INV_SRC_ALPHA (5), test on,
        // func GREATER (4), no-sorter on: 1 | 4<<1 | 5<<5 | 0x200 | 4<<10 | 0x2000.
        let flags: UInt16 = 1 | 4 << 1 | 5 << 5 | 0x200 | 4 << 10 | 0x2000
        let property = try NIFAlphaProperty(
            data: NIFFixture.niAlphaProperty(flags: flags, threshold: 128),
            header: header()
        )
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
