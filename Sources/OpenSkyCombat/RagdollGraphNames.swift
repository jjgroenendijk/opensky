// The graph event names death and ragdoll bind to, read from the behavior
// census over the install, never from memory. Raised: `bleedOutStart` and
// `DeathAnim`. Observed: `AddRagdollToWorld`, `NPCAddRagdollToWorld`,
// `Ragdoll`, and `RagdollInstant`, the hand-off to physics.
// See docs/engine/ragdoll.md.

import Foundation

nonisolated public enum RagdollGraphNames: Sendable {
    // MARK: - Events raised into the graph

    /// Entry to the bleedout behavior, which is the state a vanilla actor
    /// reaches at zero health before the death clip plays.
    public static let bleedOutStart = "bleedOutStart"
    /// The death animation itself.
    public static let deathAnim = "DeathAnim"

    /// Every event the ragdoll runtime raises when an actor dies, in the order
    /// it raises them. Bleedout first, then the death clip: an actor that
    /// crosses zero health enters bleedout and the death animation follows from
    /// it, which is the order the census's own state names imply.
    public static let deathEvents = [bleedOutStart, deathAnim]

    // MARK: - Events observed coming back out

    /// The clip annotation that marks the frame the physics takes the skeleton
    /// over. This is the hand-off the runtime spawns a ragdoll on.
    public static let addRagdollToWorld = "AddRagdollToWorld"
    /// The NPC-side spelling of the same annotation.
    public static let npcAddRagdollToWorld = "NPCAddRagdollToWorld"
    /// The plain hand-off, which blends over the controlling modifier's
    /// `m_durationToBlend`.
    public static let ragdoll = "Ragdoll"
    /// The hand-off that asks for no blend at all.
    public static let ragdollInstant = "RagdollInstant"

    /// Every event that hands the skeleton to the physics.
    public static let handOffEvents = [
        addRagdollToWorld, npcAddRagdollToWorld, ragdoll, ragdollInstant
    ]

    /// Whether `name` is a hand-off, and whether it asks for an instant one.
    ///
    /// - Returns: nil when the name is not a hand-off at all; otherwise true
    ///   when the hand-off must skip the blend.
    public static func handOff(_ name: String) -> Bool? {
        guard handOffEvents.contains(name) else { return nil }
        return name == ragdollInstant
    }
}
