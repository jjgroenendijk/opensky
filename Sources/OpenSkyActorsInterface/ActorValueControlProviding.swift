// The seam the actor-value panel is written against: the engine-owned damage,
// restore and reset operations, without `GameViewController`. One snapshot value,
// so the readout comes from a single observation while the streamer mutates.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One actor's values as a panel spells them.
nonisolated public struct ActorValueReadout: Equatable, Sendable {
    /// FULL name when the actor index resolves one, else the editor ID, else
    /// the FormID. Never empty, so a readout line always names something.
    public let name: String
    public let current: ActorValues
    public let maximums: ActorValues
    /// Percent of each maximum restored per second, from RACE DATA.
    public let regenPercentPerSecond: ActorValues
    /// The level the derivation used, which is what explains an unexpected
    /// maximum more often than anything else on this readout.
    public let level: Int
    /// Whether the per-level class spread applied.
    public let autoCalculatesStats: Bool
    /// The flag ragdoll and death consume.
    public let hasZeroHealth: Bool

    public static let empty = ActorValueReadout(
        name: "—",
        current: .zero,
        maximums: .zero,
        regenPercentPerSecond: .zero,
        level: 1,
        autoCalculatesStats: false,
        hasZeroHealth: true
    )

    public init(
        name: String,
        current: ActorValues,
        maximums: ActorValues,
        regenPercentPerSecond: ActorValues,
        level: Int,
        autoCalculatesStats: Bool,
        hasZeroHealth: Bool
    ) {
        self.name = name
        self.current = current
        self.maximums = maximums
        self.regenPercentPerSecond = regenPercentPerSecond
        self.level = level
        self.autoCalculatesStats = autoCalculatesStats
        self.hasZeroHealth = hasZeroHealth
    }
}

/// One actor value as the panel inspects it. The modifier slots stay separate,
/// because a damaged value and a lowered base read the same at a glance.
nonisolated public struct ActorValueInspection: Equatable, Sendable {
    /// Vanilla name, or the bare index when the selection names none, so a
    /// readout line always names something.
    public let name: String
    public let index: Int32
    public let current: Float
    public let base: Float
    public let permanent: Float
    public let temporary: Float
    public let damage: Float
    /// The capped fraction of damage this value removes, for a percentage
    /// resistance; nil for every other actor value, including `Damage Resist`,
    /// which is an armor rating rather than a percentage.
    public let resistanceFraction: Float?

    public static let empty = ActorValueInspection(
        name: "—",
        index: ActorValueIdentity.noneIndex,
        current: 0,
        base: 0,
        permanent: 0,
        temporary: 0,
        damage: 0,
        resistanceFraction: nil
    )

    public init(
        name: String,
        index: Int32,
        current: Float,
        base: Float,
        permanent: Float,
        temporary: Float,
        damage: Float,
        resistanceFraction: Float?
    ) {
        self.name = name
        self.index = index
        self.current = current
        self.base = base
        self.permanent = permanent
        self.temporary = temporary
        self.damage = damage
        self.resistanceFraction = resistanceFraction
    }
}

/// Who a damage or restore control applies to.
///
/// The same two selectors `EquipmentTargetSelector` offers, for the same
/// reason: the player is where the HUD meters are checked, and the nearest
/// resident actor is the only thing a hit is visible on.
nonisolated public enum ActorValueTargetSelector: Equatable, Sendable {
    case player
    /// The resident ACHR closest to the player.
    case nearestActor
}

/// One observation of the actor-value runtime.
nonisolated public struct ActorValueControlSnapshot: Equatable, Sendable {
    /// False when no actor-value runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather than
    /// showing a convincing zero.
    public let isAvailable: Bool
    /// The player's values, always present when available.
    public let player: ActorValueReadout
    /// The nearest resident ACHR's values, or nil when none is loaded.
    public let nearestActor: ActorValueReadout?
    /// Which target the dev controls act on.
    public let target: ActorValueTargetSelector
    /// The actor value the controls act on, read off the selected target.
    public let selection: ActorValueInspection
    /// How many references currently carry an actor-value component, across
    /// every cell whether resident or not.
    public let runtimeActorCount: Int
    /// Human-readable result of the last panel action.
    public let lastActionText: String

    /// The reading with no runtime attached.
    public static let unavailable = ActorValueControlSnapshot(
        isAvailable: false,
        player: .empty,
        nearestActor: nil,
        target: .player,
        selection: .empty,
        runtimeActorCount: 0,
        lastActionText: "Actor values unavailable: no game data loaded."
    )

    public init(
        isAvailable: Bool,
        player: ActorValueReadout,
        nearestActor: ActorValueReadout?,
        target: ActorValueTargetSelector,
        selection: ActorValueInspection,
        runtimeActorCount: Int,
        lastActionText: String
    ) {
        self.isAvailable = isAvailable
        self.player = player
        self.nearestActor = nearestActor
        self.target = target
        self.selection = selection
        self.runtimeActorCount = runtimeActorCount
        self.lastActionText = lastActionText
    }
}

@MainActor
public protocol ActorValueControlProviding: AnyObject {
    var actorValueControlSnapshot: ActorValueControlSnapshot { get }

    /// Which target the damage and restore controls act on.
    var actorValueTarget: ActorValueTargetSelector { get set }

    /// Which actor value they act on, by vanilla table index.
    /// Health until a panel selects another, and any of the 164 after that.
    var actorValueSelection: Int32 { get set }

    /// Takes `amount` off the selected target's selected value.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func damageSelectedActor(by amount: Float) -> String

    /// Adds `amount` to the selected target's selected value.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func restoreSelectedActor(by amount: Float) -> String

    /// Sets the selected value outright: the current value for a primary and
    /// the base value for everything else, which is what makes a resistance
    /// settable from the panel at all.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func setSelectedActorValue(to value: Float) -> String

    /// Sets the selected value's base outright, as `SetActorValue` does; for a
    /// primary that moves its maximum. Stored as a delta, so "Reset to records"
    /// still works. Returns a readable outcome the panel shows verbatim.
    @discardableResult
    func setSelectedActorBase(to value: Float) -> String

    /// Refills the selected target to its derived maximums.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func restoreSelectedActorFully() -> String

    /// Drops the selected target's runtime state, so it re-derives from
    /// records again.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func resetSelectedActorValues() -> String
}
