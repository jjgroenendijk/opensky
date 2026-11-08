// Narrow live-renderer seams consumed by agent control and the
// frame HUD. No AppKit here on purpose: the file compiles into both the app and
// the CLI target, so a protocol added here needs no project-membership change.

import Foundation
import OpenSkyGameData

/// Per-frame scene accounting plus the streaming and memory numbers that answer
/// "is this frame slow because of what is resident?".
nonisolated public struct SceneStatsSnapshot: Equatable, Sendable {
    public let drawCalls: Int
    public let drawnInstances: Int
    public let culledInstances: Int
    public let residentCellCount: Int
    /// Process physical footprint, or nil when the mach call fails.
    public let memoryFootprintMB: Double?

    public init(
        drawCalls: Int,
        drawnInstances: Int,
        culledInstances: Int,
        residentCellCount: Int,
        memoryFootprintMB: Double?
    ) {
        self.drawCalls = drawCalls
        self.drawnInstances = drawnInstances
        self.culledInstances = culledInstances
        self.residentCellCount = residentCellCount
        self.memoryFootprintMB = memoryFootprintMB
    }
}
