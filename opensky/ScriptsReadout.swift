// World > Scripts readout text (issue #278): the device-free half of the
// Papyrus verification surface.
//
// Every line the four Scripts sections show is a pure function of one
// `ScriptsSnapshot`, exactly as `SWFLabReadout` is a pure function of one
// `SWFLabControlSnapshot`. Keeping the wording here rather than inside the
// section view controllers is what lets the text be asserted without AppKit,
// without a Metal device, and without a game install.
//
// No AppKit import on purpose: the file compiles into both the app and the CLI
// target, so it needs no project-membership exception.

nonisolated enum ScriptsReadout {
    /// Instance count, the current interaction target, and the scripts attached
    /// to it. An untargeted session and a targeted reference carrying no
    /// scripts read as two different stated conditions, never as a blank.
    static func instancesText(for snapshot: ScriptsSnapshot) -> String {
        guard let target = snapshot.targetDescription else {
            return "Instances: \(snapshot.instanceCount)\nTarget: none"
        }
        let scripts = snapshot.targetScripts.isEmpty
            ? "none"
            : snapshot.targetScripts.joined(separator: ", ")
        return """
        Instances: \(snapshot.instanceCount)
        Target: \(target)
        Target scripts: \(scripts)
        """
    }

    /// Queue depth plus the dispatched-event tail, oldest first, in the same
    /// most-recent-last presentation the Runtime State journal uses.
    static func eventsText(for snapshot: ScriptsSnapshot) -> String {
        let header = "Pending events: \(snapshot.pendingEventCount)"
            + "  Dropped: \(snapshot.droppedRecentEventCount)"
        guard !snapshot.recentEvents.isEmpty else {
            return "\(header)\nNo events dispatched yet."
        }
        return ([header] + snapshot.recentEvents).joined(separator: "\n")
    }

    /// Whether the VM is running, what it is holding, and what the last fixed
    /// step actually did. The pause line states the VM's own pause only; the
    /// engine's menu-mode pause is a separate control under System Menu.
    static func schedulerText(for snapshot: ScriptsSnapshot) -> String {
        [
            "VM: \(snapshot.isPaused ? "paused" : "running")",
            "Pending waits: \(snapshot.pendingWaitCount)"
                + "  Pending timers: \(snapshot.pendingTimerCount)",
            "Ticks: \(snapshot.tickCount)"
                + "  Budget: \(snapshot.budgetEvents) events / "
                + "\(snapshot.budgetInstructions) instructions",
            "Last tick: steps \(snapshot.lastTickSteps) · "
                + "dispatched \(snapshot.lastTickDispatched) · "
                + "queued \(snapshot.lastTickQueued) · "
                + "resumed \(snapshot.lastTickResumed) · "
                + "faulted \(snapshot.lastTickFaulted)"
        ].joined(separator: "\n")
    }

    /// Native coverage as observed, not as registered: a native nothing has
    /// called yet is counted nowhere. The ranked list names the worst offenders
    /// so a missing native is a fact on screen rather than a silent no-op.
    static func nativeTallyText(for snapshot: ScriptsSnapshot) -> String {
        var lines = [
            "Native calls: \(snapshot.nativeCallTotal)",
            "Implemented names: \(snapshot.implementedNativeNameCount)"
                + "  Unimplemented calls: \(snapshot.unimplementedNativeTotal)"
        ]
        if snapshot.topUnimplementedNatives.isEmpty {
            lines.append("Top unimplemented: none")
        } else {
            lines.append("Top unimplemented:")
            for (index, entry) in snapshot.topUnimplementedNatives.enumerated() {
                lines.append("\(index + 1). \(entry.name) \(entry.count)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
