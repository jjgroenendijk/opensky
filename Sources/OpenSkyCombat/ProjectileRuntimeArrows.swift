// What a landed arrow does after its damage: how deep it sits, how long it stays in
// an actor, and whether the target keeps it. A satellite of `ProjectileRuntime`, which
// is at its body-length cap. See docs/engine/projectiles.md, "After the impact".

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import simd

/// The arrows standing in actors, the clock they age on, and the recovery roll.
public struct AttachedArrows {
    public internal(set) var now: Float = 0
    /// When each arrow in an actor comes out, by its spawned key.
    public internal(set) var expiry: [ReferenceKey: Float] = [:]
    public internal(set) var recoveredCount = 0
    var random = ConditionRandom()

    public init() {}
}

extension ProjectileRuntime {
    /// The contact point pushed `fCombatMissileStickDepth` along the flight.
    func stuckPosition(of projectile: LiveProjectile, at impact: ProjectileImpact) -> SIMD3<Float> {
        let velocity = projectile.state.velocity
        let speed = simd_length(velocity)
        guard speed > 0, arrows.stickDepth.isFinite else { return impact.position }
        return impact.position + velocity / speed * max(0, arrows.stickDepth)
    }

    /// Starts the `fAttachedArrowAgeMax` clock on an arrow that stuck in an actor.
    func trackAttached(_ key: ReferenceKey, inActor: Bool) {
        guard inActor else { return }
        let age = arrows.attachedAgeMax.isFinite ? max(0, arrows.attachedAgeMax) : 0
        attached.expiry[key] = attached.now + age
    }

    /// Pulls out every arrow standing in `host`: Papyrus `ClearExtraArrows`. Returns the count.
    @discardableResult
    public func removeArrows(stuckIn host: FormID) -> Int {
        let held = stuck.indices.filter { stuck[$0].arrow.host == host }
        removeStuckArrows(held)
        return held.count
    }

    /// Pulls out every arrow whose time in an actor has run out.
    func ageAttachedArrows(by frameTime: Float) {
        attached.now += frameTime.isFinite ? max(0, frameTime) : 0
        guard !attached.expiry.isEmpty else { return }
        let expired = stuck.indices.filter { index in
            guard let key = stuck[index].key, let end = attached.expiry[key] else { return false }
            return end <= attached.now
        }
        removeStuckArrows(expired)
        let standing = Set(stuck.compactMap(\.key))
        attached.expiry = attached.expiry.filter { standing.contains($0.key) }
    }

    /// UESP "Skyrim:Archery": an arrow that hits an actor joins its inventory with
    /// an `iArrowInventoryChance` percent chance, scaled by the shooter's perks.
    /// A dev shot carries no ammunition.
    func recoverArrow(
        _ arrow: ArrowPayload, from shooter: ReferenceKey, into target: ReferenceKey,
        world: any ProjectileWorld
    ) {
        guard let ammunition = arrow.ammunition else { return }
        let chance = Float(arrows.inventoryChance) * world.arrowRecoveryMultiplier(of: shooter)
        guard Float(attached.random.percent()) < chance else { return }
        if world.giveRecoveredArrow(ammunition, to: target) {
            attached.recoveredCount += 1
        }
    }
}
