// The port the router drives. The app implements it over its coordinators; a
// test passes a fake. Every call runs on the main actor, between frames.

import Foundation

/// The simulation clock as an agent sees it.
nonisolated public struct AgentTimeline: Equatable, Sendable {
    /// Frames drawn since the game view started.
    public var frame: Int
    /// True while the agent holds the simulation frozen.
    public var paused: Bool
    /// Steps asked for and not yet drawn.
    public var pendingSteps: Int
    /// Simulated seconds per wall second while running.
    public var scale: Double

    public init(frame: Int, paused: Bool, pendingSteps: Int = 0, scale: Double = 1) {
        self.frame = frame
        self.paused = paused
        self.pendingSteps = pendingSteps
        self.scale = scale
    }

    public var json: AgentJSON {
        [
            "frame": .init(frame), "paused": .bool(paused),
            "pendingSteps": .init(pendingSteps), "scale": .number(scale)
        ]
    }
}

nonisolated public struct AgentWorldStatus: Equatable, Sendable {
    /// True once the first cell is in the scene and the player can move.
    public var worldReady: Bool
    public var dataRoot: String?
    public var mode: String?

    public init(worldReady: Bool, dataRoot: String?, mode: String?) {
        self.worldReady = worldReady
        self.dataRoot = dataRoot
        self.mode = mode
    }
}

@MainActor
public protocol AgentControlWorld: AnyObject {
    var agentStatus: AgentWorldStatus { get }
    var agentTimeline: AgentTimeline { get }

    func pauseSimulation()
    func resumeSimulation()
    /// Queues `count` frames of `seconds` each. They draw one per display frame.
    func requestSteps(_ count: Int, seconds: Double)
    func setTimeScale(_ scale: Double) throws(AgentFailure)

    /// Feeds a logical action into the same input path the keyboard uses.
    /// - Returns: true when the action is held until released.
    func applyInput(_ action: String, phase: AgentInputPhase) throws(AgentFailure) -> Bool
    /// Turns the view by degrees; positive yaw turns right, positive pitch looks up.
    func look(yawDegrees: Float, pitchDegrees: Float) throws(AgentFailure)
    /// Moves the top menu's selection to the row with this visible label.
    func selectMenuRow(label: String) throws(AgentFailure) -> AgentJSON

    func captureScreenshot(_ request: AgentScreenshotRequest) throws(AgentFailure) -> AgentJSON
    func query(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON
    /// A teleport waits until the destination has loaded, so it may return a wait.
    func perform(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentHandling

    /// Called once per poll, so the game can diff its state into events.
    func pollEvents(_ emit: (String, [String: AgentJSON]) -> Void)
    func quitApplication()
}
