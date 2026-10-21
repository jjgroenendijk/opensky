// A made enchantment as the runtime reads it: the profile of the item copy that carries
// it, built from its base records. See docs/engine/enchanting.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension ItemEnchantmentProfile {
    /// `made` on `item`, or nil when a base left the load order. A base's magnitude
    /// grows with its power where its MGEF lets power change magnitude, and its
    /// duration where it lets power change duration; both round down (UESP
    /// "Skyrim:Enchanting_Effects").
    public static func made(
        _ made: MadeEnchantment, item: FormID, using store: EnchantmentStore
    ) -> ItemEnchantmentProfile? {
        let bases = made.bases.compactMap { store.enchantment(key: $0) }
        guard let first = bases.first, bases.count == made.bases.count else { return nil }
        let entries = zip(bases, made.powers).flatMap { base, power in
            base.effects.map { resolved in
                let flags = resolved.effect?.effect.data?.flags ?? []
                let entry = resolved.item
                return entry.with(
                    magnitude: flags.contains(.powerAffectsMagnitude)
                        ? (entry.magnitude * power).rounded(.down) : entry.magnitude,
                    duration: flags.contains(.powerAffectsDuration)
                        ? (Float(entry.duration) * power).rounded(.down) : Float(entry.duration)
                )
            }
        }
        return ItemEnchantmentProfile(
            item: item,
            enchantment: ReferenceKey(resolved: first.id),
            sourcePlugin: first.sourcePlugin,
            entries: entries,
            name: made.name,
            castingType: first.data?.castingType ?? .constantEffect,
            delivery: first.data?.delivery ?? .selfTarget,
            type: first.data?.type ?? .enchantment,
            capacity: made.capacity,
            costPerUse: made.costPerUse,
            wornRestriction: nil
        )
    }
}

nonisolated extension EnchantmentStore {
    public func enchantment(key: ReferenceKey) -> ResolvedEnchantment? {
        guard case let .plugin(name, objectID) = key else { return nil }
        return enchantment(ResolvedFormID(plugin: name, objectID: objectID))
    }

    /// An ENCH as the subject of a perk's enchantment tab. `HasKeyword` reads the
    /// keywords of its effects, as Fire Enchanter's `MagicDamageFire` test does.
    public func conditionSubject(of enchantment: ResolvedEnchantment) -> ConditionFormSubject {
        let keywords = enchantment.effects.compactMap(\.effect).flatMap { effect in
            effect.effect.keywords.keywords.compactMap { keyword in
                resolvedID(keyword, fromPlugin: effect.sourcePlugin)
                    .map(ReferenceKey.init(resolved:))
            }
        }
        return ConditionFormSubject(id: enchantment.id, effectKeywords: Set(keywords))
    }
}
