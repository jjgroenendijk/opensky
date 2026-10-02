// World > World > Triggers: trigger-volume counts, dropped sources, player
// occupancy, and recent enter/leave events. Under World because occupancy
// needs walk mode, which the Camera section selects.

import AppKit
import OpenSkyPhysics

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
        statsLabel.toolTip = "Checked in walk mode only."
        PanelComponents.configureButton(
            clearLogControl,
            target: self,
            action: #selector(clearLogPressed),
            identifier: "TriggerLogClearControl"
        )
        return [
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
