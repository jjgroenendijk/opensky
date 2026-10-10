// The xEdit-named fields of world records that no game system reads yet.
// Synthetic records only. Layout: docs/formats/world-records.md.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct WorldRecordDetailTests {
    private typealias Fixture = RecordDetailFixture

    @Test func waterReadsEveryDetailField() throws {
        var fields = Fixture.string("FULL", "Lake")
        fields += Fixture.string("NNAM", "a.dds") + Fixture.string("NNAM", "b.dds")
        fields += ESMFixture.field("ANAM", Data([40]))
        fields += ESMFixture.field("FNAM", Data([0x09]))
        fields += ESMFixture.field("MNAM", Data([7]))
        fields += Fixture.formIDs(["TNAM", "SNAM", "XNAM", "INAM"], from: 0x10)
        fields += ESMFixture.field("DATA", Data([3, 0]))
        fields += ESMFixture.field("GNAM", Fixture.uint32(0x20) + Fixture.uint32(0x21))
        fields += ESMFixture.field("NAM0", Fixture.floats(1, 2, 3))
        fields += ESMFixture.field("NAM1", Fixture.floats(4, 5, 6))
        fields += Fixture.string("NAM2", "n2.dds") + Fixture.string("NAM5", "flow.dds")
        let water = try WaterType(record: Fixture.record("WATR", fields), localized: false)
        let details = water.details
        #expect(water.skipped.isEmpty)
        #expect(details.name == .inline("Lake"))
        #expect(details.oldNoiseTextures == ["a.dds", "b.dds"])
        #expect(details.opacity == 40)
        #expect(details.flags == 0x09)
        #expect(details.unusedMaterialID == Data([7]))
        #expect([details.material, details.openSound, details.spell, details.imageSpace]
            == Fixture.expectedIDs(4, from: 0x10))
        #expect(details.damagePerSecond == 3)
        #expect(details.relatedWaters == [FormID(0x20), FormID(0x21)])
        #expect(details.linearVelocity == SIMD3(1, 2, 3))
        #expect(details.angularVelocity == SIMD3(4, 5, 6))
        #expect(details.noiseTextures == ["n2.dds", nil, nil, "flow.dds"])
    }

    @Test func impactReadsEffectDecalAndLinks() throws {
        var data = Fixture.floats(0.5)
        data.appendUInt32(2)
        data += Fixture.floats(15, 8)
        data.appendUInt32(1)
        data += Data([1, 4, 0, 0])
        var fields = ESMFixture.field("DATA", data)
        fields += Fixture.string("MODL", "hit.nif")
        fields += Fixture.decalField()
        fields += Fixture.formIDs(["DNAM", "ENAM", "NAM2"], from: 0x10)
        let impact = try Impact(record: Fixture.record("IPCT", fields))
        #expect(impact.skipped.isEmpty)
        #expect(impact.model?.path == "hit.nif")
        let effect = try #require(impact.effect)
        #expect([effect.duration, effect.angleThreshold, effect.placementRadius] == [0.5, 15, 8])
        #expect(effect.orientation == 2)
        #expect(effect.soundLevel == 1)
        #expect(effect.flags == 1)
        #expect(effect.result == 4)
        #expect([impact.textureSet, impact.secondaryTextureSet, impact.hazard]
            == Fixture.expectedIDs(3, from: 0x10))
        try Self.expectFixtureDecal(impact.decal)
    }

    @Test func textureSetReadsSlotsDecalAndFlags() throws {
        var fields = Fixture.boundsField()
        fields += Fixture.string("TX00", "d.dds") + Fixture.string("TX02", "e.dds")
        fields += Fixture.decalField()
        fields += ESMFixture.field("DNAM", Data([0x07, 0]))
        let set = try TextureSet(record: Fixture.record("TXST", fields))
        #expect(set.skipped.isEmpty)
        #expect(Fixture.isFixtureBounds(set.bounds))
        #expect(set.paths.prefix(3) == ["d.dds", nil, "e.dds"])
        #expect(set.flags.contains(.noSpecularMap))
        #expect(set.flags.contains(.faceGenTextures))
        #expect(set.flags.contains(.modelSpaceNormalMap))
        try Self.expectFixtureDecal(set.decal)
    }

    @Test func staticReadsBoundsAndMaterialAngle() throws {
        var dnam = Fixture.floats(90)
        dnam.appendUInt32(0x70)
        var fields = Fixture.boundsField()
        fields += ESMFixture.field("DNAM", dnam)
        let stat = try StaticObject(record: Fixture.record("STAT", fields))
        #expect(Fixture.isFixtureBounds(stat.bounds))
        #expect(stat.directionalMaterial?.maxAngle == 90)
    }

    @Test func skyGrassAndMovementReadTheirExtras() throws {
        let hashes = ESMFixture.field("MODT", Data([9]))
        let climate = try Climate(record: Fixture.record("CLMT", hashes))
        #expect(climate.nightSkyTextureHashes == Data([9]))
        #expect(climate.skipped.isEmpty)
        let grass = try Grass(record: Fixture.record("GRAS", Fixture.boundsField() + hashes))
        #expect(Fixture.isFixtureBounds(grass.bounds))
        #expect(grass.modelTextureHashes == Data([9]))
        #expect(grass.skipped.isEmpty)
        let inam = ESMFixture.field("INAM", Fixture.floats(1, 2, 3))
        let movement = try MovementType(record: Fixture.record("MOVT", inam))
        #expect(movement.animChangeThresholds == SIMD3(1, 2, 3))
        #expect(movement.skipped.isEmpty)
        let space = try AcousticSpace(record: Fixture.record("ASPC", Fixture.boundsField()))
        #expect(Fixture.isFixtureBounds(space.bounds))
        #expect(space.skipped.isEmpty)
    }

    @Test func surfaceMaterialsReadHavokAndFlags() throws {
        var fields = ESMFixture.field("HNAM", Data([30, 40]))
        fields += ESMFixture.field("SNAM", Data([12]))
        fields += ESMFixture.field("INAM", Fixture.uint32(1))
        let texture = try LandTexture(record: Fixture.record("LTEX", fields))
        #expect(texture.havokFriction == 30)
        #expect(texture.havokRestitution == 40)
        #expect(texture.specularExponent == 12)
        #expect(texture.isSnow)
        #expect(texture.skipped.isEmpty)
        var matt = ESMFixture.field("CNAM", Fixture.floats(0.25, 0.5, 1))
        matt += ESMFixture.field("BNAM", Fixture.floats(2))
        matt += ESMFixture.field("FNAM", Fixture.uint32(3))
        let material = try MaterialType(record: Fixture.record("MATT", matt))
        #expect(material.havokDisplayColor == SIMD3(0.25, 0.5, 1))
        #expect(material.buoyancy == 2)
        #expect(material.flags == 3)
        #expect(material.skipped.isEmpty)
    }

    @Test func navmeshReadsCutsAndConnectors() throws {
        var fields = ESMFixture.field("NVNM", NavmeshFixture.twoTriangleMesh())
        fields += ESMFixture.field("ONAM", Fixture.uint32(0x10))
        fields += ESMFixture.field("PNAM", Data([1, 0, 2, 0]))
        fields += ESMFixture.field("NNAM", Data([3, 0]))
        let navmesh = try Navmesh(record: Fixture.record("NAVM", fields))
        #expect(navmesh.skipped.isEmpty)
        #expect(navmesh.baseObjects == [FormID(0x10)])
        #expect(navmesh.preferredConnectors == [1, 2])
        #expect(navmesh.nonConnectors == [3])
    }

    @Test func regionReadsAreasMapNameIconAndObjects() throws {
        var fields = ESMFixture.field("RPLI", Fixture.uint32(5))
        fields += ESMFixture.field("RPLD", Fixture.floats(1, 2, 3, 4))
        fields += Fixture.string("RDMP", "Whiterun Hold")
        fields += Fixture.string("ICON", "region.dds")
        fields += ESMFixture.field("RDOT", Data([8]))
        let region = try Region(record: Fixture.record("REGN", fields))
        #expect(region.skipped.isEmpty)
        #expect(region.areas.map(\.edgeFalloff) == [5])
        #expect(region.areas.first?.points == [SIMD2(1, 2), SIMD2(3, 4)])
        #expect(region.mapName == .inline("Whiterun Hold"))
        #expect(region.iconPath == "region.dds")
        #expect(region.objectData == [Data([8])])
    }

    private static func expectFixtureDecal(_ decal: DecalData?) throws {
        let decal = try #require(decal)
        #expect([
            decal.minWidth,
            decal.maxWidth,
            decal.minHeight,
            decal.maxHeight,
            decal.depth,
            decal.shininess,
            decal.parallaxScale
        ] == [1, 2, 3, 4, 5, 6, 7])
        #expect(decal.parallaxPasses == 3)
        #expect(decal.flags == [.parallax, .alphaTesting])
        #expect(!decal.flags.contains(.alphaBlending))
        #expect(!decal.flags.contains(.noSubtextures))
        #expect(decal.color == SIMD3(10, 20, 30))
    }
}
