// Ability-type perk effects: a perk that grants a spell while owned. Written as
// a reconcile, like `WornEnchantmentApplication`, so every path that changes
// perks calls it and a second call changes nothing. Effects use
// `ActiveEffectSourceKind.perk` and apply as unscaled constants
// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PERK>).
// See docs/engine/perks.md and docs/engine/spellcasting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

/// What one reconciliation did.
nonisolated public struct PerkAbilityReport: Equatable, Sendable {
    /// Spells newly granted, in ascending key order.
    public let granted: [ReferenceKey]
    /// Spells taken back off, in ascending key order.
    public let revoked: [ReferenceKey]
    /// Constant effects stored across every newly granted ability.
    public let storedCount: Int
    /// Effects dispelled across every revoked ability.
    public let dispelledCount: Int

    public static let none = PerkAbilityReport(
        granted: [], revoked: [], storedCount: 0, dispelledCount: 0
    )

    /// Whether anything moved, which is what tells a caller to refresh a
    /// readout.
    public var didChange: Bool {
        !granted.isEmpty || !revoked.isEmpty
    }
}

@MainActor
public enum PerkAbilityApplication {
    /// Makes the perk-sourced constant effects on `holder` match the abilities
    /// its owned perks grant.
    @discardableResult
    public static func reconcile(
        on holder: ActorValueHolder,
        perks: any PerkAccess,
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
    public static func abilities(
        of holder: ActorValueHolder,
        perks: any PerkAccess,
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
