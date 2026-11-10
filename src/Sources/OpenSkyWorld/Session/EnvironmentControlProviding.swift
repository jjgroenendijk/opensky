// Narrow live-renderer seams consumed by agent control and the
// frame HUD. No AppKit here on purpose: the file compiles into both the app and
// the CLI target, so a protocol added here needs no project-membership change.

import Foundation
import OpenSkyGameData

/// Per-frame scene accounting plus the streaming and memory numbers that answer
/// "is this frame slow because of what is resident?".
nonisolated struct SceneStatsSnapshot: Equatable, Sendable {
    let drawCalls: Int
    let drawnInstances: Int
    let culledInstances: Int
    let residentCellCount: Int
    /// Process physical footprint, or nil when the mach call fails.
    let memoryFootprintMB: Double?
}
