// Base class for a full sidebar destination panel (issue #98): a vertically
// scrolling column of either collapsible sections (Environment) or direct
// controls (UI Lab). Replaces the per-panel hand-computed content height + the
// scroll-to-top hack with a flipped auto-layout document that starts at the top.

import AppKit

class InspectorPanelViewController: NSViewController, InspectorPanel {
    private let ticker = InspectionTicker()

    /// Reports aggregate override changes to the shell sidebar.
    var onOverrideStateChange: (() -> Void)?

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

    /// Direct-content panels may override this until their controls become sections.
    var directContentIsOverridden: Bool {
        false
    }

    /// Whether each section runs a ticker of its own, which is what a panel of
    /// unrelated sections wants. A panel whose sections all read one expensive
    /// provider value overrides this to false: the panel then runs the only
    /// ticker and refreshes its sections together through `refreshSections`, so
    /// that value is built once per tick instead of once per section
    /// (issue #556).
    var sectionsTickIndependently: Bool {
        true
    }

    /// Direct-content panels may override this until their controls become sections.
    func resetDirectContentToDefaults() {}

    override func loadView() {
        sections = makeSections()
        for section in sections {
            addChild(section)
            section.refocusAction = refocusAction
        }

        let column: [NSView] = sections.isEmpty
            ? makeContentViews()
            : sections.map(makeCollapsibleSection)

        let stack = NSStackView(views: column)
        stack.orientation = .vertical
        stack.alignment = .leading
        // Sections are the panel's structure, so they get the widest step; a
        // direct-content panel's bare controls are one group and get the
        // narrowest.
        stack.spacing = sections.isEmpty
            ? PanelMetrics.rowSpacing
            : PanelMetrics.sectionSpacing
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

    var isOverridden: Bool {
        directContentIsOverridden || sections.contains(where: \.isOverridden)
    }

    func resetToDefaults() {
        resetDirectContentToDefaults()
        for section in sections {
            section.performResetToDefaults()
        }
        syncControls()
        refreshReadout()
        onOverrideStateChange?()
    }

    func startInspecting() {
        syncControls()
        refreshReadout()
        guard !sections.isEmpty else {
            onOverrideStateChange?()
            ticker.start { [weak self] in
                self?.refreshReadout()
                self?.onOverrideStateChange?()
            }
            return
        }
        for section in sections {
            section.beginInspecting(ticking: sectionsTickIndependently)
        }
        guard !sectionsTickIndependently else { return }
        ticker.start { [weak self] in
            self?.refreshSections()
        }
    }

    /// Refreshes every section from this panel's ticker, for a panel that turned
    /// `sectionsTickIndependently` off. Override to build the shared value the
    /// sections read before calling `super` (issue #556).
    func refreshSections() {
        refreshReadout()
        for section in sections {
            section.refreshReadout()
            section.refreshOverrideState()
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
        onOverrideStateChange?()
        if refocusOnMouseUpOnly, NSApp.currentEvent?.type != .leftMouseUp {
            return
        }
        refocusAction?()
    }

    private func makeCollapsibleSection(
        _ section: PanelSectionViewController
    ) -> CollapsibleSectionView {
        let hosted = CollapsibleSectionView(
            title: section.sectionTitle,
            identifier: section.sectionIdentifier,
            content: section.view,
            isOverridden: section.isOverridden,
            onReset: { [weak section] in section?.performResetToDefaults() }
        )
        section.onOverrideStateChange = { [weak self, weak section, weak hosted] in
            hosted?.setOverridden(section?.isOverridden ?? false)
            self?.onOverrideStateChange?()
        }
        return hosted
    }
}

/// Flipped document container so scroll content anchors to the top-left.
private final class FlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}
