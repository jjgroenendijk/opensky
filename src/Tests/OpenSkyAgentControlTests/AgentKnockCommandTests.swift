// The knock commands and the impulses state topic, as scripts type them.

import Foundation
import OpenSkyAgentControl
import Testing

struct AgentKnockCommandTests {
    private func args(_ values: [String: AgentJSON], _ command: String = "test") -> AgentArguments {
        AgentArguments(command: command, values: values)
    }

    @Test func knockNamesTheActorAndTheDamage() throws {
        let request = try AgentCommandLine.request(["debug", "knock", "1A2B", "30"])
        #expect(try AgentDebugCommand.parse("knock", args(request.args))
            == .knock(reference: "1A2B", damage: 30))
        #expect(throws: AgentFailure.self) {
            try AgentDebugCommand.parse("knock", args(["ref": "player", "damage": -1]))
        }
        #expect(try AgentStateQuery.parse("impulses", args([:])) == .impulses)
    }

    @Test func knockdownNamesTheActorAndAnOptionalMagnitude() throws {
        let request = try AgentCommandLine.request(["debug", "knockdown", "1A2B", "-4"])
        #expect(try AgentDebugCommand.parse("knockdown", args(request.args))
            == .knockdown(reference: "1A2B", magnitude: -4))
        #expect(try AgentDebugCommand.parse("knockdown", args(["ref": "player"]))
            == .knockdown(reference: "player", magnitude: 10))
        #expect(throws: AgentFailure.self) {
            try AgentDebugCommand.parse("knockdown", args(["ref": "player", "magnitude": 0]))
        }
    }
}
