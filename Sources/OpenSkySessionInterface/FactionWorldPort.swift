public import OpenSkyScriptingInterface

/// What the world adapters use of `FactionWorldAdapter`.
public protocol FactionWorldPort: AnyObject {
    func papyrusNatives() -> PapyrusFactionNatives
}
