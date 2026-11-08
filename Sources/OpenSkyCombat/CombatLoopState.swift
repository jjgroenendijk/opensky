// What "the player is in combat" means, and one blow on the player. Derived every step,
// never stored, so a death, unload or calm ends it with nothing to clear. The target is
// the nearest hostile living actor. Pure values, so the acceptance chain is arithmetic.
// See docs/engine/combat.md.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import simd

/// One blow an actor landed on the player, kept for the readout's trace.
nonisolated public struct CombatIncomingHit: Equatable, Sendable {
    public let damage: MeleeDamageResult
    /// Whether the player's own graph took the hit-react event.
    public let playedReaction: Bool
}
