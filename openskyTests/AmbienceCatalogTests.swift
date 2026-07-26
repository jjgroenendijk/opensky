// AmbienceCatalog bed resolution over synthetic Region + ASPC inputs. Pure
// value logic; no engine, no file system. Source: docs/engine/world-sfx.md
// and docs/formats/acoustic-space.md.

import Foundation
@testable import opensky
import Testing

struct AmbienceCatalogTests {
    @Test func exteriorResolvesFromEachRegionSoundArea() {
        let weather = makeWeatherStore(regions: [
            RegionFixture(id: 0x100, sounds: [
                SoundFixture(sound: 0xAAA, flags: 0x01, chance: 0.5),
                SoundFixture(sound: 0xAAB, flags: 0x0F, chance: 1.0)
            ]),
            RegionFixture(id: 0x101, sounds: [
                SoundFixture(sound: 0xBBA, flags: 0x02, chance: 0.25)
            ])
        ])

        let bed = AmbienceBed.resolve(
            context: AmbienceContext(
                regions: [FormID(0x100), FormID(0x101)],
                acousticSpace: nil,
                isInterior: false
            ),
            weatherStore: weather,
            aspcStore: nil
        )

        #expect(bed.entries.map(\.sound) == [FormID(0xAAA), FormID(0xAAB), FormID(0xBBA)])
    }

    @Test func exteriorEmptyWhenNoRegions() {
        let bed = AmbienceBed.resolve(
            context: AmbienceContext.empty,
            weatherStore: nil,
            aspcStore: nil
        )
        #expect(bed.entries.isEmpty)
    }

    @Test func exteriorSkipsUnknownRegions() {
        let weather = makeWeatherStore(regions: [
            RegionFixture(id: 0x100, sounds: [SoundFixture(sound: 0xAAA, flags: 0, chance: 1)])
        ])
        let bed = AmbienceBed.resolve(
            context: AmbienceContext(
                regions: [FormID(0x100), FormID(0x999)],
                acousticSpace: nil,
                isInterior: false
            ),
            weatherStore: weather,
            aspcStore: nil
        )
        #expect(bed.entries.map(\.sound) == [FormID(0xAAA)])
    }

    @Test func interiorResolvesAspcDirectPlusBorrowedRegion() {
        let weather = makeWeatherStore(regions: [
            RegionFixture(id: 0x200, sounds: [SoundFixture(sound: 0xCCC, flags: 0, chance: 1)])
        ])
        let aspcStore = makeAspcStore(spaces: [
            AspcFixture(id: 0x300, ambient: 0xBBB, borrowed: 0x200, reverb: nil)
        ])

        let bed = AmbienceBed.resolve(
            context: AmbienceContext(
                regions: [],
                acousticSpace: FormID(0x300),
                isInterior: true
            ),
            weatherStore: weather,
            aspcStore: aspcStore
        )

        // Direct SNAM first, then borrowed region's RDSA entries.
        #expect(bed.entries.map(\.sound) == [FormID(0xBBB), FormID(0xCCC)])
    }

    @Test func interiorEmptyWhenAspcAbsent() {
        let bed = AmbienceBed.resolve(
            context: AmbienceContext(
                regions: [], acousticSpace: FormID(0x999), isInterior: true
            ),
            weatherStore: nil,
            aspcStore: makeAspcStore(spaces: [])
        )
        #expect(bed.entries.isEmpty)
    }

    @Test func interiorEmptyWhenAspcHasNeitherDirectNorBorrow() {
        let aspcStore = makeAspcStore(spaces: [
            AspcFixture(id: 0x300, ambient: nil, borrowed: nil, reverb: nil)
        ])
        let bed = AmbienceBed.resolve(
            context: AmbienceContext(
                regions: [], acousticSpace: FormID(0x300), isInterior: true
            ),
            weatherStore: nil,
            aspcStore: aspcStore
        )
        #expect(bed.entries.isEmpty)
    }

    // MARK: - Synthetic store builders

    /// Synthetic region-fixture shape (id + RDSA sound entries) for exterior
    /// bed tests. Struct instead of a tuple to stay under the lint large-tuple
    /// cap.
    struct RegionFixture {
        let id: UInt32
        let sounds: [SoundFixture]
    }

    /// Synthetic RDSA entry: SNDR/SOUN FormID, weather-state flags, weight.
    struct SoundFixture {
        let sound: UInt32
        let flags: UInt32
        let chance: Float
    }

    /// Synthetic ASPC shape for the interior bed tests.
    struct AspcFixture {
        let id: UInt32
        let ambient: UInt32?
        let borrowed: UInt32?
        let reverb: UInt32?
    }

    private func makeWeatherStore(regions: [RegionFixture]) -> WeatherStore {
        var bytes = Data()
        for region in regions {
            bytes += ESMFixture.record("REGN", formID: region.id, data: regionFields(region))
        }
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup("REGN", contents: bytes)
        do {
            return try WeatherStore(file: ESMFile(data: plugin))
        } catch {
            preconditionFailure("synthetic fixture failed: \(error)")
        }
    }

    private func regionFields(_ region: RegionFixture) -> Data {
        var soundHeader = Data()
        soundHeader.appendUInt32(7) // type: sound
        soundHeader.append(contentsOf: [0x00, 1]) // flags, priority
        soundHeader.appendUInt16(0)

        var rdsa = Data()
        for entry in region.sounds {
            rdsa.appendUInt32(entry.sound)
            rdsa.appendUInt32(entry.flags)
            rdsa.appendUInt32(entry.chance.bitPattern)
        }

        var fields = ESMFixture.field("EDID", ESMFixture.zstring("Region\(region.id)"))
        fields += ESMFixture.field("RDAT", soundHeader)
        if !rdsa.isEmpty {
            fields += ESMFixture.field("RDSA", rdsa)
        }
        return fields
    }

    private func makeAspcStore(spaces: [AspcFixture]) -> AcousticSpaceStore {
        var bytes = Data()
        for aspc in spaces {
            var fields = ESMFixture.field("EDID", ESMFixture.zstring("Aspc\(aspc.id)"))
            if let ambient = aspc.ambient {
                fields += ESMFixture.field("SNAM", uint32(ambient))
            }
            if let borrowed = aspc.borrowed {
                fields += ESMFixture.field("RDAT", uint32(borrowed))
            }
            if let reverb = aspc.reverb {
                fields += ESMFixture.field("BNAM", uint32(reverb))
            }
            bytes += ESMFixture.record("ASPC", formID: aspc.id, data: fields)
        }
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup("ASPC", contents: bytes)
        do {
            return try AcousticSpaceStore(file: ESMFile(data: plugin))
        } catch {
            preconditionFailure("synthetic fixture failed: \(error)")
        }
    }

    private func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
