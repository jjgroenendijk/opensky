// 678 `ShouldAttackKill`, from xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas: whether the
// attack starting now would kill its target (<https://ck.uesp.net/wiki/ShouldAttackKill>).
// The kill-move idles test it. See docs/engine/paired-animations.md#kill-moves.

import Foundation
import OpenSkyFormatsESM

/// Whether the attack the caller is weighing kills its target: the attacker, the target,
/// and the answer the combat damage rules gave.
nonisolated public struct AttackKillResolution: Sendable {
    public static let empty = AttackKillResolution(attacks: [])

    public struct Attack: Equatable, Sendable {
        public let attacker: ReferenceKey
        public let target: ReferenceKey
        public let kills: Bool

        public init(attacker: ReferenceKey, target: ReferenceKey, kills: Bool) {
            self.attacker = attacker
            self.target = target
            self.kills = kills
        }
    }

    private let attacks: [Attack]

    public init(attacks: [Attack]) {
        self.attacks = attacks
    }

    /// A nil `target` reads the attacker's own attack, as the vanilla kill-move idles
    /// leave the parameter empty.
    public func kills(_ attacker: ReferenceKey, _ target: ReferenceKey?) -> Bool? {
        attacks.first { $0.attacker == attacker && (target == nil || $0.target == target) }?
            .kills
    }
}

nonisolated extension AttackKillResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    public var attackKills: AttackKillResolution {
        get { self[resolution: AttackKillResolution.self] }
        set { self[resolution: AttackKillResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    public static func installAttack(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 678, name: "ShouldAttackKill", parameter1: .formID
        ) { call in
            let named = (call.parameter1?.rawValue ?? 0) != 0
            let target = named ? parameterReference(call) : nil
            if named, target == nil {
                return .failure(.unresolvedParameter(678))
            }
            return call.referenceKey().flatMap { attacker in
                guard let kills = call.context.attackKills.kills(attacker, target) else {
                    return .failure(.unavailableData(.attack))
                }
                return .success(kills ? 1 : 0)
            }
        })
    }
}
