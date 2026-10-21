// The shout side of `MagicWorld`: what the player knows lives in the script state the
// Papyrus shout natives write, so a word wall script and the panel change one record.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyScripting
import OpenSkyScriptingInterface

extension MagicWorldAdapter {
    var shoutKnowledge: ShoutKnowledge {
        guard let state = game.scripts.bridge?.scriptedState(of: .player) else {
            return ShoutKnowledge()
        }
        var knowledge = ShoutKnowledge(equipped: state.form(ScriptedStateName.equippedShout))
        for (key, shout) in game.magic.shouts {
            if state.flag(ScriptedStateName.shout(key)) == true {
                knowledge.shouts.insert(key)
            }
            for word in shout.words.compactMap(\.word) {
                let wordKey = ReferenceKey(resolved: word.id)
                if state.flag(ScriptedStateName.wordKnown(wordKey)) == true {
                    knowledge.knownWords.insert(wordKey)
                }
                if state.flag(ScriptedStateName.wordUnlocked(wordKey)) == true {
                    knowledge.unlockedWords.insert(wordKey)
                }
            }
        }
        return knowledge
    }

    func changeShoutKnowledge(_ change: ShoutKnowledgeChange) {
        game.scripts.bridge?.updateScriptedState(of: .player) { state in
            switch change {
            case let .addShout(shout): state.setFlag(ScriptedStateName.shout(shout), true)
            case let .equip(shout): state.setForm(ScriptedStateName.equippedShout, shout)
            case let .teachWord(word): state.setFlag(ScriptedStateName.wordKnown(word), true)
            case let .unlockWord(word): state.setFlag(ScriptedStateName.wordUnlocked(word), true)
            }
        }
    }

    func wireShouts(provider: WorldDataStores) {
        game.magic.shoutSettings = ShoutSettings.resolve(store: provider.gameSettings)
        game.magic.wireShouts(store: provider.shoutStore)
    }
}
