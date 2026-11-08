// Where each resident reference is, for the conditions that read a reference's
// location, interior flag, or cell.

import OpenSkyCells
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldInterface
import OpenSkyWorldState

extension CellStreamer {
    /// `location` names a cell's location; nil leaves the cell's references out.
    public func residentReferencePlaces(
        location: (CellLocationKey) -> ResolvedFormID?
    ) -> ReferencePlaces {
        var places = ReferencePlaces()
        for scene in residentScenes {
            let cell = scene.referenceCell
            let place = location(scene.locationKey)
            for entry in scene.references.sortedEntries() {
                places.locations[entry.key] = place
                places.interiors[entry.key] = scene.isInterior
                places.cells[entry.key] = cell
            }
        }
        return places
    }
}
