// The gaps command runs the asked sections in report order, and the fields section needs
// the lists make rank-gaps writes.

import OpenSkyCLIArguments
import Testing

extension CommandLineTests {
    @Test func gapsRunsTheAskedSectionsInReportOrder() throws {
        let all = try command(
            [
                "gaps", "--field-reads", "reads.tsv", "--value-reads", "values.tsv",
                "--shallow-handlers", "handlers.tsv"
            ],
            as: GapsArguments.self
        )
        #expect(all.sections == GapsArguments.sectionKeys)
        #expect(all.fieldReads == "reads.tsv")
        #expect(all.valueReads == "values.tsv")
        #expect(all.shallowHandlers == "handlers.tsv")
        let some = try command(
            ["gaps", "--only", "perks,Papyrus", "--limit", "5"],
            as: GapsArguments.self
        )
        #expect(some.sections == ["papyrus", "perks"])
        #expect(some.limit == 5)
        #expect(exitCode(["gaps", "--only", "dance"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["gaps", "--limit", "0"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["gaps"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["gaps", "--only", "fields"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["gaps", "--only", "enums"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["gaps", "--only", "shallow"]) == OpenSkyCommandLine.usageExitCode)
    }
}
