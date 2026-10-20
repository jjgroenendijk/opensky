// The last crime and the last guard step, as values. Only the `text` formatters
// build the readout lines.

import OpenSkyCrimeInterface

nonisolated public enum CrimeNote: Equatable, Sendable {
    case idle
    /// `label` names the crime, such as "Assault"; `faction` is nil when nobody tracks it.
    case recorded(CrimeOutcome, label: String, faction: String?)
    case trespassWarning(secondsLeft: Int)
    /// Every witness died before a guard heard: the gold came off again.
    case reportLost(gold: Int32, faction: String)
    /// A witness reached a guard, so the bounty stays.
    case reportDelivered(faction: String, by: String)

    public var text: String {
        switch self {
        case .idle: "No crime recorded yet."
        case let .recorded(outcome, label, faction):
            CrimeCore.outcomeText(outcome, label: label, factionName: faction)
        case let .trespassWarning(seconds): "Trespass warning: \(seconds) s to leave."
        case let .reportLost(gold, faction):
            "Every witness died: \(gold) bounty removed from \(faction)."
        case let .reportDelivered(faction, witness):
            "\(witness) reported the crime to a \(faction) guard."
        }
    }
}

nonisolated public enum GuardNote: Equatable, Sendable {
    case idle
    case arrestRefused(faction: String, ArrestRefusal)
    case settled(ArrestSettlement, faction: String, moved: Bool)
    case resisted(faction: String)
    /// `reason` is the dialogue session's own line, when it gave one.
    case conversationFailed(reason: String?)
    case confronted(bounty: Int32, faction: String)
    /// `move` is the movement system's own line.
    case pursuing(faction: String, move: String)
    case jailed(days: Int, faction: String)
    /// `skills` is how many skills lost their progress.
    case served(days: Int, skills: Int, faction: String, moved: Bool)
    case escaped(gold: Int32, faction: String)
    case actorCriminal(name: String, faction: String)

    public var text: String {
        switch self {
        case .idle: "No guard has acted yet."
        case let .arrestRefused(faction, refusal):
            "Arrest with \(faction) refused: \(refusal)."
        case let .settled(settlement, faction, moved):
            CrimeCore.settlementText(settlement, factionName: faction, moved: moved)
        case let .resisted(faction): "Resisted arrest with \(faction)."
        case let .conversationFailed(reason):
            "Guard could not open the arrest conversation (\(reason ?? "no reason given"))."
        case let .confronted(bounty, faction):
            "Guard confronted the player over a \(bounty) bounty with \(faction)."
        case let .pursuing(faction, move): "Guard of \(faction) pursuing: \(move)."
        case let .jailed(days, faction): "In the \(faction) jail for \(days) days."
        case let .served(days, skills, faction, moved):
            "Served \(days) days in the \(faction) jail; \(skills) skills lost progress"
                + (moved ? "." : "; the release door is not reachable.")
        case let .actorCriminal(name, faction):
            "\(name) struck first in \(faction)'s land; its guards fight them."
        case let .escaped(gold, faction):
            "Escaped the \(faction) jail: \(gold) bounty is owed again."
        }
    }
}
