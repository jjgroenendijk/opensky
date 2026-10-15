// The regions the player stands in, for conditions that ask about them.

import OpenSkyFormatsESM

extension CellStreamer {
    /// The REGN records over the exterior cell at the grid centre; empty indoors.
    public var playerRegions: [FormID] {
        guard interiorScene == nil else { return [] }
        return composition.cells[grid.center]?.regions ?? []
    }
}
