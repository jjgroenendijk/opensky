// The text of the explosion and hazard readout, kept out of the panel so a
// unit test can pin it.

import Foundation
import OpenSkyPhysics

nonisolated public enum ExplosionReadout {
    /// Rows shown per list; the rest are counted.
    public static let listedRows = 6

    public static func text(for snapshot: ExplosionControlSnapshot) -> String {
        var lines = [
            "Detonations: \(snapshot.detonationTotal) · debris \(snapshot.debrisCount)"
                + " · skipped placements \(snapshot.skippedPlacements)"
        ]
        if let last = snapshot.reports.last {
            lines.append(line(last))
        }
        lines.append("Hazards: \(snapshot.hazards.count)")
        lines += snapshot.hazards.prefix(listedRows).map { "  " + line($0) }
        if snapshot.hazards.count > listedRows {
            lines.append("  and \(snapshot.hazards.count - listedRows) more")
        }
        return lines.joined(separator: "\n")
    }

    public static func line(_ report: ExplosionReport) -> String {
        let damage = report.damaged.values.reduce(0, +)
        let modifier = report.imageSpaceStrength.map { ", screen \(number($0))" } ?? ""
        let hazard = report.hazardPlaced ? ", hazard placed" : ""
        return "Last: \(report.name) (\(report.cause.rawValue)),"
            + " \(report.damaged.count) hit for \(number(damage)),"
            + " \(report.soundsPlayed) sounds\(modifier)\(hazard)"
    }

    public static func line(_ row: TrapHazardRow) -> String {
        let lifetime = row.remainingLifetime.map { "\(number($0)) s left" } ?? "stays with cell"
        let position = "at \(Int(row.position.x)) \(Int(row.position.y)) \(Int(row.position.z))"
        return "\(row.name) \(position), \(lifetime), \(row.tickCount) ticks"
    }

    private static func number(_ value: Float) -> String {
        String(format: "%.1f", value)
    }
}
