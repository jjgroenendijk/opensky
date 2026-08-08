// Main-app combat-loop inspection seam (issue #374, roadmap item 15.7, scope
// point 7): the hostility toggle, the combat-state and target readouts, the
// dev-target spawn and reset controls, and the transient-object counts.
//
// One snapshot value rather than a bag of protocol properties, for the reason
// `MeleeCombatSnapshot` and `ArcherySnapshot` are one: the readout has to be a
// pure function of a single engine observation, not of several taken
// microseconds apart while a fight is running between them.
//
// Specified and conformed here; the section that reads it ships with the M15
// gate panel (item 15.9), which is where a `World > Combat & Physics`
// destination belongs. Defining the protocol now means the runtime below it is
// built to answer the questions a panel asks rather than being retrofitted to.
//
// AppKit-free, so it compiles into `openskycli` alongside the app.

import Foundation

/// One observation of the combat loop.
nonisolated struct CombatLoopSnapshot: Equatable, Sendable {
    /// False when no combat runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather than
    /// showing a convincing zero.
    let isAvailable: Bool
    /// Whether the player is in combat, and with whom.
    let isPlayerInCombat: Bool
    /// The current target's name, or "—" when there is none.
    let targetName: String
    let targetDistance: Float
    /// Resident actors that are hostile and alive, and those recorded dead.
    let hostileCount: Int
    let deadCount: Int
    /// The designated opponent's name, or "—" when none is spawned, and where
    /// its attack clock currently is.
    let devTargetName: String
    let devTargetPhase: DevTargetPhase
    let devTargetIsRunning: Bool
    /// Attacks it has started and contact steps it has reached.
    let devTargetAttackCount: Int
    let devTargetContactCount: Int
    /// Whether the *selected* actor — the one the hostility toggle acts on — is
    /// hostile right now, and what it is called.
    let selectedActorName: String
    let selectedActorIsHostile: Bool
    /// Blows the player has taken, and the newest few spelled out.
    let incomingHitCount: Int
    let incomingTrace: [String]
    /// The HUD's damage-flash hook, `0...1`.
    let damageFlash: Float
    /// Live transient counts, their ceilings, and how many have been trimmed.
    let transients: CombatTransientCounts
    let limits: CombatTransientLimits
    let trimmedTransients: CombatTransientCounts
    /// Human-readable result of the last panel action.
    let lastActionText: String

    /// The reading with no runtime attached.
    static let unavailable = CombatLoopSnapshot(
        isAvailable: false,
        isPlayerInCombat: false,
        targetName: "—",
        targetDistance: 0,
        hostileCount: 0,
        deadCount: 0,
        devTargetName: "—",
        devTargetPhase: .idle,
        devTargetIsRunning: false,
        devTargetAttackCount: 0,
        devTargetContactCount: 0,
        selectedActorName: "—",
        selectedActorIsHostile: false,
        incomingHitCount: 0,
        incomingTrace: [],
        damageFlash: 0,
        transients: .none,
        limits: .standard,
        trimmedTransients: .none,
        lastActionText: "Combat unavailable: no game data loaded."
    )
}

@MainActor
protocol CombatLoopControlProviding: AnyObject {
    var combatLoopSnapshot: CombatLoopSnapshot { get }

    /// Whether the selected actor — the crosshair target, else the nearest
    /// resident one — regards the player as an enemy. Settable, which is the
    /// hostility toggle scope point 7 asks for.
    var selectedActorIsHostile: Bool { get set }

    /// Designates the nearest living actor as the opponent and starts its
    /// attack clock.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func spawnCombatDevTarget() -> String

    /// Stops the opponent's clock, calms it and forgets it.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func resetCombatDevTarget() -> String

    /// Empties the incoming-hit trace and its count, without disturbing the
    /// fight.
    func clearCombatTrace()
}
