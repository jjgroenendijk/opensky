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
            var row = MagicMenuSpell(
                name: spell.displayName,
                isReadied: !book.hands(of: spell.key).isEmpty,
                category: texts.menuCategory(of: spell.spellType, magicSkill: spell.magicSkill),
                card: card(of: spell, caster: caster, texts: texts)
            )
            row.hands = book.hands(of: spell.key)
            return row
        }
    }

    /// The level is the minimum skill level of the costliest effect, the effect that
    /// also picks the school.
    private func card(
        of spell: ResolvedSpell, caster: CasterRuntime, texts: MagicTexts
    ) -> MagicMenuSpellCard {
        let costliest = spell.effects.max { $0.cost < $1.cost }
        let isPower = spell.spellType == .power || spell.spellType == .lesserPower
        return MagicMenuSpellCard(
            kind: isPower ? .power : .spell,
            effects: cardText(of: spell),
            cost: Int(caster.cost(of: spell, caster: .player).rounded()),
            costIsPerSecond: spell.data?.castingType == .concentration,
            level: texts.level(minimumSkill: costliest?.effect?.effect.data?.minimumSkillLevel ?? 0)
        )
    }

    /// The spell's own description, or else the description of each effect the player
    /// would get, with its numbers after the player's perks. See docs/engine/magic.md.
    private func cardText(of spell: ResolvedSpell) -> String {
        if let own = spell.localizedDescription, !own.isEmpty {
            return own
        }
        let shown = spell.effects.filter { entry in
            !(entry.effect?.effect.data?.flags.contains(.hideInUI) ?? false)
                && entryHoldsForPlayer(entry.item.conditions)
        }
        let scaled = coordinator.perkEffects.perkScaledForMenu(shown.map(\.item), of: spell)
        return zip(shown, scaled).map { entry, values in
            Self.line(of: entry, values: values)
        }.joined(separator: " ")
    }

    private static func line(of entry: ResolvedSpellEffect, values: MagicItemEffect) -> String {
        let flags = entry.effect?.effect.data?.flags ?? []
        let filled = MagicDescriptionText.Values(
            magnitude: flags.contains(.noMagnitude) ? nil : values.magnitude,
            duration: flags.contains(.noDuration) ? nil : Float(values.duration),
            area: flags.contains(.noArea) ? nil : Float(values.area)
        )
        guard let template = entry.effect?.localizedDescription, !template.isEmpty else {
            return [entry.displayName, filled.magnitude.map(MagicDescriptionText.number)]
                .compactMap(\.self).joined(separator: " ")
        }
        return MagicDescriptionText.filled(template, values: filled)
    }

    /// An entry's conditions ask about the actor that gets the effect, here the player.
    /// Without an effect runtime every entry shows.
    private func entryHoldsForPlayer(_ list: ConditionList) -> Bool {
        guard
            !list.conditions.isEmpty,
            coordinator.effects != nil,
            let player = coordinator.world.actorValueHolder(for: .player)
        else { return true }
        return coordinator.effects?.allows(list, on: player) ?? true
    }

    /// The effects on the player, for the menu's last tab. An effect with an end shows
    /// the whole seconds it has left.
    public var magicMenuActiveEffects: [MagicMenuSpell] {
        guard let runtime = coordinator.effects else { return [] }
        return runtime.active(on: .player).map { effect in
            let name = coordinator.effectsPanel.readout(of: effect, runtime: runtime).name
            let secondsLeft = effect.lifetime > 0 ? Int(effect.remaining.rounded(.down)) : nil
            var row = MagicMenuSpell(
                name: name, isReadied: false, card: MagicMenuSpellCard(
                    kind: .activeEffect(secondsLeft: secondsLeft),
                    effects: activeEffectText(of: effect, runtime: runtime, name: name)
                )
            )
            row.isNegative = effect.isDetrimental
            return row
        }
    }

    /// The effect's own description with its running magnitude and duration filled in,
    /// or its name and magnitude when it has none.
    private func activeEffectText(
        of effect: ActiveEffect, runtime: ActiveEffectRuntime, name: String
    ) -> String {
        let record = runtime.effects.effect(key: effect.effect)
        let flags = record?.effect.data?.flags ?? []
        let magnitude = effect.values.first?.magnitude
        let filled = MagicDescriptionText.Values(
            magnitude: flags.contains(.noMagnitude) ? nil : magnitude,
            duration: flags.contains(.noDuration) ? nil : effect.duration,
            area: nil
        )
        guard let template = record?.localizedDescription, !template.isEmpty else {
            return [name, filled.magnitude.map(MagicDescriptionText.number)]
                .compactMap(\.self).joined(separator: " ")
        }
        return MagicDescriptionText.filled(template, values: filled)
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
