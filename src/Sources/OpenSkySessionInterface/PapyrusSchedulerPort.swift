public import OpenSkyScriptingInterface

/// What the world adapters use of `PapyrusScheduler`.
public protocol PapyrusSchedulerPort: AnyObject {
    @discardableResult func answer(_ token: UInt64, returning value: PapyrusValue) -> Bool
}
