// The trap record views in the Asset Browser and reference inspector: `HAZD`
// numbers, a `PHZD` with its enable parent, and a `REFR` lock.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyPreview
import Testing

struct RecordTextDumpTrapsTests {
    private typealias Fixture = ESMFixture

    @Test func dumpsHazardNumbers() throws {
        let dump = try RecordTextDump.dump(record: Fixture.record("HAZD", fields: [
            ("EDID", Fixture.zstring("FireHazard")),
            (
                "DATA",
                Fixture.u32(5) + Fixture.f32(128, 30, 256, 0.5)
                    + Fixture.u32(0x01) + Fixture.u32(0x100, 0, 0, 0)
            )
        ]), localized: false)
        #expect(dump.contains(
            "decoded HAZD: editorID FireHazard, spell 00000100, radius 128.0, "
                + "lifetime 30.0, target interval 0.5, limit 5, player only true"
        ))
    }

    @Test func dumpsPlacedHazardWithItsEnableParent() throws {
        let dump = try RecordTextDump.dump(record: Fixture.record("PHZD", fields: [
            ("NAME", Fixture.u32(0x900)),
            ("XESP", Fixture.u32(0x901) + Fixture.u8(1, 0, 0, 0)),
            ("DATA", Fixture.f32(1, 2, 3, 0, 0, 0))
        ]), localized: false)
        #expect(dump.contains("decoded PHZD: hazard 00000900, position (1.0, 2.0, 3.0)"))
        #expect(dump.contains("enable parent 00000901 (opposite)"))
    }

    @Test func dumpsReferenceLock() throws {
        let dump = try RecordTextDump.dump(record: Fixture.record("REFR", fields: [
            ("NAME", Fixture.u32(0x10)),
            (
                "XLOC",
                Fixture.u8(50, 0, 0, 0) + Fixture.u32(0x77) + Fixture.u8(0, 0, 0, 0)
                    + Fixture.u32(0, 0)
            ),
            ("DATA", Fixture.f32(0, 0, 0, 0, 0, 0))
        ]), localized: false)
        #expect(dump.contains(", lock level 50 key 00000077"))
    }
}
