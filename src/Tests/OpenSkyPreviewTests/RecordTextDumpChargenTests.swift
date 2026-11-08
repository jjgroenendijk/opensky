// The chargen and map record views in the Asset Browser: NPC face data, race
// chargen data, and a map marker on a reference.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyPreview
import Testing

struct RecordTextDumpChargenTests {
    private typealias Fixture = ESMFixture

    @Test func dumpsFaceMorphsPartsAndTints() throws {
        var morphs = [Float](repeating: 0, count: 19)
        morphs[2] = 0.5
        let dump = try RecordTextDump.dump(record: Fixture.record("NPC_", fields: [
            ("ACBS", Data(count: 24)),
            ("NAM7", Fixture.f32(40)),
            ("NAM9", Fixture.f32(morphs)),
            ("NAMA", Fixture.i32(1, -1, 3, 4)),
            ("TINI", Fixture.u16(7)),
            ("TINV", Fixture.u32(80))
        ]), localized: false)
        #expect(dump.contains("decoded NPC_ face: weight 40.0, 0 head parts"))
        #expect(dump.contains("  morphs: 2=0.50"))
        #expect(dump.contains("  parts: 1 -1 3 4"))
        #expect(dump.contains("  tints: 7@80"))
    }

    @Test func dumpsRaceChargenCounts() throws {
        let dump = try RecordTextDump.dump(record: Fixture.record("RACE", fields: [
            ("EDID", Fixture.zstring("NordRace"))
        ]), localized: false)
        #expect(dump.contains("decoded RACE chargen: NordRace, not playable"))
        #expect(dump.contains("  male: 0 presets"))
    }

    @Test func dumpsTheMarkerOnAReference() throws {
        let dump = try RecordTextDump.dump(record: Fixture.record("REFR", fields: [
            ("NAME", Fixture.u32(0x10)),
            ("XMRK", Data()),
            ("FNAM", Fixture.u8(0x03)),
            ("TNAM", Fixture.u8(2, 0)),
            ("DATA", Fixture.f32(0, 0, 0, 0, 0, 0))
        ]), localized: false)
        #expect(dump.contains("\n  marker: type Town, visible, travel"))
    }
}
