// Animated object state.

import Foundation

/// The readout text of the Animated Objects section.
nonisolated public enum ObjectAnimationReadout {
    public static func text(rows: [ObjectAnimationRow], selected: UInt32?, last: String) -> String {
        guard !rows.isEmpty else { return "No animated objects loaded.\n\(last)" }
        let row = rows.first { $0.reference == selected } ?? rows[0]
        let file = row.project.split(separator: "\\").last.map(String.init) ?? row.project
        return """
        Objects: \(rows.count)
        \(String(format: "%08X", row.reference)) \(file)
        State: \(row.activeState ?? "none")
        Events: \(row.events.joined(separator: ", "))
        \(last)
        """
    }
}
