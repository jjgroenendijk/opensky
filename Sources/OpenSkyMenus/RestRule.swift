// When the game refuses to let the player wait or sleep. The reasons and their
// texts are the `sNoWait*` and `sNoSleep*` game settings listed on the CK wiki
// "Category:Settings" page. See docs/engine/sleep-wait.md.

import Foundation

nonisolated public enum RestRefusal: String, Equatable, Sendable, CaseIterable {
    case hostileActorsNear = "HostileActorsNear"
    case alarm = "WhileAlarm"
    case trespass = "Trespass"
    /// Sleep only: the bed belongs to someone else.
    case ownedBed = "InOwnedBed"
    case inAir = "InAir"
    case takingHealthDamage = "TakingHealthDamage"

    /// The game setting that holds the text, such as `sNoWaitInAir`.
    public func settingEditorID(sleeping: Bool) -> String {
        "sNo\(sleeping ? "Sleep" : "Wait")\(rawValue)"
    }

    /// The text when the load order has no such setting.
    public func fallbackText(sleeping: Bool) -> String {
        let verb = sleeping ? "sleep" : "wait"
        return switch self {
        case .hostileActorsNear: "You cannot \(verb) when enemies are nearby."
        case .alarm: "You cannot \(verb) while guards are pursuing you."
        case .trespass: "You cannot \(verb) while trespassing."
        case .ownedBed: "You cannot sleep in an owned bed."
        case .inAir: "You cannot \(verb) in the air."
        case .takingHealthDamage: "You cannot \(verb) while taking health damage."
        }
    }
}

nonisolated public struct RestContext: Equatable, Sendable {
    public var inCombat = false
    public var hostilesNear = false
    public var alarmed = false
    public var trespassing = false
    /// The bed the player chose belongs to someone else. False for the wait key.
    public var bedOwnedByOther = false
    public var inAir = false
    public var takingHealthDamage = false

    public init() {}
}

/// The game hours at which a rest of `hours` stops to update the world.
nonisolated public enum RestTimeSteps {
    public static let stepHours = 0.25

    /// Ends of each step since the start, the last one exactly `hours`.
    public static func steps(hours: Int) -> [Double] {
        let count = Int((Double(max(0, hours)) / stepHours).rounded(.up))
        return (0 ..< count).map { Swift.min(Double($0 + 1) * stepHours, Double(hours)) }
    }
}

nonisolated public enum RestRule {
    /// The first reason the player may not rest, or nil when resting is allowed.
    public static func refusal(_ context: RestContext) -> RestRefusal? {
        if context.inCombat || context.hostilesNear {
            return .hostileActorsNear
        }
        if context.alarmed {
            return .alarm
        }
        if context.trespassing {
            return .trespass
        }
        if context.bedOwnedByOther {
            return .ownedBed
        }
        if context.inAir {
            return .inAir
        }
        if context.takingHealthDamage {
            return .takingHealthDamage
        }
        return nil
    }
}
