import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyRenderCore
public import OpenSkySessionInterface
public import OpenSkyWorld
public import OpenSkyWorldInterface

/// What `BenchmarkWorldAdapter` and its tour settings part share during a tour.
public final class BenchmarkPartState {
    public var view: (any BenchmarkViewPort)?
    public var arrival: (any AgentTeleportJobPort)?
    public var saved: BenchmarkSavedState?
    public var request = BenchmarkRequest()
    public var tourOverrides: [PlayerSettingID: Double] = [:]
    /// Set by the owner, which waits for the tour's last screenshots.
    public var finishAfterScreenshots: (BenchmarkTourResult) -> Void = { _ in }

    public init() {}
}

public struct BenchmarkSavedState {
    let movementMode: CameraMovementMode
    let wasFrozen: Bool
    let hudEnabled: Bool
    let camera: FreeFlyCamera
    let forcedWeather: FormID?
    let outputMuted: Bool
}
