// Base class for one control group inside an inspector panel (issue #98). A
// section owns its controls + an optional live readout; it does not scroll
// (the parent InspectorPanelViewController scrolls). Because a section is fully
// self-contained — its own sync/readout/ticker — it can later be promoted to a
// standalone sidebar destination without change (see docs/tools/app-ui.md).

import AppKit

class PanelSectionViewController: NSViewController, InspectorPanel {
    private let ticker = InspectionTicker()

    /// Hands first-responder back to the game view after a control interaction.
    /// Set by the owning panel from its live-renderer bridge.
    var refocusAction: (() -> Void)?

    /// Title shown in the collapsible section header.
    var sectionTitle: String {
        ""
    }

    /// Stable id for the section header accessibility identifier.
    var sectionIdentifier: String {
        ""
    }

    override func loadView() {
        let controls = makeContentViews()
        let stack = NSStackView(views: controls)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PanelMetrics.rowSpacing
        for control in controls {
            control.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        view = stack
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        syncControls()
        refreshReadout()
    }

    // MARK: Overridable hooks

    /// The section's controls, top to bottom. No leading caption — the
    /// collapsible header supplies the title.
    func makeContentViews() -> [NSView] {
        []
    }

    /// Pulls live provider state onto the controls.
    func syncControls() {}

    /// Refreshes the live readout label(s). Called on the ticker.
    func refreshReadout() {}

    // MARK: InspectorPanel

    func startInspecting() {
        syncControls()
        refreshReadout()
        ticker.start { [weak self] in self?.refreshReadout() }
    }

    func stopInspecting() {
        ticker.stop()
    }

    /// Refreshes the readout and returns focus to the game view. Pass
    /// `refocusOnMouseUpOnly` for continuous sliders so focus is handed back
    /// only when the drag ends, not on every intermediate value.
    func finishInteraction(refocusOnMouseUpOnly: Bool = false) {
        refreshReadout()
        if refocusOnMouseUpOnly, NSApp.currentEvent?.type != .leftMouseUp {
            return
        }
        refocusAction?()
    }
}
