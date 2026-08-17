// One enchanted item, resolved once into everything the runtime needs from it
// (issue #472, roadmap item 19.9).
//
// The counterpart of `SpellPayload` for an item rather than a cast: resolved when
// equipment resolves and never re-derived, so a weapon already swinging applies
// the enchantment it was carrying when the swing started.
//
// ## What the record shapes are, measured
//
// The Creation Kit wiki states the authoring rules
// (<https://ck.uesp.net/wiki/Enchantment>): "Armor Enchantments must use the
// 'Constant Effect' casting type" and "can only have 'Self' as their delivery
// type"; weapons "can only have 'Contact'"; staves "can only use 'Aimed' or
// 'Target Location'". Every one of those holds in this machine's install, counted
// on 2026-08-17 across the whole active load order:
//
//   ARMO EITM -> 2,885 enchantments, all `enchantment / constant effect / self`
//   WEAP EITM -> 2,939 `enchantment / fire and forget / touch`, plus 86 staff
//                enchantments spread over aimed, target-actor and target-location
//
// So the *casting type* is what selects the runtime behaviour here, not the record
// family: a constant effect is worn, a contact enchantment fires on a hit, and a
// staff enchantment is neither (see `EnchantmentRuntime` for the staff tally).
//
// ## The worn restriction is not a runtime gate
//
// `ENIT`'s worn-restriction link is a form list of keywords, and the same wiki
// page describes it as an *authoring* restriction: "When the player tries to
// enchant a Weapon or piece of Armor with this Enchantment, only items that have
// one of the keywords in this list may be enchanted with it."
//
// It is exposed here as a question a caller can ask, and deliberately not
// consulted when a worn item's effects are applied, because enforcing it would
// break vanilla items. Of the 2,727 enchanted ARMO records whose enchantment
// chain names a restriction list, 70 do not carry any keyword their own list
// names — among them the Gauldur Amulet and its three fragments, a Dragon Priest
// mask, and Cicero's hat (measured 2026-08-17; the counterexamples are pinned in
// `EnchantmentRuntimeRealDataTests` so nothing can quietly start enforcing it).
//
// Documented in docs/engine/magic.md.

import Foundation

/// One enchanted item's enchantment, resolved.
nonisolated struct ItemEnchantmentProfile: Equatable, Sendable {
    /// The WEAP or ARMO base record. What the charge and the worn effects are
    /// keyed by, and what a readout names.
    let item: FormID
    /// The winning ENCH identity, which every applied effect is sourced to.
    let enchantment: ReferenceKey
    /// The plugin every `EFID` in `entries` is relative to.
    let sourcePlugin: String
    /// The effect list as authored. Magnitudes are pre-resistance.
    let entries: [MagicItemEffect]
    /// FULL name or editor ID of the enchantment, for the readout. Never empty.
    let name: String
    let castingType: MagicEffectCastingType
    let delivery: MagicEffectDelivery
    let type: EnchantmentType
    /// The item's `EAMT`: the fully charged value. Zero on ARMO, which has no
    /// charge field at all.
    let capacity: Float
    /// The enchantment's cost — what one use spends.
    let costPerUse: Float
    /// The `FLST` of keywords the enchantment may be applied to, from the
    /// nearest link in the base chain. Carried for inspection only; see the file
    /// header for why it gates nothing here.
    let wornRestriction: FormID?

    /// The effects a worn item grants for as long as it is worn.
    var isWorn: Bool {
        castingType == .constantEffect
    }

    /// The effects a landed hit delivers. Contact delivery, which is the only
    /// delivery a weapon enchantment has.
    var isContact: Bool {
        delivery == .touch && !isWorn
    }

    /// Whether this is a staff enchantment, which neither of the two paths above
    /// carries out.
    var isStaff: Bool {
        type == .staffEnchantment
    }

    /// A fully charged reading, which is what an item nothing has spent yet
    /// reads.
    var fullCharge: EnchantmentCharge {
        EnchantmentCharge(capacity: capacity, costPerUse: costPerUse)
    }

    /// The charge with `remaining` left of it.
    func charge(remaining: Float) -> EnchantmentCharge {
        EnchantmentCharge(capacity: capacity, remaining: remaining, costPerUse: costPerUse)
    }

    /// What the applied effects are sourced to.
    var source: ActiveEffectSource {
        ActiveEffectSource(kind: .enchantment, record: enchantment)
    }

    /// Whether `keywords` satisfies the worn restriction: true when the
    /// enchantment names none, when the list is empty, and when the item carries
    /// one of the listed keywords.
    ///
    /// - Parameter listedKeywords: the resolved contents of `wornRestriction`,
    ///   or nil when the caller could not resolve the form list. An unresolvable
    ///   list allows everything, on the same reasoning an unresolvable link
    ///   elsewhere in this engine is data rather than a fault.
    func allowsWearing(keywords: [FormID], listedKeywords: [FormID]?) -> Bool {
        guard let listedKeywords, !listedKeywords.isEmpty else { return true }
        let carried = Set(keywords.map(\.rawValue))
        return listedKeywords.contains { carried.contains($0.rawValue) }
    }

    /// One line for a readout: what the enchantment is and what it costs.
    var describedLine: String {
        let shape = isWorn ? "worn" : (isStaff ? "staff" : "on hit")
        return "\(name) (\(shape)): \(fullCharge.describedLine)"
    }
}

nonisolated extension ItemEnchantmentProfile {
    /// Resolves one carried item's enchantment, or nil when the item carries
    /// none or its `EITM` does not resolve.
    ///
    /// - Parameters:
    ///   - definition: the unified item view, whose `enchantment` carries the
    ///     already load-order-resolved identity and the `EAMT` charge.
    ///   - store: the ENCH store, which supplies the effect list, the cost and
    ///     the base chain the worn restriction is read from.
    static func resolve(
        _ definition: ItemDefinition,
        using store: EnchantmentStore
    ) -> ItemEnchantmentProfile? {
        guard
            let link = definition.enchantment,
            let resolvedID = link.resolvedID,
            let resolved = store.enchantment(resolvedID)
        else { return nil }
        return ItemEnchantmentProfile(
            item: definition.formID,
            enchantment: ReferenceKey(resolved: resolved.id),
            sourcePlugin: resolved.sourcePlugin,
            entries: resolved.record.effects,
            name: resolved.displayName,
            castingType: resolved.data?.castingType ?? .fireAndForget,
            delivery: resolved.data?.delivery ?? .touch,
            type: resolved.data?.type ?? .enchantment,
            capacity: Float(link.charge ?? 0),
            costPerUse: Float(resolved.cost.cost),
            wornRestriction: store.baseChain(of: resolved.id)
                .lazy
                .compactMap { $0.data?.wornRestrictions }
                .first
        )
    }
}
