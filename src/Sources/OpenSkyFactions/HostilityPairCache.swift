// The answers `FactionCoordinator` keeps per ordered actor pair, and when they expire.
// See docs/engine/hostility.md#memberships-at-runtime.

import OpenSkyActorsInterface
public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated struct HostilityPair: Hashable, Sendable {
    let observer: ReferenceKey
    let target: ReferenceKey
}

nonisolated struct HostilityPairAnswer: Equatable, Sendable {
    let decision: HostilityDecision
    let factionReaction: ActorReaction
}

nonisolated struct HostilityPairCache: Sendable {
    /// The components the derivation reads: memberships, relationship ranks, and the
    /// stored hostility override.
    static let readKinds = [
        ActorFactionState.componentKind, ActorRelationshipState.componentKind,
        ActorCombatState.componentKind
    ]

    private(set) var revision: UInt64?
    var answers: [HostilityPair: HostilityPairAnswer] = [:]

    /// Drops every answer when the store moved on since they were worked out.
    mutating func expire(revision current: UInt64) {
        guard revision != current else { return }
        answers.removeAll(keepingCapacity: true)
        revision = current
    }

    mutating func reset() {
        answers.removeAll(keepingCapacity: true)
    }
}
