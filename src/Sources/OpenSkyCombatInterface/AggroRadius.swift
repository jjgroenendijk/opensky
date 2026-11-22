// The aggro radius of the AI Data tab: an actor warns a stranger that comes near, and
// attacks one that comes nearer or stays. docs/engine/combat-behavior.md#aggro-radius.

import Foundation

/// The three distances of one actor, in game units. Zero switches a distance off.
nonisolated public struct AggroRadius: Equatable, Sendable {
    public var warn: Float
    public var warnOrAttack: Float
    public var attack: Float

    public init(warn: Float, warnOrAttack: Float, attack: Float) {
        self.warn = warn
        self.warnOrAttack = warnOrAttack
        self.attack = attack
    }
}

nonisolated public enum AggroZone: String, Equatable, Sendable {
    case outside
    case warn
    case warnOrAttack
    case attack
}

/// How far one actor's warning of its target has come.
nonisolated public struct AggroWatch: Equatable, Sendable {
    public var zone = AggroZone.outside
    /// Seconds since the watch began or the last warning.
    public var timer: Float = 0
    /// Warnings given inside the warn-or-attack distance.
    public var warnings = 0

    public init() {}
}

nonisolated public enum AggroRadiusRule {
    /// Seconds between two warnings.
    public static let warnInterval: Float = 5
    /// The actor attacks at the first interval that ends with more warnings than this.
    public static let maximumWarnings = 2

    /// The innermost zone that holds `distance`.
    public static func zone(distance: Float, radius: AggroRadius) -> AggroZone {
        guard distance.isFinite else { return .outside }
        if distance < radius.attack {
            return .attack
        }
        if distance < radius.warnOrAttack {
            return .warnOrAttack
        }
        return distance < radius.warn ? .warn : .outside
    }

    /// One step of the watch. The actor attacks at once inside the attack distance. Each
    /// interval ends in a warning, which counts only inside the warn-or-attack distance.
    public static func advance(
        _ watch: AggroWatch, zone: AggroZone, by seconds: Float
    ) -> (watch: AggroWatch, attacks: Bool) {
        guard zone != .outside else { return (AggroWatch(), false) }
        var next = watch
        next.zone = zone
        guard zone != .attack else { return (next, true) }
        next.timer += max(0, seconds)
        guard next.timer >= warnInterval else { return (next, false) }
        next.timer = 0
        if next.warnings > maximumWarnings {
            return (next, true)
        }
        if zone == .warnOrAttack {
            next.warnings += 1
        }
        return (next, false)
    }
}
