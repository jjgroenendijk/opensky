// The persisted settings and the panel readout of `ActorGraphCoordinator`.

import OpenSkyBehavior
import OpenSkyFormatsESM
import OpenSkyGameData

extension ActorGraphCoordinator {
    /// Reads the switch and the cutoff from `store`.
    public func load(settings store: PlayerSettingsStore) {
        isEnabled = store.bool(.actorGraphs)
        cutoff = ActorGraphCutoff(
            fullRateDistance: Float(store.value(.actorGraphFullRateDistance)),
            maximumDistance: Float(store.value(.actorGraphDistance))
        )
    }

    /// Race graph projects that failed to load, with the reason, in path order.
    var failures: [String] {
        projects.keys.sorted().compactMap { path in
            guard case let .failed(reason) = projects[path] else { return nil }
            return "\(path): \(reason)"
        }
    }

    func readout(for actor: ReferenceKey) -> ActorGraphReadout? {
        guard let entry = running[actor] else { return nil }
        return ActorGraphReadout(
            actor: actor,
            project: entry.project.asset.projectPath,
            activeStates: entry.instance.activeStates.map {
                $0.stateName ?? "state \($0.stateId)"
            },
            recentEvents: entry.recentEvents,
            steps: entry.steps,
            rate: entry.rate
        )
    }

    public func snapshot(for actor: ReferenceKey?) -> ActorGraphControlSnapshot {
        ActorGraphControlSnapshot(
            isEnabled: isEnabled, cutoff: cutoff, runningCount: running.count,
            fullRateCount: fullRateCount, reducedRateCount: reducedRateCount,
            failures: failures, selected: actor.flatMap(readout(for:))
        )
    }
}
