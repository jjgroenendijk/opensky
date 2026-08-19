// One actor value as a caller *reads* it (issue #468, roadmap item 19.5): a
// base value plus the three modifier slots the Creation Kit's own actor-value
// vocabulary names.
//
// The resolved view, not the stored one. `ActorValueOverride` is what the store
// actually holds — the same three modifiers over a base *offset* rather than an
// absolute base, so the derived baseline stays authoritative (issue #496).
//
// ## Why a base and three modifiers rather than one number
//
// The scripting surface distinguishes them by name, so a store that kept only
// the current number could not answer the questions the natives ask. The wiki
// states the split directly: "While GetActorValue returns the current value,
// SetActorValue sets the base value ... Any modifiers are left intact."
// (<https://www.creationkit.com/index.php?title=SetActorValue_-_Actor>) The
// three modifier slots are the three the same reference names —
// `ModActorValue` writes the permanent one, a magic effect writes the temporary
// one, and `DamageActorValue` writes the damage one
// (<https://www.creationkit.com/index.php?title=DamageActorValue_-_Actor>).
//
// The current value is therefore derived, never stored, which is the same rule
// `ActorValueState.hasZeroHealth` follows: a stored current value and a stored
// base can disagree, and after a save round trip there is no way to say which
// was right.
//
// ## Which slot means what
//
// * `base` — what the records author, what `SetActorValue` would write.
// * `permanent` — a lasting adjustment that outlives the thing that made it.
// * `temporary` — an active magic effect's contribution, which is why it is
//   the one slot the save deliberately does not carry (issue 19.6 owns the
//   effects that re-establish it).
// * `damage` — never positive. Damage lowers a value without touching its
//   base, and restoring puts the damage back toward zero rather than above it.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// Which of an actor value's three modifier slots a write lands in.
nonisolated enum ActorValueModifier: String, CaseIterable, Hashable, Sendable {
    /// `ModActorValue`'s slot: an adjustment with nothing keeping it alive.
    case permanent
    /// An active magic effect's slot, dropped by the save on purpose.
    case temporary
    /// `DamageActorValue`'s slot. Never positive.
    case damage
}

/// One actor value's stored state: a base plus its three modifiers.
///
/// Every stored number is finite, enforced in `init` rather than checked at use
/// sites, for the reason `ActorValueState`'s non-negative invariant is: one NaN
/// would spread through every later sum and a resistance query would answer
/// NaN rather than a fraction.
nonisolated struct ActorValueEntry: Equatable, Sendable {
    private(set) var base: Float
    private(set) var permanent: Float
    private(set) var temporary: Float
    private(set) var damage: Float

    init(base: Float = 0, permanent: Float = 0, temporary: Float = 0, damage: Float = 0) {
        self.base = Self.finite(base)
        self.permanent = Self.finite(permanent)
        self.temporary = Self.finite(temporary)
        // A positive damage modifier would be a heal wearing damage's name.
        self.damage = min(0, Self.finite(damage))
    }

    subscript(modifier: ActorValueModifier) -> Float {
        switch modifier {
        case .permanent: permanent
        case .temporary: temporary
        case .damage: damage
        }
    }

    /// What `GetActorValue` reports: the base plus every modifier.
    ///
    /// Not floored at zero. The mutations below never take a value below zero
    /// on their own, but a permanent modifier a caller sets outright may, and
    /// clamping here would hide that rather than let the caller see it.
    var current: Float {
        base + permanent + temporary + damage
    }

    /// The sum a damage modifier is measured against — everything that is not
    /// damage. `restore` cannot lift `current` above it.
    var undamagedValue: Float {
        base + permanent + temporary
    }

    /// This entry with its base replaced — `SetActorValue`'s effect, leaving
    /// every modifier intact.
    func settingBase(_ value: Float) -> ActorValueEntry {
        with { $0.base = Self.finite(value) }
    }

    /// This entry with one modifier replaced outright.
    func setting(_ modifier: ActorValueModifier, to value: Float) -> ActorValueEntry {
        with { entry in
            switch modifier {
            case .permanent: entry.permanent = Self.finite(value)
            case .temporary: entry.temporary = Self.finite(value)
            case .damage: entry.damage = min(0, Self.finite(value))
            }
        }
    }

    /// This entry with `delta` added to one modifier, which is what applying
    /// and removing an effect both do.
    func adding(_ delta: Float, to modifier: ActorValueModifier) -> ActorValueEntry {
        guard delta.isFinite else { return self }
        return setting(modifier, to: self[modifier] + delta)
    }

    /// This entry with `amount` taken off its current value through the damage
    /// modifier, floored so the current value does not go below zero.
    ///
    /// A non-positive or non-finite `amount` changes nothing rather than
    /// healing, mirroring `ActorValueState.damaging(_:by:)`.
    func damaging(by amount: Float) -> ActorValueEntry {
        guard amount.isFinite, amount > 0 else { return self }
        return with { $0.damage = max(-max(0, undamagedValue), damage - amount) }
    }

    /// This entry with `amount` of its damage undone, capped at no damage at
    /// all. Restoring never lifts a value above what its base and modifiers
    /// say, which is why it writes the damage slot rather than the base.
    func restoring(by amount: Float) -> ActorValueEntry {
        guard amount.isFinite, amount > 0 else { return self }
        return with { $0.damage = min(0, damage + amount) }
    }

    // MARK: - Private

    private func with(_ change: (inout ActorValueEntry) -> Void) -> ActorValueEntry {
        var copy = self
        change(&copy)
        return copy
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }
}
