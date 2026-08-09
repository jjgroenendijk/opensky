// What "the player is in combat" means in this engine (issues #374 and #424,
// roadmap items 15.7 and 16.7), and the record of one blow landing on the
// player.
//
// Combat state is **derived, not stored**. The question is "is any resident
// actor engaged", and deriving it every step from the same actor list the fight
// runs over is what keeps it from going stale: a target that died, a cell that
// unloaded, an actor that gave up the search, or a hostility cleared from the
// panel all change the answer on the next step with nothing to invalidate. A
// stored flag would have to be cleared from each of those places, and the one
// that was forgotten would leave the player permanently "in combat" with a
// corpse.
//
// The current target is the nearest hostile living actor. Nearest rather than
// most-recently-hit, because 15.8's combat-target condition run-on and the
// music hook both want "who am I fighting" and a player who turned to face a
// second attacker has answered that question by turning.
//
// Pure value types over a list of observations: no world, no clock, no store.
// That is what makes the combat-state half of the acceptance chain a plain
// arithmetic assertion.
//
// Documented in docs/engine/combat.md.

import simd

/// The player's combat situation as of one step.
nonisolated struct CombatLoopState: Equatable, Sendable {
    /// True while at least one resident actor is *engaged* — fighting the
    /// player or searching for them.
    ///
    /// Hostile-and-alive was the answer while the opponent was a clock, because
    /// a hostile actor had nothing else it could be doing. With 16.7 it does: a
    /// bandit that has not perceived the player yet, and one that searched and
    /// gave up and walked back to its schedule, are both hostile and both out of
    /// the fight. Deriving from engagement rather than from hostility is what
    /// makes the combat music stop when the fight actually ends instead of when
    /// the actor is finally killed or calmed from the panel.
    var isPlayerInCombat = false
    /// The nearest hostile living actor, or nil when there is none.
    ///
    /// Nearest *hostile*, unchanged from 15.7 and deliberately not narrowed to
    /// the engaged ones: "who am I fighting" from the player's side is answered
    /// by turning to face somebody, and an actor that is hostile but has not
    /// noticed the player yet is still the thing the player is about to fight.
    var target: ReferenceKey?
    /// Its name, for the readout. Empty when there is no target.
    var targetName = ""
    /// How far away it is, world units. Zero when there is no target.
    var targetDistance: Float = 0
    /// Resident actors that are hostile and alive.
    var hostileCount = 0
    /// Resident actors currently engaged, which is a subset of those.
    var engagedCount = 0
    /// Resident actors currently searching, which is a subset of the engaged.
    var searchingCount = 0
    /// Resident actors recorded dead.
    var deadCount = 0

    static let calm = CombatLoopState()

    /// Derives the state from one observation of the resident actors.
    ///
    /// - Parameters:
    ///   - actors: every resident actor.
    ///   - hostility: each one's stored regard for the player.
    ///   - phase: each one's combat behavior phase, or nil for an actor with no
    ///     machine running.
    ///   - playerFeet: where the player is standing, for the nearest-target
    ///     comparison.
    static func derive(
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
nonisolated struct CombatIncomingHit: Equatable, Sendable {
    /// Who swung.
    let aggressor: ReferenceKey
    let damage: MeleeDamageResult
    /// Whether the player's own graph took the hit-react event.
    let playedReaction: Bool
    /// Which of the aggressor's attacks it was, so two hits from one attack
    /// read as one attack.
    let attackID: Int
}
