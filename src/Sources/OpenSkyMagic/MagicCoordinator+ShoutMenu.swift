// Shouts in the magic menu: Accept equips one, and the unlock key spends a dragon soul
// on its next learned word after a question. See docs/engine/shouts.md#magic-menu.

import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface

extension MagicCoordinator.MagicMenu {
    /// The shouts `AddShout` gave, and those with a learned word, by name.
    var menuShouts: [(key: ReferenceKey, shout: ResolvedShout)] {
        let knowledge = coordinator.world.shoutKnowledge
        let voice = coordinator.shoutVoice
        return coordinator.shouts
            .filter { key, shout in
                knowledge.shouts.contains(key)
                    || voice.wordKeys(of: shout)
                    .contains { $0.map(knowledge.knownWords.contains) == true }
            }
            .map { (key: $0.key, shout: $0.value) }
            .sorted { lhs, rhs in
                (lhs.shout.displayName, lhs.key.description)
                    < (rhs.shout.displayName, rhs.key.description)
            }
    }

    public var magicMenuShouts: [MagicMenuSpell] {
        let texts = coordinator.texts.magic
        let equipped = coordinator.world.shoutKnowledge.equipped
        return menuShouts.map {
            MagicMenuSpell(
                name: $0.shout.displayName, typeName: texts.name(of: .voice),
                isReadied: $0.key == equipped, category: texts.menuCategory(
                    of: .voice,
                    magicSkill: nil
                )
            )
        }
    }

    /// Equips the shout; a shout in progress keeps the old one.
    public func readyShout(at index: Int, texts: GameSettingTexts<ShoutMenuText>) -> String {
        let shouts = menuShouts
        guard shouts.indices.contains(index) else { return "No shout selected." }
        guard coordinator.shoutMachine.isIdle else { return texts[.failShouting] }
        coordinator.shoutReadout.equipShout(shouts[index].key)
        return "Equipped \(shouts[index].shout.displayName)."
    }

    /// Nil when the shout has no learned word left to unlock.
    public func shoutUnlockStep(
        at index: Int, texts: GameSettingTexts<ShoutMenuText>
    ) -> ShoutUnlockStep? {
        let shouts = menuShouts
        guard shouts.indices.contains(index) else { return nil }
        let shout = shouts[index].shout
        let voice = coordinator.shoutVoice
        let unlocked = voice.unlockedWordCount(of: shout)
        let words = voice.wordKeys(of: shout)
        guard
            words.indices.contains(unlocked), let word = words[unlocked],
            coordinator.world.shoutKnowledge.knownWords.contains(word)
        else { return nil }
        return coordinator.shoutReadout.dragonSouls >= 1
            ? .ask(texts[.confirmSpendSoul]) : .refuse(texts[.failSpendSoul])
    }

    public func unlockShout(at index: Int) -> String {
        let shouts = menuShouts
        guard shouts.indices.contains(index) else { return "No shout selected." }
        let outcome = coordinator.shoutReadout.unlockNextWord(of: shouts[index].key)
        guard case let .unlocked(word, soulsLeft) = outcome else { return "\(outcome)" }
        return "Unlocked \(word); \(soulsLeft) dragon souls left."
    }
}
