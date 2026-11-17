// The parse of `collision --column`, which tools/probe.sh runs.

import OpenSkyCLIArguments
import Testing

extension CommandLineTests {
    @Test func collisionTakesAColumnAsTwoNumbers() throws {
        let probe = try command(
            ["collision", "--x", "-25", "--y", "20", "--column", "-100352,83968.5"],
            as: CollisionArguments.self
        )
        #expect(probe.column == MapPoint(x: -100_352, y: 83968.5))
        #expect(exitCode(["collision", "--column", "1"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["collision", "--column", "1,b"]) == OpenSkyCommandLine.usageExitCode)
    }
}
