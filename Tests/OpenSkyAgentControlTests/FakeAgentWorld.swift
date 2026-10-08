// A scripted game for the router tests: it records calls and answers from
// plain fields, so each test sets only what it reads.

import Foundation
import OpenSkyAgentControl

@MainActor
final class FakeAgentWorld: AgentControlWorld {
    var agentStatus = AgentWorldStatus(worldReady: true, dataRoot: "/data", mode: "play")
    var agentTimeline = AgentTimeline(frame: 10, paused: false)
    var heldActions: Set = ["forward", "back", "block"]
    var oneShotActions: Set = ["jump", "activate"]
    var inputLog: [String] = []
    var stepRequests: [Int] = []
    var pendingEvents: [(String, [String: AgentJSON])] = []
    var quitCount = 0

    func pauseSimulation() {
        agentTimeline.paused = true
    }

    func resumeSimulation() {
        agentTimeline.paused = false
    }

    func requestSteps(_ count: Int, seconds _: Double) {
        stepRequests.append(count)
        agentTimeline.pendingSteps += count
    }

    /// Draws one frame, consuming a step when any is queued.
    func drawFrame() {
        agentTimeline.frame += 1
        if agentTimeline.pendingSteps > 0 {
            agentTimeline.pendingSteps -= 1
        }
    }

    func setTimeScale(_ scale: Double) throws(AgentFailure) {
        guard scale > 0 else { throw AgentFailure(.invalidArgument, "scale") }
        agentTimeline.scale = scale
    }

    func applyInput(_ action: String, phase: AgentInputPhase) throws(AgentFailure) -> Bool {
        let held = heldActions.contains(action)
        guard held || oneShotActions.contains(action) else {
            throw AgentFailure(.invalidArgument, "unknown action \(action)")
        }
        inputLog.append("\(phase.rawValue) \(action)")
        return held
    }

    func look(yawDegrees: Float, pitchDegrees: Float) throws(AgentFailure) {
        inputLog.append("look \(yawDegrees) \(pitchDegrees)")
    }

    func selectMenuRow(label: String) throws(AgentFailure) -> AgentJSON {
        ["selected": .string(label)]
    }

    func pointMenu(x: Float, y: Float, click: Bool) throws(AgentFailure) -> AgentJSON {
        inputLog.append("\(click ? "click" : "point") \(x) \(y)")
        return ["clicked": .bool(click)]
    }

    func typeText(_ text: String) throws(AgentFailure) -> AgentJSON {
        inputLog.append("text \(text)")
        return ["typed": .string(text)]
    }

    func captureScreenshot(_ request: AgentScreenshotRequest) throws(AgentFailure)
        -> AgentHandling
    {
        .done(.success(["path": .string(request.path), "offscreen": .bool(request.offscreen)]))
    }

    func query(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON {
        switch query {
        case .player: ["position": [1, 2, 3]]
        default: throw AgentFailure(.notFound, "no such state")
        }
    }

    func perform(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentHandling {
        .done(.success(["done": .string(String(describing: command))]))
    }

    func pollEvents(_ emit: (String, [String: AgentJSON]) -> Void) {
        for (kind, data) in pendingEvents {
            emit(kind, data)
        }
        pendingEvents.removeAll()
    }

    func quitApplication() {
        quitCount += 1
    }
}
