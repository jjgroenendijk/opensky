// The graph event names death and ragdoll bind to (issue #197, roadmap item
// 15.6).
//
// Every name here was read out of the M14 behavior census over the user's own
// install (`logs/hkx-behavior-census.log`, produced by
// `HKBBehaviorCensusRealDataTests`), never from memory, and every one of them
// appears in that log's `distinct events` union across the character behavior
// files. The same rule and the same reasons as `CombatGraphNames`: vanilla's
// capitalization is inconsistent — `bleedOutStart` is lower-camel and
// `DeathAnim` is upper-camel, in the same file — and a merely plausible name
// resolves to nothing at all.
//
// The direction of travel splits the same way melee's does.
//
// * Raised: the engine tells the graph the actor's health reached zero.
//   `bleedOutStart` is the entry to `BleedOutBehavior`, whose clips the census
//   lists as `Animations\BleedOut_*.hkx`, and `DeathAnim` is the death clip
//   selector `0_master.hkx` declares beside it.
// * Observed: the graph tells the engine that the animation has reached the
//   frame the physics takes over at. `AddRagdollToWorld` is that frame — its
//   name says what it asks the engine to do — with `NPCAddRagdollToWorld` as the
//   NPC-side spelling the census also carries, `Ragdoll` as the plain hand-off,
//   and `RagdollInstant` as the one that asks for no blend at all.
//
// Documented in docs/engine/ragdoll.md.

import Foundation

nonisolated enum RagdollGraphNames {
    // MARK: - Events raised into the graph

    /// Entry to the bleedout behavior, which is the state a vanilla actor
    /// reaches at zero health before the death clip plays.
    static let bleedOutStart = "bleedOutStart"
    /// The death animation itself.
    static let deathAnim = "DeathAnim"
    /// Leaving the death state, which nothing but a resurrection raises.
    static let deathStop = "deathStop"

    /// Every event the ragdoll runtime raises when an actor dies, in the order
    /// it raises them. Bleedout first, then the death clip: an actor that
    /// crosses zero health enters bleedout and the death animation follows from
    /// it, which is the order the census's own state names imply.
    static let deathEvents = [bleedOutStart, deathAnim]

    // MARK: - Events observed coming back out

    /// The clip annotation that marks the frame the physics takes the skeleton
    /// over. This is the hand-off the runtime spawns a ragdoll on.
    static let addRagdollToWorld = "AddRagdollToWorld"
    /// The NPC-side spelling of the same annotation.
    static let npcAddRagdollToWorld = "NPCAddRagdollToWorld"
    /// The plain hand-off, which blends over the controlling modifier's
    /// `m_durationToBlend`.
    static let ragdoll = "Ragdoll"
    /// The hand-off that asks for no blend at all.
    static let ragdollInstant = "RagdollInstant"

    /// Every event that hands the skeleton to the physics.
    static let handOffEvents = [
        addRagdollToWorld, npcAddRagdollToWorld, ragdoll, ragdollInstant
    ]

    /// Whether `name` is a hand-off, and whether it asks for an instant one.
    ///
    /// - Returns: nil when the name is not a hand-off at all; otherwise true
    ///   when the hand-off must skip the blend.
    static func handOff(_ name: String) -> Bool? {
        guard handOffEvents.contains(name) else { return nil }
        return name == ragdollInstant
    }
}
