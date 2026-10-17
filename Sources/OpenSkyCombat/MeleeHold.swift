// Turns an attack press and how long it is held into the graph event to raise:
// a swing, a power attack, a bash, or a power bash. A pure value type over the
// frame's intent; the runtime raises what it answers. See docs/engine/melee-combat.md.

import Foundation

/// What the swing in progress is.
nonisolated public enum MeleeStrikeKind: String, Equatable, Sendable {
    case normal
    case power
    case bash
    case powerBash

    public var isPowerAttack: Bool {
        self == .power || self == .powerBash
    }

    public var isBash: Bool {
        self == .bash || self == .powerBash
    }
}

/// Which way the player moves when a power attack starts, which picks its clip.
nonisolated public enum MeleePowerDirection: Equatable, Sendable {
    case inPlace, forward, backward, left, right

    public init(moveForward: Float, moveRight: Float) {
        if abs(moveForward) >= abs(moveRight), abs(moveForward) > 0.1 {
            self = moveForward > 0 ? .forward : .backward
        } else if abs(moveRight) > 0.1 {
            self = moveRight > 0 ? .right : .left
        } else {
            self = .inPlace
        }
    }

    /// The `0_master.hkx` event that starts this power attack.
    public var eventName: String {
        switch self {
        case .inPlace: CombatGraphNames.attackPowerStartInPlace
        case .forward: CombatGraphNames.attackPowerStartForward
        case .backward: CombatGraphNames.attackPowerStartBackward
        case .left: CombatGraphNames.attackPowerStartLeft
        case .right: CombatGraphNames.attackPowerStartRight
        }
    }
}

/// What a press became once it was released or held long enough.
nonisolated public enum MeleeHoldOutcome: Equatable, Sendable {
    /// Released early: a swing, or a bash with the guard up.
    case tapped(MeleeStrikeKind)
    /// Held past the delay: a power attack or a power bash, still to be paid for.
    case held(MeleeStrikeKind)
}

/// The hold clock of the attack button. A press waits for its release or the
/// power-attack delay, so a power attack never has to interrupt a started swing.
nonisolated public struct MeleeHold: Equatable, Sendable {
    /// The INI `fInitialPowerAttackDelay` default: a press held this long powers up.
    public static let powerAttackDelay: Float = 0.3

    public private(set) var heldSeconds: Float = 0
    public private(set) var coolDownLeft: Float = 0
    /// The press waiting for its outcome, or nil.
    public private(set) var pending: MeleeStrikeKind?

    public init() {}

    /// A press with the guard down starts a swing, with it up a bash.
    public mutating func pressed(asBash: Bool) {
        pending = asBash ? .bash : .normal
        heldSeconds = 0
    }

    /// Advances the clock by one frame. Answers once per press.
    public mutating func advance(held: Bool, deltaTime: Float) -> MeleeHoldOutcome? {
        let step = deltaTime.isFinite ? max(0, deltaTime) : 0
        coolDownLeft = max(0, coolDownLeft - step)
        guard let kind = pending else { return nil }
        guard held else {
            pending = nil
            return .tapped(kind)
        }
        heldSeconds += step
        guard heldSeconds >= Self.powerAttackDelay else { return nil }
        pending = nil
        if kind == .bash {
            return .held(.powerBash)
        }
        return coolDownLeft > 0 ? .tapped(.normal) : .held(.power)
    }

    /// A power attack started; the next one waits `coolDown` seconds.
    public mutating func startedPowerAttack(coolDown: Float) {
        coolDownLeft = coolDown.isFinite ? max(0, coolDown) : 0
    }

    public mutating func reset() {
        self = Self()
    }
}
