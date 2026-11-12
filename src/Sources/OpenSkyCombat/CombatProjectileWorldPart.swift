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
        guard !shared.perks.deflectsArrow(target) else { return false }
        let damage = shared.damage
        guard shooter == projectileShooter.key else {
            return damage.applyHealthDamage(amount, to: target, attacker: shooter, kind: .ranged)
        }
        let blow = CombatBlow(
            attacker: shooter, weapon: shared.gear.playerWeapon()?.formID, handType: .bow,
            baseDamage: amount
        )
        let strikes = shared.strikes
        let strike = strikes.strike(blow, on: target)
        strikes.reportSneakAttack(strike, ranged: true)
        let landed = damage.applyHealthDamage(
            strike.damage(base: amount), to: target, attacker: shooter, kind: .ranged
        )
        if landed {
            shared.perks.applyPerkHitSpell(blow, on: target)
        }
        return landed
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
        shared.pendingCommands.append(.detectionEvent(owner: .player, at: position))
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
