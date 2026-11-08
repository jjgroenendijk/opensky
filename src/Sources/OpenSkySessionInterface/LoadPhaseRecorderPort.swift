public import OpenSkyGameData

/// What the world adapters use of `LoadPhaseRecorder`.
public protocol LoadPhaseRecorderPort: AnyObject {
    func reset()
    func snapshot() -> LoadPhaseTimes
}
