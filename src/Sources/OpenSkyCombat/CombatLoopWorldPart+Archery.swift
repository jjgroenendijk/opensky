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
        ArcheryShots(owner: self).fireCombatArrow(shot)
    }

    func combatAimPoint(
        of shooter: CombatActorObservation, at point: SIMD3<Float>, velocity: SIMD3<Float>
    ) -> SIMD3<Float>? {
        ArcheryShots(owner: self).aimPoint(of: shooter, at: point, velocity: velocity)
    }

    /// The shooter's Archery skill, or the starting value without actor values.
    private func archerySkill(of key: ReferenceKey) -> Float {
        ArcheryShots(owner: self).archerySkill(of: key)
    }
}

extension CombatLoopWorldPart {
    /// Fires the arrows of NPC archers and reads their archery skill.
    struct ArcheryShots {
        unowned let owner: CombatLoopWorldPart

        func aimPoint(
            of shooter: CombatActorObservation, at point: SIMD3<Float>, velocity: SIMD3<Float>
        ) -> SIMD3<Float>? {
            let gear = owner.shared.world.gearReads
            let bow = owner.combatWeapon(of: shooter.key)
            guard
                let items = owner.shared.items,
                let arrow = CombatCore.arrow(
                    equipped: gear.equippedItems(of: shooter.key).map(\.item),
                    carried: gear.carriedItems(of: shooter.key),
                    bolts: bow.handType == .crossbow,
                    resolve: items.archeryAmmunition
                )
            else { return nil }
            let origin = shooter.feet + SIMD3(0, 0, shooter.capsule.eyeHeight * shooter.scale)
            return NPCArcheryAim.lead(
                from: origin, to: point, velocity: velocity, speed: arrow.profile.speed
            )
        }

        /// The aim line before the spread: toward the noisy, led aim point along its arc,
        /// or straight at the target when the `PROJ` turns combat aim correction off.
        static func launch(
            _ line: (from: SIMD3<Float>, to: SIMD3<Float>), velocity: SIMD3<Float>,
            profile: ProjectileProfile, random: inout ConditionRandom
        ) -> SIMD3<Float> {
            let (origin, centre) = line
            guard profile.correctsCombatAim else {
                return NPCArcheryAim.ballistic(from: origin, to: centre, speed: 0, gravity: 0)
            }
            let aimed = NPCArcheryAim.noisy(
                NPCArcheryAim.lead(
                    from: origin,
                    to: centre,
                    velocity: velocity,
                    speed: profile.speed
                ),
                random: &random
            )
            return NPCArcheryAim.ballistic(
                from: origin, to: aimed, speed: profile.speed,
                gravity: ProjectileFlight.worldGravity * profile.aimGravityFactor
            )
        }

        func fireCombatArrow(_ shot: CombatArrowShot) -> Bool {
            let key = shot.shooter.key
            let gear = owner.shared.world.gearReads
            guard
                let archery = owner.shared.archery, let items = owner.shared.items,
                let arrow = CombatCore.arrow(
                    equipped: gear.equippedItems(of: key).map(\.item),
                    carried: gear.carriedItems(of: key),
                    bolts: shot.bow.handType == .crossbow,
                    resolve: items.archeryAmmunition
                )
            else { return false }
            let origin = shot.shooter.feet
                + SIMD3(0, 0, shot.shooter.capsule.eyeHeight * shot.shooter.scale)
            let atFeet = archery.settings.aimsAtFeet(
                explosionRadius: owner.shared.explosions.spec(itemLink: arrow.profile.explosion)?
                    .radius ?? 0,
                spellArea: 0
            )
            let centre = shot.target.feet
                + SIMD3(0, 0, atFeet ? 0 : shot.target.capsule.height / 2)
            var random = owner.shared.archeryRandom
            let launch = Self.launch(
                (origin, centre), velocity: shot.targetVelocity,
                profile: arrow.profile, random: &random
            )
            let maximum = NPCArcheryAim.maximumSpread(
                skill: owner.archerySkill(of: key), coneDegrees: archery.settings.npcSpreadDegrees
            )
            let direction = NPCArcheryAim.spread(launch, maximum: maximum, random: &random)
            owner.shared.archeryRandom = random
            var payload = ArrowPayload(
                damage: ArcheryDamage.resolve(
                    bowDamage: shot.bow.damage, arrowDamage: arrow.damage, skill: 0
                ),
                weapon: shot.bow.weapon,
                ammunition: arrow.item
            )
            payload.spendsAmmunition = false
            payload.stagger = shot.bow.stagger
            payload.handType = shot.bow.handType
            var fired = ProjectileShot(profile: arrow.profile, payload: .arrow(payload))
            fired.tiltsUp = false
            let shooter = ProjectileShooter(
                key: key, origin: origin, aim: direction, isFirstPerson: false,
                location: owner.shared.world.cellLocation(of: key)
            )
            return archery.projectiles.fire(fired, from: shooter) != nil
        }

        func archerySkill(of key: ReferenceKey) -> Float {
            guard
                let index = ActorValueIdentity.index(named: "Archery"),
                let skill = owner.shared.world.actorValues(of: key)?(index)
            else { return ArcheryDamage.defaultArcherySkill }
            return skill
        }
    }
}
