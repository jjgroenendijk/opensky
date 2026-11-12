import Foundation

// A finished tour answers the agent with its folder, its stop, its failed scenes, and
// the error that kept its files from being written.

@testable import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyWorld
import OpenSkyWorldInterface
import Testing

@MainActor
struct BenchmarkRunReplyTests {
    @Test func aFinishedRunAnswersItsFolderAndCounts() {
        let machine = BenchmarkMachine(
            modelIdentifier: "Mac0,0", cpu: "Test CPU", gpu: "Test GPU", logicalCores: 8,
            memoryGB: 16, osVersion: "26.0"
        )
        var result = BenchmarkTourResult(startedAt: Date(), machine: machine, preset: .quick)
        result.stopped = true
        let run = BenchmarkRun(
            result: result, folder: URL(filePath: "/tmp/tour"), writeError: "disk full"
        )
        let json = BenchmarkAgentRequests.json(run)
        #expect(json["folder"] == AgentJSON.string("/tmp/tour"))
        #expect(json["stopped"] == AgentJSON.bool(true))
        #expect(json["failed"] == AgentJSON(0))
        #expect(json["writeError"] == AgentJSON.string("disk full"))
    }
}
