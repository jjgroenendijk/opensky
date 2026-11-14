// `debug newgame` and `state newgame`, parsed with no socket and no game.

import OpenSkyAgentControl
import Testing

struct AgentNewGameCommandTests {
    private func arguments(_ words: [String]) throws -> AgentArguments {
        try AgentArguments(command: "test", values: AgentCommandLine.request(words).args)
    }

    @Test func newGameTakesAStartAndItsOptions() throws {
        let args = try arguments([
            "debug", "newgame", "--at", "cell:QASmoke", "--hour", "9", "--weather", "SkyrimClear",
            "--story", "helgen-hadvar", "--items", "warrior", "--no-racemenu"
        ])
        let request = AgentNewGameRequest(
            start: "cell:QASmoke", hour: 9, weather: "SkyrimClear", story: "helgen-hadvar",
            items: "warrior", opensRaceMenu: false
        )
        #expect(try AgentDebugCommand.parse("newgame", args) == .newGame(request))
        #expect(request.json == [
            "start": "cell:QASmoke", "hour": .init(Float(9)), "weather": "SkyrimClear",
            "story": "helgen-hadvar", "items": "warrior", "raceMenu": false
        ])
    }

    @Test func theOptionsHaveDefaults() throws {
        let args = try arguments(["debug", "newgame", "--at", "exterior:Tamriel:6:-2"])
        let request = AgentNewGameRequest(start: "exterior:Tamriel:6:-2")
        #expect(try AgentDebugCommand.parse("newgame", args) == .newGame(request))
        #expect(request.json == [
            "start": "exterior:Tamriel:6:-2", "hour": .null, "weather": .null,
            "story": "not-started", "items": "none", "raceMenu": true
        ])
    }

    @Test func aStartIsRequiredAndTheHourIsChecked() throws {
        #expect(throws: AgentFailure.self) {
            try AgentDebugCommand.parse("newgame", arguments(["debug", "newgame"]))
        }
        #expect(throws: AgentFailure.self) {
            try AgentDebugCommand.parse(
                "newgame", arguments(["debug", "newgame", "--at", "cell:QASmoke", "--hour", "30"])
            )
        }
    }

    @Test func theStateReadParses() throws {
        #expect(try AgentStateQuery.parse("newgame", arguments(["state", "newgame"])) == .newGame)
    }
}
