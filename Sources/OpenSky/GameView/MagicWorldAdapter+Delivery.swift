// Aimed spell delivery: where a spell projectile leaves from, and what the aim
// ray reaches. The ray uses the projectile queries but no aim assist. PROJ
// lookups use the combat item index, so without one no spell projectile flies.

import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension MagicWorldAdapter {
    /// Through the arrow's `ProjectileRuntime`, so a spell shares the fixed
    /// step, bounds and impact query. It leaves the payload's own caster.
    @discardableResult
    func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
        guard
            let runtime = game.combat.archery,
            let link = payload.projectile,
            let profile = game.combat.items?.projectileProfile(link),
            let shooter = spellShooter(for: payload.caster)
        else { return false }
        return runtime.projectiles.fire(
            ProjectileShot.spell(profile: profile, payload: payload),
            from: shooter
        ) != nil
    }

    /// The player casts from the camera, an NPC from its eye. Range zero
    /// bounds nothing, and the projectile ceiling applies; past it UESP says
    /// a shot "will phase through targets without doing any damage".
    func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        let reach = castReach(within: range)
        let origin: SIMD3<Float>
        let direction: SIMD3<Float>
        if caster == .player {
            guard let renderer = game.renderer else { return .none }
            origin = renderer.freeFlyCamera.position
            direction = ProjectileFlight.normalized(renderer.freeFlyCamera.forward)
        } else {
            guard let eye = actorCastOrigin(of: caster) else { return .none }
            origin = eye
            direction = ProjectileFlight.normalized(playerCastTarget() - eye)
        }
        let combat = game.combat
        let candidates = combat.projectileTargets()
        let impact = ProjectileImpactQuery.first(
            step: ProjectileStep(from: origin, to: origin + direction * reach, radius: 0),
            targets: candidates,
            shooter: caster,
            sweep: { combat.sweepProjectile($0) }
        )
        return SpellAim(
            target: impact?.target,
            position: impact?.position ?? origin + direction * reach,
            candidates: candidates
        )
    }

    /// How far a cast of SPIT range `range` reaches in this session.
    func castReach(within range: Float) -> Float {
        MagicCore.castReach(
            within: range,
            ceiling: game.combat.archery?.settings.visibleMoveDistance.value ?? 0
        )
    }

    /// An NPC casts at the player, the only target `StartCombat` accepts.
    private func spellShooter(for caster: ReferenceKey) -> ProjectileShooter? {
        guard caster != .player else { return game.combat.projectileShooter }
        guard let origin = actorCastOrigin(of: caster) else { return nil }
        return ProjectileShooter(
            key: caster,
            origin: origin,
            aim: ProjectileFlight.normalized(playerCastTarget() - origin),
            isFirstPerson: false,
            location: game.streamer?.cellLocation(of: caster)
        )
    }

    /// An NPC's eye, scaled with the actor.
    private func actorCastOrigin(of key: ReferenceKey) -> SIMD3<Float>? {
        guard
            let streamer = game.streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor
        else { return nil }
        let moved = streamer.npcTransform(for: key)
            ?? game.worldState.component(ReferenceTransformOverride.self, for: key)
        let feet = moved?.position ?? actor.placement.position
        return feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight * actor.scale)
    }

    /// The middle of the player's capsule, so a miss means the target moved,
    /// not that the caster aimed at the floor.
    private func playerCastTarget() -> SIMD3<Float> {
        let player = game.combat.meleeAttacker
        return player.feet + SIMD3(0, 0, player.capsule.height / 2)
    }
}
