// The one place a condition asks "does this actor own that perk?" (issue #497,
// roadmap item 20.4), mirroring `MagicConditionResolution` and
// `ActorStateResolution`.
//
// Shaped as a resolved snapshot rather than as a live handle for the reason
// every other seam on `ConditionContext` is: the evaluator is a nonisolated
// value a build thread may run, so a condition body cannot reach into
// `WorldStateStore` or `PerkRuntime`. The caller that *is* on the main actor
// reads the component and hands the result over.
//
// The store rides along beside the per-actor sets because `HasPerk` takes a
// FormID parameter that has to be resolved against the load order before it can
// be compared, exactly as the magic seam's does.
//
// Documented in docs/engine/perks.md and docs/formats/conditions.md.

import Foundation

/// Every actor's owned perks plus the store their FormID parameters resolve
/// against.
///
/// `@unchecked Sendable` for the reason `MagicConditionResolution` is: the store
/// is an immutable value snapshot built once at load, and only its
/// `RecordIndex` back-reference keeps it from being checked automatically.
nonisolated struct PerkConditionResolution: @unchecked Sendable {
    /// Load-order PERK lookup, for the `ptPerk` parameter. Nil in a session with
    /// no perk data, which is what makes `HasPerk` report a gap rather than
    /// answering "does not own it" for every actor in the game.
    let store: PerkStore?
    /// The plugin a condition's FormID parameters are spelled against.
    let sourcePlugin: String?

    private let owned: [ReferenceKey: Set<ReferenceKey>]

    static let empty = PerkConditionResolution()

    init(
        store: PerkStore? = nil,
        sourcePlugin: String? = nil,
        owned: [ReferenceKey: Set<ReferenceKey>] = [:]
    ) {
        self.store = store
        self.sourcePlugin = sourcePlugin
        self.owned = owned
    }

    /// Whether the seam can answer at all: a session with no PERK store cannot,
    /// and says so rather than answering false everywhere.
    var isAvailable: Bool {
        store != nil
    }

    /// One FormID parameter as the runtime identity the component stores.
    ///
    /// The record has to exist, not merely resolve. Plugin-relative resolution
    /// answers with an identity for any FormID whose plugin is loaded, so a
    /// parameter naming a perk no plugin defines would otherwise come back as
    /// an ordinary key and read as "this actor does not have it" — which is a
    /// different answer from "this engine has no such perk". The keyword seam
    /// applies the same rule for the same reason.
    func key(of formID: FormID) -> ReferenceKey? {
        guard
            let sourcePlugin,
            let store,
            let resolved = store.resolvedID(formID, fromPlugin: sourcePlugin),
            store.perk(resolved) != nil
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }

    /// Whether `actor` owns `perk`, or nil when no perk data is wired.
    ///
    /// An actor with no entry owns nothing, which is a real answer rather than
    /// a gap: not having taken a perk is the normal state, and every actor in
    /// the game starts there.
    func owns(_ perk: ReferenceKey, on actor: ReferenceKey) -> Bool? {
        guard isAvailable else { return nil }
        return owned[actor]?.contains(perk) ?? false
    }

    /// The perks `actor` owns, empty for an actor that owns none.
    func perks(of actor: ReferenceKey) -> Set<ReferenceKey> {
        owned[actor] ?? []
    }
}
