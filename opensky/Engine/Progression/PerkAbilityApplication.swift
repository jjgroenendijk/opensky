// Ability-type perk effects (issue #497, roadmap item 20.4): a perk that grants
// a spell for as long as the actor owns it.
//
// ## Reconciliation rather than an add hook
//
// Written as a *reconcile*, exactly like `WornEnchantmentApplication` and for
// the same reason: perks arrive from several places — a script's `AddPerk`, an
// NPC's `PRKR` seeding, a loaded save — and hanging "apply the ability" off each
// of them would be one missed call away from an effect that never comes off.
// Given who owns what, make the stored perk-sourced effects match; do nothing
// when they already do. Every path calls this afterwards, calling it twice
// changes nothing, and a loaded session calls it once per actor to pick up the
// abilities its restored perks grant.
//
// That is also why `ActiveEffectSourceKind.perk` exists. Dispelling by source
// *record* would take the ability off even when the actor still owns the perk
// that granted it, and a spell an actor also knows in its own right would be
// indistinguishable from one a perk lent it.
//
// ## What is applied
//
// The whole effect list of the granted SPEL, as `constant` effects, unscaled —
// the shape a worn enchantment uses, and for the same reason: UESP describes a
// perk ability as something the actor simply carries
// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PERK>, "the data is
// simply a spell applied without conditions"). A zero duration on such an entry
// means "for as long as it is carried" rather than "once", which is exactly
// what `isConstant` means to the active-effect runtime.
//
// Documented in docs/engine/perks.md and docs/engine/magic.md.

import Foundation

/// What one reconciliation did.
nonisolated struct PerkAbilityReport: Equatable, Sendable {
    /// Spells newly granted, in ascending key order.
    let granted: [ReferenceKey]
    /// Spells taken back off, in ascending key order.
    let revoked: [ReferenceKey]
    /// Constant effects stored across every newly granted ability.
    let storedCount: Int
    /// Effects dispelled across every revoked ability.
    let dispelledCount: Int

    static let none = PerkAbilityReport(
        granted: [], revoked: [], storedCount: 0, dispelledCount: 0
    )

    /// Whether anything moved, which is what tells a caller to refresh a
    /// readout.
    var didChange: Bool {
        !granted.isEmpty || !revoked.isEmpty
    }

    var describedLine: String {
        guard didChange else { return "Perk abilities unchanged." }
        return "Perk abilities: \(granted.count) granted (\(storedCount) effect(s)), "
            + "\(revoked.count) revoked (\(dispelledCount) effect(s))."
    }
}

@MainActor
enum PerkAbilityApplication {
    /// Makes the perk-sourced constant effects on `holder` match the abilities
    /// its owned perks grant.
    @discardableResult
    static func reconcile(
        on holder: ActorValueHolder,
        perks: PerkRuntime,
        spells: SpellStore,
        using runtime: inout ActiveEffectRuntime
    ) -> PerkAbilityReport {
        let wanted = abilities(of: holder, perks: perks, spells: spells)
        let held = Set(
            runtime.state(of: holder).effects
                .filter { $0.source.kind == .perk }
                .map(\.source.record)
        )
        var dispelledCount = 0
        let revoked = held.subtracting(wanted.keys).sorted()
        for spell in revoked {
            dispelledCount += runtime.dispel(on: holder) {
                $0.source.kind == .perk && $0.source.record == spell
            }
        }
        var granted: [ReferenceKey] = []
        var storedCount = 0
        for key in wanted.keys.sorted() where !held.contains(key) {
            guard let spell = wanted[key] else { continue }
            let stored = runtime.apply(
                spell.record.effects,
                fromPlugin: spell.sourcePlugin,
                source: ActiveEffectSource(kind: .perk, record: key),
                caster: holder.key,
                isConstant: true,
                on: holder
            )
            // An ability whose every entry was refused establishes nothing and
            // is deliberately not recorded, the rule the worn-enchantment
            // reconcile states: there would be no effect to dispel when the
            // perk came off.
            guard !stored.isEmpty else { continue }
            storedCount += stored.count
            granted.append(key)
        }
        return PerkAbilityReport(
            granted: granted,
            revoked: revoked,
            storedCount: storedCount,
            dispelledCount: dispelledCount
        )
    }

    /// The SPEL records every perk `holder` owns grants as an ability.
    ///
    /// Ability effects only. An entry-point effect whose function *selects* a
    /// spell is not an ability: that spell is cast when the entry point fires
    /// (a combat hit, a bash), not carried, and applying it here would give
    /// every Bladesman owner a permanent bleed.
    static func abilities(
        of holder: ActorValueHolder,
        perks: PerkRuntime,
        spells: SpellStore
    ) -> [ReferenceKey: ResolvedSpell] {
        var wanted: [ReferenceKey: ResolvedSpell] = [:]
        for perk in perks.ownedPerks(of: holder) {
            for effect in perk.effects where effect.effect.type == .ability {
                guard
                    case let .ability(link) = effect.effect.data,
                    let link,
                    let spell = spells.resolve(link, fromPlugin: perk.sourcePlugin)
                else { continue }
                wanted[spell.key] = spell
            }
        }
        return wanted
    }
}
