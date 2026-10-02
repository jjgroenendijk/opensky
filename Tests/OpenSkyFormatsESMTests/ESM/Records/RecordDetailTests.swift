// The detail decoders of WTHR, CELL, RACE, NPC_ and WRLD, the shared field
// groups (DEST, attacks, inventory), positional model groups, and the
// decoder registry, over synthetic fields. See docs/formats/records.md.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct RecordDetailTests {
    private typealias Fixture = ESMFixture

    @Test func decodesWeatherSkyLinksAndCloudLayers() throws {
        let weather = try Weather(record: Fixture.record("WTHR", fields: [
            ("00TX", Fixture.zstring("cloud0.dds")), ("A0TX", Fixture.zstring("cloud17.dds")),
            ("LNAM", Fixture.u32(4)), ("MNAM", Fixture.u32(0x10)), ("NNAM", Fixture.u32(0)),
            ("RNAM", Fixture.u8(127, 130)), ("QNAM", Fixture.u8(127)),
            ("JNAM", Fixture.f32(1, 0.5, 1, 0.2)),
            ("NAM1", Fixture.u32(0x02)),
            ("SNAM", Fixture.u32(0x20, 2)), ("TNAM", Fixture.u32(0x30)),
            ("IMSP", Fixture.u32(0x40, 0x41, 0x42, 0x43)),
            ("HNAM", Fixture.u32(0x50, 0, 0, 0)),
            ("NAM2", Fixture.u8(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)),
            ("DATA", Data(count: 7))
        ]))
        let sky = weather.sky
        #expect(sky.cloudLayers[0].texture == "cloud0.dds")
        #expect(sky.cloudLayers[17].texture == "cloud17.dds")
        #expect(sky.cloudLayers[1].speedY == 130)
        #expect(sky.cloudLayers[1].speedX == nil)
        #expect(sky.cloudLayers[0].alphas?.night == 0.2)
        #expect(sky.cloudLayers[1].isDisabled)
        #expect(sky.precipitation == FormID(0x10))
        #expect(sky.visualEffect == nil)
        #expect(sky.sounds == [WeatherSound(sound: FormID(0x20), type: 2)])
        #expect(sky.imageSpaces?.night == FormID(0x43))
        #expect(sky.volumetricLighting?.day == nil)
        #expect(sky.sunGlare?.night == SIMD4(13, 14, 15, 16))
        #expect(weather.data == nil)
        #expect(weather.skipped.counts[.mismatch("WTHR DATA has an unknown size")] == 1)
        #expect(WeatherSky.cloudLayerIndex("@0TX") == 16)
        #expect(WeatherSky.cloudLayerIndex("P0TX") == nil)
    }

    @Test func decodesCellExtrasAndTalliesUnknownField() throws {
        let cell = try Cell(record: Fixture.record("CELL", fields: [
            ("DATA", Fixture.u16(1)), ("XCIM", Fixture.u32(0x10)), ("XILL", Fixture.u32(0x11)),
            ("XCCM", Fixture.u32(0x12)), ("XWEM", Fixture.zstring("env.dds")),
            ("XWCN", Fixture.u32(1)), ("XWCU", Fixture.f32(1, 2, 3, 0)),
            ("TVDT", Data(count: 8)), ("ZZZZ", Data())
        ]), localized: false)
        #expect(cell.extras.imageSpace == FormID(0x10))
        #expect(cell.extras.lockList == FormID(0x11))
        #expect(cell.extras.skyRegion == FormID(0x12))
        #expect(cell.extras.waterVelocities.first?.velocity == SIMD3(1, 2, 3))
        #expect(cell.extras.occlusionData?.count == 8)
        #expect(cell.skipped.counts[.unknownField("ZZZZ")] == 1)
    }

    @Test func decodesRaceSectionsBySex() throws {
        let record = try Fixture.record("RACE", fields: Self.raceFields)
        let race = try Race(record: record, localized: false)
        let details = race.details
        #expect(details.properties?.size == 1)
        #expect(details.properties?.mountOffsets == nil)
        #expect(details.skeletons.male?.path == "male.nif")
        #expect(details.skeletons.female?.textureHashes?.count == 12)
        #expect(details.attacks.map(\.event) == ["attackStart", "bashStart"])
        #expect(details.bodyParts.male.map(\.index) == [0, 1])
        #expect(details.bodyParts.male[1].model?.path == "lower.nif")
        #expect(details.bipedObjectNames == ["Head"])
        #expect(details.movementTypes.first?.overrides.count == 11)
        #expect(details.headData.female.headParts.map(\.part) == [FormID(0x70)])
        #expect(details.headData.female.tintMasks.first?.presets.first?.defaultValue == 0.5)
        #expect(details.headData.male.presets == [FormID(0x71)])
        #expect(details.armorRace == FormID(0x72))
        #expect(race.skipped.isEmpty, "\(race.skipped.ranked)")
    }

    @Test func decodesActorFaceDataInventoryAndDestruction() throws {
        let actor = try ActorBase(record: Fixture.record("NPC_", fields: [
            ("ACBS", Data(count: 24)), ("RNAM", Fixture.u32(0x10)), ("DATA", Data()),
            ("DEST", Fixture.i32(100) + Fixture.u8(1, 1, 0, 0)),
            (
                "DSTD",
                Fixture.u8(50, 0, 1, 0x04) + Fixture.i32(0) + Fixture.u32(0x20, 0)
                    + Fixture.i32(0)
            ),
            ("DMDL", Fixture.zstring("broken.nif")), ("DSTF", Data()),
            ("COCT", Fixture.u32(2)), ("CNTO", Fixture.u32(0x30) + Fixture.i32(3)),
            ("COED", Fixture.u32(0x31, 0) + Fixture.f32(1)),
            ("ZNAM", Fixture.u32(0x40)), ("NAM6", Fixture.f32(1.02)),
            ("QNAM", Fixture.f32(0.5, 0.4, 0.3)),
            ("NAM9", Fixture.f32(Array(repeating: 0.1, count: 19) as [Float])),
            ("NAMA", Fixture.i32(1, -1, 2, 3)),
            ("TINI", Fixture.u16(7)), ("TINC", Fixture.u8(1, 2, 3, 0)), ("TINV", Fixture.u32(50)),
            ("TIAS", Fixture.u16(0xFFFF)),
            ("CSDT", Fixture.u32(0)), ("CSDI", Fixture.u32(0x50)), ("CSDC", Fixture.u8(80))
        ]), localized: false)
        let details = actor.details
        #expect(details.destructible?.stages.first?.explosion == FormID(0x20))
        #expect(details.destructible?.stages.first?.model?.path == "broken.nif")
        #expect(details.destructible?.stages.first?.isClosed == true)
        #expect(details.inventory.first?.owner == FormID(0x31))
        #expect(details.combatStyle == FormID(0x40))
        #expect(details.faceMorphs.count == 19)
        #expect(details.faceParts == [1, -1, 2, 3])
        #expect(details.tintLayers.first?.preset == -1)
        #expect(details.soundTypes.first?.entries.first?.chance == 80)
        #expect(actor.skipped.counts[.mismatch("COCT differs from the CNTO count")] == 1)
    }

    @Test func decodesWorldspaceMapAndLargeReferences() throws {
        let world = try Worldspace(record: Fixture.record("WRLD", fields: [
            (
                "RNAM",
                Fixture.u16(2, 0xFFFF) + Fixture.u32(1) + Fixture.u32(0x10)
                    + Fixture.u16(2, 3)
            ),
            (
                "MNAM",
                Fixture.i32(1024, 768) + Fixture.u16(0xFFE0, 32, 32, 0xFFE0)
                    + Fixture.f32(50000, 80000, 50)
            ),
            ("ONAM", Fixture.f32(2, 1, 2, 3)),
            ("NAM0", Fixture.f32(-4096, -8192)), ("NAM9", Fixture.f32(4096, 8192))
        ]), localized: false)
        let details = world.details
        #expect(details.largeReferences.first?.cell == SIMD2(-1, 2))
        #expect(details.largeReferences.first?.references.first?.cell == SIMD2(3, 2))
        #expect(details.map?.northWestCell == SIMD2(-32, 32))
        #expect(details.map?.cameraInitialPitch == 50)
        #expect(details.mapOffset?.scale == 2)
        #expect(details.boundsMax == SIMD2(4096, 8192))
        #expect(world.skipped.isEmpty)
    }

    @Test func modelHashesBelongOnlyToTheModelTheyFollow() throws {
        var fields = try RecordFields(record: Fixture.record("STAT", fields: [
            ("MODT", Data(count: 4)), ("MODL", Fixture.zstring("a.nif")), ("EDID", Data()),
            ("MODT", Data(count: 12))
        ]), type: "STAT")
        let model = fields.model()
        #expect(model?.path == "a.nif")
        #expect(model?.textureHashes == nil)
        #expect(fields.finish().total == 3)
    }

    @Test func registryCoversEveryDecodedTypeAndRejectsUnknownTypes() throws {
        #expect(RecordDecoders.decodedTypes.count >= 119)
        let value = try RecordDecoders.decode(Fixture.record("HAZD", fields: []), localized: false)
        #expect(value is Hazard)
        #expect(throws: ESMError.self) {
            _ = try RecordDecoders.decode(Fixture.record("ZZZZ", fields: []), localized: false)
        }
    }

    private static let raceFields: [(String, Data)] = {
        var data = Data(count: 0x40) + Fixture.u32(1) + Data(count: 0x7C - 0x44) + Fixture.u32(0)
        data = data.prefix(0x80)
        return [
            ("DATA", data),
            ("MNAM", Data()), ("ANAM", Fixture.zstring("male.nif")),
            ("FNAM", Data()), ("ANAM", Fixture.zstring("female.nif")), ("MODT", Data(count: 12)),
            ("NAM2", Data()),
            ("ATKD", Data(count: 44)), ("ATKE", Fixture.zstring("attackStart")),
            ("ATKE", Fixture.zstring("bashStart")),
            ("NAM1", Data()), ("MNAM", Data()),
            ("INDX", Fixture.u32(0)), ("MODL", Fixture.zstring("upper.nif")),
            ("INDX", Fixture.u32(1)), ("MODL", Fixture.zstring("lower.nif")),
            ("FNAM", Data()), ("NAM2", Data()), ("NAM3", Data()),
            ("MNAM", Data()), ("MODL", Fixture.zstring("male.hkx")),
            ("NAME", Fixture.zstring("Head")),
            ("MTYP", Fixture.u32(0x60)),
            ("SPED", Fixture.f32(Array(repeating: 1, count: 11) as [Float])),
            ("NAM0", Data()), ("MNAM", Data()), ("RPRM", Fixture.u32(0x71)),
            ("NAM0", Data()), ("FNAM", Data()),
            ("INDX", Fixture.u32(0)), ("HEAD", Fixture.u32(0x70)),
            ("TINI", Fixture.u16(1)), ("TINT", Fixture.zstring("mask.dds")),
            ("TINP", Fixture.u16(6)),
            ("TINC", Fixture.u32(0x73)), ("TINV", Fixture.f32(0.5)), ("TIRS", Fixture.u16(2)),
            ("RNAM", Fixture.u32(0x72))
        ]
    }()
}
