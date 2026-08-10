// Narrow provider seam for `World > Render Debug` (issue #144), so the shell
// reaches the debug channel and the layer mask without seeing `Renderer`.
//
// The readout below is the section's evidence: a mode name alone cannot show
// that hiding a layer actually removed its draws, and a draw-call delta can.

nonisolated struct RenderDebugControlSnapshot: Equatable {
    let mode: RenderDebugMode
    /// The mask the user set.
    let layers: RenderLayer
    /// The mask after the subsystem enables were folded in
    /// (`RenderLayerPolicy`). Differs from `layers` when a layer is checked
    /// here but switched off by its own panel section.
    let effectiveLayers: RenderLayer
    let stats: SceneDrawStats
    let shadowStats: ShadowDrawStats
}

@MainActor
protocol RenderDebugControlProviding: AnyObject {
    var renderDebugMode: RenderDebugMode { get set }
    var renderDebugLayers: RenderLayer { get set }
    var renderDebugSnapshot: RenderDebugControlSnapshot { get }
}

/// Readout text for the Render Debug section, kept apart from AppKit so the
/// wording is unit-testable.
nonisolated enum RenderDebugReadout {
    static func modeText(for snapshot: RenderDebugControlSnapshot) -> String {
        "View: \(snapshot.mode.title)"
    }

    /// Names the isolated layer when there is one, otherwise lists what is
    /// hidden — "all layers" is the answer a default session should read.
    static func layerText(for snapshot: RenderDebugControlSnapshot) -> String {
        if let soloed = snapshot.layers.soloedLayer {
            return "Layers: solo \(soloed.title)"
        }
        let hidden = RenderLayer.ordered.filter { !snapshot.layers.contains($0) }
        guard !hidden.isEmpty else { return "Layers: all layers" }
        return "Layers: hiding " + hidden.map(\.title).joined(separator: ", ")
    }

    /// Layers the mask allows but a subsystem enable has switched off anyway.
    static func suppressedText(for snapshot: RenderDebugControlSnapshot) -> String? {
        let suppressed = RenderLayer.ordered.filter {
            snapshot.layers.contains($0) && !snapshot.effectiveLayers.contains($0)
        }
        guard !suppressed.isEmpty else { return nil }
        return "Also off by their own controls: "
            + suppressed.map(\.title).joined(separator: ", ")
    }

    static func drawText(for snapshot: RenderDebugControlSnapshot) -> String {
        """
        Scene: \(snapshot.stats.drawCalls) draws, \
        \(snapshot.stats.drawnInstances) instances
        Shadow: \(snapshot.shadowStats.drawCalls) draws, \
        \(snapshot.shadowStats.drawnInstances) casters
        """
    }

    static func text(for snapshot: RenderDebugControlSnapshot) -> String {
        [
            modeText(for: snapshot),
            layerText(for: snapshot),
            suppressedText(for: snapshot),
            drawText(for: snapshot)
        ].compactMap(\.self).joined(separator: "\n")
    }
}
