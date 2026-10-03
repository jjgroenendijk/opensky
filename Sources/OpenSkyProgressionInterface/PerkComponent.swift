// The perks one actor owns, as a world-state component. It stores identities
// only: each rank is its own PERK record joined by `NNAM`, and
// `PerkRuntime.rank(inChainFrom:on:)` walks the chain. The NPC_ `PRKR` rank byte
// is "no longer in use" (UESP). Dropped once empty. See docs/engine/perks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One actor's owned perks, in ascending key order.
///
/// Ordered rather than a set so the save writes the same bytes twice for the
/// same state, which is the rule `SpellbookState.known` already follows.
nonisolated public struct PerkState: WorldStateComponent, Sendable {
    public private(set) var owned: [ReferenceKey]

    public static var componentKind: WorldStateComponentKind {
        .perks
    }

    /// True when the actor owns nothing, which is when the store drops the slot
    /// rather than keeping an empty component around.
    public var isEmpty: Bool {
        owned.isEmpty
    }

    public var count: Int {
        owned.count
    }

    /// Normalizes on the way in, so a save from another load order restores a valid
    /// component. A key the load order no longer resolves is kept, so removing a
    /// plugin does not destroy progress.
    public init(owned: [ReferenceKey] = []) {
        self.owned = Set(owned).sorted()
    }

    public func owns(_ perk: ReferenceKey) -> Bool {
        owned.contains(perk)
    }

    public func adding(_ perk: ReferenceKey) -> PerkState {
        guard !owns(perk) else { return self }
        return PerkState(owned: owned + [perk])
    }

    public func removing(_ perk: ReferenceKey) -> PerkState {
        guard owns(perk) else { return self }
        return PerkState(owned: owned.filter { $0 != perk })
    }
}

nonisolated extension WorldStateComponentKind {
    /// The perks one actor owns. A slot of its own for the reason `spellbook` is
    /// one: owning a perk changes on a level-up, a script call or an actor's first
    /// appearance, never per frame, while the actor values a perk goes on to modify
    /// are rewritten sixty times a second.
    public static let perks = Self(rawValue: "perks", order: 15, affectsCellBuild: false)
}
