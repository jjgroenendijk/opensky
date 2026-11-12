// Shouts: the equipped shout, its words, dragon souls, and
// the cooldown, with the control actions that teach, unlock, equip, and shout.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

extension MagicCoordinator.ShoutReadout {
    /// Teaches and unlocks every word, the way the Greybeards' words arrive unlocked.
    @discardableResult
    func learnShout(_ shout: ReferenceKey) -> ShoutOutcome {
        guard let resolved = coordinator.shouts[shout]
        else { return coordinator.shoutVoice.noteShout(.refused(.unknownShout)) }
        coordinator.world.changeShoutKnowledge(.addShout(shout))
        for word in coordinator.shoutVoice.wordKeys(of: resolved).compactMap(\.self) {
            coordinator.world.changeShoutKnowledge(.teachWord(word))
            coordinator.world.changeShoutKnowledge(.unlockWord(word))
        }
        return coordinator.shoutVoice.noteShout(.learned(shout: resolved.displayName))
    }

    @discardableResult
    func equipShout(_ shout: ReferenceKey) -> ShoutOutcome {
        guard let resolved = coordinator.shouts[shout]
        else { return coordinator.shoutVoice.noteShout(.refused(.unknownShout)) }
        coordinator.world.changeShoutKnowledge(.equip(shout))
        return coordinator.shoutVoice.noteShout(.equipped(shout: resolved.displayName))
    }

    /// Spends one dragon soul on the first learned word that is still locked.
    @discardableResult
    func unlockNextWord(of shout: ReferenceKey) -> ShoutOutcome {
        guard let resolved = coordinator.shouts[shout]
        else { return coordinator.shoutVoice.noteShout(.refused(.unknownShout)) }
        let knowledge = coordinator.world.shoutKnowledge
        let unlocked = coordinator.shoutVoice.unlockedWordCount(of: resolved)
        let words = coordinator.shoutVoice.wordKeys(of: resolved)
        guard words.indices.contains(unlocked), let word = words[unlocked] else {
            return coordinator.shoutVoice.noteShout(.refused(.wordAlreadyUnlocked))
        }
        guard knowledge.knownWords.contains(word)
        else { return coordinator.shoutVoice.noteShout(.refused(.wordNotKnown)) }
        guard dragonSouls >= 1, let index = Self.dragonSoulsIndex else {
            return coordinator.shoutVoice.noteShout(.refused(.noDragonSoul))
        }
        coordinator.effects?.values.addModifier(-1, to: .permanent, at: index, on: .player)
        coordinator.world.changeShoutKnowledge(.unlockWord(word))
        let name = resolved.words[unlocked].wordName
        return coordinator.shoutVoice.noteShout(.unlocked(word: name, soulsLeft: dragonSouls))
    }

    var dragonSouls: Int {
        guard let index = Self.dragonSoulsIndex else { return 0 }
        return Int((coordinator.effects?.values.value(at: index, on: .player) ?? 0).rounded(.down))
    }

    static let dragonSoulsIndex = ActorValueIdentity.index(named: "Dragon Souls")
}
