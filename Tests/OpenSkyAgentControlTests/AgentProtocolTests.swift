// The line codec and the argument parsing, with no socket and no game.

import Foundation
import OpenSkyAgentControl
import Testing

struct AgentProtocolTests {
    @Test func aRequestRoundTripsThroughOneLine() throws {
        let request = AgentRequest(id: 7, command: "input.press", args: ["action": "jump"])
        let line = AgentLineCodec.encode(request)
        #expect(line.last == UInt8(ascii: "\n"))
        let decoded = try AgentLineCodec.decodeRequest(line.dropLast())
        #expect(decoded == request)
    }

    @Test func aRequestWithoutIdOrArgsStillDecodes() throws {
        let decoded = try AgentLineCodec.decodeRequest(Data(#"{"command":"status"}"#.utf8))
        #expect(decoded.command == "status")
        #expect(decoded.id == 0)
        #expect(decoded.args.isEmpty)
    }

    @Test(arguments: ["", "not json", "[1,2]", #"{"args":{}}"#, #"{"command":5}"#])
    func malformedLinesAreTypedErrors(line: String) {
        #expect(throws: AgentFailure.self) {
            try AgentLineCodec.decodeRequest(Data(line.utf8))
        }
    }

    @Test func aFailedReplyCarriesTheCodeAndNoResult() throws {
        let context = AgentReplyContext(frame: 3, paused: true, eventSeq: 9)
        let reply = AgentReply(id: 2, context: context, error: AgentFailure(.notFound, "gone"))
        let decoded = try AgentLineCodec.decode(AgentReply.self, from: AgentLineCodec.encode(reply))
        #expect(!decoded.ok)
        #expect(decoded.error?.code == .notFound)
        #expect(decoded.frame == 3)
        #expect(decoded.paused)
        #expect(decoded.eventSeq == 9)
        #expect(decoded.result == nil)
    }

    @Test func theLineBufferSplitsChunksAndDropsBlankLines() {
        var buffer = AgentLineBuffer()
        #expect(buffer.append(Data("{\"a\":1}\n\n{\"b\"".utf8)) == [.line(Data("{\"a\":1}".utf8))])
        #expect(buffer.append(Data(":2}\n".utf8)) == [.line(Data("{\"b\":2}".utf8))])
    }

    @Test func anOverlongLineIsReportedOnceAndTheNextLineIsClean() {
        var buffer = AgentLineBuffer()
        let long = Data(repeating: UInt8(ascii: "x"), count: AgentProtocol.maximumLineBytes + 10)
        #expect(buffer.append(long + Data("\nok\n".utf8)) == [.tooLong, .line(Data("ok".utf8))])
    }

    @Test func jsonPathsReachIntoObjectsAndArrays() {
        let value: AgentJSON = ["actors": [["formID": "00012345"]], "menu": ["top": "Inventory"]]
        #expect(value.value(atPath: "actors.0.formID") == "00012345")
        #expect(value.value(atPath: "menu.top") == "Inventory")
        #expect(value.value(atPath: "actors.4") == nil)
    }
}

struct AgentCommandParsingTests {
    private func args(_ values: [String: AgentJSON], _ command: String = "test") -> AgentArguments {
        AgentArguments(command: command, values: values)
    }

    @Test func teleportTakesOneKindOfTarget() throws {
        #expect(try AgentDebugCommand.parse("teleport", args(["cell": "RiverwoodSleepingGiantInn"]))
            == .teleport(.cell("RiverwoodSleepingGiantInn")))
        #expect(try AgentDebugCommand.parse("teleport", args(["x": 6, "y": "-2"]))
            == .teleport(.grid(x: 6, y: -2)))
        #expect(try AgentDebugCommand.parse("teleport", args(["pos": "1, 2.5, -3"]))
            == .teleport(.position(SIMD3(1, 2.5, -3))))
        #expect(throws: AgentFailure.self) { try AgentDebugCommand.parse("teleport", args([:])) }
        #expect(throws: AgentFailure.self) {
            try AgentDebugCommand.parse("teleport", args(["pos": [1, 2]]))
        }
    }

    @Test func aNegativeItemCountRemoves() throws {
        #expect(try AgentDebugCommand.parse("item", args(["id": "Gold001", "count": -5]))
            == .removeItem(reference: "player", item: "Gold001", count: 5))
        #expect(throws: AgentFailure.self) {
            try AgentDebugCommand.parse("item", args(["id": "Gold001", "count": 0]))
        }
    }

    @Test func actorValuesSetOrModify() throws {
        #expect(try AgentDebugCommand.parse("av", args(["name": "Health", "value": 50]))
            == .setActorValue(reference: "player", name: "Health", value: 50))
        #expect(try AgentDebugCommand.parse(
            "av",
            args(["ref": "Lydia", "name": "Health", "mod": -10])
        )
            == .modActorValue(reference: "Lydia", name: "Health", delta: -10))
    }

    @Test func outOfRangeValuesAreRejected() {
        #expect(throws: AgentFailure.self) {
            try AgentDebugCommand.parse("time", args(["hour": 24]))
        }
        #expect(throws: AgentFailure.self) { try AgentDebugCommand.parse("fly", args([:])) }
        #expect(throws: AgentFailure.self) { try AgentStateQuery.parse("quest", args([:])) }
    }

    @Test func screenshotsNeedAnAbsolutePathAndASaneSize() throws {
        let request = try AgentScreenshotRequest.parse(args([
            "out": "/tmp/a.png",
            "size": "640x360"
        ]))
        #expect(request.width == 640)
        #expect(request.height == 360)
        #expect(request.offscreen, "a size needs a second render")
        let window = try AgentScreenshotRequest.parse(args(["out": "/tmp/a.png"]))
        #expect(!window.offscreen, "the default is the window's own frame")
        #expect(try AgentScreenshotRequest.parse(args(["out": "/tmp/a.png", "worldOnly": true]))
            .offscreen)
        #expect(throws: AgentFailure.self) {
            try AgentScreenshotRequest.parse(args(["out": "a.png"]))
        }
        #expect(throws: AgentFailure.self) {
            try AgentScreenshotRequest.parse(args(["out": "/tmp/a.png", "size": "1x99999"]))
        }
    }
}
