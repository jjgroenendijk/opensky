// Live-renderer seam for the World > World > Triggers section (issue #173).
// Same shape as the other panel bridges: one Equatable snapshot crosses from
// the engine to the readout, polled at 2 Hz, plus one action the section can
// invoke. Nothing here reaches into the streamer directly.

/// What the trigger readout shows for one refresh.
nonisolated struct TriggerStatsSnapshot: Equatable {
    /// False when there is no streamer at all (missing game data, or the
    /// synthetic DemoScene). Reported rather than shown as a row of zeros,
    /// which would read as "this cell authored no triggers".
    let streamerAvailable: Bool
    /// Trigger accounting summed over whatever is resident, including the
    /// dropped-source counters that would otherwise truncate silently.
    let stats: TriggerVolumeStats
    /// Volumes the player capsule is inside as of the last walk-mode frame.
    let occupiedCount: Int
    /// True while the camera is in walk mode. Occupancy is only tested there,
    /// and leaving walk mode freezes the set instead of clearing it, so a
    /// non-zero occupancy in fly mode is correct rather than a bug — the
    /// readout has to say which state produced the number.
    let walkModeActive: Bool
    /// Recent transition lines, oldest first (`TriggerEventLog.lines`).
    let recentTransitions: [String]
    /// Transitions recorded since the log was last cleared, including any the
    /// bounded ring has already dropped.
    let recordedTransitionCount: Int

    static let unavailable = TriggerStatsSnapshot(
        streamerAvailable: false,
        stats: TriggerVolumeStats(),
        occupiedCount: 0,
        walkModeActive: false,
        recentTransitions: [],
        recordedTransitionCount: 0
    )
}

@MainActor
protocol TriggerControlProviding: AnyObject {
    var triggerStatsSnapshot: TriggerStatsSnapshot { get }
    /// Empties the rolling transition log so the next walk produces a readable
    /// tail. Action-only: it leaves no provider state behind, so it is not an
    /// override.
    func clearTriggerLog()
}
