// An enchantment's effect landing again on the target that still has it.
// Rule: docs/formats/enchantments.md.

import OpenSkyGameData
import OpenSkyMagicInterface

extension ActiveEffectRuntime {
    /// An enchantment's effect landing again on its target: with Extend Duration on
    /// Recast the running effect starts over and is returned; without, it is dispelled.
    mutating func recastEnchantment(
        _ application: MagicEffectApplication, source: ActiveEffectSource,
        on target: ActorValueHolder
    ) -> ActiveEffect? {
        guard let extends = self.application.enchantmentRecast else { return nil }
        let earlier = state(of: target).effects
            .filter { $0.source == source && $0.effect == application.effect }
        guard let first = earlier.first else { return nil }
        guard extends else {
            let sequences = Set(earlier.map(\.sequence))
            dispel(on: target) { sequences.contains($0.sequence) }
            return nil
        }
        let restarted = first.restarted()
        write(state(of: target).replacing([restarted]), for: target)
        tally.noteApplied()
        return restarted
    }
}
