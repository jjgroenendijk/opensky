// Text for the `World > Player & Locomotion > Archery` readout (issue #196,
// roadmap item 15.5).
//
// Engine-side and AppKit-free, on the `MeleeCombatReadout` precedent: the panel
// section owns layout and the wording lives here, so a unit test can assert on
// the sentence a user reads without standing up a window.

import Foundation

nonisolated enum ArcheryReadout {
    /// The state line: where the shot is, whether an arrow is nocked, and how
    /// long the draw has been held.
    static func stateText(for snapshot: ArcherySnapshot) -> String {
        guard snapshot.isAvailable else {
            return "Archery: unavailable (no game data loaded)"
        }
        var parts = ["shot \(snapshot.phase.rawValue)"]
        if snapshot.hasArrowAttached {
            parts.append("arrow nocked")
        }
        if snapshot.phase.isDrawing {
            parts.append(
                String(
                    format: "held %.2fs (%.0f%% damage)",
                    snapshot.heldSeconds,
                    snapshot.drawFraction * 100
                )
            )
        }
        return "Archery: " + parts.joined(separator: ", ")
    }

    /// The equipment line: the bow, the arrow, and the flight the PROJ gives.
    static func equipmentText(for snapshot: ArcherySnapshot) -> String {
        guard snapshot.isAvailable else { return "Bow: unavailable" }
        return String(
            format: "Bow: %@ — damage %.0f, speed %.2f\nArrow: %@ — damage %.0f",
            snapshot.bowName,
            snapshot.bowDamage,
            snapshot.bowSpeed,
            snapshot.arrowName,
            snapshot.arrowDamage
        )
    }

    /// The flight line: the PROJ numbers a shot inherits.
    static func flightText(for snapshot: ArcherySnapshot) -> String {
        guard snapshot.isAvailable else { return "Projectile: unavailable" }
        return String(
            format: "Projectile: %@ — speed %.0f, gravity x%.3f, range %.0f",
            snapshot.projectileName,
            snapshot.projectileSpeed,
            snapshot.projectileGravityFactor,
            snapshot.projectileRange
        )
    }

    /// The trace line: the counts plus the newest finished shot, which is the
    /// one a user has just taken and wants to read.
    static func traceText(for snapshot: ArcherySnapshot) -> String {
        guard snapshot.isAvailable else { return "Shots: unavailable" }
        let header = String(
            format: "Shots: %d fired, %d impacts, %d in flight, %d stuck",
            snapshot.firedCount,
            snapshot.impactCount,
            snapshot.liveCount,
            snapshot.stuckCount
        )
        guard let last = snapshot.trace.last else {
            return header + " — no shot yet"
        }
        return header + "\n" + describe(last)
    }

    /// One trace entry as a line: spawn point, impact point, flight time.
    static func describe(_ shot: ProjectileTraceReadout) -> String {
        var line = String(
            format: "#%d %@: %@ -> %@ in %.2fs, %.0f units, drop %.0f",
            shot.id,
            shot.outcome.rawValue,
            point(shot.launch),
            point(shot.end),
            shot.flightTime,
            shot.travelled,
            shot.drop
        )
        if let target = shot.target {
            line += String(format: ", %@ took %.1f", target, shot.appliedDamage)
        }
        if shot.stuck {
            line += ", stuck"
        }
        line += shot.sound.map { ", \($0)" } ?? ", silent"
        return line
    }

    /// The GMST line: every archery setting with its value and its source, so
    /// a surprising trajectory can be traced to the plugin that set it rather
    /// than guessed at.
    static func settingsText(for snapshot: ArcherySnapshot) -> String {
        guard snapshot.isAvailable, !snapshot.settings.isEmpty else {
            return "Settings: unavailable"
        }
        return "Settings: " + snapshot.settings.joined(separator: "\n")
    }

    /// One world position, rounded — a trajectory readout wants to be read,
    /// not to carry seven significant figures.
    static func point(_ value: SIMD3<Float>) -> String {
        String(format: "(%.0f, %.0f, %.0f)", value.x, value.y, value.z)
    }
}
