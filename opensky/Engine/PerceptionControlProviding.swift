// Narrow provider seam for the M16 acceptance panel (issue #202, roadmap item
// 16.6, scope point 7). This issue supplies the readout and the settings
// provenance; issue #203 adds the controls that show them, without the shell
// ever seeing `PerceptionRuntime` or `CellStreamer`.
//
// The same shape as `AIOverlayControlProviding` next door, and for the same
// reason: a panel that could reach the runtime could also drive it, and a panel
// driving a fixed-step simulation is how a readout stops matching the world it
// describes.

/// One resolved detection setting as a panel shows it: the name it is addressed
/// by, its value, and where that value came from.
nonisolated struct DetectionSettingReadout: Equatable {
    let editorID: String
    let value: Float
    /// The winning plugin, the documented fallback, or "OpenSky constant" for a
    /// number no record states. The whole point of the row.
    let source: String
}

nonisolated struct PerceptionControlSnapshot: Equatable {
    /// Every tracked pair, the roster sizes, and what the caps dropped.
    let readout: PerceptionReadout
    /// Every resolved setting beside its provenance, in formula order.
    let settings: [DetectionSettingReadout]

    static let unavailable = PerceptionControlSnapshot(readout: .empty, settings: [])

    /// True when no perception runtime is attached, which is every synthetic
    /// scene. The panel reports that rather than showing a convincing zero.
    var isUnavailable: Bool {
        settings.isEmpty
    }
}

@MainActor
protocol PerceptionControlProviding: AnyObject {
    var perceptionSnapshot: PerceptionControlSnapshot { get }

    /// The `DetectionStatsLabel` lines for one actor: every pair it observes or
    /// is observed in. Empty when nothing watches it.
    func perceptionLines(for actor: ReferenceKey) -> [String]
}
