// The abilities an item in a casting slot grants through its effects' `MGEF` equip
// ability. Written as a reconcile, like `PerkAbilityApplication`: the effects carry
// `ActiveEffectSourceKind.equipAbility`, so a save keeps them and a second call changes
// nothing. See docs/formats/magic-records.md#mgef-data.

import Foundation
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyMagicInterface

@MainActor
public enum EquipAbilityApplication {
    /// Casts the equip ability of each of `slotted` on `holder`, and dispels the equip
    /// abilities no slotted effect names. Returns how many abilities changed.
    @discardableResult
    public static func reconcile(
        slotted: [ResolvedMagicEffect],
        on holder: ActorValueHolder,
        spells: SpellStore,
        using runtime: inout ActiveEffectRuntime
    ) -> Int {
        var wanted: [ReferenceKey: ResolvedSpell] = [:]
        for effect in slotted {
            guard
                let link = effect.effect.data?.equipAbility,
                let spell = spells.resolve(link, fromPlugin: effect.sourcePlugin)
            else { continue }
            wanted[spell.key] = spell
        }
        let held = Set(
            runtime.state(of: holder).effects
                .filter { $0.source.kind == .equipAbility }
                .map(\.source.record)
        )
        var changed = 0
        for spell in held.subtracting(wanted.keys).sorted() {
            runtime.dispel(on: holder) {
                $0.source.kind == .equipAbility && $0.source.record == spell
            }
            changed += 1
        }
        for key in wanted.keys.sorted() where !held.contains(key) {
            guard let spell = wanted[key] else { continue }
            let stored = runtime.apply(
                spell.record.effects,
                fromPlugin: spell.sourcePlugin,
                source: ActiveEffectSource(kind: .equipAbility, record: key),
                caster: holder.key,
                isConstant: true,
                on: holder
            )
            changed += stored.isEmpty ? 0 : 1
        }
        return changed
    }
}
