// The AI panel's lines, formatted in the engine target so a unit test can check them
// without a window. One namespace per provider seam; per-pair detection lines are
// `DetectionPairReadout.summaryLine`. See docs/engine/navigation.md,
// docs/engine/package-schedules.md and docs/engine/detection.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyRendering

/// The `AIOverlayStatsLabel` lines: what is switched on and what it cost.
nonisolated public enum AIOverlayReadout: Sendable {
    public static func toggleText(for snapshot: AIOverlayControlSnapshot) -> String {
        let on = [
            snapshot.navmeshOverlayEnabled ? "navmesh" : nil,
            snapshot.pathOverlayEnabled ? "path" : nil,
            snapshot.detectionOverlayEnabled ? "detection" : nil
        ].compactMap(\.self)
        return "Overlays: " + (on.isEmpty ? "all off" : on.joined(separator: ", "))
    }

    /// What the overlay pass actually submitted and drew last frame. A user who
    /// switched the navmesh on and sees nothing needs to know whether the pass
    /// drew nothing or drew it somewhere else.
    public static func drawText(for snapshot: AIOverlayControlSnapshot) -> String {
        let stats = snapshot.stats
        let truncation = stats.wasTruncated
            ? " — \(stats.droppedPrimitiveCount) dropped over the primitive budget"
            : ""
        return "Overlay draw: \(stats.drawnPrimitiveCount)/\(stats.submittedPrimitiveCount)"
            + " primitives (\(stats.triangleCount) triangles,"
            + " \(stats.lineSegmentCount) lines) in \(stats.drawCalls) draw calls"
            + truncation
    }
}

/// The `AIActorStatsLabel` and `AIMovementStatsLabel` lines.
nonisolated public enum AINavigationReadout: Sendable {
    /// Who is resident and which of them the destination is acting on.
    public static func actorText(for snapshot: AINavigationSnapshot) -> String {
        guard snapshot.isAvailable else { return "Actors: unavailable" }
        guard !snapshot.actors.isEmpty else {
            return "Actors: none resident.\nStream a cell holding one, or walk to Whiterun."
        }
        let dead = snapshot.actors.count { $0.isDead }
        let selected = snapshot.actors.first { $0.key == snapshot.selectedActor }
        let away = selected.map { String(format: " at %.0f u", $0.distance) } ?? ""
        let header = "Actors: \(snapshot.actors.count) resident (\(dead) dead),"
            + " acting on \(snapshot.selectedActorName)\(away)"
        let crosshair = snapshot.crosshairPoint.map {
            String(format: "Crosshair: (%.0f, %.0f, %.0f)", $0.x, $0.y, $0.z)
        } ?? "Crosshair: not on anything"
        return "\(header)\n\(crosshair)\n\(snapshot.lastActionText)"
    }

    /// One selected actor's mover: where it is on its path and how it is
    /// travelling.
    public static func movementText(for snapshot: AINavigationSnapshot) -> String {
        guard snapshot.isAvailable else { return "Movement: unavailable" }
        let crowd = "Movers: \(snapshot.moverCount)/\(snapshot.moverLimit)"
        guard let movement = snapshot.movement else {
            return "\(crowd)\nMovement: \(snapshot.selectedActorName) is not moving."
        }
        let feet = movement.feetPosition
        let position = String(format: "(%.0f, %.0f, %.0f)", feet.x, feet.y, feet.z)
        let waypoint = "waypoint \(movement.waypointIndex)/\(movement.waypointCount)"
        let travel = "\(movement.gait.rawValue), \(movement.repathCount) repaths"
        let line = "Movement: \(snapshot.selectedActorName) \(movement.state.rawValue)"
        return "\(crowd)\n\(line) at \(position), \(waypoint), \(travel)"
    }

    /// What one move request answered, in the words the panel shows.
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
    public static func packageText(for snapshot: AINavigationSnapshot) -> String {
        guard snapshot.isAvailable else { return "Package: unavailable" }
        let header = "Packages: \(snapshot.packagedActorCount) actors keeping a schedule"
        guard let package = snapshot.package else {
            return "\(header)\nPackage: \(snapshot.selectedActorName) has none registered."
        }
        let lines = [
            header, selectionText(for: package), scheduleText(for: package.schedule),
            snapshot.procedure.map(procedureStateText(for:)),
            snapshot.carrier.map { "Riding: \($0)" }
        ]
        return lines.compactMap(\.self).joined(separator: "\n")
    }

    /// Where a held package's procedure is, such as `Procedure: moving, point 3 of 32`.
    public static func procedureStateText(for machine: PackageProcedureMachine) -> String {
        let state = switch machine.state {
        case .ready: "ready"
        case .moving: "moving"
        case .idleStop: "pausing"
        case let .looping(clip): "looping \(clip.rawValue)"
        case .waiting: "waiting"
        case .complete: "done"
        case .failed: "failed"
        }
        guard !machine.path.isEmpty else { return "Procedure: \(state)" }
        return "Procedure: \(state), point \(machine.pathIndex + 1) of \(machine.path.count + 1)"
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
        switch procedure {
        case .travel: "travel"
        case .patrol: "patrol"
        case .wander: "wander"
        case .sandbox: "sandbox"
        case .sleep: "sleep"
        case .eat: "eat"
        case .wait: "wait"
        case let .unsupported(name): "unsupported (\(name))"
        }
    }

    /// The authored schedule spelled out, because a row of signed bytes is not
    /// a thing a person can check a clock against.
    public static func scheduleText(for schedule: Package.Schedule?) -> String {
        guard let schedule else { return "Schedule: none authored" }
        guard schedule.hour >= 0 else {
            return "Schedule: any time" + calendarSuffix(schedule)
        }
        let minute = max(Int(schedule.minute), 0)
        let start = String(format: "%02d:%02d", Int(schedule.hour), minute)
        return "Schedule: from \(start) for \(schedule.durationMinutes) minutes"
            + calendarSuffix(schedule)
    }

    private static func calendarSuffix(_ schedule: Package.Schedule) -> String {
        var parts: [String] = []
        if schedule.month >= 0 {
            parts.append("month \(schedule.month)")
        }
        if schedule.dayOfWeek >= 0 {
            parts.append("day-of-week \(schedule.dayOfWeek)")
        }
        if schedule.date > 0 {
            parts.append("date \(schedule.date)")
        }
        return parts.isEmpty ? "" : " (" + parts.joined(separator: ", ") + ")"
    }
}

/// The `DetectionStatsLabel` header lines; the pair lines are
/// `DetectionPairReadout.summaryLine`.
nonisolated public enum AIDetectionReadout: Sendable {
    public static func passText(for snapshot: PerceptionControlSnapshot) -> String {
        guard !snapshot.isUnavailable else { return "Detection: unavailable" }
        let readout = snapshot.readout
        let dropped = readout.droppedPairCount > 0
            ? ", \(readout.droppedPairCount) pairs over the cap"
            : ""
        let pass = "Detection: \(readout.pairs.count) pairs from"
            + " \(readout.observerCount) observers over \(readout.targetCount) targets"
            + " (\(readout.lineOfSightQueryCount) sight queries,"
            + " \(readout.stepCount) steps)\(dropped)"
        return ([pass] + readout.targets.map { "  \($0.summaryLine)" }).joined(separator: "\n")
    }

    /// Every pair the selected actor is on either side of.
    public static func pairsText(lines: [String], actor: String) -> String {
        guard !lines.isEmpty else {
            return "\(actor): nothing perceives it and it perceives nothing"
        }
        return lines.map { "  \($0)" }.joined(separator: "\n")
    }
}
