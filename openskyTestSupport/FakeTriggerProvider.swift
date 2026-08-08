// The trigger stats fake and the `FakeWorldProviders` forwarding that goes with
// it, shared by the World panel suites and by the real-data trigger suites in
// openskyRealDataTests. See openskyTestSupport/AGENTS.md.

import AppKit
@testable import opensky
import Testing

/// Records what the Triggers section asks of the live streamer (issue #173).
/// `FakeWorldProviders` forwards its `TriggerControlProviding` conformance
/// here, so a registry-built panel and a directly built one observe the same
/// fake.
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
