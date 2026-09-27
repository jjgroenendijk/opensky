// Spellcasting readout lines (issue #470, roadmap item 19.7), formatted here
// rather than in the panel section for the reason `MagicEffectControlReadout` is:
// a string a milestone gate asserts on belongs in the engine target, where a
// unit test can reach it without a window.
//
// Documented in docs/engine/magic.md.

import Foundation

nonisolated enum CastingControlReadout {
    /// The player's known spells, one line per spell, or the honest absence of
    /// any.
    static func spellsText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Known spells: unavailable" }
        guard !snapshot.knownSpells.isEmpty else {
            return "Known spells: none — Learn start spells grants the flagged ones"
        }
        let lines = snapshot.knownSpells.map { "  \($0.line)" }.joined(separator: "\n")
        return "Known spells (\(snapshot.knownSpells.count)):\n\(lines)"
    }

    /// What the hands are doing and what is left to pay for it.
    static func handsText(for snapshot: CastingControlSnapshot) -> String {
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
    static func tomesText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Tomes: unavailable" }
        let carried = snapshot.carriedTomeNames.isEmpty
            ? "none carried"
            : snapshot.carriedTomeNames.joined(separator: ", ")
        return "Tomes: \(carried) — \(snapshot.readBookCount) book(s) already read"
    }

    /// What the cast loop has done this session.
    static func activityText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Casts: unavailable" }
        return "Casts: \(snapshot.castCount) completed, "
            + "\(snapshot.concentrationSeconds) second(s) maintained"
    }

    /// What it declined to do, which is the point of the tally: unimplemented
    /// ground is measured rather than silent.
    static func coverageText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Coverage: unavailable" }
        var text = if snapshot.failureCount > 0 {
            "Coverage: \(snapshot.failureCount) refusal(s) — "
                + snapshot.failureLines.joined(separator: ", ")
        } else {
            "Coverage: no cast was refused"
        }
        if snapshot.unheldAbilityEntries > 0 {
            text += "; \(snapshot.unheldAbilityEntries) ability entr(ies) carry no duration "
                + "and are counted rather than held"
        }
        return text
    }

    /// Aimed delivery: what left the caster, and what the last landed spell's
    /// resistances did to it (issue #471).
    ///
    /// The adjustment lines are the readout the resistance rule is verified
    /// through, in the app and in the panel test alike — a health bar moving is
    /// not evidence that the multiplier was the documented one.
    static func deliveryText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Delivery: unavailable" }
        let deliveries = snapshot.deliveryLines.isEmpty
            ? "nothing cast yet"
            : snapshot.deliveryLines.joined(separator: ", ")
        var text = "Delivery: \(snapshot.projectileCount) projectile(s) — \(deliveries)"
        guard snapshot.lastHitTargets > 0 else {
            return text + "; no spell has landed on anybody yet"
        }
        text += "; last hit reached \(snapshot.lastHitTargets) actor(s)"
        guard !snapshot.lastHitAdjustments.isEmpty else {
            return text + " with nothing hostile to resist"
        }
        let lines = snapshot.lastHitAdjustments.map { "  \($0)" }.joined(separator: "\n")
        return text + "\n\(lines)"
    }

    /// What the magic condition functions say about the player right now
    /// (issue #474), which is what makes the registrations verifiable from the
    /// app rather than only from a test.
    static func conditionsText(for snapshot: CastingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Conditions: unavailable" }
        guard !snapshot.conditionLines.isEmpty else {
            return "Conditions: no magic condition function could be evaluated"
        }
        let lines = snapshot.conditionLines.map { "  \($0)" }.joined(separator: "\n")
        return "Conditions (player):\n\(lines)"
    }

    static func lastActionText(for snapshot: CastingControlSnapshot) -> String {
        "Last action: \(snapshot.lastActionText)"
    }

    /// Every line the section shows, in order.
    static func text(for snapshot: CastingControlSnapshot) -> String {
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
