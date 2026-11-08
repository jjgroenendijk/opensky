public import OpenSkyGameData

/// What the world adapters use of `CellResetCoordinator`.
public protocol CellResetPort: AnyObject {
    func flagForReset(_ location: CellSceneLocation)
}
