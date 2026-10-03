// `openskycli game` words to requests, and results to `--text` lines.

import OpenSkyAgentControl
import Testing

struct AgentCommandLineTests {
    @Test func groupedCommandsTakePositionalsAndOptions() throws {
        let request = try AgentCommandLine.request(["input", "hold", "forward", "--frames", "60"])
        #expect(request.command == "input.hold")
        #expect(request.args == ["action": "forward", "frames": 60])
    }

    @Test func kebabOptionsBecomeCamelCaseAndBareOptionsAreTrue() throws {
        let request = try AgentCommandLine.request([
            "screenshot",
            "--world-only",
            "--size",
            "640x360"
        ])
        #expect(request.command == "screenshot")
        #expect(request.args == ["worldOnly": true, "size": "640x360"])
    }

    @Test func negativeNumbersAreValuesNotOptions() throws {
        let request = try AgentCommandLine.request(["debug", "item", "IronSword", "--count", "-2"])
        #expect(request.args == ["id": "IronSword", "count": -2])
    }

    @Test func anEqualsSignJoinsAnOptionToItsValue() throws {
        let request = try AgentCommandLine.request(["input", "look", "--dx=-90", "--dy", "5"])
        #expect(request.args == ["dx": -90, "dy": 5])
    }

    @Test func onAndOffAreBooleans() throws {
        let request = try AgentCommandLine.request(["debug", "overlay", "navmesh", "off"])
        #expect(request.args == ["name": "navmesh", "on": false])
    }

    @Test func actorValueStateDefaultsToThePlayer() throws {
        let request = try AgentCommandLine.request(["state", "av", "Health"])
        #expect(request.args == ["name": "Health", "ref": "player"])
        let target = try AgentCommandLine.request(["state", "av", "Health", "--ref", "target"])
        #expect(target.args["ref"] == "target")
    }

    @Test func unknownCommandsAndExtraWordsFail() {
        #expect(throws: AgentFailure.self) { try AgentCommandLine.request(["dance"]) }
        #expect(throws: AgentFailure.self) { try AgentCommandLine.request([]) }
        #expect(throws: AgentFailure.self) { try AgentCommandLine.request(["status", "now"]) }
    }

    @Test func textLinesFlattenNestedResults() {
        let value: AgentJSON = [
            "health": ["current": 50, "max": 100],
            "position": [1.5, 2, 3],
            "name": "Whiterun",
            "target": .null
        ]
        #expect(AgentCommandLine.textLines(value) == [
            "health.current: 50", "health.max: 100", "name: Whiterun",
            "position: 1.5, 2, 3", "target: none"
        ])
    }

    @Test func textLinesNumberArraysOfObjects() {
        let value: AgentJSON = ["actors": [["name": "Lydia"], ["name": "Hulda"]]]
        #expect(AgentCommandLine.textLines(value) == [
            "actors[0].name: Lydia",
            "actors[1].name: Hulda"
        ])
    }
}
