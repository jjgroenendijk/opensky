// `game run` script parsing and the `expect` check.

import OpenSkyAgentControl
import Testing

struct AgentScriptTests {
    @Test func commentsAndBlankLinesAreSkippedAndLineNumbersKept() throws {
        let steps = try AgentScript.parse("""
        # setup
        {"command":"time.pause"}

        {"command":"input.hold","args":{"action":"forward","frames":60},"expect":{"released":true}}
        """)
        #expect(steps.map(\.request.command) == ["time.pause", "input.hold"])
        #expect(steps.map(\.lineNumber) == [2, 4])
        #expect(steps[1].request.args["frames"]?.intValue == 60)
        #expect(steps[1].expect["released"] == true)
    }

    @Test func aBrokenLineNamesItsNumber() {
        #expect(throws: AgentFailure(.malformedRequest, "line 2: no command")) {
            try AgentScript.parse("{\"command\":\"status\"}\n{\"args\":{}}")
        }
    }

    @Test func expectationsCompareNumbersWithATolerance() {
        let result: AgentJSON = ["position": [1.00001, 2, 3], "menu": ["top": "InventoryMenu"]]
        #expect(AgentScript.mismatches(
            of: result,
            against: ["position.0": 1, "menu.top": "InventoryMenu"]
        )
        .isEmpty)
        #expect(AgentScript.mismatches(of: result, against: ["position.1": 2.5]).count == 1)
        #expect(AgentScript.mismatches(of: result, against: ["missing": true]).count == 1)
    }

    @Test func aRecordedLineReplays() throws {
        let request = AgentRequest(id: 4, command: "debug.teleport", args: ["cell": "Whiterun"])
        let replayed = try AgentScript.parse(AgentScript.line(for: request))
        #expect(replayed.first?.request.command == "debug.teleport")
        #expect(replayed.first?.request.args == request.args)
    }
}
