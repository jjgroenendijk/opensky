// The last crime and the last guard step, as values. Only the `text` formatters
// build the readout lines.

import OpenSkyCrimeInterface

nonisolated public enum CrimeNote: Equatable, Sendable {
    case idle
    /// `label` names the crime, such as "Assault"; `faction` is nil when nobody tracks it.
    case recorded(CrimeOutcome, label: String, faction: String?)

    public var text: String {
        switch self {
        case .idle: "No crime recorded yet."
        case let .recorded(outcome, label, faction):
            CrimeCore.outcomeText(outcome, label: label, factionName: faction)
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
        }
    }
}
