// Base class for a full sidebar destination panel (issue #98): a vertically
// scrolling column of either collapsible sections (Environment) or direct
// controls (UI Lab). Replaces the per-panel hand-computed content height + the
// scroll-to-top hack with a flipped auto-layout document that starts at the top.

import AppKit

class InspectorPanelViewController: NSViewController, InspectorPanel {
    private let ticker = InspectionTicker()

    /// Child sections in display order (empty for a direct-content panel).
    private(set) var sections: [PanelSectionViewController] = []

    /// Hands first-responder back to the game view after a control interaction;
    /// fanned out to every section so each control can restore game focus.
    var refocusAction: (() -> Void)? {
        didSet {
            for section in sections {
                section.refocusAction = refocusAction
            }
        }
    }

    // MARK: Overridable hooks

    /// Sections composing this panel. Default: none (direct-content panel).
    func makeSections() -> [PanelSectionViewController] {
        []
    }

    /// Controls for a direct-content panel (used only when `makeSections` empty).
    func makeContentViews() -> [NSView] {
        []
    }

    /// Direct-content panels: pull provider state onto controls.
    func syncControls() {}

    /// Direct-content panels: refresh the live readout on the ticker.
    func refreshReadout() {}

    override func loadView() {
        sections = makeSections()
        for section in sections {
            addChild(section)
            section.refocusAction = refocusAction
        }

        let column: [NSView] = sections.isEmpty
            ? makeContentViews()
            : sections.map {
                CollapsibleSectionView(
                    title: $0.sectionTitle,
                    identifier: $0.sectionIdentifier,
                    content: $0.view
                )
            }

        let stack = NSStackView(views: column)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PanelMetrics.rowSpacing
        stack.edgeInsets = NSEdgeInsets(
            top: PanelMetrics.edgeInset,
            left: PanelMetrics.edgeInset,
            bottom: PanelMetrics.edgeInset,
            right: PanelMetrics.edgeInset
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        for control in column {
            control.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        let scroll = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: PanelMetrics.panelWidth, height: 700)
        )
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document

        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.widthAnchor.constraint(equalTo: clip.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        view = scroll
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        syncControls()
        refreshReadout()
    }

    // MARK: InspectorPanel

    func startInspecting() {
        syncControls()
        refreshReadout()
        if sections.isEmpty {
            ticker.start { [weak self] in self?.refreshReadout() }
        } else {
            for section in sections {
                section.startInspecting()
            }
        }
    }

    func stopInspecting() {
        ticker.stop()
        for section in sections {
            section.stopInspecting()
        }
    }

    /// Direct-content panels: refresh + return focus to the game view.
    func finishInteraction(refocusOnMouseUpOnly: Bool = false) {
        refreshReadout()
        if refocusOnMouseUpOnly, NSApp.currentEvent?.type != .leftMouseUp {
            return
        }
        refocusAction?()
    }
}

/// Flipped document container so scroll content anchors to the top-left.
private final class FlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}
