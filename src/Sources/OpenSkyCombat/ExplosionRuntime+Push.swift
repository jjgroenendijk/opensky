// The push of an explosion: loose bodies by `fGameplayImpulseMult*`, actors knocked
// down by the blast's mode, and a splash under water (docs/engine/impulses.md#explosions).

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

extension ExplosionRuntime {
    func push(
        _ spec: ExplosionSpec, radius: Float, at position: SIMD3<Float>, source: FormID?
    ) {
        guard let impulses, let world = impulses.world else { return }
        let settings = impulses.settings
        let waterHeight = world.waterHeight(at: SIMD2(position.x, position.y))
        if let splash = WaterImpacts.explosionSplash(
            at: position, radius: radius, waterHeight: waterHeight, settings: impulses.water
        ) {
            impulses.play(splash)
        }
        let blast = ImpulseBlast(force: spec.force, radius: radius, center: position)
        if spec.force > 0 {
            for body in world.impulseBodies() {
                guard let impulse = GameplayImpulse.explosion(
                    blast, on: (body, source == body.reference), spin: nextSpin(),
                    settings: settings
                ) else { continue }
                world.applyBodyImpulse(impulse)
                impulses.record(.push(
                    body.key,
                    impulse: simd_length(impulse.linear),
                    cause: .explosion
                ))
            }
        }
        guard spec.knockdown != .never else { return }
        for target in world.impulseActors() {
            let distance = Self.distance(position, target)
            guard
                let health = world.actorHealth(of: target.key),
                GameplayImpulse.explosionKnocksDown(
                    blast, knockdown: (spec.knockdown, distance),
                    hit: KnockdownHit(
                        damage: ExplosionFalloff.damage(
                            spec.damage,
                            radius: radius,
                            distance: distance
                        ),
                        health: health, roll: nextRoll()
                    ),
                    settings: settings
                ),
                world.knockDown(target.key, from: position, magnitude: spec.force)
            else { continue }
            impulses.record(.knock(
                target.key,
                speed: spec.force,
                knockdown: true,
                cause: .explosion
            ))
        }
    }

    /// Three values in -1...1 for an explosion's random turn.
    private func nextSpin() -> SIMD3<Float> {
        SIMD3(nextRoll(), nextRoll(), nextRoll()) * 2 - 1
    }

    /// 0 to 1, from the runtime's own seed so a test can repeat it.
    private func nextRoll() -> Float {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(seed >> 40) / Float(1 << 24)
    }
}
