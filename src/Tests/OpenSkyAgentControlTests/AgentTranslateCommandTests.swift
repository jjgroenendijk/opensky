// The translate command, parsed with no socket and no game.

import OpenSkyAgentControl
import Testing

struct AgentTranslateCommandTests {
    private static func parse(_ words: [String]) throws -> AgentDebugCommand {
        let request = try AgentCommandLine.request(words)
        return try AgentDebugCommand.parse(
            "translate", AgentArguments(command: "test", values: request.args)
        )
    }

    @Test func translateNamesTheReferenceTheTargetAndTheSpeed() throws {
        #expect(try Self.parse(["debug", "translate", "1A2B", "1,2,-3", "50"])
            == .translate(reference: "1A2B", position: SIMD3(1, 2, -3), speed: 50))
        #expect(try Self.parse(["debug", "translate", "1A2B", "1,2,3"])
            == .translate(reference: "1A2B", position: SIMD3(1, 2, 3), speed: 100))
    }

    @Test func aSpeedThatIsNotAboveZeroIsRefused() {
        #expect(throws: AgentFailure.self) {
            try Self.parse(["debug", "translate", "1A2B", "1,2,3", "0"])
        }
    }
}
