// The paired-animation command and read, parsed with no socket and no game.

import OpenSkyAgentControl
import Testing

struct AgentPairedCommandTests {
    @Test func pairedNamesTheLeadTheTargetAndTheIdle() throws {
        let request = try AgentCommandLine.request(
            ["debug", "paired", "player", "1A2B", "1HMKillMoveC"]
        )
        let args = AgentArguments(command: "test", values: request.args)
        #expect(try AgentDebugCommand.parse("paired", args)
            == .paired(reference: "player", target: "1A2B", idle: "1HMKillMoveC"))
        let none = AgentArguments(command: "test", values: [:])
        #expect(try AgentStateQuery.parse("paired", none) == .paired)
    }
}
