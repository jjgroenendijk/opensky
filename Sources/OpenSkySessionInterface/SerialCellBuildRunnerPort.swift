public import OpenSkyRendering
public import OpenSkyWorldInterface

/// What the world adapters use of `SerialCellBuildRunner`.
public protocol SerialCellBuildRunnerPort: AnyObject {
    func drainCompletedPlayerRigs() -> [PlayerRigLoadResult<ActorRenderAsset>]
    func enqueuePlayerRig(_ request: PlayerRigRequest)
}
