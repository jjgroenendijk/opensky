// World > Scripts readout text: pure functions of one `ScriptsSnapshot`, so the wording
// is tested without AppKit, Metal or an install. No AppKit import, so the CLI builds it.

import OpenSkyScriptingInterface

nonisolated public enum ScriptsReadout: Sendable {
    /// Instance count, the current interaction target, and the scripts attached
    /// to it. An untargeted session and a targeted reference carrying no
    /// scripts read as two different stated conditions, never as a blank.
    public static func instancesText(for snapshot: ScriptsSnapshot) -> String {
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

    /// Quest script instances, their quests, and stage-fragment dispatch. Running quests
    /// and quests with instances differ on purpose: a quest needs no scripts to run.
    public static func questsText(for snapshot: ScriptsSnapshot) -> String {
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

    /// One quest's alias table, one line per alias in fill order. An empty alias shows
    /// its fill type, so an unimplemented type differs from an empty result. A stopped
    /// quest shows all aliases empty.
    public static func questAliasText(
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
    public static func eventsText(for snapshot: ScriptsSnapshot) -> String {
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
    public static func schedulerText(for snapshot: ScriptsSnapshot) -> String {
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
                + "faulted \(snapshot.lastTickFaulted)",
            "Last step instructions: \(snapshot.lastStepInstructions)"
                + " of \(snapshot.budgetInstructions)"
        ].joined(separator: "\n")
    }

    /// Native coverage as observed, not as registered: a native nothing has
    /// called yet is counted nowhere. The ranked list names the worst offenders
    /// so a missing native is a fact on screen rather than a silent no-op.
    public static func nativeTallyText(for snapshot: ScriptsSnapshot) -> String {
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
