import OpenSkyActorsInterface
public import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMagic
public import OpenSkyMagicInterface
public import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `MagicSpellDeliveryAdapter` reads from the session.
@MainActor
public protocol MagicSpellDeliveryHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var factions: any FactionPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `MagicWorldAdapter`, over its own narrow host.
public struct MagicSpellDeliveryAdapter {
    public let game: any MagicSpellDeliveryHost
}

extension MagicSpellDeliveryAdapter {
    /// Through the arrow's `ProjectileRuntime`, so a spell shares the fixed
    /// step, bounds and impact query. It leaves the payload's own caster.
    @discardableResult
    public func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
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
    public func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        let reach = castReach(within: range)
        let origin: SIMD3<Float>
        let direction: SIMD3<Float>
        if caster == .player {
            guard let gameSession = game.gameSession else { return .none }
            origin = gameSession.freeFlyCamera.position
            direction = ProjectileFlight.normalized(gameSession.freeFlyCamera.forward)
        } else {
            guard let eye = actorCastOrigin(of: caster) else { return .none }
            origin = eye
            direction = ProjectileFlight.normalized(castTarget(of: caster) - eye)
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
    public func castReach(within range: Float) -> Float {
        MagicCore.castReach(
            within: range,
            ceiling: game.combat.archery?.settings.visibleMoveDistance.value ?? 0
        )
    }

    /// An NPC casts at whom it fights: the player, an ally, or a foe of its commander.
    private func spellShooter(for caster: ReferenceKey) -> ProjectileShooter? {
        guard caster != .player else { return game.combat.projectileShooter }
        guard let origin = actorCastOrigin(of: caster) else { return nil }
        return ProjectileShooter(
            key: caster,
            origin: origin,
            aim: ProjectileFlight.normalized(castTarget(of: caster) - origin),
            isFirstPerson: false,
            location: game.streamer?.cellLocation(of: caster)
        )
    }

    /// An NPC's eye, scaled with the actor.
    public func actorCastOrigin(of key: ReferenceKey) -> SIMD3<Float>? {
        guard
            let streamer = game.streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor
        else { return nil }
        let moved = streamer.npcTransform(for: key)
            ?? game.worldState.component(ReferenceTransformOverride.self, for: key)
        let feet = moved?.position ?? actor.placement.position
        return feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight * actor.scale)
    }

    /// The middle of the target's capsule, so a miss means the target moved,
    /// not that the caster aimed at the floor.
    public func castTarget(of caster: ReferenceKey) -> SIMD3<Float> {
        if
            let key = game.combat.loop?.combatTarget(of: caster), key != .player,
            let target = game.combat.combatActor(key: key)
        {
            return target.feet + SIMD3(0, 0, target.capsule.centreHeight)
        }
        let player = game.combat.meleeAttacker
        return player.feet + SIMD3(0, 0, player.capsule.centreHeight)
    }

    /// How far the wall ray starts from the impact, so the surface a projectile hit
    /// does not count as the wall.
    public static let sightStartOffset: Float = 2

    public func actor(_ target: ReferenceKey, faces source: ReferenceKey) -> Bool {
        guard let holder = standing(target), let caster = standing(source) else { return true }
        return WardArc.covers(
            holder: SIMD2(holder.feet.x, holder.feet.y), facing: holder.facing,
            source: SIMD2(caster.feet.x, caster.feet.y)
        )
    }

    public func point(_ point: SIMD3<Float>, canSee target: ReferenceKey) -> Bool {
        guard let actor = standing(target) else { return true }
        let centre = actor.feet + SIMD3(0, 0, PlayerCapsule.centreHeight(height: actor.height))
        let path = centre - point
        let distance = simd_length(path)
        guard distance > Self.sightStartOffset else { return true }
        let direction = path / distance
        let hit = game.combat.sweepProjectile(.sphere(
            center: point + direction * Self.sightStartOffset,
            radius: 0,
            direction: direction,
            maximumDistance: distance - Self.sightStartOffset
        ))
        return hit == nil
    }

    private func standing(_ key: ReferenceKey) -> StandingActor? {
        if key == .player {
            let player = game.combat.meleeAttacker
            return StandingActor(
                feet: player.feet, facing: player.facing, height: player.capsule.height
            )
        }
        guard let actor = game.actorWorld.combatActors().first(where: { $0.key == key })
        else { return nil }
        return StandingActor(
            feet: actor.feet, facing: actor.facing, height: actor.capsule.height * actor.scale
        )
    }

    public func keyword(editorID: String) -> ReferenceKey? {
        game.worldData?.locationStore?.keywords.keyword(editorID: editorID)
            .map { ReferenceKey(resolved: $0.id) }
    }

    /// The player's runes wait for hostile NPCs; an NPC's rune waits for the player.
    public func runeTriggers(for caster: ReferenceKey) -> [MeleeTarget] {
        let living = Set(game.actorWorld.combatActors().filter { !$0.isDead }.map(\.key))
        guard caster != .player else {
            return game.combat.projectileTargets().filter {
                living.contains($0.key) && game.factions.hostility(of: $0.key) == .hostile
            }
        }
        guard game.factions.hostility(of: caster) == .hostile else { return [] }
        return [playerTarget]
    }

    public func spellHitCandidates() -> [MeleeTarget] {
        game.combat.projectileTargets() + [playerTarget]
    }

    public var isOutdoors: Bool {
        game.streamer.map { !$0.isInterior } ?? false
    }

    public func projectileProximity(of payload: SpellPayload) -> Float {
        guard let link = payload.projectile else { return 0 }
        return game.combat.items?.projectileProfile(link)?.explosionProximity ?? 0
    }

    /// The rune's `PROJ` explosion, as a spell projectile's impact sets it off.
    public func detonateRune(_ payload: SpellPayload, at position: SIMD3<Float>) {
        let explosions = game.combat.explosions
        guard
            let link = payload.projectile,
            let profile = game.combat.items?.projectileProfile(link),
            let spec = explosions.spec(itemLink: profile.explosion)
        else { return }
        explosions.detonate(spec, at: position, cause: .spell)
    }

    private var playerTarget: MeleeTarget {
        MeleeTarget(key: .player, feet: game.combat.meleeAttacker.feet)
    }
}

private struct StandingActor {
    let feet: SIMD3<Float>
    let facing: Float
    let height: Float
}
