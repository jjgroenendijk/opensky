import Foundation
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// A reference's current state and the cell that draws it.
public struct ReferencePlacement {
    public let state: ReferenceState
    public let location: CellSceneLocation?

    public init(
        state: ReferenceState,
        location: CellSceneLocation?
    ) {
        self.state = state
        self.location = location
    }
}
