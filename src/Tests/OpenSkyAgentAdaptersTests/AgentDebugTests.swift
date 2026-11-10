import Foundation

// Debug commands that name a reference fail before they reach a port when the reference
// is not loaded, and the clock commands reach the runtime state.

import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkySessionTesting
import Testing

@MainActor
struct AgentDebugTests {
    private let host = AgentHost()
    private let world: AgentWorldAdapter

    init() {
        world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    private func failure(of command: AgentDebugCommand) -> AgentErrorCode? {
        do {
            switch try world.perform(command) {
            case let .done(result):
                if case let .failure(error) = result {
                    return error.code
                }
                return nil
            case .waiting:
                return nil
            }
        } catch {
            return error.code
        }
    }

    @Test func actorCommandsNeedALoadedActor() {
        let commands: [AgentDebugCommand] = [
            .kill("14"), .resurrect("14"), .decapitate("14"), .drunk(reference: "14", drunk: true),
            .eyes(reference: "14", textureSet: "Eyes"),
            .setActorValue(reference: "14", name: "Health", value: 1),
            .modActorValue(reference: "14", name: "Health", delta: 1)
        ]
        for command in commands {
            #expect(failure(of: command) != nil, "\(command)")
        }
    }

    @Test func settingTheTimeMovesTheGameClock() {
        #expect(failure(of: .setTime(hour: 9)) == nil)
        #expect(host.fakeRuntimeState.setGameClockHourCalls == [9])
    }

    @Test func aTeleportBeforeTheWorldLoadsIsRefused() {
        #expect(throws: AgentFailure.self) { try world.perform(.teleport(.position([0, 0, 0]))) }
    }

    @Test func anUnknownInputIsRefused() {
        #expect(throws: AgentFailure.self) { try world.applyInput("no such input", phase: .press) }
    }
}
