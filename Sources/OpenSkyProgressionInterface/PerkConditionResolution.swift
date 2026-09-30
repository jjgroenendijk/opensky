// Whether an actor owns a perk, for conditions: a snapshot the main actor
// builds, like `MagicConditionResolution`. The store rides along, because
// `HasPerk`'s FormID parameter must be resolved against the load order.
// See docs/engine/perks.md and docs/engine/condition-functions.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// Every actor's owned perks plus the store their FormID parameters resolve
/// against.
///
/// `@unchecked Sendable` for the reason `MagicConditionResolution` is: the store
/// is an immutable value snapshot built once at load, and only its
/// `RecordIndex` back-reference keeps it from being checked automatically.
nonisolated public struct PerkConditionResolution: @unchecked Sendable, Sendable {
    /// Load-order PERK lookup, for the `ptPerk` parameter. Nil in a session with
    /// no perk data, which is what makes `HasPerk` report a gap rather than
    /// answering "does not own it" for every actor in the game.
    public let store: PerkStore?
    /// The plugin a condition's FormID parameters are spelled against.
    public let sourcePlugin: String?

    private let owned: [ReferenceKey: Set<ReferenceKey>]

    public static let empty = PerkConditionResolution()

    public init(
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
    public var isAvailable: Bool {
        store != nil
    }

    /// One FormID parameter as the runtime identity the component stores. The record
    /// must exist, not just resolve, so "no such perk" differs from "not owned".
    public func key(of formID: FormID) -> ReferenceKey? {
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
    public func owns(_ perk: ReferenceKey, on actor: ReferenceKey) -> Bool? {
        guard isAvailable else { return nil }
        return owned[actor]?.contains(perk) ?? false
    }
}

nonisolated extension PerkConditionResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    /// Owned perks per actor plus the PERK store `HasPerk`'s parameter resolves
    /// against. Empty when no perk runtime is wired, which makes
    /// `HasPerk` a reason-tagged false rather than an actor who has taken
    /// nothing.
    public var perks: PerkConditionResolution {
        get { self[resolution: PerkConditionResolution.self] }
        set {
            self[resolution: PerkConditionResolution.self] = newValue
        }
    }
}
