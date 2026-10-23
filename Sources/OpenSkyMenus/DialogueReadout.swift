// Dialogue readout text. Each line is a pure function of one
// `DialogueControlSnapshot`, so the wording is testable without AppKit, a
// Metal device, or an install. No AppKit import: the CLI builds it too.

import OpenSkyDialogueInterface

nonisolated public enum DialogueReadout: Sendable {
    /// One rejection reason worded for a readout.
    public static func reason(_ rejection: DialogueRejection) -> String {
        switch rejection {
        case let .questNotRunning(quest): "quest \(quest) not running"
        case .alreadySaid: "already said"
        case .waitingForReset: "waiting for its reset time"
        case .conditionsFailed: "conditions failed"
        case .notReached: "not reached"
        case .lostRandomPick: "lost the random pick"
        case .notBranchEntry: "not a branch start"
        case let .blockedByBranch(branch): "blocked by branch \(branch)"
        }
    }
}
