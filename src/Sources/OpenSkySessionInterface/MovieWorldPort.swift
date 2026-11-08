public import OpenSkyScriptingInterface

/// What the world adapters use of `MovieWorldAdapter`.
public protocol MovieWorldPort: AnyObject {
    func playBink(_ request: PapyrusBinkRequest, waitToken token: UInt64) -> Bool
}
