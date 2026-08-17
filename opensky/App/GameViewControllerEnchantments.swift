// Session wiring for item enchantments (issue #472, roadmap item 19.9): where an
// equipped item's ENCH comes from, how a landed hit spends its charge, and how a
// worn item's constant effects go on and come off.
//
// AppKit stays in this controller satellite; the ledger, the profile, the charge
// arithmetic and both application paths are engine types that build into
// `openskycli` and are testable without a window.
//
// ## Two calls, and where they come from
//
// * `applyWeaponEnchantment(_:)` is the `WeaponEnchantmentApplying` conformance
//   both `MeleeCombatWorld` and `ProjectileWorld` refine, so a swing and an arrow
//   take the same path — the same reason `reportScriptHit` and `applySpellHit`
//   are each implemented once here.
// * `refreshWornEnchantments(on:)` reconciles rather than hooks. Every equip path
//   in this controller calls it afterwards, calling it twice changes nothing, and
//   a loaded session calls it once per actor. See `WornEnchantmentApplication` for
//   why that shape was chosen over an equip hook.
//
// The effect runtime is a value over a shared store, so it is taken out, worked
// through and put back — the pattern `applySpellHit` and `consumeMagicItem`
// follow, and what keeps the Magic Effects panel's tally counting an enchantment
// too.

import AppKit

/// Enchantment state the controller owns. Extensions cannot add stored
/// properties, so it lives as one value on `GameViewController`.
struct EnchantmentBridgeState {
    /// Load-order ENCH index, written by `wireEnchantments` when the provider can
    /// supply one. Nil without game data, and then an enchanted item applies
    /// nothing and the readout says so.
    var store: EnchantmentStore?
    /// What the most recent enchanted hit did. Nil until one lands.
    var lastHit: WeaponEnchantmentReport?
    /// What the most recent worn-item reconciliation did. Nil until one runs.
    var lastWorn: WornEnchantmentReport?
    /// Human-readable result of the last panel or menu action.
    var lastActionText = "No enchantment action yet."
}

extension GameViewController: WeaponEnchantmentApplying {
    /// Spends an enchanted weapon's charge and applies its effects to what it hit.
    @discardableResult
    func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        guard
            var runtime = magicEffects.runtime,
            let owner = actorValueHolder(for: hit.attacker)
        else { return nil }
        let report = WeaponEnchantmentApplication.apply(
            hit,
            owner: owner,
            target: actorValueHolder(for: hit.target),
            using: &runtime
        )
        magicEffects.runtime = runtime
        enchantments.lastHit = report
        return report
    }
}

extension GameViewController {
    /// Publishes the provider's ENCH index, so an equipped item can resolve its
    /// enchantment.
    ///
    /// Wired beside `wireMagicEffects`, which owns the effect runtime every
    /// application ultimately writes through.
    func wireEnchantments(provider: any CellSceneProvider) {
        enchantments.store = (provider as? MagicDataProviding)?.enchantmentStore
    }

    /// The resolved enchantment of one carried item, or nil when it carries none
    /// and when this session has no ENCH index.
    func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile? {
        guard
            let store = enchantments.store,
            let definition = worldItems.runtime?.inventory.baselines.items.definition(item)
        else { return nil }
        return ItemEnchantmentProfile.resolve(definition, using: store)
    }

    /// What `item` has left on `holder`, or nil when it carries no enchantment.
    func enchantmentCharge(of item: FormID, on holder: ActorValueHolder) -> EnchantmentCharge? {
        guard
            let runtime = magicEffects.runtime,
            let profile = enchantmentProfile(of: item)
        else { return nil }
        return EnchantmentLedger(store: runtime.store).charge(of: profile, on: holder)
    }

    /// Brings `holder`'s worn constant effects in line with what it is wearing.
    ///
    /// Called after every equip and unequip, and once per actor after a load. A
    /// call that changes nothing costs one component read.
    ///
    /// The inventory holder is what the equip paths have in hand, and the
    /// actor-value holder the effects are applied to is resolved from its key: an
    /// owner with no actor-value state — a container — wears nothing this could
    /// apply to, and answers "nothing changed".
    @discardableResult
    func refreshWornEnchantments(on holder: InventoryHolder) -> WornEnchantmentReport {
        guard
            var runtime = magicEffects.runtime,
            let equipment = worldItems.equipment,
            let values = actorValueHolder(for: holder.key)
        else { return .none }
        let worn = equipment.equipped(on: holder).compactMap { enchantmentProfile(of: $0) }
        let report = WornEnchantmentApplication.reconcile(
            worn: worn,
            on: values,
            using: &runtime
        )
        magicEffects.runtime = runtime
        if report.didChange {
            enchantments.lastWorn = report
        }
        return report
    }

    /// One item's enchantment and what it has left, preformatted, or nil when it
    /// carries none.
    ///
    /// The one place a charge is turned into words, so the equipment readout, the
    /// inventory menu detail and the magic panel cannot disagree about how much a
    /// weapon has left.
    ///
    /// A holder is needed for the *stored* charge; without one — an owner with no
    /// actor-value state — the item's own full charge is reported, which is what
    /// nothing having spent any means.
    func enchantmentLine(of item: FormID, on holder: ActorValueHolder?) -> String? {
        guard let profile = enchantmentProfile(of: item) else { return nil }
        let charge = holder.flatMap { enchantmentCharge(of: item, on: $0) } ?? profile.fullCharge
        let shape = profile.isWorn ? "worn" : (profile.isStaff ? "staff" : "on hit")
        return "\(profile.name) (\(shape)): \(charge.describedLine)"
    }
}
