// Main-app actor-value inspection seam (issue #194, roadmap item 15.3). The
// provider keeps a future panel independent of `GameViewController` while
// exposing the engine-owned damage, restore and reset operations.
//
// Specified here and shipped with the M15 acceptance gate (item 15.9), which is
// what the issue asks for: the protocol is the contract the panel is written
// against, and defining it now means the runtime below it is already built to
// answer the questions a panel asks rather than being retrofitted to.
//
// One snapshot value rather than a bag of protocol properties, for the same
// reason `ItemControlSnapshot` is one: the readout has to be a pure function of
// a single engine observation, not of several taken microseconds apart while
// the streamer is mutating between them.
//
// AppKit-free, so it compiles into `openskycli` alongside the app.

import Foundation

/// One actor's values as a panel spells them.
nonisolated struct ActorValueReadout: Equatable, Sendable {
    /// FULL name when the actor index resolves one, else the editor ID, else
    /// the FormID. Never empty, so a readout line always names something.
    let name: String
    let current: ActorValues
    let maximums: ActorValues
    /// Percent of each maximum restored per second, from RACE DATA.
    let regenPercentPerSecond: ActorValues
    /// The level the derivation used, which is what explains an unexpected
    /// maximum more often than anything else on this readout.
    let level: Int
    /// Whether the per-level class spread applied.
    let autoCalculatesStats: Bool
    /// The flag item 15.6 consumes.
    let hasZeroHealth: Bool

    static let empty = ActorValueReadout(
        name: "—",
        current: .zero,
        maximums: .zero,
        regenPercentPerSecond: .zero,
        level: 1,
        autoCalculatesStats: false,
        hasZeroHealth: true
    )
}

/// One actor value as the panel inspects it (issue #468, roadmap item 19.5).
///
/// Carries the modifier slots separately rather than only the current number,
/// because the whole point of the general store is that a damaged resistance
/// and a lowered base are different states that read the same at a glance.
nonisolated struct ActorValueInspection: Equatable, Sendable {
    /// Vanilla name, or the bare index when the selection names none, so a
    /// readout line always names something.
    let name: String
    let index: Int32
    let current: Float
    let base: Float
    let permanent: Float
    let temporary: Float
    let damage: Float
    /// The capped fraction of damage this value removes, for a percentage
    /// resistance; nil for every other actor value, including `Damage Resist`,
    /// which is an armor rating rather than a percentage.
    let resistanceFraction: Float?

    static let empty = ActorValueInspection(
        name: "—",
        index: ActorValueIdentity.noneIndex,
        current: 0,
        base: 0,
        permanent: 0,
        temporary: 0,
        damage: 0,
        resistanceFraction: nil
    )
}

/// Who a damage or restore control applies to.
///
/// The same two selectors `EquipmentTargetSelector` offers, for the same
/// reason: the player is where the HUD meters are checked, and the nearest
/// resident actor is the only thing a hit is visible on.
nonisolated enum ActorValueTargetSelector: Equatable, Sendable {
    case player
    /// The resident ACHR closest to the player.
    case nearestActor
}

/// One observation of the actor-value runtime.
nonisolated struct ActorValueControlSnapshot: Equatable, Sendable {
    /// False when no actor-value runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather than
    /// showing a convincing zero.
    let isAvailable: Bool
    /// The player's values, always present when available.
    let player: ActorValueReadout
    /// The nearest resident ACHR's values, or nil when none is loaded.
    let nearestActor: ActorValueReadout?
    /// Which target the dev controls act on.
    let target: ActorValueTargetSelector
    /// The actor value the controls act on, read off the selected target
    /// (issue #468).
    let selection: ActorValueInspection
    /// How many references currently carry an actor-value component, across
    /// every cell whether resident or not.
    let runtimeActorCount: Int
    /// Human-readable result of the last panel action.
    let lastActionText: String

    /// The reading with no runtime attached.
    static let unavailable = ActorValueControlSnapshot(
        isAvailable: false,
        player: .empty,
        nearestActor: nil,
        target: .player,
        selection: .empty,
        runtimeActorCount: 0,
        lastActionText: "Actor values unavailable: no game data loaded."
    )
}

@MainActor
protocol ActorValueControlProviding: AnyObject {
    var actorValueControlSnapshot: ActorValueControlSnapshot { get }

    /// Which target the damage and restore controls act on.
    var actorValueTarget: ActorValueTargetSelector { get set }

    /// Which actor value they act on, by vanilla table index (issue #468).
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
