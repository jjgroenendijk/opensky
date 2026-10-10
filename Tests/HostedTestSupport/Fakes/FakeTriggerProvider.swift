// The trigger stats fake and the `FakeWorldProviders` forwarding that goes with
// it, shared by the World panel suites and by the real-data trigger suites in
// OpenSkyRealDataTests. See Tests/HostedTestSupport/AGENTS.md.

import AppKit
@testable import OpenSkyPhysics
import Testing

/// Records what the Triggers section asks of the streamer.
/// `FakeWorldProviders` forwards `TriggerControlProviding` here, so every
/// panel sees the same fake.
@MainActor
final class FakeTriggerProvider {
    var snapshot = TriggerStatsSnapshot.unavailable
    private(set) var clearCount = 0

    func clear() {
        clearCount += 1
        snapshot = TriggerStatsSnapshot(
            streamerAvailable: snapshot.streamerAvailable,
            stats: snapshot.stats,
            occupiedCount: snapshot.occupiedCount,
            walkModeActive: snapshot.walkModeActive,
            recentTransitions: [],
            recordedTransitionCount: 0
        )
    }
}

extension FakeWorldProviders {
    var triggerStatsSnapshot: TriggerStatsSnapshot {
        triggers.snapshot
    }

    func clearTriggerLog() {
        triggers.clear()
    }
}
