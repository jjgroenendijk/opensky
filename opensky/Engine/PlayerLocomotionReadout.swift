// World > Player & Locomotion readout text (issue #191): the device-free half
// of the locomotion verification surface.
//
// Every line the panel shows is a pure function of one
// `PlayerLocomotionSnapshot`, exactly as `JournalReadout` is of one
// `JournalControlSnapshot`. Keeping the wording here rather than inside the
// section view controllers is what lets the text be asserted without AppKit,
// without a Metal device, and without a game install.
//
// No AppKit import on purpose: the file compiles into both the app and the CLI
// target, so it needs no project-membership exception.

import Foundation

nonisolated enum PlayerLocomotionReadout {
    /// Where the player is and what is moving them.
    static func stateText(for snapshot: PlayerLocomotionSnapshot) -> String {
        guard snapshot.rendererAvailable else {
            return "Locomotion: unavailable (no renderer)"
        }
        guard snapshot.walkModeActive else {
            return "Camera: fly\nThe player is not simulated in fly mode; "
                + "the values below are the last simulated step."
        }
        let status = snapshot.status
        let plan = status.lastPlan
        let water: String = status.waterSurfaceHeight.map { format($0) } ?? "none"
        let forced: String = snapshot.forcedGait == nil ? "" : "  (forced)"
        let impulse: String = plan.jumpImpulse.map { format($0) } ?? "none"
        let gait = "Gait: \(status.gait.rawValue)  Motion: \(name(of: status.motionSource))"
        let place = "Feet: \(format(status.feetPosition))"
        let vertical = "Vertical: \(format(status.verticalVelocity)) u/s"
        let grounded = "Grounded: \(status.isGrounded ? "yes" : "no")"
        let swimming = "Swimming: \(status.isSwimming ? "yes" : "no")"
        let step = "Step displacement: \(format(plan.horizontalDisplacement)) u"
        return [
            gait + forced,
            place + "  " + vertical,
            grounded + "  " + swimming + "  Water surface: " + water,
            step + "  Jump impulse: " + impulse,
            gaitSpeedLine(snapshot.configuration),
            "Walk speed source: \(snapshot.configuration.walkSpeed.source)"
        ].joined(separator: "\n")
    }

    /// The resolved gait speeds on one line, built piece by piece so the
    /// expression stays cheap to type-check.
    private static func gaitSpeedLine(_ configuration: PlayerMovementConfiguration) -> String {
        var line = "Gaits: walk \(format(configuration.walkSpeed.value))"
        line += "  run \(format(configuration.runSpeed.value))"
        line += "  sprint \(format(configuration.sprintSpeed.value))"
        line += "  sneak \(format(configuration.sneakSpeed.value))"
        line += "  swim \(format(configuration.swimSpeed.value))"
        return line
    }

    /// What the behavior graph is doing: the state path, the variables the
    /// bridge wrote, and the events that came back.
    static func graphText(for snapshot: PlayerLocomotionSnapshot) -> String {
        let status = snapshot.status
        guard status.graphAvailable else {
            return "Behavior graph: not attached\n"
                + "Locomotion still resolves; nothing is written or raised."
        }
        let firstPerson: String = status.firstPersonGraphAvailable
            ? "attached (\(status.firstPersonGraphUpdates) updates)"
            : "not attached"
        var header = "Behavior graph: attached"
        header += "  Updates: \(status.graphUpdates)"
        header += "  First person: " + firstPerson
        return ([header]
            + statePathLines(snapshot.activeStates, label: "State path")
            + statePathLines(snapshot.firstPersonActiveStates, label: "First-person path")
            + variableLines(snapshot.variables)
            + eventLines(status)
            + tallyLines(snapshot.tally)).joined(separator: "\n")
    }

    /// The bindings the milestone added, and whether each input is asserted
    /// right now.
    static func bindingsText(for snapshot: PlayerLocomotionSnapshot) -> String {
        guard !snapshot.bindings.isEmpty else {
            return "No binding is published."
        }
        let rows = snapshot.bindings.map { binding -> String in
            let state: String = binding.isActive ? "active" : "idle"
            return "  \(binding.label) — \(binding.key)  \(state)"
        }
        return (["Bindings:"] + rows).joined(separator: "\n")
    }

    /// Where each motion source has carried the capsule, and the steps at which
    /// the answer changed.
    static func motionText(for snapshot: PlayerLocomotionSnapshot) -> String {
        let status = snapshot.status
        var header = "Travel: root motion \(format(status.rootMotionDistance)) u"
        header += "  configured speed \(format(status.configuredSpeedDistance)) u"
        // States the rule the two totals are split by, so a reader can tell a
        // zero root-motion total from a broken one. Every vanilla animation
        // leaves `m_extractedMotion` null, so on an unmodded install the first
        // total stays at zero for the whole session (issue #370).
        let rule = "Root motion drives the capsule only for a clip whose data carries "
            + "extracted motion; vanilla clips animate in place, so the gait drives it."
        guard !status.motionTrace.isEmpty else {
            return "\(header)\n\(rule)\nNo step has planned motion yet."
        }
        let rows = status.motionTrace.map(traceLine)
        return ([header, rule, "Changes (oldest first):"] + rows).joined(separator: "\n")
    }

    private static func traceLine(_ sample: LocomotionMotionSample) -> String {
        var line = "  \(sample.gait.rawValue) via \(name(of: sample.source))"
        line += " at \(format(sample.feetPosition))"
        line += "  step \(format(sample.displacement)) u"
        line += sample.isGrounded ? "" : "  airborne"
        line += sample.isSwimming ? "  swimming" : ""
        return line
    }

    /// What the two dev controls have done, stated even when they have done
    /// nothing: "no gait forced" is the default the sidebar's reset restores.
    static func devText(for snapshot: PlayerLocomotionSnapshot, lastEvent: String?) -> String {
        let forced: String = snapshot.forcedGait
            .map { "Forced gait: \($0.rawValue)" }
            ?? "Forced gait: none (player input resolves it)"
        let event: String = lastEvent.map { "Last event: \($0)" } ?? "No event raised yet."
        return [forced, event].joined(separator: "\n")
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
        gaps += "  partial \(tally.partialGeneratorTotal)"
        gaps += "  pass-through \(tally.passthroughModifierTotal)"
        gaps += "  unresolved clips \(tally.unresolvedClipTotal)"
        let top: String = ranked.isEmpty ? "none" : ranked.joined(separator: ", ")
        return [coverage, gaps, "Top gaps: " + top]
    }

    // MARK: - Formatting

    private static func list(_ names: [String]) -> String {
        names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    static func name(of source: LocomotionMotionSource) -> String {
        switch source {
        case .rootMotion: "root motion"
        case .configuredSpeed: "configured speed"
        case .idle: "idle"
        }
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.1f", value)
    }

    private static func format(_ value: SIMD2<Float>) -> String {
        String(format: "%.1f, %.1f", value.x, value.y)
    }

    private static func format(_ value: SIMD3<Float>) -> String {
        String(format: "%.1f, %.1f, %.1f", value.x, value.y, value.z)
    }
}
