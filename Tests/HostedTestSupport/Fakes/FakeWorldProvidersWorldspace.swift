// `FakeWorldProviders`' worldspace seam: two worldspaces and the jumps kept.

import AppKit
import OpenSkyFormatsCore
@testable import OpenSkyGameData

extension FakeWorldProviders {
    var currentWorldspace: String? {
        "Tamriel"
    }

    var worldspacePlayerCell: CellSceneLocation? {
        .exterior(CellCoordinate(x: 6, y: -2))
    }

    var worldspaceNames: [String] {
        ["DLC2SolstheimWorld", "Tamriel"]
    }

    func goToExterior(worldspace: String, x: Int32, y: Int32) {
        menuCalls.calls.append("worldspace.go(\(worldspace), \(x), \(y))")
    }
}
