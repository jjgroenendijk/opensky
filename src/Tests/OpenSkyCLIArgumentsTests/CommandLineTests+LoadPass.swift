// The parse of `load-pass`, which tools/probe.sh runs.

import OpenSkyCLIArguments
import Testing

extension CommandLineTests {
    @Test func loadPassTakesItsSwitches() throws {
        let pass = try command(
            [
                "load-pass",
                "--scene",
                "dragonsreach",
                "--runs",
                "3",
                "--serial",
                "--asset-cache",
                "--evict",
                "--off",
                "parallelRecords,prebuildIndexes"
            ],
            as: LoadPassArguments.self
        )
        #expect(pass.scene == "dragonsreach" && pass.runs == 3)
        #expect(pass.serial && pass.assetCache && pass.evict)
        #expect(pass.off?.items == ["parallelRecords", "prebuildIndexes"])
        #expect(try command(["load-pass"], as: LoadPassArguments.self).scene == "whiterun")
        #expect(exitCode(["load-pass", "--runs", "0"]) == OpenSkyCommandLine.usageExitCode)
    }
}
