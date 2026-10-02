// Spellcasting readout lines, formatted in the engine target so a unit test can check
// them without a window. See docs/engine/spellcasting.md.

import Foundation

nonisolated public enum CastingControlReadout: Sendable {
    /// The player's known spells, one line per spell, or the honest absence of
    /// any.
    public static func spellsText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Known spells: unavailable" }
        guard !snapshot.knownSpells.isEmpty else {
            return "Known spells: none"
        }
        let lines = snapshot.knownSpells.map { "  \($0.line)" }.joined(separator: "\n")
        return "Known spells (\(snapshot.knownSpells.count)):\n\(lines)"
    }

    /// What the hands are doing and what is left to pay for it.
    public static func handsText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Hands: unavailable" }
        return String(
            format: "Hands: left %@, right %@ — magicka %.0f / %.0f, selected %@",
            snapshot.leftPhase.rawValue,
            snapshot.rightPhase.rawValue,
            snapshot.magicka,
            snapshot.maximumMagicka,
            snapshot.selectedSpellName ?? "none"
        )
    }

    /// The tome side: what is carried and how many books have been opened.
    public static func tomesText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Tomes: unavailable" }
        let carried = snapshot.carriedTomeNames.isEmpty
            ? "none carried"
            : snapshot.carriedTomeNames.joined(separator: ", ")
        return "Tomes: \(carried) · \(snapshot.readBookCount) read"
    }

    /// What the cast loop has done this session.
    public static func activityText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Casts: unavailable" }
        return "Casts: \(snapshot.castCount) completed, "
            + "\(snapshot.concentrationSeconds) second(s) maintained"
    }

    /// What it declined to do, which is the point of the tally: unimplemented
    /// ground is measured rather than silent.
    public static func coverageText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Refused casts: unavailable" }
        var text = if snapshot.failureCount > 0 {
            "Refused casts: \(snapshot.failureCount) — "
                + snapshot.failureLines.joined(separator: ", ")
        } else {
            "Refused casts: none"
        }
        if snapshot.unheldAbilityEntries > 0 {
            text += "; \(snapshot.unheldAbilityEntries) permanent ability effect(s) skipped"
        }
        return text
    }

    /// Aimed delivery: what left the caster, and how resistances changed the last landed
    /// spell. These lines verify the resistance rule; a moving bar does not.
    public static func deliveryText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Delivery: unavailable" }
        let deliveries = snapshot.deliveryLines.isEmpty
            ? "nothing cast yet"
            : snapshot.deliveryLines.joined(separator: ", ")
        var text = "Delivery: \(snapshot.projectileCount) projectile(s) — \(deliveries)"
        guard snapshot.lastHitTargets > 0 else {
            return text + "; no hits yet"
        }
        text += "; last hit reached \(snapshot.lastHitTargets) actor(s)"
        guard !snapshot.lastHitAdjustments.isEmpty else {
            return text + ", nothing resisted"
        }
        let lines = snapshot.lastHitAdjustments.map { "  \($0)" }.joined(separator: "\n")
        return text + "\n\(lines)"
    }

    /// What the magic condition functions say about the player now, so the app can
    /// verify them.
    public static func conditionsText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Conditions: unavailable" }
        guard !snapshot.conditionLines.isEmpty else {
            return "Conditions: none"
        }
        let lines = snapshot.conditionLines.map { "  \($0)" }.joined(separator: "\n")
        return "Conditions (player):\n\(lines)"
    }

    public static func lastActionText(for snapshot: CastingControlSnapshot) -> String {
        "Last action: \(snapshot.lastActionText)"
    }

    /// Every line the section shows, in order.
    public static func text(for snapshot: CastingControlSnapshot) -> String {
        [
            spellsText(for: snapshot),
            handsText(for: snapshot),
            tomesText(for: snapshot),
            activityText(for: snapshot),
            coverageText(for: snapshot),
            deliveryText(for: snapshot),
            conditionsText(for: snapshot),
            lastActionText(for: snapshot)
        ].joined(separator: "\n")
    }
}
