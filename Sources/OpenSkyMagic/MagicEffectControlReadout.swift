// Active-effect readout lines, formatted in the engine target so a unit test can check
// them without a window. See docs/engine/magic.md.

import Foundation

nonisolated public enum MagicEffectControlReadout: Sendable {
    /// The player's effect list, one line per effect, or the honest absence of
    /// one.
    public static func effectsText(for snapshot: MagicEffectControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Player effects: unavailable" }
        guard !snapshot.playerEffects.isEmpty else {
            return "Player effects: none running"
        }
        let lines = snapshot.playerEffects.map { "  \($0.line)" }.joined(separator: "\n")
        return "Player effects (\(snapshot.playerEffects.count)):\n\(lines)"
    }

    /// The nearest actor's effect list, the actor the resistances above describe. "no
    /// actor resident" and "nothing running" read differently.
    public static func nearestActorEffectsText(for snapshot: MagicEffectControlSnapshot) -> String {
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
    public static func activityText(for snapshot: MagicEffectControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Applied: unavailable" }
        return "Applied: \(snapshot.appliedCount) timed, \(snapshot.instantCount) instant — "
            + "\(snapshot.expiredCount) expired, \(snapshot.dispelledCount) dispelled, "
            + "\(snapshot.runtimeActorCount) actor(s) carrying effects"
    }

    /// What it declined to do, which is the point of the tally: unimplemented
    /// ground is measured rather than silent.
    public static func coverageText(for snapshot: MagicEffectControlSnapshot) -> String {
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

    public static func lastActionText(for snapshot: MagicEffectControlSnapshot) -> String {
        "Last action: \(snapshot.lastActionText)"
    }

    /// Every line the section shows, in order.
    public static func text(for snapshot: MagicEffectControlSnapshot) -> String {
        [
            effectsText(for: snapshot),
            nearestActorEffectsText(for: snapshot),
            activityText(for: snapshot),
            coverageText(for: snapshot),
            lastActionText(for: snapshot)
        ].joined(separator: "\n")
    }
}
