import Foundation
import OpenSkyFormatsESM
public import OpenSkyGameData

/// A held staff: the item's enchantment and the spell it casts.
public struct HeldStaff {
    public let profile: ItemEnchantmentProfile
    public let spell: ResolvedSpell

    public init(
        profile: ItemEnchantmentProfile,
        spell: ResolvedSpell
    ) {
        self.profile = profile
        self.spell = spell
    }
}
