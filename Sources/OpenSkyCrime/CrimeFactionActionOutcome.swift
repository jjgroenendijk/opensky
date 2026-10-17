// What the last `World > Crime & Factions` control did, as a value. Only `text`
// builds the line.

nonisolated public enum CrimeFactionActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    case noCrimeFaction
    case noFactions
    case bountyMoved(faction: String, gold: Int32, violent: Bool, total: Int32)
    case bountyCleared(faction: String, owed: Int32)
    case guardCheckNeedsSubject
    case notAGuard(String)
    /// `tick` is the guard pass's own line, or nil when no world ran one.
    case guardChecked(
        guardName: String, faction: String, bounty: Int32, response: CrimeResponse, tick: String?
    )
    /// The guard pass's own line after resisting.
    case resisted(String)
    case crosshairNotOnActor
    case subjectSelected(String?)
    case joined(actor: String, faction: String, rank: Int8, changed: Bool)
    case left(actor: String, faction: String, changed: Bool)
    /// The barter session's own line.
    case barter(String)

    public var text: String {
        switch self {
        case .idle: "No crime or faction action yet."
        case .unavailable: "Crime and factions unavailable: no game data loaded."
        case .noCrimeFaction: CrimeCore.noFactionTracksCrimeText
        case .noFactions: CrimeCore.noFactionsText
        case let .bountyMoved(faction, gold, violent, total):
            "Moved the \(violent ? "violent" : "non-violent") bounty with \(faction) by "
                + "\(gold): now \(total) gold."
        case let .bountyCleared(faction, owed): "Cleared \(owed) gold owed to \(faction)."
        case .guardCheckNeedsSubject:
            "Guard check: pick an actor with the crosshair first — the player is nobody's guard."
        case let .notAGuard(name): "Guard check: \(name) is not a guard."
        case let .guardChecked(guardName, faction, bounty, response, tick):
            "Guard check: \(guardName) polices \(faction); bounty \(bounty) gold → "
                + "\(CrimeFactionReadout.responseText(response))."
                + (tick.map { " Guard tick: \($0)" }
                    ?? " No world is running, so no guard tick ran.")
        case .resisted, .crosshairNotOnActor, .subjectSelected, .joined, .left, .barter:
            membershipText
        }
    }

    private var membershipText: String {
        switch self {
        case let .resisted(line): line
        case .crosshairNotOnActor: "The crosshair is not on an actor."
        case let .subjectSelected(name): "Subject: \(name ?? "the player")."
        case let .joined(actor, faction, rank, changed):
            changed
                ? "\(actor) is in \(faction) at rank \(rank)."
                : "\(actor) was already in \(faction) at rank \(rank), or is not resident."
        case let .left(actor, faction, changed):
            changed ? "\(actor) left \(faction)." : "\(actor) was not in \(faction)."
        case let .barter(line): line
        default: ""
        }
    }
}
