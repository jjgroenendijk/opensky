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

    /// Quest script instances, the quests behind them, and stage-fragment
    /// dispatch (issue #322).
    ///
    /// Running quests and quests with instances are two different numbers on
    /// purpose: a quest that carries no scripts runs perfectly well without
    /// any, so the gap between them is information rather than an error.
    static func questsText(for snapshot: ScriptsSnapshot) -> String {
        [
            "Running quests: \(snapshot.runningQuestCount)"
                + "  Scripted: \(snapshot.questCount)",
            "Quest instances: \(snapshot.questInstanceCount)"
                + "  Stage fragments queued: \(snapshot.questFragmentsQueued)",
            "Last fragment: \(snapshot.lastQuestFragment ?? "none")",
            "Aliases filled: \(snapshot.filledAliasCount)"
                + " across \(snapshot.aliasQuestCount) quests"
                + "  Alias instances: \(snapshot.questAliasInstanceCount)",
            "Fill failures: \(snapshot.questAliasFillFailures)"
                + "  Last fill: \(snapshot.lastQuestAliasFill ?? "none")"
        ].joined(separator: "\n")
    }

    /// One quest's alias table (issue #183), one line per alias in the order
    /// the quest fills them.
    ///
    /// An empty alias reads as "empty" beside the fill type that was supposed
    /// to fill it, so an unimplemented fill type and a fill that genuinely
    /// found nothing are told apart on screen rather than both reading as a
    /// blank. A quest that is not running shows every alias empty, which is
    /// what the Creation Kit describes rather than a fault.
    static func questAliasText(
        for table: ScriptQuestAliasInspection?,
        editorID: String
    ) -> String {
        guard let table else {
            return editorID.isEmpty
                ? "No quest selected."
                : "No loaded plugin defines \(editorID)."
        }
        let header = "\(table.editorID) (\(table.formIDText))"
            + "  \(table.isRunning ? "running" : "not running")"
            + "  filled \(table.filledCount)/\(table.rows.count)"
        guard !table.rows.isEmpty else {
            return "\(header)\nThis quest declares no aliases."
        }
        return ([header] + table.rows.map(line)).joined(separator: "\n")
    }

    private static func line(_ row: ScriptQuestAliasRow) -> String {
        let name = row.name.isEmpty ? "unnamed" : row.name
        let optional = row.isOptional ? ", optional" : ""
        return "  [\(row.aliasID)] \(name) (\(row.fillType)\(optional))"
            + " -> \(row.reference ?? "empty")"
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
