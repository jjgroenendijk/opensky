// Narrow live-renderer seam consumed by the Developer > UI Lab SWF movie
// selector (M8.2.5). The section picks a vanilla movie from the located
// install, toggles the SWF layer, and mirrors the movie's frame-1 tag tally
// plus the last frame's draw stats — only through this bridge, never renderer
// or loader internals. The readout text is built by `SWFLabReadout` so the
// formatting is device-free and unit-testable without AppKit.

/// UI Lab SWF readout: what is selected, what decoding produced, and what the
/// last encoded frame drew.
nonisolated struct SWFLabControlSnapshot: Equatable {
    /// Archive path of the assigned movie (`interface\console.swf`); nil when
    /// no movie is assigned.
    let selectedPath: String?
    /// Mirror of `Renderer.swfEnabled`.
    let layerEnabled: Bool
    /// Message from the last failed load or GPU package build; nil when the
    /// last selection succeeded. A failure never crashes the panel.
    let loadError: String?
    /// Frame-1 tag accounting from the decoded movie; nil when none is loaded.
    let tally: SWFMovieTally?
    /// Font names the movie references that fontconfig could not resolve.
    let unresolvedFontNames: [String]
    /// `Renderer.lastSWFDrawStats` from the most recently encoded frame.
    let drawStats: SWFDrawStats
    /// True when an install was located and its movies could be enumerated.
    let installLoaded: Bool
}

@MainActor
protocol SWFLabControlProviding: AnyObject {
    /// Sorted `interface\*.swf` paths from the located install; empty when no
    /// install is present, which the section degrades to gracefully.
    var swfMoviePaths: [String] { get }

    /// Assigns the movie at `path` to the renderer, or clears it with nil.
    /// Never throws: a decode or package-build failure lands in the snapshot's
    /// `loadError` instead, because a malformed movie must not take the app
    /// down (AGENTS.md "Reverse-engineering discipline").
    func selectSWFMovie(path: String?)

    var swfLayerEnabled: Bool { get set }
    var swfLabSnapshot: SWFLabControlSnapshot { get }
}

/// Builds the UI Lab SWF readout text from a snapshot. Pure formatting, kept
/// out of the section view controller so the wording is asserted directly.
nonisolated enum SWFLabReadout {
    /// Display name for a movie path (`interface\console.swf` -> `console.swf`).
    static func displayName(for path: String) -> String {
        path.split(separator: "\\").last.map(String.init) ?? path
    }

    static func text(for snapshot: SWFLabControlSnapshot) -> String {
        var lines = [
            movieLine(snapshot), tagLine(snapshot), spriteLine(snapshot),
            actionLine(snapshot)
        ]
        let stats = snapshot.drawStats
        lines.append(
            "Draws: \(stats.drawCalls) · triangles \(stats.triangles) · "
                + "glyphs \(stats.glyphs) · masks \(stats.maskDraws) · "
                + "skipped \(stats.skippedItems)"
        )
        lines.append(fontLine(snapshot))
        if let error = snapshot.loadError {
            lines.append("[ERROR] \(error)")
        }
        return lines.joined(separator: "\n")
    }

    private static func movieLine(_ snapshot: SWFLabControlSnapshot) -> String {
        let movie = snapshot.selectedPath.map(displayName(for:))
            ?? (snapshot.installLoaded ? "none" : "no game data")
        return "Movie: \(movie) · layer \(snapshot.layerEnabled ? "on" : "off")"
    }

    private static func tagLine(_ snapshot: SWFLabControlSnapshot) -> String {
        guard let tally = snapshot.tally else {
            return "Tags: no movie loaded"
        }
        return "Tags: place \(tally.placeObject)/\(tally.placeObject2)/"
            + "\(tally.placeObject3) · moves \(tally.moves) · "
            + "removes \(tally.removals) · frames \(tally.showFrames)"
    }

    private static func spriteLine(_ snapshot: SWFLabControlSnapshot) -> String {
        guard let tally = snapshot.tally else {
            return "Sprites: none"
        }
        return "Sprites: \(tally.sprites) · clips \(tally.clipLayers) · "
            + "filters \(tally.filters) · blends \(tally.blendModes) · "
            + "actions \(tally.clipActions) · dangling \(tally.danglingPlacements)"
    }

    /// Whole-movie ActionScript inventory (milestone 8.3.1). Nothing executes
    /// yet, so this reports what was framed, not what ran.
    private static func actionLine(_ snapshot: SWFLabControlSnapshot) -> String {
        guard let tally = snapshot.tally else {
            return "Actions: no movie loaded"
        }
        return "Actions: \(tally.actionBlocks) blocks · "
            + "\(tally.actionRecords) records · "
            + "unknown \(tally.unknownActionOpcodes) · "
            + "undecoded \(tally.undecodedActionOpcodes) · "
            + "warnings \(tally.actionWarnings)"
    }

    private static func fontLine(_ snapshot: SWFLabControlSnapshot) -> String {
        let names = snapshot.unresolvedFontNames
        guard !names.isEmpty else {
            return "Unresolved fonts: none"
        }
        return "Unresolved fonts: \(names.count) (\(names.prefix(3).joined(separator: ", ")))"
    }
}
