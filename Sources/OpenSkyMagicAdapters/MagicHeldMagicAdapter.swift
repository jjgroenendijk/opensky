import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEffects
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyNavigation
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `MagicHeldMagicAdapter` reads from the session.
@MainActor
public protocol MagicHeldMagicHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hazardWorld: any HazardWorldPort { get }
    var hazards: any HazardPort { get }
    var magic: any MagicPort { get }
    var mapWorld: any MapWorldPort { get }
    var menuWorld: any MenuWorldPort { get }
    var renderer: (any RendererPort)? { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `MagicWorldAdapter`, over its own narrow host.
public struct MagicHeldMagicAdapter {
    public unowned let owner: MagicWorldAdapter
    public unowned let game: any MagicHeldMagicHost
}

extension MagicHeldMagicAdapter {
    public func commandActor(_ actor: ReferenceKey, for caster: ReferenceKey) {
        owner.summonedActors.enlist(actor, for: caster)
    }

    public func livingActors(near key: ReferenceKey, radius: Float) -> [ReferenceKey] {
        guard let center = feet(of: key) else { return [] }
        let player = [MeleeTarget(key: .player, feet: game.combat.meleeAttacker.feet)]
        let others = game.actorWorld.combatActors().filter { !$0.isDead }
            .map { MeleeTarget(key: $0.key, feet: $0.feet) }
        return (player + others)
            .filter { $0.key != key && simd_distance($0.feet, center) <= radius }
            .map(\.key)
    }

    public func changeRace(of key: ReferenceKey, to race: FormID) -> Bool {
        game.menuWorld.setRace(of: key, to: race)
    }

    public func markEaten(_ key: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: key) {
            $0.setFlag(ScriptedStateName.eaten, true)
        }
    }

    public func aimRay(of key: ReferenceKey) -> MagicAimRay? {
        if key == .player {
            guard let gameSession = game.gameSession else { return nil }
            return MagicAimRay(
                origin: gameSession.freeFlyCamera.position,
                direction: simd_normalize(gameSession.freeFlyCamera.forward)
            )
        }
        guard let eye = owner.spellDelivery.actorCastOrigin(of: key) else { return nil }
        let toward = owner.spellDelivery.castTarget(of: key) - eye
        guard simd_length(toward) > 0 else { return nil }
        return MagicAimRay(origin: eye, direction: simd_normalize(toward))
    }

    /// The nearest loose body whose bounding sphere the aim ray passes through.
    public func telekinesisTarget(for caster: ReferenceKey, within reach: Float) -> ReferenceKey? {
        guard let ray = aimRay(of: caster), let bodies = game.streamer?.dynamicBodies.bodies
        else { return nil }
        let hits = bodies.compactMap { body -> (key: ReferenceKey, along: Float)? in
            let along = simd_dot(body.position - ray.origin, ray.direction)
            guard along > 0, along <= reach else { return nil }
            let miss = simd_distance(ray.origin + ray.direction * along, body.position)
            return miss <= body.definition.boundingRadius ? (body.key, along) : nil
        }
        return hits.min { $0.along < $1.along }?.key
    }

    public func heldBody(_ key: ReferenceKey) -> MagicHeldBody? {
        guard let body = game.streamer?.dynamicBodies.body(for: key) else { return nil }
        return MagicHeldBody(
            position: body.position, velocity: body.linearVelocity, mass: body.definition.mass
        )
    }

    public func pushBody(_ key: ReferenceKey, impulse: SIMD3<Float>) {
        guard let body = game.streamer?.dynamicBodies.body(for: key) else { return }
        game.streamer?.dynamicBodies.applyImpulse(impulse, at: body.position, to: key)
    }

    /// An NPC is held through the ridden-actor hold, which steers its pose each frame.
    /// The player is not lifted; the grab paralyses them instead.
    public func holdActor(_ actor: ReferenceKey, at point: SIMD3<Float>?) {
        guard actor != .player, let streamer = game.streamer else { return }
        guard let point else {
            if let ground = feet(of: actor).map({ SIMD3($0.x, $0.y, groundHeight(near: actor)) }) {
                streamer.steerRiddenActor(actor, to: ground, yaw: 0)
            }
            streamer.releaseRiddenActor(actor)
            owner.grabbedActors.remove(actor)
            return
        }
        if !owner.grabbedActors.contains(actor) {
            guard streamer.takeRiddenActor(actor) != nil else { return }
            owner.grabbedActors.insert(actor)
        }
        streamer.steerRiddenActor(actor, to: point, yaw: 0)
    }

    /// The player is knocked back; an NPC is knocked down along the throw.
    public func throwActor(_ actor: ReferenceKey, along direction: SIMD3<Float>, force: Float) {
        let flat = SIMD3(direction.x, direction.y, 0)
        guard simd_length(flat) > 0 else { return }
        guard actor == .player else {
            guard let feet = feet(of: actor) else { return }
            _ = game.effectsWorld.knockDown(
                actor, from: feet - simd_normalize(flat) * 100, magnitude: force
            )
            return
        }
        game.gameSession?.knockPlayer(
            simd_normalize(flat) * force * Self.throwSpeedPerForce
        )
    }

    /// `fMagicGrabActorThrowForce` to speed, units per second. [WARNING] Not confirmed;
    /// the same scale `PushActorAway` uses.
    public static let throwSpeedPerForce: Float = 100

    /// The player's nearest tracked quest target, reached over the navmesh.
    public func guidePath(for caster: ReferenceKey) -> MagicGuidePath {
        guard caster == .player, let start = feet(of: .player) else { return .noMarker }
        let targets = game.mapWorld.questTargets.map(\.position)
        guard let target = targets.min(by: { simd_distance($0, start) < simd_distance($1, start) })
        else { return .noMarker }
        let query = NavigationPathQuery(
            start: start, target: target, capsuleRadius: PlayerCapsule.standard.radius
        )
        guard case let .path(path) = game.streamer?.findPath(query) ?? .miss(.disconnected) else {
            return .noPath
        }
        return .path([start] + path.waypoints + [target])
    }

    @discardableResult
    public func placeHazard(_ hazard: ReferenceKey, at point: SIMD3<Float>) -> Bool {
        guard let spec = game.hazardWorld.store?.spec(for: hazard) else { return false }
        game.hazards.spawn(HazardPlacement(
            id: game.effectsWorld.nextHazardKey(), spec: spec, position: point
        ))
        return true
    }

    /// Detect Life's `EFSH` on a painted actor, until the paint ends.
    public func paintActor(_ actor: ReferenceKey, shader: FormID, plugin: String, shown: Bool) {
        let effects = game.effectsWorld.effects
        guard let key = effects.records.resolve(shader, fromPlugin: plugin) else { return }
        if shown {
            effects.attach(key, to: .actor(actor), cause: .spellHit, duration: nil)
        } else {
            effects.detach(key, from: .actor(actor))
        }
    }

    /// Hands the renderer this frame's spell lights: a self-cast light floats beside its
    /// actor, an aimed one stays where it landed. A casting light floats at the same
    /// place while its caster readies the spell. Projectile and flash lights follow.
    public func publishMagicLights() {
        guard let renderer = game.renderer else { return }
        let effects = game.effectsWorld
        let spells = game.magic.magicLights.compactMap { light -> RenderPointLight? in
            let position: SIMD3<Float>? = switch light.anchor {
            case let .point(point): point
            case let .actor(key): handLightPosition(of: key)
            }
            return position.flatMap { effects.renderLight(light.light, at: $0, strength: 1) }
        }
        let casting = owner.castingLights.keys.sorted { "\($0)" < "\($1)" }.compactMap { caster in
            owner.castingLights[caster].flatMap { light in
                handLightPosition(of: caster).flatMap {
                    effects.renderLight(light, at: $0, strength: 1)
                }
            }
        }
        renderer.transientPointLights = spells + casting + effects.projectileAndFlashLights()
    }

    private func handLightPosition(of key: ReferenceKey) -> SIMD3<Float>? {
        guard let ray = aimRay(of: key) else { return nil }
        return MagicHoldCore.lightPosition(
            eye: ray.origin, forward: ray.direction, settings: game.magic.holdSettings
        )
    }

    /// Shows or drops the `MGEF` casting light of `caster`, written in `plugin`.
    public func showCastingLight(
        _ light: FormID, plugin: String, caster: ReferenceKey, shown: Bool
    ) {
        guard shown else {
            owner.castingLights[caster] = nil
            return
        }
        owner.castingLights[caster] = game.effectsWorld.effects.records.resolve(
            light,
            fromPlugin: plugin
        )
    }

    private func feet(of key: ReferenceKey) -> SIMD3<Float>? {
        guard key != .player else { return game.gameSession?.walkController.feetPosition }
        return game.streamer?.npcTransform(for: key)?.position
            ?? game.scripts.bridge?.referenceState(for: key)?.transform.position
    }

    /// A let-go actor lands at the height of the caster's ground: the player's feet.
    private func groundHeight(near _: ReferenceKey) -> Float {
        game.gameSession?.walkController.feetPosition.z ?? 0
    }

    /// Hands the renderer how far each dismissed summon has faded, by its reference.
    public func publishSummonFades() {
        guard let gameSession = game.gameSession else { return }
        let fades = game.magic.summonFades
        guard !fades.isEmpty || !gameSession.instancePoses.fades.isEmpty else { return }
        gameSession.instancePoses.fades = fades.reduce(into: [:]) { byFormID, entry in
            guard let formID = game.streamer?.referenceEntry(key: entry.key)?.formID else { return }
            byFormID[formID.rawValue] = entry.value
        }
    }
}
