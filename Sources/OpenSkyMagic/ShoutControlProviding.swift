// Shouts: the equipped shout, its words, dragon souls, and
// the cooldown, with the control actions that teach, unlock, equip, and shout.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

extension MagicCoordinator {
    /// Teaches and unlocks every word, the way the Greybeards' words arrive unlocked.
    @discardableResult
    public func learnShout(_ shout: ReferenceKey) -> ShoutOutcome {
        guard let resolved = shouts[shout] else { return noteShout(.refused(.unknownShout)) }
        world.changeShoutKnowledge(.addShout(shout))
        for word in wordKeys(of: resolved).compactMap(\.self) {
            world.changeShoutKnowledge(.teachWord(word))
            world.changeShoutKnowledge(.unlockWord(word))
        }
        return noteShout(.learned(shout: resolved.displayName))
    }

    @discardableResult
    public func equipShout(_ shout: ReferenceKey) -> ShoutOutcome {
        guard let resolved = shouts[shout] else { return noteShout(.refused(.unknownShout)) }
        world.changeShoutKnowledge(.equip(shout))
        return noteShout(.equipped(shout: resolved.displayName))
    }

    /// Spends one dragon soul on the first learned word that is still locked.
    @discardableResult
    public func unlockNextWord(of shout: ReferenceKey) -> ShoutOutcome {
        guard let resolved = shouts[shout] else { return noteShout(.refused(.unknownShout)) }
        let knowledge = world.shoutKnowledge
        let unlocked = unlockedWordCount(of: resolved)
        let words = wordKeys(of: resolved)
        guard words.indices.contains(unlocked), let word = words[unlocked] else {
            return noteShout(.refused(.wordAlreadyUnlocked))
        }
        guard knowledge.knownWords.contains(word) else { return noteShout(.refused(.wordNotKnown)) }
        guard dragonSouls >= 1, let index = Self.dragonSoulsIndex else {
            return noteShout(.refused(.noDragonSoul))
        }
        effects?.values.addModifier(-1, to: .permanent, at: index, on: .player)
        world.changeShoutKnowledge(.unlockWord(word))
        let name = resolved.words[unlocked].wordName
        return noteShout(.unlocked(word: name, soulsLeft: dragonSouls))
    }

    var dragonSouls: Int {
        guard let index = Self.dragonSoulsIndex else { return 0 }
        return Int((effects?.values.value(at: index, on: .player) ?? 0).rounded(.down))
    }

    static let dragonSoulsIndex = ActorValueIdentity.index(named: "Dragon Souls")
}
