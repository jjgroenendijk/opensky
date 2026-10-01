// The seam for `World > Render Debug`: the debug channel and the layer mask, without
// `Renderer`. The readout shows a draw-call delta, which proves a hidden layer is gone.

nonisolated public struct RenderDebugControlSnapshot: Equatable, Sendable {
    public let mode: RenderDebugMode
    /// The mask the user set.
    public let layers: RenderLayer
    /// The mask after the subsystem enables were folded in
    /// (`RenderLayerPolicy`). Differs from `layers` when a layer is checked
    /// here but switched off by its own panel section.
    public let effectiveLayers: RenderLayer
    public let stats: SceneDrawStats
    public let shadowStats: ShadowDrawStats

    public init(
        mode: RenderDebugMode,
        layers: RenderLayer,
        effectiveLayers: RenderLayer,
        stats: SceneDrawStats,
        shadowStats: ShadowDrawStats
    ) {
        self.mode = mode
        self.layers = layers
        self.effectiveLayers = effectiveLayers
        self.stats = stats
        self.shadowStats = shadowStats
    }
}

@MainActor
public protocol RenderDebugControlProviding: AnyObject {
    var renderDebugMode: RenderDebugMode { get set }
    var renderDebugLayers: RenderLayer { get set }
    var renderDebugSnapshot: RenderDebugControlSnapshot { get }
}

/// Readout text for the Render Debug section, kept apart from AppKit so the
/// wording is unit-testable.
nonisolated public enum RenderDebugReadout: Sendable {
    public static func modeText(for snapshot: RenderDebugControlSnapshot) -> String {
        "View: \(snapshot.mode.title)"
    }

    /// Names the isolated layer when there is one, otherwise lists what is
    /// hidden — "all layers" is the answer a default session should read.
    public static func layerText(for snapshot: RenderDebugControlSnapshot) -> String {
        if let soloed = snapshot.layers.soloedLayer {
            return "Layers: solo \(soloed.title)"
        }
        let hidden = RenderLayer.ordered.filter { !snapshot.layers.contains($0) }
        guard !hidden.isEmpty else { return "Layers: all layers" }
        return "Layers: hiding " + hidden.map(\.title).joined(separator: ", ")
    }

    /// Layers the mask allows but a subsystem enable has switched off anyway.
    public static func suppressedText(for snapshot: RenderDebugControlSnapshot) -> String? {
        let suppressed = RenderLayer.ordered.filter {
            snapshot.layers.contains($0) && !snapshot.effectiveLayers.contains($0)
        }
        guard !suppressed.isEmpty else { return nil }
        return "Also off by their own controls: "
            + suppressed.map(\.title).joined(separator: ", ")
    }

    public static func drawText(for snapshot: RenderDebugControlSnapshot) -> String {
        """
        Scene: \(snapshot.stats.drawCalls) draws, \
        \(snapshot.stats.drawnInstances) instances
        Shadow: \(snapshot.shadowStats.drawCalls) draws, \
        \(snapshot.shadowStats.drawnInstances) casters
        """
    }

    public static func text(for snapshot: RenderDebugControlSnapshot) -> String {
        [
            modeText(for: snapshot),
            layerText(for: snapshot),
            suppressedText(for: snapshot),
            drawText(for: snapshot)
        ].compactMap(\.self).joined(separator: "\n")
    }
}
