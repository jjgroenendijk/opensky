// Owned perks per actor for `HasPerk`. See docs/engine/perks.md and
// docs/engine/condition-functions.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// Every actor's owned perks plus the PERK store the parameter resolves against.
nonisolated public struct PerkConditionResolution: Sendable {
    public let facts: ActorConditionFacts<PerkStore, Set<ReferenceKey>>

    public static let empty = PerkConditionResolution()

    public init(
        store: PerkStore? = nil,
        sourcePlugin: String? = nil,
        owned: [ReferenceKey: Set<ReferenceKey>] = [:]
    ) {
        facts = ActorConditionFacts(store: store, sourcePlugin: sourcePlugin, facts: owned)
    }

    public func key(of formID: FormID) -> ReferenceKey? {
        facts.key(of: formID)
    }

    /// Nil when no perk data is wired. An actor with no entry owns nothing:
    /// every actor starts there.
    public func owns(_ perk: ReferenceKey, on actor: ReferenceKey) -> Bool? {
        guard facts.isAvailable else { return nil }
        return facts.fact(of: actor)?.contains(perk) ?? false
    }
}

nonisolated extension PerkConditionResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    /// Empty when no perk runtime is wired, so `HasPerk` is a reason-tagged
    /// false rather than an actor who has taken nothing.
    public var perks: PerkConditionResolution {
        get { self[resolution: PerkConditionResolution.self] }
        set { self[resolution: PerkConditionResolution.self] = newValue }
    }
}
