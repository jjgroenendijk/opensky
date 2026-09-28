// Narrow provider seam for the M16 acceptance panel. Issue #422 supplies the
// renderer toggles and readout; issue #203 adds the actual controls without
// exposing Renderer or CellStreamer to the shell.

nonisolated public struct AIOverlayControlSnapshot: Equatable, Sendable {
    public let navmeshOverlayEnabled: Bool
    public let pathOverlayEnabled: Bool
    public let detectionOverlayEnabled: Bool
    public let stats: WorldOverlayDrawStats

    public init(
        navmeshOverlayEnabled: Bool,
        pathOverlayEnabled: Bool,
        detectionOverlayEnabled: Bool,
        stats: WorldOverlayDrawStats
    ) {
        self.navmeshOverlayEnabled = navmeshOverlayEnabled
        self.pathOverlayEnabled = pathOverlayEnabled
        self.detectionOverlayEnabled = detectionOverlayEnabled
        self.stats = stats
    }
}

@MainActor
public protocol AIOverlayControlProviding: AnyObject {
    var navmeshOverlayEnabled: Bool { get set }
    var pathOverlayEnabled: Bool { get set }
    var detectionOverlayEnabled: Bool { get set }
    var aiOverlaySnapshot: AIOverlayControlSnapshot { get }
}
