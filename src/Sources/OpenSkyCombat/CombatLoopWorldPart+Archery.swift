// An NPC archer's shot: its own bow and arrow, aimed by the game's NPC rules (lead,
// tracker noise, spread). See docs/engine/archery.md, NPC archers.

import OpenSkyActorsInterface
public import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyPhysics
import simd

/// One NPC shot: who shoots, at what, with which bow.
nonisolated public struct CombatArrowShot: Equatable, Sendable {
    public let shooter: CombatActorObservation
    public let target: MeleeTarget
    /// How fast the target moves, in units a second, for the lead.
    public let targetVelocity: SIMD3<Float>
    public let bow: MeleeWeaponProfile

    public init(
        shooter: CombatActorObservation, target: MeleeTarget,
        targetVelocity: SIMD3<Float>, bow: MeleeWeaponProfile
    ) {
        self.shooter = shooter
        self.target = target
        self.targetVelocity = targetVelocity
        self.bow = bow
    }
}

extension CombatLoopWorldPart {
    /// False when the shooter carries no arrow or the session has no archery.
    func fireCombatArrow(_ shot: CombatArrowShot) -> Bool {
        let key = shot.shooter.key
        let gear = shared.world.gearReads
        guard
            let archery = shared.archery, let items = shared.items,
            let arrow = CombatCore.arrow(
                equipped: gear.equippedItems(of: key).map(\.item),
                carried: gear.carriedItems(of: key),
                bolts: shot.bow.handType == .crossbow,
                resolve: items.archeryAmmunition
            )
        else { return false }
        let origin = shot.shooter.feet
            + SIMD3(0, 0, shot.shooter.capsule.eyeHeight * shot.shooter.scale)
        let centre = shot.target.feet + SIMD3(0, 0, shot.target.capsule.height / 2)
        var random = shared.archeryRandom
        let aimed = NPCArcheryAim.noisy(
            NPCArcheryAim.lead(
                from: origin, to: centre, velocity: shot.targetVelocity,
                speed: arrow.profile.speed
            ),
            random: &random
        )
        let gravity = ProjectileFlight.worldGravity * arrow.profile.gravityFactor
        let maximum = NPCArcheryAim.maximumSpread(
            skill: archerySkill(of: key), coneDegrees: archery.settings.npcSpreadDegrees
        )
        let direction = NPCArcheryAim.spread(
            NPCArcheryAim.ballistic(
                from: origin, to: aimed, speed: arrow.profile.speed, gravity: gravity
            ),
            maximum: maximum, random: &random
        )
        shared.archeryRandom = random
        var payload = ArrowPayload(
            damage: ArcheryDamage.resolve(
                bowDamage: shot.bow.damage, arrowDamage: arrow.damage, skill: 0
            ),
            weapon: shot.bow.weapon,
            ammunition: arrow.item
        )
        payload.spendsAmmunition = false
        var fired = ProjectileShot(profile: arrow.profile, payload: .arrow(payload))
        fired.tiltsUp = false
        let shooter = ProjectileShooter(
            key: key, origin: origin, aim: direction, isFirstPerson: false,
            location: shared.world.cellLocation(of: key)
        )
        return archery.projectiles.fire(fired, from: shooter) != nil
    }

    /// The shooter's Archery skill, or the starting value without actor values.
    private func archerySkill(of key: ReferenceKey) -> Float {
        guard
            let index = ActorValueIdentity.index(named: "Archery"),
            let skill = shared.world.actorValues(of: key)?(index)
        else { return ArcheryDamage.defaultArcherySkill }
        return skill
    }
}
