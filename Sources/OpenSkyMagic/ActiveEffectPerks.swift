// The perks active magic effects apply. An MGEF's "Perk to Apply" is owned while the
// effect lasts: the Rested spells and the Guardian Stones change skill experience this
// way (docs/engine/skill-advancement.md).

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

nonisolated public enum ActiveEffectPerks: Sendable {
    /// A link no loaded plugin resolves applies nothing.
    public static func perks(
        of active: [ActiveEffect],
        effects: MagicEffectStore,
        perks: PerkStore
    ) -> Set<ReferenceKey> {
        var granted: Set<ReferenceKey> = []
        for effect in active {
            guard
                let record = effects.effect(key: effect.effect),
                let link = record.effect.data?.perkToApply,
                let perk = perks.resolvedID(link, fromPlugin: record.sourcePlugin)
            else { continue }
            granted.insert(ReferenceKey(resolved: perk))
        }
        return granted
    }
}
