import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
public import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `EffectsBlastsAdapter` reads from the session.
@MainActor
public protocol EffectsBlastsHost: AnyObject {
    var effects: any EffectsPort { get }
    var audio: any AudioPort { get }
    var combat: any CombatPort { get }
    var combatWorld: any CombatWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hazardWorld: any HazardWorldPort { get }
    var hazards: any HazardPort { get }
}

/// Part of `EffectsWorldAdapter`, over its own narrow host.
public struct EffectsBlastsAdapter {
    public let game: any EffectsBlastsHost
    public let state: EffectsPartState
}

extension EffectsBlastsAdapter {
    public func explosionTargets() -> [MeleeTarget] {
        game.hazardWorld.hazardCandidates()
    }

    public func explosionViewer() -> SIMD3<Float>? {
        state.cameraPosition
    }

    public func applyExplosionDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        game.combat.applyHealthDamage(amount, to: target, attacker: nil)
    }

    /// The sound index is built from the base plugin, so only its sounds play.
    public func playExplosionSound(_ sound: ReferenceKey, at position: SIMD3<Float>) {
        guard
            case let .plugin(name, objectID) = sound,
            name == EffectsWorldAdapter.basePlugin.lowercased() else { return }
        game.audio.soundDirector?.forcePlaySound(formID: FormID(objectID), position: position)
    }

    public func startExplosionImageSpace(_ modifier: ReferenceKey, strength: Float) {
        guard let gameSession = game.gameSession else { return }
        game.effects.startModifier(modifier, strength: strength, on: &gameSession.imageSpace)
    }

    public func placeExplosionHazard(_ hazard: ReferenceKey, at position: SIMD3<Float>) -> Bool {
        guard let spec = game.hazardWorld.hazardSpec(for: hazard) else { return false }
        game.hazards.spawn(HazardPlacement(
            id: state.nextHazardKey(),
            spec: spec,
            position: position
        ))
        return true
    }

    public func showExplosionModel(_ path: String, at position: SIMD3<Float>) {
        game.effects.showModel(path, at: .point(position), cause: .explosion)
    }

    /// Above every visual effect instance id, so a projectile keeps its own particles.
    public static let projectileInstanceBase = 1 << 30
    /// The smallest light falloff exponent; at 0 the light would not fade at all.
    private static let flattestFalloff: Float = 0.01
    /// A projectile slower than this, squared, has no direction of its own.
    private static let stillSpeedSquared: Float = 1e-6

    /// Each live projectile's model along its velocity.
    public func projectileModels() -> [VisualEffectModel] {
        (game.combat.archery?.projectiles.live ?? []).compactMap { projectile in
            guard let model = projectile.profile.visuals.model else { return nil }
            let along = simd_length_squared(projectile.state.velocity) > Self.stillSpeedSquared
                ? projectile.state.velocity : projectile.launchDirection
            return VisualEffectModel(
                path: model,
                transform: VisualEffectRuntime.facing(projectile.position, forward: along),
                instanceID: Self.projectileInstanceBase + projectile.id
            )
        }
    }

    /// The flight lights of live projectiles, then the muzzle and blast flashes.
    public func projectileAndFlashLights() -> [RenderPointLight] {
        let plugin = game.combat.explosions.itemPlugin
        let records = game.effects.records
        let flying = (game.combat.archery?.projectiles.live ?? []).compactMap { projectile in
            records.resolve(projectile.profile.visuals.light, fromPlugin: plugin).flatMap {
                renderLight($0, at: projectile.position, strength: 1)
            }
        }
        let flashes = game.effects.flashLights.compactMap {
            renderLight($0.light, at: $0.position, strength: $0.strength)
        }
        return flying + flashes
    }

    /// One `LIGH` at `position`, its colour scaled by `strength`; nil for a dark light.
    public func renderLight(
        _ key: ReferenceKey, at position: SIMD3<Float>, strength: Float
    ) -> RenderPointLight? {
        guard
            case let .plugin(name, objectID) = key,
            let record = game.effects.records.lights
                .record(ResolvedFormID(plugin: name, objectID: objectID))?.record,
            record.radius > 0
        else { return nil }
        return RenderPointLight(
            position: position, radius: Float(record.radius),
            color: record.color * max(0, record.fade) * max(0, strength),
            falloffExponent: max(Self.flattestFalloff, record.falloffExponent)
        )
    }

    public func showMuzzleFlash(
        _ visuals: ProjectileVisuals, at position: SIMD3<Float>, along direction: SIMD3<Float>
    ) {
        game.effects.showMuzzleFlash(
            model: visuals.muzzleFlashModel,
            light: game.effects.records.resolve(
                visuals.muzzleFlashLight,
                fromPlugin: game.combat.explosions.itemPlugin
            ),
            at: position, along: direction,
            duration: visuals.muzzleFlashDuration
        )
    }

    public func showExplosionLight(_ light: ReferenceKey, at position: SIMD3<Float>) {
        game.effects.addFlashLight(
            light,
            at: position,
            duration: EffectsCoordinator.instantArtDuration
        )
    }

    /// The blast's `IPDS` on the ground below it, as an impact with no material.
    public func playExplosionImpact(_ dataSet: ReferenceKey, at position: SIMD3<Float>) {
        guard
            let id = game.effects.records.loadOrderFormID(dataSet),
            let resolved = game.combat.archery?.projectiles.impacts?
                .resolve(dataSet: id, material: nil)
        else { return }
        game.combatWorld.playImpact(resolved, at: position)
    }
}
