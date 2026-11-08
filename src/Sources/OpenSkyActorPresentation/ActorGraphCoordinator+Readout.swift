// What `openskycli game state actors` shows of an actor's behaviour graph.

import OpenSkyBehavior
import OpenSkyFormatsAnimation
public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

extension ActorGraphCoordinator {
    /// The readout of `actor`'s graph, or nil when its race names no graph project.
    public func readout(for actor: ReferenceKey) -> ActorGraphReadout? {
        if let entry = running[actor] {
            let instance = entry.instance
            var readout = ActorGraphReadout(
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
                clipsMissed: entry.project.clips.missCount,
                heldFromBone: entry.heldFromBone.map { entry.project.asset.skeleton.boneNames[$0] }
            )
            readout.isDrunk = entry.isDrunk
            readout.state = instance.variable(named: ActorGraphNames.state)
                .map { Int32(truncatingIfNeeded: $0.intValue) }
            readout.stateTag = instance.stateTag?.value
            for name in [
                ActorGraphNames.weaponAdjust, ActorGraphNames.bodyMorphWeight,
                ActorGraphNames.bodyMorphMuscular
            ] {
                readout.bodyWeight[name] = instance.variable(named: name)?.realValue
            }
            return readout
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
