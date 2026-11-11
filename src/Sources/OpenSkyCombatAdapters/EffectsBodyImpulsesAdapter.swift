import Foundation
import OpenSkyAudio
import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyEffects
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// What `EffectsBodyImpulsesAdapter` reads from the session.
@MainActor
public protocol EffectsBodyImpulsesHost: AnyObject, SendableMetatype {
    var actorWorld: any ActorWorldPort { get }
    var audio: any AudioPort { get }
    var combat: any CombatPort { get }
    var combatWorld: any CombatWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hazardWorld: any HazardWorldPort { get }
    var magicWorld: any MagicWorldPort { get }
    var mapWorld: any MapWorldPort { get }
    var ragdoll: any RagdollPort { get }
    var renderer: (any RendererPort)? { get }
    var streamer: any CellStreamerPort { get }
    var combatRecords: (any CombatRecordsPort)? { get }
}

/// Part of `EffectsWorldAdapter`, over its own narrow host.
public struct EffectsBodyImpulsesAdapter {
    public let game: any EffectsBodyImpulsesHost
    public let effects: any EffectsPort
    public let locator: EffectsLocatorAdapter
}

extension EffectsBodyImpulsesAdapter {
    /// Closer than this, in units, the push from the source has no direction.
    private static let sameSpot: Float = 0.001

    // The splash sound. No setting names it, so this is the one `SNDR` whose editor
    // ID says so. [WARNING] Not confirmed against the game.

    public func makeImpulses(world: any ImpulseWorld) -> ImpulseRuntime {
        guard let settings = game.combatRecords?.gameSettings
        else { return ImpulseRuntime(world: world) }
        let text: GameTextResolver = { [game] in game.mapWorld.text($0) }
        return ImpulseRuntime(
            settings: ImpulseSettings.resolve(store: settings),
            water: WaterImpactSettings.resolve(store: settings, text: text),
            world: world
        )
    }

    public func impulseBodies() -> [ImpulseBody] {
        (game.streamer.dynamicBodies.bodies).map { body in
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
        return game.streamer.sampleTerrain(at: SIMD2(touch.point.x, touch.point.y))?.material
    }

    /// The body's material names the impact data set; the surface it hit picks the entry,
    /// as a weapon's impact does.
    public func playCollision(_ collision: BodyCollision) {
        guard
            let store = game.combatRecords?.footstepStore,
            let dataSet = store.materialParents.impactDataSet(of: collision.material),
            let impact = MeleeImpactResolver(footsteps: store).resolve(
                dataSet: dataSet,
                material: collision.surface
            )
        else { return }
        game.combatWorld.playImpact(impact, at: collision.position, gain: collision.gain)
    }

    public func applyBodyImpulse(_ impulse: BodyImpulse) {
        game.streamer.dynamicBodies.applyImpulse(
            impulse.linear, at: impulse.point, to: impulse.key, angularScale: impulse.angularScale,
            angular: impulse.angular
        )
    }

    /// The living: a corpse lies in its ragdoll.
    public func impulseActors() -> [MeleeTarget] {
        splashesAndActors.impulseActors()
    }

    public func waterContacts(_ contacts: [WaterSample]) {
        game.renderer?.updateWaders(contacts.compactMap { contact in
            contact.waterHeight.map {
                (key: contact.key, position: SIMD3(contact.position.x, contact.position.y, $0))
            }
        })
    }

    public func waterHeight(at position: SIMD2<Float>) -> Float? {
        game.streamer.sampleWaterHeight(at: position)
    }

    public func waterCurrent(at point: SIMD3<Float>) -> SIMD3<Float>? {
        game.streamer.water(at: point)?.current
    }

    public func isDangerousWater(at point: SIMD3<Float>) -> Bool {
        game.streamer.water(at: point)?.isDangerous ?? false
    }

    public func raceSize(of actor: ReferenceKey) -> Int {
        race(of: actor)?.details.properties.map { Int($0.size) } ?? 1
    }

    /// How a current pushes `actor`: its race size and whether it only swims.
    public func waterPushRace(of actor: ReferenceKey) -> WaterPushRace {
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

    public func isPushable(_ actor: ReferenceKey) -> Bool {
        !(race(of: actor)?.flags.contains(.notPushable) ?? false)
    }

    public func race(of actor: ReferenceKey) -> Race? {
        guard
            let base = actor == .player ? nil : game.streamer.residentActorEntry(key: actor)?
                .placedActor?.base,
            let resolver = game.combatRecords?.actorValueBaselines?.resolver
        else { return nil }
        let identity = ActorIdentityRecords(resolver: resolver)
        return identity.race(ofBase: base).flatMap { identity.races[$0.rawValue] }
    }

    public func actorHealth(of actor: ReferenceKey) -> (current: Float, maximum: Float)? {
        game.combatWorld.health(of: actor)
    }

    /// Every knockdown lands here. A "No Knockdowns" race staggers instead. An actor
    /// with no ragdoll, and the player, slides on its capsule at the knock's speed.
    public func knockDown(
        _ actor: ReferenceKey,
        from source: SIMD3<Float>,
        magnitude: Float
    ) -> Bool {
        guard magnitude.isFinite, magnitude != 0 else { return false }
        if race(of: actor)?.flags.contains(.noKnockdowns) == true {
            return game.magicWorld.staggerActor(actor, magnitude: 1)
        }
        let downTime = game.combat.impulses?.settings.knockdownTime
            ?? ImpulseSettings.vanilla.knockdownTime
        if game.ragdoll.knockDown(actor, from: source, magnitude: magnitude, downTime: downTime) {
            return true
        }
        guard let feet = locator.trapPosition(of: actor) else { return false }
        let away = SIMD3(feet.x - source.x, feet.y - source.y, 0)
        guard simd_length(away) > Self.sameSpot else { return false }
        let speed = magnitude * GameplayImpulse.havokScale
        return knockActor(actor, velocity: simd_normalize(away) * speed, knockdown: true)
    }

    /// A push along the ground on the actor's capsule.
    public func knockActor(
        _ actor: ReferenceKey,
        velocity: SIMD3<Float>,
        knockdown _: Bool
    ) -> Bool {
        guard simd_length(velocity) > 0, velocity.x.isFinite, velocity.y.isFinite else {
            return false
        }
        guard actor == .player else {
            return game.streamer.knockActor(actor, velocity: velocity)
        }
        game.gameSession?.knockPlayer(velocity)
        return true
    }

    public func applyPhysicsDamage(_ amount: Float, to actor: ReferenceKey) -> Bool {
        game.combat.applyHealthDamage(amount, to: actor, attacker: nil)
    }

    public func showSplash(_ splash: SplashEvent) {
        splashesAndActors.showSplash(splash)
    }
}

extension EffectsBodyImpulsesAdapter {
    var splashesAndActors: EffectsSplashesAndActors {
        EffectsSplashesAndActors(game: game, effects: effects)
    }
}

struct EffectsSplashesAndActors {
    let game: any EffectsBodyImpulsesHost
    let effects: any EffectsPort

    func showSplash(_ splash: SplashEvent) {
        effects.showModel(splash.model, at: .point(splash.position), cause: .impact)
        game.renderer?.addWaterRipple(
            at: splash.position, strength: splash.weight.rippleStrength
        )
        guard let sound = splash.weight.sound else { return }
        game.audio.soundDirector?.playAnimationSound(
            editorID: sound, source: splash.source ?? .player, at: splash.position
        )
    }

    /// The living: a corpse lies in its ragdoll.
    func impulseActors() -> [MeleeTarget] {
        game.hazardWorld.hazardCandidates().filter { target in
            target.key == .player || game.actorWorld.combatActor(key: target.key)?.isDead == false
        }
    }
}
