// The command list the app sends with `catalog`: it survives the wire, and the command
// line parses against it, so an openskycli from another build drives the app.

import Foundation
@testable import OpenSkyAgentControl
import Testing

struct AgentCommandListTests {
    @Test func theCatalogSurvivesTheWire() throws {
        let line = AgentLineCodec.text(AgentCommandList.builtIn.json)
        // The reply is one line, and a reader drops a line over the limit.
        #expect(line.utf8.count < AgentProtocol.maximumLineBytes / 2, "\(line.utf8.count) bytes")
        let decoded = try AgentLineCodec.decode(AgentJSON.self, from: Data(line.utf8))
        let list = try #require(AgentCommandList(json: decoded))
        #expect(list.specs.map(\.name) == AgentCommandCatalog.all.map(\.name))
        for spec in AgentCommandCatalog.all {
            let copy = try #require(list.spec(spec.name))
            #expect(copy.summary == spec.summary)
            #expect(copy.positionals.map(\.key) == spec.positionals.map(\.key))
            #expect(copy.options.map(\.key) == spec.options.map(\.key))
            #expect(copy.options.map(\.kind) == spec.options.map(\.kind))
        }
    }

    @MainActor @Test func theRouterAnswersCatalogWithoutAGame() throws {
        let router = AgentCommandRouter(world: { nil })
        let handling = router.handle(AgentRequest(command: "catalog"), now: 0)
        guard case let .done(result) = handling else {
            Issue.record("catalog waited")
            return
        }
        let list = try #require(try AgentCommandList(json: result.get()))
        #expect(list.spec("state.player") != nil)
    }

    @Test func wordsParseAgainstTheAppsList() throws {
        let newer: AgentJSON = ["commands": [[
            "name": "state.weather", "summary": "Weather.", "positionals": [],
            "options": [["key": "ref", "kind": "value", "value": "id", "help": "Who."]]
        ]]]
        let list = try #require(AgentCommandList(json: newer))
        let request = try AgentCommandLine.request(
            ["state", "weather", "--ref", "player"], commands: list
        )
        #expect(request.command == "state.weather")
        #expect(request.args == ["ref": "player"])
        #expect(throws: AgentFailure(
            .unknownCommand,
            "unknown game command: state player; "
                + "'openskycli game help' lists the commands the app answers"
        )) {
            try AgentCommandLine.request(["state", "player"], commands: list)
        }
    }

    @Test func notACatalogReadsAsNil() {
        #expect(AgentCommandList(json: ["running": true]) == nil)
    }
}
