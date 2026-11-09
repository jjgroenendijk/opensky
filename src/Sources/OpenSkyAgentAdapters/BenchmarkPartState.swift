public import OpenSkyGameData
public import OpenSkySessionInterface
public import OpenSkyWorld
public import OpenSkyWorldInterface

/// What `BenchmarkWorldAdapter` and its tour settings part share during a tour.
public final class BenchmarkPartState {
    public var view: (any BenchmarkViewPort)?
    public var arrival: (any AgentTeleportJobPort)?
    public var saved: BenchmarkWorldAdapter.SavedState?
    public var request = BenchmarkRequest()
    public var tourOverrides: [PlayerSettingID: Double] = [:]
    /// Set by the owner, which waits for the tour's last screenshots.
    public var finishAfterScreenshots: (BenchmarkTourResult) -> Void = { _ in }

    public init() {}
}
