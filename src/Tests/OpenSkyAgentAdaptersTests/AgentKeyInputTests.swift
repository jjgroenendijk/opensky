// One keyboard key from an agent: the Controls page's key wait takes it first, then
// the action the key is bound to.

import Foundation
import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyMenusInterface
import OpenSkySessionInterface
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

    @Test func aMenuDirectionPressIsATapAndAHoldEndsWithARelease() throws {
        host.fakeMenuMode.isMenuMode = true
        let held = try input.applyInput("menuDown", phase: .press)
        #expect(!held)
        #expect(try input.applyInput("menuDown", phase: .hold))
        #expect(host.fakeMenuMode.routeMenuInputCalls == [
            .move(.down), .release(.down), .move(.down)
        ])
    }

    @Test func anUnknownKeyFails() {
        #expect(throws: AgentFailure.self) { try input.pressKey("NoSuchKey") }
    }

    @Test func theControlsPageShowsItsWaitAndKeys() throws {
        host.fakeMovies.readout = MoviePlaybackReadout(loading: false, interruptible: true)
        host.fakeMapMenu.snapshot = MapMenuSnapshot(
            selected: nil, cameraHeight: nil, questTargets: [], lastResult: nil
        )
        host.fakeSystemMenu.isOpen = true
        host.fakeSystemMenu.model.page = .controls
        host.fakeSystemMenu.controls = ControlsPageReadout(
            waitingForKey: true,
            rows: [.init(action: "Jump", key: "Space"), .init(action: "Wait", key: nil)]
        )
        let world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        guard
            case let .object(state) = try world.query(.menu),
            case let .object(controls) = state["controls"],
            case let .array(rows) = controls["bindings"], rows.count == 2,
            case let .object(first) = rows[0], case let .object(second) = rows[1]
        else {
            Issue.record("no Controls readout")
            return
        }
        #expect(controls["waitingForKey"] == .bool(true))
        #expect(first["key"] == .string("Space"))
        #expect(second["key"] == .null)
    }
}
