// Player locomotion readout text. Each line is a pure function of
// one `PlayerLocomotionSnapshot`, so the wording is testable without AppKit, a
// Metal device, or an install. No AppKit import: the CLI builds it too.

import Foundation
import OpenSkyBehavior

nonisolated public enum PlayerLocomotionReadout: Sendable {
    /// The breath left under water, and whether the player is drowning.
    public static func breathLine(_ breath: PlayerBreath?) -> String {
        guard let breath else { return "Breath: unavailable" }
        let total = format(breath.settings.breathSeconds)
        let left = "\(format(breath.remainingSeconds)) of \(total) s"
        guard breath.isSubmerged else { return "Breath: \(left)  (above water)" }
        return "Breath: \(left)" +
            (breath.remainingSeconds > 0 ? "  (under water)" : "  (drowning)")
    }

    /// What the behavior graph is doing: the state path, the variables the
    /// bridge wrote, and the events that came back.
    public static func graphText(for snapshot: PlayerLocomotionSnapshot) -> String {
        let status = snapshot.status
        let bodyLines = snapshot.bodyFailureReason.map { ["Player body: none (\($0))"] } ?? []
        guard status.graphAvailable else {
            return ([
                "Behavior graph: not attached",
                "Locomotion still resolves; nothing is written or raised."
            ] + bodyLines).joined(separator: "\n")
        }
        let firstPerson: String = status.firstPersonGraphAvailable
            ? "attached (\(status.firstPersonGraphUpdates) updates)"
            : "not attached"
        var header = "Behavior graph: attached"
        header += "  Updates: \(status.graphUpdates)"
        header += "  First person: " + firstPerson
        return ([header] + bodyLines
            + statePathLines(snapshot.activeStates, label: "State path")
            + statePathLines(snapshot.firstPersonActiveStates, label: "First-person path")
            + variableLines(snapshot.variables)
            + eventLines(status)
            + tallyLines(snapshot.tally)).joined(separator: "\n")
    }

    // MARK: - Sections of the graph readout

    private static func statePathLines(
        _ states: [BehaviorActiveState],
        label: String
    ) -> [String] {
        guard !states.isEmpty else {
            return ["\(label): no state machine reported one"]
        }
        return ["\(label):"] + states.map(stateLine)
    }

    private static func stateLine(_ state: BehaviorActiveState) -> String {
        let machine: String = state.machineName ?? "<unnamed machine>"
        let name: String = state.stateName ?? "state \(state.stateId)"
        guard state.blendWeight < 1 else {
            return "  \(machine) > \(name)"
        }
        let previous: String = state.previousStateName ?? "-"
        return "  \(machine) > \(name)  blending from \(previous) at \(format(state.blendWeight))"
    }

    private static func variableLines(_ variables: [LocomotionVariableSnapshot]) -> [String] {
        guard !variables.isEmpty else {
            return ["Variables: none written yet"]
        }
        return ["Variables:"] + variables.map { variable in
            "  \(variable.name) = \(variable.value ?? "<not declared by the graph>")"
        }
    }

    private static func eventLines(_ status: LocomotionStatus) -> [String] {
        let recent = status.recentGraphEvents.isEmpty
            ? "none"
            : status.recentGraphEvents.joined(separator: ", ")
        return [
            "Raised: \(list(status.raisedEvents))",
            "Missing names: variables \(list(status.missingVariables))"
                + "  events \(list(status.missingEvents))",
            "Recent graph events: \(recent)"
        ]
    }

    /// The honest-coverage line. Zeros are stated rather than hidden: "0 gaps"
    /// is the claim the milestone gate makes, and a missing line would read as
    /// a missing readout instead of a clean run.
    private static func tallyLines(_ tally: BehaviorTally?) -> [String] {
        guard let tally else {
            return ["Coverage: no tally (the graph has not been updated)"]
        }
        let ranked = tally.rankedFeatureGaps.prefix(3).map { "\($0.name) \($0.count)" }
        var coverage = "Coverage: \(tally.generatorsEvaluated) generators"
        coverage += ", \(tally.modifiersEvaluated) modifiers"
        coverage += " over \(tally.updatesRun) updates"
        var gaps = "Gaps: \(tally.gapTotal) total"
        gaps += "  unevaluated \(tally.unevaluatedGeneratorTotal)"
        gaps += "  pass-through \(tally.passthroughModifierTotal)"
        gaps += "  unresolved clips \(tally.unresolvedClipTotal)"
        let top: String = ranked.isEmpty ? "none" : ranked.joined(separator: ", ")
        return [coverage, gaps, "Top gaps: " + top]
    }

    // MARK: - Formatting

    private static func list(_ names: [String]) -> String {
        names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.1f", value)
    }
}
