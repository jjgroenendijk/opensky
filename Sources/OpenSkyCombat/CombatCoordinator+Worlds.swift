// `CombatCoordinator` as the world of its three runtimes. Each answer reads
// another runtime it owns, a `CombatCore` rule, or one `CombatWorld` member.

import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import OpenSkyWorldState
import simd

extension CombatCoordinator: ScriptHitReporting, SkillUseReporting, SpellHitApplying,
    WeaponEnchantmentApplying
{
    @discardableResult
    public func reportScriptHit(_ hit: ScriptHitEvent) -> Int {
        world?.reportScriptHit(hit) ?? 0
    }

    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        world?.reportSkillUse(use) ?? 0
    }

    @discardableResult
    public func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        world?.applySpellHit(hit) ?? .none
    }

    @discardableResult
    public func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        world?.applyWeaponEnchantment(hit)
    }

    /// Only the player carries a behavior graph, so an event on an NPC
    /// answers false.
    @discardableResult
    public func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        guard target == nil || target == .player else { return false }
        return world?.raisePlayerGraphEvent(name) ?? false
    }

    public func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        world?.writePlayerGraphVariable(value, named: name)
    }
}

extension CombatCoordinator: MeleeCombatWorld {
    public var meleeAttacker: MeleeAttacker {
        world?.playerAttacker ?? MeleeAttacker(key: .player, feet: SIMD3<Float>(), facing: 0)
    }

    public func meleeAttackMultiplier(handType: CombatHandType) -> Float {
        guard let world, let values = world.actorValues(of: .player) else { return 1 }
        return CombatFortifyBonus.melee(handType: handType, reading: values)
            * world.perkMultiplier(at: CombatCore.attackDamageEntryPoint, on: .player)
    }

    public func meleeTargets() -> [MeleeTarget] {
        (world?.residentActors() ?? []).map { MeleeTarget(key: $0.key, feet: $0.feet) }
    }

    public func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind? {
        CombatCore.block(
            of: target,
            playerIsBlocking: melee?.state.isBlocking == true,
            machineBlock: target == .player ? nil : loop?.blockKind(of: target)
        )
    }

    /// The blocker's fortify term times `Mod Percent Blocked`.
    public func meleeBlockMultiplier(of target: ReferenceKey) -> Float {
        guard let world, let values = world.actorValues(of: target) else { return 1 }
        return CombatFortifyBonus.block(reading: values)
            * world.perkMultiplier(at: CombatCore.percentBlockedEntryPoint, on: target)
    }

    /// The player's own swing: the melee runtime only ever swings for the player.
    @discardableResult
    public func applyMeleeDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        applyHealthDamage(amount, to: target, attacker: meleeAttacker.key)
    }

    /// Every weapon, arrow, and explosion hit passes here, so difficulty scales
    /// health damage at one point. A nil attacker is never the player.
    @discardableResult
    public func applyHealthDamage(
        _ amount: Float, to target: ReferenceKey, attacker: ReferenceKey?
    ) -> Bool {
        guard amount > 0 else { return false }
        let scaled = DifficultyDamage.scaled(
            amount, attackerIsPlayer: attacker == .player, targetIsPlayer: target == .player,
            multipliers: difficultyMultipliers
        )
        let landed = world?.damageHealth(by: scaled, of: target) ?? false
        if landed, attacker == .player, target != .player {
            playerStruckTarget = target
        }
        return landed
    }

    public func playMeleeImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        world?.playImpact(impact, at: position)
    }
}

extension CombatCoordinator: ProjectileWorld {
    public var projectileShooter: ProjectileShooter {
        world?.playerShooter ?? ProjectileShooter(
            key: .player, origin: SIMD3(), aim: SIMD3(1, 0, 0),
            isFirstPerson: true, location: nil
        )
    }

    public func projectileTargets() -> [MeleeTarget] {
        meleeTargets()
    }

    public func sweepProjectile(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
        world?.sweep(query)
    }

    @discardableResult
    public func applyProjectileDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        applyHealthDamage(amount, to: target, attacker: projectileShooter.key)
    }

    public func playProjectileImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        world?.playImpact(impact, at: position)
    }

    /// False on an empty quiver, which is ordinary play: the shot does not happen.
    @discardableResult
    public func consumeArrow(_ ammunition: FormID) -> Bool {
        world?.removeOneFromPlayer(ammunition) ?? false
    }

    /// A stuck arrow is a spawned AMMO model at the impact point. It does not
    /// follow the bone of the actor it hit.
    @discardableResult
    public func spawnStuckProjectile(_ arrow: StuckProjectile) -> ReferenceKey? {
        let spawn = ReferenceSpawnState(
            base: arrow.base,
            location: arrow.location,
            placement: PlacedReference.Placement(
                position: arrow.position,
                rotation: arrow.rotation
            ),
            count: 1
        )
        guard let key = world?.spawn(spawn, in: arrow.location) else { return nil }
        stuckKeys.insert(key)
        return key
    }

    public func removeStuckProjectile(_ key: ReferenceKey) {
        guard stuckKeys.remove(key) != nil else { return }
        world?.resetReference(key)
    }

    public func residentProjectileCells() -> Set<CellSceneLocation> {
        world?.residentCells() ?? []
    }

    @discardableResult
    public func raiseArcheryEvent(_ name: String) -> Bool {
        raiseCombatEvent(name, on: nil)
    }

    public func writeArcheryVariable(_ value: BehaviorVariableValue, named name: String) {
        writeCombatVariable(value, named: name)
    }
}
