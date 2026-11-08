// One actor value as a caller reads it: a base plus the permanent, temporary and
// damage modifiers the Creation Kit names. "GetActorValue returns the current
// value, SetActorValue sets the base value" (<https://ck.uesp.net/wiki/SetActorValue_-_Actor>),
// so the current value is derived, never stored. `damage` is never positive, and
// the save skips `temporary`, which active effects rebuild. `ActorValueOverride` is
// the stored form. See docs/engine/actor-value-store.md.

import Foundation

/// Which of an actor value's three modifier slots a write lands in.
nonisolated public enum ActorValueModifier: String, CaseIterable, Hashable, Sendable {
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
nonisolated public struct ActorValueEntry: Equatable, Sendable {
    public private(set) var base: Float
    public private(set) var permanent: Float
    public private(set) var temporary: Float
    public private(set) var damage: Float

    public init(base: Float = 0, permanent: Float = 0, temporary: Float = 0, damage: Float = 0) {
        self.base = Self.finite(base)
        self.permanent = Self.finite(permanent)
        self.temporary = Self.finite(temporary)
        // A positive damage modifier would be a heal wearing damage's name.
        self.damage = min(0, Self.finite(damage))
    }

    public subscript(modifier: ActorValueModifier) -> Float {
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
    public var current: Float {
        base + permanent + temporary + damage
    }

    /// The sum a damage modifier is measured against — everything that is not
    /// damage. `restore` cannot lift `current` above it.
    public var undamagedValue: Float {
        base + permanent + temporary
    }

    /// This entry with its base replaced — `SetActorValue`'s effect, leaving
    /// every modifier intact.
    public func settingBase(_ value: Float) -> ActorValueEntry {
        with { $0.base = Self.finite(value) }
    }

    /// This entry with one modifier replaced outright.
    public func setting(_ modifier: ActorValueModifier, to value: Float) -> ActorValueEntry {
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
    public func adding(_ delta: Float, to modifier: ActorValueModifier) -> ActorValueEntry {
        guard delta.isFinite else { return self }
        return setting(modifier, to: self[modifier] + delta)
    }

    /// This entry with `amount` taken off its current value through the damage
    /// modifier, floored so the current value does not go below zero.
    ///
    /// A non-positive or non-finite `amount` changes nothing rather than
    /// healing, mirroring `ActorValueState.damaging(_:by:)`.
    public func damaging(by amount: Float) -> ActorValueEntry {
        guard amount.isFinite, amount > 0 else { return self }
        return with { $0.damage = max(-max(0, undamagedValue), damage - amount) }
    }

    /// This entry with `amount` of its damage undone, capped at no damage at
    /// all. Restoring never lifts a value above what its base and modifiers
    /// say, which is why it writes the damage slot rather than the base.
    public func restoring(by amount: Float) -> ActorValueEntry {
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
