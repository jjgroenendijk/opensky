// The assembled head's part set over synthetic HDPT, FLST, TXST, and CLFM
// records: overrides by type, extra parts, the race filter, and colors.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyWorld
import Testing

struct HeadPartResolverTests {
    private static let nord = FormID(0x13746)
    private static let elf = FormID(0x13749)

    private static func part(
        _ formID: UInt32,
        type: UInt32,
        model: String? = "part.nif",
        extras: [UInt32] = [],
        fields: [(String, Data)] = []
    ) throws -> HeadPart {
        var all = [("EDID", ESMFixture.zstring("Part\(formID)")), ("PNAM", ESMFixture.u32(type))]
        if let model {
            all.append(("MODL", ESMFixture.zstring(model)))
        }
        all += extras.map { ("HNAM", ESMFixture.u32($0)) } + fields
        return try HeadPart(record: ESMFixture.record("HDPT", formID: formID, fields: all))
    }

    private static func resolver(_ parts: [HeadPart]) throws -> HeadPartResolver {
        try HeadPartResolver(
            headParts: Dictionary(uniqueKeysWithValues: parts.map { ($0.formID.rawValue, $0) }),
            formLists: [0x50: FormList(record: FormListFixture.record(
                formID: 0x50, entries: [nord.rawValue]
            ))],
            textureSets: [0x60: TextureSet(record: ESMFixture.record("TXST", formID: 0x60, fields: [
                ("TX00", ESMFixture.zstring("hair_d.dds")), (
                    "TX01",
                    ESMFixture.zstring("hair_n.dds")
                )
            ]))],
            colors: [
                0x70: ColorForm(record: ESMFixture.record("CLFM", formID: 0x70, fields: [
                    ("CNAM", ESMFixture.u8(255, 0, 0, 0))
                ]), localized: false),
                0x71: ColorForm(record: ESMFixture.record("CLFM", formID: 0x71, fields: [
                    ("CNAM", ESMFixture.u8(0, 0, 255, 0))
                ]), localized: false)
            ]
        )
    }

    @Test func anNPCPartReplacesTheRaceDefaultOfItsType() throws {
        let resolver = try Self.resolver([
            Self.part(0x10, type: 1), Self.part(0x11, type: 3), Self.part(0x20, type: 3),
            Self.part(0x21, type: 0), Self.part(0x22, type: 0)
        ])
        let set = resolver.resolve(
            raceDefaults: [FormID(0x10), FormID(0x11)],
            npcParts: [FormID(0x20), FormID(0x21), FormID(0x22)],
            race: Self.nord, hairColor: nil
        )
        #expect(set.parts.map(\.formID.rawValue) == [0x10, 0x20, 0x21, 0x22])
        #expect(set.parts.map(\.origin) == [.raceDefault, .npcOverride, .npcOverride, .npcOverride])
        #expect(set.misses.isEmpty)
    }

    @Test func extraPartsComeAlongOnceEvenInALoop() throws {
        let resolver = try Self.resolver([
            Self.part(0x10, type: 3, extras: [0x11]),
            Self.part(0x11, type: 0, extras: [0x12]),
            Self.part(0x12, type: 0, extras: [0x10])
        ])
        let set = resolver.resolve(
            raceDefaults: [], npcParts: [FormID(0x10)], race: Self.nord, hairColor: nil
        )
        #expect(set.parts.map(\.formID.rawValue) == [0x10, 0x11, 0x12])
        #expect(set.parts.map(\.origin) == [.npcOverride, .extraPart, .extraPart])
        #expect(set.misses == [HeadPartMiss(formID: FormID(0x10), reason: .cycle)])
    }

    @Test func theRaceListFiltersAndAMissingPartDegrades() throws {
        let resolver = try Self.resolver([
            Self.part(0x10, type: 1),
            Self.part(0x20, type: 1, fields: [("RNAM", ESMFixture.u32(0x50))]),
            Self.part(0x30, type: 2, model: nil)
        ])
        let elfSet = resolver.resolve(
            raceDefaults: [FormID(0x10)], npcParts: [FormID(0x20), FormID(0x99), FormID(0x30)],
            race: Self.elf, hairColor: nil
        )
        #expect(elfSet.parts.map(\.formID.rawValue) == [0x10])
        #expect(elfSet.misses.map(\.reason) == [.wrongRace, .missingRecord, .noModel])
        let nordSet = resolver.resolve(
            raceDefaults: [FormID(0x10)], npcParts: [FormID(0x20)], race: Self.nord, hairColor: nil
        )
        #expect(nordSet.parts.map(\.formID.rawValue) == [0x20])
    }

    @Test func aPartWithoutAMeshCanGroupItsExtraParts() throws {
        let resolver = try Self.resolver([
            Self.part(0x10, type: 3, model: nil, extras: [0x11]),
            Self.part(0x11, type: 0)
        ])
        let set = resolver.resolve(
            raceDefaults: [], npcParts: [FormID(0x10)], race: Self.nord, hairColor: nil
        )
        #expect(set.parts.map(\.formID.rawValue) == [0x11])
        #expect(set.misses.isEmpty)
    }

    @Test func hairTakesTheNPCHairColorAndOtherPartsTheirOwn() throws {
        let resolver = try Self.resolver([
            Self.part(0x10, type: 3, fields: [
                ("TNAM", ESMFixture.u32(0x60)), ("CNAM", ESMFixture.u32(0x70))
            ]),
            Self.part(0x11, type: 5, fields: [("CNAM", ESMFixture.u32(0x70))])
        ])
        let set = resolver.resolve(
            raceDefaults: [], npcParts: [FormID(0x10), FormID(0x11)],
            race: Self.nord, hairColor: FormID(0x71)
        )
        #expect(set.parts.first?.tint == SIMD3(0, 0, 1))
        #expect(set.parts.first?.diffuseTexture == "hair_d.dds")
        #expect(set.parts.first?.normalTexture == "hair_n.dds")
        #expect(set.parts.last?.tint == SIMD3(1, 0, 0))
        #expect(set.parts.last?.diffuseTexture == nil)
    }
}
