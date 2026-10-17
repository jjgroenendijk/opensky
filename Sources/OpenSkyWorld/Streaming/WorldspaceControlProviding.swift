// Main-app seam for the World > Worldspace section.

import OpenSkyFormatsCore
import OpenSkyGameData

public protocol WorldspaceControlProviding: AnyObject {
    /// The exterior worldspace that streams; nil before the world loads.
    var currentWorldspace: String? { get }
    var worldspacePlayerCell: CellSceneLocation? { get }
    /// Every worldspace editor ID in the load order, sorted.
    var worldspaceNames: [String] { get }
    /// Moves the player to the exterior cell, as `debug.teleport` does.
    func goToExterior(worldspace: String, x: Int32, y: Int32)
}

/// The readout text of the Worldspace section.
nonisolated public enum WorldspaceReadout {
    public static func text(worldspace: String?, cell: CellSceneLocation?, last: String) -> String {
        let place = switch cell {
        case let .exterior(grid)?: "\(grid.x), \(grid.y)"
        case .interior?: "interior"
        case nil: "none"
        }
        return """
        Worldspace: \(worldspace ?? "none")
        Cell: \(place)
        \(last)
        """
    }
}
