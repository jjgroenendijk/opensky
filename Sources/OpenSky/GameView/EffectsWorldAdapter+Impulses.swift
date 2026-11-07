// The world hits, explosions, and splashes push through: loose bodies in the streamer's
// solver, actors on their capsules, and the water of the resident cells
// (docs/engine/impulses.md).

import Foundation
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombat
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension EffectsWorldAdapter: ImpulseWorld {
    // The splash sound. No setting names it, so this is the one `SNDR` whose editor
    // ID says so. [WARNING] Not confirmed against the game.

    func makeImpulses() -> ImpulseRuntime {
        guard let settings = game.worldData?.gameSettings
        else { return ImpulseRuntime(world: self) }
        let text: GameTextResolver = { [game] in game.mapWorld.text($0) }
        return ImpulseRuntime(
            settings: ImpulseSettings.resolve(store: settings),
            water: WaterImpactSettings.resolve(store: settings, text: text),
            world: self
        )
    }

    func impulseBodies() -> [ImpulseBody] {
        (game.streamer?.dynamicBodies.bodies ?? []).map { body in
            var impulseBody = ImpulseBody(
                key: body.key, reference: body.reference, position: body.position,
                velocity: body.linearVelocity, mass: body.definition.mass,
                boundingRadius: body.definition.boundingRadius,
                kind: ImpulseBodyKind(collisionLayer: body.definition.collisionLayer),
                material: body.definition.material
            )
            impulseBody.surfaceMaterial = surfaceMaterial(of: body.lastSurface)
            return impulseBody
        }
    }

    /// A shape without a `MATT`, such as the land, takes the land texture's under the point.
    private func surfaceMaterial(of touch: DynamicSurfaceTouch?) -> FormID? {
        guard let touch else { return nil }
        if let material = touch.material {
            return material
        }
        return game.streamer?.sampleTerrain(at: SIMD2(touch.point.x, touch.point.y))?.material
    }

    /// The body's material names the impact data set; the surface it hit picks the entry,
    /// as a weapon's impact does.
    func playCollision(_ collision: BodyCollision) {
        guard
            let store = game.worldData?.footstepStore,
            let dataSet = store.materialParents.impactDataSet(of: collision.material),
            let impact = MeleeImpactResolver(footsteps: store).resolve(
                dataSet: dataSet,
                material: collision.surface
            )
        else { return }
        game.combatWorld.playImpact(impact, at: collision.position, gain: collision.gain)
    }

    func applyBodyImpulse(_ impulse: BodyImpulse) {
        game.streamer?.dynamicBodies.applyImpulse(
            impulse.linear, at: impulse.point, to: impulse.key, angularScale: impulse.angularScale,
            angular: impulse.angular
        )
    }

    /// The living: a corpse lies in its ragdoll.
    func impulseActors() -> [MeleeTarget] {
        game.hazardWorld.hazardCandidates().filter { target in
            target.key == .player || game.actorWorld.combatActor(key: target.key)?.isDead == false
        }
    }

    func waterContacts(_ contacts: [WaterSample]) {
        game.renderer?.updateWaders(contacts.compactMap { contact in
            contact.waterHeight.map {
                (key: contact.key, position: SIMD3(contact.position.x, contact.position.y, $0))
            }
        })
    }

    func waterHeight(at position: SIMD2<Float>) -> Float? {
        game.streamer?.sampleWaterHeight(at: position)
    }

    func waterCurrent(at point: SIMD3<Float>) -> SIMD3<Float>? {
        game.streamer?.water(at: point)?.current
    }

    func isDangerousWater(at point: SIMD3<Float>) -> Bool {
        game.streamer?.water(at: point)?.isDangerous ?? false
    }

    func raceSize(of actor: ReferenceKey) -> Int {
        race(of: actor)?.details.properties.map { Int($0.size) } ?? 1
    }

    /// How a current pushes `actor`: its race size and whether it only swims.
    func waterPushRace(of actor: ReferenceKey) -> WaterPushRace {
        let water = game.combat.impulses?.water ?? .vanilla
        let race = race(of: actor)
        guard
            let strong = WaterImpacts.strongCurrent(
                raceSize: race?.details.properties.map { Int($0.size) } ?? 1, settings: water
            )
        else { return .normal }
        let flags = race?.flags ?? []
        return WaterPushRace(
            strongCurrent: strong,
            isSwimOnly: flags.contains(.swims) && flags.isDisjoint(with: [.walks, .flies])
        )
    }

    func isPushable(_ actor: ReferenceKey) -> Bool {
        !(race(of: actor)?.flags.contains(.notPushable) ?? false)
    }

    private func race(of actor: ReferenceKey) -> Race? {
        guard
            let base = actor == .player ? nil : game.streamer?.residentActorEntry(key: actor)?
                .placedActor?.base,
            let resolver = game.worldData?.actorValueBaselines?.resolver
        else { return nil }
        let identity = ActorIdentityRecords(resolver: resolver)
        return identity.race(ofBase: base).flatMap { identity.races[$0.rawValue] }
    }

    func actorHealth(of actor: ReferenceKey) -> (current: Float, maximum: Float)? {
        game.combatWorld.health(of: actor)
    }

    /// Every knockdown lands here. A "No Knockdowns" race staggers instead. An actor
    /// with no ragdoll, and the player, slides on its capsule at the knock's speed.
    func knockDown(_ actor: ReferenceKey, from source: SIMD3<Float>, magnitude: Float) -> Bool {
        guard magnitude.isFinite, magnitude != 0 else { return false }
        if race(of: actor)?.flags.contains(.noKnockdowns) == true {
            return game.magicWorld.staggerActor(actor, magnitude: 1)
        }
        let downTime = game.combat.impulses?.settings.knockdownTime
            ?? ImpulseSettings.vanilla.knockdownTime
        if game.ragdoll.knockDown(actor, from: source, magnitude: magnitude, downTime: downTime) {
            return true
        }
        guard let feet = trapPosition(of: actor) else { return false }
        let away = SIMD3(feet.x - source.x, feet.y - source.y, 0)
        guard simd_length(away) > 0.001 else { return false }
        let speed = magnitude * GameplayImpulse.havokScale
        return knockActor(actor, velocity: simd_normalize(away) * speed, knockdown: true)
    }

    /// A push along the ground on the actor's capsule.
    func knockActor(_ actor: ReferenceKey, velocity: SIMD3<Float>, knockdown _: Bool) -> Bool {
        guard simd_length(velocity) > 0, velocity.x.isFinite, velocity.y.isFinite else {
            return false
        }
        guard actor == .player else {
            return game.streamer?.knockActor(actor, velocity: velocity) ?? false
        }
        game.gameSession?.walkController.knock(velocity)
        return true
    }

    func applyPhysicsDamage(_ amount: Float, to actor: ReferenceKey) -> Bool {
        game.combat.applyHealthDamage(amount, to: actor, attacker: nil)
    }

    func showSplash(_ splash: SplashEvent) {
        effects.showModel(splash.model, at: .point(splash.position), cause: .impact)
        game.renderer?.addWaterRipple(
            at: splash.position, strength: splash.weight == .heavy ? 1 : 0.6
        )
        guard let sound = splash.weight.sound else { return }
        game.audio.soundDirector?.playAnimationSound(
            editorID: sound, source: splash.source ?? .player, at: splash.position
        )
    }
}
