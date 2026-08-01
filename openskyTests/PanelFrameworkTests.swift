// Coverage for the shared inspector-panel framework (issue #98): the readout
// ticker's start/stop lifecycle, collapsible-section reveal + persistence, and
// the scrolling panel document starting at the top.

import AppKit
@testable import opensky
import Testing

private final class DirectPanel: InspectorPanelViewController {
    let marker = NSTextField(labelWithString: "marker")

    override func makeContentViews() -> [NSView] {
        marker.setAccessibilityIdentifier("DirectPanelMarker")
        return [marker]
    }
}

/// A section with enough content that a failure to collapse is unmistakable.
private final class TallSection: PanelSectionViewController {
    private let id: String

    init(id: String) {
        self.id = id
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var sectionTitle: String {
        "Tall \(id)"
    }

    override var sectionIdentifier: String {
        id
    }

    override func makeContentViews() -> [NSView] {
        (0 ..< 6).map { NSTextField(labelWithString: "row \($0)") }
    }
}

private final class TwoSectionPanel: InspectorPanelViewController {
    override func makeSections() -> [PanelSectionViewController] {
        [TallSection(id: "test-first"), TallSection(id: "test-second")]
    }
}

private final class MutableSection: PanelSectionViewController {
    var overridden = true
    var resetCount = 0
    var syncCount = 0
    var readoutCount = 0

    override var sectionTitle: String {
        "Mutable"
    }

    override var sectionIdentifier: String {
        "test-mutable"
    }

    override var isOverridden: Bool {
        overridden
    }

    override func makeContentViews() -> [NSView] {
        [NSTextField(labelWithString: "mutable")]
    }

    override func syncControls() {
        syncCount += 1
    }

    override func refreshReadout() {
        readoutCount += 1
    }

    override func resetToDefaults() {
        resetCount += 1
        overridden = false
    }
}

private final class MutablePanel: InspectorPanelViewController {
    let mutableSection = MutableSection()

    override func makeSections() -> [PanelSectionViewController] {
        [mutableSection]
    }
}

struct PanelFrameworkTests {
    @Test @MainActor
    func sectionOverrideHooksHaveSafeDefaults() {
        let section = PanelSectionViewController()
        #expect(!section.isOverridden)
        section.resetToDefaults()
        #expect(!section.isOverridden)
    }

    @Test @MainActor
    func tickerStartsIdempotentlyAndStops() {
        let ticker = InspectionTicker()
        #expect(!ticker.isActive)
        ticker.start {}
        #expect(ticker.isActive)
        ticker.start {} // second start must not schedule a second timer
        #expect(ticker.isActive)
        ticker.stop()
        #expect(!ticker.isActive)
    }

    @Test @MainActor
    func collapsibleSectionTogglesContent() {
        let content = NSView()
        let section = CollapsibleSectionView(
            title: "Grass", identifier: "test-toggle", content: content
        )
        defer { UserDefaults.standard.removeObject(forKey: "panelSection.expanded.test-toggle") }

        #expect(section.isExpanded) // default expanded
        #expect(!content.isHidden)
        section.setExpanded(false)
        #expect(!section.isExpanded)
        #expect(content.isHidden)
        section.setExpanded(true)
        #expect(!content.isHidden)
    }

    /// The invariant that matters for panel density: a collapsed section must
    /// occupy its header and nothing more. Before this was asserted, collapsing
    /// only set `isHidden` on a non-arranged subview, so the section kept its
    /// full expanded height and the column reserved a blank block for it.
    @Test @MainActor
    func collapsedSectionOccupiesOnlyItsHeader() throws {
        let panel = TwoSectionPanel()
        let scrollView = try #require(panel.view as? NSScrollView)
        defer {
            for id in ["test-first", "test-second"] {
                UserDefaults.standard.removeObject(forKey: "panelSection.expanded.\(id)")
            }
        }
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        let sections = try Self.collapsibleSections(in: #require(scrollView.documentView))
        #expect(sections.count == 2)
        let first = try #require(sections.first)
        let header = try #require(first.arrangedSubviews.first)
        let expandedHeight = first.frame.height
        let expandedDocumentHeight = try #require(scrollView.documentView).frame.height
        #expect(expandedHeight > header.frame.height)

        first.setExpanded(false)
        panel.view.layoutSubtreeIfNeeded()

        #expect(
            abs(first.frame.height - header.frame.height) < 0.5,
            "collapsed section is \(first.frame.height) tall, header is \(header.frame.height)"
        )
        let collapsedDocument = try #require(scrollView.documentView).frame.height
        #expect(
            collapsedDocument < expandedDocumentHeight,
            "document did not shrink: \(expandedDocumentHeight) -> \(collapsedDocument)"
        )

        // Re-expanding restores the original geometry.
        first.setExpanded(true)
        panel.view.layoutSubtreeIfNeeded()
        #expect(abs(first.frame.height - expandedHeight) < 0.5)
    }

    /// Every `CollapsibleSectionView` in `root`'s subtree, in layout order.
    @MainActor
    private static func collapsibleSections(in root: NSView) -> [CollapsibleSectionView] {
        if let section = root as? CollapsibleSectionView {
            return [section]
        }
        return root.subviews.flatMap { collapsibleSections(in: $0) }
    }

    @Test @MainActor
    func collapsibleSectionPersistsCollapsedState() {
        let id = "test-persist"
        let key = "panelSection.expanded.\(id)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let first = CollapsibleSectionView(title: "Grass", identifier: id, content: NSView())
        first.setExpanded(false)

        // A fresh view with the same id restores the stored collapsed state.
        let restored = CollapsibleSectionView(title: "Grass", identifier: id, content: NSView())
        #expect(!restored.isExpanded)
    }

    @Test @MainActor
    func overrideHeaderTracksStateAndResets() throws {
        let panel = MutablePanel()
        let document = try #require((panel.view as? NSScrollView)?.documentView)
        let indicator = try #require(
            Self.view(
                identified: "PanelSection-test-mutable-OverrideIndicator",
                in: document
            ) as? NSTextField
        )
        let reset = try #require(
            Self.view(
                identified: "PanelSection-test-mutable-ResetControl",
                in: document
            ) as? NSButton
        )

        #expect(!indicator.isHidden)
        #expect(indicator.textColor == Theme.gold)
        #expect(!reset.isHidden)
        let syncBeforeReset = panel.mutableSection.syncCount
        let readoutBeforeReset = panel.mutableSection.readoutCount

        reset.sendAction(reset.action, to: reset.target)

        #expect(panel.mutableSection.resetCount == 1)
        #expect(panel.mutableSection.syncCount > syncBeforeReset)
        #expect(panel.mutableSection.readoutCount > readoutBeforeReset)
        #expect(indicator.isHidden)
        #expect(reset.isHidden)
        #expect(!panel.isOverridden)
    }

    @Test @MainActor
    func panelAggregatesAndResetsChildOverrides() {
        let panel = MutablePanel()
        panel.loadViewIfNeeded()
        #expect(panel.isOverridden)
        panel.resetToDefaults()
        #expect(!panel.isOverridden)
        #expect(panel.mutableSection.resetCount == 1)
    }

    @Test @MainActor
    func directContentPanelScrollDocumentStartsAtTop() throws {
        let panel = DirectPanel()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        let document = try #require(scrollView.documentView)
        #expect(document.frame.height > 0)
        // Flipped document: the first control sits near the top (small y).
        let markerInDoc = panel.marker.convert(panel.marker.bounds, to: document)
        #expect(markerInDoc.minY < 60, "marker not near top: \(markerInDoc)")
        #expect(document.bounds.intersects(markerInDoc))
    }

    @MainActor
    private static func view(identified identifier: String, in root: NSView) -> NSView? {
        if root.accessibilityIdentifier() == identifier {
            return root
        }
        return root.subviews.lazy.compactMap {
            view(identified: identifier, in: $0)
        }.first
    }
}
