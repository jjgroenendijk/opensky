// What one actor value's *stored* deviation looks like (issue #496, roadmap
// item 20.3): a base offset plus the three modifier slots, for every one of the
// 164 vanilla actor values including the three primaries.
//
// ## Why an offset rather than a base
//
// `ActorValueEntry` is the resolved view — an absolute base plus its modifiers,
// which is the vocabulary the Papyrus surface speaks. This is the stored view,
// and the two differ in exactly one field, deliberately.
//
// The derived baseline stays authoritative. A base write records *what the
// session did to the value*, never what the value is, so a level change, a race
// change or a reordered load order moves every actor value with the records it
// came from, and the session's own contribution rides on top unchanged. That is
// the same "re-derive, never persist" rule the primaries' maximums, the
// inventory baseline and the quest baseline already follow — stated once here
// because item 20.5's skill advancement and item 20.6's attribute picks both
// depend on it: a skill trained by five points is five points above whatever the
// records now author, so it survives re-derivation *and* still gains from a
// level-up, and neither can silently clobber the other.
//
// ## Which slot means what
//
// * `baseOffset` — what `SetActorValue` moves, as a delta from the derived
//   baseline. Zero for an actor nothing has explicitly written.
// * `permanent` — `ModActorValue`'s and `ForceActorValue`'s slot: an adjustment
//   with nothing keeping it alive.
// * `temporary` — an active magic effect's slot, which is why it is the one slot
//   the save deliberately does not carry (`ActiveEffectRuntime` re-establishes
//   it).
// * `damage` — never positive, and never written for a primary: a primary's
//   damage is the drop in its stored current value instead. See
//   docs/engine/actor-values.md.
//
// A modifier write states itself against `ActorValueEntry` and arrives here
// through `storing(_:baseline:)`, so there is one place an absolute base becomes
// an offset rather than two. Only the base *increment* is stated directly
// against the stored form, because adding to an offset needs no baseline and so
// cannot drift through one.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// One actor value's stored deviation from what its records author.
///
/// Every stored number is finite, enforced in `init` rather than checked at use
/// sites, for the reason `ActorValueEntry`'s invariant is: one NaN would spread
/// through every later sum and a resistance query would answer NaN rather than a
/// fraction.
nonisolated struct ActorValueOverride: Equatable, Sendable {
    /// Delta on top of the derived baseline. Never an absolute value.
    private(set) var baseOffset: Float
    private(set) var permanent: Float
    private(set) var temporary: Float
    private(set) var damage: Float

    init(baseOffset: Float = 0, permanent: Float = 0, temporary: Float = 0, damage: Float = 0) {
        self.baseOffset = Self.finite(baseOffset)
        self.permanent = Self.finite(permanent)
        self.temporary = Self.finite(temporary)
        // A positive damage modifier would be a heal wearing damage's name.
        self.damage = min(0, Self.finite(damage))
    }

    /// The override an actor has for a value nothing has touched.
    static let none = ActorValueOverride()

    /// Whether this override says nothing at all, which is what lets the store
    /// drop it rather than persist a no-op. An actor whose fire resistance was
    /// raised and then lowered again is an actor nothing happened to.
    var isEmpty: Bool {
        self == Self.none
    }

    /// Everything it adds to the value's *maximum* — the base offset and the
    /// two modifiers that raise or lower a ceiling, with damage left out
    /// because damage lowers a current value and never a maximum.
    var maximumOffset: Float {
        baseOffset + permanent + temporary
    }

    /// This override as the resolved entry a caller reads, given the value's
    /// re-derived baseline.
    func resolved(baseline: Float) -> ActorValueEntry {
        ActorValueEntry(
            base: baseline + baseOffset,
            permanent: permanent,
            temporary: temporary,
            damage: damage
        )
    }

    /// The override that stores `entry` against `baseline` — the inverse of
    /// `resolved(baseline:)`, and the only place an absolute base becomes an
    /// offset.
    static func storing(_ entry: ActorValueEntry, baseline: Float) -> ActorValueOverride {
        ActorValueOverride(
            baseOffset: entry.base - baseline,
            permanent: entry.permanent,
            temporary: entry.temporary,
            damage: entry.damage
        )
    }

    /// This override with `delta` added to its base offset, which is what a
    /// skill advance and an attribute pick both do.
    func addingBaseOffset(_ delta: Float) -> ActorValueOverride {
        guard delta.isFinite else { return self }
        return with { $0.baseOffset = Self.finite(baseOffset + delta) }
    }

    // MARK: - Private

    private func with(_ change: (inout ActorValueOverride) -> Void) -> ActorValueOverride {
        var copy = self
        change(&copy)
        return copy
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }
}
