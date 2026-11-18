import Foundation
public import OpenSkyFormatsESM

/// The selected arrow, reduced to what a shot needs from it.
nonisolated public struct ArcheryAmmunition: Equatable, Sendable {
    /// The AMMO itself, which is what the inventory consumes.
    public let item: FormID
    /// AMMO DATA base damage.
    public let damage: Float
    /// The PROJ it launches, already decoded into a flight profile.
    public let profile: ProjectileProfile
    /// A crossbow bolt: AMMO without the Non-Bolt flag. A bow fires only arrows, and a
    /// crossbow only bolts.
    public let isBolt: Bool

    public init(item: FormID, damage: Float, profile: ProjectileProfile, isBolt: Bool = false) {
        self.item = item
        self.damage = damage.isFinite ? max(0, damage) : 0
        self.profile = profile
        self.isBolt = isBolt
    }

    /// One decoded AMMO plus the PROJ it names.
    public init(ammunition: Ammunition, projectile: Projectile) {
        self.init(
            item: ammunition.formID,
            damage: ammunition.damage,
            profile: ProjectileProfile(record: projectile),
            isBolt: !ammunition.flags.contains(.nonBolt)
        )
    }
}
