// What a hit does through the body part it struck: the limb's actor value takes
// damage, and the part's blood impact sprays one decal on a nearby surface.
// See docs/formats/body-parts.md#in-the-game.

import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyRenderCore
import simd

extension CombatShared {
    /// One landed hit's body part effects.
    struct BodyPartHits {
        let shared: CombatShared

        /// AVIF index 24, Health.
        static let healthIndex: Int32 = 24

        func land(
            _ hit: CombatHitRecord, on part: StruckBodyPart, target: ReferenceKey,
            at point: SIMD3<Float>?
        ) {
            damageLimb(hit, part: part, target: target)
            sprayBlood(hit, part: part, target: target, at: point ?? part.position)
        }

        private func damageLimb(
            _ hit: CombatHitRecord,
            part: StruckBodyPart,
            target: ReferenceKey
        ) {
            guard let index = part.actorValue else { return }
            let world = shared.world
            let limb = BodyPartHitRules.limbDamage(
                hit.damage, part: part,
                baseHealth: world.baseActorValue(at: Self.healthIndex, of: target) ?? 0,
                playerMultiplier: target == .player ? shared.weaponDamage.playerLimbDamageMult : nil
            )
            guard limb > 0 else { return }
            world.damageActorValue(at: index, by: limb, of: target)
        }

        /// The roll, then a ray from the hit point along the spray; the first world
        /// surface it meets takes the impact's decal.
        private func sprayBlood(
            _ hit: CombatHitRecord, part: StruckBodyPart, target: ReferenceKey,
            at point: SIMD3<Float>
        ) {
            let world = shared.world
            guard
                let dataSet = part.bloodImpactDataSet,
                Float(shared.bloodRandom.percent()) < BodyPartHitRules.bloodSprayChance * 100,
                let source = hit.attacker.flatMap(sourcePosition(of:)) ?? hit.origin
            else { return }
            var away = point - source
            away.z = 0
            let jitter = SIMD3(draw(), draw(), draw())
            guard
                let ray = BodyPartHitRules.bloodRay(hitDirection: away, jitter: jitter),
                let impact = shared.melee?.impacts?.impact(
                    dataSet: dataSet, material: world.impactMaterial(of: target)
                ),
                let surface = nearestSurface(from: point, along: ray)
            else { return }
            shared.pendingCommands.append(
                .placeBloodDecal(impact, at: surface.position, normal: surface.normal)
            )
        }

        /// The nearer of placed collision and the land along the spray, since the
        /// static sweep holds no terrain.
        private func nearestSurface(
            from point: SIMD3<Float>, along ray: SIMD3<Float>
        ) -> TerrainRayHit? {
            let reach = BodyPartHitRules.bloodSprayReach
            let swept = shared.world.sweep(.sphere(
                center: point, radius: 1, direction: ray, maximumDistance: reach
            )).flatMap { hit in
                hit.startsOverlapping ? nil
                    : TerrainRayHit(
                        position: hit.position,
                        normal: hit.normal,
                        distance: hit.distance
                    )
            }
            let ground = shared.world.groundHit(from: point, along: ray, within: reach)
            return [swept, ground].compactMap(\.self).min { $0.distance < $1.distance }
        }

        private func sourcePosition(of key: ReferenceKey) -> SIMD3<Float>? {
            key == .player ? shared.world.playerAttacker?.feet
                : shared.world.residentActor(key: key)?.feet
        }

        /// One draw from -1 to 1.
        private func draw() -> Float {
            Float(shared.bloodRandom.percent()) / 49.5 - 1
        }
    }
}
