// Latest-frame renderer accounting used by tests, app inspectors, and
// streaming acceptance gates.

/// Per-frame culling + draw accounting from the most recently encoded frame.
nonisolated struct SceneDrawStats: Equatable {
    var drawCalls = 0
    var drawnInstances = 0
    var culledInstances = 0
}

/// Separates intentional grass policy from ordinary frustum culling.
nonisolated struct GrassDrawStats: Equatable {
    var sceneInstances = 0
    var drawCalls = 0
    var drawnInstances = 0
    var densityCulledInstances = 0
    var distanceCulledInstances = 0
    var frustumCulledInstances = 0
    var budgetDroppedInstances = 0

    mutating func formMaximum(_ other: GrassDrawStats) {
        sceneInstances = max(sceneInstances, other.sceneInstances)
        drawCalls = max(drawCalls, other.drawCalls)
        drawnInstances = max(drawnInstances, other.drawnInstances)
        densityCulledInstances = max(densityCulledInstances, other.densityCulledInstances)
        distanceCulledInstances = max(distanceCulledInstances, other.distanceCulledInstances)
        frustumCulledInstances = max(frustumCulledInstances, other.frustumCulledInstances)
        budgetDroppedInstances = max(budgetDroppedInstances, other.budgetDroppedInstances)
    }
}
