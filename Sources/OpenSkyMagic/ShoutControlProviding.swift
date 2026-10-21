// World > Combat & Physics > Shouts: the equipped shout, its words, dragon souls, and
// the cooldown, with the panel actions that teach, unlock, equip, and shout.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct ShoutReadout: Equatable, Sendable {
    public let key: ReferenceKey
    public let name: String
    public let wordsKnown: Int
    public let wordsUnlocked: Int
    public let wordCount: Int

    public init(
        key: ReferenceKey,
        name: String,
        wordsKnown: Int,
        wordsUnlocked: Int,
        wordCount: Int
    ) {
        self.key = key
        self.name = name
        self.wordsKnown = wordsKnown
        self.wordsUnlocked = wordsUnlocked
        self.wordCount = wordCount
    }
}

nonisolated public struct ShoutControlSnapshot: Equatable, Sendable {
    public var isAvailable = false
    public var isAllowed = false
    public var dragonSouls = 0
    public var equipped: ReferenceKey?
    public var known: [ShoutReadout] = []
    /// Every shout of the load order, for the teach control.
    public var all: [ShoutReadout] = []
    public var phase = ShoutPhase.idle
    public var cooldown: Float = 0
    public var lastShout = ShoutOutcome.idle

    public static let unavailable = Self()

    public init() {}

    public var readoutText: String {
        guard isAvailable else { return "Shouts: unavailable" }
        let equippedName = known.first { $0.key == equipped }.map {
            "\($0.name) (\($0.wordsUnlocked) of \($0.wordCount) words)"
        } ?? "none"
        return [
            "Shouting allowed (entry point 82): \(isAllowed ? "yes" : "no")",
            "Equipped: \(equippedName)   Dragon souls: \(dragonSouls)",
            "Phase: \(phase.text)   Cooldown: " + String(format: "%.1f s", cooldown),
            "Last: \(lastShout.text)"
        ].joined(separator: "\n")
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

@MainActor
public protocol ShoutControlProviding: AnyObject {
    var shoutSnapshot: ShoutControlSnapshot { get }
    @discardableResult
    func learnShout(_ shout: ReferenceKey) -> ShoutOutcome
    @discardableResult
    func equipShout(_ shout: ReferenceKey) -> ShoutOutcome
    @discardableResult
    func unlockNextWord(of shout: ReferenceKey) -> ShoutOutcome
    func addDragonSoul()
    /// Holds the shout key long enough for `words` words.
    @discardableResult
    func shout(words: Int) -> ShoutOutcome
}

extension MagicCoordinator: ShoutControlProviding {
    public var shoutSnapshot: ShoutControlSnapshot {
        guard effects != nil, caster != nil, !shouts.isEmpty else { return .unavailable }
        var snapshot = ShoutControlSnapshot()
        snapshot.isAvailable = true
        snapshot.isAllowed = isShoutAllowed
        snapshot.dragonSouls = dragonSouls
        snapshot.equipped = world.shoutKnowledge.equipped
        snapshot.known = knownShouts.compactMap(shoutReadout)
        snapshot.all = shouts.keys.sorted().compactMap(shoutReadout)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        snapshot.phase = shoutMachine.phase
        snapshot.cooldown = shoutMachine.cooldown
        snapshot.lastShout = lastShout
        return snapshot
    }

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

    public func addDragonSoul() {
        guard let index = Self.dragonSoulsIndex else { return }
        effects?.values.addModifier(1, to: .permanent, at: index, on: .player)
    }

    @discardableResult
    public func shout(words: Int) -> ShoutOutcome {
        guard shoutMachine.isIdle else { return lastShout }
        let outcome = beginShout()
        guard !shoutMachine.isIdle else { return outcome }
        let hold = ShoutCore.fullChargeHold(unlocked: max(1, words), settings: shoutSettings)
        panelShoutHold = hold > 0 ? hold + 0.05 : 0
        return outcome
    }

    var dragonSouls: Int {
        guard let index = Self.dragonSoulsIndex else { return 0 }
        return Int((effects?.values.value(at: index, on: .player) ?? 0).rounded(.down))
    }

    static let dragonSoulsIndex = ActorValueIdentity.index(named: "Dragon Souls")

    private func shoutReadout(_ key: ReferenceKey) -> ShoutReadout? {
        guard let shout = shouts[key] else { return nil }
        let words = wordKeys(of: shout)
        let known = world.shoutKnowledge.knownWords
        return ShoutReadout(
            key: key, name: shout.displayName,
            wordsKnown: words.filter { $0.map(known.contains) ?? false }.count,
            wordsUnlocked: unlockedWordCount(of: shout), wordCount: words.count
        )
    }
}
