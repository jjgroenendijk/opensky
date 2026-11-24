public import OpenSkyFormatsESM
public import OpenSkyGameData
import simd

/// One change to the world outside the combat domain.
nonisolated public enum CombatCommand: Equatable, Sendable {
    case showNotification(String)
    /// The impact sound and visual effect of a melee or projectile hit.
    case playImpact(ResolvedMeleeImpact, at: SIMD3<Float>)
    /// A projectile of `owner` landed or exploded: observers near it may hear it.
    /// `level` is the record's sound level: 0 loud, 1 normal, 2 silent, 3 very loud.
    case detectionEvent(owner: ReferenceKey, level: UInt32?, at: SIMD3<Float>)
    /// Drops every stored change for the reference, which removes a spawned one.
    case removeReference(ReferenceKey)
    case resetRagdolls
    case setCombatMusic(active: Bool)
    /// The player began a swing or loosed an arrow while no one fights it, which a
    /// witness may comment on.
    case playerAttackedOutsideCombat(CombatWeaponUse)
    /// An attack drew blood: screen blood on a struck player, blood on a melee weapon.
    case drewBlood(CombatHitRecord, target: ReferenceKey)
    /// A hit on an actor with no impact data of its own: the default blood effects.
    case showDefaultBlood(on: ReferenceKey, at: SIMD3<Float>, melee: Bool)
    /// A projectile left with a muzzle flash: its `NAM1` model and light at the launch.
    case muzzleFlash(ProjectileVisuals, at: SIMD3<Float>, along: SIMD3<Float>)
    /// The player's shot `projectile` will kill `target`, and a kill cam follows it.
    case rangedKillCam(projectile: Int, target: ReferenceKey)
    /// The player loosed an arrow; `power` below 1 is a dud.
    case playerBowShot(weapon: FormID?, ammunition: FormID?, power: Float)
    /// Raises the misc stat with this name by one.
    case incrementStat(String)
    /// The player swung or fired this `WEAP`: one use for Favorite Weapon.
    case playerUsedWeapon(FormID)
}

/// What the player did with a weapon outside a fight.
nonisolated public enum CombatWeaponUse: Equatable, Sendable {
    case swing
    case shot
}
