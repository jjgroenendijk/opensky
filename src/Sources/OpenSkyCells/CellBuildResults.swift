// The results a cell build runner hands back to the main-thread streamer.

public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyTerrain

/// One finished build handed back to the main-thread streamer.
nonisolated public struct CellBuildResult: Sendable {
    public let coordinate: CellCoordinate
    public let result: Result<CellScene, any Error>
    /// The worldspace the build read; nil when the provider has none.
    public let worldspaceEditorID: String?

    public init(
        coordinate: CellCoordinate,
        result: Result<CellScene, any Error>,
        worldspaceEditorID: String? = nil
    ) {
        self.coordinate = coordinate
        self.result = result
        self.worldspaceEditorID = worldspaceEditorID
    }
}

nonisolated public struct CellBuildMetric: Equatable, Sendable {
    public let collisionDurationMS: Double
    let collisionShapeCount: Int
    let collisionTriangleCount: Int
    /// Actor phase accounting mirrored off CellLoadSummary so the fly bench
    /// can gate latency + exact accounting per cell (5.5).
    public var actorDurationMS = 0.0
    public var actorDiscoveredCount = 0
    public var actorRenderedCount = 0
    public var actorDisabledSkipCount = 0
    public var actorFailureCount = 0
    /// One reason per counted failure, mirrored off CellLoadSummary so the
    /// fly bench can prove every failure explained (5.6 acceptance).
    public var actorFailureReasons: [String] = []
    public var actorAnimatedCount = 0
    public var actorAnimationFailureCount = 0
    public var actorAnimationFailureReasons: [String] = []

    public var actorAccountingIsExact: Bool {
        actorDiscoveredCount
            == actorRenderedCount + actorDisabledSkipCount + actorFailureCount
    }

    public var actorFailuresAreExplained: Bool {
        actorFailureCount == actorFailureReasons.count
    }

    public var actorAnimationAccountingIsExact: Bool {
        actorRenderedCount == actorAnimatedCount + actorAnimationFailureCount
    }

    public var actorAnimationFailuresAreExplained: Bool {
        actorAnimationFailureCount == actorAnimationFailureReasons.count
    }
}

nonisolated public struct DistantLODBuildResult: Sendable {
    public let center: CellCoordinate
    public let result: Result<DistantLODScene?, any Error>
    /// The cells the ring leaves out, because full cells draw there.
    public let hiddenCells: Set<CellCoordinate>
    /// The worldspace the ring was built for; nil when the provider has none.
    public var worldspaceEditorID: String?
}

nonisolated public struct DoorTransitionBuildResult: Sendable {
    public let sourceDoor: FormID
    public let result: Result<DoorTransition, any Error>
}
