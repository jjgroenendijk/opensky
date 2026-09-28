// BSEffectShaderProperty decode tests. Fixtures built in code from nif.xml
// layout (never extracted game files, AGENTS.md "Legal & IP boundary").
// Layout: NifTools nif.xml (BSEffectShaderProperty, SkyrimShaderPropertyFlags1/2).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml

@testable import opensky
import simd
import XCTest

final class NIFEffectShaderTests: XCTestCase {
    /// Local payload builder — NIFFixture is shared and off-limits here, so the
    /// BSEffectShaderProperty byte layout lives in this file only.
    private struct EffectFixture {
        var nameIndex: UInt32 = 0xFFFF_FFFF
        var shaderFlags1: UInt32 = 0x8000_0000
        var shaderFlags2: UInt32 = 0x20
        var uvOffset = SIMD2<Float>(0, 0)
        var uvScale = SIMD2<Float>(1, 1)
        var sourceTexture = "textures/effects/glow.dds"
        var textureClampMode: UInt8 = 3
        var lightingInfluence: UInt8 = 255
        var envMapMinLOD: UInt8 = 0
        var unusedByte: UInt8 = 0
        var falloffStartAngle: Float = 1
        var falloffStopAngle: Float = 1
        var falloffStartOpacity: Float = 0
        var falloffStopOpacity: Float = 1
        var baseColor = SIMD4<Float>(1, 1, 1, 1)
        var baseColorScale: Float = 1
        var softFalloffDepth: Float = 100
        var greyscaleTexture = "textures/effects/palette.dds"

        func sizedString(_ string: String) -> Data {
            var out = Data()
            out.appendUInt32(UInt32(string.utf8.count))
            out.append(Data(string.utf8))
            return out
        }

        func data() -> Data {
            var out = Data()
            out.appendUInt32(nameIndex)
            out.appendUInt32(0) // extra data count
            out.appendUInt32(UInt32(bitPattern: -1)) // controller ref
            out.appendUInt32(shaderFlags1)
            out.appendUInt32(shaderFlags2)
            out.appendFloat32(uvOffset.x)
            out.appendFloat32(uvOffset.y)
            out.appendFloat32(uvScale.x)
            out.appendFloat32(uvScale.y)
            out.append(sizedString(sourceTexture))
            out.append(textureClampMode)
            out.append(lightingInfluence)
            out.append(envMapMinLOD)
            out.append(unusedByte)
            out.appendFloat32(falloffStartAngle)
            out.appendFloat32(falloffStopAngle)
            out.appendFloat32(falloffStartOpacity)
            out.appendFloat32(falloffStopOpacity)
            out.appendFloat32(baseColor.x)
            out.appendFloat32(baseColor.y)
            out.appendFloat32(baseColor.z)
            out.appendFloat32(baseColor.w)
            out.appendFloat32(baseColorScale)
            out.appendFloat32(softFalloffDepth)
            out.append(sizedString(greyscaleTexture))
            return out
        }
    }

    private func header(
        bsVersion: UInt32 = 100,
        strings: [String] = []
    ) throws -> NIFHeader {
        let bytes = NIFFixture.header(
            userVersion: 12,
            bsVersion: bsVersion,
            blocks: [NIFFixture.Block("BSEffectShaderProperty", Data())],
            strings: strings
        )
        var reader = BinaryReader(bytes)
        return try NIFHeader(reader: &reader)
    }

    func testRoundTripStream100() throws {
        var fixture = EffectFixture()
        fixture.nameIndex = 0
        fixture
            .shaderFlags1 = 0x4000_0071 // Soft_Effect | Use_Falloff | GS color/alpha | vertex alpha
        fixture.shaderFlags2 = 0x11 // Double_Sided | ZBuffer_Write
        fixture.uvOffset = SIMD2(0.25, 0.5)
        fixture.uvScale = SIMD2(2, 4)
        fixture.textureClampMode = 3
        fixture.falloffStartAngle = 0.1
        fixture.falloffStopAngle = 0.9
        fixture.falloffStartOpacity = 0.2
        fixture.falloffStopOpacity = 0.8
        fixture.baseColor = SIMD4(0.1, 0.2, 0.3, 0.4)
        fixture.baseColorScale = 3.5
        fixture.softFalloffDepth = 55

        let head = try header(strings: ["GlowEffect"])
        let property = try NIFEffectShaderProperty(data: fixture.data(), header: head)

        XCTAssertEqual(property.name, "GlowEffect")
        XCTAssertEqual(property.shaderFlags1, 0x4000_0071)
        XCTAssertEqual(property.shaderFlags2, 0x11)
        XCTAssertEqual(property.uvOffset, SIMD2(0.25, 0.5))
        XCTAssertEqual(property.uvScale, SIMD2(2, 4))
        XCTAssertEqual(property.sourceTexture, "textures/effects/glow.dds")
        XCTAssertEqual(property.textureClampMode, 3)
        XCTAssertEqual(property.falloffStartAngle, 0.1)
        XCTAssertEqual(property.falloffStopAngle, 0.9)
        XCTAssertEqual(property.falloffStartOpacity, 0.2)
        XCTAssertEqual(property.falloffStopOpacity, 0.8)
        XCTAssertEqual(property.baseColor, SIMD4(0.1, 0.2, 0.3, 0.4))
        XCTAssertEqual(property.baseColorScale, 3.5)
        XCTAssertEqual(property.softFalloffDepth, 55)
        XCTAssertEqual(property.greyscaleTexture, "textures/effects/palette.dds")
        XCTAssertEqual(property.sourceTexturePath, "textures/effects/glow.dds")
        XCTAssertEqual(property.greyscaleTexturePath, "textures/effects/palette.dds")
    }

    /// BS stream 83 (Skyrim LE) shares the exact BSEffectShaderProperty layout
    /// with stream 100 (nif.xml gates all differing fields on FO4+); same bytes
    /// must decode identically under the 83 guard branch.
    func testRoundTripStream83MatchesStream100() throws {
        let fixture = EffectFixture()
        let bytes = fixture.data()

        let head83 = try header(bsVersion: 83)
        let head100 = try header(bsVersion: 100)
        let property83 = try NIFEffectShaderProperty(data: bytes, header: head83)
        let property100 = try NIFEffectShaderProperty(data: bytes, header: head100)

        XCTAssertEqual(property83.sourceTexture, property100.sourceTexture)
        XCTAssertEqual(property83.greyscaleTexture, property100.greyscaleTexture)
        XCTAssertEqual(property83.baseColor, property100.baseColor)
        XCTAssertEqual(property83.softFalloffDepth, property100.softFalloffDepth)
        XCTAssertEqual(property83.shaderFlags1, property100.shaderFlags1)
    }

    func testFlagAccessorsBitByBit() throws {
        let head = try header()

        // Each SLSF1 bit isolated.
        try assertFlags1(0x08, on: head) { XCTAssertTrue($0.hasVertexAlpha) }
        try assertFlags1(0x10, on: head) {
            XCTAssertTrue($0.usesGreyscaleToPaletteColor)
        }
        try assertFlags1(0x20, on: head) {
            XCTAssertTrue($0.usesGreyscaleToPaletteAlpha)
        }
        try assertFlags1(0x40, on: head) { XCTAssertTrue($0.usesFalloff) }
        try assertFlags1(0x4000_0000, on: head) { XCTAssertTrue($0.isSoftEffect) }
        try assertFlags1(0x8000_0000, on: head) { XCTAssertTrue($0.isZBufferTest) }

        // Clearing all SLSF1 bits flips every SLSF1-derived accessor off.
        try assertFlags1(0, on: head) {
            XCTAssertFalse($0.hasVertexAlpha)
            XCTAssertFalse($0.usesGreyscaleToPaletteColor)
            XCTAssertFalse($0.usesGreyscaleToPaletteAlpha)
            XCTAssertFalse($0.usesFalloff)
            XCTAssertFalse($0.isSoftEffect)
            XCTAssertFalse($0.isZBufferTest)
        }

        // SLSF2 bit 4 Double_Sided.
        try assertFlags2(0x10, on: head) { XCTAssertTrue($0.isDoubleSided) }
        try assertFlags2(0, on: head) { XCTAssertFalse($0.isDoubleSided) }

        // SLSF2 bit 0 ZBuffer_Write: set -> writes enabled, clear -> disabled.
        try assertFlags2(0x01, on: head) {
            XCTAssertFalse($0.isZBufferWriteDisabled)
        }
        try assertFlags2(0, on: head) {
            XCTAssertTrue($0.isZBufferWriteDisabled)
        }
    }

    func testUnsupportedStreamRejected() throws {
        let fixture = EffectFixture()
        // Pre-Skyrim BS stream (34, FO3 era). FO4 (130) needs a wider stream
        // header the fixture does not emit, so a lower non-83/100 stream stands
        // in for "reject anything but Skyrim 83/100".
        let head = try header(bsVersion: 34)
        XCTAssertThrowsError(
            try NIFEffectShaderProperty(data: fixture.data(), header: head)
        ) { error in
            guard case NIFError.unsupported = error else {
                return XCTFail("expected NIFError.unsupported, got \(error)")
            }
        }
    }

    func testTruncatedPayloadThrows() throws {
        let head = try header()
        let full = EffectFixture().data()
        // Cut mid-payload: must throw, never crash.
        let truncated = full.prefix(full.count - 10)
        XCTAssertThrowsError(
            try NIFEffectShaderProperty(data: Data(truncated), header: head)
        )
    }

    func testGarbageTextureLengthThrows() throws {
        let head = try header()
        var fixture = EffectFixture()
        fixture.sourceTexture = ""
        var bytes = fixture.data()
        // Overwrite the source-texture length prefix (after 12-byte NiObjectNET
        // + 8 flags + 16 UV = offset 36) with a huge value.
        bytes.replaceSubrange(
            36 ..< 40,
            with: withUnsafeBytes(of: UInt32(0xFFFF).littleEndian) { Data($0) }
        )
        XCTAssertThrowsError(
            try NIFEffectShaderProperty(data: bytes, header: head)
        ) { error in
            guard case NIFError.malformed = error else {
                return XCTFail("expected NIFError.malformed, got \(error)")
            }
        }
    }

    func testGarbageNameIndexTolerated() throws {
        var fixture = EffectFixture()
        fixture.nameIndex = 0xDEAD_BEEF // out of range -> name nil, no throw
        let head = try header(strings: ["OnlyString"])
        let property = try NIFEffectShaderProperty(data: fixture.data(), header: head)
        XCTAssertNil(property.name)
        XCTAssertEqual(property.sourceTexture, "textures/effects/glow.dds")
    }

    func testEmptyTexturesDecodeNil() throws {
        var fixture = EffectFixture()
        fixture.sourceTexture = ""
        fixture.greyscaleTexture = ""
        let head = try header()
        let property = try NIFEffectShaderProperty(data: fixture.data(), header: head)
        XCTAssertNil(property.sourceTexture)
        XCTAssertNil(property.greyscaleTexture)
        XCTAssertNil(property.sourceTexturePath)
        XCTAssertNil(property.greyscaleTexturePath)
    }

    // Helpers: decode a fixture with one flag word overridden, run assertions.
    private func assertFlags1(
        _ value: UInt32,
        on header: NIFHeader,
        _ check: (NIFEffectShaderProperty) -> Void
    ) throws {
        var fixture = EffectFixture()
        fixture.shaderFlags1 = value
        try check(NIFEffectShaderProperty(data: fixture.data(), header: header))
    }

    private func assertFlags2(
        _ value: UInt32,
        on header: NIFHeader,
        _ check: (NIFEffectShaderProperty) -> Void
    ) throws {
        var fixture = EffectFixture()
        fixture.shaderFlags2 = value
        try check(NIFEffectShaderProperty(data: fixture.data(), header: header))
    }
}
