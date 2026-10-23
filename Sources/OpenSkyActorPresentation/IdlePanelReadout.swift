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

    public static func traceLine(_ trace: IdleCandidateTrace) -> String {
        String(repeating: "  ", count: trace.depth + 1)
            + "\(trace.editorID ?? trace.id.description): \(verdictText(trace.verdict))"
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
}

nonisolated public enum HeadAssemblyReadout {
    static func missText(_ reason: HeadPartMiss.Reason) -> String {
        switch reason {
        case .missingRecord: "no such head part"
        case .wrongRace: "not allowed for the race"
        case .noModel: "no model"
        case .cycle: "extra parts loop"
        }
    }
}
