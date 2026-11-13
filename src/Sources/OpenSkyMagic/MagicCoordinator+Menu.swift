// The magic menu's view of the spellbook: the player's known spells with their kind
// and hands, and readying one by its position in that list.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMagicInterface

extension MagicCoordinator.MagicMenu {
    public var magicMenuSpells: [MagicMenuSpell] {
        guard let caster = coordinator.caster else { return [] }
        let book = caster.spellbook.state(of: .player)
        let texts = coordinator.texts.magic
        return coordinator.controlPanels.playerKnownSpells().map { spell in
            MagicMenuSpell(
                name: spell.displayName,
                isReadied: !book.hands(of: spell.key).isEmpty,
                category: texts.menuCategory(of: spell.spellType, magicSkill: spell.magicSkill)
            )
        }
    }

    /// The names of the effects on the player, for the menu's last tab.
    public var magicMenuActiveEffects: [String] {
        guard let runtime = coordinator.effects else { return [] }
        return runtime.active(on: .player).map { effect in
            coordinator.effectsPanel.readout(of: effect, runtime: runtime).name
        }
    }

    public var magicMenuCategoryOrder: [String] {
        coordinator.texts.magic.menuCategoryOrder
    }

    /// The last tab's title.
    public var magicMenuActiveEffectsTitle: String {
        coordinator.texts.magic.word("sActiveEffects", or: "ACTIVE EFFECTS")
    }

    /// Selects the known spell at `index` and readies it in `hand`.
    @discardableResult
    func readyKnownSpell(at index: Int, in hand: SpellHand) -> CastingActionOutcome {
        guard coordinator.controlPanels.playerKnownSpells().indices.contains(index) else {
            return coordinator.recordCasting(.noSpellSelected)
        }
        coordinator.castingState.selection = index
        return coordinator.controlPanels.readySelectedSpell(in: hand)
    }
}

extension MagicCoordinator.MagicMenu {
    /// A harmful effect drains the player's health each second, such as poison or fire.
    /// The game then refuses rest (`sNoWaitTakingHealthDamage`).
    public var isPlayerTakingHealthDamage: Bool {
        guard
            let runtime = coordinator.effects,
            let health = ActorValueIdentity.index(named: "Health")
        else { return false }
        return runtime.active(on: .player).contains { effect in
            effect.isDetrimental && effect.mode == .perSecond
                && effect.values.contains { $0.index == health && $0.magnitude > 0 }
        }
    }
}
