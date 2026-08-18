// Active-effect readout lines (issue #469, roadmap item 19.6), formatted here
// rather than in the panel section for the reason `ActorValueControlReadout` is:
// a string a milestone gate asserts on belongs in the engine target, where a
// unit test can reach it without a window.
//
// Documented in docs/engine/magic.md.

import Foundation

nonisolated enum MagicEffectControlReadout {
    /// The player's effect list, one line per effect, or the honest absence of
    /// one.
    static func effectsText(for snapshot: MagicEffectControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Player effects: unavailable" }
        guard !snapshot.playerEffects.isEmpty else {
            return "Player effects: none running"
        }
        let lines = snapshot.playerEffects.map { "  \($0.line)" }.joined(separator: "\n")
        return "Player effects (\(snapshot.playerEffects.count)):\n\(lines)"
    }

    /// The nearest resident actor's effect list, which is the actor the
    /// resistance values in the Actor Values section above are read about
    /// (issue #475, roadmap item 19.12).
    ///
    /// "no actor resident" and "an actor with nothing running" are different
    /// states and are spelled differently: an NPC that just took a hostile
    /// spell and an empty cell must not read the same.
    static func nearestActorEffectsText(for snapshot: MagicEffectControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Nearest actor effects: unavailable" }
        guard let name = snapshot.nearestActorName else {
            return "Nearest actor effects: none resident"
        }
        guard !snapshot.nearestActorEffects.isEmpty else {
            return "Nearest actor effects: none running on \(name)"
        }
        let lines = snapshot.nearestActorEffects.map { "  \($0.line)" }.joined(separator: "\n")
        return "Nearest actor effects — \(name) (\(snapshot.nearestActorEffects.count)):"
            + "\n\(lines)"
    }

    /// What the runtime has done this session.
    static func activityText(for snapshot: MagicEffectControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Applied: unavailable" }
        return "Applied: \(snapshot.appliedCount) timed, \(snapshot.instantCount) instant — "
            + "\(snapshot.expiredCount) expired, \(snapshot.dispelledCount) dispelled, "
            + "\(snapshot.runtimeActorCount) actor(s) carrying effects"
    }

    /// What it declined to do, which is the point of the tally: unimplemented
    /// ground is measured rather than silent.
    static func coverageText(for snapshot: MagicEffectControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Coverage: unavailable" }
        guard snapshot.skippedCount > 0 else {
            return "Coverage: every effect entry applied"
        }
        let unimplemented = snapshot.unimplementedLines.isEmpty
            ? "none named"
            : snapshot.unimplementedLines.joined(separator: ", ")
        return "Coverage: \(snapshot.skippedCount) entr(ies) skipped — "
            + "unimplemented archetypes: \(unimplemented)"
    }

    static func lastActionText(for snapshot: MagicEffectControlSnapshot) -> String {
        "Last action: \(snapshot.lastActionText)"
    }

    /// Every line the section shows, in order.
    static func text(for snapshot: MagicEffectControlSnapshot) -> String {
        [
            effectsText(for: snapshot),
            nearestActorEffectsText(for: snapshot),
            activityText(for: snapshot),
            coverageText(for: snapshot),
            lastActionText(for: snapshot)
        ].joined(separator: "\n")
    }
}
