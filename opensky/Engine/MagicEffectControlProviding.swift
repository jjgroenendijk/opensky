// Main-app active-effect inspection seam (issue #469, roadmap item 19.6). The
// provider keeps the panel independent of `GameViewController` while exposing
// the engine-owned consume, dispel and coverage observations.
//
// One snapshot value rather than a bag of protocol properties, for the same
// reason `ActorValueControlSnapshot` is one: the readout has to be a pure
// function of a single engine observation, not of several taken microseconds
// apart while the simulation is mutating between them.
//
// AppKit-free, so it compiles into `openskycli` alongside the app.

import Foundation

/// One active effect as a panel spells it.
nonisolated struct ActiveEffectReadout: Equatable, Sendable {
    /// FULL name of the MGEF when the index resolves one, else its editor ID,
    /// else its key. Never empty, so a line always names something.
    let name: String
    /// Where it came from, spelled for a reader: "potion", "ingredient".
    let sourceName: String
    /// Which of the two documented timed behaviours it follows.
    let mode: ActiveEffectMode
    let isDetrimental: Bool
    let magnitude: Float
    let duration: Float
    let remaining: Float
    /// Vanilla names of the actor values it acts on, in the MGEF's order.
    let valueNames: [String]

    /// One line, the shape the readout joins with newlines.
    var line: String {
        let direction = isDetrimental ? "damages" : "restores"
        let behaviour = mode == .modifier ? "held" : "per second"
        let values = valueNames.joined(separator: ", ")
        return String(
            format: "%@ (%@) %@ %@ by %.1f %@, %.1fs of %.1fs left",
            name, sourceName, direction, values, magnitude, behaviour, remaining, duration
        )
    }
}

/// One observation of the active-effect runtime.
nonisolated struct MagicEffectControlSnapshot: Equatable, Sendable {
    /// False when no active-effect runtime is attached — no game data, or a
    /// synthetic scene. Every other field is then empty and the panel says so
    /// rather than showing a convincing zero.
    let isAvailable: Bool
    /// Every effect currently acting on the player, in application order.
    let playerEffects: [ActiveEffectReadout]
    /// The nearest resident actor the panel can name, or nil when no actor is
    /// resident. The same actor `ActorValueControlSnapshot.nearestActor`
    /// describes, so the effects list and the resistance values below it are
    /// read about the same body (issue #475, roadmap item 19.12).
    let nearestActorName: String?
    /// Every effect currently acting on that actor, in application order.
    /// Empty both when the actor carries none and when there is no actor; the
    /// name above is what tells those two apart.
    let nearestActorEffects: [ActiveEffectReadout]
    /// How many references carry an active-effect component, across every cell
    /// whether resident or not.
    let runtimeActorCount: Int
    /// Timed effects stored this session.
    let appliedCount: Int
    /// Zero-duration effects applied this session.
    let instantCount: Int
    /// Effects that ran out this session.
    let expiredCount: Int
    /// Effects removed by an explicit dispel this session.
    let dispelledCount: Int
    /// Everything the runtime declined to do, for any reason.
    let skippedCount: Int
    /// The unimplemented archetypes seen, most frequent first, already spelled
    /// as `name x count`.
    let unimplementedLines: [String]
    /// Human-readable result of the last panel action.
    let lastActionText: String

    /// The reading with no runtime attached.
    static let unavailable = MagicEffectControlSnapshot(
        isAvailable: false,
        playerEffects: [],
        nearestActorName: nil,
        nearestActorEffects: [],
        runtimeActorCount: 0,
        appliedCount: 0,
        instantCount: 0,
        expiredCount: 0,
        dispelledCount: 0,
        skippedCount: 0,
        unimplementedLines: [],
        lastActionText: "Magic effects unavailable: no game data loaded."
    )
}

@MainActor
protocol MagicEffectControlProviding: AnyObject {
    var magicEffectControlSnapshot: MagicEffectControlSnapshot { get }

    /// Drinks or eats the first ALCH or INGR the player carries.
    ///
    /// Exists beside the inventory menu's own consume action so the behaviour
    /// is reachable without opening a menu, which is what makes it verifiable
    /// from the panel alone.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func consumeFirstCarriedMagicItem() -> String

    /// Removes every effect currently acting on the player.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func dispelPlayerMagicEffects() -> String
}
