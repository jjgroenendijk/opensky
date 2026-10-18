// When the game refuses to let the player wait or sleep. The reasons and their
// texts are the `sNoWait*` and `sNoSleep*` game settings listed on the CK wiki
// "Category:Settings" page. See docs/engine/sleep-wait.md.

import Foundation

nonisolated public enum RestRefusal: String, Equatable, Sendable, CaseIterable {
    case hostileActorsNear = "HostileActorsNear"
    case alarm = "WhileAlarm"
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
        case .inAir: "You cannot \(verb) in the air."
        case .takingHealthDamage: "You cannot \(verb) while taking health damage."
        }
    }
}

nonisolated public struct RestContext: Equatable, Sendable {
    public var inCombat = false
    public var hostilesNear = false
    public var alarmed = false
    public var inAir = false
    public var takingHealthDamage = false

    public init() {}
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
        if context.inAir {
            return .inAir
        }
        if context.takingHealthDamage {
            return .takingHealthDamage
        }
        return nil
    }
}
