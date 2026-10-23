// The player's shout: the key feeds `ShoutMachine`, the graph hears `bWantCastVoice`
// and `shoutRelease`, and the spell of the shouted word fires on the exhale's
// `Voice_SpellFire_Event`. Entry point 82 (Mod Shout OK) gates it. See docs/engine/shouts.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

/// The graph names a shout uses (`0_master.hkx`, `shout_behavior.hkx`).
nonisolated public enum ShoutGraphNames: Sendable {
    /// Raised at the release; the graph plays the exhale.
    public static let release = "shoutRelease"
    /// The exhale clips' annotation at the frame the voice leaves the mouth. Two
    /// vanilla clips spell it `Voice_Spellfire_Event`, so the match ignores case.
    public static let spellFire = "Voice_SpellFire_Event"

    /// Every event the shout runtime acts on when the graph fires it.
    public static let observedEvents = [spellFire]
}

nonisolated public enum ShoutRefusal: Equatable, Sendable {
    /// Entry point 82 left the value at or below 0; `AllowShoutingPerk` adds 1.
    case notAllowed
    case recovering(seconds: Float)
    case noShoutEquipped
    case noWordUnlocked
    /// UESP: a hand that casts cannot shout (`sMagicCastShoutWhileCasting`).
    case casting
    case unknownShout
    case wordNotKnown
    case wordAlreadyUnlocked
    case noDragonSoul
}

nonisolated public enum ShoutOutcome: Equatable, Sendable {
    case idle
    case shouted(shout: String, words: Int, cooldown: Float)
    case refused(ShoutRefusal)
    case unlocked(word: String, soulsLeft: Int)
    case learned(shout: String)
    case equipped(shout: String)
    case unavailable
}

extension MagicCoordinator {
    public func wireShouts(store: ShoutStore?) {
        var byKey: [ReferenceKey: ResolvedShout] = [:]
        for (id, shout) in store?.shouts ?? [:] {
            byKey[ReferenceKey(resolved: id)] = shout
        }
        shouts = byKey
        shoutStore = store
    }

    /// The shouts on an NPC's own and race spell lists (`SPLO` entries that name a `SHOU`).
    public func npcShouts(of holder: ActorValueHolder) -> [ResolvedShout] {
        guard let shoutStore, let spellBaselines, let spellPluginName else { return [] }
        return spellBaselines.baseline(for: holder.subject).all.compactMap {
            shoutStore.resolve($0, fromPlugin: spellPluginName)
        }
    }

    /// An NPC shouts `spell`, a word's spell, along its facing. No cooldown is kept here;
    /// the combat machine keeps the word's recovery time.
    @discardableResult
    public func npcShout(_ spell: ReferenceKey, by holder: ActorValueHolder) -> Bool {
        guard
            let caster,
            let word = shouts.values.lazy.flatMap(\.words).first(where: { $0.spell?.key == spell }),
            let resolved = word.spell
        else { return false }
        _ = caster.apply(resolved, caster: holder)
        spellWasCast(spell, by: holder.key)
        return true
    }

    /// Entry point 82 on a base of 0: `AllowShoutingPerk` adds 1 once its quest stage is done.
    public var isShoutAllowed: Bool {
        world.perkModified(
            0, at: .modShoutOK, on: .player,
            subjects: PerkEvaluationSubjects(owner: .player), seams: ConditionContext()
        ) > 0
    }

    public var equippedShout: ResolvedShout? {
        world.shoutKnowledge.equipped.flatMap { shouts[$0] }
    }

    public func unlockedWordCount(of shout: ResolvedShout) -> Int {
        ShoutCore.unlockedWordCount(
            wordKeys(of: shout),
            unlocked: world.shoutKnowledge.unlockedWords
        )
    }

    func wordKeys(of shout: ResolvedShout) -> [ReferenceKey?] {
        shout.words.map { $0.word.map { ReferenceKey(resolved: $0.id) } }
    }

    /// One frame of the shout key. `events` are the player graph's events since the last frame.
    public func advanceShout(
        held: Bool, delta: Float, events: [String], isPlayerControlled: Bool
    ) -> [MagicCommand] {
        let keyHeld = held && isPlayerControlled
        if keyHeld, !wasShoutHeld, shoutMachine.isIdle {
            beginShout()
        }
        wasShoutHeld = keyHeld
        let panelHeld = (panelShoutHold ?? 0) > 0
        panelShoutHold = panelShoutHold.map { $0 - delta }.flatMap { $0 > 0 ? $0 : nil }
        let held = keyHeld || panelHeld
        let fired = events
            .contains { $0.caseInsensitiveCompare(ShoutGraphNames.spellFire) == .orderedSame }
        let unlocked = voicedShout.flatMap { shouts[$0] }.map(unlockedWordCount) ?? 0
        switch shoutMachine.advance(
            held: held, delta: delta, unlockedWords: unlocked, fired: fired, settings: shoutSettings
        ) {
        case .none: break
        case .release: pendingCommands.append(.playerGraphEvent(ShoutGraphNames.release))
        case let .fire(words): fireShout(words: words)
        }
        return takeCommands()
    }

    /// The press: every refusal is checked here, so a held key that was refused stays quiet.
    @discardableResult
    func beginShout() -> ShoutOutcome {
        if let refusal = shoutRefusal() {
            if refusal == .casting {
                pendingCommands.append(.notice(castNotices[.shoutWhileCasting]))
            }
            return noteShout(.refused(refusal))
        }
        voicedShout = world.shoutKnowledge.equipped
        shoutMachine.begin()
        return lastShout
    }

    func shoutRefusal() -> ShoutRefusal? {
        guard isShoutAllowed else { return .notAllowed }
        guard shoutMachine.cooldown <= 0 else { return .recovering(seconds: shoutMachine.cooldown) }
        guard let shout = equippedShout else { return .noShoutEquipped }
        guard unlockedWordCount(of: shout) > 0 else { return .noWordUnlocked }
        let casting = SpellHand.allCases.contains { caster?.phase(of: $0).isCasting ?? false }
        return casting ? .casting : nil
    }

    private func fireShout(words: Int) {
        defer { voicedShout = nil }
        guard
            let key = voicedShout, let shout = shouts[key],
            shout.words.indices.contains(words - 1),
            let spell = shout.words[words - 1].spell,
            let caster, let holder = world.actorValueHolder(for: .player)
        else { return }
        _ = caster.apply(spell, caster: holder)
        spellWasCast(spell.key, by: .player)
        let multiplier = ActorValueIdentity.index(named: "Shout Recovery Mult")
            .flatMap { effects?.values.value(at: $0, on: .player) } ?? 1
        let cooldown = ShoutCore.cooldown(
            recovery: shout.words[words - 1].entry.recoveryTime, multiplier: multiplier
        )
        shoutMachine.startCooldown(cooldown)
        pendingCommands.append(.playerShouted)
        noteShout(.shouted(shout: shout.displayName, words: words, cooldown: cooldown))
    }

    @discardableResult
    func noteShout(_ outcome: ShoutOutcome) -> ShoutOutcome {
        lastShout = outcome
        return outcome
    }
}
