// Abilities (issue #470, roadmap item 19.7): the half of the caster runtime
// that applies what an actor simply carries rather than what a hand casts.
//
// A satellite of `CasterRuntime` so that type stays under the strict-lint body
// cap, and along a real seam: everything else in that file is a cast the player
// asked for, and nothing here is cast at all.
//
// Documented in docs/engine/magic.md.

import Foundation

extension CasterRuntime {
    /// Applies every ability `holder` knows as an effect on `holder`.
    ///
    /// An ability is a spell of SPIT type `ability`: nothing casts it, the actor
    /// simply has it. Vanilla authors most ability entries with a zero duration,
    /// meaning "for as long as the actor carries it", and the active-effect
    /// runtime has no permanent mode — a zero-duration entry there applies once
    /// and is stored nowhere, which for a resistance would be a one-off nudge
    /// wearing the name of a permanent bonus. Those entries are counted here
    /// rather than applied wrongly (`CastingTally.unheldAbilityEntries`); the
    /// timed ones apply normally.
    ///
    /// - Returns: how many timed effects were stored.
    @discardableResult
    func applyAbilities(on holder: ActorValueHolder) -> Int {
        guard let world else { return 0 }
        var stored = 0
        for spell in spellbook.knownSpells(of: holder) where spell.spellType == .ability {
            let entries = spell.record.effects
            let timed = entries.filter { $0.duration > 0 }
            tally.noteUnheldAbilityEntries(entries.count - timed.count)
            guard !timed.isEmpty else { continue }
            stored += world.applyCastEffects(
                timed,
                fromPlugin: spell.sourcePlugin,
                source: ActiveEffectSource(kind: .spell, record: spell.key),
                caster: holder.key,
                on: holder
            )
        }
        return stored
    }
}
