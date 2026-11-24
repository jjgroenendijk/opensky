import OpenSkyMenus
import OpenSkySessionInterface

extension CombatPort {
    /// The reads the item card and the barter bar use for the player's own values.
    var shownGearStats: ShownGearStats {
        ShownGearStats(
            damage: { [self] in shownDamage(of: $0, temperLevel: $1) },
            armour: { [self] in shownArmourRating(of: $0, temperLevel: $1) },
            armourBonus: shownArmourBonus
        )
    }
}
