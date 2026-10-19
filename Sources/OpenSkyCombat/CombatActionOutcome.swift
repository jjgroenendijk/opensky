// What the last melee, archery, and combat-loop control did, as values. Only the
// `text` formatters build lines.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM

nonisolated public enum MeleeActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    case cannotAttack(WeaponDrawState)
    case requested(power: Bool)
    case clearedTrace

    public var text: String {
        switch self {
        case .idle: "No melee action yet."
        case .unavailable: "Melee unavailable: no game data loaded."
        case let .cannotAttack(state): "Cannot attack: weapon is \(state.rawValue)."
        case .requested(power: false): "Requested one swing."
        case .requested(power: true): "Requested one power attack."
        case .clearedTrace: "Cleared the hit trace."
        }
    }
}

nonisolated public enum ArcheryActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    case noAmmunition
    case noLaunchSpeed
    case fired(id: Int, speed: Float)
    case despawned
    case clearedStuck
    case clearedTrace

    public var text: String {
        switch self {
        case .idle: "No shot taken yet."
        case .unavailable: "Archery unavailable: no game data loaded."
        case .noAmmunition: "Cannot fire: no ammunition with a flyable PROJ carried."
        case .noLaunchSpeed: "Cannot fire: the projectile has no launch speed."
        case let .fired(id, speed):
            String(format: "Fired projectile #%d at %.0f units/s.", id, speed)
        case .despawned: "Despawned everything in flight."
        case .clearedStuck: "Pulled every stuck arrow back out."
        case .clearedTrace: "Cleared the shot trace."
        }
    }
}

nonisolated public enum CombatLoopOutcome: Equatable, Sendable {
    case idle
    case castingDisallowed
    case noHostilityTarget
    case hostility(actor: String, hostile: Bool)
    case scriptStarted(ReferenceKey)
    case scriptStopped(ReferenceKey)
    case assisted(ReferenceKey, ally: ReferenceKey)

    public var text: String {
        switch self {
        case .idle: "No fight yet."
        case .castingDisallowed: "Combat: fighters may not cast their spells."
        case .noHostilityTarget: "Hostility: no resident actor to act on."
        case let .hostility(actor, hostile):
            "Hostility: \(actor) is now \(hostile ? "hostile" : "neutral")."
        case let .scriptStarted(actor):
            "Combat: a script started \(actor.description) fighting the player."
        case let .scriptStopped(actor): "Combat: a script stopped \(actor.description) fighting."
        case let .assisted(actor, ally):
            "Combat: \(actor.description) joined to help \(ally.description)."
        }
    }
}
