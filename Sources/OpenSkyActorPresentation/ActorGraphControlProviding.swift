// The Behaviour Graphs section's seam: the switch, the distance cutoff, and the
// selected actor's running graph.

import OpenSkyFormatsESM

/// How often an actor's graph stepped on the last frame.
nonisolated public enum ActorGraphStepRate: String, Equatable, Sendable {
    case full
    case reduced
    case stopped
}

/// One actor's running graph, as the panel shows it.
nonisolated public struct ActorGraphReadout: Equatable, Sendable {
    public let actor: ReferenceKey
    public let project: String
    /// The state of each state machine the last step reached, outermost first.
    public let activeStates: [String]
    /// The newest events the graph fired, newest last.
    public let recentEvents: [String]
    public let steps: Int
    public let rate: ActorGraphStepRate

    public init(
        actor: ReferenceKey, project: String, activeStates: [String],
        recentEvents: [String], steps: Int, rate: ActorGraphStepRate
    ) {
        self.actor = actor
        self.project = project
        self.activeStates = activeStates
        self.recentEvents = recentEvents
        self.steps = steps
        self.rate = rate
    }
}

nonisolated public struct ActorGraphControlSnapshot: Equatable, Sendable {
    public let isEnabled: Bool
    public let cutoff: ActorGraphCutoff
    public let runningCount: Int
    /// Graphs stepped on the last frame, at full and at reduced rate.
    public let fullRateCount: Int
    public let reducedRateCount: Int
    /// Race graph projects that failed to load, with the reason.
    public let failures: [String]
    public let selected: ActorGraphReadout?

    public init(
        isEnabled: Bool, cutoff: ActorGraphCutoff, runningCount: Int, fullRateCount: Int,
        reducedRateCount: Int, failures: [String], selected: ActorGraphReadout?
    ) {
        self.isEnabled = isEnabled
        self.cutoff = cutoff
        self.runningCount = runningCount
        self.fullRateCount = fullRateCount
        self.reducedRateCount = reducedRateCount
        self.failures = failures
        self.selected = selected
    }
}

@MainActor
public protocol ActorGraphControlProviding: AnyObject {
    func actorGraphSnapshot(for actor: ReferenceKey?) -> ActorGraphControlSnapshot
    /// Off returns every actor to its clips. Persisted.
    func setActorGraphsEnabled(_ enabled: Bool)
    /// Persisted.
    func setActorGraphCutoff(_ cutoff: ActorGraphCutoff)
    /// Raises `event` on the actor's graph. False when it runs none or lacks the event.
    @discardableResult
    func sendActorGraphEvent(_ event: String, to actor: ReferenceKey) -> Bool
}
