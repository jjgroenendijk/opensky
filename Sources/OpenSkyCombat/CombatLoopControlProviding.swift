// Main-app combat-loop inspection seam (issues #374 and #424, roadmap items
// 15.7 and 16.7): the hostility toggle, the combat-state and target readouts,
// the per-actor combat readout, and the transient-object counts.
//
// Item 16.7 deleted the dev-target spawn and reset controls along with the clock
// they drove. What a user does instead is make an actor hostile and let it
// notice them, which is the shipping path rather than a developer shortcut into
// it, and what the panel shows instead is one line per fighting actor.
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
nonisolated public struct CombatLoopSnapshot: Equatable, Sendable {
    /// False when no combat runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather than
    /// showing a convincing zero.
    public let isAvailable: Bool
    /// Whether the player is in combat, and with whom.
    public let isPlayerInCombat: Bool
    /// The current target's name, or "—" when there is none.
    public let targetName: String
    public let targetDistance: Float
    /// Resident actors that are hostile and alive, and those recorded dead.
    public let hostileCount: Int
    public let deadCount: Int
    /// Resident actors currently engaged, and how many of those are searching.
    public let engagedCount: Int
    public let searchingCount: Int
    /// One line's worth of state per actor with a combat machine, nearest
    /// first.
    public let actors: [CombatActorReadout]
    /// Hostile living actors the engagement cap refused a machine.
    public let crowdedOutCount: Int
    /// Whether the *selected* actor — the one the hostility toggle acts on — is
    /// hostile right now, and what it is called.
    public let selectedActorName: String
    public let selectedActorIsHostile: Bool
    /// Blows the player has taken, and the newest few spelled out.
    public let incomingHitCount: Int
    public let incomingTrace: [String]
    /// The HUD's damage-flash hook, `0...1`.
    public let damageFlash: Float
    /// Live transient counts, their ceilings, and how many have been trimmed.
    public let transients: CombatTransientCounts
    public let limits: CombatTransientLimits
    public let trimmedTransients: CombatTransientCounts
    /// Whether fighters are allowed to cast at all, which is the panel's own
    /// switch rather than anything the world holds (issue #473).
    public let isActorCastingEnabled: Bool
    /// Spells NPCs have finished casting this session.
    public let actorCastCount: Int
    /// Human-readable result of the last panel action.
    public let lastActionText: String

    /// The reading with no runtime attached.
    public static let unavailable = CombatLoopSnapshot(
        isAvailable: false,
        isPlayerInCombat: false,
        targetName: "—",
        targetDistance: 0,
        hostileCount: 0,
        deadCount: 0,
        engagedCount: 0,
        searchingCount: 0,
        actors: [],
        crowdedOutCount: 0,
        selectedActorName: "—",
        selectedActorIsHostile: false,
        incomingHitCount: 0,
        incomingTrace: [],
        damageFlash: 0,
        transients: .none,
        limits: .standard,
        trimmedTransients: .none,
        isActorCastingEnabled: false,
        actorCastCount: 0,
        lastActionText: "Combat unavailable: no game data loaded."
    )

    public init(
        isAvailable: Bool,
        isPlayerInCombat: Bool,
        targetName: String,
        targetDistance: Float,
        hostileCount: Int,
        deadCount: Int,
        engagedCount: Int,
        searchingCount: Int,
        actors: [CombatActorReadout],
        crowdedOutCount: Int,
        selectedActorName: String,
        selectedActorIsHostile: Bool,
        incomingHitCount: Int,
        incomingTrace: [String],
        damageFlash: Float,
        transients: CombatTransientCounts,
        limits: CombatTransientLimits,
        trimmedTransients: CombatTransientCounts,
        isActorCastingEnabled: Bool,
        actorCastCount: Int,
        lastActionText: String
    ) {
        self.isAvailable = isAvailable
        self.isPlayerInCombat = isPlayerInCombat
        self.targetName = targetName
        self.targetDistance = targetDistance
        self.hostileCount = hostileCount
        self.deadCount = deadCount
        self.engagedCount = engagedCount
        self.searchingCount = searchingCount
        self.actors = actors
        self.crowdedOutCount = crowdedOutCount
        self.selectedActorName = selectedActorName
        self.selectedActorIsHostile = selectedActorIsHostile
        self.incomingHitCount = incomingHitCount
        self.incomingTrace = incomingTrace
        self.damageFlash = damageFlash
        self.transients = transients
        self.limits = limits
        self.trimmedTransients = trimmedTransients
        self.isActorCastingEnabled = isActorCastingEnabled
        self.actorCastCount = actorCastCount
        self.lastActionText = lastActionText
    }
}

@MainActor
public protocol CombatLoopControlProviding: AnyObject {
    var combatLoopSnapshot: CombatLoopSnapshot { get }

    /// Whether the selected actor — the crosshair target, else the nearest
    /// resident one — regards the player as an enemy. Settable, which is the
    /// hostility toggle scope point 7 asks for.
    var selectedActorIsHostile: Bool { get set }

    /// Whether fighting actors may cast the spells they know (issue #473).
    ///
    /// A switch rather than a tuning number, and the one control this item adds:
    /// turning it off is how a user tells "the caster is not casting because the
    /// decision layer chose a swing" apart from "the caster is not casting
    /// because nothing it knows is deliverable". On by default, because casting
    /// is the shipping behaviour.
    var isActorCastingEnabled: Bool { get set }

    /// Empties the incoming-hit trace and its count, without disturbing the
    /// fight.
    func clearCombatTrace()
}
