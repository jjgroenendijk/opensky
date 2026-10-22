// When the game refuses to let the player wait or sleep. The reasons and their
// texts are the `sNoWait*` and `sNoSleep*` game settings listed on the CK wiki
// "Category:Settings" page. See docs/engine/sleep-wait.md.

import Foundation
import OpenSkyGameData

nonisolated public enum RestRefusal: String, Equatable, Sendable, CaseIterable {
    case hostileActorsNear = "HostileActorsNear"
    case alarm = "WhileAlarm"
    /// A trespass warning was given and the player has not left yet.
    case warnedToLeave = "WarnToLeave"
    case trespass = "Trespass"
    /// Sleep only: the bed belongs to someone else.
    case ownedBed = "InOwnedBed"
    case inAir = "InAir"
    case takingHealthDamage = "TakingHealthDamage"

    /// The game setting that holds the text, such as `sNoWaitInAir`.
    public func settingEditorID(sleeping: Bool) -> String {
        text(sleeping: sleeping).rawValue
    }

    public func text(sleeping: Bool) -> RestText {
        switch self {
        case .hostileActorsNear: sleeping ? .sleepHostileActorsNear : .waitHostileActorsNear
        case .alarm: sleeping ? .sleepWhileAlarm : .waitWhileAlarm
        case .warnedToLeave: sleeping ? .sleepWarnToLeave : .waitWarnToLeave
        case .trespass: sleeping ? .sleepTrespass : .waitTrespass
        case .ownedBed: .sleepInOwnedBed
        case .inAir: sleeping ? .sleepInAir : .waitInAir
        case .takingHealthDamage: sleeping ? .sleepTakingHealthDamage : .waitTakingHealthDamage
        }
    }
}

/// The refusal texts of the rest and wait menus.
nonisolated public enum RestText: String, GameSettingTextKey {
    case sleepHostileActorsNear = "sNoSleepHostileActorsNear"
    case sleepWhileAlarm = "sNoSleepWhileAlarm"
    case sleepWarnToLeave = "sNoSleepWarnToLeave"
    case sleepTrespass = "sNoSleepTrespass"
    case sleepInOwnedBed = "sNoSleepInOwnedBed"
    case sleepInAir = "sNoSleepInAir"
    case sleepTakingHealthDamage = "sNoSleepTakingHealthDamage"
    case waitHostileActorsNear = "sNoWaitHostileActorsNear"
    case waitWhileAlarm = "sNoWaitWhileAlarm"
    case waitWarnToLeave = "sNoWaitWarnToLeave"
    case waitTrespass = "sNoWaitTrespass"
    case waitInAir = "sNoWaitInAir"
    case waitTakingHealthDamage = "sNoWaitTakingHealthDamage"

    public var fallback: String {
        let verb = rawValue.hasPrefix("sNoSleep") ? "rest" : "wait"
        return switch self {
        case .sleepHostileActorsNear, .waitHostileActorsNear:
            "Enemies are near; you cannot \(verb)."
        case .sleepWhileAlarm, .waitWhileAlarm: "Guards are after you; you cannot \(verb)."
        case .sleepWarnToLeave, .waitWarnToLeave: "You were told to leave; you cannot \(verb)."
        case .sleepTrespass, .waitTrespass: "You are trespassing; you cannot \(verb)."
        case .sleepInOwnedBed: "This bed is not yours."
        case .sleepInAir, .waitInAir: "You cannot \(verb) in the air."
        case .sleepTakingHealthDamage, .waitTakingHealthDamage:
            "You are losing health; you cannot \(verb)."
        }
    }
}

nonisolated public struct RestContext: Equatable, Sendable {
    public var inCombat = false
    public var hostilesNear = false
    public var alarmed = false
    public var trespassing = false
    /// A trespass warning is running and the grace period has not ended.
    public var warnedToLeave = false
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
        if context.warnedToLeave {
            return .warnedToLeave
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
