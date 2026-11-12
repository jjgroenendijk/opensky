// A poison dose landing on its target: its effects apply as an ingestible's, after the
// target's resistance.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyWorldState

extension MagicCoordinator.PoisonDoses {
    /// A poison's effects on `target`, scaled by its resistances like a hostile spell.
    static func land(
        _ dose: PoisonDose, caster: ReferenceKey,
        on target: ActorValueHolder, using runtime: inout ActiveEffectRuntime
    ) -> Int {
        let (potion, id, plugin) = (dose.potion, dose.id, dose.plugin)
        let scaled = SpellHitApplication.scale(
            potion.effects, source: (plugin, false),
            on: target, using: runtime, resistances: .documentedDefaults
        )
        return runtime.apply(
            scaled.entries,
            fromPlugin: plugin,
            source: ActiveEffectSource(
                kind: .potion, record: runtime.effects.sourceKey(of: id, fallbackPlugin: plugin)
            ),
            caster: caster,
            on: target
        ).count
    }
}
