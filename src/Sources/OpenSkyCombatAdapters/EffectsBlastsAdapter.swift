import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
public import OpenSkyCombatInterface
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
public protocol EffectsBlastsHost: AnyObject, SendableMetatype {
    var effects: any EffectsPort { get }
    var audio: any AudioPort { get }
    var combat: any CombatPort { get }
    var combatWorld: any CombatWorldPort { get }
    var crime: any CrimePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hazardWorld: any HazardWorldPort { get }
    var hazards: any HazardPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
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
        BlastObjects(owner: self).playExplosionSound(sound, at: position)
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

    /// A thin sphere swept along the line through the static world.
    public func explosionObstruction(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Float? {
        let offset = end - start
        let length = simd_length(offset)
        guard length > Self.sightProbeRadius else { return nil }
        return game.combat.sweepProjectile(.sphere(
            center: start, radius: Self.sightProbeRadius, direction: offset / length,
            maximumDistance: length
        ))?.distance
    }

    /// The resident placed objects with `DEST` data inside the radius. Actors are left out.
    public func explosionObjects(within radius: Float, of center: SIMD3<Float>) -> [MeleeTarget] {
        BlastObjects(owner: self).explosionObjects(within: radius, of: center)
    }

    public func applyDestructionDamage(_ amount: Float, to object: ReferenceKey) -> Bool {
        game.scripts.bridge?.damageDestructible(object, amount: amount, forced: false) ?? false
    }

    /// A new reference at the blast, in its cell or the cell around the point, owned
    /// as its source is.
    public func placeExplosionObject(_ placement: ExplosionObjectPlacement) -> Bool {
        BlastObjects(owner: self).placeExplosionObject(placement)
    }

    public func showExplosionModel(_ path: String, at position: SIMD3<Float>) {
        game.effects.showModel(path, at: .point(position), cause: .explosion)
    }

    /// The radius of the sphere that tests a blast's line of sight.
    private static let sightProbeRadius: Float = 1

    /// Above every visual effect instance id, so a projectile keeps its own particles.
    static let projectileInstanceBase = 1 << 30
    /// The smallest light falloff exponent; at 0 the light would not fade at all.
    private static let flattestFalloff: Float = 0.01
    /// A projectile slower than this, squared, has no direction of its own.
    private static let stillSpeedSquared: Float = 1e-6

    /// Each live projectile's model along its velocity.
    public func projectileModels() -> [VisualEffectModel] {
        game.combat.liveProjectiles.compactMap { projectile in
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
        let flying = game.combat.liveProjectiles.compactMap { projectile in
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
        let flash = MuzzleFlash(
            model: visuals.muzzleFlashModel,
            light: game.effects.records.resolve(
                visuals.muzzleFlashLight,
                fromPlugin: game.combat.explosions.itemPlugin
            ),
            duration: visuals.muzzleFlashDuration
        )
        game.effects.showMuzzleFlash(flash, at: position, along: direction)
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
            let resolved = game.combat.projectileImpacts?
                .resolve(dataSet: id, material: nil)
        else { return }
        game.combatWorld.playImpact(resolved, at: position)
    }
}

extension EffectsBlastsAdapter {
    /// Plays explosion sounds and finds and places the objects an explosion touches.
    struct BlastObjects {
        let owner: EffectsBlastsAdapter

        func playExplosionSound(_ sound: ReferenceKey, at position: SIMD3<Float>) {
            let game = owner.game
            guard
                case let .plugin(name, objectID) = sound,
                name == EffectsBasePlugin.name.lowercased() else { return }
            game.audio.soundDirector?.forcePlaySound(formID: FormID(objectID), position: position)
        }

        func explosionObjects(within radius: Float, of center: SIMD3<Float>) -> [MeleeTarget] {
            let game = owner.game
            guard radius > 0, let bridge = game.scripts.bridge else { return [] }
            let streamer = game.streamer
            let entries = streamer.interiorScene.map { $0.references.sortedEntries() }
                ?? streamer.composition.cells.values.flatMap { $0.references.sortedEntries() }
            return entries.compactMap { entry in
                guard let placed = entry.placedReference else { return nil }
                let position = placed.placement.position
                guard
                    simd_distance(position, center) <= radius,
                    bridge.destructionHealthLeft(of: entry.key) != nil
                else { return nil }
                return MeleeTarget(key: entry.key, feet: position)
            }
        }

        func placeExplosionObject(_ placement: ExplosionObjectPlacement) -> Bool {
            let game = owner.game
            guard let formID = game.effects.records.loadOrderFormID(placement.base) else {
                return false
            }
            let position = placement.position
            let cell = placement.location ?? game.streamer.interiorScene?.location
                ?? .exterior(CellCoordinate(containing: position))
            let spawn = ReferenceSpawnState(
                base: formID, location: cell,
                placement: PlacedReference.Placement(
                    position: position,
                    rotation: placement.rotation
                )
            )
            let key = game.worldState.allocateGeneratedKey()
            game.worldState.set(spawn, for: key, in: cell)
            if let source = placement.ownerSource, let owner = game.crime.crimeOwner(of: source) {
                game.scripts.bridge?.setScriptedOwner(owner, of: key)
            }
            return true
        }
    }
}
