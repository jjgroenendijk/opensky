// What a projectile shows: its PROJ model and light along the flight, its muzzle
// flash, and an explosion's light and impact data. The rules are in
// docs/engine/spell-delivery.md#what-a-projectile-shows.

import OpenSkyCombat
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import simd

extension EffectsWorldAdapter {
    /// Above every visual effect instance id, so a projectile keeps its own particles.
    static let projectileInstanceBase = 1 << 30

    /// Each live projectile's model along its velocity.
    func projectileModels() -> [VisualEffectModel] {
        (game.combat.archery?.projectiles.live ?? []).compactMap { projectile in
            guard let model = projectile.profile.visuals.model else { return nil }
            let along = simd_length_squared(projectile.state.velocity) > 1e-6
                ? projectile.state.velocity : projectile.launchDirection
            return VisualEffectModel(
                path: model,
                transform: VisualEffectRuntime.facing(projectile.position, forward: along),
                instanceID: Self.projectileInstanceBase + projectile.id
            )
        }
    }

    /// The flight lights of live projectiles, then the muzzle and blast flashes.
    func projectileAndFlashLights() -> [RenderPointLight] {
        let plugin = explosions.itemPlugin
        let records = effects.records
        let flying = (game.combat.archery?.projectiles.live ?? []).compactMap { projectile in
            records.resolve(projectile.profile.visuals.light, fromPlugin: plugin).flatMap {
                renderLight($0, at: projectile.position, strength: 1)
            }
        }
        let flashes = effects.flashLights.compactMap {
            renderLight($0.light, at: $0.position, strength: $0.strength)
        }
        return flying + flashes
    }

    /// One `LIGH` at `position`, its colour scaled by `strength`; nil for a dark light.
    func renderLight(
        _ key: ReferenceKey, at position: SIMD3<Float>, strength: Float
    ) -> RenderPointLight? {
        guard
            case let .plugin(name, objectID) = key,
            let record = effects.records.lights
                .record(ResolvedFormID(plugin: name, objectID: objectID))?.record,
            record.radius > 0
        else { return nil }
        return RenderPointLight(
            position: position, radius: Float(record.radius),
            color: record.color * max(0, record.fade) * max(0, strength),
            falloffExponent: max(0.01, record.falloffExponent)
        )
    }

    func showMuzzleFlash(
        _ visuals: ProjectileVisuals, at position: SIMD3<Float>, along direction: SIMD3<Float>
    ) {
        effects.showMuzzleFlash(
            model: visuals.muzzleFlashModel,
            light: effects.records.resolve(
                visuals.muzzleFlashLight,
                fromPlugin: explosions.itemPlugin
            ),
            at: position, along: direction,
            duration: visuals.muzzleFlashDuration
        )
    }

    func showExplosionLight(_ light: ReferenceKey, at position: SIMD3<Float>) {
        effects.addFlashLight(light, at: position, duration: EffectsCoordinator.instantArtDuration)
    }

    /// The blast's `IPDS` on the ground below it, as an impact with no material.
    func playExplosionImpact(_ dataSet: ReferenceKey, at position: SIMD3<Float>) {
        guard
            let id = effects.records.loadOrderFormID(dataSet),
            let resolved = game.combat.archery?.projectiles.impacts?
                .resolve(dataSet: id, material: nil)
        else { return }
        game.combatWorld.playImpact(resolved, at: position)
    }
}
