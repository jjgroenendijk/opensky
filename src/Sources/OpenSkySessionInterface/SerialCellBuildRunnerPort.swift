public import OpenSkyRendering
public import OpenSkyRenderResources
public import OpenSkyWorldInterface

/// What the world adapters use of `SerialCellBuildRunner`.
public protocol SerialCellBuildRunnerPort: AnyObject {
    func drainCompletedPlayerRigs() -> [PlayerRigLoadResult<ActorRenderAsset, FaceMorphBuffer>]
    func enqueuePlayerRig(_ request: PlayerRigRequest)
}
