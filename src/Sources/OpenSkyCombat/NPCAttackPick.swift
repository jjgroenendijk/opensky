// Which ATKD attack an NPC starts: a weighted pick over its attack list, and the cone a
// target must be inside. Rules: docs/engine/attack-data.md ("The AI's pick", "The hit cone").

import Foundation
public import OpenSkyFormatsESM

/// One attack an NPC may start: its `ATKE` event and its `ATKD` values.
nonisolated public struct NPCAttack: Equatable, Sendable {
    public var event: String
    public var data: RaceAttack.Properties

    public init(event: String, data: RaceAttack.Properties) {
        self.event = event
        self.data = data
    }

    public var isPowerAttack: Bool {
        data.flags.contains(.powerAttack)
    }

    public var isBash: Bool {
        data.flags.contains(.bash)
    }

    public var isLeftHand: Bool {
        data.flags.contains(.leftHand)
    }
}

/// What the pick reads about the fight at the moment of the choice.
nonisolated public struct NPCAttackSituation: Equatable, Sendable {
    /// Which part of the list the pick draws from.
    public enum Pool: Equatable, Sendable {
        /// Every attack that is neither a bash nor a left-hand attack.
        case general
        /// Power attacks only.
        case powerOnly
        case bash
        case leftHand
    }

    public var pool = Pool.general
    public var targetIsStaggered = false
    /// The target blocks with the attacker inside its block cone.
    public var targetBlocksTowardAttacker = false
    public var stamina: Float = 1
    /// Seconds since each attack event was last used; a missing event was never used.
    public var secondsSinceUse: [String: Float] = [:]
    /// The attacker's combat style multipliers.
    public var weights = NPCAttackWeights()

    public init() {}
}

/// The `CSME` weights the pick multiplies by.
nonisolated public struct NPCAttackWeights: Equatable, Sendable {
    public var attackStaggered: Float = 1
    public var powerAttackStaggered: Float = 1
    public var powerAttackBlocking: Float = 1

    public init() {}

    public init(style: CombatStyle?) {
        guard let style else { return }
        attackStaggered = style.value(.attackStaggeredMultiplier) ?? 1
        powerAttackStaggered = style.value(.powerAttackStaggeredMultiplier) ?? 1
        powerAttackBlocking = style.value(.powerAttackBlockingMultiplier) ?? 1
    }
}

nonisolated public enum NPCAttackPick {
    /// The attacks of `list` that may start now, with their weights. An attack whose
    /// recovery time has not passed, or that costs stamina while Stamina is 0 or less, is
    /// left out, and so is a weight of 0 or less.
    public static func candidates(
        _ list: [RaceAttack], situation: NPCAttackSituation
    ) -> [(attack: NPCAttack, weight: Float)] {
        let weights = situation.weights
        return list.compactMap { entry -> (NPCAttack, Float)? in
            guard let event = entry.event, let data = entry.properties else { return nil }
            let attack = NPCAttack(event: event, data: data)
            guard inPool(attack, situation.pool) else { return nil }
            if
                let since = situation.secondsSinceUse[event.lowercased()],
                since < data.recoveryTime
            {
                return nil
            }
            if costsStamina(attack), situation.stamina <= 0 {
                return nil
            }
            var weight = data.attackChance
            if situation.targetIsStaggered {
                weight *= attack.isPowerAttack ? weights.powerAttackStaggered
                    : weights.attackStaggered
            } else if situation.targetBlocksTowardAttacker, attack.isPowerAttack {
                weight *= weights.powerAttackBlocking
            }
            guard weight.isFinite, weight > 0 else { return nil }
            return (attack, weight)
        }
    }

    /// The cone share of the strike angle the pick tests against.
    public static let pickConeMultiplier: Float = 0.67

    /// The whole pick: a weighted draw, a second roll at or below the weight, and the
    /// cone test, with a failed attack removed before the next draw. `roll` gives a
    /// value in 0 ..< 1 each call.
    public static func choose(
        _ list: [RaceAttack], situation: NPCAttackSituation,
        aim: (heading: Float, directionToTarget: Float), roll: () -> Float
    ) -> NPCAttack? {
        var options = candidates(list, situation: situation)
        while !options.isEmpty {
            let index = draw(options.map(\.weight), roll: roll())
            let option = options[index]
            let accepted = roll() <= option.weight
                && isInCone(
                    option.attack.data, heading: aim.heading,
                    directionToTarget: aim.directionToTarget, mult: pickConeMultiplier
                )
            if accepted {
                return option.attack
            }
            options.remove(at: index)
        }
        return nil
    }

    static func draw(_ weights: [Float], roll: Float) -> Int {
        let total = weights.reduce(0, +)
        var threshold = min(max(roll, 0), 0.999_999) * total
        for (index, weight) in weights.enumerated() {
            if threshold < weight {
                return index
            }
            threshold -= weight
        }
        return weights.count - 1
    }

    /// Whether `target` lies inside the attack's cone: within the strike angle times
    /// `mult` of the attacker's heading, turned by the attack angle unless the attack
    /// rotates. Angles in degrees; `heading` and `direction` in radians.
    public static func isInCone(
        _ attack: RaceAttack.Properties, heading: Float, directionToTarget: Float, mult: Float
    ) -> Bool {
        let turn = attack.flags.contains(.rotating) ? 0 : attack.attackAngle * .pi / 180
        let difference = remainder(heading + turn - directionToTarget, 2 * .pi)
        return abs(difference) <= attack.strikeAngle * mult * .pi / 180
    }

    private static func inPool(_ attack: NPCAttack, _ pool: NPCAttackSituation.Pool) -> Bool {
        switch pool {
        case .general: !attack.isBash && !attack.isLeftHand
        case .powerOnly: attack.isPowerAttack && !attack.isBash && !attack.isLeftHand
        case .bash: attack.isBash
        case .leftHand: attack.isLeftHand && !attack.isBash
        }
    }

    private static func costsStamina(_ attack: NPCAttack) -> Bool {
        attack.isBash || attack.isPowerAttack
    }
}
