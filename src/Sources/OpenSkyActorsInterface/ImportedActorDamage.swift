// Damage an imported Skyrim save says an actor carries. The import cannot read the
// actor's maximums, so it keeps the damage, and the actor value runtime takes it off
// the maximums the first time it reads the actor (docs/engine/ess-import.md).

import Foundation
public import OpenSkyGameData
public import OpenSkyWorldState

nonisolated public struct ImportedActorDamage: WorldStateComponent, Sendable {
    /// Damage taken off each maximum; never negative.
    public let amounts: ActorValues

    public static var componentKind: WorldStateComponentKind {
        .importedActorDamage
    }

    /// A value that is negative or not finite becomes 0.
    public init(amounts: ActorValues) {
        var clean = ActorValues.zero
        for kind in ActorValueKind.allCases {
            let value = amounts[kind]
            clean[kind] = value.isFinite ? max(0, value) : 0
        }
        self.amounts = clean
    }

    /// The full state of an actor with `maximums`, less this damage, floored at zero.
    public func applied(to maximums: ActorValues) -> ActorValueState {
        var current = maximums
        for kind in ActorValueKind.allCases {
            current[kind] = max(0, maximums[kind] - amounts[kind])
        }
        return ActorValueState(current: current)
    }
}

nonisolated extension WorldStateComponentKind {
    /// Damage from an imported save, until the actor value runtime first writes the
    /// actor. Keyed by the actor.
    public static let importedActorDamage = Self(
        rawValue: "importedActorDamage", order: 52, affectsCellBuild: false
    )
}
