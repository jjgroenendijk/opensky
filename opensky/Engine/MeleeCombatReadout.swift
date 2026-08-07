// Text for the `World > Player & Locomotion > Melee` readout (issue #195,
// roadmap item 15.4).
//
// Engine-side and AppKit-free, on the `PlayerLocomotionReadout` precedent: the
// panel section owns layout and the wording lives here, so a unit test can
// assert on the sentence a user reads without standing up a window.

import Foundation

nonisolated enum MeleeCombatReadout {
    /// The state line: where the weapon is, where the swing is, and whether
    /// the guard is up.
    static func stateText(for snapshot: MeleeCombatSnapshot) -> String {
        guard snapshot.isAvailable else {
            return "Melee: unavailable (no game data loaded)"
        }
        var parts = [
            "weapon \(snapshot.drawState.rawValue)",
            "attack \(snapshot.attackPhase.rawValue)"
        ]
        if snapshot.isBlocking {
            parts.append("blocking")
        }
        if snapshot.isStaggering {
            parts.append("staggering")
        }
        return "Melee: " + parts.joined(separator: ", ")
    }

    /// The weapon line: what is equipped and how far it reaches.
    static func weaponText(for snapshot: MeleeCombatSnapshot) -> String {
        guard snapshot.isAvailable else { return "Weapon: unavailable" }
        return String(
            format: "Weapon: %@ — damage %.0f, reach x%.2f (%.0f units), speed %.2f",
            snapshot.weaponName,
            snapshot.weaponDamage,
            snapshot.weaponReachMultiplier,
            snapshot.reach,
            snapshot.weaponSpeed
        )
    }

    /// The hands line: what the graph is being told each hand holds, which is
    /// what picks the equip and attack animation sets.
    static func handsText(for snapshot: MeleeCombatSnapshot) -> String {
        guard snapshot.isAvailable else { return "Hands: unavailable" }
        return String(
            format: "Hands: right %@ (%d), left %@ (%d)",
            snapshot.rightHandType.displayName,
            snapshot.rightHandType.rawValue,
            snapshot.leftHandType.displayName,
            snapshot.leftHandType.rawValue
        )
    }

    /// The trace line: the swing and hit counts plus the newest hit, which is
    /// the one a user has just made and wants to read.
    static func traceText(for snapshot: MeleeCombatSnapshot) -> String {
        guard snapshot.isAvailable else { return "Hits: unavailable" }
        let header = "Hits: \(snapshot.hitCount) from \(snapshot.swingCount) contact frames"
        guard let last = snapshot.trace.last else {
            return header + " — no hit yet"
        }
        return header + "\n" + describe(last)
    }

    /// One trace entry as a line.
    static func describe(_ hit: MeleeHitReadout) -> String {
        var line = String(
            format: "%@ at %.0f units: %.1f damage",
            hit.target,
            hit.distance,
            hit.appliedDamage
        )
        if hit.blockedPercent > 0 {
            line += String(
                format: " (blocked %.0f%% of %.1f)", hit.blockedPercent, hit.baseDamage
            )
        }
        if hit.staggered {
            line += ", staggered"
        }
        line += hit.sound.map { ", \($0)" } ?? ", silent"
        return line
    }

    /// The GMST line: every combat setting with its value and its source, so a
    /// surprising reach or block number can be traced to the plugin that set
    /// it rather than guessed at.
    static func settingsText(for snapshot: MeleeCombatSnapshot) -> String {
        guard snapshot.isAvailable, !snapshot.settings.isEmpty else {
            return "Settings: unavailable"
        }
        return "Settings: " + snapshot.settings.joined(separator: "\n")
    }
}
