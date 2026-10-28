// Which spells a dragon rider casts. No record lists them, so this is OpenSky's rule: it
// lets through every spell UESP "Skyrim:Dragon Riding" lists and refuses summons,
// placed and self-centred area spells, as that page says (docs/engine/dragon-flight.md#riding).

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public enum FlyingMountSpellRules {
    /// Effects that need the ground, a body nearby, or the caster's hands free.
    static let refusedArchetypes: [MagicEffectArchetype] = [
        .summonCreature, .reanimate, .boundWeapon, .spawnHazard, .cloak, .telekinesis,
        .detectLife, .guide, .invisibility
    ]

    public static func allows(_ spell: ResolvedSpell) -> Bool {
        let delivery = spell.data?.delivery ?? .selfTarget
        if delivery == .targetLocation {
            return false
        }
        return !spell.effects.contains { entry in
            guard let data = entry.effect?.effect.data else { return false }
            if refusedArchetypes.contains(data.archetype) {
                return true
            }
            return delivery == .selfTarget && entry.item.area > 0
                && data.flags.contains(.hostile)
        }
    }
}
