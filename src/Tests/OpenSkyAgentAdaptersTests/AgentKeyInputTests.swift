// One keyboard key from an agent: the Controls page's key wait takes it first, then
// the action the key is bound to.

import Foundation
import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyMenusInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct AgentKeyInputTests {
    private let host = AgentHost()

    private var input: AgentInputAdapter {
        AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) }).input
    }

    @Test func theControlsWaitTakesTheKey() throws {
        host.fakeMenuMode.isMenuMode = true
        host.fakePlayerSettings.scanCodeResult = 0x39
        host.fakePlayerSettings.keyNameResult = "Space"
        host.fakeSystemMenu.captureKeyResult = true
        let result = try input.pressKey("Space")
        #expect(result["bound"] == true)
        #expect(result["key"] == "Space")
        #expect(host.fakeSystemMenu.captureKeyCalls == [0x39])
        #expect(host.fakePlayerSettings.actionCalls.isEmpty)
    }

    @Test func outsideAMenuTheBoundActionRuns() throws {
        host.fakePlayerSettings.scanCodeResult = 0x11
        host.fakePlayerSettings.actionResult = .forward
        let result = try input.pressKey("W")
        #expect(result["action"] == "forward")
        #expect(host.fakeSystemMenu.captureKeyCalls.isEmpty)
    }

    @Test func anUnboundKeyRunsNothing() throws {
        host.fakePlayerSettings.scanCodeResult = 0x3B
        let result = try input.pressKey("F1")
        #expect(result["action"] == .null)
    }

    @Test func anUnknownKeyFails() {
        #expect(throws: AgentFailure.self) { try input.pressKey("NoSuchKey") }
    }
}
