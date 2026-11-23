// What a landed arrow does after its damage: how deep it sits, how long it stays in
// an actor, and whether the target keeps it. A satellite of `ProjectileRuntime`, which
// is at its body-length cap. See docs/engine/projectiles.md, "After the impact".

import Foundation
import OpenSkyCombatInterface
public import OpenSkyConditions
public import OpenSkyFormatsESM
import simd

/// The arrows standing in actors, the clock they age on, and the recovery roll.
struct AttachedArrows {
    var now: Float = 0
    /// When each arrow in an actor comes out, by its spawned key.
    var expiry: [ReferenceKey: Float] = [:]
    /// The actor each of those arrows stands in.
    var holder: [ReferenceKey: ReferenceKey] = [:]
    var recoveredCount = 0
    var random = ConditionRandom()
}

extension ProjectileRuntime {
    /// Leaves the arrow standing in what it hit, evicting the oldest at the cap. Only an
    /// arrow sticks; a spell projectile is spent on impact.
    func stick(
        _ projectile: LiveProjectile, at impact: ProjectileImpact, lying: Bool = false
    ) -> Bool {
        guard
            let world,
            let base = projectile.payload.arrow?.ammunition,
            let location = projectile.location
        else { return false }
        let arrow = StuckProjectile(
            base: base,
            location: location,
            position: lying ? impact.position : stuckPosition(of: projectile, at: impact),
            rotation: ProjectileImpactQuery.stuckRotation(
                alongFlight: projectile.state.velocity
            ),
            host: impact.reference
        )
        guard let key = world.spawnStuckProjectile(arrow) else { return false }
        stuck.append((arrow, key))
        trackAttached(key, in: impact.isActor ? impact.target : nil)
        if stuck.count > Self.stuckLimit {
            removeStuckArrows(Array(stuck.indices.prefix(stuck.count - Self.stuckLimit)))
        }
        return true
    }

    /// Removes the stuck arrows at `indices` from the world and from the registry.
    /// Internal, so `ProjectileRuntimeBounds.swift` can reach it.
    public func removeStuckArrows(_ indices: [Int]) {
        guard !indices.isEmpty else { return }
        let doomed = Set(indices)
        for index in indices.sorted() {
            guard let key = stuck[index].key else { continue }
            world?.removeStuckProjectile(key)
        }
        stuck = stuck.indices.filter { !doomed.contains($0) }.map { stuck[$0] }
    }

    /// The contact point pushed `fCombatMissileStickDepth` along the flight, or the
    /// bolt depth for a crossbow bolt.
    func stuckPosition(of projectile: LiveProjectile, at impact: ProjectileImpact) -> SIMD3<Float> {
        let velocity = projectile.state.velocity
        let speed = simd_length(velocity)
        let depth = projectile.isBolt ? arrows.boltStickDepth : arrows.stickDepth
        guard speed > 0, depth.isFinite else { return impact.position }
        return impact.position + velocity / speed * max(0, depth)
    }

    /// Starts the `fAttachedArrowAgeMax` clock on an arrow that stuck in `actor`, and
    /// pulls out that actor's oldest arrows past the per-actor limit.
    func trackAttached(_ key: ReferenceKey, in actor: ReferenceKey?) {
        guard let actor else { return }
        let age = arrows.attachedAgeMax.isFinite ? max(0, arrows.attachedAgeMax) : 0
        attached.expiry[key] = attached.now + age
        attached.holder[key] = actor
        let held = stuck.indices.filter { index in
            stuck[index].key.map { attached.holder[$0] == actor } ?? false
        }
        removeStuckArrows(Array(held.dropLast(max(0, arrows.arrowsPerActor))))
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
        attached.holder = attached.holder.filter { standing.contains($0.key) }
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
