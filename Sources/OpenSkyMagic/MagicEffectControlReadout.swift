// Active-effect readout lines, formatted in the engine target so a unit test can check
// them without a window. See docs/engine/magic.md.

import Foundation
import OpenSkyMagicInterface

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

    /// What the player's and the nearest actor's effects force on them.
    public static func influenceText(for snapshot: MagicEffectControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Forced behaviour: unavailable" }
        let player = words(of: snapshot.playerInfluence)
        let nearest = snapshot.nearestActorName.map { name in
            "; \(name): " + words(of: snapshot.nearestActorInfluence)
        } ?? ""
        return "Forced behaviour: player: \(player)\(nearest)"
    }

    /// The influence as words, such as "calmed, paralysed", or "none".
    public static func words(of influence: ActorMagicInfluence) -> String {
        let flags: [(Bool, String)] = [
            (influence.isCalmed, "calmed"), (influence.isFrenzied, "frenzied"),
            (influence.isFrightened, "frightened"), (influence.isRallied, "rallied"),
            (influence.isParalysed, "paralysed"), (influence.isEthereal, "ethereal")
        ]
        let set = flags.filter(\.0).map(\.1)
        return set.isEmpty ? "none" : set.joined(separator: ", ")
    }

    /// The holds and lights the world archetypes keep running.
    public static func worldEffectsText(for snapshot: MagicEffectControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "World effects: unavailable" }
        guard !snapshot.worldEffectLines.isEmpty else { return "World effects: none running" }
        let lines = snapshot.worldEffectLines.map { "  \($0)" }.joined(separator: "\n")
        return "World effects (\(snapshot.worldEffectLines.count)):\n\(lines)"
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
        guard snapshot.isAvailable else { return "Not supported: unavailable" }
        guard snapshot.skippedCount > 0 else {
            return "Not supported: none"
        }
        let unimplemented = snapshot.unimplementedLines.isEmpty
            ? "none named"
            : snapshot.unimplementedLines.joined(separator: ", ")
        return "Not supported: \(snapshot.skippedCount) effect(s) skipped — \(unimplemented)"
    }

    public static func lastActionText(for snapshot: MagicEffectControlSnapshot) -> String {
        "Last action: \(snapshot.lastActionText)"
    }

    /// Every line the section shows, in order.
    public static func text(for snapshot: MagicEffectControlSnapshot) -> String {
        [
            effectsText(for: snapshot),
            nearestActorEffectsText(for: snapshot),
            influenceText(for: snapshot),
            worldEffectsText(for: snapshot),
            activityText(for: snapshot),
            coverageText(for: snapshot),
            lastActionText(for: snapshot)
        ].joined(separator: "\n")
    }
}
