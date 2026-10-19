// ActorGraphControlProviding part of the shared panel fake.

import Foundation
@testable import OpenSkyActorPresentation
@testable import OpenSkyFormatsESM

/// What the Behaviour Graphs section reads, and what it asked for.
final class FakeActorGraphState {
    var snapshot = ActorGraphControlSnapshot(
        isEnabled: true, cutoff: .standard, runningCount: 0, fullRateCount: 0,
        reducedRateCount: 0, failures: [], selected: nil
    )
    var sentEvents: [(event: String, actor: ReferenceKey)] = []
}

extension FakeWorldProviders {
    func actorGraphSnapshot(for _: ReferenceKey?) -> ActorGraphControlSnapshot {
        actorGraphState.snapshot
    }

    func setActorGraphsEnabled(_ enabled: Bool) {
        setActorGraphSnapshot(enabled: enabled, cutoff: actorGraphState.snapshot.cutoff)
    }

    func setActorGraphCutoff(_ cutoff: ActorGraphCutoff) {
        setActorGraphSnapshot(enabled: actorGraphState.snapshot.isEnabled, cutoff: cutoff)
    }

    func sendActorGraphEvent(_ event: String, to actor: ReferenceKey) -> Bool {
        actorGraphState.sentEvents.append((event, actor))
        return true
    }

    private func setActorGraphSnapshot(enabled: Bool, cutoff: ActorGraphCutoff) {
        let old = actorGraphState.snapshot
        actorGraphState.snapshot = ActorGraphControlSnapshot(
            isEnabled: enabled, cutoff: cutoff, runningCount: old.runningCount,
            fullRateCount: old.fullRateCount, reducedRateCount: old.reducedRateCount,
            failures: old.failures, selected: old.selected
        )
    }
}
