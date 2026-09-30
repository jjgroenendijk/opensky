// Abilities: the part of the caster runtime that applies what an actor carries
// rather than casts. A satellite of `CasterRuntime`, which is at its body cap.
// See docs/engine/spellcasting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

extension CasterRuntime {
    /// Applies every ability `holder` knows as an effect on `holder`. A
    /// zero-duration entry means "while carried", which the active-effect runtime
    /// cannot hold, so it is counted (`CastingTally.unheldAbilityEntries`), not
    /// applied wrongly.
    /// - Returns: how many timed effects were stored.
    @discardableResult
    public func applyAbilities(on holder: ActorValueHolder) -> Int {
        guard let world else { return 0 }
        var stored = 0
        for spell in spellbook.knownSpells(of: holder) where spell.spellType == .ability {
            let entries = spell.record.effects
            let timed = entries.filter { $0.duration > 0 }
            tally.noteUnheldAbilityEntries(entries.count - timed.count)
            guard !timed.isEmpty else { continue }
            stored += world.applyCastEffects(
                timed,
                fromPlugin: spell.sourcePlugin,
                source: ActiveEffectSource(kind: .spell, record: spell.key),
                caster: holder.key,
                on: holder
            )
        }
        return stored
    }
}
