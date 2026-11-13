// The player's blows on a friend or an ally, counted until one too many turns it on the
// player. See docs/engine/hostility.md#friendly-fire.

import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData

extension CombatLoopRuntime {
    nonisolated struct FriendlyFire: Equatable, Sendable {
        var settings = FriendlyFireSettings.vanilla
        /// Counted blows and the time of the last one, by actor.
        private(set) var hits: [ReferenceKey: FriendlyHits] = [:]

        init(settings: FriendlyFireSettings = .vanilla) {
            self.settings = settings
        }

        /// Counts the player's blow on `key` at `now` seconds. True when the actor attacks
        /// the player: always for a neutral or an enemy, and for a friend or an ally once
        /// the count passes what it allows.
        mutating func noteHit(
            on key: ReferenceKey, reaction: ActorReaction?, inCombat: Bool, now: Double
        ) -> Bool {
            guard let allowed = settings.allowedHits(for: reaction, inCombat: inCombat) else {
                hits[key] = nil
                return true
            }
            var entry = hits[key].flatMap { old in
                now - old.lastSeconds < Double(settings.hitTimer) ? old : nil
            } ?? FriendlyHits(count: 0, lastSeconds: -.infinity)
            if allowed >= FriendlyFireSettings.unlimited {
                entry = FriendlyHits(count: 1, lastSeconds: now)
            } else if now - entry.lastSeconds >= Double(settings.minimumLastHitTime) {
                entry = FriendlyHits(count: entry.count + 1, lastSeconds: now)
            }
            guard entry.count > allowed, allowed < FriendlyFireSettings.unlimited else {
                hits[key] = entry
                return false
            }
            hits[key] = nil
            return true
        }

        /// The counted blows on `key`, which `GetFriendHit` reads.
        func count(on key: ReferenceKey) -> Int {
            hits[key]?.count ?? 0
        }
    }
}

/// The player's counted blows on one actor, and when the last one landed.
nonisolated struct FriendlyHits: Equatable, Sendable {
    var count: Int
    var lastSeconds: Double
}
