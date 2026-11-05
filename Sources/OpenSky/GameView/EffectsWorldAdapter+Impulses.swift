// The world hits, explosions, and splashes push through: loose bodies in the streamer's
// solver, actors on their capsules, and the water of the resident cells
// (docs/engine/impulses.md).

import Foundation
import OpenSkyCells
import OpenSkyCombat
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension EffectsWorldAdapter: ImpulseWorld {
    /// The splash sound. No setting names it, so this is the one `SNDR` whose editor
    /// ID says so. [WARNING] Not confirmed against the game.
    static let splashSound = "PHYWaterSplash"

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
            ImpulseBody(
                key: body.key, reference: body.reference, position: body.position,
                velocity: body.linearVelocity, mass: body.definition.mass,
                boundingRadius: body.definition.boundingRadius,
                kind: ImpulseBodyKind(collisionLayer: body.definition.collisionLayer)
            )
        }
    }

    func applyBodyImpulse(_ impulse: BodyImpulse) {
        game.streamer?.dynamicBodies.applyImpulse(
            impulse.linear, at: impulse.point, to: impulse.key, angularScale: impulse.angularScale
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

    func waterFlow(at position: SIMD2<Float>) -> SIMD2<Float>? {
        game.streamer?.sampleWaterFlow(at: position)
    }

    func raceSize(of actor: ReferenceKey) -> Int {
        let normal = 1
        guard
            let base = actor == .player ? nil : game.streamer?.residentActorEntry(key: actor)?
                .placedActor?.base,
            let resolver = game.worldData?.actorValueBaselines?.resolver
        else { return normal }
        let identity = ActorIdentityRecords(resolver: resolver)
        let race = identity.race(ofBase: base).flatMap { identity.races[$0.rawValue] }
        return race?.details.properties.map { Int($0.size) } ?? normal
    }

    /// OpenSky has no knockdown ragdoll for the living, so a knockdown pushes too.
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
        guard splash.weight != .silent else { return }
        game.audio.soundDirector?.playAnimationSound(
            editorID: Self.splashSound, source: splash.source ?? .player, at: splash.position
        )
    }
}
