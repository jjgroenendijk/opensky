// The world of the archery runtime and its projectiles. Each answer reads a combat
// part or one `CombatWorld` member.

import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import OpenSkyWorldState
import simd

/// What the archery and projectile runtimes read and change, over the shared state.
final class CombatProjectileWorldPart: CombatSharedPart, ProjectileWorld {
    var projectileShooter: ProjectileShooter {
        shared.world.playerShooter ?? ProjectileShooter(
            key: .player, origin: SIMD3(), aim: SIMD3(1, 0, 0),
            isFirstPerson: true, location: nil
        )
    }

    /// The candidates are the living hostile actors in combat, without the mount the
    /// player rides.
    func projectileAutoAim(from shooter: ProjectileShooter) -> ProjectileAimPick? {
        AimAndDamage(owner: self).projectileAutoAim(from: shooter)
    }

    func projectileTargets() -> [MeleeTarget] {
        shared.world.residentActors().map { MeleeTarget(key: $0.key, feet: $0.feet) }
    }

    func sweepProjectile(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
        shared.world.sweep(query)
    }

    /// A shot no wielder fired, such as a dart trap's, takes no perks or sneak bonus.
    @discardableResult
    func applyProjectileDamage(
        _ amount: Float, to target: ReferenceKey, from shooter: ReferenceKey
    ) -> Bool {
        AimAndDamage(owner: self).applyProjectileDamage(amount, to: target, from: shooter)
    }

    func projectileIsSneakAttack(by shooter: ReferenceKey, on target: ReferenceKey) -> Bool {
        shared.strikes.isSneakAttack(by: shooter, on: target)
    }

    func projectileLaunched(_ projectile: LiveProjectile) {
        let visuals = projectile.profile.visuals
        guard visuals.hasMuzzleFlash else { return }
        shared.pendingCommands.append(.muzzleFlash(
            visuals, at: projectile.launchPosition, along: projectile.launchDirection
        ))
    }

    func playProjectileImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        shared.pendingCommands.append(.playImpact(impact, at: position))
    }

    func noteProjectileSound(level: UInt32?, at position: SIMD3<Float>, by shooter: ReferenceKey) {
        shared.pendingCommands.append(.detectionEvent(owner: shooter, level: level, at: position))
    }

    /// False on an empty quiver, which is ordinary play: the shot does not happen.
    @discardableResult
    func consumeArrow(_ ammunition: FormID) -> Bool {
        shared.world.gearReads.removeOneFromPlayer(ammunition)
    }

    /// A stuck arrow is a spawned AMMO model at the impact point. It does not
    /// follow the bone of the actor it hit.
    @discardableResult
    func spawnStuckProjectile(_ arrow: StuckProjectile) -> ReferenceKey? {
        let spawn = ReferenceSpawnState(
            base: arrow.base,
            location: arrow.location,
            placement: PlacedReference.Placement(
                position: arrow.position,
                rotation: arrow.rotation
            ),
            count: 1
        )
        guard let key = shared.world.spawn(spawn, in: arrow.location) else { return nil }
        shared.stuckKeys.insert(key)
        return key
    }

    func removeStuckProjectile(_ key: ReferenceKey) {
        guard shared.stuckKeys.remove(key) != nil else { return }
        shared.pendingCommands.append(.removeReference(key))
    }

    func residentProjectileCells() -> Set<CellSceneLocation> {
        shared.world.residentCells()
    }

    @discardableResult
    func raiseArcheryEvent(_ name: String) -> Bool {
        raiseCombatEvent(name, on: nil)
    }

    func writeArcheryVariable(_ value: BehaviorVariableValue, named name: String) {
        writeCombatVariable(value, named: name)
    }

    @discardableResult
    func giveRecoveredArrow(_ ammunition: FormID, to target: ReferenceKey) -> Bool {
        shared.world.gearReads.addItem(ammunition, count: 1, to: target)
    }

    func showArcheryNotice(_ text: String) {
        shared.pendingCommands.append(.showNotification(text))
    }

    /// Hunter's Discipline doubles the chance through this entry point.
    func arrowRecoveryMultiplier(of shooter: ReferenceKey) -> Float {
        shared.perks.arrowRecoveryMultiplier(of: shooter)
    }
}

extension CombatProjectileWorldPart {
    func makeRuntime(_ data: CombatSessionData) -> ArcheryRuntime {
        let projectiles = ProjectileRuntime(settings: data.archery, world: self)
        projectiles.impacts = data.impacts
        projectiles.explosions = shared.explosions
        projectiles.arrows = data.arrows
        projectiles.magicWorld = data.magicWorld
        return ArcheryRuntime(settings: data.archery, projectiles: projectiles, world: self)
    }
}

extension CombatProjectileWorldPart {
    /// Picks the auto-aim target of a shot and applies the damage of a hit.
    struct AimAndDamage {
        let owner: CombatProjectileWorldPart

        func projectileAutoAim(from shooter: ProjectileShooter) -> ProjectileAimPick? {
            let world = owner.shared.world
            guard
                let loop = owner.shared.loop,
                let fovY = world.playerViewFOVYRadians else { return nil }
            let mount = world.playerMount
            let view = ProjectileAimView(fovYRadians: fovY, aspect: world.playerViewAspect ?? 1)
            let candidates = world.residentActors().compactMap { actor -> ProjectileAimCandidate? in
                guard
                    !actor.isDead, actor.key != mount, world.hostility(of: actor.key) == .hostile,
                    loop.activity(of: actor.key) != .notFighting
                else { return nil }
                let height = actor.capsule.height * actor.scale
                return ProjectileAimCandidate(
                    key: actor.key, centre: actor.feet + SIMD3(0, 0, height / 2),
                    top: actor.feet + SIMD3(0, 0, height)
                )
            }
            guard
                let target = ProjectileAutoAim.pick(
                    candidates, from: shooter.origin, forward: shooter.aim, view: view
                )
            else { return nil }
            let hand = owner.shared.melee?.weapon.handType ?? .handToHand
            return ProjectileAimPick(
                target: target,
                rightHandIsFree: !(hand.isRanged || hand == .staff || hand == .spell)
            )
        }

        @discardableResult
        func applyProjectileDamage(
            _ amount: Float, to target: ReferenceKey, from shooter: ReferenceKey
        ) -> Bool {
            guard !owner.shared.perks.deflectsArrow(target) else { return false }
            let damage = owner.shared.damage
            guard shooter == owner.projectileShooter.key else {
                return damage.applyHealthDamage(
                    amount,
                    to: target,
                    attacker: shooter,
                    kind: .ranged
                )
            }
            let weapon = owner.shared.gear.playerWeapon()
            let blow = CombatBlow(
                attacker: shooter, weapon: weapon?.formID,
                handType: CombatHandType(weapon: weapon?.animationType) == .crossbow
                    ? .crossbow : .bow,
                baseDamage: amount
            )
            let strikes = owner.shared.strikes
            let strike = strikes.strike(blow, on: target)
            strikes.reportSneakAttack(strike, ranged: true)
            strikes.countCriticalStats(strike, blow: blow, on: target)
            strikes.reportCriticalStrike(strike, blow: blow, on: target)
            let landed = damage.applyHealthDamage(
                strike.damage(base: amount), to: target, attacker: shooter, kind: .ranged
            )
            if landed {
                owner.shared.perks.applyPerkHitSpell(blow, on: target)
            }
            return landed
        }
    }
}
