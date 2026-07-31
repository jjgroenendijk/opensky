// World > World > Triggers section (issue #173): how many trigger volumes the
// resident cells authored, how they were authored, how many sources were
// dropped on the way in, whether the player is standing in any of them, and the
// tail of the enter/leave events that fired.
//
// It sits under World rather than under a destination of its own because
// occupancy only updates in walk mode, and the fly/walk selector is one section
// above it. Read-only apart from the log clear, which leaves no provider state
// behind, so the section deliberately inherits the base no-override hooks.

import AppKit

final class TriggerVolumeSection: PanelSectionViewController {
    weak var provider: (any TriggerControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "TriggerVolumeStatsLabel")
    private let eventsLabel = PanelComponents.statsLabel(identifier: "TriggerEventStatsLabel")
    let clearLogControl = NSButton(title: "Clear log", target: nil, action: nil)

    override var sectionTitle: String {
        "Triggers"
    }

    override var sectionIdentifier: String {
        "triggerVolumes"
    }

    /// Current readout texts; the verification-surface tests read them directly.
    var statsReadout: String {
        statsLabel.stringValue
    }

    var eventsReadout: String {
        eventsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureButton(
            clearLogControl,
            target: self,
            action: #selector(clearLogPressed),
            identifier: "TriggerLogClearControl"
        )
        return [
            PanelComponents.note(
                "Trigger volumes come from SkyrimLayer 12 bodies inside a placed NIF and "
                    + "from XPRM primitives. Occupancy is tested once per frame in walk "
                    + "mode only, and freezes rather than clearing when you switch to fly."
            ),
            statsLabel,
            PanelComponents.caption("Transitions (most recent last)"),
            PanelComponents.group([eventsLabel, PanelComponents.buttonRow([clearLogControl])])
        ]
    }

    override func refreshReadout() {
        guard let snapshot = provider?.triggerStatsSnapshot, snapshot.streamerAvailable else {
            statsLabel.stringValue = "Trigger volumes: unavailable"
            eventsLabel.stringValue = "No streamer, so no transitions."
            return
        }
        let stats = snapshot.stats
        statsLabel.stringValue = [
            "Volumes: \(stats.volumeCount) resident  Occupied: \(snapshot.occupiedCount)",
            "Sources: mesh \(stats.meshVolumeCount)  primitive \(stats.primitiveVolumeCount)",
            "Dropped: excluded \(stats.excludedPrimitiveCount)"
                + "  degenerate \(stats.degenerateVolumeCount)"
                + "  unkeyed \(stats.unkeyedReferenceCount)",
            "Occupancy: \(Self.occupancyGateText(snapshot))"
        ].joined(separator: "\n")
        eventsLabel.stringValue = Self.transitionsText(snapshot)
    }

    /// Names the walk-mode gate, because occupancy only tracks in walk mode and
    /// a frozen non-zero count in fly mode would otherwise read as a bug.
    private static func occupancyGateText(_ snapshot: TriggerStatsSnapshot) -> String {
        guard snapshot.walkModeActive else {
            return snapshot.occupiedCount > 0
                ? "fly mode, frozen at \(snapshot.occupiedCount)"
                : "fly mode, not tested"
        }
        return "walk mode, live"
    }

    private static func transitionsText(_ snapshot: TriggerStatsSnapshot) -> String {
        guard !snapshot.recentTransitions.isEmpty else {
            return "No transitions recorded."
        }
        let dropped = snapshot.recordedTransitionCount - snapshot.recentTransitions.count
        let tail = snapshot.recentTransitions.joined(separator: "\n")
        return dropped > 0 ? "\(dropped) older dropped\n\(tail)" : tail
    }

    @objc private func clearLogPressed() {
        provider?.clearTriggerLog()
        finishInteraction()
    }
}
