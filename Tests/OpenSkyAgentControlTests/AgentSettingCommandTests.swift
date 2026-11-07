// The debug setting command: a list of id=value pairs, or none to restore the saved ones.

import OpenSkyAgentControl
import Testing

struct AgentSettingCommandTests {
    private func parse(_ words: [String]) throws -> AgentDebugCommand {
        let request = try AgentCommandLine.request(words)
        return try AgentDebugCommand.parse(
            "setting", AgentArguments(command: "debug.setting", values: request.args)
        )
    }

    @Test func settingTakesAListOrNone() throws {
        #expect(try parse(["debug", "setting", "rendering.indirectLight=on,graphics.bSAOEnable=0"])
            == .settings(["rendering.indirectLight=on", "graphics.bSAOEnable=0"]))
        #expect(try parse(["debug", "setting"]) == .settings([]))
    }
}
