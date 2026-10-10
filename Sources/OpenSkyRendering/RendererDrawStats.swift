// Latest-frame renderer accounting used by tests, app inspectors, and
// streaming acceptance gates.

/// Per-frame culling + draw accounting from the most recently encoded frame.
nonisolated public struct SceneDrawStats: Equatable, Sendable {
    public var drawCalls = 0
    public var drawnInstances = 0
    public var culledInstances = 0
    /// Instances in a room the camera cannot see, inside `culledInstances`.
    public var roomCulledInstances = 0

    public init(
        drawCalls: Int = 0,
        drawnInstances: Int = 0,
        culledInstances: Int = 0,
        roomCulledInstances: Int = 0
    ) {
        self.drawCalls = drawCalls
        self.drawnInstances = drawnInstances
        self.culledInstances = culledInstances
        self.roomCulledInstances = roomCulledInstances
    }
}

/// Separates intentional grass policy from ordinary frustum culling.
nonisolated public struct GrassDrawStats: Equatable, Sendable {
    public var sceneInstances = 0
    public var drawCalls = 0
    public var drawnInstances = 0
    public var densityCulledInstances = 0
    public var distanceCulledInstances = 0
    public var frustumCulledInstances = 0
    public var budgetDroppedInstances = 0

    public mutating func formMaximum(_ other: GrassDrawStats) {
        sceneInstances = max(sceneInstances, other.sceneInstances)
        drawCalls = max(drawCalls, other.drawCalls)
        drawnInstances = max(drawnInstances, other.drawnInstances)
        densityCulledInstances = max(densityCulledInstances, other.densityCulledInstances)
        distanceCulledInstances = max(distanceCulledInstances, other.distanceCulledInstances)
        frustumCulledInstances = max(frustumCulledInstances, other.frustumCulledInstances)
        budgetDroppedInstances = max(budgetDroppedInstances, other.budgetDroppedInstances)
    }

    public init(
        sceneInstances: Int = 0,
        drawCalls: Int = 0,
        drawnInstances: Int = 0,
        densityCulledInstances: Int = 0,
        distanceCulledInstances: Int = 0,
        frustumCulledInstances: Int = 0,
        budgetDroppedInstances: Int = 0
    ) {
        self.sceneInstances = sceneInstances
        self.drawCalls = drawCalls
        self.drawnInstances = drawnInstances
        self.densityCulledInstances = densityCulledInstances
        self.distanceCulledInstances = distanceCulledInstances
        self.frustumCulledInstances = frustumCulledInstances
        self.budgetDroppedInstances = budgetDroppedInstances
    }
}
