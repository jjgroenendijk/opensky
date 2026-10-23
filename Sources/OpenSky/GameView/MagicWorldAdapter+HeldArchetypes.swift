// The world half of the later magic archetypes: commanding a summon, race changes,
// the eaten flag, Telekinesis bodies, Grab Actor holds, the Guide path, Detect Life
// paint, and spell lights (docs/engine/magic-archetypes.md).

import OpenSkyCombat
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyNavigation
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension MagicWorldAdapter {
    func commandActor(_ actor: ReferenceKey, for caster: ReferenceKey) {
        enlist(actor, for: caster)
    }

    func livingActors(near key: ReferenceKey, radius: Float) -> [ReferenceKey] {
        guard let center = feet(of: key) else { return [] }
        let player = [MeleeTarget(key: .player, feet: game.combat.meleeAttacker.feet)]
        let others = game.actorWorld.combatActors().filter { !$0.isDead }
            .map { MeleeTarget(key: $0.key, feet: $0.feet) }
        return (player + others)
            .filter { $0.key != key && simd_distance($0.feet, center) <= radius }
            .map(\.key)
    }

    func changeRace(of key: ReferenceKey, to race: FormID) -> Bool {
        game.menuWorld.setRace(of: key, to: race)
    }

    func markEaten(_ key: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: key) {
            $0.setFlag(ScriptedStateName.eaten, true)
        }
    }

    func aimRay(of key: ReferenceKey) -> MagicAimRay? {
        if key == .player {
            guard let gameSession = game.gameSession else { return nil }
            return MagicAimRay(
                origin: gameSession.freeFlyCamera.position,
                direction: simd_normalize(gameSession.freeFlyCamera.forward)
            )
        }
        guard let eye = actorCastOrigin(of: key) else { return nil }
        let toward = castTarget(of: key) - eye
        guard simd_length(toward) > 0 else { return nil }
        return MagicAimRay(origin: eye, direction: simd_normalize(toward))
    }

    /// The nearest loose body whose bounding sphere the aim ray passes through.
    func telekinesisTarget(for caster: ReferenceKey, within reach: Float) -> ReferenceKey? {
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

    func heldBody(_ key: ReferenceKey) -> MagicHeldBody? {
        guard let body = game.streamer?.dynamicBodies.body(for: key) else { return nil }
        return MagicHeldBody(
            position: body.position, velocity: body.linearVelocity, mass: body.definition.mass
        )
    }

    func pushBody(_ key: ReferenceKey, impulse: SIMD3<Float>) {
        guard let body = game.streamer?.dynamicBodies.body(for: key) else { return }
        game.streamer?.dynamicBodies.applyImpulse(impulse, at: body.position, to: key)
    }

    /// An NPC is held through the ridden-actor hold, which steers its pose each frame.
    /// The player is not lifted; the grab paralyses them instead.
    func holdActor(_ actor: ReferenceKey, at point: SIMD3<Float>?) {
        guard actor != .player, let streamer = game.streamer else { return }
        guard let point else {
            if let ground = feet(of: actor).map({ SIMD3($0.x, $0.y, groundHeight(near: actor)) }) {
                streamer.steerRiddenActor(actor, to: ground, yaw: 0)
            }
            streamer.releaseRiddenActor(actor)
            grabbedActors.remove(actor)
            return
        }
        if !grabbedActors.contains(actor) {
            guard streamer.takeRiddenActor(actor) != nil else { return }
            grabbedActors.insert(actor)
        }
        streamer.steerRiddenActor(actor, to: point, yaw: 0)
    }

    /// The player is knocked back; an NPC has no outside velocity, so it lands where
    /// it was let go.
    func throwActor(_ actor: ReferenceKey, along direction: SIMD3<Float>, force: Float) {
        guard actor == .player, let gameSession = game.gameSession else { return }
        let flat = SIMD3(direction.x, direction.y, 0)
        guard simd_length(flat) > 0 else { return }
        gameSession.walkController.knock(simd_normalize(flat) * force * Self.throwSpeedPerForce)
    }

    /// `fMagicGrabActorThrowForce` to speed, units per second. [WARNING] Not confirmed;
    /// the same scale `PushActorAway` uses.
    static let throwSpeedPerForce: Float = 100

    /// The player's nearest tracked quest target, reached over the navmesh.
    func guidePath(for caster: ReferenceKey) -> MagicGuidePath {
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
    func placeHazard(_ hazard: ReferenceKey, at point: SIMD3<Float>) -> Bool {
        guard let spec = game.hazardWorld.store?.spec(for: hazard) else { return false }
        game.hazards.spawn(HazardPlacement(
            id: game.effectsWorld.nextHazardKey(), spec: spec, position: point
        ))
        return true
    }

    /// Detect Life's `EFSH` on a painted actor, until the paint ends.
    func paintActor(_ actor: ReferenceKey, shader: FormID, plugin: String, shown: Bool) {
        let effects = game.effectsWorld.effects
        guard let key = effects.records.resolve(shader, fromPlugin: plugin) else { return }
        if shown {
            effects.attach(key, to: .actor(actor), cause: .spellHit, duration: nil)
        } else {
            effects.detach(key, from: .actor(actor))
        }
    }

    /// Hands the renderer this frame's spell lights: a self-cast light floats beside its
    /// actor, an aimed one stays where it landed.
    func publishMagicLights() {
        guard let renderer = game.renderer else { return }
        let lights = game.effectsWorld.effects.records.lights
        let settings = game.magic.holdSettings
        renderer.transientPointLights = game.magic.magicLights.compactMap { light in
            guard
                case let .plugin(name, objectID) = light.light,
                let record = lights.record(ResolvedFormID(plugin: name, objectID: objectID))?
                    .record,
                record.radius > 0
            else { return nil }
            let position: SIMD3<Float>
            switch light.anchor {
            case let .point(point):
                position = point
            case let .actor(key):
                guard let ray = aimRay(of: key) else { return nil }
                position = MagicHoldCore.lightPosition(
                    eye: ray.origin, forward: ray.direction, settings: settings
                )
            }
            return RenderPointLight(
                position: position, radius: Float(record.radius),
                color: record.color * max(0, record.fade),
                falloffExponent: max(0.01, record.falloffExponent)
            )
        }
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
}
