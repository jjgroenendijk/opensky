// The record commands keep their filters, fields, and output choices.

import OpenSkyCLIArguments
import Testing

extension CommandLineTests {
    @Test func recordFindTakesFiltersAndFields() throws {
        let find = try command(
            [
                "record", "find", "--type", "WEAP", "--where", "keywords=WeapTypeDagger",
                "--where", "data.damage>5", "--fields", "editorID,data.damage", "--limit", "3"
            ],
            as: RecordArguments.Find.self
        )
        #expect(find.type == "WEAP")
        #expect(find.filters == ["keywords=WeapTypeDagger", "data.damage>5"])
        #expect(find.fields?.items == ["editorID", "data.damage"])
        #expect(find.limit == 3)
        #expect(exitCode(["record", "find", "--type", "WEAPON"]) == OpenSkyCommandLine
            .usageExitCode)
        #expect(exitCode(["record", "find", "--type", "WEAP", "--count", "--json"])
            == OpenSkyCommandLine.usageExitCode)
    }

    @Test func recordShowWritesAFileUnlessToldToPrint() throws {
        let show = try command(["record", "show", "0x3C"], as: RecordArguments.Show.self)
        #expect(show.out == nil)
        #expect(!show.print)
        let named = try command(
            ["record", "show", "0x3C", "--out", "a.txt"], as: RecordArguments.Show.self
        )
        #expect(named.out == "a.txt")
        let printed = try command(
            ["record", "show", "0x3C", "--print"],
            as: RecordArguments.Show.self
        )
        #expect(printed.print)
        #expect(exitCode(["record", "show", "0x3C", "--out", "a.txt", "--print"])
            == OpenSkyCommandLine.usageExitCode)
    }
}
