// IMGS, IMAD, EFSH, EXPL, DEBR, ADDN, RFCT, SPGD, VOLI, MATO, SOPM and REVB
// over synthetic fields, with their DATA size variants. Layout sources:
// xEdit wbDefinitionsTES5.pas; see the matching docs/formats/ pages.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct VisualRecordTests {
    private typealias Fixture = ESMFixture

    @Test(arguments: [12, 16])
    func decodesImageSpaceDepthOfFieldSizes(size: Int) throws {
        let dof = Fixture.f32(0.5, 100, 200) + (size == 16 ? Fixture.u16(0, 300) : Data())
        let space = try ImageSpace(record: Fixture.record("IMGS", fields: [
            ("ENAM", Fixture.f32(Array(repeating: 1, count: 14) as [Float])),
            ("HNAM", Fixture.f32(1, 2, 3, 4, 5, 6, 7, 8, 9)),
            ("CNAM", Fixture.f32(1, 1.2, 0.9)),
            ("TNAM", Fixture.f32(0.1, 1, 0, 0)),
            ("DNAM", dof)
        ]))
        #expect(space.hdr?.eyeAdaptSpeed == 1)
        #expect(space.hdr?.eyeAdaptStrength == 9)
        #expect(space.cinematic?.brightness == 1.2)
        #expect(space.tint?.color == SIMD3(1, 0, 0))
        #expect(space.depthOfField?.range == 200)
        #expect(space.depthOfField?.skyBlurRadius == (size == 16 ? 300 : nil))
        #expect(space.legacyData?.count == 14)
        #expect(space.skipped.isEmpty)
    }

    @Test func decodesImageSpaceAdapterEnvelopesAndTalliesCountMismatch() throws {
        var header = Fixture.u32(1) + Fixture.f32(2)
        header += Fixture.words(Array(repeating: 0, count: 42))
        header += Fixture.u32(1) // tint count
        header += Fixture.u32(0, 0, 0, 0, 0) + Fixture.u32(0) + Fixture.f32(0, 0)
        header += Fixture.u32(0, 0, 0) + Fixture.u8(0, 0, 0, 0) + Fixture.u32(0, 0, 0, 0)
        let adapter = try ImageSpaceAdapter(record: Fixture.record("IMAD", fields: [
            ("DNAM", header),
            ("TNAM", Fixture.f32(0, 1, 1, 1, 1)),
            ("BNAM", Fixture.f32(0, 0, 1, 4)),
            ("@IAD", Fixture.f32(0, 0.5))
        ]))
        #expect(adapter.header?.duration == 2)
        #expect(adapter.tint.count == 1)
        #expect(adapter.envelopes[.blurRadius]?.count == 2)
        #expect(adapter.envelopes[.hdr(index: 0, add: true)]?.first?.value == 0.5)
        #expect(adapter.skipped.total == 2)
        #expect(ImageSpaceChannel(signature: "QIAD") == .cinematic(index: 0, add: true))
        #expect(ImageSpaceChannel(signature: "ZZZZ") == nil)
    }

    @Test(arguments: [308, 400])
    func decodesEffectShaderSizes(size: Int) throws {
        let shader = try EffectShader(record: Fixture.record("EFSH", fields: [
            ("ICON", Fixture.zstring("fill.dds")),
            ("DATA", Fixture.u8(0x01, 0, 0, 0) + Fixture.u32(5) + Data(count: size - 8))
        ]))
        #expect(shader.fillTexture == "fill.dds")
        #expect(shader.dataSize == size)
        #expect(shader.members.count == size / 4)
        #expect(shader.value(.legacyFlags) == .uint(1))
        #expect(shader.value(.membraneSourceBlend) == .uint(5))
        #expect((shader.flags != nil) == (size >= 400))
    }

    @Test(arguments: [40, 44, 48, 52])
    func decodesExplosionDataSizes(size: Int) throws {
        let data = Fixture.u32(0x10, 0, 0, 0, 0, 0) + Fixture.f32(50, 25, 300, 100)
            + Fixture.f32(1.5) + Fixture.u32(0x02) + Fixture.u32(1)
        let explosion = try Explosion(record: Fixture.record("EXPL", fields: [
            ("EITM", Fixture.u32(0x20)),
            ("DATA", data.prefix(size))
        ]), localized: false)
        let properties = try #require(explosion.properties)
        #expect(properties.light == FormID(0x10))
        #expect(properties.radius == 300)
        #expect(properties.size == size)
        #expect((properties.verticalOffsetMultiplier != nil) == (size >= 44))
        #expect((properties.soundLevel != nil) == (size >= 52))
        #expect(explosion.enchantment == FormID(0x20))
    }

    @Test func decodesDebrisModelsWithTheirHashes() throws {
        let debris = try Debris(record: Fixture.record("DEBR", fields: [
            ("DATA", Fixture.u8(40) + Fixture.zstring("rock01.nif") + Fixture.u8(1)),
            ("MODT", Data(count: 12)),
            ("DATA", Fixture.u8(60) + Fixture.zstring("rock02.nif") + Fixture.u8(0))
        ]))
        #expect(debris.models.map(\.path) == ["rock01.nif", "rock02.nif"])
        #expect(debris.models[0].hasCollision)
        #expect(debris.models[0].textureHashes?.count == 12)
        #expect(debris.models[1].textureHashes == nil)
    }

    @Test func decodesAddonNodeAndVisualEffect() throws {
        let node = try AddonNode(record: Fixture.record("ADDN", fields: [
            ("MODL", Fixture.zstring("fx.nif")), ("DATA", Fixture.u32(7)),
            ("SNAM", Fixture.u32(0x30)), ("DNAM", Fixture.u16(40, 1))
        ]))
        #expect(node.nodeIndex == 7)
        #expect(node.masterParticleSystemCap == 40)
        #expect(node.flags == 1)
        let effect = try VisualEffect(record: Fixture.record("RFCT", fields: [
            ("DATA", Fixture.u32(0x40, 0x41, 0x02))
        ]))
        #expect(effect.effectArt == FormID(0x40))
        #expect(effect.shader == FormID(0x41))
        #expect(effect.flags == 2)
    }

    @Test(arguments: [40, 48])
    func decodesShaderParticleGeometrySizes(size: Int) throws {
        let data = Fixture.f32(10, 1, 2, 3, 0, 0, 0) + Fixture.u32(1, 1, 0) + Fixture.u32(5)
            + Fixture.f32(0.5)
        let geometry = try ShaderParticleGeometry(record: Fixture.record("SPGD", fields: [
            ("DATA", data.prefix(size)), ("ICON", Fixture.zstring("rain.dds"))
        ]))
        #expect(geometry.properties?.gravityVelocity == 10)
        #expect(geometry.properties?.particleSize == SIMD2(2, 3))
        #expect((geometry.properties?.boxSize != nil) == (size == 48))
        #expect(geometry.texturePath == "rain.dds")
    }

    @Test func decodesReverbParameters() throws {
        let reverb = try ReverbParameters(record: Fixture.record("REVB", fields: [
            (
                "DATA",
                Fixture.u16(1500, 5000)
                    + Fixture.u8(0xF6, 0xFB, 0, 0, 80, 20, 40, 100, 100, 0)
            )
        ]))
        #expect(reverb.properties?.decayTimeMilliseconds == 1500)
        #expect(reverb.properties?.roomFilter == -10)
        #expect(reverb.properties?.decayHFRatio == 0.8)
        #expect(reverb.properties?.densityPercent == 100)
    }

    @Test func truncatedReverbIsTalliedNotThrown() throws {
        let reverb = try ReverbParameters(record: Fixture.record("REVB", fields: [
            ("DATA", Fixture.u16(1500))
        ]))
        #expect(reverb.properties == nil)
        #expect(reverb.skipped.counts[.malformedField("DATA")] == 1)
    }
}
