import Foundation
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// A reference's current state and the cell that draws it.
public struct ReferencePlacement {
    public let state: ReferenceState
    public let location: CellSceneLocation?
    /// The editor ID of the worldspace of an exterior `location`; nil for an interior.
    public let worldspace: String?

    public init(
        state: ReferenceState,
        location: CellSceneLocation?,
        worldspace: String? = nil
    ) {
        self.state = state
        self.location = location
        self.worldspace = worldspace
    }
}
