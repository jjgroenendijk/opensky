import Foundation
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface

nonisolated extension ProjectileShot {
    /// A bow's shot: the launch speed scales with the draw and the archery
    /// tilt-up angle applies.
    public static func arrow(
        profile: ProjectileProfile,
        damage: ArcheryDamageResult,
        weapon: FormID? = nil,
        ammunition: FormID? = nil,
        enchantment: ItemEnchantmentProfile? = nil
    ) -> ProjectileShot {
        ProjectileShot(
            profile: profile,
            payload: .arrow(ArrowPayload(
                damage: damage,
                weapon: weapon,
                ammunition: ammunition,
                enchantment: enchantment
            ))
        )
    }
}
