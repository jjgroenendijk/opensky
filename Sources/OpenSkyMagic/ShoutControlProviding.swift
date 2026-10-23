// Shouts: the equipped shout, its words, dragon souls, and
// the cooldown, with the control actions that teach, unlock, equip, and shout.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension MagicTimeScales {
    public var text: String {
        String(format: "world %.0f%%, player %.0f%%", world * 100, player * 100)
    }
}

nonisolated extension ShoutPhase {
    public var text: String {
        switch self {
        case .idle: "idle"
        case let .inhaling(held): "inhaling " + String(format: "%.2f s", held)
        case let .exhaling(words, _): "exhaling \(words) word\(words == 1 ? "" : "s")"
        }
    }
}

nonisolated extension ShoutOutcome {
    public var text: String {
        switch self {
        case .idle: "none yet"
        case let .shouted(shout, words, cooldown):
            "shouted \(shout), \(words) word\(words == 1 ? "" : "s"), " + String(
                format: "%.1f s",
                cooldown
            )
        case let .refused(refusal): "refused: \(refusal.text)"
        case let .unlocked(word, souls): "unlocked \(word), \(souls) dragon souls left"
        case let .learned(shout): "learned every word of \(shout)"
        case let .equipped(shout): "equipped \(shout)"
        case .unavailable: "unavailable"
        }
    }
}

nonisolated extension ShoutRefusal {
    public var text: String {
        switch self {
        case .notAllowed: "shouting is not allowed yet (entry point 82)"
        case let .recovering(seconds): "recovering, " + String(format: "%.1f s", seconds) + " left"
        case .noShoutEquipped: "no shout equipped"
        case .noWordUnlocked: "no word of the shout is unlocked"
        case .casting: "a hand is casting"
        case .unknownShout: "no such shout in the load order"
        case .wordNotKnown: "the next word is not learned"
        case .wordAlreadyUnlocked: "every learned word is unlocked"
        case .noDragonSoul: "no dragon soul to spend"
        }
    }
}

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
