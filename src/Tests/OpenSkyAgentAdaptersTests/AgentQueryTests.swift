import Foundation

// A state query of a reference that is not loaded fails, and the clock reaches its port.

import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkySessionTesting
import Testing

@MainActor
struct AgentQueryTests {
    private let host = AgentHost()
    private let world: AgentWorldAdapter

    init() {
        world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    private func failure(of query: AgentStateQuery) -> AgentErrorCode? {
        do {
            _ = try world.query(query)
            return nil
        } catch {
            return error.code
        }
    }

    @Test func readsOfAnUnloadedReferenceFail() {
        let queries: [AgentStateQuery] = [
            .packages(reference: "zz"), .furniture(reference: "not hex"),
            .actorValue(reference: "14", name: "Health")
        ]
        for query in queries {
            #expect(failure(of: query) != nil, "\(query)")
        }
    }

    @Test func aReferenceIsThePlayerOrALoadedFormID() throws {
        let player = try world.hub.resolveReference("Player")
        #expect(player.key == .player)
        #expect(throws: AgentFailure.self) { try world.hub.resolveReference("target") }
        #expect(throws: AgentFailure.self) { try world.hub.resolveReference("not hex") }
        #expect(throws: AgentFailure.self) { try world.hub.resolveReference("14") }
        #expect(throws: AgentFailure.self) { try world.hub.actorValueIndex("NoSuchValue") }
    }

    @Test func statusAndClockReachTheirPorts() throws {
        host.fakeTitleMenu.isOpen = true
        let status = world.agentStatus
        #expect(status.titleMenuOpen)
        #expect(!status.worldReady)
        #expect(status.dataRoot == nil)
        world.pauseSimulation()
        world.resumeSimulation()
        world.requestSteps(3, seconds: 0.1)
        try world.setTimeScale(2)
        #expect(throws: AgentFailure.self) { try world.setTimeScale(0) }
        #expect(throws: AgentFailure.self) {
            try world.setTimeScale(AgentWorldAdapter.maximumTimeScale + 1)
        }
        #expect(host.fakeSimulationClock.freezeCallCount == 1)
        #expect(host.fakeSimulationClock.resumeCallCount == 1)
        #expect(host.fakeSimulationClock.requestStepsCalls.map(\.count) == [3])
        #expect(host.fakeSimulationClock.setScaleCalls == [2])
    }
}
