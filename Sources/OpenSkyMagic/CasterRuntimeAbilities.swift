// Abilities: the part of the caster runtime that applies what an actor carries
// rather than casts. Every entry of an ability lasts as long as the spell is
// known, whatever its duration, so a zero-duration racial resistance holds.
// Written as a reconcile, like `PerkAbilityApplication`. See
// docs/engine/spellcasting.md#abilities-and-powers.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// What one ability reconcile did.
nonisolated public struct AbilityReconcileReport: Equatable, Sendable {
    /// Abilities newly applied and taken off, in key order.
    public let applied: [ReferenceKey]
    public let removed: [ReferenceKey]
    /// Constant effects stored across every newly applied ability.
    public let storedCount: Int

    public static let none = AbilityReconcileReport(applied: [], removed: [], storedCount: 0)
}

@MainActor
public enum SpellAbilityApplication {
    /// Makes `holder`'s ability effects match the abilities in `known`.
    @discardableResult
    public static func reconcile(
        known: [ResolvedSpell],
        on holder: ActorValueHolder,
        using runtime: inout ActiveEffectRuntime
    ) -> AbilityReconcileReport {
        let wanted = Dictionary(
            known.filter { $0.spellType == .ability }.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let held = Set(
            runtime.state(of: holder).effects
                .filter { $0.source.kind == .ability }
                .map(\.source.record)
        )
        let removed = held.subtracting(wanted.keys).sorted()
        for spell in removed {
            runtime.dispel(on: holder) { $0.source.kind == .ability && $0.source.record == spell }
        }
        var applied: [ReferenceKey] = []
        var storedCount = 0
        for key in wanted.keys.sorted() where !held.contains(key) {
            guard let spell = wanted[key] else { continue }
            let stored = runtime.apply(
                spell.record.effects,
                fromPlugin: spell.sourcePlugin,
                source: ActiveEffectSource(kind: .ability, record: key),
                caster: holder.key,
                isConstant: true,
                on: holder
            )
            // An ability that stored nothing is not recorded, so there is no
            // effect to dispel when it is forgotten.
            guard !stored.isEmpty else { continue }
            storedCount += stored.count
            applied.append(key)
        }
        return AbilityReconcileReport(applied: applied, removed: removed, storedCount: storedCount)
    }
}

extension CasterRuntime {
    /// Every ability `holder` knows, resolved.
    public func knownAbilities(of holder: ActorValueHolder) -> [ResolvedSpell] {
        spellbook.knownSpells(of: holder).filter { $0.spellType == .ability }
    }
}
