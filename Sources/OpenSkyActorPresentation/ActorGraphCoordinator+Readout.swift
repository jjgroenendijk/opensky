// What `openskycli game state actors` shows of an actor's behaviour graph.

import OpenSkyBehavior
import OpenSkyFormatsESM

/// One actor's graph, or why it runs none.
nonisolated public struct ActorGraphReadout: Equatable, Sendable {
    /// `running`, `loading`, `failed: <reason>`, or `waiting for playback`.
    public let status: String
    public let project: String
    public let activeStates: [String]
    public let isWaitingForClip: Bool
    /// False while the graph has published no pose, so the actor draws its clip.
    public let hasPose: Bool
    public let steps: Int
    public let rate: String
    public let recentEvents: [String]
    public let unresolvedClips: [String]
    public let clipsLoaded: Int
    public let clipsMissed: Int
}

extension ActorGraphCoordinator {
    /// The readout of `actor`'s graph, or nil when its race names no graph project.
    public func readout(for actor: ReferenceKey) -> ActorGraphReadout? {
        if let entry = running[actor] {
            let instance = entry.instance
            return ActorGraphReadout(
                status: entry.isLent ? "lent" : "running",
                project: entry.project.asset.projectPath,
                activeStates: instance.activeStates.map {
                    "\($0.machineName ?? "?") / \($0.stateName ?? "?")"
                },
                isWaitingForClip: instance.isWaitingForClip,
                hasPose: !entry.pose.bones.isEmpty,
                steps: entry.steps,
                rate: entry.rate.rawValue,
                recentEvents: entry.recentEvents,
                unresolvedClips: instance.tally.unresolvedClips.keys.sorted(),
                clipsLoaded: entry.project.clips.loadedCount,
                clipsMissed: entry.project.clips.missCount
            )
        }
        guard
            let projectPath = world?.actorGraphCandidates().first(where: { $0.key == actor })?
                .projectPath
        else { return nil }
        let status = switch projects[projectPath] {
        case .ready: "waiting for playback"
        case let .failed(reason): "failed: \(reason)"
        case .loading, nil: "loading"
        }
        return ActorGraphReadout(
            status: status, project: projectPath, activeStates: [], isWaitingForClip: false,
            hasPose: false, steps: 0, rate: ActorGraphStepRate.stopped.rawValue,
            recentEvents: [], unresolvedClips: [], clipsLoaded: 0, clipsMissed: 0
        )
    }
}
