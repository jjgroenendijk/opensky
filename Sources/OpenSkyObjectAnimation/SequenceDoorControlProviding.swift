// Main-app seam for the World > Animated Doors section.

import Foundation

public protocol SequenceDoorControlProviding: AnyObject {
    var sequenceDoorRows: [SequenceDoorRow] { get }
    /// Writes the door's open state, as `SetOpen` does. False when the door is not loaded.
    func setSequenceDoorOpen(_ open: Bool, reference: UInt32) -> Bool
}

/// The readout text of the Animated Doors section.
nonisolated public enum SequenceDoorReadout {
    public static func text(rows: [SequenceDoorRow], selected: UInt32?, last: String) -> String {
        guard !rows.isEmpty else { return "Doors: none\n\(last)" }
        let row = rows.first { $0.reference == selected } ?? rows[0]
        return """
        Doors: \(rows.count)
        \(title(row))
        State: \(phaseName(row.phase))
        \(last)
        """
    }

    public static func title(_ row: SequenceDoorRow) -> String {
        let file = row.modelPath.split(separator: "\\").last.map(String.init) ?? row.modelPath
        return String(format: "%08X ", row.reference) + file
    }

    public static func phaseName(_ phase: SequenceDoorMotion.Phase) -> String {
        switch phase {
        case .open: "open"
        case .opening: "opening"
        case .closed: "closed"
        case .closing: "closing"
        }
    }
}
