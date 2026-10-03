// Text for the Idles and Head Assembly sections. Pure, so the wording is
// tested without building the app.

import Foundation
import OpenSkyFormatsESM

nonisolated public enum IdleReadout {
    public static func markersText(for snapshot: IdleControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Idle markers: unavailable" }
        guard !snapshot.markers.isEmpty else { return "Idle markers: none in the loaded cells" }
        let lines = snapshot.markers.map { marker in
            let holder = marker.claimedBy.map { " · used by \($0)" } ?? ""
            return "\(marker.editorID): \(marker.idles.count) idles\(holder)"
        }
        return (["Idle markers: \(snapshot.markers.count), actors idling: "
                + "\(snapshot.idlingActorCount)"] + lines).joined(separator: "\n")
    }

    public static func markerText(_ marker: IdleMarkerReadout?) -> String {
        guard let marker else { return "Marker: none" }
        let order = marker.inSequence ? "in sequence" : "random"
        let once = marker.doOnce ? ", once" : ""
        let idles = marker.idles.isEmpty ? "none" : marker.idles.joined(separator: ", ")
        return """
        Marker: \(marker.editorID) (\(order)\(once), timer \(seconds(marker.timer)))
        Idles: \(idles)
        """
    }

    public static func treeText(_ lines: [IdleTreeLine]) -> String {
        guard !lines.isEmpty else { return "Tree: none" }
        return (["Tree:"] + lines.map { line in
            String(repeating: "  ", count: line.depth + 1) + line.editorID
                + (line.event.map { " -> \($0)" } ?? "")
        }).joined(separator: "\n")
    }

    public static func reportText(_ report: IdleReport?) -> String {
        guard let report else { return "Last pick: none" }
        var lines = ["Last pick (\(report.source)): \(report.chosen ?? "nothing")"]
        if let plan = report.plan {
            lines.append("Event: \(plan.event ?? "none") · served by \(pathText(plan.path))")
            lines.append("Prop: \(propText(plan.prop)) · plays \(seconds(report.seconds))")
        }
        if let failure = report.failure {
            lines.append("Result: \(failure)")
        }
        lines += report.trace.map { trace in
            String(repeating: "  ", count: trace.depth + 1)
                + "\(trace.editorID ?? trace.id.description): \(verdictText(trace.verdict))"
        }
        return lines.joined(separator: "\n")
    }

    public static func pathText(_ path: IdleServedPath) -> String {
        switch path {
        case let .graphEvent(files): "graph event (\(files.last ?? "graph"))"
        case .namedClip: "clip named after the event"
        case .none(.noEvent): "nothing (no event)"
        case .none(.eventNotInGraph): "nothing (event not in the graph)"
        case let .none(.clipMissing(path)): "nothing (missing \(path))"
        }
    }

    public static func propText(_ prop: IdleProp) -> String {
        switch prop {
        case let .attached(editorID, _, bone): "\(editorID) on \(bone)"
        case .none: "none"
        case let .modelMissing(editorID): "\(editorID), model missing"
        case let .noBone(editorID): "\(editorID), no bone named"
        }
    }

    public static func verdictText(_ verdict: IdleCandidateTrace.Verdict) -> String {
        switch verdict {
        case .chosen: "chosen"
        case .passed: "passed"
        case let .rejected(condition): "failed \(condition)"
        case .notReached: "not reached"
        case .alreadyPlayed: "already played"
        case .noAnimation: "no animation"
        }
    }

    private static func seconds(_ value: Float) -> String {
        String(format: "%.1f s", value)
    }
}

nonisolated public enum HeadAssemblyReadout {
    public static func text(for snapshot: HeadAssemblySnapshot) -> String {
        guard snapshot.actor != nil else { return "Head: no actor selected" }
        guard let head = snapshot.head else { return "Head: actor not drawn" }
        let shown = head.source == .assembled
            ? "assembled, \(head.loadedPartCount) of \(head.parts.parts.count) parts loaded"
            : head.hasBakedHead ? "baked FaceGen" : "none"
        var lines = ["Head: \(shown)"]
        if snapshot.requested != head.source {
            lines.append("Requested: \(sourceText(snapshot.requested)), applies on rebuild")
        }
        lines += head.parts.parts.map(partText)
        lines += head.parts.misses.map { "Missing \($0.formID): \(missText($0.reason))" }
        return lines.joined(separator: "\n")
    }

    public static func sourceText(_ source: ActorHeadSource) -> String {
        switch source {
        case .baked: "baked"
        case .assembled: "assembled"
        }
    }

    static func partText(_ part: ResolvedHeadPart) -> String {
        let type = part.partType.map { "\($0)" } ?? "untyped"
        let tint = part.tint.map {
            String(format: " · tint %.2f %.2f %.2f", $0.x, $0.y, $0.z)
        } ?? ""
        return "\(part.editorID ?? part.formID.description): \(type), "
            + "\(originText(part.origin))\(tint)"
    }

    static func originText(_ origin: HeadPartOrigin) -> String {
        switch origin {
        case .raceDefault: "race default"
        case .npcOverride: "NPC choice"
        case .extraPart: "extra part"
        }
    }

    static func missText(_ reason: HeadPartMiss.Reason) -> String {
        switch reason {
        case .missingRecord: "no such head part"
        case .wrongRace: "not allowed for the race"
        case .noModel: "no model"
        case .cycle: "extra parts loop"
        }
    }
}
