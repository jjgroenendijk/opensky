// What the last actor-value control did, as a value. Only `text` builds the line.

import Foundation
import OpenSkyFormatsESM

nonisolated public enum ActorValueActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    case noTarget(ActorValueTargetSelector)
    case notAnActorValue(Int32)
    /// `verb` is the control's own word, such as "Damaged" or "Set the base of".
    case changed(verb: String, actor: String, index: Int32, value: Float)
    case refilled(actor: String, health: Float, magicka: Float, stamina: Float)
    case reset(actor: String, changed: Bool)
}

nonisolated extension ActorValueActionOutcome {
    public var text: String {
        switch self {
        case .idle: "No actor-value action yet."
        case .unavailable: "Actor values unavailable: no game data loaded."
        case .noTarget(.player): "No player actor values."
        case .noTarget(.nearestActor): "No resident actor to act on."
        case let .notAnActorValue(index):
            "\(ActorValueIdentity.description(of: index)) is not an actor value."
        case let .changed(verb, actor, index, value):
            String(
                format: "%@ %@ %@: now %.1f.",
                verb, actor, ActorValueIdentity.description(of: index), value
            )
        case let .refilled(actor, health, magicka, stamina):
            String(format: "Refilled %@: %.1f / %.1f / %.1f.", actor, health, magicka, stamina)
        case let .reset(actor, changed):
            changed ? "Reset \(actor) to derived values." : "\(actor) already reads from records."
        }
    }
}
