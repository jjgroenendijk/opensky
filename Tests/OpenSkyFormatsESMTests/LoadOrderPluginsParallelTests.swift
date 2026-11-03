// The load-order decode on every core must give the serial result: a later
// plugin wins, a failed override keeps the earlier record, and skips count once.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct LoadOrderPluginsParallelTests {
    private struct Broken: Error {}

    private func stat(_ formID: UInt32, _ editorID: String) -> Data {
        ESMFixture.record("STAT", formID: formID, data: ESMFixture.field(
            "EDID", ESMFixture.zstring(editorID)
        ))
    }

    /// Enough records for several work items; the mod edits, breaks, and adds records.
    private func loadOrder() throws -> LoadOrderPlugins {
        let base = (1 ... 300).map { stat(UInt32($0), "Rock\($0)") }.reduce(Data(), +)
        let mod = stat(0x10, "RockEdited") + stat(0x11, "Broken")
            + (0 ..< 100).map { stat(0x0100_0800 + UInt32($0), "New\($0)") }.reduce(Data(), +)
        let baseFile = try ESMFile(data: ESMFixture.tes4()
            + ESMFixture.topGroup("STAT", contents: base))
        let modFile = try ESMFile(data: ESMFixture.tes4(masters: ["Skyrim.esm"])
            + ESMFixture.topGroup("STAT", contents: mod))
        return LoadOrderPlugins([("Skyrim.esm", baseFile), ("Mod.esp", modFile)])
    }

    private static func editorID(_ record: ESMRecord) throws -> String? {
        let id = ESMWalk.editorID(of: record)
        if id == "Broken" {
            throw Broken()
        }
        return id
    }

    @Test func parallelDecodeMatchesTheSerialOne() throws {
        let plugins = try loadOrder()
        var serialSkips = SkippedRecords()
        let serial = plugins.indexRecords(of: "STAT", skipped: &serialSkips) {
            try Self.editorID($0)
        }
        var parallelSkips = SkippedRecords()
        let parallel = plugins.indexRecordsInParallel(of: "STAT", skipped: &parallelSkips) {
            try Self.editorID($0)
        }
        #expect(parallel == serial)
        #expect(parallel.count == 400)
        #expect(parallel[0x10] == "RockEdited")
        #expect(parallel[0x11] == "Rock17")
        #expect(parallelSkips.count(of: "STAT") == 1)
        #expect(parallelSkips == serialSkips)
    }
}
