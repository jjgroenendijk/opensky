// The sweep subcommands share their report options.

import OpenSkyCLIArguments
import Testing

extension CommandLineTests {
    @Test func sweepSubcommandsParseTheReportOptions() throws {
        let quests = try command(
            ["sweep", "quests", "--out", "run", "--limit", "5", "--examples", "2"],
            as: SweepArguments.Quests.self
        )
        #expect(quests.report.out == "run")
        #expect(quests.report.limit == 5)
        #expect(quests.report.examples == 2)
        let fragments = try command(["sweep", "fragments"], as: SweepArguments.Fragments.self)
        #expect(fragments.report.examples == 3)
        #expect(fragments.report.limit == nil)
        _ = try command(["sweep", "rules"], as: SweepArguments.Rules.self)
        #expect(exitCode(["sweep", "rules", "--examples", "0"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["sweep", "quests", "--limit", "0"]) == OpenSkyCommandLine.usageExitCode)
    }
}
