// The push of an explosion: loose bodies by `fGameplayImpulseMult*`, actors knocked
// along the ground, a radius cut short under water, and a splash at the surface
// (docs/engine/impulses.md#explosions).

import Foundation
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

extension ExplosionRuntime {
    /// The blast radius, shrunk by `fExplosionWaterRadiusRatio` under water.
    func reach(of spec: ExplosionSpec, at position: SIMD3<Float>) -> Float {
        guard let impulses else { return spec.radius }
        return WaterImpacts.explosionRadius(
            spec.radius, at: position,
            waterHeight: impulses.world?.waterHeight(at: SIMD2(position.x, position.y)),
            settings: impulses.water
        )
    }

    func push(
        _ spec: ExplosionSpec, radius: Float, at position: SIMD3<Float>, source: FormID?
    ) {
        guard let impulses, let world = impulses.world else { return }
        let settings = impulses.settings
        let waterHeight = world.waterHeight(at: SIMD2(position.x, position.y))
        if let splash = WaterImpacts.explosionSplash(
            at: position, waterHeight: waterHeight, settings: impulses.water
        ) {
            impulses.play(splash)
        }
        guard spec.force > 0 else { return }
        let blast = ImpulseBlast(force: spec.force, radius: radius, center: position)
        for body in world.impulseBodies() {
            guard let impulse = GameplayImpulse.explosion(
                blast, on: body, isSource: source == body.reference, settings: settings
            ) else { continue }
            world.applyBodyImpulse(impulse)
            let amount = simd_length(impulse.linear)
            impulses.record(.push(body.key, impulse: amount, cause: .explosion))
        }
        for target in world.impulseActors() {
            let speed = GameplayImpulse.explosionKnock(
                blast, distance: Self.distance(position, target), settings: settings
            )
            let away = SIMD3(target.feet.x - position.x, target.feet.y - position.y, 0)
            guard speed > 0, simd_length(away) > 0.001 else { continue }
            let velocity = simd_normalize(away) * speed
            if world.knockActor(target.key, velocity: velocity, knockdown: false) {
                impulses.record(
                    .knock(target.key, speed: speed, knockdown: false, cause: .explosion)
                )
            }
        }
    }
}
