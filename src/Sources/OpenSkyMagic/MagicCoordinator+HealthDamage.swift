// The health a spell takes from the actor it lands on, read before it lands, for the
// kill cam's release check (docs/engine/kill-cam.md#bow-and-spell-kill-cams-in-the-game).

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMagicInterface

extension MagicCoordinator {
    /// The sum of `spell`'s detrimental value modifiers on Health, before resistance.
    public func healthDamage(of spell: SpellPayload) -> Float {
        guard let store = effects?.effects else { return 0 }
        let health = ActorValueIdentity.index(named: "Health")
        return spell.entries.reduce(0) { total, entry in
            guard
                let data = store.resolve(entry.effect, fromPlugin: spell.sourcePlugin)?.effect.data,
                data.archetype == .valueModifier, data.relatedActorValue == health,
                data.flags.contains(.detrimental), entry.magnitude.isFinite
            else { return total }
            return total + max(0, entry.magnitude)
        }
    }
}
