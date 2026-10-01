// What "the player is in combat" means, and one blow on the player. Derived every step,
// never stored, so a death, unload or calm ends it with nothing to clear. The target is
// the nearest hostile living actor. Pure values, so the acceptance chain is arithmetic.
// See docs/engine/combat.md.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import simd

/// The player's combat situation as of one step.
nonisolated public struct CombatLoopState: Equatable, Sendable {
    /// True while a resident actor is engaged: fighting or searching for the player. A
    /// hostile actor that has not noticed the player, or gave up, is not, so combat
    /// music stops when the fight ends.
    public var isPlayerInCombat = false
    /// The nearest hostile living actor, or nil when there is none.
    ///
    /// Nearest *hostile*, unchanged from 15.7 and deliberately not narrowed to
    /// the engaged ones: "who am I fighting" from the player's side is answered
    /// by turning to face somebody, and an actor that is hostile but has not
    /// noticed the player yet is still the thing the player is about to fight.
    public var target: ReferenceKey?
    /// Its name, for the readout. Empty when there is no target.
    public var targetName = ""
    /// How far away it is, world units. Zero when there is no target.
    public var targetDistance: Float = 0
    /// Resident actors that are hostile and alive.
    public var hostileCount = 0
    /// Resident actors currently engaged, which is a subset of those.
    public var engagedCount = 0
    /// Resident actors currently searching, which is a subset of the engaged.
    public var searchingCount = 0
    /// Resident actors recorded dead.
    public var deadCount = 0

    public static let calm = CombatLoopState()

    /// Derives the state from one observation of resident actors. `phase` is nil for an
    /// actor with no machine; `playerFeet` picks the nearest target.
    public static func derive(
        actors: [CombatActorObservation],
        hostility: (ReferenceKey) -> ActorHostility,
        phase: (ReferenceKey) -> CombatBehaviorPhase?,
        playerFeet: SIMD3<Float>
    ) -> CombatLoopState {
        var state = CombatLoopState()
        var nearest: (actor: CombatActorObservation, distance: Float)?
        for actor in actors {
            if actor.isDead {
                state.deadCount += 1
                continue
            }
            if let phase = phase(actor.key), phase.isEngaged {
                state.engagedCount += 1
                if phase == .searching {
                    state.searchingCount += 1
                }
            }
            guard hostility(actor.key) == .hostile else { continue }
            state.hostileCount += 1
            let distance = simd_distance(actor.feet, playerFeet)
            // Ties break on the lower reference, so two actors standing on the
            // same spot always produce the same target.
            guard
                let current = nearest,
                (current.distance, current.actor.key) <= (distance, actor.key)
            else {
                nearest = (actor, distance)
                continue
            }
        }
        state.isPlayerInCombat = state.engagedCount > 0
        state.target = nearest?.actor.key
        state.targetName = nearest?.actor.name ?? ""
        state.targetDistance = nearest?.distance ?? 0
        return state
    }
}

/// One blow an actor landed on the player, kept for the panel's trace.
nonisolated public struct CombatIncomingHit: Equatable, Sendable {
    /// Who swung.
    public let aggressor: ReferenceKey
    public let damage: MeleeDamageResult
    /// Whether the player's own graph took the hit-react event.
    public let playedReaction: Bool
    /// Which of the aggressor's attacks it was, so two hits from one attack
    /// read as one attack.
    public let attackID: Int
}
