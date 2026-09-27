// The lines the M16 gate panel prints (issue #203, roadmap item 16.8), built
// here rather than in the sections for the reason `CombatLoopReadout`,
// `PhysicsReadout` and `ActorValueControlReadout` are: a string a milestone
// gate asserts on belongs in the engine target, where a unit test can reach it
// without a window and without AppKit.
//
// Four namespaces rather than one, matching the four provider seams the panel
// consumes. `AIDetectionReadout` deliberately owns only the *pass* half of the
// detection lines; the per-pair line is `DetectionPairReadout.summaryLine`,
// which 16.6 already published for exactly this label.
//
// Documented in docs/engine/navigation.md, docs/engine/package-schedules.md and
// docs/engine/detection.md.

import Foundation

/// The `AIOverlayStatsLabel` lines: what is switched on and what it cost.
nonisolated enum AIOverlayReadout {
    static func toggleText(for snapshot: AIOverlayControlSnapshot) -> String {
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
    static func drawText(for snapshot: AIOverlayControlSnapshot) -> String {
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
nonisolated enum AINavigationReadout {
    /// Who is resident and which of them the destination is acting on.
    static func actorText(for snapshot: AINavigationSnapshot) -> String {
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
    static func movementText(for snapshot: AINavigationSnapshot) -> String {
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
    static func moveResultText(_ result: NPCMoveCommandResult, actor: String) -> String {
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

    static func missText(_ miss: NavigationPathMiss) -> String {
        switch miss {
        case .startProjection: "the actor is not standing on the navmesh"
        case .targetProjection: "the crosshair point is not on the navmesh"
        case .disconnected: "no corridor connects the two"
        }
    }
}

/// The `AIPackageStatsLabel` lines: which package the schedule chose, and when.
nonisolated enum AIPackageReadout {
    static func packageText(for snapshot: AINavigationSnapshot) -> String {
        guard snapshot.isAvailable else { return "Package: unavailable" }
        let header = "Packages: \(snapshot.packagedActorCount) actors keeping a schedule"
        guard let package = snapshot.package else {
            return "\(header)\nPackage: \(snapshot.selectedActorName) has none registered."
        }
        return "\(header)\n\(selectionText(for: package))\n\(scheduleText(for: package.schedule))"
    }

    /// Which package won for one actor, and which procedure it runs.
    static func selectionText(for package: PackageActorReadout) -> String {
        guard let current = package.currentPackage else {
            return "Package: none selected (base \(package.actorBase))"
        }
        let name = package.editorID ?? current.description
        let procedure = package.procedure.map(procedureText(for:)) ?? "no procedure"
        let evaluated = package.lastEvaluationGameSeconds.map {
            String(format: ", evaluated at %.0f game seconds", $0)
        } ?? ""
        return "Package: \(name) (\(current)), \(procedure)\(evaluated)"
    }

    static func procedureText(for procedure: PackageProcedureKind) -> String {
        switch procedure {
        case .travel: "travel"
        case .wander: "wander"
        case .sandbox: "sandbox"
        case .sleep: "sleep"
        case .eat: "eat"
        case let .unsupported(name): "unsupported (\(name))"
        }
    }

    /// The authored schedule spelled out, because a row of signed bytes is not
    /// a thing a person can check a clock against.
    static func scheduleText(for schedule: Package.Schedule?) -> String {
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

/// The `DetectionStatsLabel` header lines. The pair lines under it are
/// `DetectionPairReadout.summaryLine`, which issue #202 published for this
/// label.
nonisolated enum AIDetectionReadout {
    static func passText(for snapshot: PerceptionControlSnapshot) -> String {
        guard !snapshot.isUnavailable else { return "Detection: unavailable" }
        let readout = snapshot.readout
        let dropped = readout.droppedPairCount > 0
            ? ", \(readout.droppedPairCount) pairs over the cap"
            : ""
        return "Detection: \(readout.pairs.count) pairs from"
            + " \(readout.observerCount) observers over \(readout.targetCount) targets"
            + " (\(readout.lineOfSightQueryCount) sight queries,"
            + " \(readout.stepCount) steps)\(dropped)"
    }

    /// Every pair the selected actor is on either side of.
    static func pairsText(lines: [String], actor: String) -> String {
        guard !lines.isEmpty else {
            return "\(actor): nothing perceives it and it perceives nothing"
        }
        return lines.map { "  \($0)" }.joined(separator: "\n")
    }
}
