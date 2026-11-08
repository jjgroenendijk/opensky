import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyTerrain
public import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

nonisolated extension PlacedRecordLookup {
    /// The cell that draws `entry` from its plugin position: its interior, or
    /// the exterior cell its position falls in.
    public func home(of entry: RuntimeReferenceEntry) -> CellSceneLocation? {
        if let interior = interiorCell(holding: entry.formID) {
            return .interior(interior)
        }
        let position = entry.placedReference?.placement.position
            ?? entry.placedActor?.placement.position
        return position.map { .exterior(CellGridManager.cellCoordinate(for: $0)) }
    }
}
