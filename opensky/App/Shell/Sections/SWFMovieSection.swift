// Developer > UI Lab > SWF movie section (M8.2.5): picks a vanilla movie from
// the located install, toggles the SWF layer, and shows the movie's frame-1 tag
// tally beside the last frame's draw stats. Self-contained
// PanelSectionViewController hosted by the direct-content UI Lab panel; talks to
// the engine only through SWFLabControlProviding.

import AppKit

final class SWFMovieSection: PanelSectionViewController {
    /// First popup entry: clears the assigned movie (`setSWFMovie(nil)`).
    static let noMovieTitle = "None"

    weak var provider: (any SWFLabControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            reloadMovies()
            syncControls()
            refreshReadout()
        }
    }

    let movieControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let layerEnabledControl = NSButton(
        checkboxWithTitle: "Draw SWF layer", target: nil, action: nil
    )
    private let statsLabel = PanelComponents.statsLabel(identifier: "SWFMovieStatsLabel")

    /// Movie paths behind the popup entries, popup-item order. Empty entry 0
    /// (the "None" row) is represented by nil.
    private var moviePaths: [String?] = [nil]

    override var sectionTitle: String {
        "SWF movie"
    }

    override var sectionIdentifier: String {
        "swfMovie"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any SWFLabControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.swfLabSnapshot.selectedPath != nil
            || !provider.swfLayerEnabled
    }

    static func resetToDefaults(provider: (any SWFLabControlProviding)?) {
        provider?.selectSWFMovie(path: nil)
        provider?.swfLayerEnabled = true
    }

    /// Current readout text; the verification-surface tests read it directly.
    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            movieControl,
            target: self,
            action: #selector(movieChanged),
            identifier: "SWFMovieControl",
            width: PanelMetrics.contentWidth
        )
        layerEnabledControl.target = self
        layerEnabledControl.action = #selector(layerEnabledChanged)
        layerEnabledControl.setAccessibilityIdentifier("SWFLayerEnabledControl")
        reloadMovies()
        return [
            PanelComponents.note(
                "Renders a vanilla movie's frame-1 display list over the world "
                    + "frame. Most menus hide frame-1 content behind a zero-alpha "
                    + "CXFORM and stay blank until ActionScript runs."
            ),
            movieControl,
            layerEnabledControl,
            statsLabel
        ]
    }

    /// Rebuilds the popup from the provider's movie list. Without an install
    /// the list is empty and only the "None" entry remains, so the control
    /// degrades instead of vanishing.
    private func reloadMovies() {
        let paths = provider?.swfMoviePaths ?? []
        moviePaths = [nil] + paths.map(Optional.some)
        movieControl.removeAllItems()
        movieControl.addItem(withTitle: Self.noMovieTitle)
        for path in paths {
            movieControl.addItem(withTitle: SWFLabReadout.displayName(for: path))
        }
    }

    override func syncControls() {
        let available = provider != nil
        movieControl.isEnabled = available && moviePaths.count > 1
        layerEnabledControl.isEnabled = available
        layerEnabledControl.state = provider?.swfLayerEnabled == true ? .on : .off
        let selected = provider?.swfLabSnapshot.selectedPath
        let index = moviePaths.firstIndex { $0 == selected } ?? 0
        movieControl.selectItem(at: index)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "SWF state unavailable."
            return
        }
        statsLabel.stringValue = SWFLabReadout.text(for: provider.swfLabSnapshot)
    }

    @objc private func movieChanged() {
        let index = movieControl.indexOfSelectedItem
        guard moviePaths.indices.contains(index) else { return }
        provider?.selectSWFMovie(path: moviePaths[index])
        finishInteraction()
    }

    @objc private func layerEnabledChanged() {
        provider?.swfLayerEnabled = layerEnabledControl.state == .on
        finishInteraction()
    }
}
