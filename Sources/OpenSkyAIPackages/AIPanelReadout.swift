// The AI readout's lines, formatted in the engine target so a unit test can check them
// without a window. One namespace per provider seam; per-pair detection lines are
// `DetectionPairReadout.summaryLine`. See docs/engine/navigation.md,
// docs/engine/package-schedules.md and docs/engine/detection.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyNavigation
import OpenSkyPhysics
import OpenSkyWorldInterface

/// The `AIActorStatsLabel` and `AIMovementStatsLabel` lines.
nonisolated public enum AINavigationReadout: Sendable {
    /// What one move request answered, in the words the readout shows.
    public static func moveResultText(_ result: NPCMoveCommandResult, actor: String) -> String {
        switch result {
        case .started:
            "Move: \(actor) is pathing to the crosshair point."
        case .actorNotResident:
            "Cannot move \(actor): it is no longer resident."
        case let .noPath(reason):
            "Cannot move \(actor): no navmesh path — \(missText(reason))."
        case .moverCapReached:
            "Cannot move \(actor): the mover cap is full."
        }
    }

    public static func missText(_ miss: NavigationPathMiss) -> String {
        switch miss {
        case .startProjection: "the actor is not standing on the navmesh"
        case .targetProjection: "the crosshair point is not on the navmesh"
        case .disconnected: "no corridor connects the two"
        }
    }
}

/// The `AIPackageStatsLabel` lines: which package the schedule chose, and when.
nonisolated public enum AIPackageReadout: Sendable {
    /// Bumps now and since the session began, and the follower spacing.
    public static func socialText(
        bumps: BumpReactions, bump: BumpReactionSettings, follow: FollowSettings
    ) -> String {
        String(
            format: "Bumps: %d reacting, %d since load (step %.0f u, hold %.1f s)"
                + " · followers %.0f u apart, run slowdown to %.0f%%",
            bumps.reactingActors.count, bumps.reactionCount, bump.moveDistance,
            bump.waitSeconds, follow.spaceBetweenFollowers,
            follow.runMinSlowdownMultiplier * 100
        )
    }

    /// Where the current package's procedure is, such as
    /// `Procedure: patrol, moving, point 3 of 32`.
    public static func procedureStateText(for machine: PackageProcedureMachine) -> String {
        var state = stateText(for: machine.state)
        if case .sandboxing = machine.state {
            state += String(format: ", %.2f game hours left", machine.sandbox.hoursLeft)
        }
        guard !machine.path.isEmpty else { return "Procedure: \(machine.kind.name), \(state)" }
        return "Procedure: \(machine.kind.name), \(state), point \(machine.pathIndex + 1) of "
            + "\(machine.path.count + 1)"
    }

    /// The tree's procedures that run at once, such as `Running: sit, wait`; nil for one.
    public static func runningText(for machines: [PackageProcedureMachine]) -> String? {
        guard machines.count > 1 else { return nil }
        return "Running: " + machines.map { "\($0.kind.name) (\(stateText(for: $0.state)))" }
            .joined(separator: ", ")
    }

    static func stateText(for state: PackageProcedureState) -> String {
        switch state {
        case .ready: "ready"
        case .moving: "moving"
        case .idleStop: "pausing"
        case let .looping(clip): "looping \(clip.rawValue)"
        case .seated: "seated"
        case .waiting: "waiting"
        case .searching: "searching"
        case .acting: "acting"
        case let .sandboxing(activity): activity.rawValue
        case .complete: "done"
        case .failed: "failed"
        }
    }

    /// Which package won for one actor, and which procedure it runs.
    public static func selectionText(for package: PackageActorReadout) -> String {
        guard let current = package.currentPackage else {
            return "Package: none selected (base \(package.actorBase))"
        }
        let name = package.editorID ?? current.description
        let procedure = package.procedure.map(procedureText(for:)) ?? "no procedure"
        let evaluated = package.lastEvaluationGameSeconds.map {
            String(format: ", evaluated at %.0f game seconds", $0)
        } ?? ""
        let held = package.override.map { ", held by scene \($0.source) action \($0.slot)" } ?? ""
        return "Package: \(name) (\(current)), \(procedure)\(evaluated)\(held)"
    }

    public static func procedureText(for procedure: PackageProcedureKind) -> String {
        if case let .unsupported(name) = procedure {
            return "unsupported (\(name))"
        }
        return procedure.name
    }
}
