// What the combat coordinator asks the app to do. Each one is fire-and-forget:
// nothing later in the same step reads its result. See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState
import simd

/// One change to the world outside the combat domain.
nonisolated public enum CombatCommand: Equatable, Sendable {
    case showNotification(String)
    /// The impact sound and visual effect of a melee or projectile hit.
    case playImpact(ResolvedMeleeImpact, at: SIMD3<Float>)
    /// A projectile of `owner` landed: observers near it may hear it (CK wiki
    /// "Category:Detection", Detection Events).
    case detectionEvent(owner: ReferenceKey, at: SIMD3<Float>)
    /// Drops every stored change for the reference, which removes a spawned one.
    case removeReference(ReferenceKey)
    case resetRagdolls
    case setCombatMusic(active: Bool)
    /// The player began a swing or loosed an arrow while no one fights it, which a
    /// witness may comment on.
    case playerAttackedOutsideCombat(CombatWeaponUse)
}

/// What the player did with a weapon outside a fight.
nonisolated public enum CombatWeaponUse: Equatable, Sendable {
    case swing
    case shot
}
