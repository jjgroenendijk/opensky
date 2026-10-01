// One actor value's stored deviation: a base offset plus three modifier slots.
// An offset and not a base, so the records stay authoritative: a level-up or a new
// load order still moves the value, and the session's change rides on top. The save
// skips `temporary`, and a primary's damage lives in its current value instead.
// `storing(_:baseline:)` is the one place an absolute base becomes an offset.
// See docs/engine/actor-value-store.md.

import Foundation

/// One actor value's stored deviation from what its records author.
///
/// Every stored number is finite, enforced in `init` rather than checked at use
/// sites, for the reason `ActorValueEntry`'s invariant is: one NaN would spread
/// through every later sum and a resistance query would answer NaN rather than a
/// fraction.
nonisolated public struct ActorValueOverride: Equatable, Sendable {
    /// Delta on top of the derived baseline. Never an absolute value.
    public private(set) var baseOffset: Float
    public private(set) var permanent: Float
    public private(set) var temporary: Float
    public private(set) var damage: Float

    public init(
        baseOffset: Float = 0,
        permanent: Float = 0,
        temporary: Float = 0,
        damage: Float = 0
    ) {
        self.baseOffset = Self.finite(baseOffset)
        self.permanent = Self.finite(permanent)
        self.temporary = Self.finite(temporary)
        // A positive damage modifier would be a heal wearing damage's name.
        self.damage = min(0, Self.finite(damage))
    }

    /// The override an actor has for a value nothing has touched.
    public static let none = ActorValueOverride()

    /// Whether this override says nothing at all, which is what lets the store
    /// drop it rather than persist a no-op. An actor whose fire resistance was
    /// raised and then lowered again is an actor nothing happened to.
    public var isEmpty: Bool {
        self == Self.none
    }

    /// Everything it adds to the value's *maximum* — the base offset and the
    /// two modifiers that raise or lower a ceiling, with damage left out
    /// because damage lowers a current value and never a maximum.
    public var maximumOffset: Float {
        baseOffset + permanent + temporary
    }

    /// This override as the resolved entry a caller reads, given the value's
    /// re-derived baseline.
    public func resolved(baseline: Float) -> ActorValueEntry {
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
    public static func storing(_ entry: ActorValueEntry, baseline: Float) -> ActorValueOverride {
        ActorValueOverride(
            baseOffset: entry.base - baseline,
            permanent: entry.permanent,
            temporary: entry.temporary,
            damage: entry.damage
        )
    }

    /// This override with `delta` added to its base offset, which is what a
    /// skill advance and an attribute pick both do.
    public func addingBaseOffset(_ delta: Float) -> ActorValueOverride {
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
