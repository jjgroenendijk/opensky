// The perks one actor owns, as a world-state component (issue #497, roadmap
// item 20.4).
//
// ## Why a flat set of records rather than a perk-and-rank table
//
// A multi-rank perk is a chain of separate PERK records joined by `NNAM`, and
// the game adds the record for the rank it wants: taking the second rank of
// Armsman adds `Armsman20`, whose own conditions turn the previous rank off
// (`Armsman00` carries `HasPerk Armsman20 == 0` on its perk-owner condition
// tab, read off this machine's install). So "which rank does this actor have"
// is a question about *which records it owns*, and storing a rank number beside
// a chain head would be a second source of truth that the record conditions
// would immediately disagree with.
//
// Rank therefore lives in `PerkRuntime.rank(inChainFrom:on:)`, which walks the
// `NNAM` chain through `PerkStore` and counts what this component holds. The
// component itself stores nothing but identities.
//
// The NPC_ `PRKR` rank byte is not stored either, for the same reason UESP
// gives for it: "uint8 Rank (no longer in use)"
// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_>).
//
// The component is dropped entirely once it empties, exactly as `SpellbookState`
// is, so an actor that owns no perk stops being dirty for this slot.
//
// Documented in docs/engine/perks.md.

import Foundation

/// One actor's owned perks, in ascending key order.
///
/// Ordered rather than a set so the save writes the same bytes twice for the
/// same state, which is the rule `SpellbookState.known` already follows.
nonisolated struct PerkState: WorldStateComponent {
    private(set) var owned: [ReferenceKey]

    static var componentKind: WorldStateComponentKind {
        .perks
    }

    var erased: WorldStateComponentValue {
        .perks(self)
    }

    /// True when the actor owns nothing, which is when the store drops the slot
    /// rather than keeping an empty component around.
    var isEmpty: Bool {
        owned.isEmpty
    }

    var count: Int {
        owned.count
    }

    /// Normalizes on the way in, which is what makes this the save decoder's
    /// entry point: duplicates collapse and order becomes key order, so a file
    /// written under a different load order still restores a valid component.
    ///
    /// A key this load order no longer resolves is *kept*. Losing it would make
    /// removing a plugin destroy progress, and it is invisible to every query
    /// that goes through `PerkStore` anyway — the same rule `SpellbookState`
    /// applies to a known spell.
    init(owned: [ReferenceKey] = []) {
        self.owned = Set(owned).sorted()
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .perks(value) = erased else { return nil }
        self = value
    }

    func owns(_ perk: ReferenceKey) -> Bool {
        owned.contains(perk)
    }

    func adding(_ perk: ReferenceKey) -> PerkState {
        guard !owns(perk) else { return self }
        return PerkState(owned: owned + [perk])
    }

    func removing(_ perk: ReferenceKey) -> PerkState {
        guard owns(perk) else { return self }
        return PerkState(owned: owned.filter { $0 != perk })
    }
}
