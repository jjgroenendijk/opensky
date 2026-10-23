// The magic menu's view of the spellbook: the player's known spells with their kind
// and hands, and readying one by its position in that list.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// One known spell as the magic menu lists it.
nonisolated public struct MagicMenuSpell: Equatable, Sendable {
    public let name: String
    /// "spell", "power", or "ability", from the load order's texts.
    public let typeName: String
    public let isReadied: Bool
}

extension MagicCoordinator {
    public var magicMenuSpells: [MagicMenuSpell] {
        guard let caster else { return [] }
        let book = caster.spellbook.state(of: .player)
        return playerKnownSpells().map { spell in
            MagicMenuSpell(
                name: spell.displayName,
                typeName: magicTexts.name(of: spell.spellType),
                isReadied: !book.hands(of: spell.key).isEmpty
            )
        }
    }

    /// Selects the known spell at `index` and readies it in `hand`.
    @discardableResult
    public func readyKnownSpell(at index: Int, in hand: SpellHand) -> CastingActionOutcome {
        guard playerKnownSpells().indices.contains(index) else {
            return recordCasting(.noSpellSelected)
        }
        selection = index
        return readySelectedSpell(in: hand)
    }
}

extension MagicCoordinator {
    /// A harmful effect drains the player's health each second, such as poison or fire.
    /// The game then refuses rest (`sNoWaitTakingHealthDamage`).
    public var isPlayerTakingHealthDamage: Bool {
        guard let runtime = effects, let health = ActorValueIdentity.index(named: "Health")
        else { return false }
        return runtime.active(on: .player).contains { effect in
            effect.isDetrimental && effect.mode == .perSecond
                && effect.values.contains { $0.index == health && $0.magnitude > 0 }
        }
    }
}
