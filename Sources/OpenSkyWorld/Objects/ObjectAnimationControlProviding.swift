// Main-app seam for the World > Animated Objects section.

import Foundation

public protocol ObjectAnimationControlProviding: AnyObject {
    /// Off holds every object in its current pose. Persisted.
    var objectAnimationEnabled: Bool { get set }
    var objectAnimationRows: [ObjectAnimationRow] { get }
    /// Raises `event` on one object's graph. False when the graph has no such event.
    func sendObjectAnimationEvent(_ event: String, to reference: UInt32) -> Bool
}

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

    public static func title(_ row: ObjectAnimationRow) -> String {
        let file = row.project.split(separator: "\\").last.map(String.init) ?? row.project
        return String(format: "%08X ", row.reference) + file
    }
}
